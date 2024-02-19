setParams .macro  t, name, nameLenAddr, driveAddr
    #load16BitImmediate \name, file.\t.namePtr
    lda \nameLenAddr
    sta file.\t.nameLen
    lda \driveAddr
    sta file.\t.drive
.endmacro

setInParams .macro name, nameLenAddr, driveAddr
    #setParams FILE_IN, \name, \nameLenAddr, \driveAddr
.endmacro

setOutParams .macro name, nameLenAddr, driveAddr
    #setParams FILE_OUT, \name, \nameLenAddr, \driveAddr
.endmacro

setInFuncs .macro vtbl 
    #load16BitImmediate \vtbl, file.FILE_IN.vtbl
.endmacro

setOutFuncs .macro vtbl 
    #load16BitImmediate \vtbl, file.FILE_OUT.vtbl
.endmacro


file .namespace

VEC_PROGRESS_FUNC .word dummyProg

progVec
    jmp (VEC_PROGRESS_FUNC)

dummyProg
    rts

NAME_DUMMY .text "sjdkfhZF65.tst"

FILE_IN .dstruct FileState_t, 76, NAME_DUMMY, len(NAME_DUMMY), BUFFER, BLOCK_SIZE, MODE_READ, 1
FILE_OUT .dstruct FileState_t, 176, NAME_DUMMY, len(NAME_DUMMY), BUFFER, BLOCK_SIZE, MODE_WRITE, 0

BUFFER .fill BLOCK_SIZE
COPY_DONE .byte 0
; carry set when error occured
copy
    stz COPY_DONE                                   ; clear flag that signals the end of the copy operation                      
    ; reset EOF marker in input file desriptor
    lda #EOF_NOT_REACHED
    sta FILE_IN.eofReached

    #openFile FILE_IN                               ; open input file for read
    bcc _fInOpen
    rts
_fInOpen
    #openFile FILE_OUT                              ; open output file for write
    bcc _readBlock
    ; opening of output file failed
    #closeFile FILE_IN
    sec
    rts
_readBlock
    #load16BitImmediate BUFFER, FILE_IN.dataPtr     ; reset data buffer to start address
    ; set length of data to read to BLOCK_SIZE
    lda #BLOCK_SIZE
    sta FILE_IN.dataLen
    ; read block
    #readBlock FILE_IN
    bcc _writeBlock                                 ; no error occured, full block was read
    ; error when reading block
    ; check for EOF reached
    lda FILE_IN.eofReached
    beq _errorClose                                 ; we had an error but EOF not reached => failure
    inc COPY_DONE                                   ; we have read last block => end loop
_writeBlock    
    ; calculate number of bytes read
    lda #BLOCK_SIZE
    sec
    sbc FILE_IN.dataLen
    beq _nextBlock                                  ; no data to write
    sta FILE_OUT.dataLen
    #load16BitImmediate BUFFER, FILE_OUT.dataPtr    ; reset data buffer start address
    #writeBlock FILE_OUT
    bcc _nextBlock                                  ; block was written without error
    bra _errorClose                                 ; block write was not successfull
_nextBlock
    jsr progVec
    lda COPY_DONE
    beq _readBlock                                  ; EOF was not reached => new loop iteration
    bra _done                                       ; EOF was reached => we are done
_errorClose
    #closeFile FILE_IN
    #closeFile FILE_OUT
    sec
    rts    
_done
    #closeFile FILE_IN
    #closeFile FILE_OUT
    clc
    rts


.endnamespace