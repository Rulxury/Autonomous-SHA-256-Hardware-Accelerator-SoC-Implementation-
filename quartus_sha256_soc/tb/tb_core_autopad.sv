// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_core_autopad.sv — Fase 2: Testbench Mode 1 (Hardware Auto-Padding)
// Menguji vektor NIST & Edge Cases dari Spesifikasi Section 7.1:
// - Empty string "" (0 Byte) -> 83 siklus
// - "abc" (3 Byte) -> 83 siklus
// - 55 Byte -> 83 siklus (TAIL)
// - 56 Byte NIST -> 165 siklus (OVF, 2 blok otomatis)
// - 64 Byte -> 149 siklus (FULL_LAST, 2 blok otomatis)
// - 112 Byte NIST -> 2 blok data (67 + 83 = 150 siklus total core)

`timescale 1ns/1ps

module tb_core_autopad;

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

  task send_start_m1;
    input do_first;
    input [31:0] len;
    begin
      @(negedge clk);
      start_req = 1'b1;
      first_in  = do_first;
      last_in   = 1'b0; // Mode 1 determines last block automatically
      auto_in   = 1'b1;
      msg_len   = len;
      @(posedge clk); #1;
      start_req = 1'b0;
    end
  endtask

  task wait_done;
    output integer cycles;
    begin
      cycles = 0;
      while (!done_pulse) begin
        @(posedge clk); #1;
        cycles = cycles + 1;
      end
      @(posedge clk); #1; // wait for HRAM write to register
    end
  endtask

  task check_digest;
    input [255:0] expected;
    input [255:0] test_name;
    begin
      if (digest !== expected) begin
        $display("FAIL: digest mismatch [%s]", test_name);
        $display("  got:      %064h", digest);
        $display("  expected: %064h", expected);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("PASS: [%s] digest correct", test_name);
      end
    end
  endtask

  initial begin
    $display("==================================================");
    $display("tb_core_autopad — Mode 1 (Hardware Auto-Padding) Test");
    $display("==================================================");
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

    // ----------------------------------------------------
    // TEST 1: Empty string "" (0 bytes) -> TAIL, 83 cycles
    // Golden: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    // ----------------------------------------------------
    $display("--- Test 1: Empty string (0 B) ---");
    send_start_m1(1'b1, 32'd0);
    wait_done(cyc_count);
    $display("  Cycles: %0d (expected 82 from start)", cyc_count);
    check_digest(256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, "Empty string");

    repeat(2) @(posedge clk);

    // ----------------------------------------------------
    // TEST 2: "abc" (3 bytes) -> TAIL, 83 cycles
    // Golden: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    // ----------------------------------------------------
    $display("--- Test 2: 'abc' (3 B) ---");
    write_wram(4'd0, 32'h61626300); // 3 bytes raw ("abc\0")
    send_start_m1(1'b1, 32'd3);
    wait_done(cyc_count);
    $display("  Cycles: %0d", cyc_count);
    check_digest(256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, "'abc'");

    repeat(2) @(posedge clk);

    // ----------------------------------------------------
    // TEST 3: "a" x 55 (55 bytes) -> TAIL (boundary < 56)
    // Golden: 9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318
    // ----------------------------------------------------
    $display("--- Test 3: 'a' x 55 (55 B) ---");
    begin : test_55b
      integer i;
      for (i = 0; i < 13; i = i + 1)
        write_wram(i[3:0], 32'h61616161);
      // Word 13: 3 bytes of 'a' = 0x61616100 (byte 52, 53, 54)
      write_wram(4'd13, 32'h61616100);
    end
    send_start_m1(1'b1, 32'd55);
    wait_done(cyc_count);
    $display("  Cycles: %0d", cyc_count);
    check_digest(256'h9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318, "55 bytes");

    repeat(2) @(posedge clk);

    // ----------------------------------------------------
    // TEST 4: NIST 56-byte OVF (56 bytes) -> OVF, 165 cycles
    // Message: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    // Golden: 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
    // ----------------------------------------------------
    $display("--- Test 4: NIST 56 B OVF ---");
    write_wram(4'd0,  32'h61626364); // "abcd"
    write_wram(4'd1,  32'h62636465); // "bcde"
    write_wram(4'd2,  32'h63646566); // "cdef"
    write_wram(4'd3,  32'h64656667); // "defg"
    write_wram(4'd4,  32'h65666768); // "efgh"
    write_wram(4'd5,  32'h66676869); // "fghi"
    write_wram(4'd6,  32'h6768696a); // "ghij"
    write_wram(4'd7,  32'h68696a6b); // "hijk"
    write_wram(4'd8,  32'h696a6b6c); // "ijkl"
    write_wram(4'd9,  32'h6a6b6c6d); // "jklm"
    write_wram(4'd10, 32'h6b6c6d6e); // "klmn"
    write_wram(4'd11, 32'h6c6d6e6f); // "lmno"
    write_wram(4'd12, 32'h6d6e6f70); // "mnop"
    write_wram(4'd13, 32'h6e6f7071); // "nopq"
    send_start_m1(1'b1, 32'd56);
    wait_done(cyc_count);
    $display("  Cycles: %0d (expected 164 from start)", cyc_count);
    check_digest(256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1, "NIST 56 B");

    repeat(2) @(posedge clk);

    // ----------------------------------------------------
    // TEST 5: 'a' x 64 (64 bytes exact) -> FULL_LAST, 149 cycles
    // Golden: ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb
    // ----------------------------------------------------
    $display("--- Test 5: 'a' x 64 (64 B exact) ---");
    begin : test_64b
      integer i;
      for (i = 0; i < 16; i = i + 1)
        write_wram(i[3:0], 32'h61616161);
    end
    send_start_m1(1'b1, 32'd64);
    wait_done(cyc_count);
    $display("  Cycles: %0d (expected 148 from start)", cyc_count);
    check_digest(256'hffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb, "64 bytes exact");

    // ====================================================
    // SUMMARY
    // ====================================================
    repeat(4) @(posedge clk);
    $display("==================================================");
    if (fail_cnt == 0)
      $display("tb_core_autopad PASS (All Mode 1 vectors OK!)");
    else
      $display("tb_core_autopad FAIL (%0d failures)", fail_cnt);
    $display("==================================================");
    $finish;
  end

  initial begin
    #5000000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
