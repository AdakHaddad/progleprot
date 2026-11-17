# Protocol Emulator - Usage Guide

## Quick Start

### Prerequisites
- iverilog (for simulation)
- yosys (for synthesis - optional)
- make

### Run Tests
```bash
cd /home/muqtada/Documents/progleprot

# Host interface unit test
iverilog -g2012 -o sim.vvp -Isrc -Irtl sim/tb_host_if.v rtl/host_if.v
vvp sim.vvp

# UART TX integration test  
iverilog -g2012 -o sim.vvp -Isrc -Irtl sim/tb_emu_uart.v src/project.v rtl/pdis_sequencer.v rtl/prog_ram.v rtl/host_if.v
vvp sim.vvp

# SAMPLE instruction test
iverilog -g2012 -o sim.vvp -Isrc -Irtl sim/tb_emu_sample.v src/project.v rtl/pdis_sequencer.v rtl/prog_ram.v rtl/host_if.v
vvp sim.vvp
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    tt_um_protocol_emu                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   host_if    │──│  prog_ram    │──│ pdis_sequencer   │  │
│  │  (SPI slave) │  │ (256×32 dual)│  │  (ISA executor)  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│         │                │                   │              │
│         ▼                ▼                   ▼              │
│    SPI pins         Program RAM          Pin I/O (8 pins)   │
└─────────────────────────────────────────────────────────────┘
```

## Loading Firmware via SPI

The host interface accepts 64-bit SPI commands (MSB first):

```
Bit:  63........................32  31..........16  15......8  7..0
      [      32-bit DATA       ] [  16-bit ADDR  ] [ 8b CMD ] [pad]
```

### Command: WRITE (0x01)
Write 32-bit instruction to program RAM at address.
- `addr`: Program address (0-255)
- `data`: 32-bit instruction encoding
- Updates `seq_prog_len` to max(addr+1) automatically

### Command: RUN (0x03)
Start sequencer execution.
- `addr`: Program length (number of instructions to execute)
- `data`: Ignored (set to 0)
- Asserts `seq_start` pulse for 1 cycle on CS rise

### SPI Timing (Mode 0)
- SCK idle low
- MOSI sampled on SCK rising edge
- CS_N active low
- 64 clocks per command

## Writing Firmware

### Instruction Helpers (Verilog)
```verilog
function [31:0] INS_NOP;
    begin INS_NOP = 32'h00000000; end
endfunction

function [31:0] INS_LOAD(input [3:0] dst, input [15:0] val);
    begin INS_LOAD = {4'd9, dst, 8'd0, val}; end
endfunction

function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
    begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
endfunction

function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
    begin INS_WAIT = {4'd2, wait_mode, 12'd0, count}; end
endfunction

function [31:0] INS_SAMPLE(input [3:0] dst, input [3:0] mask);
    begin INS_SAMPLE = {4'd3, dst, mask, 20'd0}; end
endfunction

function [31:0] INS_SHIFT(input [3:0] dst, input [3:0] src, input [3:0] cnt, input dir);
    begin INS_SHIFT = {4'd4, dst, src, cnt, dir, 11'd0}; end
endfunction

function [31:0] INS_BRANCH(input [3:0] cond, input [7:0] target);
    begin INS_BRANCH = {4'd5, cond, 12'd0, target}; end
endfunction

function [31:0] INS_CRC(input [3:0] dst, input [3:0] src);
    begin INS_CRC = {4'd6, dst, src, 20'd0}; end
endfunction

function [31:0] INS_CALL(input [7:0] target);
    begin INS_CALL = {4'd7, 20'd0, target}; end
endfunction

function [31:0] INS_RET;
    begin INS_RET = {4'd8, 28'd0}; end
endfunction

function [31:0] INS_XOR(input [3:0] dst, input [3:0] s1, input [3:0] s2);
    begin INS_XOR = {4'd10, dst, s1, s2, 16'd0}; end
endfunction
```

