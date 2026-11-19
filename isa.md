# Protocol Emulator ASIC - ISA Specification

## Overview
16-bit RISC-like CPU with custom timing instructions for cycle-accurate protocol emulation.

## Instruction Format (16-bit)

```
┌─────────────────────────────────────────────────────────────┐
│                    INSTRUCTION ENCODING                     │
├──────┬──────┬──────┬──────┬──────┬──────┬──────┬────────────┤
│ 15-12│ 11-8 │  7-4 │  3-0 │      Description               │
├──────┼──────┼──────┼──────┼────────────────────────────────┤
│ OP   │ rd   │ rs1  │ rs2  │ ALU ops (ADD, SUB, etc.)       │
│ 0x8  │ rd   │ imm8 │      │ Immediate ops (ADDI, ORI)      │
│ 0xF  │ funct│ rs1  │ rs2  │ Custom timing instructions     │
└──────┴──────┴──────┴──────┴────────────────────────────────┘
```

## Opcode Map

| Opcode | Mnemonic | Format | Description |
|--------|----------|--------|-------------|
| 0x0    | ALU      | R-type | ALU operations (see funct) |
| 0x8    | ADDI     | I-type | Add sign-extended immediate |
| 0x9    | ORI      | I-type | OR zero-extended immediate |
| 0xC    | MEM      | I-type | Memory ops (LOAD/STORE) - TBD |
| 0xE    | BRANCH   | B-type | Branch ops (BEQ, BNE, etc.) - TBD |
| 0xF    | CUSTOM   | Custom | Timing/peripheral instructions |

## ALU Funct Codes (opcode 0x0)

| Funct | Mnemonic | Operation |
|-------|----------|-----------|
| 0x0   | ADD      | rd = rs1 + rs2 |
| 0x1   | SUB      | rd = rs1 - rs2 |
| 0x2   | AND      | rd = rs1 & rs2 |
| 0x3   | OR       | rd = rs1 \| rs2 |
| 0x4   | XOR      | rd = rs1 ^ rs2 |
| 0x5   | SLT      | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| 0x6   | SLL      | rd = rs1 << rs2[3:0] |
| 0x7   | SRL      | rd = rs1 >> rs2[3:0] |
| 0x8   | SRA      | rd = $signed(rs1) >>> rs2[3:0] |

## Immediate Instructions

| Opcode | Mnemonic | Format | Operation |
|--------|----------|--------|-----------|
| 0x8    | ADDI     | rd, imm8 | rd = 0 + sign_ext(imm8) |
| 0x9    | ORI      | rd, imm8 | rd = 0 | zero_ext(imm8) |

## Custom Timing Instructions (opcode 0xF)

Format: `[15:12]=0xF, [11:8]=funct, [7:4]=rs1, [3:0]=rs2/rd`

| Funct | Mnemonic | Operands | Description |
|-------|----------|----------|-------------|
| 0x0   | OUT      | pin, val | Drive pin from register bit 0 |
| 0x1   | DIR      | pin, dir | Set pin direction (0=in, 1=out) |
| 0x2   | WAIT     | timer, cycles | Stall CPU for N cycles |
| 0x3   | WAITE    | timer, event | Stall until timer event |
| 0x4   | TIME     | rd, timer | Read timer counter/capture → rd |
| 0x5   | TCFG     | timer, config | Configure timer mode |
| 0x6   | TUNING   | timer, val | Set NCO tuning word |
| 0x7   | PINSEL   | pin, src | Select pin source (0=CPU, 1-8=Timer0-7) |
| 0x8   | EVEN     | timer, mask | Enable timer events |
| 0x9   | SWAP     | - | Trigger program bank swap |
| 0xA   | VERIFY   | rd | Read host CRC → rd |
| 0xB   | CAPRD    | rd, timer | Read capture register → rd |
| 0xF   | HALT     | - | Stop CPU execution |

### Custom Instruction Details

**OUT pin, val_reg**
- `pin = rs1[3:0]` (0-7)
- `val = rs2[0]` (bit 0 of rs2)
- Writes to pin matrix REG_OUT

**DIR pin, dir_reg**
- `pin = rs1[3:0]`
- `dir = rs2[0]`
- Writes to pin matrix REG_DIR (OR for set, REG_DIR_CLR for clear)

**WAIT timer_reg, cycles_reg**
- `timer = rs1[3:0]` (0-7)
- `cycles = rs2[15:0]`
- Stalls pipeline for N cycles

**WAITE timer_reg, event_reg**
- `timer = rs1[3:0]`
- `event = rs2[7:0]` (event mask)
- Stalls until timer_event[timer] matches mask

**TIME rd, timer_reg**
- `rd = rd` (destination register)
- `timer = rs1[3:0]`
- Reads timer counter → rd

**TCFG timer_reg, config_reg**
- `timer = rs1[3:0]`
- `config = rs2[7:0]` (mode + config)
- Writes to timer REG_MODE

