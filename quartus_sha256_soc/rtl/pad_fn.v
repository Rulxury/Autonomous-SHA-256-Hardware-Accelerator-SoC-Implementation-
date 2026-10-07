// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// pad_fn.v — SHA-256 Hardware Auto-Padding Unit (kombinasional, 1 word per siklus)
// Menghasilkan satu word padding pada tiap siklus state PAD (16 siklus rotasi).

`default_nettype none

module pad_fn (
    input  wire [3:0]  idx,         // indeks word 0..15 (pad_cnt)
    input  wire [31:0] din,         // w0 (word yang keluar dari ujung shift register)
    input  wire [5:0]  keep,        // jumlah byte pesan yang dipertahankan (0..63)
    input  wire        ins80,       // sisipkan 0x80 pada byte ke-keep
    input  wire        inslen,      // sisipkan panjang 64-bit di word 14,15
    input  wire [63:0] len_bits,    // {29'b0, msg_len_q, 3'b0} — panjang dalam bit
    output wire [31:0] dout
);

  // d = signed(keep) - signed(4*idx), lebar >= 8 bit, WAJIB signed
  wire signed [7:0] d  = $signed({2'b00, keep}) - $signed({2'b00, idx, 2'b00});

  // kb = jumlah byte dari din yang dipertahankan (0..4)
  wire [2:0] kb = (d <= 0) ? 3'd0 : (d >= 4) ? 3'd4 : d[2:0];

  // mask: MSB-aligned, kb byte dari bit [31]
  wire [31:0] mask = (kb == 3'd0) ? 32'h0000_0000 :
                     (kb == 3'd1) ? 32'hFF00_0000 :
                     (kb == 3'd2) ? 32'hFFFF_0000 :
                     (kb == 3'd3) ? 32'hFFFFFF00  :
                                    32'hFFFFFFFF;

  // padding byte 0x80 position: byte ke-(keep & 3) dari MSB dalam word (keep>>2)==idx
  wire [31:0] byte80 = (32'h80 << (24 - (keep[1:0] * 8)));

  wire [31:0] base  = din & mask;
  wire [31:0] add80 = (ins80 && (keep[5:2] == idx)) ? byte80 : 32'h0;
  wire [31:0] addh  = (inslen && (idx == 4'd14))     ? len_bits[63:32] : 32'h0;
  wire [31:0] addl  = (inslen && (idx == 4'd15))     ? len_bits[31:0]  : 32'h0;

  assign dout = base | add80 | addh | addl;

endmodule

`default_nettype wire
