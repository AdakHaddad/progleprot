# Firmware Development Guide — Protocol Emulator

## Overview

Firmware = Assembly code (`.s`) → Assembled to binary (`.bin`) → Loaded via UART/SPI → Executed by CPU

**The CPU runs YOUR firmware.** The protocol behavior is 100% defined by what you write.

---

## Toolchain

| Tool | File | Purpose |
|------|------|---------|
| Assembler | `scripts/asm.py` | `.s` → `.bin` (raw 16-bit words) |
| UART Loader | `scripts/uart_load_firmware.py` | Load `.bin` via USB-UART (Basys3) |
| SPI Loader | (host_if protocol) | Load `.bin` via SPI (ASIC) |

```bash
# Assemble
cd /home/muqtada/Documents/progleprot
python3 scripts/asm.py firmware/my_proto.s -o firmware/my_proto.bin

# Load (Basys3)
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware/my_proto.bin
```

---

## Assembly Syntax

### Basic Instructions

```assembly
; Comments start with ;
; Labels end with :

; Registers: r0-r15 (r0 = zero, r15 = stack pointer convention)
; Immediates: decimal, 0xHEX, 0bBINARY

; ALU (3-operand)
ADD  r1, r2, r3      ; r1 = r2 + r3
SUB  r1, r2, r3      ; r1 = r2 - r3
AND  r1, r2, r3
OR   r1, r2, r3
XOR  r1, r2, r3
SHL  r1, r2, r3      ; r1 = r2 << r3
SHR  r1, r2, r3      ; r1 = r2 >> r3

; ALU immediate (8-bit sign-extended)
ADDI r1, r2, 0x29    ; r1 = r2 + 0x29
SUBI r1, r2, -10
ANDI r1, r2, 0xFF
ORI  r1, r2, 0x0F

; Branch (8-bit signed offset = ±127 instructions)
BEQZ r1, label       ; if r1==0 jump
BNEZ r1, label       ; if r1!=0 jump
BLTZ r1, label       ; if r1<0 jump
BGEZ r1, label       ; if r1>=0 jump
JAL  r1, label       ; jump and link (r1 = return addr)
JALR r1, r2          ; jump register (r1 = ret, pc = r2)

; Memory (not implemented yet - use memory-mapped I/O)
; LOAD r1, [addr]
; STORE r1, [addr]

; Custom timing/peripheral instructions (opcode 0xF)
OUT   r0, r1         ; Drive pin[r0] = r1[0]
DIR   r0, r1         ; Pin[r0] direction = r1[0] (1=out, 0=in)
WAIT  r0, r1         ; Stall CPU for r1 cycles (uses timer r0)
WAITE r0, r1         ; Stall until timer r0 event mask r1
PINSEL r0, r1        ; Pin[r0] source = r1 (0=CPU, 1-8=Timer0-7)
TCFG  r0, r1         ; Timer[r0] mode = r1
TUNING r0, r1        ; Timer[r0] NCO tuning = r1 (24-bit across regs)
EVEN  r0, r1         ; Timer[r0] event enable = r1
TIME  r0, r1         ; Read timer[r0] counter → r1
CAPRD r0, r1         ; Read timer[r0] capture → r1
HALT                 ; Stop CPU

; Pseudo-ops
.org 0x0000          ; Set assembly address
.word 0x1234         ; Raw 16-bit word
ldi  r1, 0xABCD      ; Load immediate (assembler expands to ADDI)
```

---

## Memory Map (Firmware View)

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x0000-0x0FFF | Program RAM | R (fetch) | Your firmware (2048×16) |
| 0x1000-0x17FF | Boot ROM | R | Factory firmware |
| 0xF000-0xF00F | Timer 0 | RW | 16 bytes |
| 0xF010-0xF01F | Timer 1 | RW | 16 bytes |
| 0xF020-0xF02F | Timer 2 | RW | 16 bytes |
| 0xF030-0xF03F | Timer 3 | RW | 16 bytes |
| 0xF040-0xF04F | Timer 4 | RW | 16 bytes |
| 0xF050-0xF05F | Timer 5 | RW | 16 bytes |
| 0xF060-0xF06F | Timer 6 | RW | 16 bytes |
| 0xF070-0xF07F | Timer 7 | RW | 16 bytes |
| 0xF100 | Pin DIR | RW | 8 bits (1=out) |
| 0xF101 | Pin SEL[3:0] | RW | 4×4 bits (pins 0-3) |
| 0xF102 | Pin SEL[7:4] | RW | 4×4 bits (pins 4-7) |
| 0xF103 | Pin PULL | RW | 8×2 bits |
| 0xF104 | Pin OUT | RW | 8 bits (CPU drive) |
| 0xF105 | Pin IN | R | 8 bits (read) |
| 0xF106 | Pin OE | RW | 8 bits (output enable) |

