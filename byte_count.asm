bcount .namespace

BYTE_COUNT .long 0

reset
    stz BYTE_COUNT
    stz BYTE_COUNT+1
    stz BYTE_COUNT+2
    rts

addBlockLen
    clc
    adc BYTE_COUNT
    sta BYTE_COUNT
    lda BYTE_COUNT+1
    adc #0
    sta BYTE_COUNT+1
    lda BYTE_COUNT+2
    adc #0
    sta BYTE_COUNT+2
    rts

printBytes
    lda BYTE_COUNT+2
    jsr txtio.printByte
    lda BYTE_COUNT+1
    jsr txtio.printByte
    lda BYTE_COUNT
    jsr txtio.printByte        
    rts

.endnamespace