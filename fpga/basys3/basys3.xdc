## Basys3 XDC Constraints for Protocol Emulator Demo
## Artix-7 XC7A35T-1CPG236C

## Clock
set_property -dict { PACKAGE_PIN W5    IOSTANDARD LVCMOS33 } [get_ports clk_100mhz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk_100mhz]

## Reset Button (BTN0 - active high)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports btn0]

## Switches
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## LEDs
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN V3    IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## PMOD JA (8 pins) - Standard PMOD Header
set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports {ja[0]}]
set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports {ja[1]}]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports {ja[2]}]
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports {ja[3]}]
set_property -dict { PACKAGE_PIN F15   IOSTANDARD LVCMOS33 } [get_ports {ja[4]}]
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports {ja[5]}]
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports {ja[6]}]
set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports {ja[7]}]

## PMOD JB (8 pins) - For I2S or extra I/O
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports {jb[0]}]
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports {jb[1]}]
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports {jb[2]}]
set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports {jb[3]}]
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports {jb[4]}]
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports {jb[5]}]
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports {jb[6]}]
set_property -dict { PACKAGE_PIN H18   IOSTANDARD LVCMOS33 } [get_ports {jb[7]}]

## UART (USB-UART Bridge)
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports uart_rx]
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports uart_tx]

## SPI Flash (Quad SPI)
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports spi_cs_n]
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports spi_sck]
set_property -dict { PACKAGE_PIN K14   IOSTANDARD LVCMOS33 } [get_ports spi_mosi]
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports spi_miso]

## Timing Constraints
# 50MHz internal clock (from clk_100mhz / 2)
create_clock -add -name clk_50mhz -period 20.00 [get_pins basys3_protocol_emu/clk_50mhz_reg/Q]

# False path between 100MHz and 50MHz domains
set_false_path -from [get_clocks sys_clk_pin] -to [get_clocks clk_50mhz]
set_false_path -from [get_clocks clk_50mhz] -to [get_clocks sys_clk_pin]

## PMOD IO constraints
set_property SLEW FAST [get_ports ja*]
set_property DRIVE 12 [get_ports ja*]
set_property SLEW FAST [get_ports jb*]
set_property DRIVE 12 [get_ports jb*]
