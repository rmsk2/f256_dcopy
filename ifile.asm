MODE_READ = 0
MODE_WRITE = 1
BLOCK_SIZE = 128

EOF_REACHED = 1
EOF_NOT_REACHED = 0

FileState_t .struct cookie, nameAddr, nameLen, dataAddr, dataLen, mode, drive    
    cookie     .byte \cookie
    streamId   .byte ?
    namePtr    .word \nameAddr
    nameLen    .byte \nameLen
    dataPtr    .word \dataAddr
    dataLen    .byte \dataLen
    mode       .byte \mode
    drive      .byte \drive
    eofReached .byte 0
    vtbl       .word ?
.endstruct

Vtbl_t .struct open, close, read, write
    open  .word \open
    close .word \close
    read  .word \read
    write .word \write
.endstruct


openFile .macro name
    #move16Bit \name.vtbl, FILEIO_PTR2
    #load16BitImmediate \name, FILEIO_PTR1
    ldy #FileState_t.streamId
    lda #0
    sta (FILEIO_PTR1), y

    ldy #Vtbl_t.open
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC
    iny
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC+1

    jsr ifile.callVtbl
.endmacro

closeFile .macro name
    #move16Bit \name.vtbl, FILEIO_PTR2
    #load16BitImmediate \name, FILEIO_PTR1

    ldy #Vtbl_t.close
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC
    iny
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC+1

    jsr ifile.callVtbl
.endmacro

readBlock .macro name
    #move16Bit \name.vtbl, FILEIO_PTR2
    #load16BitImmediate \name, FILEIO_PTR1

    ldy #Vtbl_t.read
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC
    iny
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC+1

    jsr ifile.callVtbl
.endmacro

writeBlock .macro name
    #move16Bit \name.vtbl, FILEIO_PTR2
    #load16BitImmediate \name, FILEIO_PTR1    

    ldy #Vtbl_t.write
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC
    iny
    lda (FILEIO_PTR2), y
    sta ifile.VTBLVEC+1

    jsr ifile.callVtbl
.endmacro

ifile .namespace

VTBLVEC .word ?

callVtbl
    jmp (VTBLVEC)

.endnamespace
