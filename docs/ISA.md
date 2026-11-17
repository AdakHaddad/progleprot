# Protocol Emulator ISA Reference

## Overview
The PDIS (Protocol Data Interface Sequencer) is a tiny timing engine designed for bit-banging hardware protocols (UART, SPI, I²C, etc.) in firmware rather than fixed logic. It executes 32-bit instructions from a 256-word program RAM loaded via SPI host interface.

## Register File
- 4 general-purpose 16-bit registers: R0-R3
- Used for data manipulation, loop counters, CRC, etc.

## Call Stack
- 8-level hardware call stack for subroutine support (CALL/RET)

## Instruction Format
All instructions are 32 bits:
```
[31:28] = OPCODE (4 bits)
[27:0]  = OPERANDS (varies by instruction)
```

## Instruction Set (11 Instructions)

### 0x0 - NOP
No operation. Single cycle.
```
| 31:28 | 27:0 |
|  0x0  |  -   |
```

### 0x1 - DRIVE  [pin_mask, mode, reg_idx]
Drive output pins with specified values.
```
| 31:28 | 27:24 | 23:22 | 21:20 | 19:0 |
|  0x1  | mask  | mode  | reg   |  -   |
```
- `pin_mask[3:0]`: Which pins to drive (bit 0 = pin 0, etc.)
- `mode[1:0]`:
  - `00` (DRV_LOW)  - Drive pins low
  - `01` (DRV_HIGH) - Drive pins high  
  - `10` (DRV_Z)    - High-Z (release pins)
  - `11` (DRV_REG)  - Drive from register (lower 4 bits of reg_file[reg_idx])
- `reg_idx[1:0]`: Register index for DRV_REG mode

### 0x2 - WAIT  [wait_mode, count]
Wait for cycles or pin conditions.
```
| 31:28 | 23:20 | 19:16 | 15:0 |
|  0x2  | mode  |  -    | count|
```
- `wait_mode[3:2]` - Wait type:
  - `00` (WAIT_CYCLES) - Wait `count` clock cycles
  - `01` (WAIT_HIGH)   - Wait for any masked pin to go high (with timeout `count`)
  - `10` (WAIT_LOW)    - Wait for any masked pin to go low (with timeout `count`)
  - `11` (WAIT_CHANGE) - Wait for any masked pin to change from reg0[3:0] (with timeout `count`)
- `wait_mode[1:0]` - Pin mask for WAIT_HIGH/LOW/CHANGE
- `count[15:0]` - Cycle count or timeout

### 0x3 - SAMPLE  [dst_reg, pin_mask]
Sample input pins into register.
```
| 31:28 | 27:24 | 23:20 | 19:0 |
|  0x3  | dst   | mask  |  -   |
```
- `dst_reg[3:0]`: Destination register (0-3)
- `pin_mask[3:0]`: Which pins to sample (bits 0-3 = pins 0-3)
- Result: `reg_file[dst_reg] = {12'd0, pin_in & pin_mask}`

### 0x4 - SHIFT  [dst_reg, src_reg, shift_cnt, dir]
Shift register value left or right.
```
| 31:28 | 27:24 | 23:20 | 19:16 | 15 | 14:0 |
|  0x4  | dst   | src   | count |dir |  -   |
```
- `dst_reg`: Destination register
- `src_reg`: Source register
- `shift_cnt[3:0]`: Number of bits to shift (0-15)
- `dir`: Direction (1 = left, 0 = right)

### 0x5 - BRANCH  [cond_reg, target]
Conditional branch if register != 0.
```
| 31:28 | 23:20 | 19:16 | 15:8 | 7:0 |
|  0x5  | cond  |  -    |  -   |target|
```
- `cond_reg[3:0]`: Register to test
- `target[7:0]`: PC to jump to if reg != 0, else PC+1

### 0x6 - CRC  [dst_reg, data_reg]
Update CRC-16 (CCITT: 0x1021) with data register.
```
| 31:28 | 27:24 | 23:20 | 19:0 |
|  0x6  | dst   | src   |  -   |
```
- `dst_reg`: Register holding CRC accumulator (updated in place)
- `src_reg`: Register holding data byte (lower 8 bits used)
- Polynomial: x^16 + x^12 + x^5 + 1 (0x1021)

### 0x7 - CALL  [target]
Call subroutine. Pushes PC+1 to stack.
```
| 31:28 | 27:24 | 23:16 | 15:8 | 7:0 |
|  0x7  |  -    |  -    |  -   |target|
```
- `target[7:0]`: Subroutine entry PC
- Stack depth: 8 levels (overflow = error)

### 0x8 - RET
Return from subroutine. Pops PC from stack.
```
| 31:28 | 27:0 |
|  0x8  |  -   |
```
- Stack underflow = error

### 0x9 - LOAD  [dst_reg, immediate]
Load 16-bit immediate into register.
```
| 31:28 | 27:24 | 23:16 | 15:0 |
|  0x9  | dst   |  -    | imm  |
```

### 0xA - XOR  [dst_reg, src1_reg, src2_reg]
Bitwise XOR of two registers.
```
| 31:28 | 27:24 | 23:20 | 19:16 | 15:0 |
|  0xA  | dst   | src1  | src2  |  -   |
```
- `reg_file[dst] = reg_file[src1] ^ reg_file[src2]`

