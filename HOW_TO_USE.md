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
LDI  x1, 0x29        ; NCO tuning low byte  (0x0F5C29 = 3M @ 50MHz)
LDI  x2, 0x5C        ; NCO tuning mid byte
LDI  x3, 0x0F        ; NCO tuning high byte
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
    LDI   x9, 8         ; Bit counter
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
                       │ Memory-mapped I/O (0xF000-0xF20F)
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

For each protocol, identify:
- **Clock frequencies** needed (baud, bit clock, sample rate)
- **Pin roles** (input, output, bidirectional, open-drain)
- **Timing requirements** (setup/hold, edge relationships)

### Step 2: Map to Hardware Resources

| Protocol Element | Hardware Resource |
|------------------|-------------------|
| Baud/bit clock | Timer NCO (hardware, jitter-free) |
| Data pins | CPU OUT + WAIT/WAITE (firmware-timed) |
| Edge detection | Timer CAPTURE/MEASURE + WAITE |
| Open-drain (I²C) | CPU DIR toggle (output=drive low, input=release) |
| Multi-pin sync | Multiple timers + PINSEL |

### Step 3: Choose Timing Strategy

| Strategy | Use When | Example |
|----------|----------|---------|
| **Hardware NCO + WAIT** | Fixed frequency, CPU drives data | UART, SPI clock |
| **Hardware NCO + WAITE** | Need to sync to external clock | SPI slave, I²C |
| **Timer CAPTURE** | Measure unknown timing | Protocol detection, analysis |
| **Pure CPU WAIT** | Very slow, simple timing | Bit-bang slow protocols |

### Step 4: Write Assembly

Use the assembler (`scripts/asm.py`) and firmware templates.

---

## Quick Start: Basys3 FPGA Demo

### Hardware Required
- Digilent Basys3 (Artix-7 XC7A35T)
- USB cable (power + UART + JTAG)
- PMOD cables for protocol pins

### Build & Program
```bash
cd /home/muqtada/Documents/progleprot

# Build bitstream
cd fpga/basys3
vivado -mode batch -source build_vivado.tcl

# Program board (using Digilent Adept)
djtgcfg prog -d Basys3 -i 0 -f basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit

# Or use Vivado Hardware Manager
# open_hw; connect_hw_server; current_hw_device [get_hw_devices xc7a35t_0]
# program_hw_devices [get_hw_devices xc7a35t_0] -bitstream basys3_protocol_emu.bit
```

### Load Firmware
```bash
# Assemble firmware
cd ../../firmware
python3 ../scripts/asm.py i2s_clocks.s -o i2s_clocks.bin

# Load via UART (Basys3 onboard USB-UART at 115200 baud)
python3 ../scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware i2s_clocks.bin

# Verify: LED[0] = CPU running, scope on PMOD JA shows clocks
```

---

## Firmware Examples

### 1. UART TX/RX (firmware/uart.s)
- **3 Mbps** using Timer 0 NCO
- Pin 0 = TX, Pin 1 = RX
- Full duplex with ring buffers

### 2. SPI Master (firmware/spi.s)
- **25 MHz** using Timer 0 NCO
- Pin 0=SCK, 1=MOSI, 2=MISO, 3=CS
- Mode 0 (CPOL=0, CPHA=0)

### 3. I²C Master (firmware/i2c.s)
- **100 kHz** using Timer 0 NCO for SCL
- Pin 0=SDA (open-drain), Pin 1=SCL
- Open-drain emulation via DIR toggle

### 4. I2S Clocks (firmware/i2s_clocks.s)
- **MCLK 12.288 MHz** (Timer 0)
- **BCLK 3.072 MHz** (Timer 1)
- **LRCK 48 kHz** (Timer 2)
- Pure hardware clocks, zero CPU overhead

---

## Pin Assignments (Basys3 PMOD JA/JB)

| PMOD Pin | FPGA Pin | Protocol Emulator Pin | Default Use |
|----------|----------|----------------------|-------------|
| JA[0] | U16 | Pin 0 | UART TX / SPI SCK / I2S MCLK |
| JA[1] | V16 | Pin 1 | UART RX / SPI MOSI / I2S BCLK |
| JA[2] | U15 | Pin 2 | SPI MISO / I2S LRCK |
| JA[3] | V15 | Pin 3 | SPI CS / I2S SDOUT |
| JA[4] | J14 | Pin 4 | I2S SDIN / I²C SDA |
| JA[5] | J15 | Pin 5 | I²C SCL / GPIO |
| JA[6] | K16 | Pin 6 | GPIO |
| JA[7] | K15 | Pin 7 | GPIO |

| PMOD Pin | FPGA Pin | Protocol Emulator Pin | Default Use |
|----------|----------|----------------------|-------------|
| JB[0] | G16 | Pin 8* | Extended I/O |
| JB[1] | F16 | Pin 9* | Extended I/O |
| ... | ... | ... | ... |

