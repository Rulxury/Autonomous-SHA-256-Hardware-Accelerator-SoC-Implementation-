// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// sha256_csr.v — Avalon-MM CSR / Register File
// Avalon-MM slave, readLatency = 1, no waitrequest, no byteenable.
// Mengatur: REG_CTRL, REG_STATUS (W1C), REG_BLOCK_CNT, REG_MSG_LEN,
//           WRAM_DATA (WO), HRAM_DIGEST (RO), REG_ID, REG_IRQ_MASK,
//           LEG_REG[0..9] (bila LEGACY_EN).

`default_nettype none

module sha256_csr #(
    parameter LEGACY_EN = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    // Avalon-MM slave
    input  wire [5:0]   avs_address,
    input  wire         avs_read,
    input  wire         avs_write,
    input  wire [31:0]  avs_writedata,
    output reg  [31:0]  avs_readdata,
    output wire         irq,
    // Ke / dari core
    output wire         soft_rst,
    output wire         start_req,
    output wire         first_out, last_out, auto_out,
    output wire [31:0]  msg_len_reg,
    output wire         host_we,
    output wire [3:0]   host_idx,
    output wire [31:0]  host_data,
    // Legacy
    output wire         leg_step_req,
    output wire         leg_we,
    output wire [3:0]   leg_idx,
    output wire [31:0]  leg_data,
    // Dari core
    input  wire         fsm_busy,
    input  wire [5:0]   round,
    input  wire         blk_inc,
    input  wire         done_pulse,
    input  wire         msg_done_pulse,
    input  wire [255:0] digest,
    input  wire [255:0] state_dbg,
    input  wire [31:0]  leg_w_in, leg_k_in
);

  // -------- Address constants (word address) --------
  localparam ADDR_CTRL       = 6'h00;
  localparam ADDR_STATUS     = 6'h01;
  localparam ADDR_BLOCK_CNT  = 6'h02;
  localparam ADDR_MSG_LEN    = 6'h03;
  // 0x04..0x13 = WRAM_DATA[0..15]
  // 0x14..0x1B = HRAM_DIGEST[0..7]
  localparam ADDR_ID         = 6'h1C;
  localparam ADDR_IRQ_MASK   = 6'h1D;
  // 0x20..0x29 = LEG_REG[0..9] (LEGACY_EN only)

  // -------- Registers --------
  reg        busy_q;
  reg        block_done_q, msg_done_q, err_q, msg_active_q;
  reg [31:0] block_cnt_q;
  reg [31:0] msg_len_q;
  reg [2:0]  irq_mask_q;        // [0]=BLOCK_DONE_IE, [1]=MSG_DONE_IE, [2]=ERR_IE

  // Latched control from START write
  reg        first_q, last_q, auto_q;
  reg        start_req_q;
  reg        soft_rst_q;
  reg        leg_step_req_q;

  // Host WRAM write
  reg        host_we_r;
  reg [3:0]  host_idx_r;
  reg [31:0] host_data_r;

  // Legacy write
  reg        leg_we_r;
  reg [3:0]  leg_idx_r;
  reg [31:0] leg_data_r;

  // -------- Decode --------
  wire is_wram   = (avs_address >= 6'h04) && (avs_address <= 6'h13);
  wire is_hram   = (avs_address >= 6'h14) && (avs_address <= 6'h1B);
  wire is_leg    = (avs_address >= 6'h20) && (avs_address <= 6'h29);
  wire is_leg_rsvd = (avs_address >= 6'h2A) && (avs_address <= 6'h3F);

  wire [3:0] wram_idx = avs_address[3:0] - 4'h4;  // 0x04..0x13 -> 0..15
  wire [2:0] hram_idx = avs_address[2:0] - 3'h4;  // 0x14..0x1B -> 0..7
  wire [3:0] leg_ridx = avs_address[3:0];           // 0x20..0x29 -> idx 0..9

  // -------- Write Logic --------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q        <= 1'b0;
      block_done_q  <= 1'b0;
      msg_done_q    <= 1'b0;
      err_q         <= 1'b0;
      msg_active_q  <= 1'b0;
      block_cnt_q   <= 32'h0;
      msg_len_q     <= 32'h0;
      irq_mask_q    <= 3'b0;
      first_q       <= 1'b0;
      last_q        <= 1'b0;
      auto_q        <= 1'b0;
      start_req_q   <= 1'b0;
      soft_rst_q    <= 1'b0;
      leg_step_req_q<= 1'b0;
      host_we_r     <= 1'b0;
      host_idx_r    <= 4'h0;
      host_data_r   <= 32'h0;
      leg_we_r      <= 1'b0;
      leg_idx_r     <= 4'h0;
      leg_data_r    <= 32'h0;
    end else begin
      // Default strobe-offs
      start_req_q    <= 1'b0;
      soft_rst_q     <= 1'b0;
      leg_step_req_q <= 1'b0;
      host_we_r      <= 1'b0;
      leg_we_r       <= 1'b0;

      // ---- Hardware set flags ----
      if (done_pulse)     block_done_q <= 1'b1;
      if (msg_done_pulse) begin
        msg_done_q   <= 1'b1;
        msg_active_q <= 1'b0;
      end
      if (blk_inc)
        block_cnt_q <= block_cnt_q + 32'd1;

      // ---- Write cycle ----
      if (avs_write) begin

        // CTRL register
        if (avs_address == ADDR_CTRL) begin
          // SOFT_RST has priority over everything
          if (avs_writedata[1]) begin
            soft_rst_q    <= 1'b1;
            busy_q        <= 1'b0;
            msg_active_q  <= 1'b0;
            block_done_q  <= 1'b0;
            msg_done_q    <= 1'b0;
            block_cnt_q   <= 32'h0;
            err_q         <= 1'b0;

          // START=1 and LEG_STEP=1 simultaneously -> ERR, ignore both
          end else if (avs_writedata[0] && avs_writedata[6] && LEGACY_EN) begin
            err_q <= 1'b1;

          // START=1
          end else if (avs_writedata[0]) begin
            if (busy_q) begin
              err_q <= 1'b1;  // START while BUSY
            end else if (!avs_writedata[2] && !msg_active_q) begin
              err_q <= 1'b1;  // FIRST_BLK=0, no active message
            end else begin
              // Accept START
              busy_q       <= 1'b1;
              msg_active_q <= 1'b1;
              block_done_q <= 1'b0;
              msg_done_q   <= 1'b0;
              // Latch control bits from this very write
              first_q      <= avs_writedata[2];
              last_q       <= avs_writedata[3];
              auto_q       <= avs_writedata[5];
              start_req_q  <= 1'b1;
            end

          // LEG_STEP=1 (LEGACY_EN, START=0)
          end else if (avs_writedata[6] && LEGACY_EN) begin
            if (busy_q) begin
              err_q <= 1'b1;
            end else begin
              busy_q         <= 1'b1;
              block_done_q   <= 1'b0;
              msg_done_q     <= 1'b0;
              leg_step_req_q <= 1'b1;
            end
          end
        end // CTRL

        // REG_MSG_LEN
        else if (avs_address == ADDR_MSG_LEN) begin
          msg_len_q <= avs_writedata;
        end

        // REG_IRQ_MASK
        else if (avs_address == ADDR_IRQ_MASK) begin
          irq_mask_q <= avs_writedata[2:0];
        end

        // STATUS (W1C)
        else if (avs_address == ADDR_STATUS) begin
          if (avs_writedata[1]) block_done_q <= 1'b0;
          if (avs_writedata[2]) msg_done_q   <= 1'b0;
          if (avs_writedata[3]) err_q        <= 1'b0;
          // Set-wins: if hardware set on same cycle, it wins (handled by OR above)
        end

        // WRAM write
        else if (is_wram) begin
          if (busy_q) begin
            err_q <= 1'b1;
          end else begin
            host_we_r   <= 1'b1;
            host_idx_r  <= avs_address[3:0] - 4'h4;
            host_data_r <= avs_writedata;
          end
        end

        // Legacy register window write (LEGACY_EN)
        else if (is_leg && LEGACY_EN) begin
          if (busy_q) begin
            err_q <= 1'b1;
          end else begin
            leg_we_r   <= 1'b1;
            leg_idx_r  <= avs_address[3:0];
            leg_data_r <= avs_writedata;
          end
        end

        // All other writes: ignored without ERR

      end // avs_write

      // ---- done_pulse: clear busy ----
      if (done_pulse) begin
        busy_q <= 1'b0;
      end

      // ---- soft_rst: clear block_cnt handled above ----

    end // else rst_n
  end // always

  // -------- Read Logic (registered, readLatency = 1) --------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      avs_readdata <= 32'h0;
    end else if (avs_read) begin
      case (avs_address)
        ADDR_CTRL:      avs_readdata <= 32'h0;  // START/SOFT_RST/LEG_STEP self-clear; read 0
        ADDR_STATUS:    avs_readdata <= {18'h0, round, 2'h0, msg_active_q, err_q, msg_done_q, block_done_q, busy_q};
        ADDR_BLOCK_CNT: avs_readdata <= block_cnt_q;
        ADDR_MSG_LEN:   avs_readdata <= msg_len_q;
        ADDR_ID:        avs_readdata <= 32'h53484132;   // "SHA2"
        ADDR_IRQ_MASK:  avs_readdata <= {29'h0, irq_mask_q};
        default: begin
          if (is_wram)
            avs_readdata <= 32'h0;   // WRAM write-only
          else if (is_hram)
            avs_readdata <= digest[255 - 32*hram_idx -: 32];
          else if (is_leg && LEGACY_EN) begin
            // LEG_REG[0..7] = A..H from state_dbg; [8]=W; [9]=K
            case (leg_ridx)
              4'd0, 4'd1, 4'd2, 4'd3,
              4'd4, 4'd5, 4'd6, 4'd7:
                avs_readdata <= state_dbg[255 - 32*leg_ridx -: 32];
              4'd8:   avs_readdata <= leg_w_in;
              4'd9:   avs_readdata <= leg_k_in;
              default: avs_readdata <= 32'h0;
            endcase
          end else
            avs_readdata <= 32'h0;
        end
      endcase
    end
  end

  // -------- IRQ --------
  assign irq = (irq_mask_q[0] & block_done_q) |
               (irq_mask_q[1] & msg_done_q)   |
               (irq_mask_q[2] & err_q);

  // -------- Output drives --------
  assign soft_rst      = soft_rst_q;
  assign start_req     = start_req_q;
  assign first_out     = first_q;
  assign last_out      = last_q;
  assign auto_out      = auto_q;
  assign msg_len_reg   = msg_len_q;
  assign host_we       = host_we_r;
  assign host_idx      = host_idx_r;
  assign host_data     = host_data_r;
  assign leg_step_req  = leg_step_req_q;
  assign leg_we        = leg_we_r;
  assign leg_idx       = leg_idx_r;
  assign leg_data      = leg_data_r;

endmodule

`default_nettype wire
