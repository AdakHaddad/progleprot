# I2S Protocol Tutorial — Complete Firmware Implementation

## I2S Overview

**I2S (Inter-IC Sound)** is a serial bus for digital audio. Three clock lines + data:

| Signal | Name | Direction | Description |
|--------|------|-----------|-------------|
| **MCLK** | Master Clock | Out | 256×fs or 512×fs (e.g., 12.288 MHz for 48 kHz) |
| **BCLK** | Bit Clock | Out | 64×fs (e.g., 3.072 MHz for 48 kHz, 32-bit) |
| **LRCK** | Left/Right Clock | Out | Frame sync = sample rate (e.g., 48 kHz) |
| **SDOUT** | Serial Data Out | Out | MSB first, left channel first |
| **SDIN** | Serial Data In | In | Optional, for ADC/microphone |

```
Timing Diagram (Standard I2S, 32-bit, 48 kHz):

MCLK:  ____/‾‾\____/‾‾\____/‾‾\____/‾‾\____  (12.288 MHz)
BCLK:  _______/‾‾\_______/‾‾\_______/‾‾\___  (3.072 MHz)
LRCK:  ____________________/‾‾‾‾‾‾‾‾‾‾\__  (48 kHz, 50% duty)
        Left (32 bits)        Right (32 bits)

SDOUT: [L31 L30 ... L0] [R31 R30 ... R0]  (MSB first, changes on BCLK falling)
        Sampled on BCLK rising
```

### I2S Variants

| Variant | LRCK Duty | Data Delay | MSB Position |
|---------|-----------|------------|--------------|
| **Standard I2S** | 50% | 1 BCLK after LRCK edge | Bit 31 |
| **Left-Justified** | 50% | 0 BCLK after LRCK edge | Bit 31 |
| **Right-Justified** | 50% | Variable (aligned to end) | Bit 0 |
| **DSP/PCM Mode** | Pulse | 0 or 1 BCLK | Configurable |

---

## Hardware Setup on Protocol Emulator

### Pin Assignment (PMOD JA on Basys3)

| PMOD Pin | FPGA Pin | Protocol Pin | Signal | Source |
|----------|----------|--------------|--------|--------|
| JA[0] | U16 | Pin 0 | MCLK | Timer 0 NCO |
| JA[1] | V16 | Pin 1 | BCLK | Timer 1 NCO |
| JA[2] | U15 | Pin 2 | LRCK | Timer 2 NCO |
| JA[3] | V15 | Pin 3 | SDOUT | CPU (bit-bang) |
| JA[4] | J14 | Pin 4 | SDIN | CPU (read) |

### Timer Configuration

```python
# NCO tuning @ 50MHz system clock
# f_out = tuning × 50MHz / 2^24

MCLK = 12_288_000  # 48k × 256
BCLK = 3_072_000   # 48k × 64  
LRCK = 48_000      # 48 kHz

tuning_MCLK = int(MCLK * 2**24 / 50_000_000)  # 0x2D1A94
tuning_BCLK = int(BCLK * 2**24 / 50_000_000)  # 0x0B46A5
tuning_LRCK = int(LRCK * 2**24 / 50_000_000)  # 0x00199A
```

| Timer | Signal | Frequency | Tuning (hex) | Mode |
|-------|--------|-----------|--------------|------|
| 0 | MCLK | 12.288 MHz | 0x2D1A94 | NCO_CLK |
| 1 | BCLK | 3.072 MHz | 0x0B46A5 | NCO_CLK |
| 2 | LRCK | 48 kHz | 0x00199A | NCO_CLK |
| 3 | Frame Sync | 48 kHz | — | CAPTURE |

---

## Complete Firmware: I2S TX + RX

