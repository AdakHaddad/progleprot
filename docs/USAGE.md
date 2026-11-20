# Protocol Emulator ASIC — Usage Guide

## Overview
This is a reprogrammable protocol emulator ASIC for Tiny Tapeout IHP (130nm CMOS5L). It implements a **16-bit CPU core** with a **timer coprocessor** (8× NCO + counter + event capture), **8×8 pin matrix**, and **SPI host interface**. Firmware running on the CPU implements any digital protocol (UART, SPI, I2C, CAN, USB-LS, Manchester, etc.) with cycle-accurate hardware timing.

## Hardware Interface (TT Pinout)

### Dedicated Pins (ui_in / uo_out)
| Pin | Direction | Function |
|-----|-----------|----------|
| ui_in[0] | Input | Protocol Pin 0 (e.g., UART TX, SPI SCK, I2C SDA) |
| ui_in[1] | Input | Protocol Pin 1 (e.g., UART RX, SPI MOSI, I2C SCL) |
| ui_in[2] | Input | Protocol Pin 2 (e.g., SPI CS_N, CAN TX) |
| ui_in[3] | Input | Protocol Pin 3 (e.g., SPI MISO, CAN RX) |
| ui_in[4-7] | Input | Protocol Pins 4-7 |
| uo_out[0-7] | Output | Pin outputs when OE=1 |

### Host Interface (uio_in / uio_out / uio_oe)
| Pin | Direction | Function |
|-----|-----------|----------|
| uio_in[0] | Input | SPI SCK (host) |
| uio_in[1] | Input | SPI MOSI (host) |
| uio_in[2] | Input | SPI CS_N (host, active low) |
| uio_out[0] | Output | SPI MISO (host) |
| uio_out[1] | Output | CPU running flag |
| uio_out[2] | Output | CPU error flag |
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
| 0x01 | WRITE | addr(16) + data(32) | Write 16-bit word to program RAM (splits 32-bit data) |
| 0x03 | RUN | length(16) | Start CPU with program length |

### Load Sequence Example
```python
# Pseudocode for host loader
def spi_write(addr, data_32):
    # Writes two 16-bit words: data[15:0] to addr, data[31:16] to addr+1
    frame = (data_32 << 24) | (addr << 8) | 0x01
    spi.transfer(frame.to_bytes(8, 'big'))

def spi_run(length):
    frame = (length << 8) | 0x03
    spi.transfer(frame.to_bytes(8, 'big'))

# Load UART firmware (example)
spi_write(0x00, 0x825c8129)   # ADDI x1,0x29 + ADDI x2,0x5C (NCO inc low/mid)
spi_write(0x02, 0x830f8400)   # ADDI x3,0x0F + ADDI x4,0x00 (NCO inc high + timer 0)
spi_write(0x04, 0x86018755)   # ADDI x6,0x01 (RX pin) + ADDI x7,0x55 (TX data)
spi_write(0x06, 0x8800890a)   # ADDI x8,0x00 + ADDI x9,0x0A (bit counter = 10)
spi_write(0x08, 0x8a008b01)   # ADDI x10,0x00 + ADDI x11,0x01 (state + const 1)
spi_write(0x0a, 0xf150f160)   # DIR x5 (TX pin=out) + DIR x6 (RX pin=in)
spi_write(0x0c, 0xf057f060)   # OUT x5,x7 (start bit=0) + WAIT timer0,x8
# ... more instructions ...
spi_write(0x16, 0xffff0000)   # HALT + padding

spi_run(0x30)  # Start CPU with 48 bytes (24 instructions)
```

## CPU ISA Reference (16-bit Instructions)

### Encoding
```
[15:12] = Opcode (4 bits)
[11:8]  = rd / funct / rs1 (depends on opcode)
[7:4]   = rs1 / rs2
[3:0]   = rs2 / funct / immediate (depends on opcode)
```

### Opcodes

