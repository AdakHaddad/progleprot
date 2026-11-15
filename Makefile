# Protocol Discovery Core - Makefile

IVERILOG = iverilog -g2012
VVP = vvp
PS2_RTL = rtl/edge_interval.v rtl/histogram.v rtl/log_bucket.v rtl/peak_detect.v rtl/m1_top.v rtl/ps2_detect.v
RTL = rtl/edge_interval.v rtl/histogram.v rtl/log_bucket.v rtl/peak_detect.v \
      rtl/m1_top.v rtl/uart_framer.v rtl/m2_top.v \
      rtl/encoding_layer.v \
      rtl/spi_detect.v rtl/i2c_detect.v rtl/m3_top.v \
      rtl/fingerprint_rom.v rtl/fingerprint_matcher.v rtl/ranked_output.v rtl/m4_top.v \
      rtl/pin_role_discovery.v rtl/m5_top.v \
      rtl/pdis_sequencer.v rtl/sequencer_compiler.v rtl/prog_rom.v rtl/m6_top.v \
      rtl/ps2_detect.v rtl/can_detect.v

.PHONY: all sim sweep m1 m2 m3 m4 m5 m6 ps2 clean

all: m1 m2 m3 m4 m5 m6

# M1: Edge interval + histogram + peak detect
m1:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m1.v
	$(VVP) sim.vvp

# M1 parameter sweep
sweep:
	for c in "2 12" "2 8" "1 8" "1 6"; do \
	  set -- $$c; \
	  echo "FRAC=$$1 BIN_W=$$2"; \
	  $(IVERILOG) -Ptb_m1.FRAC=$$1 -Ptb_m1.BIN_W=$$2 -o s.vvp $(RTL) sim/tb_m1.v && $(VVP) s.vvp | grep -E "FAIL|ALL"; \
	done

# M2: UART auto-baud + framing
m2:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m2.v
	$(VVP) sim.vvp

# M3: SPI + I2C detection
m3:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m3.v
	$(VVP) sim.vvp

# M4: Fingerprint matching + ranked output
m4:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m4.v
	$(VVP) sim.vvp

# M5: Pin-role discovery
m5:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m5.v
	$(VVP) sim.vvp

# M6: Full closed-loop (discovery -> compile -> replay)
m6:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m6.v
	$(VVP) sim.vvp

# M6 simple (discovery only, uses m5_top)
m6_simple:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m6_simple.v
	$(VVP) sim.vvp

# Debug M6 with sequencer monitoring
m6_debug:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_m6_debug.v
	$(VVP) sim.vvp

# Test sequencer compiler
test_compiler:
	$(IVERILOG) -o sim.vvp rtl/sequencer_compiler.v rtl/pdis_sequencer.v sim/tb_sequencer.v
	$(VVP) sim.vvp

# Test sequencer
test_sequencer:
	$(IVERILOG) -o sim.vvp rtl/pdis_sequencer.v rtl/sequencer_compiler.v sim/tb_sequencer2.v
	$(VVP) sim.vvp

# PS/2 test
ps2:
	$(IVERILOG) -o sim.vvp $(PS2_RTL) sim/tb_ps2.v
	$(VVP) sim.vvp

# CAN test
can:
	$(IVERILOG) -o sim.vvp $(RTL) sim/tb_can.v
	$(VVP) sim.vvp

# Quick smoke test (M1 only)
smoke: m1

clean:
	rm -f sim.vvp s.vvp *.vcd *.dump

# Run all tests with timeout
test_all: m1 m2 m3 m4 m5 m6 ps2

# Yosys area estimation (requires yosys installed)
yosys_area:
	@echo "read_verilog -sv $(RTL)" > synth.ys
	@echo "hierarchy -top m6_top" >> synth.ys
	@echo "synth -top m6_top -run coarse" >> synth.ys
	@echo "stat -tech ihp" >> synth.ys
	yosys synth.ys

# Vivado project generation
vivado_proj:
	mkdir -p vivado
	cd vivado && vivado -mode batch -source ../scripts/create_project.tcl

# Help
help:
	@echo "Targets:"
	@echo "  m1          - M1 tests (histogram/peak)"
	@echo "  sweep       - M1 parameter sweep"
	@echo "  m2          - M2 UART tests"
	@echo "  m3          - M3 SPI/I2C tests"
	@echo "  m4          - M4 fingerprint tests"
	@echo "  m5          - M5 pin-role discovery"
	@echo "  m6          - M6 full closed-loop"
	@echo "  m6_simple   - M6 discovery only"
	@echo "  m6_debug    - M6 with sequencer debug"
	@echo "  ps2         - PS/2 detector tests"
	@echo "  can         - CAN detector tests"
	@echo "  test_all    - Run all milestones"
	@echo "  yosys_area  - Quick area estimate"
	@echo "  clean       - Remove build artifacts"
