.include "uart.asm"

BLOCK_T_DATA          = 1
BLOCK_T_DATA_LAST     = 2
BLOCK_T_OPEN_SEND     = 3
BLOCK_T_OPEN_RECEIVE  = 4
BLOCK_T_CLOSE         = 5
BLOCK_T_BLOCK_NEXT    = 6
BLOCK_T_BLOCK_RETRANS = 7
BLOCK_T_ANSWER        = 8

RESULT_OK = 0
RESULT_RETRANSMIT = 1
RESULT_FAILURE = 2

protocol .namespace

init
    #load16BitImmediate Buffer, UART_PTR
    #initUart BPS_115200
    rts

DataBlock_t .struct
    blockType .byte BLOCK_T_DATA
    dataLen   .byte ?
    data      .fill BLOCK_SIZE
    checkSum  .word ?
.endstruct

OpenBlock_t .struct 
    blockType .byte BLOCK_T_OPEN_SEND
    nameLen   .byte ?
    fileName  .fill BLOCK_SIZE
    checkSum  .word ?
.endstruct

CloseBlock_t .struct
    blockType .byte BLOCK_T_CLOSE
    checkSum  .word ?
.endstruct

RequestBlock_t .struct
    blockType .byte ?
    checkSum  .word ?
.endstruct

AnswerBlock_t .struct
    blockType  .byte BLOCK_T_ANSWER
    result     .byte ?
    checkSum   .word ?
.endstruct

Blocks_t .union 
    dataBlock    .dstruct DataBlock_t
    openBlock    .dstruct OpenBlock_t
    closeBlock   .dstruct CloseBlock_t
    answerBlock  .dstruct AnswerBlock_t
    requestBlock .dstruct RequestBlock_t
.endunion

SerialTable .dstruct Vtbl_t, openConnection, closeConnection, receiveBlock, sendBlock

Buffer .dunion Blocks_t

DATA_LEN .byte 0
memcpyCall
    sta DATA_LEN
    ldy #0
_next
    cpy DATA_LEN
    beq _done
    lda (TEMP_PTR), y
    sta (TEMP_PTR2), y
    iny
    bra _next
_done
    rts


moveWord .macro s, component, addr
    ldy #\s.\component
    lda (FILEIO_PTR1), Y
    sta \addr
    iny
    lda (FILEIO_PTR1), y
    sta \addr+1
.endmacro


loadByte .macro s, component
    ldy #\s.\component
    lda (FILEIO_PTR1), y
.endmacro

transactBlockSendAddr .macro blockStruct, blockType
    lda \blockType
    sta Buffer
    lda #len(Buffer.\blockStruct)
    sta UART_LEN
    jsr transactBlockSendCall
.endmacro

transactBlockSend .macro blockStruct, blockType
    lda #\blockType
    sta Buffer
    lda #len(Buffer.\blockStruct)
    sta UART_LEN
    jsr transactBlockSendCall
.endmacro

transactBlockSendCall
    jsr uart.sendFrame
    bcs _doneError
    jsr uart.receiveFrame
    bcs _doneError
    lda UART_LEN
    cmp #len(Buffer.answerBlock)
    bne _doneError
    lda Buffer
    cmp #BLOCK_T_ANSWER
    bne _doneError
    lda Buffer.answerBlock.result
    cmp #RESULT_OK
    bne _doneError
    clc
    rts
_doneError
    sec
    rts

openConnection
    ; Copy file name of file struct to Buffer.openBlock
    #moveWord FileState_t, namePtr, TEMP_PTR
    #load16BitImmediate Buffer.openBlock.fileName, TEMP_PTR2
    #loadByte FileState_t, nameLen
    sta Buffer.openBlock.nameLen                        ; store file name length in open struct
    jsr memcpyCall                                      ; copy file name

    #loadByte FileState_t, mode                         ; check open for receive or send
    bne openConnectionSend
    jmp openConnectionReceive
openConnectionSend
    #transactBlockSend openBlock, BLOCK_T_OPEN_SEND
    rts

openConnectionReceive
    #transactBlockSend openBlock, BLOCK_T_OPEN_RECEIVE
    rts

closeConnection
    #transactBlockSend closeBlock, BLOCK_T_CLOSE
    rts

receiveBlock
    lda #BLOCK_T_BLOCK_NEXT
    sta Buffer
    lda #len(Buffer.requestBlock)
    sta UART_LEN
    jsr uart.sendFrame
    bcs _doneError
    jsr uart.receiveFrame
    bcs _doneError
    lda Buffer
    cmp #BLOCK_T_DATA
    beq _copyData
    cmp #BLOCK_T_DATA_LAST
    beq _copyData
    sec
    jmp _doneError
_copyData
    #load16BitImmediate Buffer.dataBlock.data, TEMP_PTR
    #moveWord FileState_t, dataPtr, TEMP_PTR2
    lda Buffer.dataBlock.dataLen
    jsr memcpyCall
    lda #BLOCK_SIZE
    sec
    sbc Buffer.dataBlock.dataLen
    ldy #FileState_t.dataLen
    sta (FILEIO_PTR1), y
    lda Buffer.dataBlock.blockType
    cmp #BLOCK_T_DATA_LAST
    beq _setEof
    lda #EOF_NOT_REACHED
    ldy #FileState_t.eofReached
    sta (FILEIO_PTR1), y
    bra _doneOK
_setEof
    lda #EOF_REACHED
    ldy #FileState_t.eofReached
    sta (FILEIO_PTR1), y
    sec
    bra _doneError
_doneOK
    clc
_doneError    
    rts

DATA_BLOCK_TYPE .byte ?
sendBlock
    lda #BLOCK_T_DATA
    sta DATA_BLOCK_TYPE
    #moveWord FileState_t, dataPtr, TEMP_PTR
    #load16BitImmediate Buffer.dataBlock.data, TEMP_PTR2
    #loadByte FileState_t, dataLen
    sta Buffer.dataBlock.dataLen
    jsr memcpyCall
    jsr file.waslastBlock
    beq _doTransact
    lda #BLOCK_T_DATA_LAST
    sta DATA_BLOCK_TYPE
_doTransact
    #transactBlockSendAddr dataBlock, DATA_BLOCK_TYPE
    rts

.endnamespace