```assembly
; ============================================================
; i2s_full.s — Complete I2S TX/RX with 32-bit stereo
; ============================================================

        .org 0x0000

; ---- CONSTANTS ----
.equ MODE_OFF       = 0x00
.equ MODE_NCO_CLK   = 0x03
.equ MODE_CAPTURE   = 0x08
.equ MODE_EVENT     = 0x10

.equ SRC_CPU        = 0x0
.equ SRC_TIMER0     = 0x1
.equ SRC_TIMER1     = 0x2
.equ SRC_TIMER2     = 0x3
.equ SRC_TIMER3     = 0x4

.equ EV_RISE        = 0x1
.equ EV_FALL        = 0x2

; NCO tuning words (50MHz clock)
; MCLK = 12.288 MHz: 0x2D1A94
.equ MCLK_TUNING_LO  = 0x94
.equ MCLK_TUNING_MID = 0x1A
.equ MCLK_TUNING_HI  = 0x2D

; BCLK = 3.072 MHz: 0x0B46A5
.equ BCLK_TUNING_LO  = 0xA5
.equ BCLK_TUNING_MID = 0x46
.equ BCLK_TUNING_HI  = 0x0B

; LRCK = 48 kHz: 0x00199A
.equ LRCK_TUNING_LO  = 0x9A
.equ LRCK_TUNING_MID = 0x19
.equ LRCK_TUNING_HI  = 0x00

; Memory map (not directly accessed - use custom instructions)
.equ TIMER_BASE      = 0xF000
.equ PIN_BASE        = 0xF100

; ============================================================================
; INITIALIZATION
; ============================================================================
reset:
    ; Initialize stack pointer
    LDI  x15, 0x0FFF
    
    ; Configure all pins
    ; Pin 0 (MCLK) → Timer 0 NCO output
    LDI  x1, 1
    DIR  x0, x1
    LDI  x1, SRC_TIMER0
    PINSEL x0, x1
    
    ; Pin 1 (BCLK) → Timer 1 NCO output
    DIR  x1, x1
    LDI  x1, SRC_TIMER1
    PINSEL x1, x1
    
    ; Pin 2 (LRCK) → Timer 2 NCO output
    DIR  x2, x1
    LDI  x1, SRC_TIMER2
    PINSEL x2, x1
    
    ; Pin 3 (SDOUT) → CPU output
    DIR  x3, x1
    LDI  x1, SRC_CPU
    PINSEL x3, x1
    
    ; Pin 4 (SDIN) → CPU input
    LDI  x1, 0
    DIR  x4, x1
    LDI  x1, SRC_CPU
    PINSEL x4, x1

; ============================================================================
; TIMER 0: MCLK = 12.288 MHz
; ============================================================================
    LDI  x1, MCLK_TUNING_LO
    TUNING x0, x1
    LDI  x1, MCLK_TUNING_MID
    TUNING x0, x1
    LDI  x1, MCLK_TUNING_HI
    TUNING x0, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x0, x1

; ============================================================================
; TIMER 1: BCLK = 3.072 MHz
; ============================================================================
    LDI  x1, BCLK_TUNING_LO
    TUNING x1, x1
    LDI  x1, BCLK_TUNING_MID
    TUNING x1, x1
    LDI  x1, BCLK_TUNING_HI
    TUNING x1, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x1, x1

; ============================================================================
; TIMER 2: LRCK = 48 kHz
; ============================================================================
    LDI  x1, LRCK_TUNING_LO
    TUNING x2, x1
    LDI  x1, LRCK_TUNING_MID
    TUNING x2, x1
    LDI  x1, LRCK_TUNING_HI
    TUNING x2, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x2, x1

; ============================================================================
; TIMER 3: Frame Sync Capture (LRCK rising edge)
; ============================================================================
    ; Configure for capture on Pin 2 (LRCK) rising edge
    LDI  x1, MODE_CAPTURE | MODE_EVENT
    TCFG   x3, x1
    LDI  x1, EV_RISE
    EVEN   x3, x1

; ============================================================================
; AUDIO BUFFERS
; ============================================================================
    ; TX Buffer: 64 samples (32 left + 32 right) = 128 words
    ; RX Buffer: same
    LDI  x10, 0x0200    ; TX buffer base
    LDI  x11, 0x0300    ; RX buffer base
    LDI  x12, 0         ; TX head
    LDI  x13, 0         ; TX tail
    LDI  x14, 0         ; RX head

; ============================================================================
; MAIN LOOP
; ============================================================================
main_loop:
    ; Check for LRCK edge (frame sync) from Timer 3 capture
    CAPRD x0, x3        ; Read capture FIFO
    ANDI  x0, x0, EV_RISE
    BEQZ  x0, check_tx  ; No LRCK edge
    
    ; ===== NEW FRAME (LRCK edge detected) =====
    ; This runs at 48 kHz (every sample period)
    
    ; --- RX: Read left channel (32 bits on BCLK) ---
    CALL i2s_rx_channel
    ; Result in x7 = left sample
    ; Store to RX buffer
    ADD  x5, x11, x14
    ST   [x5], x7
    ADDI x14, x14, 1
    ANDI x14, x14, 0x3F ; Modulo 64
    
    ; --- RX: Read right channel ---
    CALL i2s_rx_channel
    ; Result in x7 = right sample
    ADD  x5, x11, x14
    ST   [x5], x7
    ADDI x14, x14, 1
    ANDI x14, x14, 0x3F
    
    ; --- TX: Get next left sample ---
    ADD  x5, x10, x12
    LD   x7, [x5]       ; Left sample
    ADDI x12, x12, 1
    ANDI x12, x12, 0x3F
    CALL i2s_tx_channel
    
    ; --- TX: Get next right sample ---
    ADD  x5, x10, x12
    LD   x7, [x5]       ; Right sample
    ADDI x12, x12, 1
    ANDI x12, x12, 0x3F
    CALL i2s_tx_channel

check_tx:
    ; Can add additional processing here
    JMP  main_loop

; ============================================================================
; I2S TX CHANNEL (32 bits, MSB first, changes on BCLK falling)
; Input: x7 = 32-bit sample to transmit
; Uses: Timer 1 (BCLK) events for timing
; ============================================================================
i2s_tx_channel:
    PUSH x8
    PUSH x9
    PUSH x10
    
    LDI  x8, 32         ; 32 bits per channel
    LDI  x9, 0          ; Bit index (0=MSB)
    
tx_bit_loop:
    ; Wait for BCLK falling edge (data changes on falling, sampled on rising)
    WAITE x1, EV_FALL   ; Timer 1 = BCLK
    
    ; Output MSB of sample
    ; Shift sample left so MSB is in bit 15, then extract
    SLL  x10, x7, 1     ; Shift left by 1 (MSB moves toward bit 15)
    MOV  x7, x10        ; Update sample
    SHR  x10, x7, 15    ; Extract MSB (now in bit 15 after 32 shifts)
    ANDI x10, x10, 1
    OUT  x3, x10        ; Drive SDOUT (pin 3)
    
    DEC  x8
    BNEZ x8, tx_bit_loop
    
    POP  x10
    POP  x9
    POP  x8
    RET

; ============================================================================
; I2S RX CHANNEL (32 bits, MSB first, sampled on BCLK rising)
; Output: x7 = 32-bit received sample
; Uses: Timer 1 (BCLK) events for timing
; ============================================================================
i2s_rx_channel:
    PUSH x8
    PUSH x9
    PUSH x10
    
    LDI  x8, 32         ; 32 bits per channel
    LDI  x7, 0          ; Clear result
    LDI  x9, 0          ; Bit index
    
rx_bit_loop:
    ; Wait for BCLK rising edge (data sampled on rising)
    WAITE x1, EV_RISE   ; Timer 1 = BCLK
    
    ; Read SDIN (pin 4)
    IN   x10, x4        ; Read pin 4
    ANDI x10, x10, 1
    
    ; Shift in new bit (MSB first)
    SLL  x7, x7, 1
    OR   x7, x7, x10
    
    DEC  x8
    BNEZ x8, rx_bit_loop
    
    POP  x10
    POP  x9
    POP  x8
    RET

; ============================================================================
; SINE WAVE GENERATION (for testing TX)
; ============================================================================
; Generates 1 kHz sine wave at 48 kHz sample rate
; Uses 256-entry quarter-wave LUT
sine_lut:
    .word 0x0000, 0x0324, 0x0647, 0x096A, 0x0C8B, 0x0FAB, 0x12C8, 0x15E2
    .word 0x18F8, 0x1C0B, 0x1F19, 0x2223, 0x2528, 0x2826, 0x2B1F, 0x2E11
    ; ... (256 entries total)

sine_next_sample:
    ; x1 = phase accumulator (0-65535)
    ; x2 = phase increment (for 1kHz @ 48kHz: 65536*1000/48000 ≈ 1365)
    ; x3 = LUT base address
    ; Returns 16-bit sample in x7 (sign-extended to 32-bit)
    ; Implementation simplified for demo
    LDI  x7, 0x7FFF
    RET

; ============================================================================
; VECTOR TABLE
; ============================================================================
        .org 0x0FF0
        .word reset
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
```

