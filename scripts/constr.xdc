# Timing constraints for Protocol Discovery Core
# Target: IHP 130nm / Tiny Tapeout

# Clock definition - 50 MHz default (20 ns period)
# Adjust based on IHP PDK timing characterization
create_clock -period 20.000 -name clk -waveform {0.0 10.0} [get_ports clk]
set_clock_latency 0.5 [get_clocks clk]
set_clock_uncertainty 0.2 [get_clocks clk]

# Input delays - signals arrive relative to clk
# Assuming external signals synchronized to clk domain
set_input_delay -clock clk -min 0.5 [get_ports pins_in[*]]
set_input_delay -clock clk -max 2.0 [get_ports pins_in[*]]

# Control signals (async, but constrained for CDC analysis)
set_input_delay -clock clk -min 0.5 [get_ports clear]
set_input_delay -clock clk -max 2.0 [get_ports clear]
set_input_delay -clock clk -min 0.5 [get_ports scan_start]
set_input_delay -clock clk -max 2.0 [get_ports scan_start]
set_input_delay -clock clk -min 0.5 [get_ports replay_start]
set_input_delay -clock clk -max 2.0 [get_ports replay_start]

# Output delays - signals leave relative to clk
set_output_delay -clock clk -min 0.5 [get_ports pin_roles[*]]
set_output_delay -clock clk -max 2.0 [get_ports pin_roles[*]]

set_output_delay -clock clk -min 0.5 [get_ports role_valid[*]]

set_output_delay -clock clk -min 0.5 [get_ports result_valid]
set_output_delay -clock clk -max 2.0 [get_ports result_proto[*] result_conf[*] result_rank[*]]

set_output_delay -clock clk -min 0.5 [get_ports list_done]
set_output_delay -clock clk -max 2.0 [get_ports list_done]

set_output_delay -clock clk -min 0.5 [get_ports ambiguous]

# Sequencer outputs
set_output_delay -clock clk -min 0.5 [get_ports replay_done]
set_output_delay -clock clk -max 2.0 [get_ports replay_error]
set_output_delay -clock clk -min 0.5 [get_ports seq_pc[*]]

# Debug/status outputs
set_output_delay -clock clk -min 0.5 [get_ports idle]
set_output_delay -clock clk -max 2.0 [get_ports peak_idx[*]]
set_output_delay -clock clk -max 2.0 [get_ports peak_count[*]]

# False paths for async control (these are single-cycle pulses)
# In real design, these would be synchronized first
set_false_path -from [get_ports clear] -to [all_registers]
set_false_path -from [get_ports scan_start] -to [all_registers]
set_false_path -from [get_ports replay_start] -to [all_registers]

# Pin roles output is combinational from registered state - no false path needed

# Area/dont_touch for SRAM macros (when IHP PDK available)
# set_dont_touch [get_cells -hierarchical *prog_rom*]
# set_dont_touch [get_cells -hierarchical *fingerprint_rom*]

# Clock grouping (single domain)
# No CDC constraints needed - single clock

# Max delay for combinational paths (if needed)
# set_max_delay -from [get_cells -hierarchical *histogram*] -to [get_cells -hierarchical *peak_detect*] 5.0

