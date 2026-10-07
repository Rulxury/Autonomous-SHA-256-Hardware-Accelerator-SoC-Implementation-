onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 235ns
echo "Time 235ns:"
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.load_w
examine -radix hex tb_core_autopad.dut.round_en_w
run 10ns
echo "Time 245ns:"
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.load_w
examine -radix hex tb_core_autopad.dut.round_en_w
run 10ns
echo "Time 255ns:"
examine -radix dec tb_core_autopad.dut.u_fsm.state
examine -radix hex tb_core_autopad.dut.load_w
examine -radix hex tb_core_autopad.dut.round_en_w
examine -radix hex tb_core_autopad.dut.u_mc.register_file
examine -radix hex tb_core_autopad.dut.u_mc.hkw
quit -f
