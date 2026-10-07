# SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
# SPDX-License-Identifier: Apache-2.0
#
# run_unit_tests.tcl — Script Vivado untuk menjalankan semua unit testbench
# Jalankan dari: vivado -mode batch -source tb/run_unit_tests.tcl
#
# Struktur direktori:
#   rtl/    — semua file RTL (.v)
#   tb/     — semua testbench (_unit_*.sv)

set ROOT [file normalize [file dirname [info script]]/..]
set RTL  $ROOT/rtl
set TB   $ROOT/tb

# ============================================================
# Fungsi: compile RTL + satu testbench, lalu jalankan simulasi
# ============================================================
proc run_tb {tb_name {extra_sv ""}} {
    global RTL TB

    set work_dir "work_${tb_name}"

    # Buat project xsim sementara
    set flist [list \
        $RTL/hash_adder.v \
        $RTL/hram.v \
        $RTL/k_rom.v \
        $RTL/mc.v \
        $RTL/me.v \
        $RTL/pad_fn.v \
        $RTL/sha256_fsm.v \
        $RTL/wram.v \
    ]

    # Compile RTL + testbench dengan xvlog
    set incdir "+incdir+$RTL"

    set cmd_rtl "xvlog -sv $incdir"
    foreach f $flist { append cmd_rtl " $f" }
    puts "Compiling RTL: $cmd_rtl"
    catch {eval exec $cmd_rtl} err
    if {$err ne ""} { puts "Note: $err" }

    set cmd_tb "xvlog -sv $incdir $TB/${tb_name}.sv"
    puts "Compiling TB: $cmd_tb"
    catch {eval exec $cmd_tb} err
    if {$err ne ""} { puts "Note: $err" }

    # Elaborate
    set cmd_elab "xelab -debug typical $tb_name -s ${tb_name}_snap"
    puts "Elaborating: $cmd_elab"
    catch {eval exec $cmd_elab} err
    if {$err ne ""} { puts "Note: $err" }

    # Simulate
    set cmd_sim "xsim ${tb_name}_snap -runall"
    puts "Running: $cmd_sim"
    catch {eval exec $cmd_sim} result
    puts "Result:\n$result"
    puts "---------------------------------------------------"
}

# ============================================================
# Daftar semua unit testbench
# ============================================================
puts ""
puts "============================================================"
puts "SHA-256 Accelerator — Unit Testbench Suite (Vivado xsim)"
puts "============================================================"
puts ""

run_tb "tb_unit_k_rom"
run_tb "tb_unit_wram"
run_tb "tb_unit_me"
run_tb "tb_unit_hash_adder"
run_tb "tb_unit_hram"
run_tb "tb_unit_pad_fn"
run_tb "tb_unit_mc"
run_tb "tb_unit_sha256_fsm"

puts ""
puts "============================================================"
puts "Semua unit testbench selesai dijalankan"
puts "============================================================"
puts ""
