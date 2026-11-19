# Area Budget Estimation (Manual)

Based on RTL analysis for Tiny Tapeout IHP (130nm CMOS5L)

## Block Breakdown

| Block | Est. Cells | Notes |
|-------|------------|-------|
| CPU Core (16-bit, 4-stage, 16 GPRs) | 3,500 | Small pipeline with forwarding |
| Timer Coprocessor (8× NCO + counter + events) | 4,500 | 24-bit NCO = ~300 ea |
| Pin Matrix (8×8 crossbar + config regs) | 1,200 | |
| Host Interface (SPI slave) | 1,000 | |
| Program RAM (4KB = 2048×16) | 2,000 | SRAM macro preferred |
| Boot ROM (2KB) | 500 | |
| Capture Buffer (256-entry FIFO) | 1,500 | For M11 stretch |
| Optional HW Assist (Manchester, NRZI, CRC) | 1,000 | For M11 stretch |
| **Subtotal** | **~15,200** | |
| Clock tree, routing margin (30%) | ~4,500 | |
| **Total** | **~20K** | **37% margin** under 32K |

## Current RTL Status

### Completed (M1-M9):
- ✅ `cpu_core.v` - 16-bit CPU with custom timing instructions (ADD, ADDI, ORI, OUT, DIR, WAIT, WAITE, TIME, TCFG, TUNING, PINSEL, TCFG, HALT)
- ✅ `timer_coproc.v` - 8× 24-bit NCO, 16-bit counter, capture, compare, events
- ✅ `pin_matrix.v` - 8×8 crossbar with DIR/SEL/PULL/OUT/IN
- ✅ `host_if.v` - SPI slave for firmware loading
- ✅ `emu_top.v` - Full integration
- ✅ `prog_ram.v` - 4KB program memory

### Verified (Simulation):
- ✅ SPI Master @ 25MHz - SCK driven by Timer 0 NCO, MOSI/CS by CPU
- ✅ I²C Master @ 100kHz - SDA/SCL driven by Timer 0 NCO
- ✅ UART TX @ 3Mbps - Pin 0 driven by Timer 0 NCO

### Firmware (Testbench-embedded):
- `sim/tb_emu_spi_master.v` - SPI Master firmware (31 instruction pairs)
- `sim/tb_emu_i2c_master.v` - I²C Master firmware
- `sim/tb_emu_uart.v` - UART TX firmware

### Verilator Lint:
- Clean (only expected: MULTITOP for separate prog_ram, UNUSEDSIGNAL for optional outputs)

## Next Steps for Tapeout (M10)

1. **Install Yosys** (for synthesis):
   ```bash
   # On Ubuntu/Debian:
   sudo apt-get install yosys
   
   # Or build from source:
   git clone https://github.com/YosysHQ/yosys
   cd yosys && cmake -B build && make -C build -j$(nproc)
   ```

2. **Run synthesis**:
   ```bash
   cd /home/muqtada/Documents/progleprot
   yosys synth.ys
   ```

3. **Timing closure** at 50MHz:
   - Check critical path
   - Pipeline timer outputs if needed
   - 2-cycle pin matrix if needed

4. **TT submission**:
   - GDS export per TT format
   - DRC/LVS clean
   - `info.yaml` with correct tile count (8x4 = 32 tiles)

## M11 Stretch (Detection/Analyzer)

If cells allow (~+3K):
- Manchester encoder/decoder
- NRZI encoder/decoder
- CRC5/CRC16 hardware
- 256-entry capture FIFO
- Firmware: `capture.s`, `can.s`, `usb_ls.s`, `manchester.s`
