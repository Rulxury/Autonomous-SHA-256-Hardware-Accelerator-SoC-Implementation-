# build.tcl — Quartus Prime Lite build script for SHA-256 SoC accelerator
# Target: Cyclone V 5CSEBA6U23I7 (DE10-Nano)
# Fmax: 100 MHz

package require ::quartus::project
package require ::quartus::flow

project_new sha256_soc -overwrite
set_global_assignment -name FAMILY           "Cyclone V"
set_global_assignment -name DEVICE           5CSEBA6U23I7
set_global_assignment -name TOP_LEVEL_ENTITY sha256_accelerator
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files

# sha256_defs.vh is an include file; add search path so `include resolves
set_global_assignment -name SEARCH_PATH ../rtl

# RTL source files (order matters: defs first, then leaf modules, then top)
foreach f {
    k_rom.v
    hram.v
    wram.v
    pad_fn.v
    me.v
    mc.v
    hash_adder.v
    sha256_fsm.v
    sha256_core.v
    sha256_csr.v
    sha256_accelerator.v
} {
    set_global_assignment -name VERILOG_FILE ../rtl/$f
}

# K-ROM MIF (use if $readmemh is replaced with .mif initialization)
# set_global_assignment -name MIF_FILE ../rtl/k_rom.mif

# Timing constraints
set_global_assignment -name SDC_FILE sha256_soc.sdc

# Optimization settings
set_global_assignment -name OPTIMIZATION_MODE "Balanced"
set_global_assignment -name PHYSICAL_SYNTHESIS_EFFORT Standard
set_global_assignment -name ROUTER_EFFORT_MULTIPLIER 1.0

# Compile
execute_flow -compile

# Report key metrics
load_report
set panel "Timing Analyzer||Multicorner Timing Analysis Summary"
set fmax [get_report_panel_data -name $panel -col_index 1 -row_index 0]
post_message "Fmax: $fmax"

project_close
