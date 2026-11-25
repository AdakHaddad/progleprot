# Firmware Development Guide — Protocol Emulator

## Overview

Firmware = Assembly code (`.s`) → Assembled to binary (`.bin`) → Loaded via UART/SPI → Executed by CPU

**The CPU runs YOUR firmware.** The protocol behavior is 100% defined by what you write.

---

## Toolchain

| Tool | File | Purpose |
|------|------|---------|
| Assembler | `scripts/asm.py` | `.s` → `.bin` (raw 16-bit words, big-endian) |
| UART Loader | `scripts/uart_load_firmware.py` | Load `.bin` via USB-UART (Basys3) |
| SPI Loader | `host_if` protocol | Load `.bin` via SPI (ASIC) |

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

; Registers: x0-x15 (x0 = zero, x15 = stack pointer convention)
; Immediates: decimal, 0xHEX, 0bBINARY

; ALU (3-operand)
ADD  x1, x2, x3      ; x1 = x2 + x3
SUB  x1, x2, x3      ; x1 = x2 - x3
AND  x1, x2, x3
OR   x1, x2, x3
XOR  x1, x2, x3
SLL  x1, x2, x3      ; x1 = x2 << x3[3:0]
SRL  x1, x2, x3      ; x1 = x2 >> x3[3:0]
SRA  x1, x2, x3      ; x1 = $signed(x2) >>> x3[3:0]
SLT  x1, x2, x3      ; x1 = (x2 < x3) ? 1 : 0 (signed)

; ALU immediate (8-bit sign-extended)
ADDI x1, x2, 0x29    ; x1 = x2 + 0x29
SUBI x1, x2, -10
ANDI x1, x2, 0xFF
ORI  x1, x2, 0x0F
XORI x1, x2, 0x55
SHLI x1, x2, 4       ; x1 = x2 << 4
SHRI x1, x2, 2       ; x1 = x2 >> 2

; Branch (8-bit signed offset = ±127 instructions)
BEQZ x1, label       ; if x1==0 jump
BNEZ x1, label       ; if x1!=0 jump
BLTZ x1, label       ; if x1<0 jump
BGEZ x1, label       ; if x1>=0 jump
JAL  x1, label       ; jump and link (x1 = return addr)
JALR x1, x2          ; jump register (x1 = ret, pc = x2)

; Pseudo-ops (assembler expands)
LDI  x1, 0xABCD      ; Load immediate → ADDI x1, x0, imm
JMP  label           ; JAL x0, label
CALL label           ; JAL x14, label
RET                  ; JALR x0, x14
NOP                  ; ADD x0, x0, x0

; Custom timing/peripheral instructions (opcode 0xF)
OUT   pin, val       ; Drive pin_out[pin] = val[0], pin_oe[pin]=1
DIR   pin, dir       ; Pin[pin] direction = dir[0] (1=out, 0=in)
WAIT  timer, cycles  ; Stall CPU for cycles (uses timer counter)
WAITE timer, event   ; Stall until timer event (1=rise, 2=fall, 4=capture)
PINSEL pin, source   ; Pin source: 0=CPU, 1=Timer0..8=Timer7
TCFG  timer, mode    ; Timer mode (see modes below)
TUNING timer, val    ; Timer NCO tuning (24-bit across regs)
EVEN  timer, mask    ; Timer event enable mask
TIME  rd, timer      ; Read timer counter → rd
CAPRD rd, timer      ; Read timer capture FIFO → rd
SWAP                 ; Atomic bank swap (staging → active)
VERIFY rd            ; rd = CRC32 of staging bank
HALT                 ; Stop CPU

