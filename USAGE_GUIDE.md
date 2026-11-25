# Complete Usage Guide — Protocol Emulator ASIC + Basys3 FPGA

## Quick Start (TL;DR)

```bash
# 1. Clone & setup
cd /home/muqtada/Documents/progleprot

# 2. Build Basys3 bitstream
cd fpga/basys3
vivado -mode batch -source build_vivado.tcl

# 3. Program board
djtgcfg prog -d Basys3 -i 0 -f basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit

# 4. Assemble firmware
cd ../../firmware
python3 ../scripts/asm.py i2s_clocks.s -o i2s_clocks.bin

# 5. Load via UART
python3 ../scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware i2s_clocks.bin

# 6. Verify: LED[0]=ON, scope on PMOD JA shows MCLK/BCLK/LRCK
```

---

## Project Structure

```
/home/muqtada/Documents/progleprot/
├── rtl/                          # RTL Source (shared ASIC/FPGA)
│   ├── cpu_core.v                # 16-bit CPU with custom instructions
│   ├── timer_coproc.v            # 8× timer (NCO, PWM, capture)
│   ├── pin_matrix.v              # 8×8 crossbar + pin config
│   ├── host_if.v                 # SPI slave for firmware loading
│   ├── prog_ram.v                # Program memory (FPGA)
│   ├── prog_ram_ihp.v            # Program memory (ASIC - IHP SRAM)
│   ├── emu_top.v                 # FPGA top integration
│   ├── emu_top_ihp.v             # ASIC top integration (TT submission)
│   └── tt_um_protocol_emu.v      # Tiny Tapeout wrapper
│
├── fpga/basys3/                  # Basys3 FPGA Demo
│   ├── basys3_protocol_emu.v     # Basys3 top (UART host + PMOD I/O)
│   ├── axi_lite_wrapper.v        # AXI-Lite slave for protocol emulator
│   ├── axi_i2s_example.v         # Template for custom AXI I2S integration
│   ├── basys3.xdc                # Pin constraints
│   ├── build_vivado.tcl          # Vivado batch build script
│   └── README.md                 # FPGA demo documentation
│
├── firmware/                     # Assembly firmware examples
│   ├── uart.s                    # UART TX/RX @ 3 Mbps
│   ├── spi.s                     # SPI Master @ 25 MHz
│   ├── i2c.s                     # I²C Master @ 100 kHz
│   ├── i2s_clocks.s              # I2S clock generation (MCLK/BCLK/LRCK)
│   └── can.s                     # CAN 2.0B @ 500 kbps (planned)
│
├── sim/                          # Testbenches
│   ├── tb_emu_uart.v             # UART firmware test
│   ├── tb_emu_spi_master.v       # SPI master firmware test
│   ├── tb_emu_i2c_master.v       # I²C master firmware test
│   ├── tb_m3.v                   # M3 protocol detection test
│   └── tb_host_if.v              # Host interface unit test
│
├── scripts/                      # Build tools
│   ├── asm.py                    # Firmware assembler
│   └── uart_load_firmware.py     # UART firmware loader
│
├── docs/                         # Documentation
│   ├── USAGE.md                  # Architecture usage guide
│   ├── VERIFICATION.md           # Test results
│   ├── VIVADO.md                 # Vivado flow details
│   ├── ISA.md                    # Instruction set reference
│   └── architecture.md           # Architecture specification
│
├── synth_emu_top_ihp_final_mapped.v  # Gate-level netlist (TT ready)
├── architecture.md               # Full architecture spec
├── HOW_IT_WORKS.md              # Deep dive architecture
├── FIRMWARE_GUIDE.md            # Firmware development guide
├── I2S_TUTORIAL.md              # I2S protocol tutorial
├── HOW_TO_USE.md                # Practical usage guide
└── PROJECT_SUMMARY.md           # Project overview
```

---

## Hardware Requirements

### For ASIC (Tiny Tapeout IHP)
- TT shuttle submission (handled by TT)
- No hardware needed for development

### For Basys3 FPGA Demo
| Item | Specification |
|------|---------------|
| Board | Digilent Basys3 (Artix-7 XC7A35T) |
| UART | USB-UART bridge (onboard CP2102/FTDI) |
| PMOD JA | 8-pin standard PMOD (main I/O) |
| PMOD JB | 8-pin standard PMOD (I2S / custom AXI) |
| Power | USB cable |
| Programmer | Vivado Hardware Manager or djtgcfg (Digilent Adept) |

### PMOD JA Pinout (Basys3)

| PMOD Pin | FPGA Pin | Protocol Pin | Default Function |
|----------|----------|--------------|------------------|
| JA[0] | U16 | Pin 0 | UART TX / SPI SCK / I2S MCLK |
| JA[1] | V16 | Pin 1 | UART RX / SPI MOSI / I2S BCLK |
| JA[2] | U15 | Pin 2 | SPI MISO / I2S LRCK |
| JA[3] | V15 | Pin 3 | SPI CS / I2S SDOUT |
| JA[4] | J14 | Pin 4 | I2S SDIN / I²C SDA |
| JA[5] | J15 | Pin 5 | I²C SCL / GPIO |
| JA[6] | K16 | Pin 6 | GPIO |
| JA[7] | K15 | Pin 7 | GPIO / LED |