### Timer Register Map (per timer, base = 0xF000 + timer×16)

| Offset | Name | Bits | Description |
|--------|------|------|-------------|
| +0x0 | TUNING[7:0] | RW | NCO phase increment byte 0 |
| +0x1 | TUNING[15:8] | RW | NCO phase increment byte 1 |
| +0x2 | TUNING[23:16] | RW | NCO phase increment byte 2 |
| +0x3 | Reserved | - | |
| +0x4 | COMPARE | RW | Compare value |
| +0x5 | MODE | RW | Timer mode (0-7) |
| +0x6 | EVEN | RW | Event enables |
| +0x7 | EV_ST | R | Event status (read clears) |

### Timer Modes (MODE register)

| Value | Mode | Description |
|-------|------|-------------|
| 0x0 | OFF | Disabled |
| 0x1 | COUNT_UP | Increment every cycle |
| 0x2 | COUNT_DOWN | Decrement, event at 0 |
| 0x3 | NCO_CLK | Output NCO MSB as 50% clock |
| 0x4 | NCO_VAR | Variable duty (counter vs compare) |
| 0x5 | PWM | PWM output (counter < compare) |
| 0x6 | CAPTURE | Latch counter on pin event |
| 0x7 | MEASURE | Pulse width / period measurement |

---

## NCO Frequency Calculation

```python
# f_out = (tuning × 50_000_000) / 2^24
# tuning = f_out × 2^24 / 50_000_000

def tuning(freq_hz):
    return int(freq_hz * (1 << 24) / 50_000_000)

# Common values @ 50MHz:
# UART 3M:      0x0F5C29
# SPI 25M:      0x800000
# SPI 12.5M:    0x400000
# I2C 100k:     0x051EB8
# I2C 400k:     0x147AE1
# CAN 500k:     0x19999A
# I2S MCLK 12.288M:  0x2D1A94
# I2S BCLK 3.072M:   0x0B46A5
# I2S LRCK 48k:      0x00199A
```

**Load 24-bit tuning across 3 bytes:**
```assembly
ldi r1, 0x29        ; Low byte
ldi r2, 0x5C        ; Mid byte
ldi r3, 0x0F        ; High byte
st [TIMER_BASE + TUNING], r1
st [TIMER_BASE + TUNING + 1], r2
st [TIMER_BASE + TUNING + 2], r3
```

---

## Pin Source Selection (PINSEL / Pin Matrix SEL registers)

| SEL Value | Pin Source |
|-----------|------------|
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
| 0xB | Timer 2 PWM |
| 0xC | Timer 3 PWM |
| 0xD | Timer 4 PWM |
| 0xE | Timer 5 PWM |
| 0xF | Timer 6 PWM |

**Via PINSEL instruction (dynamic):**
```assembly
PINSEL r0, r1        ; Pin[r0] source = r1
```

**Via memory-mapped SEL registers (static, 4 pins per register):**
```assembly
; SEL register at 0xF101: pins 0,1,2,3 (4 bits each)
; SEL register at 0xF102: pins 4,5,6,7
ldi r0, 0x1111        ; Pin0=T0, Pin1=T1, Pin2=T2, Pin3=T3
st [PIN_BASE + PIN_SEL], r0
```

---

## Complete Firmware Template

