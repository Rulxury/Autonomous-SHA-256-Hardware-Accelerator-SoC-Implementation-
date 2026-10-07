// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_sha256_fsm.sv - Unit test for sha256_fsm.v
// Verifikasi: IDLE -> LOAD -> PROC (64 round) -> FIN -> IDLE
// Mode: CLS_RAW (first=1, last=1, auto=0)
//
// CATATAN TIMING: semua output kontrol sha256_fsm adalah REGISTER yang diisi
// saat state tertentu, sehingga muncul satu siklus SETELAH state tersebut:
//   - load     : tinggi di siklus pertama PROC (di-set pada state LOAD)
//   - round_en : 64 siklus, pulsa terakhir tinggi di siklus FIN
//   - sched_en : 48 siklus, pulsa terakhir tinggi di siklus FIN
//   - hram_we, done_pulse, blk_inc, msg_done_pulse : tinggi di siklus setelah
//     FIN (saat state sudah kembali IDLE)
// Urutan ini konsisten dengan datapath: round terakhir dieksekusi di akhir
// siklus FIN, lalu HRAM menulis di siklus berikutnya.

`timescale 1ns/1ps

module tb_unit_sha256_fsm;

  reg        clk, rst_n;
  reg        soft_rst, start_req;
  reg        first_in, last_in, auto_in;
  reg [31:0] msg_len_reg;
  reg        leg_step_req;

  wire       load, round_en, shift_en, hram_we;
  wire       leg_prep;
  wire [5:0] k_addr;
  wire       sched_en;
  wire [3:0] pad_cnt;
  wire [5:0] keep;
  wire       ins80, inslen;
  wire [63:0] len_bits;
  wire       fsm_busy;
  wire [5:0] round;
  wire       blk_inc, done_pulse, msg_done_pulse;
  wire       state_is_pad, first_eff;
  wire [2:0] state;

  initial clk = 0;
  always #5 clk = ~clk;

  sha256_fsm #(.LEGACY_EN(1)) dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .soft_rst        (soft_rst),
    .start_req       (start_req),
    .first_in        (first_in),
    .last_in         (last_in),
    .auto_in         (auto_in),
    .msg_len_reg     (msg_len_reg),
    .leg_step_req    (leg_step_req),
    .load            (load),
    .round_en        (round_en),
    .shift_en        (shift_en),
    .hram_we         (hram_we),
    .leg_prep        (leg_prep),
    .k_addr          (k_addr),
    .sched_en        (sched_en),
    .pad_cnt         (pad_cnt),
    .keep            (keep),
    .ins80           (ins80),
    .inslen          (inslen),
    .len_bits        (len_bits),
    .fsm_busy        (fsm_busy),
    .round           (round),
    .blk_inc         (blk_inc),
    .done_pulse      (done_pulse),
    .msg_done_pulse  (msg_done_pulse),
    .state_is_pad    (state_is_pad),
    .first_eff       (first_eff),
    .state           (state)
  );

  integer fail;
  integer timeout, proc_cnt, round_en_cnt, sched_cnt;

  // Cek nilai integer/bit; label berupa string
  task check_eq;
    input integer got;
    input integer exp;
    input string  label;
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got=%0d exp=%0d", label, got, exp);
        fail = fail + 1;
      end else
        $display("PASS %0s: %0d", label, got);
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_sha256_fsm: Test Mode CLS_RAW (1 blok)");
    $display("==============================================");
    fail = 0;
    soft_rst = 0; start_req = 0;
    first_in = 1; last_in = 1; auto_in = 0;
    msg_len_reg = 32'd0;
    leg_step_req = 0;
    rst_n = 0;
    repeat(3) @(posedge clk); #1;
    rst_n = 1;
    @(posedge clk); #1;

    // ---- T1: Setelah reset -> IDLE ----
    check_eq(state,    0, "T1  state=IDLE setelah reset");
    check_eq(fsm_busy, 0, "T1b fsm_busy=0 di IDLE");

    // ---- T2: start_req -> LOAD -> (load=1 tampil di siklus pertama PROC) ----
    $display("--- T2: start_req -> LOAD ---");
    @(negedge clk);
    start_req = 1'b1;
    @(posedge clk); #1;          // IDLE -> LOAD
    start_req = 1'b0;
    @(posedge clk); #1;          // LOAD -> PROC, load (register) = 1
    check_eq(load,  1, "T2  load=1 (siklus pertama PROC)");
    check_eq(state, 3, "T2b state=PROC setelah LOAD");

    // ---- T3: PROC - hitung siklus PROC, round_en, sched_en ----
    // Sampling mulai TEPAT di siklus PROC pertama (jangan tambah @(posedge) lagi).
    $display("--- T3: Hitung 64 siklus PROC ---");
    proc_cnt = 0; round_en_cnt = 0; sched_cnt = 0;
    timeout = 200;

    while (state === 3'd3 && timeout > 0) begin
      proc_cnt = proc_cnt + 1;
      if (round_en) round_en_cnt = round_en_cnt + 1;
      if (sched_en) sched_cnt    = sched_cnt + 1;
      @(posedge clk); #1;
      timeout = timeout - 1;
    end

    // Sekarang di siklus FIN: pulsa round_en dan sched_en terakhir masih tinggi
    check_eq(state, 4, "T4  state=FIN setelah PROC");
    if (round_en) round_en_cnt = round_en_cnt + 1;
    if (sched_en) sched_cnt    = sched_cnt + 1;
    check_eq(hram_we,    0, "T4a hram_we=0 di siklus FIN (register, naik 1 siklus kemudian)");
    check_eq(done_pulse, 0, "T4a done_pulse=0 di siklus FIN");

    check_eq(proc_cnt,     64, "T3a siklus state=PROC");
    check_eq(round_en_cnt, 64, "T3b jumlah siklus round_en");
    check_eq(sched_cnt,    48, "T3c jumlah siklus sched_en (W16..W63)");

    // ---- T4: Siklus setelah FIN: state=IDLE, pulsa selesai aktif ----
    $display("--- T4: Siklus setelah FIN ---");
    @(posedge clk); #1;
    check_eq(state,          0, "T4b state kembali IDLE");
    check_eq(hram_we,        1, "T4c hram_we=1 (tulis HRAM)");
    check_eq(done_pulse,     1, "T4d done_pulse=1");
    check_eq(blk_inc,        1, "T4e blk_inc=1");
    check_eq(msg_done_pulse, 1, "T4f msg_done_pulse=1 (last_in=1, auto=0)");
    check_eq(round_en,       0, "T4g round_en=0");
    check_eq(sched_en,       0, "T4h sched_en=0");

    // ---- T5: Pulsa 1 siklus, FSM idle ----
    $display("--- T5: Pulsa hanya 1 siklus ---");
    @(posedge clk); #1;
    check_eq(hram_we,    0, "T5  hram_we=0 (pulsa 1 siklus)");
    check_eq(done_pulse, 0, "T5a done_pulse=0 (pulsa 1 siklus)");
    check_eq(fsm_busy,   0, "T5b fsm_busy=0 di IDLE");

    $display("");
    if (fail == 0)
      $display("tb_unit_sha256_fsm PASS - IDLE->LOAD->PROC(64)->FIN->IDLE OK");
    else
      $display("tb_unit_sha256_fsm FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #20000; $display("TIMEOUT"); $finish; end

endmodule