; Directives
.org 0x0000          ; Set assembly address
.word 0x1234         ; Raw 16-bit word (big-endian in .bin)
```

### Timer Modes (for TCFG)

```assembly
; Mode constants
.equ MODE_OFF       = 0x00
.equ MODE_COUNT_UP  = 0x01
.equ MODE_COUNT_DN  = 0x02
.equ MODE_NCO_CLK   = 0x03    ; 50% duty NCO clock output
.equ MODE_NCO_VAR   = 0x04    ; Variable duty (uses COMPARE)
.equ MODE_PWM       = 0x05    ; PWM (COMPARE = duty)
.equ MODE_CAPTURE   = 0x08    ; Input capture on edge
.equ MODE_MEASURE   = 0x10    ; Period/pulse measurement
```

### Pin Sources (for PINSEL)

```assembly
.equ SRC_CPU     = 0x0
.equ SRC_TIMER0  = 0x1
.equ SRC_TIMER1  = 0x2
.equ SRC_TIMER2  = 0x3
.equ SRC_TIMER3  = 0x4
.equ SRC_TIMER4  = 0x5
.equ SRC_TIMER5  = 0x6
.equ SRC_TIMER6  = 0x7
.equ SRC_TIMER7  = 0x8
```

### WAITE Event Masks

```assembly
.equ EV_RISE   = 0x1    ; Rising edge
.equ EV_FALL   = 0x2    ; Falling edge
.equ EV_CAPT   = 0x4    ; Capture complete
```

---

## Memory Map (Firmware View)

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| 0x0000-0x07FF | Program RAM (Bank A) | R (fetch) | Active firmware (2048×16) |
| 0x0800-0x0FFF | Program RAM (Bank B) | R/W | Staging bank (ASIC only) |
| 0x1000-0x11FF | Boot ROM | R | Factory firmware (512×16) |
| 0xF000-0xF00F | Timer 0 | RW | Timer 0 registers |
| 0xF010-0xF01F | Timer 1 | RW | Timer 1 registers |
| 0xF020-0xF02F | Timer 2 | RW | Timer 2 registers |
| 0xF030-0xF03F | Timer 3 | RW | Timer 3 registers |
| 0xF040-0xF04F | Timer 4 | RW | Timer 4 registers |
| 0xF050-0xF05F | Timer 5 | RW | Timer 5 registers |
| 0xF060-0xF06F | Timer 6 | RW | Timer 6 registers |
| 0xF070-0xF07F | Timer 7 | RW | Timer 7 registers |
| 0xF100-0xF10F | Pin Matrix | RW | Pin configuration |
| 0xF200-0xF207 | Host Interface | R | Status, CRC, version |

### Timer Register Offsets (per timer, 16 bytes)

| Offset | Register | Description |
|--------|----------|-------------|
| 0x0 | NCO_INC_LOW | NCO tuning [7:0] |
| 0x1 | NCO_INC_MID | NCO tuning [15:8] |
| 0x2 | NCO_INC_HIGH | NCO tuning [23:16] |
| 0x3 | CONFIG | Mode, enable, polarity |
| 0x4 | COMPARE | Compare value |
| 0x5 | COUNTER | Counter value |
| 0x6 | CAPTURE | Capture FIFO read |
| 0x7 | EVENTS | Event status/clear |

### Pin Matrix Registers

| Addr | Register | Bits | Description |
|------|----------|------|-------------|
| 0xF100 | DIR | [7:0] | Pin directions (1=out) |
| 0xF101 | OUT | [7:0] | CPU pin output values |
| 0xF102 | IN | [7:0] | Pin input values (read-only) |
| 0xF103 | OE | [7:0] | Output enables |
| 0xF104 | SEL_LO | [15:0] | Pins 0-3 source (4 bits each) |
| 0xF105 | SEL_HI | [15:0] | Pins 4-7 source (4 bits each) |
| 0xF106 | PULL | [15:0] | Pull config (2 bits per pin) |
| 0xF107 | RISE | [7:0] | Rising edge detect |
| 0xF108 | FALL | [7:0] | Falling edge detect |

**Note:** Use `OUT/DIR/PINSEL/TCFG/TUNING/EVEN` custom instructions instead of direct memory access — they're faster and atomic.

---

## NCO Frequency Calculator

```python
# f_out = (tuning × 50MHz) / 2^24
# tuning = f_out × 2^24 / 50MHz

def nco_tuning(freq_hz, clk_hz=50_000_000):
    return int(freq_hz * (1 << 24) / clk_hz)

# Pre-calculated common values:
COMMON_TUNINGS = {
    # UART
    'UART_3M':      0x0F5C29,  # 3,000,000
    'UART_2M':      0x0A3D70,  # 2,000,000
    'UART_1M':      0x051EB8,  # 1,000,000
    'UART_115200':  0x0005EB,  # 115,200
    'UART_9600':    0x000079,  # 9,600
    
    # SPI
    'SPI_25M':      0x800000,  # 25,000,000
    'SPI_12M5':     0x400000,  # 12,500,000
    'SPI_6M25':     0x200000,  # 6,250,000
    'SPI_1M':       0x051EB8,  # 1,000,000
    
    # I²C
    'I2C_100K':     0x0051EB,  # 100,000
    'I2C_400K':     0x0147AE,  # 400,000
    'I2C_1M':       0x051EB8,  # 1,000,000
    
    # I2S (48 kHz base)
    'I2S_MCLK_256': 0x2D1A94,  # 12,288,000 (48k × 256)
    'I2S_MCLK_512': 0x5A3529,  # 24,576,000 (48k × 512)
    'I2S_BCLK_32':  0x0B46A5,  # 3,072,000 (48k × 64)
    'I2S_BCLK_64':  0x168D4A,  # 6,144,000 (48k × 128)
    'I2S_LRCK':     0x00199A,  # 48,000
    
    # CAN
    'CAN_500K':     0x01999A,  # 500,000
    'CAN_250K':     0x00CCCD,  # 250,000
    'CAN_125K':     0x006666,  # 125,000
    
    # USB Low Speed
    'USB_LS':       0x07AE14,  # 1,500,000
}
```

### Writing 24-bit Tuning (split across 3 registers)

```assembly
; Timer 0 = 3 Mbps UART (0x0F5C29)
LDI  x1, 0x29        ; Low byte
TUNING x0, x1
LDI  x1, 0x5C        ; Mid byte
TUNING x0, x1
LDI  x1, 0x0F        ; High byte
TUNING x0, x1
TCFG   x0, MODE_NCO_CLK
```

---

## Firmware Template

```assembly
        .org 0x0000

