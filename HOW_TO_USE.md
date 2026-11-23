# How to Use the Protocol Emulator — Practical Guide

## The Core Concept

**This is NOT a fixed-protocol ASIC.** It's a **tiny CPU + hardware timers + programmable pin crossbar**.

| What you might expect | What this actually is |
|----------------------|----------------------|
| UART block, SPI block, I²C block | **No fixed blocks** |
| Configure via registers | **Write firmware (assembly)** |
| "Enable UART at 3Mbps" | **CPU executes bit-bang loop with timer-precise delays** |

The CPU has **custom instructions** for:
- `OUT pin, val` — Drive a pin high/low
- `DIR pin, dir` — Set pin input/output
- `WAIT timer, cycles` — Stall CPU for exact cycle count
- `WAITE timer, event` — Stall until pin edge detected
- `PINSEL pin, src` — Route pin to Timer NCO output (hardware clock gen)
- `TCFG/TUNING` — Configure timer as NCO/PWM/capture

---

## How Any Protocol Works

### Example: UART TX at 3 Mbps

**Hardware setup (once at startup):**
```assembly
; Configure Timer 0 as NCO for 3 Mbps baud clock
ADDI  x1, 0x29        ; NCO tuning low byte  (0x0F5C29 = 3M @ 50MHz)
ADDI  x2, 0x5C        ; NCO tuning mid byte
ADDI  x3, 0x0F        ; NCO tuning high byte
TUNING x0, x1         ; Timer 0 = x1|x2|x3
TCFG   x0, x3         ; Timer 0 mode = NCO_CLK (0x03)

; Pin 0 = TX output, driven by Timer 0 NCO
PINSEL x0, x1         ; Pin 0 source = Timer 0 (0x01)
DIR    x0, x1         ; Pin 0 = output
```

**Transmit loop (runs per byte):**
```assembly
uart_tx_byte:
    ; Start bit (0)
    OUT  x0, x0         ; Pin 0 = 0 (x0 = zero reg)
    WAIT x0, x8         ; Wait 1 bit time (x8 = 16 cycles @ 3M/50M)

    ; 8 data bits (LSB first)
    ldi   x9, 8         ; Bit counter
tx_bit_loop:
    AND   x10, x7, 1    ; Get LSB of tx byte (in x7)
    OUT   x0, x10       ; Drive pin
    SHR   x7, x7, 1     ; Shift right
    WAIT  x0, x8        ; Wait 1 bit time
    DEC   x9
    BNEZ  x9, tx_bit_loop

    ; Stop bit (1)
    OUT  x0, x11        ; Pin 0 = 1 (x11 = 1)
    WAIT x0, x8
    RET
```

**Key point:** The `WAIT` instruction uses Timer 0 hardware counter — **cycle-accurate**, not software loop counting.

---

## Architecture Walkthrough

```
┌─────────────────────────────────────────────────────────────────┐
│                        CPU (16-bit, 4-stage)                    │
│  Registers: x0-x15 (x0=zero)                                    │
│  Custom Instructions: OUT, DIR, WAIT, WAITE, PINSEL, TCFG...   │
└──────────────────────┬──────────────────────────────────────────┘
                       │ Memory-mapped I/O (0xF000-0xF10F)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  Timer Coprocessor (8 independent timers)                       │
│  Each: 24-bit NCO + 16-bit counter + capture + compare + events │
│  Modes: OFF, COUNT_UP, COUNT_DOWN, NCO_CLK, NCO_VAR, PWM,      │
│         CAPTURE, MEASURE                                        │
└──────────────────────┬──────────────────────────────────────────┘
                       │ NCO clock / PWM / events
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  Pin Matrix (8×8 crossbar)                                      │
│  Per pin: Source select (CPU/Timer0-7), Direction, Pull, OE    │
└──────────────────────┬──────────────────────────────────────────┘
                       ▼
              ┌──────────────────┐
              │  8 External Pins │
              └──────────────────┘
```

---

## Writing Firmware for a New Protocol

### Step 1: Understand the Protocol Timing

| Protocol | Key Timing Requirements |
|----------|------------------------|
| UART | Fixed baud rate, start/stop bits, LSB first |
| SPI | Clock from master, MOSI/MISO on edges, CS framing |
| I²C | Open-drain, SCL clock, SDA data, ACK/NACK, START/STOP |
| CAN | Bit-stuffing, CRC, arbitration, sync on edges |
| I2S | MCLK/BCLK/LRCK clocks, MSB first, left/right frames |

### Step 2: Calculate NCO Tuning Words

