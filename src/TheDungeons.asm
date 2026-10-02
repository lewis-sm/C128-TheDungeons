; ============================================================
; game_harness.asm
; Combines ml_entry_c128.asm, the game's binary data assets, and
; the tokenized C128 port of the_dungeons_c128.bas into one
; loadable PRG. All four phases of the migration order are now
; complete and confirmed working via real gameplay.
;
; CONFIRMED WORKING:
;   - Title, character creation, shop, combat, SID sound, sprites,
;     room rendering, text/digit rendering, disk save/load (full
;     state restoration across sessions).
;   - BASIC loader stub at $1C01: after LOAD"GAME",8,1, user sees
;     "10 SYS 11488" and types RUN to start. Also fixes the
;     RELINK-during-LOAD corruption issue (RELINK now finds a valid
;     1-line BASIC program at $1C01, follows its link to the
;     end-of-program marker, and stops cleanly).
;
; REMAINING OPEN ITEMS (lower priority, see plan doc §11):
;   - TRAP token not in basic_tokens.py: FILE NOT FOUND on load is
;     an unhandled BASIC error (user can restart with RUN).
;   - wall_tiles_1140.bin: real purpose unknown, not in this build.
;     BASIC renders room walls at runtime; no pre-loaded dataset
;     needed based on gameplay testing.
;   - Room exit perspective is by design (not a bug): entry
;     direction becomes "ahead", confirmed matches C64 behaviour.
;
; Build:  acme game_harness.asm
; Run in VICE (x128):
;   LOAD"GAME",8,1
;   RUN
; ============================================================
;
; Build:  acme game_harness.asm
; Test in VICE (x128):
;   LOAD "128DUNGEONS.PRG",8,1
;   SYS 11488                   (decimal for $2CE0 = ML_ENTRY_STUB_START)
;   OR RUN after load
;
; For save/load testing specifically: play until reaching the quit
; prompt (Q), confirm SAVE completes without error, then reload the
; game fresh and choose "restart with a quit file" (Y) at the start
; to confirm LOAD restores the saved state correctly.
; ============================================================

        !cpu 6510
        
;        !to "128DUNGEONS.prg", cbm

        !source "src/include/constants_c128.acme"

        * = GAME_STATE_START
        !binary "src/resources/binary/game_state_1C00.bin"

        * = LOOKUP_TABLE_START
        !binary "src/resources/binary/lookup_table_1260.bin"

        * = SPRITE_POOL_START
        !binary "src/resources/binary/sprites_0840.bin"

        ; --- BASIC loader stub at $1C01 ---
        ; C128's default TXTTAB on a fresh boot is $1C01. After
        ; LOAD"GAME",8,1 (which doesn't change TXTTAB), BASIC sees
        ; this 1-line stub as the current program - so the user just
        ; types RUN, line 10 executes SYS 11488, and ml_entry_c128
        ; handles the rest (sets TXTTAB to BASIC_PROGRAM_START,
        ; injects "RUN" into the keyboard buffer, game starts).
        ; Also fixes the old RELINK-during-LOAD corruption: previously
        ; RELINK started from $1C01 and walked into whatever happened
        ; to be there (zeros or ML code), corrupting it. Now it finds
        ; a valid 1-line BASIC program, follows the link to the
        ; end-of-program marker at $1C0D, and stops cleanly.
        ;
        ; Bytes: link=$1C0D, lineno=10, SYS token=$9E, " 11488", $00,
        ; end-of-program $0000. Total 14 bytes ($1C01-$1C0E).
        * = $1C01
        !byte $0D,$1C     ; link address = $1C0D (end of program)
        !byte $0A,$00     ; line number 10
        !byte $9E,$20     ; SYS token + space
        !text "11488"     ; target address decimal (= ML_ENTRY_STUB_START)
        !byte $00         ; line terminator
        !byte $00,$00     ; end of program marker

        * = CHARSET_COPY_START
        !binary "src/resources/binary/charset_1400.bin"

        !source "src/include/ml_entry_c128.acme"

        * = BASIC_PROGRAM_START
        !binary "src/resources/binary/the_dungeons_c128.bin"
