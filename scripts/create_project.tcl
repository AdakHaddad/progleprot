# Vivado project creation script for Protocol Discovery Core
# Run: vivado -mode batch -source scripts/create_project.tcl

create_project protocoldisc ./vivado -part xc7k70tfbv676-1 -force
# Note: Use IHP PDK part when available; xc7k70t for prototyping

# Add RTL sources
add_files {
    ../rtl/edge_interval.v
    ../rtl/histogram.v
    ../rtl/log_bucket.v
    ../rtl/peak_detect.v
    ../rtl/m1_top.v
    ../rtl/uart_framer.v
    ../rtl/m2_top.v
    ../rtl/spi_detect.v
    ../rtl/i2c_detect.v
    ../rtl/m3_top.v
    ../rtl/fingerprint_rom.v
    ../rtl/fingerprint_matcher.v
    ../rtl/ranked_output.v
    ../rtl/m4_top.v
    ../rtl/pin_role_discovery.v
    ../rtl/m5_top.v
    ../rtl/pdis_sequencer.v
    ../rtl/sequencer_compiler.v
    ../rtl/prog_rom.v
    ../rtl/m6_top.v
}

set_property top m6_top [current_fileset]

# Add constraints
add_files -fileset constrs_1 ../scripts/constr.xdc

# Synthesis settings
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY full [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Report utilization
open_run synth_1 -name netlist_1
report_utilization -hierarchical -file ../reports/utilization_m6.rpt
report_timing_summary -file ../reports/timing_m6.rpt
report_power -file ../reports/power_m6.rpt

# Also synthesize milestones individually for area tracking
foreach m {m1_top m2_top m3_top m4_top m5_top} {
    set_property top $m [current_fileset]
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    open_run synth_1 -name netlist_1
    report_utilization -hierarchical -file ../reports/utilization_${m}.rpt
}

# Restore top
set_property top m6_top [current_fileset]

puts "Synthesis complete. Reports in ../reports/"