```python
# NCO Formula: f_out = (tuning × 50MHz) / 2^24
# tuning = f_out × 2^24 / 50MHz

def calc_tuning(freq_hz):
    return int(freq_hz * (1 << 24) / 50_000_000)

# Examples:
calc_tuning(3_000_000)     # 3M UART → 0x0F5C29
calc_tuning(25_000_000)    # 25M SPI → 0x800000
calc_tuning(100_000)       # 100k I²C → 0x051EB8
calc_tuning(500_000)       # 500k CAN → 0x19999A
calc_tuning(12_288_000)    # 12.288M I2S MCLK → 0x2D1A94
calc_tuning(3_072_000)     # 3.072M I2S BCLK → 0x0B46A5
calc_tuning(48_000)        # 48k I2S LRCK → 0x00199A
```

### Step 3: Write Assembly

Template structure:
```assembly
.org 0x0000

; ===== CONSTANTS =====
TIMER_BASE = 0xF000
PIN_BASE   = 0xF100

; Timer registers (per timer, 16 bytes)
TUNING   = 0x00  ; 24-bit: low, mid, high bytes
MODE     = 0x05
COMPARE  = 0x04
EVEN     = 0x06

; Pin registers
PIN_DIR     = 0x00
PIN_SEL     = 0x01  ; low 4 pins
PIN_SEL_H   = 0x02  ; high 4 pins
PIN_OUT     = 0x04
PIN_IN      = 0x05
PIN_OE      = 0x06

; Timer modes
MODE_NCO    = 0x03
MODE_CAPTURE = 0x06

; Pin sources
SRC_CPU     = 0x0
SRC_TIMER0  = 0x1
; ... SRC_TIMER7 = 0x8

; ===== INIT =====
reset:
    ldi x15, 0x0FFF      ; Stack pointer
    
    ; Configure timers
    ; Timer 0 for protocol clock
    ldi x1, TUNING_LOW
    ldi x2, TUNING_MID
    ldi x3, TUNING_HIGH
    st [TIMER_BASE + TUNING], x1
    st [TIMER_BASE + TUNING + 1], x2
    st [TIMER_BASE + TUNING + 2], x3
    ldi x0, MODE_NCO
    st [TIMER_BASE + MODE], x0
    
    ; Configure pins
    ldi x0, PIN_OUTPUT_MASK
    st [PIN_BASE + PIN_DIR], x0
    
    ldi x0, SRC_TIMER0
    st [PIN_BASE + PIN_SEL], x0   ; Pin 0-3
    st [PIN_BASE + PIN_SEL_H], x0 ; Pin 4-7
    
    ldi x0, PIN_OE_MASK
    st [PIN_BASE + PIN_OE], x0

; ===== MAIN LOOP =====
main:
    ; Your protocol state machine here
    ; Use WAIT/WAITE for timing
    ; Use OUT/DIR for bit-banging
    ; Use PINSEL to switch pin sources dynamically
    jmp main

; ===== VECTORS =====
.org 0x0FF0
.word reset
```

### Step 4: Assemble & Load

```bash
cd /home/muqtada/Documents/progleprot

# Assemble
python3 scripts/asm.py firmware/my_protocol.s -o firmware/my_protocol.bin

# Load via UART (Basys3)
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware/my_protocol.bin

# Or via SPI (ASIC)
# Use host_if SPI protocol (see USAGE.md)
```

---

## Concrete Protocol Examples

### UART RX (using WAITE for edge detection)

```assembly
; Timer 1 in capture mode for start bit detection
ldi x0, MODE_CAPTURE | MODE_EVENT
st [TIMER_BASE + 16 + MODE], x0
ldi x0, 0x01              ; Enable rise/fall events
st [TIMER_BASE + 16 + EVEN], x0

uart_rx_byte:
    ; Wait for start bit (falling edge on RX pin)
    WAITE x1, x0          ; x1=Timer1, x0=event mask
    
    ; Start bit detected, wait 1.5 bit times to sample middle
    WAIT x1, x8           ; x8 = 1.5 bit cycles
    
    ; Sample 8 data bits
    ldi x9, 8
rx_loop:
    WAIT x1, x7           ; x7 = 1 bit cycle
    ld x10, [PIN_BASE + PIN_IN]
    and x10, x10, 0x02    ; Pin 1 = RX
    shr x11, x11, 1       ; Shift in
    or x11, x11, x10      ; (adjust for bit position)
    dec x9
    bnez x9, rx_loop
    
    ; Wait for stop bit
    WAIT x1, x7
    RET
```

### SPI Master (using Timer NCO for SCK)

