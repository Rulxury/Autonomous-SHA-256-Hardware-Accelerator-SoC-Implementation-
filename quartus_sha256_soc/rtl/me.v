// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// me.v — SHA-256 Message Expansion (kombinasional)
// w_n = w0 + σ0(w1) + w9 + σ1(w14)  bila sched_en; else w_n = w0
`timescale 1ns/1ps
`default_nettype none

`include "sha256_defs.vh"

module me (
    input  wire        sched_en,           // 1 jika n >= 16
    input  wire [31:0] w0, w1, w9, w14,
    output wire [31:0] w_n
);

  // Gating operand: sched_en ? expansion : 0  agar tidak menambah level pada critical path
  wire [31:0] sig0_w1  = sched_en ? `SIG0(w1)  : 32'd0;
  wire [31:0] sig1_w14 = sched_en ? `SIG1(w14) : 32'd0;
  wire [31:0] w9_g     = sched_en ? w9         : 32'd0;

  assign w_n = w0 + sig0_w1 + w9_g + sig1_w14;

endmodule

`default_nettype wire