; ============================================================================
; CONSTANTS
; ============================================================================
.equ MODE_OFF       = 0x00
.equ MODE_COUNT_UP  = 0x01
.equ MODE_NCO_CLK   = 0x03
.equ MODE_CAPTURE   = 0x08

.equ SRC_CPU        = 0x0
.equ SRC_TIMER0     = 0x1

.equ TIMER_BASE     = 0xF000
.equ PIN_BASE       = 0xF100

; Protocol-specific tuning
.equ BAUD_TUNING_LO = 0x29
.equ BAUD_TUNING_MID = 0x5C
.equ BAUD_TUNING_HI = 0x0F

; ============================================================================
; RESET / INITIALIZATION
; ============================================================================
reset:
    ; Stack pointer
    LDI  x15, 0x0FFF
    
    ; Configure pins
    ; Pin 0 = TX output (Timer 0 NCO)
    DIR  x0, x1          ; x1=1 for output
    LDI  x1, SRC_TIMER0
    PINSEL x0, x1        ; Pin 0 → Timer 0
    
    ; Pin 1 = RX input
    LDI  x1, 0
    DIR  x1, x1          ; Pin 1 = input
    LDI  x1, SRC_CPU
    PINSEL x1, x1        ; Pin 1 → CPU
    
    ; Configure Timer 0 as NCO for baud clock
    LDI  x1, BAUD_TUNING_LO
    TUNING x0, x1
    LDI  x1, BAUD_TUNING_MID
    TUNING x0, x1
    LDI  x1, BAUD_TUNING_HI
    TUNING x0, x1
    LDI  x1, MODE_NCO_CLK
    TCFG   x0, x1

; ============================================================================
; MAIN PROGRAM
; ============================================================================
main:
    ; Your protocol implementation here
    CALL uart_tx_init
    CALL uart_rx_init
    
main_loop:
    ; Poll for RX data
    CALL uart_rx_poll
    BNEZ x1, got_data
    
    ; Check for TX request
    CALL uart_tx_poll
    
    JMP  main_loop

got_data:
    ; Process received byte in x1
    CALL process_byte
    JMP  main_loop

; ============================================================================
; SUBROUTINES
; ============================================================================

; UART TX: send byte in x7
uart_tx_byte:
    ; Start bit
    LDI  x1, 0
    OUT  x0, x1
    WAIT x0, x8        ; x8 = bit_time_cycles
    
    ; 8 data bits
    LDI  x9, 8
tx_loop:
    AND  x1, x7, 1     ; Get LSB
    OUT  x0, x1
    SHR  x7, x7, 1
    WAIT x0, x8
    DEC  x9
    BNEZ x9, tx_loop
    
    ; Stop bit
    LDI  x1, 1
    OUT  x0, x1
    WAIT x0, x8
    RET

; UART RX: receive byte → x7
uart_rx_byte:
    ; Wait for start bit (falling edge)
    WAITE x0, EV_FALL
    
    ; Wait 1.5 bit times to center of first data bit
    LDI  x1, 24        ; 1.5 × 16
    WAIT x0, x1
    
    ; 8 data bits
    LDI  x9, 8
    LDI  x7, 0
rx_loop:
    WAIT x0, x8        ; Wait 1 bit time
    IN   x1, x1        ; Read pin 1
    SHR  x7, x7, 1     ; Shift right (LSB first)
    OR   x7, x7, x1    ; Insert bit
    DEC  x9
    BNEZ x9, rx_loop
    
    ; Wait for stop bit
    WAIT x0, x8
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

## Common Patterns

### Bit-Bang Output Loop
```assembly
; Send N bits from register, MSB first
send_bits_msb:
    LDI  x9, 8          ; Bit count
send_loop:
    SLL  x10, x7, 7     ; MSB to bit 7
    SHR  x10, x10, 7    ; Isolate
    OUT  pin, x10
    WAIT timer, cycles
    SLL  x7, x7, 1      ; Shift left for next MSB
    DEC  x9
    BNEZ x9, send_loop
    RET
```

