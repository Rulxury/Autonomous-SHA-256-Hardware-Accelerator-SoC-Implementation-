onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 235ns
echo "=== AT t=235ns (LOAD state) ==="
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.u_wram.w
examine -radix hex tb_core_autopad.dut.h_base_w
examine -radix hex tb_core_autopad.dut.k_val_w
examine -radix hex tb_core_autopad.dut.w_n_w
examine -radix hex tb_core_autopad.dut.u_mc.hkw
run 10ns
echo "=== AT t=245ns (PROC cycle 0) ==="
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.u_wram.w
examine -radix hex tb_core_autopad.dut.u_mc.hkw
quit -f
