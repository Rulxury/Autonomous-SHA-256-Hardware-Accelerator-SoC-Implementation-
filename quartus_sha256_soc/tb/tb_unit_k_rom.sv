// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_k_rom.sv — Unit test for k_rom.v
// Verifikasi: 64 konstanta SHA-256 benar + latensi 1 siklus

`timescale 1ns/1ps

module tb_unit_k_rom;

  reg        clk;
  reg [5:0]  addr;
  wire [31:0] q;

  initial clk = 0;
  always #5 clk = ~clk;

  k_rom dut (
    .clk  (clk),
    .addr (addr),
    .q    (q)
  );

  // 64 konstanta SHA-256 (NIST FIPS 180-4)
  reg [31:0] K_REF [0:63];
  initial begin
    K_REF[ 0] = 32'h428a2f98; K_REF[ 1] = 32'h71374491;
    K_REF[ 2] = 32'hb5c0fbcf; K_REF[ 3] = 32'he9b5dba5;
    K_REF[ 4] = 32'h3956c25b; K_REF[ 5] = 32'h59f111f1;
    K_REF[ 6] = 32'h923f82a4; K_REF[ 7] = 32'hab1c5ed5;
    K_REF[ 8] = 32'hd807aa98; K_REF[ 9] = 32'h12835b01;
    K_REF[10] = 32'h243185be; K_REF[11] = 32'h550c7dc3;
    K_REF[12] = 32'h72be5d74; K_REF[13] = 32'h80deb1fe;
    K_REF[14] = 32'h9bdc06a7; K_REF[15] = 32'hc19bf174;
    K_REF[16] = 32'he49b69c1; K_REF[17] = 32'hefbe4786;
    K_REF[18] = 32'h0fc19dc6; K_REF[19] = 32'h240ca1cc;
    K_REF[20] = 32'h2de92c6f; K_REF[21] = 32'h4a7484aa;
    K_REF[22] = 32'h5cb0a9dc; K_REF[23] = 32'h76f988da;
    K_REF[24] = 32'h983e5152; K_REF[25] = 32'ha831c66d;
    K_REF[26] = 32'hb00327c8; K_REF[27] = 32'hbf597fc7;
    K_REF[28] = 32'hc6e00bf3; K_REF[29] = 32'hd5a79147;
    K_REF[30] = 32'h06ca6351; K_REF[31] = 32'h14292967;
    K_REF[32] = 32'h27b70a85; K_REF[33] = 32'h2e1b2138;
    K_REF[34] = 32'h4d2c6dfc; K_REF[35] = 32'h53380d13;
    K_REF[36] = 32'h650a7354; K_REF[37] = 32'h766a0abb;
    K_REF[38] = 32'h81c2c92e; K_REF[39] = 32'h92722c85;
    K_REF[40] = 32'ha2bfe8a1; K_REF[41] = 32'ha81a664b;
    K_REF[42] = 32'hc24b8b70; K_REF[43] = 32'hc76c51a3;
    K_REF[44] = 32'hd192e819; K_REF[45] = 32'hd6990624;
    K_REF[46] = 32'hf40e3585; K_REF[47] = 32'h106aa070;
    K_REF[48] = 32'h19a4c116; K_REF[49] = 32'h1e376c08;
    K_REF[50] = 32'h2748774c; K_REF[51] = 32'h34b0bcb5;
    K_REF[52] = 32'h391c0cb3; K_REF[53] = 32'h4ed8aa4a;
    K_REF[54] = 32'h5b9cca4f; K_REF[55] = 32'h682e6ff3;
    K_REF[56] = 32'h748f82ee; K_REF[57] = 32'h78a5636f;
    K_REF[58] = 32'h84c87814; K_REF[59] = 32'h8cc70208;
    K_REF[60] = 32'h90befffa; K_REF[61] = 32'ha4506ceb;
    K_REF[62] = 32'hbef9a3f7; K_REF[63] = 32'hc67178f2;
  end

  integer i, fail;

  initial begin
    $display("==============================================");
    $display("tb_unit_k_rom: Test semua 64 konstanta SHA-256");
    $display("==============================================");
    fail = 0;
    addr = 6'd0;
    @(negedge clk);

    for (i = 0; i < 64; i = i + 1) begin
      addr = i[5:0];
      @(posedge clk); #1; // k_rom latensi 1 siklus
      if (q !== K_REF[i]) begin
        $display("FAIL K[%0d]: got=%08h expected=%08h", i, q, K_REF[i]);
        fail = fail + 1;
      end
    end

    $display("");
    if (fail == 0)
      $display("tb_unit_k_rom PASS — semua 64 konstanta benar, latensi 1 siklus OK");
    else
      $display("tb_unit_k_rom FAIL — %0d mismatch", fail);
    $finish;
  end

  initial begin #5000; $display("TIMEOUT"); $finish; end

endmodule
