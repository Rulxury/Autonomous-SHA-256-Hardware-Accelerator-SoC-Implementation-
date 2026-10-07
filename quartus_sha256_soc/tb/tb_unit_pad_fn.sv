// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_unit_pad_fn.sv — Unit test for pad_fn.v
// Verifikasi: mask byte, sisipan 0x80, length word 14/15, kombinasi

`timescale 1ns/1ps

module tb_unit_pad_fn;

  reg [3:0]  idx;
  reg [31:0] din;
  reg [5:0]  keep;
  reg        ins80, inslen;
  reg [63:0] len_bits;
  wire [31:0] dout;

  pad_fn dut (
    .idx      (idx),
    .din      (din),
    .keep     (keep),
    .ins80    (ins80),
    .inslen   (inslen),
    .len_bits (len_bits),
    .dout     (dout)
  );

  integer fail;

  task check;
    input [31:0] exp;
    input [7:0]  tid;
    begin
      #1;
      if (dout !== exp) begin
        $display("FAIL T%0d: dout=%08h exp=%08h [idx=%0d keep=%0d ins80=%0d inslen=%0d]",
                 tid, dout, exp, idx, keep, ins80, inslen);
        fail = fail + 1;
      end else
        $display("PASS T%0d: dout=%08h", tid, dout);
    end
  endtask

  initial begin
    $display("==============================================");
    $display("tb_unit_pad_fn: Test padding byte, mask, length");
    $display("==============================================");
    fail = 0;
    ins80 = 0; inslen = 0; len_bits = 64'd0;

    // ---- T1: keep=0, idx=0 → dout = 0 (semua 0, tidak ada 0x80) ----
    din = 32'hFFFFFFFF; keep = 6'd0; idx = 4'd0; ins80 = 0; inslen = 0;
    check(32'h00000000, 8'd1);

    // ---- T2: keep=4 (satu word penuh), idx=0 → dout = din ----
    din = 32'hDEADBEEF; keep = 6'd4; idx = 4'd0; ins80 = 0; inslen = 0;
    check(32'hDEADBEEF, 8'd2);

    // ---- T3: keep=4 (satu word penuh), idx=1 → dout = 0 (word 1 bukan data) ----
    din = 32'hDEADBEEF; keep = 6'd4; idx = 4'd1; ins80 = 0; inslen = 0;
    check(32'h00000000, 8'd3);

    // ---- T4: keep=1, idx=0 → mask=FF000000, dout = din & FF000000 ----
    din = 32'hABCDEF12; keep = 6'd1; idx = 4'd0; ins80 = 0; inslen = 0;
    check(32'hAB000000, 8'd4);

    // ---- T5: keep=2, idx=0 → mask=FFFF0000 ----
    din = 32'hABCDEF12; keep = 6'd2; idx = 4'd0; ins80 = 0; inslen = 0;
    check(32'hABCD0000, 8'd5);

    // ---- T6: keep=3, idx=0 → mask=FFFFFF00 ----
    din = 32'hABCDEF12; keep = 6'd3; idx = 4'd0; ins80 = 0; inslen = 0;
    check(32'hABCDEF00, 8'd6);

    // ---- T7: ins80=1, keep=0, idx=0 → 0x80 di byte 0 MSB ----
    // keep[5:2]=0=idx, byte80 = 0x80 << 24 = 80000000
    din = 32'h00000000; keep = 6'd0; idx = 4'd0; ins80 = 1; inslen = 0;
    check(32'h80000000, 8'd7);

    // ---- T8: ins80=1, keep=1, idx=0 → mask=FF000000, byte80 pada byte 1 MSB ----
    // keep=1: keep[1:0]=1 → byte80 = 0x80 << (24-8) = 0x80<<16 = 00800000
    // keep[5:2]=0 == idx=0 → add80 aktif
    // din & FF000000 = AB000000; OR dengan 00800000 = AB800000
    din = 32'hABCDEF12; keep = 6'd1; idx = 4'd0; ins80 = 1; inslen = 0;
    check(32'hAB800000, 8'd8);

    // ---- T9: ins80=1, keep=4, idx=1 → 0x80 di word 1 byte 0 ----
    // keep=4: keep[5:2]=1==idx=1, keep[1:0]=0 → byte80 = 0x80<<24 = 80000000
    din = 32'h00000000; keep = 6'd4; idx = 4'd1; ins80 = 1; inslen = 0;
    check(32'h80000000, 8'd9);

    // ---- T10: inslen=1, idx=14, len_bits=0x18 (24 bit = pesan "abc") ----
    din = 32'h00000000; keep = 6'd0; idx = 4'd14; ins80 = 0; inslen = 1;
    len_bits = 64'h0000000000000018;
    check(32'h00000000, 8'd10); // len_bits[63:32] = 0

    // ---- T11: inslen=1, idx=15 → len_bits[31:0] = 0x00000018 ----
    idx = 4'd15;
    check(32'h00000018, 8'd11);

    // ---- T12: Kombinasi: keep=3, ins80=1, inslen=1, idx=0 ----
    // mask=FFFFFF00, byte80 pada keep=3 → keep[1:0]=3 → 0x80<<0 = 80
    // keep[5:2]=0 == idx=0 → add80 = 0x00000080
    din = 32'hABCDEF12; keep = 6'd3; idx = 4'd0; ins80 = 1; inslen = 1;
    len_bits = 64'h0000000000000018;
    check(32'hABCDEF80, 8'd12); // FFFFFF00 & ABCDEF12 = ABCDEF00, OR 80 = ABCDEF80

    // ---- T13: Kombinasi: keep=12 (3 word), idx=2 → full word ----
    din = 32'hDEADC0DE; keep = 6'd12; idx = 4'd2; ins80 = 1; inslen = 0;
    // keep[5:2]=3 != idx=2 → ins80 tidak aktif disini
    check(32'hDEADC0DE, 8'd13);

    $display("");
    if (fail == 0)
      $display("tb_unit_pad_fn PASS");
    else
      $display("tb_unit_pad_fn FAIL (%0d mismatch)", fail);
    $finish;
  end

  initial begin #1000; $display("TIMEOUT"); $finish; end

endmodule
