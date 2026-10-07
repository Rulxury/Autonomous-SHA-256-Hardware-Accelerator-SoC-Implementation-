// sha256_accelerator_hw.tcl — Platform Designer (Qsys) component descriptor
// SHA-256 Accelerator Avalon-MM slave component for DE10-Nano HPS integration

package require -exact qsys 14.0

#
# Module
#
set_module_property DESCRIPTION     "SHA-256 Hardware Accelerator (Avalon-MM Slave)"
set_module_property NAME            sha256_accelerator
set_module_property VERSION         2.0
set_module_property INTERNAL        false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property AUTHOR          "Peruri"
set_module_property DISPLAY_NAME    "SHA-256 Accelerator"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE        true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false

#
# File sets
#
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL sha256_accelerator

foreach f {
    sha256_defs.vh
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
    add_fileset_file $f VERILOG PATH ../rtl/$f
}

#
# Parameters
#
add_parameter LEGACY_EN INTEGER 1 "Enable Legacy Step Mode (0=disable for lower area)"
set_parameter_property LEGACY_EN DEFAULT_VALUE 1
set_parameter_property LEGACY_EN DISPLAY_NAME  "Enable Legacy Step Mode"
set_parameter_property LEGACY_EN TYPE          INTEGER
set_parameter_property LEGACY_EN UNITS         None
set_parameter_property LEGACY_EN ALLOWED_RANGES {0:1}
set_parameter_property LEGACY_EN HDL_PARAMETER true

#
# Clock sink
#
add_interface clk clock end
set_interface_property clk clockRate 0
set_interface_property clk ENABLED true
add_interface_port clk clk clk Input 1

#
# Reset sink
#
add_interface reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

#
# Avalon-MM slave
#
add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clk
set_interface_property s0 associatedReset reset
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 burstCountUnits WORDS
set_interface_property s0 burstOnBurstBoundariesOnly false
set_interface_property s0 burstcountUnits WORDS
set_interface_property s0 explicitAddressSpan 0
set_interface_property s0 holdTime 0
set_interface_property s0 linewrapBursts false
set_interface_property s0 maximumPendingAllowedTransactions 0
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 minimumResponseLatency 1
set_interface_property s0 readLatency 1
set_interface_property s0 readWaitTime 0
set_interface_property s0 setupTime 0
set_interface_property s0 timingUnits Cycles
set_interface_property s0 writeWaitTime 0
set_interface_property s0 ENABLED true

add_interface_port s0 avs_address   address   Input   6
add_interface_port s0 avs_read      read      Input   1
add_interface_port s0 avs_write     write     Input   1
add_interface_port s0 avs_writedata writedata Input   32
add_interface_port s0 avs_readdata  readdata  Output  32

set_interface_assignment s0 embeddedsw.configuration.isFlash 0
set_interface_assignment s0 embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment s0 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s0 embeddedsw.configuration.isPrintableDevice 0

#
# Interrupt sender
#
add_interface irq_sender interrupt end
set_interface_property irq_sender associatedAddressablePoint s0
set_interface_property irq_sender associatedClock clk
set_interface_property irq_sender associatedReset reset
set_interface_property irq_sender ENABLED true
add_interface_port irq_sender irq irq Output 1