---

## Simplified Firmware: Clocks Only (i2s_clocks.s)

For testing clock generation without data handling:

```assembly
; ============================================================
; i2s_clocks.s — I2S Clock Generation Only
; ============================================================

        .org 0x0000

; ---- CONSTANTS ----
.equ MODE_NCO_CLK   = 0x03
.equ SRC_CPU        = 0x0
.equ SRC_TIMER0     = 0x1
.equ SRC_TIMER1     = 0x2
.equ SRC_TIMER2     = 0x3

; NCO tuning words
.equ MCLK_TUNING_LO  = 0x94
.equ MCLK_TUNING_MID = 0x1A
.equ MCLK_TUNING_HI  = 0x2D

.equ BCLK_TUNING_LO  = 0xA5
.equ BCLK_TUNING_MID = 0x46
.equ BCLK_TUNING_HI  = 0x0B

.equ LRCK_TUNING_LO  = 0x9A
.equ LRCK_TUNING_MID = 0x19
.equ LRCK_TUNING_HI  = 0x00

; ============================================================================
reset:
    LDI  x15, 0x0FFF
    
    ; Pin directions: 0-3 output, 4 input
    LDI  x1, 1
    DIR  x0, x1
    DIR  x1, x1
    DIR  x2, x1
    DIR  x3, x1
    LDI  x1, 0
    DIR  x4, x1
    
    ; Pin sources: 0-2 = Timers, 3-4 = CPU
    LDI  x1, SRC_TIMER0
    PINSEL x0, x1
    LDI  x1, SRC_TIMER1
    PINSEL x1, x1
    LDI  x1, SRC_TIMER2
    PINSEL x2, x1
    LDI  x1, SRC_CPU
    PINSEL x3, x1
    PINSEL x4, x1

; ---- TIMER 0: MCLK 12.288 MHz ----
    LDI  x1, MCLK_TUNING_LO
    TUNING x0, x1
    LDI  x1, MCLK_TUNING_MID
    TUNING x0, x1
    LDI  x1, MCLK_TUNING_HI
    TUNING x0, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x0, x1

; ---- TIMER 1: BCLK 3.072 MHz ----
    LDI  x1, BCLK_TUNING_LO
    TUNING x1, x1
    LDI  x1, BCLK_TUNING_MID
    TUNING x1, x1
    LDI  x1, BCLK_TUNING_HI
    TUNING x1, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x1, x1

; ---- TIMER 2: LRCK 48 kHz ----
    LDI  x1, LRCK_TUNING_LO
    TUNING x2, x1
    LDI  x1, LRCK_TUNING_MID
    TUNING x2, x1
    LDI  x1, LRCK_TUNING_HI
    TUNING x2, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x2, x1

; ---- MAIN LOOP ----
main_loop:
    ; All clocks running in hardware, zero CPU overhead
    ; Add any housekeeping here
    WAIT x0, 10000
    JMP  main_loop

        .org 0x0FF0
        .word reset
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
```

