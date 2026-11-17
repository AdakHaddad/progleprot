# Vivado Synthesis Flow for Tiny Tapeout IHP

## Prerequisites
- Vivado 2023.2+
- IHP 130nm PDK installed
- Tiny Tapeout IHP user project template

## Project Structure
```
project/
├── src/
│   └── project.v              # Top-level wrapper (includes tt_um_protocol_emu.v)
├── rtl/
│   ├── tt_um_protocol_emu.v   # TT IHP wrapper
│   ├── pdis_sequencer.v       # Instruction sequencer
│   ├── prog_ram.v             # Dual-port program RAM
│   └── host_if.v              # SPI host interface
├── sim/
│   ├── tb_host_if.v           # Host IF unit test
│   ├── tb_emu_uart.v          # UART TX integration test
│   └── tb_emu_sample.v        # SAMPLE instruction test
├── constraints/
│   └── timing.xdc             # Timing constraints
└── docs/
    ├── ISA.md                 # Instruction set reference
    ├── USAGE.md               # This file
    └── VIVADO.md              # This file
```

## Vivado Project Setup

### 1. Create Project
```tcl
# In Vivado Tcl console
create_project protocol_emu ./project -part ihp_sg13g2
# Note: IHP part name depends on PDK installation
```

### 2. Add Sources
```tcl
add_files {
  ../src/project.v
  ../rtl/tt_um_protocol_emu.v
  ../rtl/pdis_sequencer.v
  ../rtl/prog_ram.v
  ../rtl/host_if.v
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

## Timing Constraints (timing.xdc)

```tcl
# Clock: 10-50 MHz typical for protocol emulation
create_clock -period 20.0 -name clk [get_ports clk]

# Input/output delays for SPI host interface
set_input_delay -clock clk -max 2.0 [get_ports uio_in[0]]   # SCK
set_input_delay -clock clk -max 2.0 [get_ports uio_in[1]]   # MOSI
set_input_delay -clock clk -max 2.0 [get_ports uio_in[2]]   # CS_N
set_output_delay -clock clk -max 3.0 [get_ports uio_out[0]] # MISO

# Protocol pins - no strict timing (software timed)
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

# Reset
set_property ASYNC_REG true [get_cells -hierarchical *rst*]
```

## IHP 130nm Specific Notes

### Memory Configuration
The `prog_ram` uses dual-port distributed RAM. For IHP:
- 256 × 32 = 8192 bits
- Maps to ~16K gates (LUTRAM)
- Should fit in available block RAM or distributed RAM

### Power/Clock Gating
```tcl
# If using power domains
create_power_domain -name PD_CORE -elements [get_cells -hierarchical u_sequencer]
create_power_domain -name PD_RAM -elements [get_cells -hierarchical u_prog_ram]
```

### Area Budget
TT IHP: 8×4 tiles ≈ 32K cells
- Estimated: ~18K cells (56% utilization)
- Room for: additional protocols, larger RAM, debug features

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
# Check: WNS > 0 (no violations at target frequency)
```

### 3. Critical Path
Typical critical path:
```
host_if SPI shift register -> prog_ram write -> sequencer fetch -> pin output
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

# Generate bitstream (if applicable)
write_bitstream -force protocol_emu.bit
```

## TT IHP Submission Checklist

- [ ] Synthesis passes without errors
- [ ] Timing meets at 50MHz (20ns period)
- [ ] Area < 32K cells
- [ ] DRC clean
- [ ] Power within budget
- [ ] All testbenches pass simulation
- [ ] RTL linting clean (spyglass/verilator)
- [ ] Documentation complete (ISA.md, USAGE.md)
- [ ] GDSII generated (via TT flow)

## Troubleshooting

### Common Issues

**RAM inference fails:**
- Ensure `prog_ram.v` uses `reg [WIDTH-1:0] mem [0:DEPTH-1]`
- Add `(* ram_style = "distributed" *)` attribute if needed

**Timing violations on SPI interface:**
- SPI is async to clk, use `set_false_path`
- Or add synchronizers in host_if

**Area too large:**
- Reduce PROG_DEPTH from 256 to 128
- Reduce NUM_REGS from 4 to 2
- Use smaller REG_W (8-bit instead of 16-bit)

**Simulation/synthesis mismatch:**
- Check for blocking vs non-blocking assignments
- Ensure reset polarity consistent (active low rst_n)
- Verify initial blocks synthesize correctly

## Yosys Alternative (Open Source)

```bash
# Quick area estimate without Vivado
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

This provides gate-level cell count for area budgeting.
