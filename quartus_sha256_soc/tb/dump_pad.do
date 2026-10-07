onerror {quit -f}
onbreak {quit -f}
vsim -c tb_core_autopad
run 65ns
for {set t 70} {$t <= 240} {incr t 10} {
    run 10ns
    echo [format "t=%0dns state=%s shift_en=%s pad_cnt=%s pad_y=%s w0=%s w15=%s" $t [examine -radix dec tb_core_autopad.dut.u_fsm.state] [examine -radix dec tb_core_autopad.dut.shift_en_w] [examine -radix dec tb_core_autopad.dut.u_fsm.pad_cnt] [examine -radix hex tb_core_autopad.dut.pad_y_w] [examine -radix hex tb_core_autopad.dut.w0_w] [examine -radix hex tb_core_autopad.dut.u_wram.w(15)]]
}
echo "WRAM array at t=240ns:"
examine -radix hex tb_core_autopad.dut.u_wram.w
quit -f