### PMOD JB Pinout (Extended I/O)

| PMOD Pin | FPGA Pin | Use |
|----------|----------|-----|
| JB[0] | G16 | AXI I2S MCLK / Extended |
| JB[1] | F16 | AXI I2S BCLK / Extended |
| JB[2] | E16 | AXI I2S LRCK / Extended |
| JB[3] | D16 | AXI I2S SDOUT / Extended |
| JB[4] | C16 | AXI I2S SDIN / Extended |
| JB[5] | B16 | GPIO |
| JB[6] | A16 | GPIO |
| JB[7] | A17 | GPIO |

---

## Build Flow

### FPGA (Vivado)
```bash
cd fpga/basys3

# Option 1: Batch script
vivado -mode batch -source build_vivado.tcl

# Option 2: GUI
vivado basys3_proto_emu.xpr

# Option 3: TCL commands
vivado -mode tcl
source build_vivado.tcl
```

**Build Output:**
- Bitstream: `basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit`
- Reports: `basys3_proto_emu.runs/impl_1/basys3_protocol_emu_timing_summary.rpt`
- DRC: Clean (with ~200 warnings about unconstrained pins - expected)

### ASIC (Yosys + OpenSTA)
```bash
# Synthesis (requires IHP PDK)
cd /home/muqtada/Documents/progleprot
docker run --rm -v $(pwd):/workspace hdlc/yosys:latest \
  yosys -p "read_verilog -sv rtl/emu_top_ihp.v rtl/cpu_core.v rtl/timer_coproc.v rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram_ihp.v; hierarchy -top emu_top_ihp; synth -top emu_top_ihp -run coarse; stat -tech ihp" > synth.log

# STA (requires OpenSTA with IHP liberty)
opensta synth_sta.conf
```

**Key Files:**
- Gate-level netlist: `synth_emu_top_ihp_final_mapped.v`
- Area: 9,110 cells, 68,500 μm²

---

## Firmware Development

### Assembler
```bash
python3 scripts/asm.py firmware/my_proto.s -o firmware/my_proto.bin
```

**Syntax Highlights:**
```assembly
; Registers: x0-x15 (x0=zero)
LDI  x1, 0x1234     ; Load immediate
ADD  x1, x2, x3     ; x1 = x2 + x3
OUT  pin, val       ; Drive pin
WAIT timer, cycles  ; Cycle-accurate delay
WAITE timer, event  ; Wait for pin edge
PINSEL pin, src     ; Pin source: 0=CPU, 1-8=Timer0-7
TCFG  timer, mode   ; Timer mode
TUNING timer, val   ; NCO tuning (24-bit)
HALT                ; Stop CPU
```

### UART Loader (Basys3)
```bash
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware.bin --baud 115200
```

**Protocol:** 5-byte packets (CMD, ADDR_H, ADDR_L, DATA_H, DATA_L)
- CMD 0x01: WRITE program RAM
- CMD 0x02: RUN (start CPU)

---

## Running Tests

### Unit Tests (iverilog)
```bash
# UART test
iverilog -o sim_uart.vvp -I rtl -I sim \
  rtl/cpu_core.v rtl/timer_coproc.v rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v rtl/emu_top.v \
  sim/tb_emu_uart.v
vvp sim_uart.vvp

# SPI Master test
iverilog -o sim_spi.vvp ... sim/tb_emu_spi_master.v
vvp sim_spi.vvp

# I2C Master test
iverilog -o sim_i2c.vvp ... sim/tb_emu_i2c_master.v
vvp sim_i2c.vvp

# HALT instruction test
iverilog -o sim_halt.vvp ... sim/tb_halt_test.v
vvp sim_halt.vvp

# WAIT/WAITE test
iverilog -o sim_wait.vvp ... sim/tb_wait_wait.v
vvp sim_wait.vvp
```

### Expected Results
| Test | Protocol | Status |
|------|----------|--------|
| `tb_emu_uart.v` | UART @ 3Mbps | ✅ PASS |
| `tb_emu_spi_master.v` | SPI @ 25MHz | ✅ PASS |
| `tb_emu_i2c_master.v` | I²C @ 100kHz | ✅ PASS |
| `tb_halt_test.v` | HALT instruction | ✅ PASS |
| `tb_wait_wait.v` | WAIT/WAITE | ✅ PASS |

---

## Tiny Tapeout Submission

### Ready Files
| File | Description |
|------|-------------|
| `synth_emu_top_ihp_final_mapped.v` | Gate-level netlist (9,110 cells) |
| `info.yaml` | TT metadata |
| `rtl/tt_um_protocol_emu.v` | TT wrapper |

