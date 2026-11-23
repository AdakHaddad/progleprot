# Vivado TCL Script for Basys3 Protocol Emulator Demo
# Run in Vivado TCL Console: source build_vivado.tcl

create_project -force basys3_proto_emu ./basys3_proto_emu -part xc7a35tcpg236-1

# Add sources
add_files -norecurse \
    ../../rtl/emu_top.v \
    ../../rtl/cpu_core.v \
    ../../rtl/timer_coproc.v \
    ../../rtl/pin_matrix.v \
    ../../rtl/host_if.v \
    ../../rtl/prog_ram.v \
    ./basys3_protocol_emu.v \
    ./axi_lite_wrapper.v \
    ./uart_rx.v \
    ./uart_tx.v

# Add constraints
add_files -fileset constrs_1 -norecurse ./basys3.xdc

# Set top module
set_property top basys3_protocol_emu [current_fileset]

# Synthesis settings
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
    {-flatten_hierarchy full} [get_runs synth_1]

# Implementation settings  
set_property strategy Performance_Explore [get_runs impl_1]

# Generate bitstream
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -jobs 4
wait_on_run impl_1

write_bitstream -force $PROJECT_DIR/basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit

# Report utilization
report_utilization -file utilization.txt

# Report timing
report_timing_summary -file timing.txt

puts "Build complete! Bitstream at basys3_proto_emu.runs/impl_1/basys3_protocol_emu.bit"
