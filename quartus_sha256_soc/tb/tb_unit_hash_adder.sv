// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_hash_adder.sv — Unit test for hash_adder.v
// Verifikasi: {A..H}_out = {A..H}_mc + {A..H}_iv (8 word 32-bit modulo 2^32)

`timescale 1ns/1ps

module tb_unit_hash_adder;

  reg [255:0] state_mc;  // hasil dari mc.v (A..H akhir)
  reg [255:0] h_prev;    // nilai H awal blok
  wire [255:0] h_out;    // H baru = state_mc + h_prev

  hash_adder dut (
    .state_mc (state_mc),
    .h_prev   (h_prev),
    .h_out    (h_out)
  );

  integer i, fail;
  reg [31:0] mc_w [0:7];
  reg [31:0] hp_w [0:7];
  reg [31:0] exp_w[0:7];

  function [31:0] get_word;
    input [255:0] vec;
    input integer  idx; // 0=A(MSB), 7=H(LSB)
    get_word = vec[255 - idx*32 -: 32];
  endfunction

  task run_test;
    input [255:0] mc_in;
    input [255:0] hp_in;
    input [7:0]   tid;
    integer j;
    reg [31:0] exp;
    reg        ok;
    begin
      state_mc = mc_in;
      h_prev   = hp_in;
      #2; // kombinasional
      ok = 1;
      for (j = 0; j < 8; j = j + 1) begin
        exp = get_word(mc_in, j) + get_word(hp_in, j);
        if (get_word(h_out, j) !== exp) begin
          $display("FAIL T%0d word%0d: got=%08h exp=%08h", tid, j, get_word(h_out,j), exp);
          fail = fail + 1;
          ok = 0;
        end
      end
      if (ok) $display("PASS T%0d: H_out = state_mc + h_prev benar", tid);
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_hash_adder: Test 8-lane modular adder");
    $display("==============================================");
    fail = 0;

    // T1: semua nol
    run_test(256'h0, 256'h0, 8'd1);

    // T2: IV SHA-256 + IV SHA-256
    run_test(
      256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19,
      256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19,
      8'd2
    );

    // T3: Overflow test (semua FFFFFFFF + 1 → 0)
    run_test(
      256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
      256'h00000001_00000001_00000001_00000001_00000001_00000001_00000001_00000001,
      8'd3
    );

    // T4: Nilai acak campuran
    run_test(
      256'hDEADBEEF_CAFEBABE_12345678_87654321_ABCDEF01_FEDCBA98_DEADC0DE_BEEFDEAD,
      256'h00000001_FFFFFFFE_00000002_FFFFFFFD_00000003_FFFFFFFC_00000004_FFFFFFFB,
      8'd4
    );

    $display("");
    if (fail == 0)
      $display("tb_unit_hash_adder PASS");
    else
      $display("tb_unit_hash_adder FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #1000; $display("TIMEOUT"); $finish; end

endmodule