| Opcode | Mnemonic | Format | Description |
|--------|----------|--------|-------------|
| 0x0 | ALU | rd, rs1, rs2 | ALU ops: ADD, SUB, AND, OR, XOR, SLT, SLL, SRL, SRA (funct in rs2[3:0] for now ADD only) |
| 0x8 | ADDI | rd, imm8 | Add sign-extended 8-bit immediate (rs1 = x0 = 0) |
| 0xF | CUSTOM | funct, rs1, rs2/rd | Timing/peripheral instructions (see below) |

### Custom Timing Instructions (Opcode 0xF)

| Funct | Mnemonic | Operands | Description |
|-------|----------|----------|-------------|
| 0x0 | OUT | pin_reg, val_reg | Drive pin from register bit 0 |
| 0x1 | DIR | pin_reg, dir_reg | Set pin direction (0=in, 1=out) |
| 0x2 | WAIT | timer_reg, cycles_reg | Stall CPU for N cycles (timer counts down) |
| 0x3 | WAITE | timer_reg, event_reg | Stall until timer pin event |
| 0x4 | TIME | rd, timer_reg | Read timer counter/capture → rd |
| 0x5 | TCFG | timer_reg, config_reg | Configure timer mode |
| 0x6 | TUNING | timer_reg, tuning_reg | Set NCO tuning word |
| 0x7 | PINSEL | pin_reg, src_reg | Select pin source (0=CPU, 1-8=Timer0-7) |
| 0x8 | EVEN | timer_reg, mask | Enable timer events |
| 0x9 | SWAP | — | Trigger program bank swap |
| 0xA | VERIFY | rd | Read host CRC → rd |
| 0xB | CAPRD | rd, timer_reg | Read capture register → rd |
| 0xF | HALT | — | Stop CPU execution |

### Instruction Examples (16-bit hex)

```verilog
// ADDI rd, imm8: opcode=8, rd=[11:8], imm8=[7:0]
16'h8129  // ADDI x1, 0x29
16'h825c  // ADDI x2, 0x5C
16'h830f  // ADDI x3, 0x0F

// OUT pin, val: opcode=F, funct=0, rs1=pin, rs2=val
16'hf057  // OUT x5, x7 (pin in x5, value in x7[0])

// DIR pin, dir: opcode=F, funct=1, rs1=pin, rs2=dir
16'hf150  // DIR x5, 0 (x5=pin, x0=0 -> output)

// WAIT timer, cycles: opcode=F, funct=2, rs1=timer, rs2=cycles
16'hf248  // WAIT x4, x8 (timer in x4, cycles in x8)

// TCFG timer, config: opcode=F, funct=5, rs1=timer, rs2=config
16'hf543  // TCFG x4, x3 (timer in x4, config in x3)

// TUNING timer, val: opcode=F, funct=6, rs1=timer, rs2=tuning
16'hf641  // TUNING x4, x1 (timer in x4, tuning in x1)

// PINSEL pin, src: opcode=F, funct=7, rs1=pin, rs2=src
16'hf721  // PINSEL x2, x1 (pin 2 = Timer 0 NCO)

// HALT
16'hffff  // HALT
```

## Memory Map

| Address Range | Device | Description |
|---------------|--------|-------------|
| 0x0000-0x0FFF | Program RAM | Active firmware bank (4KB = 2K × 16-bit) |
| 0x1000-0x17FF | Boot ROM | Factory firmware (2KB) |
| 0xF000-0xF07F | Timers | 8 timers × 16 bytes = 128 bytes |
| 0xF100-0xF10F | Pin Matrix | Crossbar config + I/O |
| 0xF200-0xF207 | Host IF | SPI status/control |

### Timer Register Map (per timer, 16 bytes = 8 registers)

