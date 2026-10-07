// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// hash_adder.v — SHA-256 Hash Accumulator (kombinasional)
// h_new[i] = h_base[i] + state_final[i]  (8 × 32-bit lane, modulo 2^32)

`default_nettype none

module hash_adder (
    input  wire [255:0] h_base,       // first_eff ? IV : HRAM  (BUKAN HRAM mentah)
    input  wire [255:0] state_final,  // state_out dari mc
    output wire [255:0] h_new         // 8 penjumlahan 32-bit mod 2^32, per lane
);

  // 8 lane 32-bit: A=[255:224] .. H=[31:0]
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : lane
      assign h_new[255-32*i -: 32] = h_base[255-32*i -: 32] + state_final[255-32*i -: 32];
    end
  endgenerate

endmodule

`default_nettype wire