**TUNING timer_reg, tuning_reg**
- `timer = rs1[3:0]`
- `tuning = rs2` (16-bit value)
- If `rs2[8] = 0`: writes low 8 bits to REG_TUNING
- If `rs2[8] = 1`: writes 16 bits to REG_TUNING_H

**PINSEL pin_reg, src_reg**
- `pin = rs1[3:0]` (0-7)
- `src = rs2[3:0]` (0=CPU, 1-8=Timer0-7)
- Writes to pin matrix REG_SEL (pins 0-3) or REG_SEL_H (pins 4-7)
- Value shifted by `pin * 4` bits

## Memory Map

| Address Range | Peripheral | Size | Description |
|---------------|------------|------|-------------|
| 0x0000-0x0FFF | Program RAM | 4KB | Active firmware bank |
| 0x1000-0x17FF | Boot ROM | 2KB | Factory firmware |
| 0xF000-0xF07F | Timers | 128B | 8× timer (16B each) |
| 0xF100-0xF10F | Pin Matrix | 16B | Crossbar config |
| 0xF200-0xF207 | Host IF | 8B | SPI slave status |

### Timer Register Map (per timer, 16 bytes = 8 registers)

| Offset | Register | Bits | Description |
|--------|----------|------|-------------|
| 0x0    | TUNING   | 7:0  | NCO increment low byte |
| 0x1    | TUNING_H | 15:0 | NCO increment high 16 bits |
| 0x2    | COUNTER  | 15:0 | Counter value |
| 0x3    | CAPTURE  | 15:0 | Capture register |
| 0x4    | COMPARE  | 15:0 | Compare value |
| 0x5    | MODE     | 7:0  | Timer mode |
| 0x6    | EV_EN    | 7:0  | Event enables |
| 0x7    | EV_ST    | 7:0  | Event status (read clears) |

### Timer Modes

| Mode | Name | Description |
|------|------|-------------|
| 0x0  | OFF | Disabled |
| 0x1  | COUNT_UP | Increment on clk |
| 0x2  | COUNT_DOWN | Decrement on clk |
| 0x3  | NCO_CLK | NCO MSB as clock output |
| 0x4  | NCO_VAR | Variable duty (counter vs compare) |
| 0x5  | PWM | PWM output (counter < compare) |
| 0x6  | CAPTURE | Capture on pin edges |
| 0x7  | MEASURE | Measure pulse width/period |

### Pin Matrix Register Map

| Offset | Register | Bits | Description |
|--------|----------|------|-------------|
| 0x0    | DIR      | 7:0  | Direction (OR write to set) |
| 0x1    | SEL      | 15:0 | Source select pins 0-3 (4 bits each) |
| 0x2    | SEL_H    | 15:0 | Source select pins 4-7 (4 bits each) |
| 0x3    | PULL     | 15:0 | Pull config (2 bits per pin) |
| 0x4    | OUT      | 7:0  | CPU output values (when SEL=0) |
| 0x5    | IN       | 7:0  | Pin input values (read) |
| 0x6    | DIR_CLR  | 7:0  | Clear direction bits |

### Pin Source Select Values (4 bits per pin)

| Value | Source |
|-------|--------|
| 0x0   | CPU (OUT register) |
| 0x1   | Timer 0 NCO |
| 0x2   | Timer 1 NCO |
| 0x3   | Timer 2 NCO |
| 0x4   | Timer 3 NCO |
| 0x5   | Timer 4 NCO |
| 0x6   | Timer 5 NCO |
| 0x7   | Timer 6 NCO |
| 0x8   | Timer 7 NCO |
| 0x9   | Timer 0 PWM |
| 0xA   | Timer 1 PWM |
| 0xB   | Timer 2 PWM |
| 0xC   | Timer 3 PWM |
| 0xD   | Timer 4 PWM |
| 0xE   | Timer 5 PWM |
| 0xF   | Timer 6 PWM |

## Pipeline

4-stage: IF → ID → EX → WB

- **IF**: Fetch instruction from program memory (PC is byte address)
- **ID**: Decode, register read with forwarding, ALU compute
- **EX**: Memory/peripheral access, wait counter decrement
- **WB**: Register writeback

### Forwarding
- EX → ID: ALU result
- WB → ID: Writeback data
- ID → ID: Computed ALU result for next instruction

## Register File

16 general-purpose registers (x0-x15)
- x0 hardwired to 0
- 16-bit width

## NCO Frequency Formula

```
f_out = (tuning × f_clk) / 2^24

Examples @ 50MHz:
- 25MHz:  tuning = 0x800000 (2^23)
- 12.5MHz: tuning = 0x400000
- 3Mbps UART: tuning = 0x0F5C29
- 100kHz I²C: tuning = 0x051EB8
- 400kHz I²C: tuning = 0x147AE1
```
