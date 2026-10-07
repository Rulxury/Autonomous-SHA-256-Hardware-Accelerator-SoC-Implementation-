// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// sha256_fsm.v — SHA-256 Accelerator FSM Controller
//
// State encoding (3-bit):
//   IDLE=0, PAD=1, LOAD=2, PROC=3, FIN=4
//   LPREP=5, LRND=6  (hanya bila LEGACY_EN = 1)
//
// Latensi per blok: 1(keputusan) + 1(LOAD) + 64(PROC) + 1(FIN) = 67 siklus
// PAD menambah 16 siklus.
`timescale 1ns/1ps
`default_nettype none

`include "sha256_defs.vh"

module sha256_fsm #(
    parameter LEGACY_EN = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    // Control inputs (dari CSR)
    input  wire         soft_rst,
    input  wire         start_req,          // 1 siklus, hanya bila START diterima CSR
    input  wire         first_in,
    input  wire         last_in,
    input  wire         auto_in,
    input  wire [31:0]  msg_len_reg,        // nilai REG_MSG_LEN
    // Legacy Step Mode
    input  wire         leg_step_req,       // 1 siklus, hanya bila LEG_STEP diterima
    // Control outputs ke datapath
    output reg          load,               // siklus LOAD: mc load h_base
    output reg          round_en,           // siklus PROC / LRND: eksekusi satu round
    output reg          shift_en,           // WRAM shift
    output reg          hram_we,            // tulis HRAM di FIN
    output reg          leg_prep,           // LPREP: hkw <= H+K+W
    output reg  [5:0]   k_addr,             // ke k_rom
    output reg          sched_en,           // ke me: sched_en = (cyc >= 16)
    // PAD control
    output reg  [3:0]   pad_cnt,            // idx untuk pad_fn
    output reg  [5:0]   keep,
    output reg          ins80,
    output reg          inslen,
    output wire [63:0]  len_bits,           // {29'b0, msg_len_q, 3'b0}
    // Status ke CSR
    output reg          fsm_busy,           // (state != IDLE)
    output reg  [5:0]   round,              // 0..63 selama PROC, selain itu 0
    output reg          blk_inc,            // 1 siklus: satu kompresi selesai (FIN non-legacy)
    output reg          done_pulse,         // 1 siklus: pekerjaan START / LEG_STEP selesai
    output reg          msg_done_pulse,     // 1 siklus: pesan selesai
    // WRAM shift_in mux select
    output wire         state_is_pad,       // (state == PAD) → shift_in = pad_y
    // first_eff untuk h_base mux
    output wire         first_eff,
    // Internal expose for core mux
    output reg  [2:0]   state
);

  // State encoding
  localparam IDLE  = 3'd0;
  localparam PAD   = 3'd1;
  localparam LOAD  = 3'd2;
  localparam PROC  = 3'd3;
  localparam FIN   = 3'd4;
  localparam LPREP = 3'd5;   // LEGACY_EN only
  localparam LRND  = 3'd6;   // LEGACY_EN only

  // Block classification
  localparam CLS_RAW       = 3'd0;
  localparam CLS_DATA      = 3'd1;
  localparam CLS_FULL_LAST = 3'd2;
  localparam CLS_OVF       = 3'd3;
  localparam CLS_TAIL      = 3'd4;

  // Pass-2 type
  localparam PASS2_NONE = 2'd0;
  localparam PASS2_FULL = 2'd1;
  localparam PASS2_LEN  = 2'd2;

  // Internal registers
  reg [6:0]  cyc;
  reg        first_q, last_q, auto_q;
  reg        second_pass;
  reg [2:0]  cls;
  reg [1:0]  pass2;
  reg        msg_last;
  reg [31:0] msg_len_q;
  reg [31:0] bytes_left;

  // first_eff = first_q && !second_pass
  assign first_eff   = first_q & ~second_pass;
  assign state_is_pad = (state == PAD);

  // len_bits = msg_len_q << 3 (= panjang dalam bit, 32-bit pesan × 8)
  // CATATAN: 29 bit atas selalu 0 karena MSG_LEN 32-bit; bit [2:0] selalu 0
  assign len_bits = {29'b0, msg_len_q, 3'b0};

  // auto_eff: untuk start_req, auto_in bila first, else auto_q
  // (dihitung hanya saat start_req, dipakai di sekuensial)

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state           <= IDLE;
      cyc             <= 7'd0;
      pad_cnt         <= 4'd0;
      first_q         <= 1'b0;
      last_q          <= 1'b0;
      auto_q          <= 1'b0;
      second_pass     <= 1'b0;
      cls             <= CLS_RAW;
      pass2           <= PASS2_NONE;
      msg_last        <= 1'b0;
      msg_len_q       <= 32'h0;
      bytes_left      <= 32'h0;
      keep            <= 6'd0;
      ins80           <= 1'b0;
      inslen          <= 1'b0;
      // outputs
      load            <= 1'b0;
      round_en        <= 1'b0;
      shift_en        <= 1'b0;
      hram_we         <= 1'b0;
      leg_prep        <= 1'b0;
      k_addr          <= 6'd0;
      sched_en        <= 1'b0;
      pad_cnt         <= 4'd0;
      fsm_busy        <= 1'b0;
      round           <= 6'd0;
      blk_inc         <= 1'b0;
      done_pulse      <= 1'b0;
      msg_done_pulse  <= 1'b0;
    end else begin
      // Default: strobe signals off every cycle
      load           <= 1'b0;
      round_en       <= 1'b0;
      shift_en       <= 1'b0;
      hram_we        <= 1'b0;
      leg_prep       <= 1'b0;
      blk_inc        <= 1'b0;
      done_pulse     <= 1'b0;
      msg_done_pulse <= 1'b0;

      // Soft reset: return to IDLE
      if (soft_rst) begin
        state       <= IDLE;
        second_pass <= 1'b0;
        fsm_busy    <= 1'b0;
        round       <= 6'd0;
        k_addr      <= 6'd0;
        sched_en    <= 1'b0;
      end else begin
        case (state)

          //--------------------------------------------------------------------
          IDLE: begin
            fsm_busy <= 1'b0;
            round    <= 6'd0;
            k_addr   <= 6'd0;
            sched_en <= 1'b0;

            if (LEGACY_EN && leg_step_req) begin
              // Legacy Step Mode: LPREP
              state    <= LPREP;
              fsm_busy <= 1'b1;
            end else if (start_req) begin
              // Latch control bits
              first_q <= first_in;
              last_q  <= last_in;

              // On first block: latch auto mode and message length
              if (first_in) begin
                auto_q     <= auto_in;
                msg_len_q  <= msg_len_reg;
                bytes_left <= msg_len_reg;
              end

              second_pass <= 1'b0;

              // Classify block
              begin : classify_block
                reg        auto_eff;
                reg [31:0] bl;
                auto_eff = first_in ? auto_in : auto_q;
                bl       = first_in ? msg_len_reg : bytes_left;

                if (!auto_eff) begin
                  cls      <= CLS_RAW;
                  msg_last <= last_in;
                  pass2    <= PASS2_NONE;
                  // No PAD
                  pad_cnt  <= 4'd0;
                  cyc      <= 7'd0;
                  state    <= LOAD;
                end else if (bl > 32'd64) begin
                  cls      <= CLS_DATA;
                  msg_last <= 1'b0;
                  pass2    <= PASS2_NONE;
                  pad_cnt  <= 4'd0;
                  cyc      <= 7'd0;
                  state    <= LOAD;
                end else if (bl == 32'd64) begin
                  cls      <= CLS_FULL_LAST;
                  msg_last <= 1'b1;
                  pass2    <= PASS2_FULL;
                  pad_cnt  <= 4'd0;
                  cyc      <= 7'd0;
                  state    <= LOAD;  // No PAD on first pass
                end else if (bl >= 32'd56) begin
                  cls      <= CLS_OVF;
                  msg_last <= 1'b1;
                  pass2    <= PASS2_LEN;
                  keep     <= bl[5:0];
                  ins80    <= 1'b1;
                  inslen   <= 1'b0;
                  pad_cnt  <= 4'd0;
                  cyc      <= 7'd0;
                  shift_en <= 1'b1;
                  state    <= PAD;
                end else begin
                  cls      <= CLS_TAIL;
                  msg_last <= 1'b1;
                  pass2    <= PASS2_NONE;
                  keep     <= bl[5:0];
                  ins80    <= 1'b1;
                  inslen   <= 1'b1;
                  pad_cnt  <= 4'd0;
                  cyc      <= 7'd0;
                  shift_en <= 1'b1;
                  state    <= PAD;
                end
              end  // classify_block

              fsm_busy <= 1'b1;
            end
          end // IDLE

          //--------------------------------------------------------------------
          PAD: begin
            // 16 siklus rotasi shift register dengan pad_fn output
            shift_en <= 1'b1;
            // pad_cnt increments each cycle; pad_fn uses current pad_cnt as idx
            pad_cnt <= pad_cnt + 4'd1;
            k_addr <= 6'd0;
            if (pad_cnt == 4'd15) begin
              // Last PAD cycle, next is LOAD
              shift_en <= 1'b0;  // Stop shifting so WRAM holds Word 0 for LOAD
              state    <= LOAD;
              cyc      <= 7'd0;
            end
          end // PAD

          //--------------------------------------------------------------------
          LOAD: begin
            // 1 siklus: muat h_base ke mc, shift WRAM (w_n masuk)
            load     <= 1'b1;
            shift_en <= 1'b1;
            sched_en <= 1'b0;
            cyc      <= 7'd0;
            k_addr   <= 6'd1;   // addr untuk K[0], output K[0] sudah siap (prefetch)
            state    <= PROC;
          end // LOAD

          //--------------------------------------------------------------------
          PROC: begin
            // 64 siklus: round 0..63
            round_en <= 1'b1;
            shift_en <= 1'b1;
            cyc      <= cyc + 7'd1;
            sched_en <= (cyc >= 7'd16);
            round    <= cyc[5:0];   // round = cyc - 1 untuk display; cyc mulai dari 0 saat masuk PROC, pertama kali menampilkan 0

            // K-ROM prefetch: k_addr = (cyc+1) & 63
            k_addr   <= (cyc[5:0] + 6'd2) & 6'd63;  // cyc masih nilai lama (sebelum +1)

            if (cyc == 7'd63) begin
              // Siklus terakhir PROC
              round_en <= 1'b1;
              shift_en <= 1'b1;
              k_addr   <= 6'd0;    // FIN state uses addr 0
              sched_en <= 1'b1;
              state    <= FIN;
            end
          end // PROC

          //--------------------------------------------------------------------
          FIN: begin
            // 1 siklus: tulis HRAM
            hram_we  <= 1'b1;
            k_addr   <= 6'd0;
            sched_en <= 1'b0;
            round    <= 6'd0;

            if (pass2 != PASS2_NONE && !second_pass) begin
              // Blok otomatis (pass-2)
              second_pass <= 1'b1;
              blk_inc     <= 1'b1;

              // Set PAD params untuk pass-2
              case (pass2)
                PASS2_FULL: begin
                  keep   <= 6'd0;
                  ins80  <= 1'b1;
                  inslen <= 1'b1;
                end
                PASS2_LEN: begin
                  keep   <= 6'd0;
                  ins80  <= 1'b0;
                  inslen <= 1'b1;
                end
                default: begin
                  keep   <= 6'd0;
                  ins80  <= 1'b0;
                  inslen <= 1'b0;
                end
              endcase

              pad_cnt  <= 4'd0;
              cyc      <= 7'd0;
              shift_en <= 1'b1;
              state    <= PAD;
            end else begin
              // Selesai
              if (cls == CLS_DATA)
                bytes_left <= bytes_left - 32'd64;

              blk_inc        <= 1'b1;
              done_pulse     <= 1'b1;
              msg_done_pulse <= msg_last;
              state          <= IDLE;
              fsm_busy       <= 1'b0;
            end
          end // FIN

          //--------------------------------------------------------------------
          LPREP: begin
            // Legacy: siklus 1 setelah IDLE → hitung hkw = H+K+W
            leg_prep <= 1'b1;
            k_addr   <= 6'd0;
            sched_en <= 1'b0;
            state    <= LRND;
          end // LPREP

          //--------------------------------------------------------------------
          LRND: begin
            // Legacy: siklus 2 → jalankan satu round (update A..H)
            round_en   <= 1'b1;
            shift_en   <= 1'b0;  // WRAM tidak digeser
            k_addr     <= 6'd0;
            sched_en   <= 1'b0;
            done_pulse <= 1'b1;  // BLOCK_DONE (tanpa MSG_DONE, tanpa blk_inc)
            state      <= IDLE;
            fsm_busy   <= 1'b0;
          end // LRND

          default: begin
            state <= IDLE;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