```assembly
; Timer 0 = SCK at 25 MHz (NCO)
; Pin 2 (SCK) → Timer 0 NCO via PINSEL
; Pin 0 (MOSI), Pin 3 (CS) = CPU driven
; Pin 1 (MISO) = CPU input

spi_xfer_byte:
    ; Assert CS
    OUT x3, x0            ; CS low
    
    ldi x9, 8
spi_loop:
    ; MOSI = next bit
    AND x10, x7, 0x80     ; MSB first
    SHR x10, x10, 7
    OUT x0, x10
    SHL x7, x7, 1
    
    ; Wait for SCK rising edge (Timer 0 event)
    WAITE x0, x1          ; Timer 0, event mask
    
    ; Sample MISO on falling edge
    WAITE x0, x2          ; Timer 0, fall event
    ld x10, [PIN_BASE + PIN_IN]
    and x10, x10, 0x02    ; Pin 1 = MISO
    or x11, x11, x10
    
    dec x9
    bnez x9, spi_loop
    
    ; Deassert CS
    OUT x3, x11           ; CS high
    RET
```

### I²C Master (open-drain emulation)

```assembly
; SCL = Pin 1 → Timer 0 NCO (100 kHz)
; SDA = Pin 0 → CPU (open-drain: DIR=out+OUT=0 for low, DIR=in for high-Z)

i2c_start:
    ; SDA high, SCL high (both released)
    DIR x0, x0            ; SDA = input (pull-up)
    DIR x1, x0            ; SCL = input
    WAIT x0, x8           ; Setup time
    
    ; SDA low while SCL high = START
    DIR x0, x11           ; SDA = output
    OUT x0, x0            ; SDA = 0
    WAIT x0, x8           ; Hold time
    RET

i2c_write_bit:
    ; SCL low, set SDA
    DIR x1, x11           ; SCL = output
    OUT x1, x0            ; SCL = 0
    OUT x0, x7            ; SDA = bit
    DIR x0, x11           ; SDA = output
    WAIT x0, x8
    
    ; SCL high
    OUT x1, x11           ; SCL = 1
    WAIT x0, x8
    
    ; SCL low
    OUT x1, x0            ; SCL = 0
    RET

i2c_read_ack:
    ; Release SDA (input with pull-up)
    DIR x0, x0            ; SDA = input
    ldi x0, CFG_PULLUP
    st [PIN_BASE + PIN_PULL], x0
    
    ; SCL high
    OUT x1, x11
    WAIT x0, x8
    
    ; Sample ACK
    ld x10, [PIN_BASE + PIN_IN]
    and x10, x10, 0x01    ; SDA = Pin 0
    
    ; SCL low
    OUT x1, x0
    RET
```

---

## Pin Matrix Mapping

| Pin Source Value | Signal Routed to Pin |
|-----------------|---------------------|
| 0x0 | CPU OUT register (bit-bang) |
| 0x1 | Timer 0 NCO clock |
| 0x2 | Timer 1 NCO clock |
| 0x3 | Timer 2 NCO clock |
| 0x4 | Timer 3 NCO clock |
| 0x5 | Timer 4 NCO clock |
| 0x6 | Timer 5 NCO clock |
| 0x7 | Timer 6 NCO clock |
| 0x8 | Timer 7 NCO clock |
| 0x9 | Timer 0 PWM |
| 0xA | Timer 1 PWM |
| ... | ... |
| 0xF | Timer 6 PWM |

**Dynamic switching:** Change `PINSEL` at runtime to switch a pin from CPU to Timer NCO mid-protocol.

---

## Memory Map Quick Reference

| Address | Register | Use |
|---------|----------|-----|
| 0x0000-0x0FFF | Program RAM | Your firmware |
| 0xF000-0xF00F | Timer 0 | 16 bytes |
| 0xF010-0xF01F | Timer 1 | 16 bytes |
| ... | ... | ... |
| 0xF070-0xF07F | Timer 7 | 16 bytes |
| 0xF100 | Pin DIR | 8 bits |
| 0xF101 | Pin SEL (0-3) | 4×4 bits |
| 0xF102 | Pin SEL (4-7) | 4×4 bits |
| 0xF103 | Pin PULL | 8×2 bits |
| 0xF104 | Pin OUT | 8 bits (CPU drive) |
| 0xF105 | Pin IN | 8 bits (read) |
| 0xF106 | Pin OE | 8 bits |

---

## Debugging Tips

### 1. Use Debug Registers
```assembly
; SW0-SW3 select register to show on LEDs
; LED[15:0] = register value
```

### 2. Add Printf-style Debug
```assembly
debug_print:
    ; Output value on pin 7 (scope/logic analyzer)
    OUT x7, x10
    WAIT x0, x1000
    RET
```

### 3. Check Timer Events
```assembly
ld x10, [TIMER_BASE + EV_ST]  ; Read event status (clears on read)
and x10, x10, 0x01            ; Check bit 0
bnez x10, event_occurred
```

