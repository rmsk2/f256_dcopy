; DLAB = 0
; Read

UART_BASE = $D630
REG_RBR = UART_BASE
REG_IER = UART_BASE + 1
REG_IIR = UART_BASE + 2
REG_LCR = UART_BASE + 3
REG_MCR = UART_BASE + 4
REG_LSR = UART_BASE + 5
REG_MSR = UART_BASE + 6
REG_SCR = UART_BASE + 7

; DLAB = 0
; Write

REG_THR = UART_BASE
REG_FCR = UART_BASE + 2

; DLAB = 1
; Read + Write

REG_DLL = UART_BASE
REG_DLM = UART_BASE + 1

DATA_BITS8 = %00000011
STOP_BIT1 = 0
NO_PARITY = 0
BRK_SIG = %01000000
NO_BRK_SIG = %0000000
DLAB = $80

REG_THR_IS_EMPTY = %00100000
REG_THR_EMPTY_IDLE = %01000000
DATA_AVAILABLE = 1
IS_ERROR = %10011110

; These divisors are taken from Table 15.6 of the F256 reference manual
BPS_2400 = 655
BPS_38400 = 40
BPS_57600 = 27
BPS_115200 = 13

setDLAB .macro 
    lda REG_LCR
    ora #$80
    sta REG_LCR
.endmacro

clearDLAB .macro
    lda REG_LCR
    and #%01111111
    sta REG_LCR
.endmacro

initUart .macro baudRate
    ldx #<\baudRate
    ldy #>\baudRate
    jsr uart.callInitUart
.endmacro

uart .namespace


; ******************** BEWARE ********************
; These routines are probably inefficient as they are synchronous and make 
; potentially suboptimal use of the FIFO of the UART. Furthermore they 
; hang when there is no one sending or receiving bytes on the other side.
; ******************** BEWARE ********************

callInitUart
    ; 8 bits, no parity, 1 stop bit
    lda #DATA_BITS8 | STOP_BIT1 | NO_PARITY | NO_BRK_SIG
    sta REG_LCR
    #setDLAB
    ; set baud rate to specified value
    stx REG_DLL
    sty REG_DLM
    #clearDLAB
    rts

; --------------------------------------------------
; This routine sends the byte in the accu over the serial line. It waits 
; indefinitely until the send buffer has room for the byte.
;
; If an error occurred the carry flag is set. It is clear otherwise.
; --------------------------------------------------
sendByte
    pha
    ; wait for REG_THR to become empty
_waitSend
    lda REG_LSR
    and #IS_ERROR
    bne _sndError
    lda REG_LSR
    and #REG_THR_IS_EMPTY
    beq _waitSend

    pla
    sta REG_THR
    clc
    rts
_sndError
    pla
    sec
    rts


; --------------------------------------------------
; This routine reads one byte from the serial port. It waits indefinitely
; until this byte becomes available. It returns the received byte in the accu.
;
; If an error occurred the carry flag is set. It is clear otherwise.
; --------------------------------------------------
receiveByte
    ; wait for data to become available
    lda REG_LSR
    and #IS_ERROR
    bne _recError
    lda REG_LSR
    and #DATA_AVAILABLE
    beq receiveByte

    ; retrieve received byte
    lda REG_RBR
    clc
    rts
_recError
    sec
    rts


; This needs to be a zero page address
FRAME_PTR = UART_PTR
; This can be anywhere in memory
FRAME_LEN = UART_LEN

; --------------------------------------------------
; This macro sets up the parameters necessary to call the routine
; sendFrame.
; --------------------------------------------------
sendBuffer .macro bufferAddr, bufferLen
    #load16BitImmediate \bufferAddr, FRAME_PTR
    lda #\bufferLen
    sta FRAME_LEN
    jsr sendFrame
.endmacro


; --------------------------------------------------
; This macro sets up the parameters necessary to call the routine
; receiveFrame.
; --------------------------------------------------
receiveBuffer .macro bufferAddr
    #load16BitImmediate \bufferAddr, FRAME_PTR
    jsr receiveFrame
.endmacro


; --------------------------------------------------
; This routine sends the data of len FRAME_LEN which is stored at the address
; to which FRAME_PTR points over the serial line. FRAME_LEN can be at most 0xFF.
;
; If an error occurred the carry flag is set. It is clear otherwise.
; --------------------------------------------------
sendFrame
    lda FRAME_LEN
    jsr sendByte
    bcs _sendEnd

    ldy #0
_sendNext
    cpy FRAME_LEN
    bcs _sendDone
    lda (FRAME_PTR), y
    jsr sendByte
    bcs _sendEnd
    iny
    bra _sendNext
_sendDone 
    clc
_sendEnd
    rts


; --------------------------------------------------
; This routine received data over the serial line. The data length is stored in FRAME_LEN.
; The data itself is written to the address to which FRAME_PTR points.
;
; If an error occurred the carry flag is set. It is clear otherwise.
; --------------------------------------------------
receiveFrame
    jsr receiveByte
    bcs _receiveEnd
    sta FRAME_LEN

    ldy #0
_receiveNext
    cpy FRAME_LEN
    bcs _receiveDone
    jsr receiveByte
    bcs _receiveEnd
    sta (FRAME_PTR), y
    iny
    bra _receiveNext
_receiveDone
    clc
_receiveEnd
    rts

.endnamespace