## Pin Mapping (Tiny Tapeout IHP)
| Signal | Pin | Description |
|--------|-----|-------------|
| ui_in[7:0] | pins_in[7:0] | Protocol pin inputs |
| uo_out[7:0] | pins_out[7:0] | Protocol pin outputs (when OE=1) |
| uio_in[0] | SPI SCK | Host interface clock |
| uio_in[1] | SPI MOSI | Host interface data in |
| uio_in[2] | SPI CS_N | Host interface chip select (active low) |
| uio_out[0] | SPI MISO | Host interface data out (always 0) |
| uio_out[1] | seq_done | Sequencer done flag |
| uio_out[2] | seq_error | Sequencer error flag |
| uio_out[4:3] | host_state | Host interface state |

## Host Interface SPI Protocol
Commands are 64 bits, MSB-first:
```
[63:32] = data (32 bits)
[31:16] = addr (16 bits, lower 8 used)
[15:8]  = cmd (8 bits)
[7:0]   = padding (ignored)
```

Commands:
- `0x01` WRITE: Write `data` to program RAM at `addr`, update prog_len
- `0x02` READBACK: Not implemented (reserved)
- `0x03` RUN: Start sequencer with program length = `addr[7:0]`

## Example: UART TX (9600 baud @ 10MHz clk = 1041 cycles/bit)

```verilog
// Start bit (low)
INS_DRIVE(4'h1, 2'b00, 2'd0)  // Pin 0 low
INS_WAIT(4'd0, 16'd1041)       // Wait 1041 cycles

// 8 data bits (LSB first) - example sending 0x55 (01010101)
INS_DRIVE(4'h1, 2'b01, 2'd0)  // Pin 0 high (bit 0 = 1)
INS_WAIT(4'd0, 16'd1041)
INS_DRIVE(4'h1, 2'b00, 2'd0)  // Pin 0 low (bit 1 = 0)
INS_WAIT(4'd0, 16'd1041)
... repeat for all 8 bits ...

// Stop bit (high)
INS_DRIVE(4'h1, 2'b01, 2'd0)
INS_WAIT(4'd0, 16'd1041)
```

## Example: SPI Master (Mode 0, CPOL=0, CPHA=0)
```verilog
// Setup: Pin 0=SCK, Pin 1=MOSI, Pin 2=CS (active low)
INS_DRIVE(4'h7, 2'b01, 2'd0)  // CS high, SCK low, MOSI low
INS_DRIVE(4'h4, 2'b00, 2'd0)  // CS low (start transaction)

// For each bit (MSB first):
INS_DRIVE(4'h2, 2'b01, 2'd0)  // MOSI = bit value (reg or immediate)
INS_DRIVE(4'h1, 2'b01, 2'd0)  // SCK high (sample on rising edge)
INS_WAIT(4'd0, 16'd10)        // Half cycle
INS_DRIVE(4'h1, 2'b00, 2'd0)  // SCK low
INS_WAIT(4'd0, 16'd10)        // Half cycle

// Sample MISO if needed:
INS_SAMPLE(4'd0, 4'h0)        // Sample pin 3 (MISO) into R0

INS_DRIVE(4'h4, 2'b01, 2'd0)  // CS high (end transaction)
```

## Example: I²C Master
```verilog
// I²C uses open-drain: drive low or release (Z)
// Pin 0 = SDA, Pin 1 = SCL

// Start condition: SDA falls while SCL high
INS_DRIVE(4'h3, 2'b01, 2'd0)  // SDA=1, SCL=1 (idle)
INS_WAIT(4'd0, 16'd10)
INS_DRIVE(4'h1, 2'b00, 2'd0)  // SDA=0 (start)
INS_WAIT(4'd0, 16'd10)
INS_DRIVE(4'h2, 2'b00, 2'd0)  // SCL=0

// For each bit:
INS_DRIVE(4'h1, 2'b01, 2'd0)  // SDA = bit value (1=release, 0=drive low)
INS_WAIT(4'd0, 16'd5)
INS_DRIVE(4'h2, 2'b01, 2'd0)  // SCL high
INS_WAIT(4'd0, 16'd10)
// Sample SDA if reading
INS_SAMPLE(4'd0, 4'h1)
INS_DRIVE(4'h2, 2'b00, 2'd0)  // SCL low
INS_WAIT(4'd0, 16'd5)

// Stop condition: SDA rises while SCL high
INS_DRIVE(4'h1, 2'b00, 2'd0)  // SDA=0
INS_DRIVE(4'h2, 2'b01, 2'd0)  // SCL=1
INS_WAIT(4'd0, 16'd10)
INS_DRIVE(4'h1, 2'b01, 2'd0)  // SDA=1 (stop)
```

## Timing Considerations
- Clock frequency: Up to ~50MHz (TT IHP limit)
- Instruction latency: 1 cycle (except WAIT which takes multiple)
- Pin sampling: Combinational read in SAMPLE instruction
- Pin driving: Registered output (1 cycle latency from DRIVE to pin change)
- Max program length: 256 instructions
