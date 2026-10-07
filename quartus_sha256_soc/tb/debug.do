onerror {quit -f}
onbreak {quit -f}
vlib work
vlog +incdir+rtl rtl/hash_adder.v rtl/hram.v rtl/k_rom.v rtl/mc.v rtl/me.v rtl/pad_fn.v rtl/sha256_accelerator.v rtl/sha256_core.v rtl/sha256_csr.v rtl/sha256_fsm.v rtl/wram.v
vlog -sv +incdir+rtl tb/tb_core_autopad.sv
vsim -c tb_core_autopad
run 215ns
echo "=== AT 215ns (PAD cycle 14) ==="
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix dec tb_core_autopad.dut.u_fsm.pad_cnt
examine -radix hex tb_core_autopad.dut.pad_y_w
examine -radix hex tb_core_autopad.dut.w0_w
examine -radix hex tb_core_autopad.dut.u_wram.w
run 10ns
echo "=== AT 225ns (PAD cycle 15) ==="
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix dec tb_core_autopad.dut.u_fsm.pad_cnt
examine -radix hex tb_core_autopad.dut.pad_y_w
examine -radix hex tb_core_autopad.dut.w0_w
examine -radix hex tb_core_autopad.dut.u_wram.w
run 10ns
echo "=== AT 235ns (LOAD or PROC) ==="
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.w0_w
examine -radix hex tb_core_autopad.dut.shift_in_w
examine -radix hex tb_core_autopad.dut.u_wram.w
quit -f