*Note: ASIC has 8 pins. FPGA demo maps PMOD JB to extended address space for AXI peripherals.

---

## Tools Reference

### Assembler (`scripts/asm.py`)
```bash
python3 scripts/asm.py firmware/my_proto.s -o firmware/my_proto.bin
```

**Syntax:**
```assembly
; Comments with ;
.org 0x0000        ; Set origin

; Registers: x0-x15 (x0=zero)
; Labels end with :

; ALU
ADD  x1, x2, x3     ; x1 = x2 + x3
SUB  x1, x2, x3
AND  x1, x2, x3
OR   x1, x2, x3
XOR  x1, x2, x3
SLL  x1, x2, x3     ; Shift left
SRL  x1, x2, x3     ; Shift right logical

; Immediate (8-bit sign-extended)
ADDI x1, x2, 0x29   ; x1 = x2 + 0x29
LDI  x1, 0xFF       ; Load immediate (pseudo: ADDI x1, x0, imm)

; Branch (8-bit signed offset = ±127 instructions)
BEQZ x1, label      ; if x1==0 jump
BNEZ x1, label      ; if x1!=0 jump
BLTZ x1, label      ; if x1<0 jump
BGEZ x1, label      ; if x1>=0 jump
JAL  x1, label      ; jump and link (x1 = ret addr)
JMP  label          ; pseudo: JAL x0, label
CALL label          ; pseudo: JAL x14, label
RET                 ; pseudo: JALR x0, x14

; Custom timing
OUT   pin, val      ; Drive pin
DIR   pin, dir      ; Set direction (1=out)
WAIT  timer, cycles ; Stall for cycles
WAITE timer, event  ; Stall until event (1=rise, 2=fall, 4=capture)
PINSEL pin, source  ; Pin source (0=CPU, 1-8=Timer0-7)
TCFG  timer, mode   ; Timer mode
TUNING timer, val   ; NCO tuning (24-bit)
EVEN  timer, mask   ; Event enable
TIME  rd, timer     ; Read counter
CAPRD rd, timer     ; Read capture
HALT                ; Stop CPU

; Memory-mapped I/O (use TUNING/TCFG/PINSEL/DIR/OUT for peripherals)
; Direct peripheral access via custom instructions preferred
```

### UART Firmware Loader (`scripts/uart_load_firmware.py`)
```bash
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware.bin
```
- Protocol: 5-byte packets (CMD, ADDR_H, ADDR_L, DATA_H, DATA_L)
- CMD 0x01 = WRITE, CMD 0x02 = RUN

---

## Common Tasks

### Generate NCO Tuning Value
```python
def nco_tuning(freq_hz, clk_hz=50_000_000):
    return int(freq_hz * (1 << 24) / clk_hz)

# Examples
print(hex(nco_tuning(3_000_000)))    # UART 3M: 0xf5c29
print(hex(nco_tuning(25_000_000)))   # SPI 25M: 0x800000
print(hex(nco_tuning(100_000)))      # I2C 100k: 0x51eb
print(hex(nco_tuning(12_288_000)))   # I2S MCLK: 0x2d1a94
```

### Debug Firmware
```assembly
; Blink LED on pin 7 for visibility
debug_blink:
    LDI x1, 1
    OUT x7, x1
    WAIT x0, 1000000
    LDI x1, 0
    OUT x7, x1
    WAIT x0, 1000000
    RET

; Print register via UART (if UART TX firmware loaded)
debug_print_reg:
    ; x1 = register to print
    CALL uart_tx_byte
    RET
```

---

## Tiny Tapeout Submission

### Netlist
- **File**: `synth_emu_top_ihp_final_mapped.v`
- **Top module**: `emu_top_ihp`
- **Cells**: 9,110 IHP standard cells
- **Area**: 68,500 μm² (28.5% of 32K budget)

### TT Requirements
| Requirement | Value |
|-------------|-------|
| Clock | 50 MHz (20ns period) |
| Reset | `rst_n` active-low |
| I/O | 8 protocol pins + SPI host |
| Program load | Via SPI host interface |

### Submission Files
```
synth_emu_top_ihp_final_mapped.v   # Gate-level netlist
info.yaml                          # TT metadata
rtl/tt_um_protocol_emu.v           # TT wrapper
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| CPU doesn't start | RUN command not sent | Check SPI loader protocol |
| Wrong baud rate | NCO tuning wrong | Recalculate: `freq * 2^24 / 50M` |
| Pin not toggling | PINSEL not set | `PINSEL pin, source` before `DIR` |
| WAIT hangs forever | Timer not configured | `TCFG timer, NCO_CLK` first |
| Branch doesn't jump | Offset too large | Use `JALR` for far jumps |
| Assembler error | Unknown instruction | Check mnemonic spelling, case |

---

*For complete firmware development guide, see `FIRMWARE_GUIDE.md`. For I2S deep dive, see `I2S_TUTORIAL.md`.*