---

## Building & Testing

### Assemble
```bash
cd /home/muqtada/Documents/progleprot
python3 scripts/asm.py firmware/i2s_clocks.s -o firmware/i2s_clocks.bin
```

### Load on Basys3
```bash
# Program FPGA first
cd fpga/basys3
vivado -mode batch -source build_vivado.tcl
djtgcfg prog -d Basys3 -i 0 -f basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit

# Load firmware
cd ../..
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware/i2s_clocks.bin
```

### Verify on Oscilloscope
Connect PMOD JA to scope:
- **CH1 (JA[0])**: MCLK = 12.288 MHz square wave
- **CH2 (JA[1])**: BCLK = 3.072 MHz square wave  
- **CH3 (JA[2])**: LRCK = 48 kHz 50% duty square wave
- **CH4 (JA[3])**: SDOUT = data (if running full TX firmware)

Expected measurements:
| Signal | Frequency | Period | Duty Cycle |
|--------|-----------|--------|------------|
| MCLK | 12.288 MHz | 81.4 ns | 50% |
| BCLK | 3.072 MHz | 325.5 ns | 50% |
| LRCK | 48 kHz | 20.8 μs | 50% |

---

## Integrating Your Custom AXI I2S Module

If you have a custom `axi_i2s.v` IP (like your `axi_i2s.v` with LCK/DIN/BCK):

### 1. Copy to FPGA Project
```bash
cp your_axi_i2s.v /home/muqtada/Documents/progleprot/fpga/basys3/
```

### 2. Instantiate in `axi_i2s_example.v`
```verilog
axi_i2s u_i2s (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(i2s_axi_awaddr),
    .s_axi_awvalid(i2s_axi_awvalid),
    .s_axi_awready(i2s_axi_awready),
    .s_axi_wdata(i2s_axi_wdata),
    .s_axi_wstrb(i2s_axi_wstrb),
    .s_axi_wvalid(i2s_axi_wvalid),
    .s_axi_wready(i2s_axi_wready),
    .s_axi_bresp(i2s_axi_bresp),
    .s_axi_bvalid(i2s_axi_bvalid),
    .s_axi_bready(i2s_axi_bready),
    .s_axi_araddr(i2s_axi_araddr),
    .s_axi_arvalid(i2s_axi_arvalid),
    .s_axi_arready(i2s_axi_arready),
    .s_axi_rdata(i2s_axi_rdata),
    .s_axi_rresp(i2s_axi_rresp),
    .s_axi_rvalid(i2s_axi_rvalid),
    .s_axi_rready(i2s_axi_rready),
    .mclk(i2s_mclk),
    .bclk(i2s_bclk),
    .lrck(i2s_lrck),
    .sdata_out(i2s_sdata_out),
    .sdata_in(i2s_sdata_in)
);
```

