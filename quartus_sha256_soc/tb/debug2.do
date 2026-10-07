onerror {quit -f}
onbreak {quit -f}
vlib work
vlog +incdir+rtl rtl/hash_adder.v rtl/hram.v rtl/k_rom.v rtl/mc.v rtl/me.v rtl/pad_fn.v rtl/sha256_accelerator.v rtl/sha256_core.v rtl/sha256_csr.v rtl/sha256_fsm.v rtl/wram.v
vlog -sv +incdir+rtl tb/tb_core_autopad.sv
vsim -c tb_core_autopad
run 65ns
for {set t 70} {$t <= 240} {incr t 10} {
    run 10ns
    echo [format "t=%0dns state=%s shift_en=%s pad_cnt=%s w0=%s" $t [examine -radix dec tb_core_autopad.dut.u_fsm.state] [examine -radix dec tb_core_autopad.dut.shift_en_w] [examine -radix dec tb_core_autopad.dut.u_fsm.pad_cnt] [examine -radix hex tb_core_autopad.dut.w0_w]]
}
quit -f
