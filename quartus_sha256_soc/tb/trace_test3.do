onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 1900ns
echo "=== Test 3 start ==="
for {set i 0} {$i < 20} {incr i} {
    run 10ns
    echo [format "state=%s shift_en=%s pad_cnt=%s w0=%s pad_y=%s" [examine -radix dec tb_core_autopad.dut.u_fsm.state] [examine -radix dec tb_core_autopad.dut.shift_en_w] [examine -radix dec tb_core_autopad.dut.u_fsm.pad_cnt] [examine -radix hex tb_core_autopad.dut.w0_w] [examine -radix hex tb_core_autopad.dut.pad_y_w]]
}
quit -f
