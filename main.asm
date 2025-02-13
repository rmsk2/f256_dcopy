.include "api.asm"

; target address is $0300
* = $0300
.cpu "w65c02"

jmp main

.include "khelp.asm"
.include "zeropage.asm"
.include "crc.asm"
.include "macros.asm"
.include "ifile.asm"
.include "diskio.asm"
.include "protocol.asm"
.include "filetools.asm"
.include "txtio.asm"
.include "byte_count.asm"

FILE_MAX_LEN = 80 - len(TXT_FROM_DRIVE) - 1

FROM_DRIVE .byte 0
TO_DRIVE   .byte 1
FROM_LEN   .byte ?
TO_LEN     .byte ?

CAPITAL_S = 83
BANNER1 .text "******* dcopy: Drive aware file copy 1.3.3 *******", 13, 13
BANNER2 .text "Enter an empty string to abort and restart", 13
BANNER3 .text "Press RUN/STOP or Control+C to reset to BASIC", 13
BANNER4 .text "If you want to use the serial device, start the server now!", 13, 13
TXT_COPIED .text "Blocks copied: "
TXT_ABORTED .text "Aborted!"

FILE_ALLOWED .text "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:#+~()!&@[]"
DRIVE_ALLOWED .text "012S"
TXT_FROM_DRIVE .text "From drive: "
TXT_TO_DRIVE   .text "To drive  : "
TXT_FROM .text       "From file : "
TXT_TO   .text       "To file   : "

COL = $21
REV_COL = $12

toRev .macro
    lda #REV_COL
    sta CURSOR_STATE.col
.endmacro

noRev .macro
    lda #COL
    sta CURSOR_STATE.col
.endmacro

prepDrive .macro addr
    lda \addr
    sec
    sbc #48
    sta \addr
.endmacro

BLOCK_DONE .byte 0

wheely
    lda BLOCK_DONE
    eor #1
    sta BLOCK_DONE
    bne _done
    lda #46
    jsr txtio.charOut
_done
    rts

setupSystem
    ; setup MMU, this seems to be neccessary when running as a PGZ
    lda #%10110011                         ; set active and edit LUT to three and allow editing
    sta 0
    lda #%00000000                         ; enable io pages and set active page to 0
    sta 1

    ; map BASIC ROM out and RAM in
    lda #4
    sta 8+4
    lda #5
    sta 8+5

    ; set foreground and background color 1 to blue
    lda #$FF
    sta $D804
    sta $D844
    stz $D805
    stz $D845
    stz $D806
    stz $D846

    ; set foreground and background color 2 to white
    lda #$FF
    sta $D808
    sta $D848
    sta $D809
    sta $D849
    sta $D80a
    sta $D84a

    rts

entryAborted
    #noRev
    jsr txtio.newLine
    #printString TXT_ABORTED, len(TXT_ABORTED)
    rts

; --------------------------------------------------
; This routine is the entry point of the program
;--------------------------------------------------
main    
    jsr initEvents
    jsr setupSystem
    jsr crc16.init

    jsr txtio.init
    #setCol COL
    jsr txtio.clear
    jsr txtio.home

    #load16BitImmediate wheely, file.VEC_PROGRESS_FUNC
    
    jsr txtio.newLine

    #printString BANNER1, len(BANNER1)
    #printString BANNER2, len(BANNER2)
    #printString BANNER3, len(BANNER3)
    #printString BANNER4, len(BANNER4)

_nextCopy
    stz BLOCK_DONE
    #printString TXT_FROM_DRIVE, len(TXT_FROM_DRIVE)
    #toRev
    #inputString FROM_DRIVE, 1, DRIVE_ALLOWED, len(DRIVE_ALLOWED)
    bcc _checkz1
    jmp _end
_checkz1
    cmp #0
    bne _next1
    jsr entryAborted
    jmp _cont1
_next1
    #noRev
    jsr txtio.newLine

    #printString TXT_FROM, len(TXT_FROM)
    #toRev
    #inputString FROM_NAME, FILE_MAX_LEN, FILE_ALLOWED, len(FILE_ALLOWED)
    bcc _checkz2
    jmp _end
_checkz2
    cmp #0
    bne _next2
    jsr entryAborted
    jmp _cont1
_next2
    sta FROM_LEN
    #noRev
    jsr txtio.newLine

    #printString TXT_TO_DRIVE, len(TXT_TO_DRIVE)
    #toRev
    #inputString TO_DRIVE, 1, DRIVE_ALLOWED, len(DRIVE_ALLOWED)
    bcc _checkz3
    jmp _end
_checkz3
    cmp #0
    bne _next3
    jsr entryAborted
    jmp _cont1
_next3
    #noRev    
    jsr txtio.newLine

    #printString TXT_TO, len(TXT_TO)
    #toRev
    #inputString TO_NAME, FILE_MAX_LEN, FILE_ALLOWED, len(FILE_ALLOWED)
    bcc _checkz4
    jmp _end
_checkz4
    cmp #0
    bne _next4
    jsr entryAborted
    jmp _cont1
_next4
    sta TO_LEN
    #noRev
    jsr txtio.newLine
    jsr txtio.newLine
    #printString TXT_COPIED, len(TXT_COPIED)

    ; not both drives can be serial device
    lda FROM_DRIVE
    cmp #CAPITAL_S
    bne _drivesOK
    cmp TO_DRIVE
    bne _drivesOK
    jmp _error                                          ; both devices are serial => error
_drivesOK

    ; set funcs for source drive
    lda FROM_DRIVE
    cmp #CAPITAL_S
    bne _setFromNormal
    jsr protocol.init
    #setInFuncs protocol.SerialTable
    bra _nextDrive
_setFromNormal
    #setInFuncs disk.FileTable

    ; set funcs for target drive
_nextDrive
    lda TO_DRIVE
    cmp #CAPITAL_S
    bne _setToNormal
    jsr protocol.init
    #setOutFuncs protocol.SerialTable
    bra _goon1
_setToNormal
    #setOutFuncs disk.FileTable
_goon1

    #prepDrive FROM_DRIVE
    #prepDrive TO_DRIVE

    #setInParams FROM_NAME, FROM_LEN, FROM_DRIVE
    #setOutParams TO_NAME, TO_LEN, TO_DRIVE
    jsr file.copy
    bcs _error

    jsr txtio.newLine    
    #printString OK, len(OK)
    jsr bcount.printBytes
    #printString TXT_BYTES_COPIED, len(TXT_BYTES_COPIED)
_cont1
    jsr txtio.newLine
    jsr txtio.newLine
    jmp _nextCopy
_error
    jsr txtio.newLine
    #printString ERROR, len(ERROR)
    jmp _cont1
_end
    #noRev
    jsr txtio.cursorOn
    lda #6
    jsr delay60thSeconds
    ; jsr restoreEvents
    jmp exitToBasic

    rts

FROM_NAME .fill  FILE_MAX_LEN
TO_NAME .fill FILE_MAX_LEN
BASIC .text "basic"
OK .text "OK: $"
TXT_BYTES_COPIED .text " bytes copied"
ERROR .text "ERROR!", 13
