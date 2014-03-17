;; setClock [Time]
;;   Sets the internal clock.
;; Inputs:
;;   HL: Lower word of a 32-bit tick value
;;   DE: Upper word of a 32-bit tick value
;; Outputs:
;;   A: errUnsupported if there is no clock, 0 otherwise
setClock:
#ifndef CLOCK
    ld a, errUnsupported
    or a
    ret
#else
    push af
        ld a, h
        out (0x41), a
        ld a, l
        out (0x42), a
        ld a, d
        out (0x43), a
        ld a, e
        out (0x44), a
        ld a, 1
        out (0x40), a
        ld a, 3
        out (0x40), a
    pop af
    cp a
    ret
#endif
    
;; getClock [Time]
;;   Sets the internal clock.
;; Inputs:
;;   None
;; Outputs:
;;   HL: Lower word of the 32-bit tick value
;;   DE: Upper word of the 32-bit tick value
;;    A: errUnsupported if there is no clock, 0 otherwise
getTimeInTicks:
#ifndef CLOCK
    ld a, errUnsupported
    or a
    ret
#else
    push af
        in a, (0x45)
        ld h, a
        in a, (0x46)
        ld l, a
        in a, (0x47)
        ld d, a
        in a, (0x48)
        ld e, a
    pop af
    cp a
    ret
#endif

;; The number of days before a given month
daysPerMonth:
    .dw 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 ; Normal

daysPerMonthLeap:
    .dw 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366 ; Leap year

;; convertTimeFromTicks [Time]
;;   Convert from ticks to time
;;   Epoch is January 1st, 1997 (Wednesday)
;;   See https://github.com/torvalds/linux/blob/master/kernel/time/timeconv.c
;; Inputs:
;;   HL: Lower word of tick value
;;   DE: Upper word of tick value
;; Outputs:
;;    D: Current second, from 0-59
;;    C: Current minute, from 0-59
;;    B: Current hour, from 0-23
;;    H: Current day, from 0-30
;;    L: Current month, from 1-12
;;   IX: Current year
;;    A: errUnsupported if there is no clock, otherwise the 
;;       day of the week, from 0-6 with 0 being sunday
convertTimeFromTicks:
    ;; Time is in big-endian, have to convert to little-endian 
    ld a, e
    ld c, d
    ld b, l
    ld l, h
    ld h, b
    push hl \ pop ix

    ld de, 60
    call div32by16
    push hl                         ; seconds on stack
        ld de, 60
        call div32by16
        push hl                     ; minutes on stack
            ld de, 24
            call div32by16
            push hl                 ; hours on stack
                push ix \ pop hl
                inc hl \ inc hl \ inc hl
                ld c, 7
                call divHLbyC
                push af             ; day of the week on stack
                    push ix \ pop hl
                    push ix \ pop bc
                    call .getYearFromDays
                    call .getLeapsToDate
                    push bc \ pop hl
                    sbc hl, de
                    inc hl \ inc hl
                    push hl \ pop bc
                    call .getYearFromDays
                    push hl         ; Years on stack
                        ex hl, de
                        push bc \ pop hl
                        call .getMonth
                        ld h, b
                        ld l, a
                    pop ix          ; Years
                pop de              ; Day of the week
                ld a, d
            pop de
            ld b, e                 ; Hours
        pop de
        ld c, e                     ; Minutes
    pop de
    ld d, e                         ; Seconds

    ret

;; Inputs:
;;   HL: The year
;; Outputs: 
;;   DE: The number of leap years (and thus days) since 1997
;; 
;; Does (a - 1)/4 - 3(a - 1)/400 - 484
.getLeapsToDate:
    push hl \ push af \ push bc 
        dec hl
        push hl 
            push hl \ pop de
            ld a, 3
            call DEMulA

            ld a, h
            ld c, l
            ld de, 400
            call divACByDE
            ld d, a
            ld e, c
        pop hl

        push de
            ld a, h
            ld c, l
            ld de, 4
            call divACByDE
            ld h, a
            ld l, c
        pop de

        sbc hl, de
        ld de, 484
        sbc hl, de
        ex hl, de
        
    pop bc \ pop af \ pop hl
    ret

;; Inputs:
;;   HL: The year
;; Outsputs:
;;    A: 1 if it is a leap year, 0 otherwise
;; 
;; Does getLeapsToDate( hl + 1 ) - getLeapsToDate( hl )
.isLeapYear:
    push hl \ push bc \ push de
        call .getLeapsToDate
        push de \ pop bc

        inc hl
        call .getLeapsToDate
        ex de, hl
        sbc hl, bc

        ld a, l
    pop de \ pop bc \ pop hl
    ret

;; Inputs: HL, number of days
;; Outputs: HL, the current year
;;
;; Does hl / 365
.getYearFromDays:
    push af \ push bc \ push de
        ld a, h
        ld c, l
        ld de, 365
        call divACByDE
        ld h, a
        ld l, c

        ld de, 1997
        add hl, de

    pop de \ pop bc \ pop af
    ret

;; Inputs:
;;   HL: the number of days
;;   DE: the year
;; Outputs:
;;    A: The current month
;;    B: The day of the month
.getMonth:
    push ix \ push hl \ push de
        push af \ push bc 
            ld a, h
            ld c, l
            ld de, 365
            call divACByDE
        pop bc \ pop af
        pop de \ push de

        ld ix, daysPerMonth

        ex hl, de
        call .isLeapYear
        cp 1
        jr nz, _  
        ld ix, daysPerMonthLeap
_:
        ld b, 11
        push bc
            ld bc, 22
            add ix, bc
        pop bc
_:
        ld h, (ix+1)
        ld l, (ix)
        ld a, b
        cp 0
        jr z, _
        call cpHLDE
        jr c, _
        dec ix \ dec ix
        dec b
        jr -_ 
_:
        ex hl, de
        sbc hl, de
        ld a, b
        ld b, l
    pop de \ pop hl \ pop ix

    ret

; H: Day
; L: Month
; IX: Year
; B: Hour
; C: Minute
; D: Second
; A: Day of Week
; Output: HLDE: Ticks
convertTimeToTicks:
    ; TODO
    ret
    
; H: Day
; L: Month
; D: Year
; B: Hours
; C: Minutes
; E: Seconds
; A: Day of Week
getTime:
#ifndef CLOCK
    ld a, errUnsupported
    or a
    ret
#else
    call getTimeInTicks
    call convertTimeFromTicks
    cp a
    ret
#endif