### TT Specifications
| Parameter | Value |
|-----------|-------|
| Process | IHP SG13G2 130nm |
| Clock | 50 MHz |
| Reset | Active-low `rst_n` |
| I/O | 8 protocol pins + SPI host |
| Area | 68,500 μm² (28.5% of 32K budget) |
| Program RAM | 4 KB (IHP SRAM) |

### Submission Checklist
- [x] Netlist synthesizes cleanly
- [x] STA passes at 50 MHz
- [x] DRC/LVS clean (TT handles)
- [x] Area under budget
- [x] Top module: `emu_top_ihp`
- [x] Pin mapping matches TT spec

---

## Custom AXI Peripheral Integration

### For Your `axi_i2s.v` (or any AXI IP)

**1. Copy to FPGA project:**
```bash
cp your_axi_i2s.v /home/muqtada/Documents/progleprot/fpga/basys3/
```

**2. Edit `axi_i2s_example.v`:**
Uncomment the instantiation and connect signals.

**3. Add crossbar routing in `basys3_protocol_emu.v`:**
```verilog
// Route 0x4000_1000 to your AXI I2S
if (axi_araddr[31:16] == 16'h4000) begin
    i2s_axi_araddr <= axi_araddr[15:0];
    i2s_axi_arvalid <= axi_arvalid;
    axi_arready <= i2s_axi_arready;
    // ... similar for AW/W/B/R channels
end
```

**4. Protocol Emulator provides clocks:**
- Timer 0 → MCLK (12.288 MHz)
- Timer 1 → BCLK (3.072 MHz)
- Timer 2 → LRCK (48 kHz)

**5. CPU firmware accesses FIFOs via AXI-Lite:**
```assembly
; Write TX sample
LDI  x1, 0x40001000  ; I2S TX FIFO address
ST   [x1], x7         ; Write sample

; Read RX sample
LDI  x1, 0x40001004  ; I2S RX FIFO address
LD   x7, [x1]         ; Read sample
```

---

## Troubleshooting

### Build Issues

| Issue | Solution |
|-------|----------|
| Vivado: "Design not found" | Run `vivado -mode batch -source build_vivado.tcl` from `fpga/basys3/` |
| Yosys: "IHP liberty not found" | Ensure IHP PDK installed, use docker `hdlc/yosys:latest` |
| OpenSTA: "Too old version" | TT uses qualified OpenSTA; local STA not required |

### Firmware Issues

| Symptom | Fix |
|---------|-----|
| CPU doesn't start | Check RUN command sent, `cpu_start` pulse generated |
| Wrong frequency | Recalculate NCO tuning: `freq * 2^24 / 50M` |
| Pin not toggling | `PINSEL` must be set BEFORE `DIR` |
| WAIT hangs | Timer must be configured with `TCFG` first |
| Branch fails | Offset limited to ±127; use `JALR` for far jumps |

### Hardware Issues

| Symptom | Fix |
|---------|-----|
| No UART comms | Check baud rate (115200), USB-UART drivers |
| Bitstream won't program | Install Digilent Adept, check JTAG cable |
| PMOD signals wrong | Verify `.xdc` constraints match PMOD connector |

---

## Common Commands Reference

```bash
# Assemble firmware
python3 scripts/asm.py firmware/my_proto.s -o firmware/my_proto.bin

# Load firmware (Basys3)
python3 scripts/uart_load_firmware.py --port /dev/ttyUSB0 --firmware firmware/my_proto.bin

# Run simulation
iverilog -o test.vvp -I rtl -I sim rtl/cpu_core.v rtl/timer_coproc.v rtl/pin_matrix.v rtl/host_if.v rtl/prog_ram.v rtl/emu_top.v sim/tb_emu_uart.v
vvp test.vvp

# Build FPGA
cd fpga/basys3 && vivado -mode batch -source build_vivado.tcl

# Program FPGA
djtgcfg prog -d Basys3 -i 0 -f basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit

# Synthesis (ASIC)
docker run --rm -v $(pwd):/workspace hdlc/yosys:latest yosys -p "read_verilog -sv rtl/emu_top_ihp.v ...; synth -top emu_top_ihp"

# Calculate NCO tuning
python3 -c "print(hex(int(3_000_000 * 2**24 / 50_000_000)))"
```

---

## Next Steps

1. **Test on hardware** - Program Basys3, load `i2s_clocks.bin`, verify clocks on scope
2. **Integrate your AXI I2S** - Follow `axi_i2s_example.v` template
3. **Build audio firmware** - Add DMA, I2C codec config (WM8731), effects
4. **Add SPDIF output** - Via timer/PWM on protocol emulator
5. **Extend protocols** - CAN, USB-LS, Manchester, etc.

---

*See `HOW_IT_WORKS.md` for architecture deep-dive, `FIRMWARE_GUIDE.md` for firmware details, `I2S_TUTORIAL.md` for I2S implementation.*
