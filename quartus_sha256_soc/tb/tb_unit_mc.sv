// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_mc.sv — Unit test for mc.v (Compression Core)
// Verifikasi: load → round_en 1 kali → periksa A,E setelah round 0
// Menggunakan NIST "abc" nilai referensi round 0

`timescale 1ns/1ps

`include "rtl/sha256_defs.vh"

module tb_unit_mc;

  reg        clk, rst_n;
  reg        load, round_en;
  reg [255:0] h_base;
  reg [31:0]  k_val, w_n;
  // Legacy: tidak dipakai dalam tes ini
  reg         leg_prep, leg_we;
  reg [3:0]   leg_idx;
  reg [31:0]  leg_data;
  wire [31:0] leg_w, leg_k;
  wire [255:0] state_out;

  initial clk = 0;
  always #5 clk = ~clk;

  mc #(.LEGACY_EN(1)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .load      (load),
    .round_en  (round_en),
    .h_base    (h_base),
    .k_val     (k_val),
    .w_n       (w_n),
    .leg_prep  (leg_prep),
    .leg_we    (leg_we),
    .leg_idx   (leg_idx),
    .leg_data  (leg_data),
    .leg_w     (leg_w),
    .leg_k     (leg_k),
    .state_out (state_out)
  );

  integer fail;

  // Fungsi ekstrak word dari state_out
  function [31:0] sA; input [255:0] s; sA = s[255:224]; endfunction
  function [31:0] sB; input [255:0] s; sB = s[223:192]; endfunction
  function [31:0] sC; input [255:0] s; sC = s[191:160]; endfunction
  function [31:0] sD; input [255:0] s; sD = s[159:128]; endfunction
  function [31:0] sE; input [255:0] s; sE = s[127: 96]; endfunction
  function [31:0] sH; input [255:0] s; sH = s[ 31:  0]; endfunction

  task check_word;
    input [31:0] got, exp;
    input [63:0] label;
    begin
      if (got !== exp) begin
        $display("FAIL %s: got=%08h exp=%08h", label, got, exp);
        fail = fail + 1;
      end else
        $display("PASS %s: %08h", label, got);
    end
  endtask

  // SHA-256 IV
  localparam [255:0] IV = 256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19;

  // "abc" padded block: W[0..15]
  reg [31:0] W [0:15];
  // K[0..2]
  reg [31:0] K [0:2];

  reg [31:0] A0,B0,C0,D0,E0,F0,G0,H0;
  reg [31:0] A1,E1;
  reg [31:0] t1, t2, s0, s1_e, ch, maj;

  initial begin
    $display("==============================================");
    $display("tb_unit_mc: Test load + 1 round compress");
    $display("==============================================");
    fail = 0;
    load = 0; round_en = 0;
    leg_prep = 0; leg_we = 0; leg_idx = 0; leg_data = 0;

    // Inisialisasi W, K
    W[ 0] = 32'h61626380; W[ 1] = 32'h00000000; W[ 2] = 32'h00000000; W[ 3] = 32'h00000000;
    W[ 4] = 32'h00000000; W[ 5] = 32'h00000000; W[ 6] = 32'h00000000; W[ 7] = 32'h00000000;
    W[ 8] = 32'h00000000; W[ 9] = 32'h00000000; W[10] = 32'h00000000; W[11] = 32'h00000000;
    W[12] = 32'h00000000; W[13] = 32'h00000000; W[14] = 32'h00000000; W[15] = 32'h00000018;

    K[0] = 32'h428a2f98;  // K[0]
    K[1] = 32'h71374491;  // K[1]
    K[2] = 32'hb5c0fbcf;  // K[2]

    // Reset
    rst_n = 0;
    @(posedge clk); @(posedge clk); #1;
    rst_n = 1;

    // ---- Test 1: Reset state harus semua 0 ----
    $display("--- T1: State setelah reset = 0 ---");
    if (state_out !== 256'h0) begin
      $display("FAIL T1: state_out=%064h exp=0", state_out);
      fail = fail + 1;
    end else $display("PASS T1: state_out = 0");

    // ---- Test 2: LOAD — muat IV, hkw = H_IV + K[0] + W[0] ----
    $display("--- T2: Load IV + W[0] + K[0] ---");
    h_base = IV;
    k_val  = K[0];
    w_n    = W[0]; // W[0] untuk LOAD, hkw precompute
    @(negedge clk);
    load   = 1'b1;
    @(posedge clk); #1;
    load   = 1'b0;
    @(posedge clk); #1;

    // State seharusnya = IV
    A0 = IV[255:224]; B0 = IV[223:192]; C0 = IV[191:160]; D0 = IV[159:128];
    E0 = IV[127: 96]; F0 = IV[ 95: 64]; G0 = IV[ 63: 32]; H0 = IV[ 31:  0];
    if (state_out !== IV) begin
      $display("FAIL T2: state_out setelah LOAD != IV");
      $display("  got=%064h", state_out);
      $display("  exp=%064h", IV);
      fail = fail + 1;
    end else $display("PASS T2: state_out = IV setelah load");

    // ---- Test 3: 1 round (round 0) → A1,E1 referensi NIST "abc" ----
    $display("--- T3: Round 0 compress ---");
    // mc melakukan: hkw sudah = H0+K[0]+W[0], round_en aktifkan round
    // Setelah round 0, pasang K[1]+W[1] untuk hkw round 1
    k_val = K[1]; w_n = W[1];
    @(negedge clk);
    round_en = 1'b1;
    @(posedge clk); #1;
    round_en = 1'b0;
    @(posedge clk); #1;

    // Hitung referensi manual round 0:
    // hkw = H0 + K[0] + W[0] (sudah di-precompute saat LOAD)
    // s1 = Sigma1(E0) = ROTR(E,6)^ROTR(E,11)^ROTR(E,25)
    // ch = (E & F) ^ (~E & G)
    // temp1 = hkw + s1 + ch
    // s0 = Sigma0(A0) = ROTR(A,2)^ROTR(A,13)^ROTR(A,22)
    // maj = (A&B)^(A&C)^(B&C)
    // temp2 = s0 + maj
    // A1 = temp1 + temp2
    // E1 = D0 + temp1
    s1_e = (`ROTR(E0, 6) ^ `ROTR(E0,11) ^ `ROTR(E0,25));
    ch   = (E0 & F0) ^ (~E0 & G0);
    t1   = H0 + K[0] + W[0] + s1_e + ch;
    s0   = (`ROTR(A0, 2) ^ `ROTR(A0,13) ^ `ROTR(A0,22));
    maj  = (A0 & B0) ^ (A0 & C0) ^ (B0 & C0);
    t2   = s0 + maj;
    A1   = t1 + t2;
    E1   = D0 + t1;

    $display("  Referensi manual: A1=%08h E1=%08h", A1, E1);
    $display("  DUT state_out:    A =%08h E =%08h", sA(state_out), sE(state_out));

    check_word(sA(state_out), A1, "A after rnd0");
    check_word(sE(state_out), E1, "E after rnd0");
    // B harus = A0
    check_word(sB(state_out), A0, "B after rnd0");
    // F harus = E0
    check_word({state_out[95:64]}, E0, "F after rnd0");

    $display("");
    if (fail == 0)
      $display("tb_unit_mc PASS");
    else
      $display("tb_unit_mc FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #5000; $display("TIMEOUT"); $finish; end

endmodule