| Offset | Register | Bits | Description |
|--------|----------|------|-------------|
| 0x0 | TUNING | 7:0 | NCO phase increment low byte |
| 0x1 | TUNING_H | 15:0 | NCO phase increment high 16 bits |
| 0x2 | COUNTER | 15:0 | Counter value |
| 0x3 | CAPTURE | 15:0 | Capture register |
| 0x4 | COMPARE | 15:0 | Compare value |
| 0x5 | MODE | 7:0 | Timer mode |
| 0x6 | EV_EN | 7:0 | Event enables |
| 0x7 | EV_ST | 7:0 | Event status (read clears) |

### Timer Modes

| Mode | Name | Description |
|------|------|-------------|
| 0x0 | OFF | Disabled |
| 0x1 | COUNT_UP | Increment every cycle |
| 0x2 | COUNT_DOWN | Decrement; event at 0 |
| 0x3 | NCO_CLK | Output NCO MSB as clock (50% duty) |
| 0x4 | NCO_VAR | Variable duty (counter vs compare) |
| 0x5 | PWM | PWM output (counter < compare) |
| 0x6 | CAPTURE | Pin event → latch counter |
| 0x7 | MEASURE | Rise→Fall width, Fall→Rise period |

### Pin Source Select (4 bits per pin in PINSEL)

| Value | Source |
|-------|--------|
| 0x0 | CPU (OUT register) |
| 0x1-0x8 | Timer 0-7 NCO clock |
| 0x9-0xF | Timer 0-6 PWM |

## NCO Frequency Formula

```
f_out = (tuning_word × f_clk) / 2^24

Examples @ 50MHz:
- 25 MHz SPI:     tuning = 0x800000 (2^23)
- 12.5 MHz:       tuning = 0x400000
- 3 Mbps UART:    tuning = 0x0F5C29
- 100 kHz I²C:    tuning = 0x051EB8
- 400 kHz I²C:    tuning = 0x147AE1
- 500 kbps CAN:   tuning = 0x19999A
```

## Example Protocols

### UART TX/RX (3 Mbps)
- Configure Timer 0 NCO with tuning = 0x0F5C29
- Set TX pin (0) as output via DIR
- Use OUT for start/stop/data bits
- Use WAIT for bit timing
- For RX: configure Timer 1 for capture, use WAITE for edge detection

### SPI Master (25 MHz)
- Configure Timer 0 NCO with tuning = 0x800000
- PINSEL SCK pin (2) → Timer 0 NCO
- DIR MOSI(0)/CS(3) = output, MISO(1) = input
- OUT for CS control, WAIT for bit timing

### I²C Master (100 kHz)
- Configure Timer 0 NCO with tuning = 0x051EB8
- PINSEL SCL pin (1) → Timer 0 NCO
- Open-drain emulation: DIR=1, OUT=0 (drive low), OUT=1 (release)
- WAITE on SDA for ACK detection

### CAN 2.0B (500 kbps)
- Configure Timer 0 NCO with tuning = 0x19999A
- Bit-stuffing and CRC in firmware
- Use pin capture for sync

## Firmware Development Flow

```
firmware/uart.s (assembly)
       │
       ▼
as/ld (custom 16-bit target - GNU as with macros)
       │
       ▼
uart.bin (raw 16-bit words)
       │
       ▼
Host PC: python spi_loader.py uart.bin
       │
       ▼
SPI → Program RAM → CMD_RUN → CPU executes
```

## Simulation

```bash
cd /home/muqtada/Documents/progleprot

# M3: SPI/I²C Detection (hardware blocks)
iverilog -g2012 -o sim_m3.vvp -Isim -Irtl \
  sim/tb_m3.v rtl/edge_interval.v rtl/log_bucket.v rtl/histogram.v \
  rtl/peak_detect.v rtl/encoding_layer.v rtl/spi_detect.v \
  rtl/i2c_detect.v rtl/m3_top.v
vvp sim_m3.vvp

# UART Firmware Test
iverilog -g2012 -o sim_emu_uart.vvp -Isim -Irtl \
  sim/tb_emu_uart.v rtl/emu_top.v rtl/cpu_core.v rtl/timer_coproc.v \
  rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v
vvp sim_emu_uart.vvp

# SPI Master Firmware Test
iverilog -g2012 -o sim_emu_spi.vvp -Isim -Irtl \
  sim/tb_emu_spi_master.v rtl/emu_top.v rtl/cpu_core.v rtl/timer_coproc.v \
  rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v
vvp sim_emu_spi.vvp

# I²C Master Firmware Test
iverilog -g2012 -o sim_emu_i2c.vvp -Isim -Irtl \
  sim/tb_emu_i2c_master.v rtl/emu_top.v rtl/cpu_core.v rtl/timer_coproc.v \
  rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v
vvp sim_emu_i2c.vvp
```

