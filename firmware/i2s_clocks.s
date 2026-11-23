/*
 * I2S Clock Generation Firmware for Protocol Emulator
 * 
 * Generates I2S clocks using timers:
 * - Timer 0: MCLK = 12.288 MHz (48kHz × 256)
 * - Timer 1: BCLK = 3.072 MHz  (48kHz × 64)
 * - Timer 2: LRCK = 48 kHz
 * 
 * Pin assignments:
 * - Pin 0: MCLK output
 * - Pin 1: BCLK output  
 * - Pin 2: LRCK output
 * - Pin 3: SDATA_OUT (TX)
 * - Pin 4: SDATA_IN (RX)
 * 
 * NCO Formula: f_out = (tuning × 50MHz) / 2^24
 * 
 * MCLK (12.288MHz): tuning = 12288000 × 2^24 / 50000000 = 0x2D1A94
 * BCLK (3.072MHz):  tuning = 3072000 × 2^24 / 50000000 = 0x0B46A5
 * LRCK (48kHz):     tuning = 48000 × 2^24 / 50000000 = 0x00199A
 */

        .org 0x0000

; Timer register offsets (per timer, 16 bytes each)
TIMER_TUNING    = 0x00
TIMER_MODE      = 0x04
TIMER_COMPARE   = 0x08
TIMER_CAPTURE   = 0x0C
TIMER_COUNTER   = 0x0C
TIMER_PREV      = 0x0E
TIMER_EVENT     = 0x10

; Pin Matrix registers
PIN_DIR         = 0x00
PIN_OUT         = 0x01
PIN_IN          = 0x02
PIN_OE          = 0x03
PIN_RISE        = 0x04
PIN_FALL        = 0x05
PIN_SEL         = 0x06
PIN_CONFIG      = 0x07

; Timer modes
MODE_NCO        = 0x0001
MODE_PWM        = 0x0002
MODE_CAPTURE    = 0x0004
MODE_EVENT      = 0x0008

; Pin config bits
CFG_TIMER       = 0x01
CFG_CPU         = 0x02
CFG_PULLUP      = 0x04
CFG_PULLDOWN    = 0x08

; NCO tuning words (50MHz clock)
MCLK_TUNING_LOW  = 0xA94   ; 0x2D1A94 low 16 bits
MCLK_TUNING_MID  = 0xD1A   ; mid 8 bits (shifted)
MCLK_TUNING_HIGH = 0x02    ; high 8 bits

BCLK_TUNING_LOW  = 0x46A5
BCLK_TUNING_MID  = 0x00B4
BCLK_TUNING_HIGH = 0x00

LRCK_TUNING_LOW  = 0x199A
LRCK_TUNING_MID  = 0x0000
LRCK_TUNING_HIGH = 0x00

; Memory map base addresses
TIMER_BASE      = 0xF000
PIN_BASE        = 0xF100

; ============================================================================
; INITIALIZATION
; ============================================================================
reset:
    ; Initialize stack pointer
    ldi r15, 0x0FFF
    
    ; Configure pins for timer output
    ; Pin 0-2: Timer NCO output (MCLK, BCLK, LRCK)
    ; Pin 3: CPU output (SDATA_OUT)
    ; Pin 4: CPU input (SDATA_IN)
    
    ; Set pin direction (output for 0-3, input for 4)
    ldi r0, 0x0F        ; pins 0-3 output
    st  [PIN_BASE + PIN_DIR], r0
    
    ; Set pin config to timer for pins 0-2
    ldi r0, CFG_TIMER
    st  [PIN_BASE + PIN_CONFIG + 0], r0  ; Pin 0 -> Timer 0
    st  [PIN_BASE + PIN_CONFIG + 1], r0  ; Pin 1 -> Timer 1
    st  [PIN_BASE + PIN_CONFIG + 2], r0  ; Pin 2 -> Timer 2
    
    ; Pin 3: CPU controlled (SDATA_OUT)
    ldi r0, CFG_CPU
    st  [PIN_BASE + PIN_CONFIG + 3], r0
    
    ; Pin 4: CPU controlled input (SDATA_IN)
    ldi r0, CFG_CPU | CFG_PULLUP
    st  [PIN_BASE + PIN_CONFIG + 4], r0
    
    ; Enable output drivers for pins 0-3
    ldi r0, 0x0F
    st  [PIN_BASE + PIN_OE], r0

; ============================================================================
; TIMER 0: MCLK = 12.288 MHz
; ============================================================================
    ; Timer 0 base = TIMER_BASE + 0*16 = 0xF000
    ldi r1, MCLK_TUNING_LOW
    ldi r2, MCLK_TUNING_MID
    ldi r3, MCLK_TUNING_HIGH
    st  [TIMER_BASE + TIMER_TUNING], r1
    st  [TIMER_BASE + TIMER_TUNING + 1], r2
    st  [TIMER_BASE + TIMER_TUNING + 2], r3
    
    ldi r0, MODE_NCO
    st  [TIMER_BASE + TIMER_MODE], r0

