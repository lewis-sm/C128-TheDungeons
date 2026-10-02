# vice_driver.ps1
# Drives a running VICE x128 instance from a text file of keypresses, for
# regression-testing The Dungeons without manually navigating the emulator
# each time. Posts key messages directly to the VICE window handle (not
# via SendKeys/global focus), so it can't leak keystrokes into whatever
# window happens to have focus.
#
# Usage:
#   powershell -File scripts\vice_driver.ps1 -Prg game.prg -KeyFile scripts\keys\example.keys -ShotDir scripts\shots
#
#   -Prg <path>       Path to the .prg to autostart. If omitted, attaches to
#                      an already-running x128 process instead of launching one.
#   -KeyFile <path>   Path to a keystroke script (format below).
#   -ShotDir <path>   Directory screenshots are written to (default: alongside
#                      this script, in a "shots" subfolder). Created if missing.
#   -VicePath <path>  Path to x128.exe. Defaults to .\ACME relative lookup
#                      failing over to the VS64DevTools bundled copy.
#   -KeyDelayMs / -StepDelayMs   Timing knobs; defaults are conservative.
#
# KNOWN QUIRK: VICE's GTK3 window sometimes queues posted key messages
# without draining them promptly — especially under load from this same
# script taking lots of screenshots — so a step can appear "stuck" on the
# previous screen for several seconds before every queued keystroke lands
# at once. This isn't lost input, just delayed processing. If a run looks
# stuck: raise -StepDelayMs, reduce how many SHOT lines you take in a row,
# or just wait longer before trusting a screenshot as the final state.
#
# Keystroke script format (one instruction per line):
#   # comment                  - ignored
#   (blank line)               - ignored
#   <single character>         - press that key (letter/digit), e.g. "M" "N" "0"
#   ENTER                      - press Return
#   SPACE                      - press Space
#   TYPE <text>                - press each character of <text> in turn
#   WAIT <ms>                  - extra pause, in milliseconds
#   SHOT <name>                - screenshot to <ShotDir>\<name>.png
#
# Example (see scripts\keys\ for ready-made ones):
#   N
#   ENTER
#   F
#   ENTER
#   0
#   ENTER
#   SHOT dungeon-start
#   M
#   E
#   SHOT after-move-east

param(
    [string]$Prg,
    [Parameter(Mandatory=$true)][string]$KeyFile,
    [string]$ShotDir = (Join-Path $PSScriptRoot "shots"),
    [string]$VicePath,
    [int]$KeyDelayMs = 60,
    [int]$StepDelayMs = 1200
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ShotDir)) {
    New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null
}

if (-not $VicePath) {
    $candidates = @(
        (Join-Path $PSScriptRoot "..\ACME\x128.exe"),
        "C:\Users\seanl\AppData\Local\Programs\VS64DevTools\gtk3vice\bin\x128.exe"
    )
    $VicePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $VicePath) { throw "Could not locate x128.exe; pass -VicePath explicitly." }
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ViceDriverWin32 {
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ViceProcess {
    Get-Process x128 -ErrorAction SilentlyContinue | Select-Object -First 1
}

$proc = Get-ViceProcess
if ($Prg) {
    if ($proc) {
        Write-Host "Closing existing x128 instance before relaunching with -Prg..."
        $proc | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }
    Write-Host "Launching $VicePath -autostart `"$Prg`""
    $started = Start-Process -FilePath $VicePath -ArgumentList "-autostart", "`"$Prg`"" -PassThru
    Start-Sleep -Seconds 8
    $proc = Get-Process -Id $started.Id -ErrorAction SilentlyContinue
} elseif (-not $proc) {
    throw "No running x128 process found, and -Prg was not given to launch one."
}

$hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { throw "x128 process found but has no main window handle yet." }
Write-Host "Driving VICE window handle $hwnd (PID $($proc.Id))"

function Send-ViceKey([IntPtr]$hwnd, [int]$vk, [int]$ch) {
    [ViceDriverWin32]::PostMessage($hwnd, 0x0100, [IntPtr]$vk, [IntPtr]0) | Out-Null   # WM_KEYDOWN
    Start-Sleep -Milliseconds $KeyDelayMs
    [ViceDriverWin32]::PostMessage($hwnd, 0x0102, [IntPtr]$ch, [IntPtr]0) | Out-Null   # WM_CHAR
    Start-Sleep -Milliseconds $KeyDelayMs
    [ViceDriverWin32]::PostMessage($hwnd, 0x0101, [IntPtr]$vk, [IntPtr]0) | Out-Null   # WM_KEYUP
    Start-Sleep -Milliseconds $StepDelayMs
}

function Send-ViceChar([IntPtr]$hwnd, [char]$c) {
    $upper = [char]::ToUpper($c)
    if ($upper -eq ' ') {
        Send-ViceKey $hwnd 0x20 0x20
        return
    }
    $vk = [int]$upper
    $ch = [int]$c
    Send-ViceKey $hwnd $vk $ch
}

function Save-ViceScreenshot([string]$name) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $path = Join-Path $ShotDir "$name.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "Screenshot -> $path"
    return $path
}

if (-not (Test-Path $KeyFile)) { throw "Key file not found: $KeyFile" }
$lines = Get-Content $KeyFile

foreach ($rawLine in $lines) {
    $line = $rawLine.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { continue }

    if ($line -eq "ENTER") {
        Send-ViceKey $hwnd 0x0D 0x0D
    } elseif ($line -eq "SPACE") {
        Send-ViceKey $hwnd 0x20 0x20
    } elseif ($line -match "^WAIT\s+(\d+)$") {
        Start-Sleep -Milliseconds ([int]$matches[1])
    } elseif ($line -match "^SHOT\s+(.+)$") {
        Save-ViceScreenshot $matches[1].Trim() | Out-Null
    } elseif ($line -match "^TYPE\s+(.*)$") {
        foreach ($c in $matches[1].ToCharArray()) { Send-ViceChar $hwnd $c }
    } elseif ($line.Length -eq 1) {
        Send-ViceChar $hwnd $line[0]
    } else {
        Write-Warning "Unrecognized key-script line, skipping: $rawLine"
    }
}

Write-Host "Key script complete."
