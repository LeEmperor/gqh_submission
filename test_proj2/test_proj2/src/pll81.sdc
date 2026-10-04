# 27 MHz reference, with the actual 3x PLL relationship explicitly constrained.
create_clock -name sys_clk -period 37.037 [get_ports {sys_clk}]
create_generated_clock -name core_clk -source [get_ports {sys_clk}] -multiply_by 3 [get_pins {pll/rpll_inst/CLKOUT}]
