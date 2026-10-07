// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_core_raw.sv — Fase 1: Core testbench Mode 0 (raw blocks, no auto-padding)
// Menguji vektor NIST: "abc" (1 blok pre-padded), back-to-back, timing 67 siklus.

`timescale 1ns/1ps

module tb_core_raw;

  // Clock / reset
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  // DUT signals
  reg         soft_rst, start_req;
  reg         first_in, last_in, auto_in;
  reg [31:0]  msg_len;
  reg         host_we;
  reg [3:0]   host_idx;
  reg [31:0]  host_data;
  reg         leg_step_req, leg_we;
  reg [3:0]   leg_idx;
  reg [31:0]  leg_data;

  wire        fsm_busy, blk_inc, done_pulse, msg_done_pulse;
  wire [5:0]  round;
  wire [255:0] digest, state_dbg;
  wire [31:0]  leg_w, leg_k;

  sha256_core #(.LEGACY_EN(1)) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .soft_rst       (soft_rst),
    .start_req      (start_req),
    .first_in       (first_in),
    .last_in        (last_in),
    .auto_in        (auto_in),
    .msg_len_reg    (msg_len),
    .host_we        (host_we),
    .host_idx       (host_idx),
    .host_data      (host_data),
    .leg_step_req   (leg_step_req),
    .leg_we         (leg_we),
    .leg_idx        (leg_idx),
    .leg_data       (leg_data),
    .fsm_busy       (fsm_busy),
    .round          (round),
    .blk_inc        (blk_inc),
    .done_pulse     (done_pulse),
    .msg_done_pulse (msg_done_pulse),
    .digest         (digest),
    .state_dbg      (state_dbg),
    .leg_w          (leg_w),
    .leg_k          (leg_k)
  );

  integer fail_cnt;
  integer cyc_count;

  // Task: write one WRAM word
  task write_wram;
    input [3:0] idx;
    input [31:0] val;
    begin
      @(negedge clk);
      host_we   = 1'b1;
      host_idx  = idx;
      host_data = val;
      @(posedge clk); #1;
      host_we   = 1'b0;
    end
  endtask

  // Task: write full 'abc' padded block
  task write_block_abc;
    begin
      write_wram(4'd0,  32'h61626380);
      write_wram(4'd1,  32'h00000000);
      write_wram(4'd2,  32'h00000000);
      write_wram(4'd3,  32'h00000000);
      write_wram(4'd4,  32'h00000000);
      write_wram(4'd5,  32'h00000000);
      write_wram(4'd6,  32'h00000000);
      write_wram(4'd7,  32'h00000000);
      write_wram(4'd8,  32'h00000000);
      write_wram(4'd9,  32'h00000000);
      write_wram(4'd10, 32'h00000000);
      write_wram(4'd11, 32'h00000000);
      write_wram(4'd12, 32'h00000000);
      write_wram(4'd13, 32'h00000000);
      write_wram(4'd14, 32'h00000000);
      write_wram(4'd15, 32'h00000018);
    end
  endtask

  // Task: send START pulse (Mode 0)
  task send_start_m0;
    input do_first;
    input do_last;
    begin
      @(negedge clk);
      start_req = 1'b1;
      first_in  = do_first;
      last_in   = do_last;
      auto_in   = 1'b0;
      @(posedge clk); #1;
      start_req = 1'b0;
    end
  endtask

  // Task: wait for done_pulse, measure cycles
  task wait_done;
    output integer cycles;
    begin
      cycles = 0;
      while (!done_pulse) begin
        @(posedge clk); #1;
        cycles = cycles + 1;
      end
      @(posedge clk); #1;
    end
  endtask

  // Task: check digest
  task check_digest;
    input [255:0] expected;
    input [127:0] test_name_unused;
    begin
      if (digest !== expected) begin
        $display("FAIL: digest mismatch");
        $display("  got:      %064h", digest);
        $display("  expected: %064h", expected);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("PASS: digest correct");
      end
    end
  endtask

  initial begin
    $display("tb_core_raw — Fase 1 Mode 0 test");
    fail_cnt    = 0;
    rst_n       = 1'b0;
    soft_rst    = 1'b0;
    start_req   = 1'b0;
    first_in    = 1'b0;
    last_in     = 1'b0;
    auto_in     = 1'b0;
    msg_len     = 32'h0;
    host_we     = 1'b0;
    host_idx    = 4'h0;
    host_data   = 32'h0;
    leg_step_req= 1'b0;
    leg_we      = 1'b0;
    leg_idx     = 4'h0;
    leg_data    = 32'h0;

    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // ================================================================
    // TEST 1: "abc" — NIST SHA-256
    // Pre-padded block (big-endian words):
    // 61626380 00000000 00000000 00000000
    // 00000000 00000000 00000000 00000000
    // 00000000 00000000 00000000 00000000
    // 00000000 00000000 00000000 00000018
    // Expected: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    // ================================================================
    $display("--- Test 1: 'abc' (NIST) ---");

    write_block_abc();

    cyc_count = 0;
    send_start_m0(1'b1, 1'b1);
    wait_done(cyc_count);

    $display("  Cycles: %0d (expected 66, counted from done_pulse)", cyc_count);
    if (cyc_count !== 66)
      $display("  WARN: cycle count %0d != 66", cyc_count);

    check_digest(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, 0);

    repeat(2) @(posedge clk);

    // ================================================================
    // TEST 2: Empty string ""
    // One block: 80000000 ... 00000000 (length=0)
    // Expected: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    // ================================================================
    $display("--- Test 2: empty string ---");

    write_wram(4'd0,  32'h80000000);
    write_wram(4'd1,  32'h00000000);
    write_wram(4'd2,  32'h00000000);
    write_wram(4'd3,  32'h00000000);
    write_wram(4'd4,  32'h00000000);
    write_wram(4'd5,  32'h00000000);
    write_wram(4'd6,  32'h00000000);
    write_wram(4'd7,  32'h00000000);
    write_wram(4'd8,  32'h00000000);
    write_wram(4'd9,  32'h00000000);
    write_wram(4'd10, 32'h00000000);
    write_wram(4'd11, 32'h00000000);
    write_wram(4'd12, 32'h00000000);
    write_wram(4'd13, 32'h00000000);
    write_wram(4'd14, 32'h00000000);
    write_wram(4'd15, 32'h00000000);

    send_start_m0(1'b1, 1'b1);
    wait_done(cyc_count);
    check_digest(256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, 0);

    repeat(2) @(posedge clk);

    // ================================================================
    // TEST 3: Back-to-back "abc" twice
    // ================================================================
    $display("--- Test 3: back-to-back 'abc' twice ---");

    write_block_abc();

    send_start_m0(1'b1, 1'b1);
    wait_done(cyc_count);
    $display("  First 'abc': cycles=%0d", cyc_count);
    check_digest(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, 0);

    // Second "abc" immediately
    write_block_abc();
    send_start_m0(1'b1, 1'b1);
    wait_done(cyc_count);
    $display("  Second 'abc': cycles=%0d", cyc_count);
    check_digest(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, 0);

    // ================================================================
    // RESULT
    // ================================================================
    repeat(4) @(posedge clk);
    if (fail_cnt == 0)
      $display("tb_core_raw PASS (all tests)");
    else
      $display("tb_core_raw FAIL (%0d failures)", fail_cnt);
    $finish;
  end

  initial begin
    #2000000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
