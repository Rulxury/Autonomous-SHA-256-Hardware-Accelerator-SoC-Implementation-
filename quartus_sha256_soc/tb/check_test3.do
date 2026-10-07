onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 2200ns
echo "=== Test 3 WRAM at LOAD ==="
examine -radix hex tb_core_autopad.dut.u_wram.w
echo "=== Test 3 h_base ==="
examine -radix hex tb_core_autopad.dut.h_base_w
echo "=== Test 3 first_eff ==="
examine tb_core_autopad.dut.first_eff_w
quit -f
