// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// hram.v — Hash result register (8 × 32-bit flip-flop)
// Diperbarui atomik 256-bit pada siklus FINALIZE.
// reset_n me-reset ke 0 agar digest awal deterministik (pengecualian aturan §4).
`timescale 1ns/1ps
`default_nettype none

module hram (
    input  wire         clk,
    input  wire         rst_n,           // reset ke 0 (digest awal deterministik)
    input  wire         we,              // 1 siklus (FINALIZE)
    input  wire [255:0] d,               // dari hash_adder
    output wire [255:0] q                // digest saat ini, {H0..H7}, H0 = [255:224]
);

  reg [255:0] mem;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mem <= 256'h0;
    else if (we)
      mem <= d;
  end

  assign q = mem;

endmodule

`default_nettype wire
