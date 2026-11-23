# Basys3 Protocol Emulator Demo

This directory contains a complete FPGA demo for the Protocol Emulator on the Digilent Basys3 board (Artix-7 XC7A35T).

## Quick Start

### 1. Build with Vivado

```bash
cd fpga/basys3
vivado -mode batch -source build_vivado.tcl
```

Or open Vivado GUI:
1. File → Project → New → RTL Project
2. Add sources from `../../rtl/` and `./`
3. Add constraints `basys3.xdc`
4. Set top module: `basys3_protocol_emu`
5. Run Synthesis → Implementation → Generate Bitstream

### 2. Program Basys3

```bash
# Using Vivado Hardware Manager
# Or using djtgcfg (Digilent Adept)
djtgcfg prog -d Basys3 -i 0 -f basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit
```

### 3. Load Firmware via UART

The board uses USB-UART (115200 baud) for firmware loading:

```bash
# Using Python script
python3 ../../scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware ../../firmware/uart.bin

# Or using any serial terminal:
# Send: [CMD=0x01][ADDR_H][ADDR_L][DATA_H][DATA_L] for each word
# Then: [CMD=0x02][LEN_H][LEN_L] to start CPU
```

## Hardware Connections

### PMOD JA (J1) - Main 8 I/O Pins
| Pin | Signal | Use |
|-----|--------|-----|
| JA1 | Pin 0  | MCLK / GPIO |
| JA2 | Pin 1  | BCLK / GPIO |
| JA3 | Pin 2  | LRCK / GPIO |
| JA4 | Pin 3  | SDATA_OUT / GPIO |
| JA7 | Pin 4  | SDATA_IN / GPIO |
| JA8 | Pin 5  | GPIO |
| JA9 | Pin 6  | GPIO |
| JA10| Pin 7  | GPIO |

### PMOD JB (J2) - I2S / Extra I/O
| Pin | Signal | Use |
|-----|--------|-----|
| JB1 | MCLK   | I2S Master Clock |
| JB2 | BCLK   | I2S Bit Clock |
| JB3 | LRCK   | I2S Left/Right Clock |
| JB4 | SDOUT  | I2S Serial Data Out |
| JB7 | SDIN   | I2S Serial Data In |
| JB8-10 | GPIO | Extra I/O |

### Status LEDs
| LED | Meaning |
|-----|---------|
| LD0 | CPU Running |
| LD1 | CPU Error |
| LD2-LD7 | Pin Output Activity |
| LD8-LD15 | Pin Input State |

### Switches
| SW | Function |
|----|----------|
| SW0-SW3 | Debug Register Select |
| SW4-SW15 | Reserved |

### Buttons
| Button | Function |
|--------|----------|
| BTN0 | Reset (active high) |

## Firmware Development

### Assembly
```bash
# Assemble firmware
cd ../../firmware
python3 asm.py uart.s -o uart.bin
python3 asm.py i2s_clocks.s -o i2s_clocks.bin
```

### UART Protocol
```
Host → FPGA: [CMD:8][ADDR_H:8][ADDR_L:8][DATA_H:8][DATA_L:8]
FPGA → Host: [ACK:8] or [DATA_H:8][DATA_L:8]

Commands:
  0x01: Write Program RAM
  0x02: Start CPU (data = program length)
  0x03: Read Debug Register (not implemented)
```

## Integrating Your AXI I2S Module

### 1. Copy your `axi_i2s.v` to this directory

### 2. Uncomment instantiation in `axi_i2s_example.v`:
```verilog
axi_i2s u_i2s (
    .s_axi_aclk(i2s_axi_aclk),
    .s_axi_aresetn(i2s_axi_aresetn),
    // ... AXI signals ...
    .mclk(i2s_mclk_int),
    .bclk(i2s_bclk_int),
    .lrck(i2s_lrck_int),
    .sdata_out(i2s_sdata_out_int),
    .sdata_in(i2s_sdata_in_int)
);
```

### 3. Add AXI crossbar routing for I2S (address 0x4000_1000):
```verilog
// In axi_i2s_example.v, add routing for slave 1
assign crossbar_awaddr[1] = s_axi_awaddr;
assign crossbar_awvalid[1] = s_axi_awvalid & (s_axi_awaddr[31:12] == 20'h40001);
// ... similar for other channels
```

### 4. Connect I2S pins to PMOD JB in XDC:
```tcl
# Already in basys3.xdc for jb[0:7]
```

### 5. Use Protocol Emulator Timers for I2S Clocks
The firmware `i2s_clocks.s` shows how to configure:
- Timer 0 → Pin 0 → MCLK (12.288 MHz)
- Timer 1 → Pin 1 → BCLK (3.072 MHz) 
- Timer 2 → Pin 2 → LRCK (48 kHz)

Pin matrix routes timer NCO outputs to PMOD pins automatically.

## Memory Map (AXI-Lite via axi_lite_wrapper.v)

| Address | Register | Access |
|---------|----------|--------|
| 0x4000_0000-0x007F | Timer 0-7 registers | RW |
| 0x4000_0080 | Pin Direction | RW |
| 0x4000_0082 | Pin Output | RW |
| 0x4000_0084 | Pin Input | R |
| 0x4000_0086 | Pin OE | RW |
| 0x4000_0088 | Pin Rise Events | R |
| 0x4000_008A | Pin Fall Events | R |
| 0x4000_0090 | CPU PC | R |
| 0x4000_0092 | CPU Status | R |
| 0x4000_0094-0x00D0 | GPRs (R0-R15) | R |
| 0x4000_00F0 | Host State | R |
| 0x4000_00F2 | Program Length | RW |
| 0x4000_00F4 | RAM Write Addr | RW |
| 0x4000_00F6 | RAM Write Data | RW |
| 0x4000_00F8 | RAM Write Enable | W |
| 0x4000_00FA | CPU Start | W |

## Resource Utilization (Estimated)

| Resource | Used | Available | % |
|----------|------|-----------|---|
| LUTs | ~8,000 | 20,800 | ~38% |
| FFs | ~6,000 | 41,600 | ~14% |
| BRAM | 2 | 50 | 4% |
| DSPs | 0 | 90 | 0% |
| IO | 26 | 106 | 25% |

## Troubleshooting

### No UART Communication
- Check USB-UART drivers (CP2102/FTDI)
- Verify baud rate 115200, 8N1
- Check PMOD JA not conflicting with UART pins

### Firmware Not Running
- Verify program length in start command (0x02)
- Check CPU error LED (LD1)
- Use debug register (SW0-SW3) to inspect CPU state

### I2S Clocks Not Working
- Verify timer tuning words match 50MHz clock
- Check pin matrix config (CFG_TIMER)
- Check pin OE register

## Next Steps

1. **Add DMA** for audio buffer transfer
2. **Implement I2C** for codec configuration (WM8731, etc.)
3. **Add SPDIF** output via timer/PWM
4. **Build audio effects** in firmware (EQ, reverb, etc.)
