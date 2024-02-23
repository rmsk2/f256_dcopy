; calcCRC .macro addr, lenAddr, targetAddr
;     #load16BitImmediate \addr, CRC_PTR1
;     lda \lenAddr
;     jsr crc16.calc
;     lda CRC
;     sta \targetAddr
;     lda CRC+1
;     sta \targetAddr+1
; .endmacro

calcCRCImmediate .macro addr, len, targetAddr
    #load16BitImmediate \addr, CRC_PTR1
    lda #\len
    jsr crc16.calc
    lda CRC
    sta \targetAddr
    lda CRC+1
    sta \targetAddr+1
.endmacro

verifyCRCImmediate .macro addr, len, refAddr
    #load16BitImmediate \addr, CRC_PTR1
    lda #\len
    jsr crc16.calc
    lda CRC
    cmp \refAddr
    bne _crcError
    lda CRC+1
    cmp \refAddr+1
    bne _crcError
    clc
    bra _end
_crcError
    sec
_end
.endmacro

crc16 .namespace

; Taken from http://6502.org/source/integers/crc.htm

CRCLO    .fill 256       ; two 256-byte tables for quick lookup
CRCHI    .fill 256       ; (should be page-aligned for speed)

makeCrcTable
    ldx #0          ; x counts from 0 to 255
byteLoop 
    lda #0          ; A contains the low 8 bits of the CRC-16
    stx CRC         ; and crc contains the high 8 bits
    ldy #8          ; Y counts bits in a byte
bitLoop  
    asl
    rol CRC         ; shift CRC left
    bcc noAdd       ; do nothing if no overflow
    eor #$21        ; else add CRC-16 polynomial $1021
    pha             ; save low byte
    lda CRC         ; do high byte
    eor #$10
    sta CRC
    pla             ; restore low byte
noAdd    
    dey
    bne bitLoop     ; do next bit
    sta CRCLO,x     ; save crc into table, low byte
    lda CRC         ; then high byte
    sta CRCHI,x
    inx
    bne byteLoop    ; do next byte
    rts

updCrc
    eor CRC+1       ; quick CRC computation with lookup tables
    tax
    lda CRC
    eor CRCHI,x
    sta CRC+1
    lda CRCLO,x
    sta CRC
    rts

init
    jsr makeCrcTable
    rts

reset 
    lda #$ff
    sta CRC
    sta CRC+1
    rts

DATA_LEN .byte 0
calc
    sta DATA_LEN
    jsr reset
    ldy #0
loop    
    lda (CRC_PTR1), y
    jsr updCrc
    iny
    cpy DATA_LEN
    bne loop
    rts

.endnamespace