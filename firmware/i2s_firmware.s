/*
 * I2S Clock Generation Firmware for Protocol Emulator
 * 
 * Generates I2S clocks using timers:
 * - Timer 0: MCLK = 12.288 MHz (48kHz × 256)
 * - Timer 1: BCLK = 3.072 MHz  (48kHz × 64)
 * - Timer 2: LRCK = 48 kHz
 * 
 * Pin assignments:
 * - Pin 0: MCLK output (Timer 0 NCO)
 * - Pin 1: BCLK output (Timer 1 NCO)
 * - Pin 2: LRCK output (Timer 2 NCO)
 * - Pin 3: SDATA_OUT (CPU bit-bang)
 * - Pin 4: SDATA_IN (CPU read)
 * 
 * NCO Formula: f_out = (tuning × 50MHz) / 2^24
 * 
 * MCLK (12.288MHz): tuning = 12288000 × 2^24 / 50000000 = 0x2D1A94
 * BCLK (3.072MHz):  tuning = 3072000 × 2^24 / 50000000 = 0x0B46A5
 * LRCK (48kHz):     tuning = 48000 × 2^24 / 50000000 = 0x00199A
 */

        .org 0x0000

; ============================================================================
; CONSTANTS (Equates)
; ============================================================================
; Timer modes
MODE_NCO        = 0x01
MODE_PWM        = 0x02
MODE_CAPTURE    = 0x04
MODE_EVENT      = 0x08

; Pin config sources
SRC_CPU         = 0x00
SRC_TIMER0      = 0x01
SRC_TIMER1      = 0x02
SRC_TIMER2      = 0x03
SRC_TIMER3      = 0x04
SRC_TIMER4      = 0x05
SRC_TIMER5      = 0x06
SRC_TIMER6      = 0x07
SRC_TIMER7      = 0x08

; NCO tuning words (24-bit each)
; MCLK = 12.288 MHz: 0x2D1A94
MCLK_TUNING_LOW  = 0xA94   ; low 12 bits
MCLK_TUNING_MID  = 0xD1A   ; mid 12 bits (actually bits 12-23)
MCLK_TUNING_HIGH = 0x02    ; high bits

; BCLK = 3.072 MHz: 0x0B46A5
BCLK_TUNING_LOW  = 0x6A5
BCLK_TUNING_MID  = 0x0B4
BCLK_TUNING_HIGH = 0x00

; LRCK = 48 kHz: 0x00199A
LRCK_TUNING_LOW  = 0x99A
LRCK_TUNING_MID  = 0x001
LRCK_TUNING_HIGH = 0x00

; Peripheral base addresses (not used directly - accessed via custom insns)
TIMER_BASE      = 0xF000
PIN_BASE        = 0xF100
HOST_BASE       = 0xF200

; ============================================================================
; INITIALIZATION
; ============================================================================
reset:
    ; Initialize stack pointer (x15)
    LDI x15, 0x0FFF
    
    ; Configure pins for timer output
    ; Pin 0-2: Timer NCO output (MCLK, BCLK, LRCK) -> PINSEL to Timer
    ; Pin 3: CPU output (SDATA_OUT) -> PINSEL to CPU
    ; Pin 4: CPU input (SDATA_IN) -> PINSEL to CPU, DIR=input
    
    ; Set pin directions: pins 0-3 output, pin 4 input
    ; DIR pin, dir (dir=1 for output, 0 for input)
    DIR x0, x1      ; Pin 0 = output (x1=1)
    LDI x1, 1
    DIR x1, x1      ; Pin 1 = output
    DIR x2, x1      ; Pin 2 = output
    DIR x3, x1      ; Pin 3 = output
    LDI x1, 0
    DIR x4, x1      ; Pin 4 = input

    ; Configure pin sources (PINSEL pin, source)
    ; Pins 0-2 -> Timer 0,1,2 NCO
    LDI x1, SRC_TIMER0
    PINSEL x0, x1   ; Pin 0 -> Timer 0
    LDI x1, SRC_TIMER1
    PINSEL x1, x1   ; Pin 1 -> Timer 1
    LDI x1, SRC_TIMER2
    PINSEL x2, x1   ; Pin 2 -> Timer 2
    ; Pin 3,4 -> CPU (default SRC_CPU = 0)
    LDI x1, SRC_CPU
    PINSEL x3, x1   ; Pin 3 -> CPU
    PINSEL x4, x1   ; Pin 4 -> CPU

; ============================================================================
; TIMER 0: MCLK = 12.288 MHz
; ============================================================================
    ; TUNING timer, value (24-bit across low/mid/high)
    ; Timer 0 tuning low
    LDI x1, MCLK_TUNING_LOW
    TUNING x0, x1
    ; Timer 0 tuning mid  
    LDI x1, MCLK_TUNING_MID
    TUNING x0, x1
    ; Timer 0 tuning high
    LDI x1, MCLK_TUNING_HIGH
    TUNING x0, x1
    
    ; TCFG timer, config (mode = NCO)
    LDI x1, MODE_NCO
    TCFG x0, x1

; ============================================================================
; TIMER 1: BCLK = 3.072 MHz
; ============================================================================
    LDI x1, BCLK_TUNING_LOW
    TUNING x1, x1
    LDI x1, BCLK_TUNING_MID
    TUNING x1, x1
    LDI x1, BCLK_TUNING_HIGH
    TUNING x1, x1
    
    LDI x1, MODE_NCO
    TCFG x1, x1

; ============================================================================
; TIMER 2: LRCK = 48 kHz
; ============================================================================
    LDI x1, LRCK_TUNING_LOW
    TUNING x2, x1
    LDI x1, LRCK_TUNING_MID
    TUNING x2, x1
    LDI x1, LRCK_TUNING_HIGH
    TUNING x2, x1
    
    LDI x1, MODE_NCO
    TCFG x2, x1

; ============================================================================
; TIMER 3: Frame Sync Capture (LRCK edge detection)
; ============================================================================
    ; Configure Timer 3 for capture mode on Pin 2 (LRCK)
    LDI x1, MODE_CAPTURE | MODE_EVENT
    TCFG x3, x1
    
    ; Enable capture on rising edge
    LDI x1, 0x01    ; Rising edge event
    EVEN x3, x1

; ============================================================================
; MAIN LOOP - I2S Data Handling
; ============================================================================
main_loop:
    ; Check for LRCK edge (frame sync) from Timer 3 capture
    ; CAPRD rd, timer - reads capture value
    CAPRD x0, x3
    ANDI x0, x0, 0x01   ; Check event status bit 0 (rise)
    BEQZ x0, check_tx
    
    ; LRCK edge detected - new frame
    ; Read RX data (pin 4) - use OUT to read pin? No, pin input is read via pin matrix
    ; For now, just toggle a pattern on TX
    
    ; Prepare TX data for next frame (simplified - output alternating pattern)
    ; This is where real I2S TX would go
    
check_tx:
    ; Check BCLK for TX bit clocking
    ; Could use Timer 1 events, but simplified polling
    
    ; Small delay
    WAIT x0, 100
    JMP main_loop

; ============================================================================
; VECTOR TABLE
; ============================================================================
        .org 0x0FF0
        .WORD reset       ; Reset vector
        .WORD 0           ; IRQ vectors (unused)
        .WORD 0
        .WORD 0
        .WORD 0
        .WORD 0
        .WORD 0
        .WORD 0