### Example: Complete UART TX Program
```verilog
// Send byte 0x55 at ~9600 baud (1041 cycles @ 10MHz)
spi_write(0, INS_DRIVE(4'h1, 2'b00, 2'd0));  // Start bit low
spi_write(1, INS_WAIT(4'd0, 16'd1041));
spi_write(2, INS_DRIVE(4'h1, 2'b01, 2'd0));  // Bit 0 = 1
spi_write(3, INS_WAIT(4'd0, 16'd1041));
spi_write(4, INS_DRIVE(4'h1, 2'b00, 2'd0));  // Bit 1 = 0
spi_write(5, INS_WAIT(4'd0, 16'd1041));
spi_write(6, INS_DRIVE(4'h1, 2'b01, 2'd0));  // Bit 2 = 1
spi_write(7, INS_WAIT(4'd0, 16'd1041));
spi_write(8, INS_DRIVE(4'h1, 2'b00, 2'd0));  // Bit 3 = 0
spi_write(9, INS_WAIT(4'd0, 16'd1041));
spi_write(10, INS_DRIVE(4'h1, 2'b01, 2'd0)); // Bit 4 = 1
spi_write(11, INS_WAIT(4'd0, 16'd1041));
spi_write(12, INS_DRIVE(4'h1, 2'b00, 2'd0)); // Bit 5 = 0
spi_write(13, INS_WAIT(4'd0, 16'd1041));
spi_write(14, INS_DRIVE(4'h1, 2'b01, 2'd0)); // Bit 6 = 1
spi_write(15, INS_WAIT(4'd0, 16'd1041));
spi_write(16, INS_DRIVE(4'h1, 2'b00, 2'd0)); // Bit 7 = 0
spi_write(17, INS_WAIT(4'd0, 16'd1041));
spi_write(18, INS_DRIVE(4'h1, 2'b01, 2'd0)); // Stop bit high
spi_write(19, INS_WAIT(4'd0, 16'd1041));

spi_run(20);  // Execute 20 instructions
```

## Synthesis with Yosys

```bash
# Check if yosys is available
which yosys

# Synthesize for IHP 130nm (if PDK available)
yosys -p "
  read_verilog -I rtl rtl/tt_um_protocol_emu.v
  read_verilog -I rtl rtl/pdis_sequencer.v
  read_verilog -I rtl rtl/prog_ram.v
  read_verilog -I rtl rtl/host_if.v
  hierarchy -top tt_um_protocol_emu
  synth -top tt_um_protocol_emu
  stat
  write_json synth.json
"
```

### Expected Area (from stat)
- Program RAM (256×32 dual-port): ~16K cells
- Host IF: ~500 cells  
- Sequencer: ~1.5K cells
- Top wrapper: ~200 cells
- **Total: ~18K cells** (well under 32K budget)

## Pin Mapping (Tiny Tapeout)

| Port | Bits | Function |
|------|------|----------|
| ui_in | 7:0 | Protocol pin inputs |
| uo_out | 7:0 | Protocol pin outputs |
| uio_in[0] | - | SPI SCK (host) |
| uio_in[1] | - | SPI MOSI (host) |
| uio_in[2] | - | SPI CS_N (host) |
| uio_out[0] | - | SPI MISO (host) |
| uio_out[1] | - | sequencer done |
| uio_out[2] | - | sequencer error |
| uio_out[4:3] | - | host state |

## Debugging Tips

### Monitor Sequencer State
In testbench, access internal signals:
```verilog
wire [1:0] seq_st = dut.u_sequencer.st;
wire [7:0] seq_pc = dut.u_sequencer.pc;
wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
// ... reg1, reg2, reg3
wire seq_done = dut.u_sequencer.done;
wire seq_error = dut.u_sequencer.error;
```

### Common Issues
1. **SPI bit order**: Must send MSB first (bit 63 down to 0)
2. **WAIT modes**: 
   - `4'd0` = cycle count
   - `4'd1` = wait high (mask in [1:0])
   - `4'd2` = wait low (mask in [1:0])
   - `4'd3` = wait change (compares to reg0[3:0])
3. **SAMPLE pin_mask**: Only 4 bits (pins 0-3), use SHIFT to access pins 4-7
4. **Program length**: Must match RUN command addr field

## Extending the ISA

To add new instructions:
1. Add opcode in `pdis_sequencer.v` localparam
2. Add case in S_EXECUTE state
3. Update docs/ISA.md

Reserved opcodes: 0xB-0xF available for future use.
