onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 220ns
echo "=== WRAM at t=220ns (LOAD) ==="
examine -radix hex tb_core_autopad.dut.u_wram.w
echo "=== h_base at t=220ns ==="
examine -radix hex tb_core_autopad.dut.h_base_w
echo "=== k_val at t=220ns ==="
examine -radix hex tb_core_autopad.dut.k_val_w
echo "=== w_n at t=220ns ==="
examine -radix hex tb_core_autopad.dut.w_n_w
echo "=== hkw after LOAD ==="
run 10ns
examine -radix hex tb_core_autopad.dut.u_mc.hkw
examine -radix hex tb_core_autopad.dut.u_mc.register_file
quit -f
