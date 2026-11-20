# Vivado Synthesis Flow for Tiny Tapeout IHP (CPU Architecture)

## Prerequisites
- Vivado 2023.2+
- IHP 130nm PDK installed (SG13G2)
- Tiny Tapeout IHP user project template

## Project Structure (Current CPU Architecture)
```
project/
├── rtl/
│   ├── emu_top.v              # Top-level integration (CPU + Timers + Pins + Host)
│   ├── cpu_core.v             # 16-bit CPU with 4-stage pipeline + custom instructions
│   ├── timer_coproc.v         # 8-channel timer coprocessor (NCO + counter + events)
│   ├── pin_matrix.v           # 8×8 crossbar with direction/pull/source select
│   ├── host_if.v              # SPI slave for firmware loading
│   ├── prog_ram.v             # Program memory (single 4KB bank)
│   └── tt_um_protocol_emu.v   # TT IHP wrapper (top module)
├── sim/
│   ├── tb_emu_uart.v          # UART firmware integration test
│   ├── tb_emu_spi_master.v    # SPI master firmware test
│   ├── tb_emu_i2c_master.v    # I²C master firmware test
│   ├── tb_m3.v                # M3 hardware detection test
│   └── tb_host_if.v           # Host interface unit test
├── constraints/
│   └── timing.xdc             # Timing constraints
└── docs/
    ├── ISA.md                 # Instruction set reference
    ├── USAGE.md               # Usage guide
    ├── VERIFICATION.md        # Test results
    ├── VIVADO.md              # This file
    └── architecture.md        # Architecture specification
```

## Vivado Project Setup

### 1. Create Project
```tcl
# In Vivado Tcl console
create_project protocol_emu ./project -part ihp_sg13g2
# Note: IHP part name depends on PDK installation (e.g., ihp_sg13g2, sg13g2)
```

### 2. Add Sources
```tcl
add_files {
  ../rtl/emu_top.v
  ../rtl/cpu_core.v
  ../rtl/timer_coproc.v
  ../rtl/pin_matrix.v
  ../rtl/host_if.v
  ../rtl/prog_ram.v
  ../rtl/tt_um_protocol_emu.v
}

# Set top module
set_property top tt_um_protocol_emu [current_fileset]
```

### 3. Add Constraints
```tcl
add_files -fileset constrs_1 ../constraints/timing.xdc
```

### 4. Synthesis Settings
```tcl
# For IHP 130nm, use appropriate synthesis strategy
set_property STEPS.SYNTH_DESIGN.ARGS.MORE_OPTIONS { -no_lc -flatten_hierarchy none } [get_runs synth_1]
```

## Timing Constraints (constraints/timing.xdc)

```tcl
# Clock: 50 MHz system clock (TT default)
create_clock -period 20.0 -name clk [get_ports clk]

# Input/output delays for SPI host interface (async to clk)
set_input_delay -clock clk -max 2.0 [get_ports uio_in[0]]   # SCK
set_input_delay -clock clk -max 2.0 [get_ports uio_in[1]]   # MOSI
set_input_delay -clock clk -max 2.0 [get_ports uio_in[2]]   # CS_N
set_output_delay -clock clk -max 3.0 [get_ports uio_out[0]] # MISO

# Protocol pins - software timed via CPU/timers
# No strict timing constraints needed (cycle-accurate in firmware)
set_input_delay -clock clk -max 5.0 [get_ports ui_in[0]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[1]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[2]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[3]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[4]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[5]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[6]]
set_input_delay -clock clk -max 5.0 [get_ports ui_in[7]]

set_output_delay -clock clk -max 5.0 [get_ports uo_out[0]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[1]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[2]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[3]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[4]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[5]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[6]]
set_output_delay -clock clk -max 5.0 [get_ports uo_out[7]]

# False paths for async host interface
set_false_path -from [get_ports uio_in[*]] -to [get_clocks clk]
set_false_path -from [get_clocks clk] -to [get_ports uio_out[0]]

# Reset - async active low
set_property ASYNC_REG true [get_cells -hierarchical *rst*]
```

