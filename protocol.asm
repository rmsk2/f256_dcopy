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
    #load16BitImmediate BUFFER_SEND, UART_PTR_SEND
    #load16BitImmediate BUFFER_RECV, UART_PTR_RECV
    #initUart BPS_115200
    rts

Generic_t .struct 
    type .byte ?
.endstruct

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
    generic      .dstruct Generic_t
    dataBlock    .dstruct DataBlock_t
    openBlock    .dstruct OpenBlock_t
    closeBlock   .dstruct CloseBlock_t
    answerBlock  .dstruct AnswerBlock_t
    requestBlock .dstruct RequestBlock_t
.endunion

SerialTable .dstruct Vtbl_t, openConnection, closeConnection, receiveBlock, sendBlock

BUFFER_SEND .dunion Blocks_t
BUFFER_RECV .dunion Blocks_t

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
    sta BUFFER_SEND.generic.type
    lda #len(BUFFER_SEND.\blockStruct)
    sta UART_LEN_SEND
    #calcCRCImmediate BUFFER_SEND, len(BUFFER_SEND.\blockStruct)-2, BUFFER_SEND.\blockStruct.checkSum
    jsr transactBlockSendCall
.endmacro

transactBlockSend .macro blockStruct, blockType
    lda #\blockType
    sta BUFFER_SEND.generic.type
    lda #len(BUFFER_SEND.\blockStruct)
    sta UART_LEN_SEND
    #calcCRCImmediate BUFFER_SEND, len(BUFFER_SEND.\blockStruct)-2, BUFFER_SEND.\blockStruct.checkSum
    jsr transactBlockSendCall
.endmacro

transactBlockSendCall
    jsr uart.sendFrame
    bcs _doneError
    jsr uart.receiveFrame
    bcs _doneError
    #verifyCRCImmediate BUFFER_RECV, len(BUFFER_RECV.answerBlock)-2, BUFFER_RECV.answerBlock.checkSum
    bcs _doneError
    lda UART_LEN_RECV
    cmp #len(BUFFER_RECV.answerBlock)
    bne _doneError
    lda BUFFER_RECV.generic.type
    cmp #BLOCK_T_ANSWER
    bne _doneError
    lda BUFFER_RECV.answerBlock.result
    cmp #RESULT_OK
    beq _doneOK
    cmp #RESULT_RETRANSMIT
    bne _doneError
    bra transactBlockSendCall
_doneOK
    clc
    rts
_doneError
    sec
    rts

openConnection
    ; Copy file name of file struct to Buffer.openBlock
    #moveWord FileState_t, namePtr, TEMP_PTR
    #load16BitImmediate BUFFER_SEND.openBlock.fileName, TEMP_PTR2
    #loadByte FileState_t, nameLen
    sta BUFFER_SEND.openBlock.nameLen                   ; store file name length in open struct
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
_sendAgain
    sta BUFFER_SEND.generic.type
    lda #len(BUFFER_SEND.requestBlock)
    sta UART_LEN_SEND
    #calcCRCImmediate BUFFER_SEND, len(BUFFER_SEND.requestBlock)-2, BUFFER_SEND.requestBlock.checkSum
    jsr uart.sendFrame
    bcs _doneError
    jsr uart.receiveFrame
    bcs _doneError
    #verifyCRCImmediate BUFFER_RECV, len(BUFFER_RECV.dataBlock)-2, BUFFER_RECV.dataBlock.checkSum
    bcc _processBlock
    lda #BLOCK_T_BLOCK_RETRANS
    bra _sendAgain
_processBlock
    lda BUFFER_RECV.generic.type
    cmp #BLOCK_T_DATA
    beq _copyData
    cmp #BLOCK_T_DATA_LAST
    beq _copyData
    sec
    jmp _doneError
_copyData
    #load16BitImmediate BUFFER_RECV.dataBlock.data, TEMP_PTR
    #moveWord FileState_t, dataPtr, TEMP_PTR2
    lda BUFFER_RECV.dataBlock.dataLen
    jsr memcpyCall
    lda #BLOCK_SIZE
    sec
    sbc BUFFER_RECV.dataBlock.dataLen
    ldy #FileState_t.dataLen
    sta (FILEIO_PTR1), y
    lda BUFFER_RECV.dataBlock.blockType
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


sendBlock
    #moveWord FileState_t, dataPtr, TEMP_PTR
    #load16BitImmediate BUFFER_SEND.dataBlock.data, TEMP_PTR2
    #loadByte FileState_t, dataLen
    sta BUFFER_SEND.dataBlock.dataLen
    jsr memcpyCall
    #transactBlockSend dataBlock, BLOCK_T_DATA
    rts

.endnamespace