## Synthesis (Yosys)

```bash
# Quick area estimate
podman run --rm -v $(pwd):/workspace docker.io/hdlc/yosys:latest \
  yosys -p "read_verilog -sv /workspace/rtl/emu_top.v /workspace/rtl/cpu_core.v \
  /workspace/rtl/timer_coproc.v /workspace/rtl/pin_matrix.v /workspace/rtl/host_if.v; \
  hierarchy -top emu_top; stat"

# Full synthesis with IHP tech mapping
podman run --rm -v $(pwd):/workspace docker.io/hdlc/yosys:latest \
  yosys /workspace/synth_run.ys
```

## Project Structure

```
progleprot/
├── rtl/
│   ├── emu_top.v              # Top-level integration
│   ├── cpu_core.v             # 16-bit CPU with custom instructions
│   ├── timer_coproc.v         # 8× NCO + counter + events
│   ├── pin_matrix.v           # 8×8 crossbar + config
│   ├── host_if.v              # SPI slave for firmware loading
│   ├── prog_ram.v             # Program memory (single bank)
│   ├── tt_um_protocol_emu.v   # TT IHP wrapper
│   ├── m3_top.v               # M3 detection pipeline
│   ├── spi_detect.v           # SPI frame detection
│   ├── i2c_detect.v           # I²C frame detection
│   ├── edge_interval.v        # Edge interval measurement
│   ├── log_bucket.v           # Logarithmic bucketing
│   ├── histogram.v            # Histogram accumulation
│   ├── peak_detect.v          # Peak detection
│   ├── encoding_layer.v       # Protocol classification
│   ├── pdis_sequencer.v       # Legacy sequencer (not used)
│   └── *.v                    # Other M1-M6 legacy blocks
├── rtl_legacy/                # Legacy M1-M6 modules
├── firmware/
│   ├── uart.s                 # UART TX/RX @ 3Mbps
│   ├── spi.s                  # SPI Master @ 25MHz
│   ├── i2c.s                  # I²C Master @ 100kHz
│   └── can.s                  # CAN 2.0B @ 500kbps
├── sim/
│   ├── tb_m3.v                # M3 detection test
│   ├── tb_emu_uart.v          # UART firmware test
│   ├── tb_emu_spi_master.v    # SPI master firmware test
│   ├── tb_emu_i2c_master.v    # I²C master firmware test
│   └── *.v                    # Other testbenches
├── docs/
│   ├── USAGE.md               # This file
│   ├── VERIFICATION.md        # Test results
│   ├── VIVADO.md              # Vivado flow
│   ├── ISA.md                 # ISA specification
│   └── architecture.md        # Architecture spec
├── plan.md                    # Project plan & milestones
├── synth_run.ys               # Yosys synthesis script
└── Makefile                   # Build automation (if present)
```

## Key Files for Development

| File | Purpose |
|------|---------|
| `rtl/cpu_core.v` | CPU core with 4-stage pipeline |
| `rtl/timer_coproc.v` | Timer coprocessor (8 channels) |
| `rtl/pin_matrix.v` | Pin crossbar and config |
| `rtl/host_if.v` | SPI host interface |
| `rtl/emu_top.v` | Top-level integration |
| `firmware/*.s` | Protocol firmware |
| `sim/tb_emu_*.v` | Firmware testbenches |
| `architecture.md` | Full architecture spec |
| `isa.md` | ISA encoding tables |