## IHP 130nm Specific Notes

### Memory Configuration
The `prog_ram` uses single-port distributed RAM (2048 × 16-bit = 32Kb):
```verilog
(* ram_style = "distributed" *)
reg [15:0] prog_ram [0:2047];
```
- Maps to LUTRAM in IHP 130nm
- Should fit in available distributed RAM resources
- For larger programs, consider dual-bank or block RAM

### Area Budget
TT IHP: 8×4 tiles ≈ 32K cells (32,000 gates)

| Block | Est. Cells | % Budget |
|-------|------------|----------|
| CPU Core (16-bit, 4-stage, 16 GPRs) | 3,500 | 11% |
| Timer Coprocessor (8× NCO + counter + events) | 4,500 | 14% |
| Pin Matrix (8×8 crossbar + config) | 1,200 | 4% |
| Host Interface (SPI slave) | 1,000 | 3% |
| Program RAM (4KB distributed) | 2,000 | 6% |
| Boot ROM (2KB) | 500 | 2% |
| Capture Buffer (256-entry FIFO) | 1,500 | 5% |
| HW Assist (Manchester/NRZI/CRC) | 1,000 | 3% |
| **Subtotal** | **15,200** | **48%** |
| Clock tree, routing margin (30%) | 4,500 | 14% |
| **Total** | **~20K** | **62%** |

**Margin**: ~38% (12K cells) for additional features

### Power/Clock Gating
```tcl
# If using power domains
create_power_domain -name PD_CORE -elements [get_cells -hierarchical u_cpu]
create_power_domain -name PD_TIMERS -elements [get_cells -hierarchical u_timers]
create_power_domain -name PD_PINS -elements [get_cells -hierarchical u_pin_matrix]
create_power_domain -name PD_RAM -elements [get_cells -hierarchical u_prog_ram]
```

## Synthesis Flow

```bash
# Run synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check results
report_utilization -hierarchical
report_timing_summary
report_power
```

## Post-Synthesis Checks

### 1. Area Report
```tcl
report_utilization -hierarchical -file area_report.txt
# Check: Total cells < 32000
```

### 2. Timing Report
```tcl
report_timing_summary -file timing_report.txt
# Check: WNS > 0 (no violations at 50MHz / 20ns period)
```

### 3. Critical Path Analysis
Typical critical paths:
```
CPU pipeline: IF → ID (decode + reg read + ALU) → EX (mem/peripheral) → WB
Timer NCO: phase_acc + tuning_word → nco_clk_out → pin_matrix mux → pin_out
Pin matrix: pin_sel mux (8:1 × 4-bit) → output register
Host IF: SPI shift register → program RAM write
```

### 4. Power Report
```tcl
report_power -file power_report.txt
# Check: Within TT power budget
```

## Implementation Flow

```bash
# Place and route
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Post-route timing
report_timing_summary -file post_route_timing.txt

# DRC check
report_drc -file drc_report.txt

# Generate GDSII (via TT flow)
write_verilog -force post_route.v
# Then use TT GDS generation flow
```

## TT IHP Submission Checklist

- [ ] Synthesis passes without errors
- [ ] Timing meets at 50MHz (20ns period) - WNS > 0
- [ ] Area < 32K cells (target ~20K)
- [ ] DRC clean
- [ ] Power within budget
- [ ] All testbenches pass RTL simulation
- [ ] Gate-level simulation with SDF passes
- [ ] RTL linting clean (spyglass/verilator)
- [ ] Documentation complete (ISA.md, USAGE.md, VERIFICATION.md)
- [ ] GDSII generated per TT format
- [ ] Firmware examples included (UART, SPI, I²C, CAN)

## Yosys Alternative (Open Source - Quick Iteration)