### Bit-Bang Input Loop
```assembly
; Receive N bits to register, MSB first
recv_bits_msb:
    LDI  x9, 8
    LDI  x7, 0
recv_loop:
    WAIT timer, cycles
    IN   x10, pin
    SLL  x7, x7, 1
    OR   x7, x7, x10
    DEC  x9
    BNEZ x9, recv_loop
    RET
```

### Ring Buffer (TX)
```assembly
; x1 = tx_head, x2 = tx_tail, x3 = buffer_base
tx_push:
    ; Check full: (head + 1) & MASK == tail
    ADD  x4, x1, 1
    AND  x4, x4, 0x1F   ; MASK = 31 (32-byte buffer)
    BEQZ x4, tx_full    ; If equal, full
    ; Store
    ADD  x5, x3, x1
    ST   [x5], x7       ; Store byte
    ; Advance head
    MOV  x1, x4
    RET
tx_full:
    ; Handle overflow
    RET
```

### Timer-Based Delay (Microseconds)
```assembly
; Delay using Timer 0 in COUNT_UP mode
delay_us:
    ; x1 = microseconds
    ; Timer 0 counts at 50MHz = 50 cycles/μs
    MUL  x2, x1, 50     ; Cycles needed (needs MUL routine)
    TCFG x0, MODE_COUNT_UP
    ; Reset counter
    LDI  x3, 0
    ; (write to timer counter register)
    WAIT x0, x2
    RET
```

---

## Debugging Tips

### 1. LED Blink for Visibility
```assembly
debug_blink:
    LDI  x1, 1
    OUT  x7, x1         ; Pin 7 = LED
    WAIT x0, 1000000
    LDI  x1, 0
    OUT  x7, x1
    WAIT x0, 1000000
    RET
```

### 2. UART Print Register
```assembly
; Print x1 as hex via UART (assumes UART TX firmware loaded)
debug_print_hex:
    ; x1 = value to print
    ; Output 4 hex nibbles
    LDI  x2, 4
hex_loop:
    AND  x3, x1, 0xF
    ; Convert to ASCII
    CMP  x3, 10
    BLTZ x3, is_digit
    ADDI x3, x3, 'A' - 10
    JMP  put_char
is_digit:
    ADDI x3, x3, '0'
put_char:
    CALL uart_tx_byte   ; x3 = char
    SRL  x1, x1, 4
    DEC  x2
    BNEZ x2, hex_loop
    RET
```

### 3. Single-Step with Breakpoint
```assembly
; Insert HALT to stop CPU at specific point
debug_break:
    HALT
    ; CPU stops, inspect registers via debug port
```

---

## Simulation Testing

```bash
# Run UART testbench
cd /home/muqtada/Documents/progleprot
iverilog -o sim_uart.vvp -I rtl -I sim \
  rtl/cpu_core.v rtl/timer_coproc.v rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v rtl/emu_top.v \
  sim/tb_emu_uart.v
vvp sim_uart.vvp

# Run SPI testbench
iverilog -o sim_spi.vvp ... sim/tb_emu_spi_master.v
vvp sim_spi.vvp

# Run I2C testbench
iverilog -o sim_i2c.vvp ... sim/tb_emu_i2c_master.v
vvp sim_i2c.vvp
```

---

## Instruction Encoding Reference

| Instruction | Encoding (16-bit) |
|-------------|-------------------|
| ADD x1,x2,x3 | 0x0123 (op=0, rd=1, rs1=2, rs2=3) |
| ADDI x1,0x29 | 0x8129 (op=8, rd=1, imm=0x29) |
| BEQZ x1,label | 0xA1xx (op=A, rs1=1, offset=xx) |
| JAL x1,label | 0xE1xx (op=E, rd=1, offset=xx) |
| OUT pin,val | 0xF0pv (op=F, funct=0, rs1=pin, rs2=val) |
| DIR pin,dir | 0xF1pd (op=F, funct=1, rs1=pin, rs2=dir) |
| WAIT tmr,cyc | 0xF2tc (op=F, funct=2, rs1=tmr, rs2=cyc) |
| WAITE tmr,evt | 0xF3te (op=F, funct=3, rs1=tmr, rs2=evt) |
| PINSEL pin,src | 0xF7ps (op=F, funct=7, rs1=pin, rs2=src) |
| TCFG tmr,mode | 0xF5tm (op=F, funct=5, rs1=tmr, rs2=mode) |
| TUNING tmr,val | 0xF6tv (op=F, funct=6, rs1=tmr, rs2=val) |
| HALT | 0xFFFF |

---

*For protocol-specific examples, see `I2S_TUTORIAL.md` and firmware/*.s files.*
