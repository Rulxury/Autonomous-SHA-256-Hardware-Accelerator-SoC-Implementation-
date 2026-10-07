// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_me.sv — Unit test for me.v (Message Expansion / Message Schedule)
// Verifikasi: w_n = w0 bila sched_en=0; w0+sig0(w1)+w9+sig1(w14) bila sched_en=1
// Nilai referensi dihitung manual dari definisi sigma SHA-256

`timescale 1ns/1ps

module tb_unit_me;

  // Macro σ0 dan σ1 (message schedule) — harus sama dengan sha256_defs.vh
  `define ROTR(x,n)  (((x) >> (n)) | ((x) << (32-(n))))
  `define SIG0(x)    (`ROTR(x,7)  ^ `ROTR(x,18) ^ ((x) >> 3))
  `define SIG1(x)    (`ROTR(x,17) ^ `ROTR(x,19) ^ ((x) >> 10))

  reg        sched_en;
  reg [31:0] w0, w1, w9, w14;
  wire [31:0] w_n;

  me dut (
    .sched_en (sched_en),
    .w0       (w0),
    .w1       (w1),
    .w9       (w9),
    .w14      (w14),
    .w_n      (w_n)
  );

  integer fail;
  reg [31:0] expected;

  task check;
    input [31:0] exp;
    input [63:0] label;
    begin
      #1; // kombinasional: tunggu propagasi
      if (w_n !== exp) begin
        $display("FAIL [%0d]: w_n=%08h expected=%08h", label, w_n, exp);
        fail = fail + 1;
      end else
        $display("PASS [%0d]: w_n=%08h", label, w_n);
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_me: Test message expansion sigma");
    $display("==============================================");
    fail = 0;

    // ---- Test 1: sched_en = 0, w_n harus = w0 ----
    $display("--- Test 1: sched_en=0, w_n=w0 ---");
    sched_en = 1'b0;
    w0 = 32'hABCD1234; w1 = 32'hFFFFFFFF; w9 = 32'h12345678; w14 = 32'h87654321;
    expected = w0; // w_n = w0 + 0 + 0 + 0 = w0
    check(expected, 1);

    sched_en = 1'b0;
    w0 = 32'h00000000;
    expected = 32'h00000000;
    check(expected, 2);

    // ---- Test 2: sched_en = 1, nilai NIST "abc" blok W[16..19] ----
    $display("--- Test 2: sched_en=1, W16..W19 dari 'abc' ---");
    // Blok "abc" padded: W[0]=61626380, W[1..13]=0, W[14]=0, W[15]=18
    // W16 = W0 + σ0(W1) + W9 + σ1(W14)
    sched_en = 1'b1;
    w0  = 32'h61626380; // W[0]
    w1  = 32'h00000000; // W[1]
    w9  = 32'h00000000; // W[9]
    w14 = 32'h00000000; // W[14]
    expected = w0 + `SIG0(w1) + w9 + `SIG1(w14);
    check(expected, 3);

    // W17 = W1 + σ0(W2) + W10 + σ1(W15)
    // (menggunakan W15=0x00000018)
    w0  = 32'h00000000; // W[1]
    w1  = 32'h00000000; // W[2]
    w9  = 32'h00000000; // W[10]
    w14 = 32'h00000018; // W[15]
    expected = w0 + `SIG0(w1) + w9 + `SIG1(w14);
    check(expected, 4);

    // ---- Test 3: Nilai ekstrem ----
    $display("--- Test 3: Nilai ekstrem ---");
    sched_en = 1'b1;
    w0 = 32'hFFFFFFFF; w1 = 32'hFFFFFFFF; w9 = 32'hFFFFFFFF; w14 = 32'hFFFFFFFF;
    expected = w0 + `SIG0(w1) + w9 + `SIG1(w14); // overflow modulo 2^32
    check(expected, 5);

    sched_en = 1'b1;
    w0 = 32'h00000001; w1 = 32'h00000002; w9 = 32'h00000004; w14 = 32'h00000008;
    expected = w0 + `SIG0(w1) + w9 + `SIG1(w14);
    check(expected, 6);

    $display("");
    if (fail == 0)
      $display("tb_unit_me PASS");
    else
      $display("tb_unit_me FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #1000; $display("TIMEOUT"); $finish; end

endmodule