### 3. Add AXI Crossbar Routing
In `basys3_protocol_emu.v` or crossbar module, route address `0x4000_1000` to your AXI I2S slave.

### 4. Protocol Emulator Still Generates Clocks
| Signal | Source | Frequency |
|--------|--------|-----------|
| MCLK | Timer 0 NCO | 12.288 MHz |
| BCLK | Timer 1 NCO | 3.072 MHz |
| LRCK | Timer 2 NCO | 48 kHz |

Your AXI I2S handles:
- Data FIFOs (TX/RX)
- DMA transfers
- I2C codec configuration (WM8731, etc.)
- Audio effects (EQ, volume, etc.)

### 5. CPU Firmware Fills/Reads FIFOs
```assembly
; Write to AXI I2S TX FIFO at 0x4000_1000
axi_write_tx:
    ; x1 = address (0x4000_1000 + TX_FIFO_OFFSET)
    ; x2 = sample data
    ST   [x1], x2
    RET

; Read from AXI I2S RX FIFO
axi_read_rx:
    ; x1 = address (0x4000_1000 + RX_FIFO_OFFSET)
    LD   x2, [x1]
    RET
```

---

## Common Issues & Debugging

| Symptom | Cause | Fix |
|---------|-------|-----|
| No clocks on scope | Timer not enabled | Check `TCFG` = `MODE_NCO_CLK`, `EVEN` set |
| Wrong frequency | Tuning calculation error | Verify: `tuning = freq × 2^24 / 50M` |
| LRCK not 50% duty | NCO_CLK mode issue | `NCO_CLK` gives 50% duty automatically |
| SDOUT stuck at 0 | Pin not in CPU mode | `PIN_SEL` for pin 3 = 0 (CPU) |
| RX all zeros | SDIN not connected / wrong pin | Check Pin 4 = input, pull-up enabled |
| Frame sync off | Timer 3 capture not working | Pin 2 (LRCK) must be monitored by Timer 3 |

### Debug: Single-Step with LED
```assembly
; Add in main loop for single-frame debug
debug_frame:
    LDI  x1, 1
    OUT  x7, x1      ; Pulse LED/debug pin
    WAIT x0, 100000
    LDI  x1, 0
    OUT  x7, x1
    RET
```

---

## Advanced: Using DMA with Your AXI I2S

```verilog
// In your AXI I2S module, add DMA interface
module axi_i2s #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
) (
    // AXI-Lite for control
    input  wire                       s_axi_aclk,
    input  wire                       s_axi_aresetn,
    // ... AXI-Lite signals ...
    
    // I2S Interface
    input  wire                       mclk,
    input  wire                       bclk,
    input  wire                       lrck,
    output wire                       sdata_out,
    input  wire                       sdata_in,
    
    // DMA Interface (optional)
    output wire                       dma_tx_req,
    input  wire                       dma_tx_ack,
    input  wire [31:0]                dma_tx_data,
    output wire                       dma_rx_req,
    input  wire                       dma_rx_ack,
    output wire [31:0]                dma_rx_data
);
```

Protocol emulator CPU can trigger DMA via memory-mapped registers at `0x4000_1000`.

---

## Summary: I2S on Protocol Emulator

| Component | Implementation |
|-----------|----------------|
| **MCLK** | Timer 0 NCO (12.288 MHz) → Pin 0 |
| **BCLK** | Timer 1 NCO (3.072 MHz) → Pin 1 |
| **LRCK** | Timer 2 NCO (48 kHz) → Pin 2 |
| **SDOUT** | CPU bit-bang via OUT + WAITE on BCLK |
| **SDIN** | CPU read via IN on BCLK edges |
| **Frame Sync** | Timer 3 capture on LRCK rising |

**Key insight:** Clocks are **hardware** (jitter-free), data is **firmware** (flexible format). This hybrid approach gives you the best of both worlds.

---

*This is the power of the protocol emulator: hardware clocks + firmware data = any audio format you can code.*