```bash
# Quick area estimate without Vivado
podman run --rm -v $(pwd):/workspace docker.io/hdlc/yosys:latest \
  yosys -p "
  read_verilog -sv /workspace/rtl/emu_top.v /workspace/rtl/cpu_core.v \
  /workspace/rtl/timer_coproc.v /workspace/rtl/pin_matrix.v /workspace/rtl/host_if.v;
  hierarchy -top emu_top;
  synth -top emu_top -run coarse;
  stat -tech ihp
  write_json /workspace/synth.json
  "

# This provides gate-level cell count for area budgeting
# Typical output: ~9,395 cells (29% of 32K budget)
```

## Troubleshooting

### Common Issues

**RAM inference fails:**
- Ensure `prog_ram.v` uses `reg [WIDTH-1:0] mem [0:DEPTH-1]`
- Add `(* ram_style = "distributed" *)` attribute
- Check for proper read-during-write behavior

**Timing violations on CPU pipeline:**
- Pipeline stages may need balancing
- Consider adding register stages in ALU or memory access
- Target: 20ns (50MHz) - should be achievable

**Area too large:**
- Reduce PROG_DEPTH from 2048 to 1024 (saves ~1K cells)
- Reduce timer channels from 8 to 4 (saves ~2K cells)
- Remove capture buffer if not needed (saves ~1.5K cells)
- Share NCO phase accumulators across timers

**Simulation/synthesis mismatch:**
- Check for blocking vs non-blocking assignments
- Ensure reset polarity consistent (active low rst_n)
- Verify initial blocks synthesize correctly
- Watch for X-propagation in Verilog

**Pin matrix timing:**
- Crossbar is purely combinational
- Add output registers if timing critical
- Current: 1-cycle through mux is fine at 50MHz

## Key Differences from Legacy Sequencer Architecture

| Aspect | Legacy (pdis_sequencer) | Current (cpu_core + timer_coproc) |
|--------|------------------------|-----------------------------------|
| Control | Fixed 32-bit instruction set | 16-bit CPU + custom instructions |
| Timing | SYNC/WAIT in instruction | WAIT/WAITE custom instructions |
| Pin Control | DRIVE/SAMPLE in instruction | OUT/DIR/PINSEL custom instructions |
| Frequency Gen | External/imprecise | Hardware NCO (24-bit, exact) |
| Protocol Flexibility | Limited by instruction set | Full firmware programmability |
| Area | ~18K cells (est) | ~20K cells (with more features) |
| Firmware | Assembly macros | C-like assembly with macros |

## Verification in Vivado

### 1. RTL Simulation
```bash
# In Vivado
add_files -fileset sim_1 {
  ../sim/tb_emu_uart.v
  ../sim/tb_emu_spi_master.v
  ../sim/tb_emu_i2c_master.v
  ../sim/tb_m3.v
  ../sim/tb_host_if.v
}
set_property top tb_emu_uart [get_filesets sim_1]
launch_simulation
```

### 2. Gate-Level Simulation with SDF
```tcl
# After implementation
write_sdf -force post_route.sdf
# Add SDF to testbench
set_property GENERIC_SDF_FILE post_route.sdf [get_filesets sim_1]
launch_simulation
```

### 3. Formal Verification (Optional)
```bash
# CPU pipeline properties
sby -f cpu_core.sby
# Timer NCO accuracy
sby -f timer_coproc.sby
```

## Example Firmware Loading (Post-Silicon)

```python
# Python SPI loader for production
import spidev

spi = spidev.SpiDev()
spi.open(0, 0)
spi.mode = 0
spi.max_speed_hz = 10_000_000

def spi_write(addr, data32):
    frame = (data32 << 24) | (addr << 8) | 0x01
    spi.xfer3(frame.to_bytes(8, 'big'))

def spi_run(length):
    frame = (length << 8) | 0x03
    spi.xfer3(frame.to_bytes(8, 'big'))

# Load UART firmware
with open('firmware/uart.bin', 'rb') as f:
    words = [int.from_bytes(f.read(2), 'little') for _ in range(len(f.read())//2)]

for i, word in enumerate(words[::2]):
    spi_write(i*2, (words[i*2+1] << 16) | word)

spi_run(len(words)*2)
```

