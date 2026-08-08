create_clock -name fpga_clk -period 10 [get_ports fpga_clk]

# The AXI Interconnect performs the CDC between the 50 MHz CPU domain and the
# MIG ui_clk domain.  XDC files do not support Tcl control-flow commands such
# as "if", so keep this as the direct constraint prescribed by the lab guide.
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins U_clkgen/clk_out1]] \
    -group [get_clocks -of_objects [get_pins U_ddr/U_mig/ui_clk]]
