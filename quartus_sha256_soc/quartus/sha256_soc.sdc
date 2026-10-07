# sha256_soc.sdc — Timing Constraints for SHA-256 Accelerator
# Target: Intel Cyclone V SoC DE10-Nano (5CSEBA6U23I7)
# Fmax target: 100 MHz

# ---- Main clock (standalone compilation) ----
# When using Platform Designer, remove create_clock (use derive_pll_clocks instead)
create_clock -name clk -period 10.000 [get_ports clk]

# ---- Derived clocks from PLL ----
derive_pll_clocks

# ---- Clock uncertainty ----
derive_clock_uncertainty

# ---- I/O constraints (standalone, adjust base address offsets as needed) ----
# Virtual clock for I/O paths (for standalone compilation without Platform Designer)
# create_clock -name vclk -period 10.000

# Uncomment and adjust for standalone:
# set_input_delay  -clock vclk -max 2.0 [get_ports avs_*]
# set_output_delay -clock vclk -max 2.0 [get_ports avs_readdata*]
# set_output_delay -clock vclk -max 2.0 [get_ports irq]

# ---- False paths (async reset) ----
# reset_n may be asserted asynchronously; no timing on it
set_false_path -from [get_ports reset_n] -to [all_registers]

# ---- Multicycle paths (readLatency=1 Avalon; readdata registered) ----
# avs_readdata is valid the cycle after avs_read; already modeled by readLatency=1
