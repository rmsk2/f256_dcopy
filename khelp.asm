; value of event buffer at program start (likely set by `superbasic`)
oldEvent .byte 0, 0
; the new event buffer
myEvent .dstruct kernel.event.event_t


; --------------------------------------------------
; This routine saves the current value of the pointer to the kernel event 
; buffer and sets that pointer to the address of myEvent. This in essence
; disconnects superbasic from the kernel event stream.
;--------------------------------------------------
initEvents
    #move16Bit kernel.args.events, oldEvent
    #load16BitImmediate myEvent, kernel.args.events
    rts


; --------------------------------------------------
; This routine restores the pointer to the kernel event buffer to the value
; encountered at program start. This reconnects superbasic to the kernel
; event stream.
;--------------------------------------------------
restoreEvents
    #move16Bit oldEvent, kernel.args.events
    rts


; waiting for a key press event from the kernel
waitForKey
    ; Peek at the queue to see if anything is pending
    lda kernel.args.events.pending ; Negated count
    bpl waitForKey
    ; Get the next event.
    jsr kernel.NextEvent
    bcs waitForKey
    ; Handle the event
    lda myEvent.type    
    cmp #kernel.event.key.PRESSED
    beq _done
    bra waitForKey
_done
    lda myEvent.key.flags 
    and #myEvent.key.META
    bne waitForKey
    lda myEvent.key.ascii
    rts


DELAY_TEMP .byte 0

setTimerDelay
    sta DELAY_TEMP
    ; get current value of timer
    lda #kernel.args.timer.FRAMES | kernel.args.timer.QUERY
    sta kernel.args.timer.units
    jsr kernel.Clock.SetTimer
    ; carry should be clear here as previous jsr clears it, when no error occurred
    ; make a timer which fires interval units from now
    adc DELAY_TEMP
    sta kernel.args.timer.absolute
    lda #kernel.args.timer.FRAMES
    sta kernel.args.timer.units
    lda TIMER_COOKIE_DELAY
    sta kernel.args.timer.cookie
    ; Create timer
    jsr kernel.Clock.SetTimer
    rts

TIMER_COOKIE_DELAY .byte 2

; Delaying program execution for a number of 1/60 th of a seconds.
; The number is given in the accu when this subroutine is called.
delay60thSeconds
    jsr setTimerDelay
_waitForTimer
    ; Peek at the queue to see if anything is pending
    lda kernel.args.events.pending ; Negated count
    bpl _waitForTimer
    ; Get the next event.
    jsr kernel.NextEvent
    bcs _waitForTimer
    ; Handle the event
    lda myEvent.type    
    cmp #kernel.event.timer.EXPIRED
    bne _waitForTimer
    lda myEvent.timer.cookie
    cmp TIMER_COOKIE_DELAY
    bne _waitForTimer
    rts


exitToBasic
    lda #65
    sta kernel.args.run.block_id
    jsr kernel.RunBlock
    rts


; See chapter 17 of the system manual. Section 'Software reset'
sys64738
    lda #$DE
    sta $D6A2
    lda #$AD
    sta $D6A3
    lda #$80
    sta $D6A0
    lda #00
    sta $D6A0
    rts