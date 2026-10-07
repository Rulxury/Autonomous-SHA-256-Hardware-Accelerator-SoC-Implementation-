// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// sha256_accelerator.v — Top-level SHA-256 Accelerator
// Avalon-MM slave + HPS interrupt sender for DE10-Nano (Cyclone V SoC).

`default_nettype none

module sha256_accelerator #(
    parameter LEGACY_EN = 1
) (
    input  wire         clk,
    input  wire         reset_n,
    // Avalon-MM slave
    input  wire [5:0]   avs_address,
    input  wire         avs_read,
    input  wire         avs_write,
    input  wire [31:0]  avs_writedata,
    output wire [31:0]  avs_readdata,
    // Interrupt sender
    output wire         irq
);

  // ---- Internal wires: CSR -> Core ----
  wire        soft_rst_w;
  wire        start_req_w;
  wire        first_w, last_w, auto_w;
  wire [31:0] msg_len_w;
  wire        host_we_w;
  wire [3:0]  host_idx_w;
  wire [31:0] host_data_w;
  wire        leg_step_req_w;
  wire        leg_we_w;
  wire [3:0]  leg_idx_w;
  wire [31:0] leg_data_w;

  // ---- Internal wires: Core -> CSR ----
  wire        fsm_busy_w;
  wire [5:0]  round_w;
  wire        blk_inc_w;
  wire        done_pulse_w;
  wire        msg_done_pulse_w;
  wire [255:0] digest_w;
  wire [255:0] state_dbg_w;
  wire [31:0]  leg_w_w, leg_k_w;

  // ---- CSR ----
  sha256_csr #(.LEGACY_EN(LEGACY_EN)) u_csr (
    .clk            (clk),
    .rst_n          (reset_n),
    .avs_address    (avs_address),
    .avs_read       (avs_read),
    .avs_write      (avs_write),
    .avs_writedata  (avs_writedata),
    .avs_readdata   (avs_readdata),
    .irq            (irq),
    .soft_rst       (soft_rst_w),
    .start_req      (start_req_w),
    .first_out      (first_w),
    .last_out       (last_w),
    .auto_out       (auto_w),
    .msg_len_reg    (msg_len_w),
    .host_we        (host_we_w),
    .host_idx       (host_idx_w),
    .host_data      (host_data_w),
    .leg_step_req   (leg_step_req_w),
    .leg_we         (leg_we_w),
    .leg_idx        (leg_idx_w),
    .leg_data       (leg_data_w),
    .fsm_busy       (fsm_busy_w),
    .round          (round_w),
    .blk_inc        (blk_inc_w),
    .done_pulse     (done_pulse_w),
    .msg_done_pulse (msg_done_pulse_w),
    .digest         (digest_w),
    .state_dbg      (state_dbg_w),
    .leg_w_in       (leg_w_w),
    .leg_k_in       (leg_k_w)
  );

  // ---- Core ----
  sha256_core #(.LEGACY_EN(LEGACY_EN)) u_core (
    .clk            (clk),
    .rst_n          (reset_n),
    .soft_rst       (soft_rst_w),
    .start_req      (start_req_w),
    .first_in       (first_w),
    .last_in        (last_w),
    .auto_in        (auto_w),
    .msg_len_reg    (msg_len_w),
    .host_we        (host_we_w),
    .host_idx       (host_idx_w),
    .host_data      (host_data_w),
    .leg_step_req   (leg_step_req_w),
    .leg_we         (leg_we_w),
    .leg_idx        (leg_idx_w),
    .leg_data       (leg_data_w),
    .fsm_busy       (fsm_busy_w),
    .round          (round_w),
    .blk_inc        (blk_inc_w),
    .done_pulse     (done_pulse_w),
    .msg_done_pulse (msg_done_pulse_w),
    .digest         (digest_w),
    .state_dbg      (state_dbg_w),
    .leg_w          (leg_w_w),
    .leg_k          (leg_k_w)
  );

endmodule

`default_nettype wire
