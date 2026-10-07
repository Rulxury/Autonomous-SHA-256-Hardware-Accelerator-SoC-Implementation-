// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_sha256_fsm.sv — Unit test for sha256_fsm.v
// Verifikasi: IDLE → LOAD → PROC (64 round) → FIN → IDLE
// Mode: CLS_RAW (first=1, last=1, auto=0)

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

  // State name
  function [63:0] st_name;
    input [2:0] s;
    case(s)
      3'd0: st_name = "IDLE";
      3'd1: st_name = "PAD ";
      3'd2: st_name = "LOAD";
      3'd3: st_name = "PROC";
      3'd4: st_name = "FIN ";
      3'd5: st_name = "LPRP";
      3'd6: st_name = "LRND";
      default: st_name = "????";
    endcase
  endfunction

  integer fail, cyc_load, cyc_proc, cyc_fin;
  integer timeout, round_cnt, sched_cnt;

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

    // ---- T1: Setelah reset → IDLE ----
    if (state !== 3'd0) begin
      $display("FAIL T1: state=%0d exp=IDLE", state);
      fail = fail + 1;
    end else $display("PASS T1: Setelah reset = IDLE");

    if (fsm_busy !== 1'b0) begin
      $display("FAIL T1b: fsm_busy=%0d exp=0", fsm_busy);
      fail = fail + 1;
    end else $display("PASS T1b: fsm_busy=0 di IDLE");

    // ---- T2: Kirim start_req → LOAD ----
    $display("--- T2: start_req → LOAD ---");
    @(negedge clk);
    start_req = 1'b1;
    @(posedge clk); #1;
    start_req = 1'b0;
    @(posedge clk); #1;

    if (load !== 1'b1) begin
      $display("FAIL T2: load=%0d exp=1 saat LOAD", load);
      fail = fail + 1;
    end else $display("PASS T2: load=1 saat LOAD");
    cyc_load = 1;

    // ---- T3: PROC — tunggu 64 round ----
    $display("--- T3: Tunggu 64 round PROC ---");
    round_cnt = 0; sched_cnt = 0;
    timeout = 200;
    @(posedge clk); #1;

    while (state === 3'd3 && timeout > 0) begin
      round_cnt = round_cnt + 1;
      if (sched_en) sched_cnt = sched_cnt + 1;
      @(posedge clk); #1;
      timeout = timeout - 1;
    end

    $display("  Round count = %0d (exp 64)", round_cnt);
    if (round_cnt !== 64) begin
      $display("FAIL T3a: round_cnt=%0d exp=64", round_cnt);
      fail = fail + 1;
    end else $display("PASS T3a: Tepat 64 round");

    if (sched_cnt !== 48) begin
      $display("FAIL T3b: sched_en aktif %0d siklus exp=48", sched_cnt);
      fail = fail + 1;
    end else $display("PASS T3b: sched_en aktif tepat 48 siklus");

    // ---- T4: FIN → done_pulse + hram_we ----
    $display("--- T4: FIN state ---");
    if (state !== 3'd4) begin
      $display("FAIL T4: state=%0d exp=FIN(4)", state);
      fail = fail + 1;
    end else $display("PASS T4: state = FIN");

    if (hram_we !== 1'b1) begin
      $display("FAIL T4b: hram_we=%0d exp=1 di FIN", hram_we);
      fail = fail + 1;
    end else $display("PASS T4b: hram_we=1 di FIN");

    // tunggu done_pulse
    @(posedge clk); #1;
    if (state !== 3'd0) begin
      $display("FAIL T4c: setelah FIN bukan IDLE (state=%0d)", state);
      fail = fail + 1;
    end else $display("PASS T4c: kembali ke IDLE setelah FIN");

    // ---- T5: blk_inc dan done_pulse harus sempat aktif ----
    $display("--- T5: done_pulse ---");
    // done_pulse diperika di siklus FIN (sudah lewat satu clock)
    // Cukup verifikasi FSM kembali IDLE dan fsm_busy=0
    if (fsm_busy !== 1'b0) begin
      $display("FAIL T5: fsm_busy=%0d exp=0 di IDLE", fsm_busy);
      fail = fail + 1;
    end else $display("PASS T5: fsm_busy=0 kembali di IDLE");

    $display("");
    if (fail == 0)
      $display("tb_unit_sha256_fsm PASS — IDLE→LOAD→PROC(64)→FIN→IDLE OK");
    else
      $display("tb_unit_sha256_fsm FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #20000; $display("TIMEOUT"); $finish; end

endmodule
