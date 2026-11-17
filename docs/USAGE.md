# Protocol Emulator ASIC — Usage Guide

## Overview
This is a reprogrammable protocol emulator ASIC for Tiny Tapeout IHP (130nm CMOS5L). It implements a tiny sequencer with custom instructions for cycle-accurate pin control, enabling firmware to implement any digital protocol (UART, SPI, I2C, CAN, USB-LS, etc.).

## Hardware Interface (TT Pinout)

### Dedicated Pins (ui_in / uo_out)
| Pin | Direction | Function |
|-----|-----------|----------|
| ui_in[0] | Input | Protocol Pin 0 (e.g., SPI SCK) |
| ui_in[1] | Input | Protocol Pin 1 (e.g., SPI MOSI) |
| ui_in[2] | Input | Protocol Pin 2 (e.g., SPI CS_N) |
| ui_in[3] | Input | Protocol Pin 3 (e.g., SPI MISO) |
| ui_in[4-7] | Input | Protocol Pins 4-7 |
| uo_out[0-7] | Output | Pin outputs when OE=1 |

### Host Interface (uio_in / uio_out / uio_oe)
| Pin | Direction | Function |
|-----|-----------|----------|
| uio_in[0] | Input | SPI SCK (host) |
| uio_in[1] | Input | SPI MOSI (host) |
| uio_in[2] | Input | SPI CS_N (host, active low) |
| uio_out[0] | Output | SPI MISO (host) |
| uio_out[1] | Output | Sequencer DONE flag |
| uio_out[2] | Output | Sequencer ERROR flag |
| uio_out[3-4] | Output | Host state |
| uio_oe[0-6] | Output | Pin OE[7:1] |
| uio_oe[7] | Output | Always 1 (MISO driven) |

## Firmware Loading (SPI Host Protocol)

### SPI Mode
- **Mode 0**: CPOL=0, CPHA=0
- **Clock**: Any frequency < 25MHz
- **Bit Order**: MSB first
- **Frame**: 64 bits = [DATA(32)][ADDR(16)][CMD(8)][PAD(8)]

### Commands
| CMD | Name | Format | Description |
|-----|------|--------|-------------|
| 0x01 | WRITE | addr(16) + data(32) | Write instruction to program RAM |
| 0x02 | READ | addr(16) | Read from program RAM |
| 0x03 | RUN | length(16) | Start sequencer with program length |

### Load Sequence Example
```python
# Pseudocode for host loader
def spi_write(addr, data):
    frame = (data << 24) | (addr << 8) | 0x01
    spi.transfer(frame.to_bytes(8, 'big'))

def spi_run(length):
    frame = (length << 8) | 0x03
    spi.transfer(frame.to_bytes(8, 'big'))

# Load program
spi_write(0x00, INS_LOAD(0, 7))   # R0 = bit counter
spi_write(0x01, INS_LOAD(1, 0))   # R1 = RX accumulator
spi_write(0x02, INS_SYNC(4, 1, 50000))  # Wait CS fall
spi_write(0x03, INS_SYNC(1, 0, 50000))  # Wait SCK rise
spi_write(0x04, INS_SHIFT(1, 1, 1, 1))  # Shift left
spi_write(0x05, INS_SAMPLE(2, 2))       # Sample MOSI
spi_write(0x06, INS_SHIFT(2, 2, 1, 0))  # Shift right
spi_write(0x07, INS_XOR(1, 1, 2))       # Accumulate
spi_write(0x08, INS_JUMP_LOOP(0, 3))    # Loop to SCK wait
spi_write(0x09, INS_DRIVE(8, 1, 3))     # Done flag

spi_run(10)  # Start with 10 instructions
```

## Instruction Set Reference

### Encoding (32-bit)
```
[31:28] = Opcode (4 bits)
[27:24] = Destination register (4 bits)
[23:20] = Source 1 / Pin mask / Wait mode (4 bits)
[19:16] = Source 2 / Shift count / Sync mode (4 bits)
[15:0]  = Immediate / Target address / Timeout (16 bits)
```

### Instructions

| Opcode | Mnemonic | Format | Description |
|--------|----------|--------|-------------|
| 0x0 | NOP | — | No operation |
| 0x1 | DRIVE | mask, mode, reg | Drive pins: mode=00 low, 01 high, 10 Z, 11 from reg |
| 0x2 | WAIT | mode, count | Wait cycles or pin level |
| 0x3 | SAMPLE | dst, mask | Sample pins into register |
| 0x4 | SHIFT | dst, src, cnt, dir | Shift register (dir=1: left, 0: right) |
| 0x5 | BRANCH | cond, target | Branch if reg != 0 |
| 0x6 | CRC | dst, src | CRC16-CCITT |
| 0x7 | CALL | target | Subroutine call |
| 0x8 | RET | — | Return from subroutine |
| 0x9 | LOAD | dst, val | Load immediate 16-bit |
| 0xA | XOR | dst, src1, src2 | Bitwise XOR |
| 0xB | SYNC | mask, mode, timeout | Edge/level sync with timeout |
| 0xC | JUMP | target/loop | Jump or loop decrement |

