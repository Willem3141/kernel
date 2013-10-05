; Calculator boot-up code
boot:
    di
    #ifdef COLOR
    ; TODO: We don't need to do this so early on in the boot process
    ; But we do so anyway since we need the backlight working for debugging purposes
    ; Set GPIO config
    ld a, 0xE0
    out (0x39), a
    #endif
    jr _
;; shutdown [System]
;;  Shuts off the device.
;; Notes:
;;  This will never return. Call it with `jp shutdown`
shutdown:
    ; TODO: Crash detection
_:  di

    ld a, 6
    out (4), a ; Memory mode 0

    #ifdef FLASH4MB
    ld a, 3
    out (0x0E), a
    out (0x0F), a
    #endif

    #ifdef CPU15
    ; Set memory mapping
    ; Bank 0: Flash Page 00
    ; Bank 1: Flash Page *
    ; Bank 2: RAM Page 01
    ; Bank 3: RAM Page 00 ; In this order for consistency with TI-83+ and TI-73 mapping
    ld a, 0x81
    out (7), a
    #else
    ; Set memory mapping
    ; Bank 0: Flash Page 00
    ; Bank 1: Flash Page *
    ; Bank 2: RAM Page 01
    ; Bank 3: RAM Page 00
    ld a, 0x41
    out (7), a
    #endif

    ld sp, userMemory ; end of kernel garbage

#ifndef TEST
    call suspendDevice
#endif
;; reboot [System]
;;  Restarts the device.
;; Notes:
;;  This will never return. Call it with `jp reboot`
reboot:
    di

    ld sp, userMemory ; end of kernel garbage

    #ifdef FLASH4MB
    ld a, 3
    out (0x0E), a
    out (0x0F), a
    #endif
    ; Re-map memory
    ld a, 6
    out (4), a
    #ifdef CPU15
    ld a, 0x81
    out (7), a
    #else
    ld a, 0x41
    out (7), a
    #endif

    ; Manipulate protection states
    #ifndef COLOR ; TODO
    #ifdef CPU15 ; TI-83+ SE, TI-84+, TI-84+ SE
        call unlockFlash
            ; Remove RAM Execution Protection
            xor a
            out (0x25), a ; RAM Lower Limit ; out (25), 0
            dec a
            out (0x26), a ; RAM Upper Limit ; out (26), $FF

            ; Remove Flash Execution Protection
            out (0x23), a ; Flash Upper Limit ; out (23), $FF
            out (0x22), a ; Flash Lower Limit ; out (22), $FF
        call lockFlash

        ; Set CPU speed to 15 MHz
        ld a, 1
        out (0x20), a

    #else ; TI-73, TI-83+
        #ifndef TI73 ; RAM does not have protection on the TI-73

        ; Remove RAM/Flash protection
        call unlockFlash
            xor a
            out (5), a
            out (0x16), a

            ld a, 0b000000001
            out (5), a
            xor a
            out (0x16), a

            ld a, 0b000000010
            out (5), a
            xor a
            out (0x16), a

            ld a, 0b000000111
            out (5), a
            xor a
            out (0x16), a
        call lockFlash
        #endif
    #endif
    #endif

    ; Set intterupt mode
    ld a, 0b000001111
    out (3), a

    ; Clear RAM
    ld hl, 0x8000
    ld (hl), 0
    ld de, 0x8001
    ld bc, 0x7FFF
    ldir

    call formatMem

    call debug_blink

    #ifdef COLOR
    jp colorTest
    #else
    ; Initialize LCD
    ld a, 0x05
    call lcdDelay
    out (0x10), a ; X-Increment Mode

    ld a, 0x01
    call lcdDelay
    out (0x10), a ; 8-bit mode

    ld a, 3
    call lcdDelay
    out (0x10), a ; Enable screen

    ld a, 0x17 ; versus 0x13? TIOS uses 0x17, and that's the only value that works (the datasheet says go with 0x13)
    call lcdDelay
    out (0x10), a ; Op-amp control (OPA1) set to max (with DB1 set for some reason)

    ld a, 0xB ; B
    call lcdDelay
    out (0x10), a ; Op-amp control (OPA2) set to max

    ; Different amounts of contrast look better on different models
    #ifdef USB
        ld a, 0xEF
    #else
        #ifdef TI73
            ld a, 0xFB
        #else
            ld a, 0xF4
        #endif
    #endif

    ld (currentContrast), a
    call lcdDelay
    out (0x10), a ; Contrast
    #endif

    ; Set all file handles to unused
    ld hl, fileHandleTable
    ld (hl), 0xFF
    ld de, fileHandleTable + 1
    ld bc, 8 * maxFileStreams
    ldir

    ld a, threadRangeMask ; When the first thread is allocated, this will wrap to 0
    ld (lastThreadId), a

    ; Initialize the font table pointer
    ld hl, kernel_font
    ld (fontTablePtr), hl

#ifdef TEST
    jp testrunner
#endif

    ld de, bootFile
    call fileExists
    ld a, kerr_init_not_found
    jp nz, kernelError
    call launchProgram
    ld h, 0
    call setInitialA

    jp contextSwitch_manual

bootFile:
    .db "/bin/init", 0

colorTest:
; Temporary proof of concept
#ifdef COLOR
    di

    ; Test if the keyboard works right
_:  call flushKeys
    call waitKey
    cp kA
    jr z, .bkOn
    cp kB
    jr z, .bkOff
    cp kC
    jr z, .lcdInit
    cp kD
    jr z, .turnOff
    cp kE
    jr z, .legacyTestA
    cp kF
    jr z, .legacyTestB
    cp kG
    jr z, .legacyTestC
    jr -_
.bkOn:
    in a, (0x3A)
    set 5, a
    out (0x3A), a
    jr -_
.bkOff:
    in a, (0x3A)
    res 5, a
    out (0x3A), a
    jr -_
.lcdInit:
    ; Initialize 84+ CSE LCD
    ; http://wikiti.brandonw.net/index.php?title=84PCSE:LCD_Controller
    call colorLcdOn
    call clearColorLcd
    jr -_
.turnOff:
    im 1 ; interrupt mode 1, for cleanliness
    in a, (3)
    push af
        ld a, 1
        out (3), a ; ON
        ei ; Enable interrupting when ON is pressed
        halt ; and halt
        di
    pop af
    out (3), a
    jp boot
.legacyTestA:
    call setLegacyLcdMode
    jr -_
.legacyTestB:
    ld iy, 0xC000 ; Somewhere inconspicuous
    call clearBuffer
    ld hl, .message
    ld de, 0
    ld b, 0
    call drawStr
    jr -_
.legacyTestC:
    call fastCopy
    jr -_
.message:
    .db "KnightOS 84+ CSE Kernel Test", 0
#endif
; /Temporary
