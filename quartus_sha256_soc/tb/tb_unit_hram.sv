// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_hram.sv — Unit test for hram.v
// Verifikasi: reset ke IV, we update semua 8 word, we=0 tidak update

`timescale 1ns/1ps

module tb_unit_hram;

  reg        clk, rst_n;
  reg        we;
  reg [255:0] h_in;
  wire [255:0] h_out;

  initial clk = 0;
  always #5 clk = ~clk;

  hram dut (
    .clk   (clk),
    .rst_n (rst_n),
    .we    (we),
    .h_in  (h_in),
    .h_out (h_out)
  );

  integer fail;

  // SHA-256 IV
  localparam [255:0] SHA256_IV = 256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19;

  task check;
    input [255:0] exp;
    input [7:0]   tid;
    begin
      if (h_out !== exp) begin
        $display("FAIL T%0d: h_out=%064h exp=%064h", tid, h_out, exp);
        fail = fail + 1;
      end else
        $display("PASS T%0d: h_out=%064h", tid, h_out);
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_hram: Test reset, write-enable, hold");
    $display("==============================================");
    fail = 0;
    we    = 1'b0;
    h_in  = 256'h0;
    rst_n = 1'b0;
    repeat(2) @(posedge clk); #1;

    // ---- T1: Setelah reset → IV ----
    rst_n = 1'b1;
    @(posedge clk); #1;
    check(SHA256_IV, 8'd1);

    // ---- T2: we=0, nilai tidak berubah walau h_in diubah ----
    we   = 1'b0;
    h_in = 256'hDEADBEEF_CAFEBABE_12345678_87654321_ABCDEF01_FEDCBA98_DEADC0DE_BEEFDEAD;
    @(posedge clk); #1;
    check(SHA256_IV, 8'd2); // harus tetap IV

    // ---- T3: we=1, nilai diupdate ----
    we   = 1'b1;
    h_in = 256'hDEADBEEF_CAFEBABE_12345678_87654321_ABCDEF01_FEDCBA98_DEADC0DE_BEEFDEAD;
    @(posedge clk); #1;
    we   = 1'b0;
    @(posedge clk); #1;
    check(256'hDEADBEEF_CAFEBABE_12345678_87654321_ABCDEF01_FEDCBA98_DEADC0DE_BEEFDEAD, 8'd3);

    // ---- T4: Reset kembali ke IV ----
    rst_n = 1'b0;
    @(posedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;
    check(SHA256_IV, 8'd4);

    // ---- T5: Tulis lalu baca, we=0 hold ----
    we   = 1'b1;
    h_in = 256'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_00000000_11111111;
    @(posedge clk); #1;
    we   = 1'b0;
    h_in = 256'h0; // ubah input, tapi we=0
    @(posedge clk); #1;
    check(256'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_00000000_11111111, 8'd5);

    $display("");
    if (fail == 0)
      $display("tb_unit_hram PASS");
    else
      $display("tb_unit_hram FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #5000; $display("TIMEOUT"); $finish; end

endmodule