### SYNC Modes (wait_mode[5:4])
| Value | Name | Edge |
|-------|------|------|
| 00 | SYNC_RISE | Rising |
| 01 | SYNC_FALL | Falling |
| 10 | SYNC_ANY | Any edge |
| 11 | SYNC_LEVEL | Level match |

### JUMP_LOOP (opcode 0xC, bit[7:0]==0)
- Decrements loop_reg
- Jumps to target if result > 0
- Falls through when reaches 0

## Building Firmware

### Assembler Macros (in testbenches)
```verilog
function [31:0] INS_LOAD(input [3:0] dst, input [15:0] val);
    INS_LOAD = {4'd9, dst, 8'd0, val};
endfunction

function [31:0] INS_SYNC(input [3:0] pin_mask, input [1:0] sync_mode, input [15:0] timeout);
    INS_SYNC = {4'd11, pin_mask, sync_mode, 6'd0, timeout};
endfunction

function [31:0] INS_SAMPLE(input [3:0] dst, input [3:0] mask);
    INS_SAMPLE = {4'd3, dst, mask, 20'd0};
endfunction

function [31:0] INS_SHIFT(input [3:0] dst, input [3:0] src, input [3:0] cnt, input dir);
    INS_SHIFT = {4'd4, dst, src, cnt, dir, 15'd0};
endfunction

function [31:0] INS_XOR(input [3:0] dst, input [3:0] src1, input [3:0] src2);
    INS_XOR = {4'd10, dst, src1, src2, 16'd0};
endfunction

function [31:0] INS_JUMP_LOOP(input [3:0] loop_reg, input [7:0] target);
    INS_JUMP_LOOP = {4'd12, 4'd0, loop_reg, 4'd0, target, 8'd0};
endfunction

function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
    INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0};
endfunction
```

## Example Protocols

### UART TX (3 Mbps @ 50MHz)
- Use NCO timer for baud generation (tuning = 100,663,296)
- DRIVE pin with start bit, 8 data bits, stop bit
- WAIT timer for bit periods

### SPI Master (25 MHz)
- Use NCO timer for SCK generation (tuning = 201,326,592)
- DRIVE CS, SCK, MOSI pins
- SAMPLE MISO on SCK edge

### I2C Master (1 MHz)
- Pin matrix config for open-drain SDA/SCL
- WAITE for pin events (ACK detection)
- NCO for timing

## Simulation

```bash
# Run all core tests
cd sim
iverilog -g2012 -o spi.vvp -Isrc -Irtl tb_emu_spi_detect.v ../src/project.v ../rtl/pdis_sequencer.v ../rtl/prog_ram.v ../rtl/host_if.v
vvp spi.vvp

iverilog -g2012 -o uart.vvp -Isrc -Irtl tb_emu_uart.v ../src/project.v ../rtl/pdis_sequencer.v ../rtl/prog_ram.v ../rtl/prog_ram.v
vvp uart.vvp

iverilog -g2012 -o sync.vvp -Isrc -Irtl tb_emu_sync_jump.v ../src/project.v ../rtl/pdis_sequencer.v ../rtl/prog_ram.v ../rtl/host_if.v
vvp sync.vvp
```

## Vivado/Gate-Level Simulation

1. Synthesize with Yosys/Verilog-to-Routing
2. Generate netlist: `yosys -p "read_verilog ...; synth_ecp5; write_verilog synth.v"`
3. Run gate-level sim with SDF timing annotation

## Project Structure

```
progleprot/
├── src/
│   └── project.v           # Top-level include
├── rtl/
│   ├── tt_um_protocol_emu.v  # TT wrapper
│   ├── pdis_sequencer.v      # Main sequencer
│   ├── prog_ram.v            # Program RAM
│   └── host_if.v             # SPI host interface
├── rtl_legacy/             # Legacy M1-M6 modules (not integrated)
├── sim/
│   ├── tb_emu_spi_detect.v   # SPI detection test
│   ├── tb_emu_uart.v         # UART TX test
│   ├── tb_emu_sync_jump.v    # SYNC/JUMP test
│   ├── tb_host_if.v          # Host interface test
│   └── ... (other tests)
├── docs/
│   ├── VERIFICATION.md       # Test results
│   └── USAGE.md              # This file
├── plan.md                 # Project plan
├── architecture.md         # Architecture spec
└── Makefile                # Build automation
```
