// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_wram.sv — Unit test for wram.v
// Verifikasi: host write per-word, shift operasi, tap w0/w1/w9/w14

`timescale 1ns/1ps

module tb_unit_wram;

  reg        clk;
  reg        host_we;
  reg [3:0]  host_idx;
  reg [31:0] host_data;
  reg        shift_en;
  reg [31:0] shift_in;
  wire [31:0] w0, w1, w9, w14;

  initial clk = 0;
  always #5 clk = ~clk;

  wram dut (
    .clk       (clk),
    .host_we   (host_we),
    .host_idx  (host_idx),
    .host_data (host_data),
    .shift_en  (shift_en),
    .shift_in  (shift_in),
    .w0        (w0),
    .w1        (w1),
    .w9        (w9),
    .w14       (w14)
  );

  integer i, fail;
  reg [31:0] expected_w [0:15];

  // Task: host write satu word
  task write_word;
    input [3:0]  idx;
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

  // Task: shift satu siklus
  task do_shift;
    input [31:0] s_in;
    begin
      @(negedge clk);
      shift_en = 1'b1;
      shift_in = s_in;
      @(posedge clk); #1;
      shift_en = 1'b0;
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_wram: Test host write + shift + taps");
    $display("==============================================");
    fail = 0;
    host_we  = 1'b0;
    shift_en = 1'b0;
    shift_in = 32'h0;
    host_idx = 4'h0;
    host_data = 32'h0;
    @(posedge clk); @(posedge clk);

    // ---- Test 1: Host write ke semua 16 word ----
    $display("--- Test 1: Host Write ---");
    for (i = 0; i < 16; i = i + 1) begin
      expected_w[i] = 32'hDEAD0000 | i[31:0];
      write_word(i[3:0], expected_w[i]);
    end

    // Verifikasi tap w0, w1, w9, w14
    @(posedge clk); #1;
    if (w0 !== expected_w[0])  begin $display("FAIL w0:  got=%08h exp=%08h", w0,  expected_w[0]);  fail=fail+1; end
    if (w1 !== expected_w[1])  begin $display("FAIL w1:  got=%08h exp=%08h", w1,  expected_w[1]);  fail=fail+1; end
    if (w9 !== expected_w[9])  begin $display("FAIL w9:  got=%08h exp=%08h", w9,  expected_w[9]);  fail=fail+1; end
    if (w14 !== expected_w[14]) begin $display("FAIL w14: got=%08h exp=%08h", w14, expected_w[14]); fail=fail+1; end
    if (fail == 0) $display("PASS: Semua tap w0/w1/w9/w14 benar setelah host write");

    // ---- Test 2: Shift 1 kali ----
    $display("--- Test 2: Shift 1 kali ---");
    do_shift(32'hCAFEBABE);
    // Setelah shift: w[0]=w[1]=old, ..., w[14]=w[15]=old, w[15]=CAFEBABE
    // w0 sekarang = expected_w[1] (sebelumnya)
    if (w0 !== expected_w[1]) begin
      $display("FAIL shift: w0 got=%08h exp=%08h", w0, expected_w[1]);
      fail = fail + 1;
    end else $display("PASS: w0 setelah 1 shift = w1 lama");

    // Verifikasi w14 = w[15] lama = expected_w[15]
    if (w14 !== expected_w[15]) begin
      $display("FAIL shift: w14 got=%08h exp=%08h", w14, expected_w[15]);
      fail = fail + 1;
    end else $display("PASS: w14 setelah 1 shift = w15 lama");

    // ---- Test 3: Shift 15 kali lagi (total 16), lalu cek w14 = shift_in pertama ----
    $display("--- Test 3: Shift 16 total ---");
    for (i = 0; i < 15; i = i + 1)
      do_shift(32'hBEEF0000 | i[31:0]);

    // Setelah 16 shift total dari kondisi expected_w, w14 = shift_in ke-15 = BEEF000E
    if (w14 !== 32'hBEEF000D) begin
      $display("FAIL 16-shift: w14 got=%08h exp=BEEF000D", w14);
      fail = fail + 1;
    end else $display("PASS: w14 setelah 16 shift benar");

    $display("");
    if (fail == 0)
      $display("tb_unit_wram PASS");
    else
      $display("tb_unit_wram FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #10000; $display("TIMEOUT"); $finish; end

endmodule
