# Vivado / Tiny Tapeout Integration Guide

## Target
- **Process**: IHP 130nm CMOS5L (Tiny Tapeout)
- **Tiles**: 8x4 = 32 tiles (~1.0 mm^2, ~32K cells budget)
- **Shuttle**: March 2027

## Prerequisites

- Vivado 2024.1+ (or compatible)
- IHP PDK for Tiny Tapeout
- Yosys for pre-synthesis area estimates

## Synthesis Flow

### 1. Yosys Quick Area Check (per milestone)

```bash
# Create synthesis script
cat > synth.ys << 'EOF'
read_verilog -sv rtl/*.v
hierarchy -top m6_top
synth -top m6_top -run coarse
stat -tech ihp
EOF

yosys synth.ys
```

Expected cell counts (from architecture.md):
| Block | Est. Cells |
|-------|------------|
| M1 (edge_interval + histogram + peak) | 1.7K |
| M2 (uart_framer + m2_top) | 4.7K |
| M3 (spi_detect + i2c_detect) | 2.0K |
| M4 (fingerprint_rom + matcher) | 2.0K |
| M5 (pin_role_discovery) | 2.0K |
| M6 (pdis_sequencer x2 + compiler) | 4.0K |
| M8 (encoding_layer) | 1.5K |
| **Total** | **~20K** (37% margin under 32K) |

### 2. Vivado Project Setup

```tcl
# create_project.tcl
create_project protocoldisc ./vivado -part xc7k70tfbv676-1
# Note: Use IHP PDK part when available; xc7k70t for prototyping

# Add sources
add_files {
    rtl/edge_interval.v
    rtl/histogram.v
    rtl/log_bucket.v
    rtl/peak_detect.v
    rtl/m1_top.v
    rtl/uart_framer.v
    rtl/m2_top.v
    rtl/encoding_layer.v
    rtl/spi_detect.v
    rtl/i2c_detect.v
    rtl/m3_top.v
    rtl/fingerprint_rom.v
    rtl/fingerprint_matcher.v
    rtl/ranked_output.v
    rtl/m4_top.v
    rtl/pin_role_discovery.v
    rtl/m5_top.v
    rtl/pdis_sequencer.v
    rtl/sequencer_compiler.v
    rtl/prog_rom.v
    rtl/m6_top.v
    rtl/ps2_detect.v
    rtl/can_detect.v
}

# Set top
set_property top m6_top [current_fileset]

# Constraints
add_files -fileset constrs_1 constr.xdc
```

### 3. Clock & Timing Constraints

```tcl
# constr.xdc
# Single clock domain (all logic synchronous to clk)
create_clock -period 20.000 -name clk [get_ports clk]
set_clock_latency 0.5 [get_clocks clk]
set_clock_uncertainty 0.2 [get_clocks clk]

# Input/output delays (adjust for IHP IO)
set_input_delay -clock clk 2.0 [get_ports pins_in[*]]
set_output_delay -clock clk 2.0 [get_ports pin_roles[*]]
set_output_delay -clock clk 2.0 [get_ports result_*]

# False paths for async control
set_false_path -from [get_ports clear] -to [all_registers]
set_false_path -from [get_ports scan_start] -to [all_registers]
set_false_path -from [get_ports replay_start] -to [all_registers]
set_false_path -from [get_ports enc_mode_ch0] -to [all_registers]
set_false_path -from [get_ports stuff_after_ch0] -to [all_registers]
```

### 4. Run Synthesis

```tcl
# In Vivado Tcl console
synth_design -top m6_top -mode out_of_context
# Or with flattening for better area
synth_design -top m6_top -flatten_hierarchy full

# Check utilization
report_utilization -hierarchical
report_timing_summary
```

### 5. Area Optimization Knobs

| Parameter | Default | Minimal | Effect |
|-----------|---------|---------|--------|
| FRAC | 1 (32 bins) | 1 | 2->1 saves ~30% histogram |
| BIN_W | 8 | 6 | Saves ~20% histogram counters |
| MAX_PRINTS | 16 | 8 | Halves fingerprint ROM |
| N_COLLECT | 1024 | 512 | Reduces scan time |
| PROG_DEPTH | 256 | 128 | Halves sequencer program mem |

```bash
# Quick test minimal config
make FRAC=1 BIN_W=6 MAX_PRINTS=8 test_all
```

### 6. IHP-Specific Notes

- **SRAM Macros**: Use for prog_mem (256x32) and fingerprint_rom (16x64) if available
- **Clock Tree**: Single clock domain simplifies CDC
- **IO Pins**: 8 input + role outputs + debug + encoding ctrl = ~24 pins (check TT template)
- **Voltage**: 1.2V core, 1.8V/3.3V IO (verify with IHP PDK)

### 7. P&R Flow

```tcl
# After synthesis
opt_design
place_design
phys_opt_design
route_design
report_timing_summary
report_drc
report_power
```

### 8. TT Shuttle Checklist

- [ ] Design fits in 8x4 tiles
- [ ] No timing violations at target frequency
- [ ] DRC clean
- [ ] Power within budget
- [ ] GDS export matches TT format
- [ ] IO ring compatible with TT frame
- [ ] Test vectors generated for silicon bring-up

## Simulation Gate-Level

```bash
# After synthesis, generate gate-level netlist
write_verilog -force ./vivado/protocoldisc_synth.v

# Simulate with SDF timing
iverilog -g2012 -o sim.vvp ./vivado/protocoldisc_synth.v sim/tb_m6.v && vvp sim.vvp
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Area > 32K | Reduce FRAC, BIN_W, MAX_PRINTS, PROG_DEPTH |
| Timing violation | Pipeline histogram/peak detect; reduce clock freq |
| Latch inferred | Check all case/default branches in FSMs |
| X propagation | Ensure all registers have rst_n |

## Current Status

- All M1-M6 tests pass
- M8 encoding layer integrated (NRZ/NRZI/Manchester/Stuffing)
- PS/2 detector fixed and passing
- CAN detector created (untested)
- Ready for M7 synthesis area check
