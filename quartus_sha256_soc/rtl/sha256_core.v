// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// sha256_core.v — SHA-256 Datapath Integration
// Menghubungkan: sha256_fsm, k_rom, wram, pad_fn, me, mc, hash_adder, hram

`default_nettype none

`include "sha256_defs.vh"

module sha256_core #(
    parameter LEGACY_EN = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    // dari CSR
    input  wire         soft_rst,
    input  wire         start_req,
    input  wire         first_in, last_in, auto_in,
    input  wire [31:0]  msg_len_reg,
    input  wire         host_we,
    input  wire [3:0]   host_idx,
    input  wire [31:0]  host_data,
    // Legacy Step Mode
    input  wire         leg_step_req,
    input  wire         leg_we,
    input  wire [3:0]   leg_idx,
    input  wire [31:0]  leg_data,
    // ke CSR
    output wire         fsm_busy,
    output wire [5:0]   round,
    output wire         blk_inc,
    output wire         done_pulse,
    output wire         msg_done_pulse,
    output wire [255:0] digest,
    output wire [255:0] state_dbg,
    output wire [31:0]  leg_w, leg_k
);

  // ------------------------------------------------------------------ FSM
  wire        load_w, round_en_w, shift_en_w, hram_we_w, leg_prep_w;
  wire [5:0]  k_addr_w;
  wire        sched_en_w;
  wire [3:0]  pad_cnt_w;
  wire [5:0]  keep_w;
  wire        ins80_w, inslen_w;
  wire [63:0] len_bits_w;
  wire        state_is_pad_w;
  wire        first_eff_w;
  wire [2:0]  fsm_state_w;

  sha256_fsm #(.LEGACY_EN(LEGACY_EN)) u_fsm (
    .clk            (clk),
    .rst_n          (rst_n),
    .soft_rst       (soft_rst),
    .start_req      (start_req),
    .first_in       (first_in),
    .last_in        (last_in),
    .auto_in        (auto_in),
    .msg_len_reg    (msg_len_reg),
    .leg_step_req   (leg_step_req),
    .load           (load_w),
    .round_en       (round_en_w),
    .shift_en       (shift_en_w),
    .hram_we        (hram_we_w),
    .leg_prep       (leg_prep_w),
    .k_addr         (k_addr_w),
    .sched_en       (sched_en_w),
    .pad_cnt        (pad_cnt_w),
    .keep           (keep_w),
    .ins80          (ins80_w),
    .inslen         (inslen_w),
    .len_bits       (len_bits_w),
    .fsm_busy       (fsm_busy),
    .round          (round),
    .blk_inc        (blk_inc),
    .done_pulse     (done_pulse),
    .msg_done_pulse (msg_done_pulse),
    .state_is_pad   (state_is_pad_w),
    .first_eff      (first_eff_w),
    .state          (fsm_state_w)
  );

  // ------------------------------------------------------------------ K-ROM
  wire [31:0] k_val_w;
  k_rom u_krom (
    .clk  (clk),
    .addr (k_addr_w),
    .q    (k_val_w)
  );

  // ------------------------------------------------------------------ WRAM
  wire [31:0] w0_w, w1_w, w9_w, w14_w;
  wire [31:0] pad_y_w;
  wire [31:0] w_n_w;
  wire [31:0] shift_in_w = state_is_pad_w ? pad_y_w : w_n_w;

  wram u_wram (
    .clk       (clk),
    .host_we   (host_we),
    .host_idx  (host_idx),
    .host_data (host_data),
    .shift_en  (shift_en_w),
    .shift_in  (shift_in_w),
    .w0        (w0_w),
    .w1        (w1_w),
    .w9        (w9_w),
    .w14       (w14_w)
  );

  // ------------------------------------------------------------------ ME
  me u_me (
    .sched_en (sched_en_w),
    .w0       (w0_w),
    .w1       (w1_w),
    .w9       (w9_w),
    .w14      (w14_w),
    .w_n      (w_n_w)
  );

  // ------------------------------------------------------------------ PAD_FN
  pad_fn u_pad (
    .idx      (pad_cnt_w),
    .din      (w0_w),
    .keep     (keep_w),
    .ins80    (ins80_w),
    .inslen   (inslen_w),
    .len_bits (len_bits_w),
    .dout     (pad_y_w)
  );

  // ------------------------------------------------------------------ h_base mux
  wire [255:0] hram_q_w;
  wire [255:0] h_base_w = first_eff_w ? `NIST_IV : hram_q_w;

  // ------------------------------------------------------------------ MC
  wire [255:0] state_out_w;

  mc #(.LEGACY_EN(LEGACY_EN)) u_mc (
    .clk       (clk),
    .rst_n     (rst_n),
    .load      (load_w),
    .round_en  (round_en_w),
    .h_base    (h_base_w),
    .k_val     (k_val_w),
    .w_n       (w_n_w),
    .leg_prep  (leg_prep_w),
    .leg_we    (leg_we),
    .leg_idx   (leg_idx),
    .leg_data  (leg_data),
    .leg_w     (leg_w),
    .leg_k     (leg_k),
    .state_out (state_out_w)
  );

  // ------------------------------------------------------------------ Hash Adder
  wire [255:0] h_new_w;
  hash_adder u_hadder (
    .h_base      (h_base_w),
    .state_final (state_out_w),
    .h_new       (h_new_w)
  );

  // ------------------------------------------------------------------ HRAM
  hram u_hram (
    .clk   (clk),
    .rst_n (rst_n),
    .we    (hram_we_w),
    .d     (h_new_w),
    .q     (hram_q_w)
  );

  // ------------------------------------------------------------------ Outputs
  assign digest    = hram_q_w;
  assign state_dbg = state_out_w;

endmodule

`default_nettype wire