; ============================================================================
; TIMER 1: BCLK = 3.072 MHz
; ============================================================================
    ; Timer 1 base = TIMER_BASE + 1*16 = 0xF010
    ldi r1, BCLK_TUNING_LOW
    ldi r2, BCLK_TUNING_MID
    ldi r3, BCLK_TUNING_HIGH
    st  [TIMER_BASE + 16 + TIMER_TUNING], r1
    st  [TIMER_BASE + 16 + TIMER_TUNING + 1], r2
    st  [TIMER_BASE + 16 + TIMER_TUNING + 2], r3
    
    ldi r0, MODE_NCO
    st  [TIMER_BASE + 16 + TIMER_MODE], r0

; ============================================================================
; TIMER 2: LRCK = 48 kHz
; ============================================================================
    ; Timer 2 base = TIMER_BASE + 2*16 = 0xF020
    ldi r1, LRCK_TUNING_LOW
    ldi r2, LRCK_TUNING_MID
    ldi r3, LRCK_TUNING_HIGH
    st  [TIMER_BASE + 32 + TIMER_TUNING], r1
    st  [TIMER_BASE + 32 + TIMER_TUNING + 1], r2
    st  [TIMER_BASE + 32 + TIMER_TUNING + 2], r3
    
    ldi r0, MODE_NCO
    st  [TIMER_BASE + 32 + TIMER_MODE], r0

; ============================================================================
; TIMER 3: Sample Rate Sync (48kHz interrupt)
; ============================================================================
    ; Timer 3 in capture mode for LRCK edge detection
    ldi r0, MODE_CAPTURE | MODE_EVENT
    st  [TIMER_BASE + 48 + TIMER_MODE], r0
    ; Capture on pin 2 (LRCK) rising edge

; ============================================================================
; MAIN LOOP - I2S Data Handling
; ============================================================================
main_loop:
    ; Check for LRCK edge (frame sync) from Timer 3 capture
    ld  r0, [TIMER_BASE + 48 + TIMER_EVENT]
    and r0, r0, 0x01
    beqz r0, check_tx
    
    ; LRCK edge detected - new frame
    ; Read RX data (pin 4)
    ld  r1, [PIN_BASE + PIN_IN]
    and r1, r1, 0x10      ; Pin 4
    ; Store to RX buffer (implement circular buffer here)
    
    ; Prepare TX data for next frame
    ; Get next sample from TX buffer
    ; For demo: output 1kHz sine on left, silence on right
    call sine_next_sample
    
    ; Write to pin 3 (SDATA_OUT) - MSB first, sync with BCLK
    ; This is simplified - real I2S needs bit-banging or shift register
    
check_tx:
    ; Check if BCLK rising edge for bit clocking
    ; (Timer 1 events)
    ld  r0, [TIMER_BASE + 16 + TIMER_EVENT]
    and r0, r0, 0x01
    beqz r0, check_rx
    
    ; BCLK edge - shift out next bit
    ; (Implement shift register for 24/32-bit I2S)
    
check_rx:
    ; Check BCLK for RX shift in
    ; (Sample pin 4 on BCLK falling edge)
    
    ; Small delay
    wait 1000
    jmp main_loop

; ============================================================================
; SINE WAVE GENERATION (1kHz @ 48kHz sample rate)
; ============================================================================
sine_next_sample:
    ; Simple sine LUT or CORDIC
    ; For demo, just return a test pattern
    ldi r0, 0x7FFF      ; Max positive
    ret

; ============================================================================
; I2S BIT-BANGING HELPERS (using WAITE for precise timing)
; ============================================================================
i2s_tx_frame:
    ; r0 = left sample, r1 = right sample
    ; Uses Timer 1 (BCLK) for bit timing
    ; Uses Timer 2 (LRCK) for frame timing
    push r2
    push r3
    push r4
    push r5
    
    ldi r2, 32          ; 32 bits per channel
    ldi r3, 0xF010      ; Timer 1 base
    
tx_left_loop:
    ; Wait for BCLK rising edge
    ld  r4, [r3 + TIMER_EVENT]
    and r4, r4, 0x01
    beqz r4, tx_left_loop
    
    ; Output MSB of left sample
    ; (Simplified - would use pin_matrix CPU output)
    shr r0, r0, 1
    dec r2
    bnez r2, tx_left_loop
    
    ; Right channel
    ldi r2, 32
tx_right_loop:
    ld  r4, [r3 + TIMER_EVENT]
    and r4, r4, 0x01
    beqz r4, tx_right_loop
    
    shr r1, r1, 1
    dec r2
    bnez r2, tx_right_loop
    
    pop r5
    pop r4
    pop r3
    pop r2
    ret

; ============================================================================
; VECTOR TABLE
; ============================================================================
        .org 0x0FF0
        .word reset       ; Reset vector
        .word 0           ; IRQ vectors (unused)
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0

