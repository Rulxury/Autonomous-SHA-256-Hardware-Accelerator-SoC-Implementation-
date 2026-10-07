// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// wram.v — Working Word Register (16 × 32-bit shift register)
// 512 flip-flop; tap tetap [0],[1],[9],[14] untuk message expansion.
`timescale 1ns/1ps
`default_nettype none

module wram (
    input  wire        clk,
    // write port dari host (per word, hanya saat tidak BUSY)
    input  wire        host_we,
    input  wire [3:0]  host_idx,
    input  wire [31:0] host_data,
    // shift (aktif di state PAD | LOAD | PROC)
    input  wire        shift_en,
    input  wire [31:0] shift_in,         // masuk ke w[15]
    // tap tetap (kombinasional)
    output wire [31:0] w0, w1, w9, w14
);

  // host_we dan shift_en tidak boleh aktif bersamaan; dijamin top (host write dibuang saat BUSY)
  // pragma translate_off
  // synthesis translate_off
  always @(posedge clk) begin
    if (host_we && shift_en)
      $error("wram: host_we and shift_en active simultaneously!");
  end
  // synthesis translate_on
  // pragma translate_on

  reg [31:0] w [0:15];
  integer i;

  always @(posedge clk) begin
    if (host_we) begin
      w[host_idx] <= host_data;
    end else if (shift_en) begin
      for (i = 0; i < 15; i = i + 1)
        w[i] <= w[i+1];
      w[15] <= shift_in;
    end
  end

  assign w0  = w[0];
  assign w1  = w[1];
  assign w9  = w[9];
  assign w14 = w[14];

endmodule

`default_nettype wire