### 4. Simulation
```bash
# Run in iverilog with VCD waveform
iverilog -g2012 -o sim.vvp -Isim -Irtl \
  sim/tb_my_protocol.v rtl/emu_top.v rtl/cpu_core.v ...
vvp sim.vvp
gtkwave sim.vcd
```

---

## Workflow Summary

```
┌─────────────┐
│ 1. Design   │  Understand protocol timing
│  Protocol   │  Calculate NCO tuning words
└──────┬──────┘
       ▼
┌─────────────┐
│ 2. Write    │  Assembly (.s) with custom instructions
│  Firmware   │  Use macros for common patterns
└──────┬──────┘
       ▼
┌─────────────┐
│ 3. Assemble │  python3 scripts/asm.py firmware/proto.s -o proto.bin
└──────┬──────┘
       ▼
┌─────────────┐
│ 4. Simulate │  iverilog + tb_*.v → VCD → gtkwave
│  (optional) │
└──────┬──────┘
       ▼
┌─────────────┐
│ 5. Load     │  UART: python3 uart_load_firmware.py --port /dev/ttyUSB0 --firmware proto.bin
│  & Run      │  SPI:  host_if protocol (see USAGE.md)
└──────┬──────┘
       ▼
┌─────────────┐
│ 6. Verify   │  Logic analyzer / scope on PMOD pins
│  on Hardware│  LEDs show CPU status
└─────────────┘
```

---

## Key Files to Reference

| File | Purpose |
|------|---------|
| `docs/USAGE.md` | Full ISA, memory map, NCO formulas |
| `docs/ISA.md` | Instruction encoding tables |
| `firmware/uart.s` | Working UART TX/RX example |
| `firmware/spi.s` | Working SPI master example |
| `firmware/i2c.s` | Working I²C master example |
| `firmware/i2s_clocks.s` | Timer NCO clock generation |
| `scripts/asm.py` | Assembler (read for pseudo-ops) |
| `rtl/cpu_core.v` | CPU implementation (custom instruction decode) |
| `rtl/timer_coproc.v` | Timer modes, NCO, capture logic |
| `rtl/pin_matrix.v` | Crossbar, pin config registers |

---

## Common Patterns Library

Create `firmware/macros.s`:
```assembly
; Wait N cycles using Timer 0
.macro WAIT_CYCLES cycles_reg
    WAIT x0, \cycles_reg
.endm

; Drive pin from register bit 0
.macro PIN_OUT pin_reg, val_reg
    OUT \pin_reg, \val_reg
.endm

; Set pin direction
.macro PIN_DIR pin_reg, dir_reg
    DIR \pin_reg, \dir_reg
.endm

; Configure pin to Timer N NCO
.macro PIN_TO_TIMER pin_reg, timer_num
    ldi x10, \timer_num
    PINSEL \pin_reg, x10
.endm

; Setup Timer N as NCO with 24-bit tuning
.macro SETUP_NCO timer_num, tuning_low, tuning_mid, tuning_high
    ldi x1, \tuning_low
    ldi x2, \tuning_mid
    ldi x3, \tuning_high
    st [TIMER_BASE + \timer_num*16 + TUNING], x1
    st [TIMER_BASE + \timer_num*16 + TUNING + 1], x2
    st [TIMER_BASE + \timer_num*16 + TUNING + 2], x3
    ldi x0, MODE_NCO
    st [TIMER_BASE + \timer_num*16 + MODE], x0
.endm
```

---

## FAQ

**Q: Can I run multiple protocols simultaneously?**
A: Yes! 8 timers + 8 pins. Example: Timer 0=UART TX, Timer 1=UART RX, Timer 2=I²C SCL, Timer 3=SPI SCK. CPU time-slices between them.

**Q: What's the max baud rate?**
A: Limited by CPU cycle time. At 50MHz, ~3-4 Mbps UART practical (needs ~12-16 cycles/bit). For higher rates, use Timer NCO + PINSEL to offload clock generation.

**Q: How do I handle protocols needing <50ns timing?**
A: Use Timer NCO in hardware. The CPU only handles state machine; pin toggling is done by timer hardware via PINSEL.

**Q: Can I add new custom instructions?**
A: Yes, modify `cpu_core.v` decode logic. Opcode 0xF has room for more funct values.

**Q: How do I do interrupts?**
A: Currently no hardware interrupts. Poll timer events (`ld [TIMER_BASE+EV_ST]`) or use `WAITE` to block until event.

---

*This is a reprogrammable protocol emulator — the "protocol" lives in YOUR firmware, not in fixed silicon.*