```assembly
; ============================================================
; my_protocol.s — Template for new protocol
; ============================================================

.org 0x0000

; ---- CONSTANTS ----
TIMER_BASE = 0xF000
PIN_BASE   = 0xF100

TUNING   = 0x00
MODE     = 0x05
COMPARE  = 0x04
EVEN     = 0x06
EV_ST    = 0x07

PIN_DIR     = 0x00
PIN_SEL     = 0x01
PIN_SEL_H   = 0x02
PIN_PULL    = 0x03
PIN_OUT     = 0x04
PIN_IN      = 0x05
PIN_OE      = 0x06

MODE_OFF        = 0x00
MODE_COUNT_UP   = 0x01
MODE_COUNT_DOWN = 0x02
MODE_NCO_CLK    = 0x03
MODE_NCO_VAR    = 0x04
MODE_PWM        = 0x05
MODE_CAPTURE    = 0x06
MODE_MEASURE    = 0x07

SRC_CPU     = 0x0
SRC_TIMER0  = 0x1
SRC_TIMER1  = 0x2
SRC_TIMER2  = 0x3
SRC_TIMER3  = 0x4
SRC_TIMER4  = 0x5
SRC_TIMER5  = 0x6
SRC_TIMER6  = 0x7
SRC_TIMER7  = 0x8

CFG_TIMER   = 0x01
CFG_CPU     = 0x02
CFG_PULLUP  = 0x04
CFG_PULLDOWN= 0x08

; ---- RESET VECTOR ----
reset:
    ldi r15, 0x0FFF      ; Stack pointer
    
    ; === HARDWARE SETUP ===
    ; Configure timers
    call setup_timers
    
    ; Configure pins
    call setup_pins
    
    ; === MAIN LOOP ===
main:
    call protocol_task
    jmp main

; ---- TIMER SETUP ----
setup_timers:
    ; Timer 0: Protocol clock (example: 3M UART)
    ldi r1, 0x29        ; tuning low
    ldi r2, 0x5C        ; tuning mid
    ldi r3, 0x0F        ; tuning high
    st [TIMER_BASE + TUNING], r1
    st [TIMER_BASE + TUNING + 1], r2
    st [TIMER_BASE + TUNING + 2], r3
    ldi r0, MODE_NCO_CLK
    st [TIMER_BASE + MODE], r0
    
    ; Timer 1: Another clock (example: 48k LRCK)
    ldi r1, 0x9A
    ldi r2, 0x00
    ldi r3, 0x00
    st [TIMER_BASE + 16 + TUNING], r1
    st [TIMER_BASE + 16 + TUNING + 1], r2
    st [TIMER_BASE + 16 + TUNING + 2], r3
    ldi r0, MODE_NCO_CLK
    st [TIMER_BASE + 16 + MODE], r0
    
    ret

; ---- PIN SETUP ----
setup_pins:
    ; Directions: pins 0-3 out, 4-7 in
    ldi r0, 0x0F
    st [PIN_BASE + PIN_DIR], r0
    
    ; Pin sources: 0=T0, 1=T1, 2=CPU, 3=CPU
    ldi r0, 0x0210    ; Pin3=CPU, Pin2=CPU, Pin1=T1, Pin0=T0
    st [PIN_BASE + PIN_SEL], r0
    
    ; Pull-ups on input pins
    ldi r0, 0xF0      ; Pins 4-7 pull-up
    st [PIN_BASE + PIN_PULL], r0
    
    ; Output enable
    ldi r0, 0x0F
    st [PIN_BASE + PIN_OE], r0
    
    ret

; ---- PROTOCOL TASK ----
protocol_task:
    ; Your state machine here
    ; Example: UART TX one byte
    ldi r7, 0x55        ; Data to send
    call uart_tx_byte
    ret

uart_tx_byte:
    ; Start bit (0)
    ldi r0, 0           ; Pin 0
    ldi r1, 0           ; Value 0
    OUT r0, r1
    ldi r8, 16          ; Cycles per bit (3M @ 50M = ~16)
    WAIT r0, r8         ; Timer 0, wait r8 cycles
    
    ; 8 data bits
    ldi r9, 8
tx_loop:
    AND r1, r7, 1       ; LSB
    OUT r0, r1
    SHR r7, r7, 1
    WAIT r0, r8
    DEC r9
    BNEZ r9, tx_loop
    
    ; Stop bit (1)
    ldi r1, 1
    OUT r0, r1
    WAIT r0, r8
    
    ret

; ---- VECTORS ----
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

## Build & Load Commands

```bash
cd /home/muqtada/Documents/progleprot

# 1. Assemble
python3 scripts/asm.py firmware/my_protocol.s -o firmware/my_protocol.bin

# 2. Load via UART (Basys3)
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware/my_protocol.bin

# 3. Verify on hardware
# - LED[0] = CPU running
# - LED[1] = CPU error  
# - LED[15:8] = Pin inputs
# - LED[7:2] = Pin outputs
# - Scope/logic analyzer on PMOD JA pins
```

---

## Existing Firmware Examples

| File | Protocol | Key Techniques |
|------|----------|----------------|
| `firmware/uart.s` | UART TX/RX @ 3Mbps | WAIT for bit timing, OUT for bit-bang |
| `firmware/spi.s` | SPI Master @ 25MHz | PINSEL for SCK (Timer NCO), WAITE for edges |
| `firmware/i2c.s` | I²C Master @ 100kHz | Open-drain emulation (DIR toggle), WAITE for ACK |
| `firmware/i2s_clocks.s` | I2S clock generation | 3 Timers as NCO (MCLK/BCLK/LRCK), Timer capture for frame sync |

---

## Debugging Firmware

### 1. LED Debug Registers
```assembly
; SW[3:0] selects register shown on LED[15:0]
; In hardware: dbg_reg_idx = sw[3:0]
```

### 2. Printf-Style Pin Toggle
```assembly
debug_pin:
    ldi r0, 7           ; Pin 7
    ldi r1, 1
    OUT r0, r1          ; High
    ldi r2, 10000
    WAIT r0, r2
    ldi r1, 0
    OUT r0, r1          ; Low
    ret
```

### 3. Simulation with VCD
```bash
# Create testbench (see sim/tb_emu_uart.v)
iverilog -g2012 -o sim.vvp -Isim -Irtl \
  sim/tb_my_proto.v rtl/emu_top.v rtl/cpu_core.v \
  rtl/timer_coproc.v rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v
vvp sim.vvp
gtkwave sim.vcd
```

### 4. Check Timer Events
```assembly
ld r0, [TIMER_BASE + EV_ST]  ; Read + clear events
and r0, r0, 0x01             ; Check bit 0
bnez r0, event_happened
```

---

## Common Patterns

### Wait N Microseconds
```assembly
; At 50MHz: 1 cycle = 20ns
; 1us = 50 cycles
; 1ms = 50000 cycles (needs 16-bit)
WAIT_US:
    ; r1 = microseconds
    ldi r2, 50
    MUL r1, r1, r2      ; r1 = us × 50
    WAIT r0, r1         ; Timer 0
    ret
```

### Pin Toggle with Timer NCO (Hardware Clock)
```assembly
; Instead of WAIT loop, route pin to Timer NCO
setup_pwm:
    ldi r0, MODE_PWM
    st [TIMER_BASE + MODE], r0
    ldi r0, 1000        ; Period
    st [TIMER_BASE + COMPARE], r0  ; Duty cycle
    ldi r1, SRC_TIMER0
    PINSEL r2, r1       ; Pin 2 = Timer 0 PWM
    ret
```

### State Machine Template
```assembly
proto_state_machine:
    ld r0, [STATE_VAR]
    
    ; State 0: IDLE
    beqz r0, state_idle
    
    ; State 1: TX
    ldi r1, 1
    beq r0, r1, state_tx
    
    ; State 2: RX
    ldi r1, 2
    beq r0, r1, state_rx
    
    jmp proto_done

state_idle:
    ; Check for start condition
    ld r1, [PIN_BASE + PIN_IN]
    and r1, r1, 0x01
    bnez r1, proto_done
    ldi r0, 1
    st [STATE_VAR], r0
    jmp proto_done

state_tx:
    ; Transmit logic
    call uart_tx_byte
    ldi r0, 0
    st [STATE_VAR], r0
    jmp proto_done

state_rx:
    ; Receive logic
    call uart_rx_byte
    ldi r0, 0
    st [STATE_VAR], r0

proto_done:
    ret
```

---

## Assembler Limitations (Current)

| Limitation | Workaround |
|------------|------------|
| No `MUL`/`DIV` instructions | Implement in software or use shifts |
| No `LOAD`/`STORE` | Use memory-mapped I/O (ST/LD to 0xFxxx) |
| Branch offset ±127 instructions | Use `JALR` for far jumps |
| 8-bit immediates only | Use multiple `ADDI`/`ORI` for 16-bit |
| No macros in asm.py | Use `.word` for raw instructions or preprocess |

---

## Workflow Summary

```
┌─────────────────────┐
│ 1. Design Protocol  │  Timing diagram, calculate NCO values
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ 2. Write Assembly   │  firmware/my_proto.s
│    (use template)   │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ 3. Assemble         │  python3 scripts/asm.py firmware/my_proto.s
│                     │    -o firmware/my_proto.bin
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ 4. Simulate (opt)   │  iverilog + testbench → VCD → gtkwave
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ 5. Load Hardware    │  python3 scripts/uart_load_firmware.py
│    (Basys3/ASIC)    │    --port /dev/ttyUSB0 --firmware my_proto.bin
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ 6. Verify           │  Scope on PMOD, check LEDs
│    on Pins          │
└─────────────────────┘
```

---

## Quick Reference Card

```assembly
; === REGISTERS ===
; r0 = zero (always 0)
; r1-r13 = general purpose
; r14 = link register (JAL)
; r15 = stack pointer

; === CUSTOM INSTRUCTIONS ===
OUT   pin, val      ; pin = val[0]
DIR   pin, dir      ; pin direction = dir[0]
WAIT  timer, cycles ; stall cycles
WAITE timer, mask   ; stall until event
PINSEL pin, src     ; pin source select
TCFG  timer, mode   ; timer mode
TUNING timer, val   ; NCO tuning (24-bit)
EVEN  timer, mask   ; event enable
TIME  rd, timer     ; read counter
CAPRD rd, timer     ; read capture
HALT                ; stop CPU

; === TIMER MODES ===
0=OFF 1=UP 2=DOWN 3=NCO_CLK 4=NCO_VAR 5=PWM 6=CAPTURE 7=MEASURE

; === PIN SOURCES ===
0=CPU 1=T0 2=T1 3=T2 4=T3 5=T4 6=T5 7=T6 8=T7 9=T0_PWM ...

; === MEMORY MAP ===
0xF000 = Timer0  0xF100 = Pin_DIR  0xF104 = Pin_OUT  0xF105 = Pin_IN
```

---

*Write firmware → Assemble → Load → Run. The protocol lives in YOUR code.*
