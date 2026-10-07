/*
 * SPDX-FileCopyrightText: Copyright (c) 2024 xenia dragon
 * SPDX-FileCopyrightText: Copyright (c) 2026 Peruri (modifications)
 * SPDX-License-Identifier: Apache-2.0
 *
 * mc.v — SHA-256 Compression Core
 *
 * DERIVED from baseline/project.v (tt_um_xeniarose_sha256, © 2024 xenia dragon, Apache-2.0).
 * This file was created by:
 *   1. Copying baseline/project.v to rtl/mc.v
 *   2. Removing Tiny Tapeout pin interface (ui_in, uio, uo_out, io_*)
 *   3. Replacing the byte-lane write trigger (addr==63) with load/round_en ports
 *   4. Adding hkw precompute register (H+K+W one cycle ahead)
 *   5. Adding h_base load path and Legacy Step Mode ports
 *
 * Modification summary (see §4.6 and §12.3 of implementation_plan_revised_v2.md):
 *   [BASELINE] = copied verbatim from project.v
 *   [MODIFIED] = changed from baseline
 *   [NEW]      = added (not present in baseline)
 *
 * Key change: temp1 = hkw + s1 + ch  where hkw = H + K + W precomputed one cycle earlier.
 *             Arithmetically identical to baseline's temp1 = H + s1 + ch + K + W.
 */

`default_nettype none                                       // [BASELINE]

module mc #(
    parameter LEGACY_EN = 1               // [NEW] 0 = buang Legacy Step Mode (§12.4)
) (
    input  wire         clk,              // [BASELINE]
    input  wire         rst_n,            // [BASELINE] reset async
    input  wire         load,             // [NEW] siklus LOAD (cyc = 0)
    input  wire         round_en,         // [NEW] pengganti "tulis alamat 63" (PROC atau LRND)
    input  wire [255:0] h_base,           // [NEW] {A..H} awal = first_eff ? IV : HRAM
    input  wire [31:0]  k_val,            // [NEW] K[n] dari k_rom
    input  wire [31:0]  w_n,              // [NEW] W[n] dari me.v
    // Legacy Step Mode (LEGACY_EN = 1; bila 0 ikat input ke 0)
    input  wire         leg_prep,         // [NEW] hkw <= H_reg + K_reg + W_reg
    input  wire         leg_we,           // [NEW] tulis register_file[leg_idx]
    input  wire [3:0]   leg_idx,          // [NEW] 0..7 = A..H, 8 = W, 9 = K
    input  wire [31:0]  leg_data,         // [NEW]
    output wire [31:0]  leg_w, leg_k,     // [NEW] W_reg, K_reg (jendela baca legacy)
    output wire [255:0] state_out         // [NEW] {A,B,C,D,E,F,G,H}
);

  reg [ 31 : 0 ] register_file [ 9 : 0 ];          // [BASELINE]

  `define A_reg register_file[0]                   // [BASELINE] dst. sampai K_reg
  `define B_reg register_file[1]
  `define C_reg register_file[2]
  `define D_reg register_file[3]
  `define E_reg register_file[4]
  `define F_reg register_file[5]
  `define G_reg register_file[6]
  `define H_reg register_file[7]
  `define W_reg register_file[8]                   // hanya dipakai Legacy Step Mode
  `define K_reg register_file[9]                   // hanya dipakai Legacy Step Mode

  reg [ 31 : 0 ] hkw;                              // [NEW] H_t + K_t + W_t

  wire [ 31 : 0 ] s1 =                             // [BASELINE] verbatim
    {`E_reg[5:0],`E_reg[31:6]} ^ {`E_reg[10:0],`E_reg[31:11]} ^ {`E_reg[24:0],`E_reg[31:25]};
  wire [ 31 : 0 ] ch = (`E_reg & `F_reg) ^ ((~`E_reg) & `G_reg);   // [BASELINE]
  // [MODIFIED] baseline: temp1 = `H_reg + s1 + ch + `K_reg + `W_reg
  wire [ 31 : 0 ] temp1 = hkw + s1 + ch;           // H+K+W sudah dijumlahkan satu siklus lebih awal
  wire [ 31 : 0 ] s0 =                             // [BASELINE] verbatim
    {`A_reg[1:0],`A_reg[31:2]} ^ {`A_reg[12:0],`A_reg[31:13]} ^ {`A_reg[21:0],`A_reg[31:22]};
  wire [ 31 : 0 ] maj = (`A_reg & `B_reg) ^ (`A_reg & `C_reg) ^ (`B_reg & `C_reg);  // [BASELINE]
  wire [ 31 : 0 ] temp2 = s0 + maj;                // [BASELINE]

  always @(posedge clk or negedge rst_n) begin : mc_proc   // [MODIFIED] sebelumnya io_proc
    if (!rst_n) begin                              // [BASELINE] semua register di-reset 0
      register_file[0] <= 32'h0;
      register_file[1] <= 32'h0;
      register_file[2] <= 32'h0;
      register_file[3] <= 32'h0;
      register_file[4] <= 32'h0;
      register_file[5] <= 32'h0;
      register_file[6] <= 32'h0;
      register_file[7] <= 32'h0;
      register_file[8] <= 32'h0;
      register_file[9] <= 32'h0;
      hkw <= 32'h0;                                // [NEW]
    end else if (load) begin                       // [NEW] muat state awal blok
      {`A_reg,`B_reg,`C_reg,`D_reg,`E_reg,`F_reg,`G_reg,`H_reg} <= h_base;
      hkw <= h_base[31:0] + k_val + w_n;           // H_0 + K_0 + W_0
    end else if (round_en) begin                   // [MODIFIED] sebelumnya: io_clk, !io_we, case 63
      `A_reg <= temp1 + temp2;                     // [BASELINE] isi `case 63`, persis
      `B_reg <= `A_reg;
      `C_reg <= `B_reg;
      `D_reg <= `C_reg;
      `E_reg <= `D_reg + temp1;
      `F_reg <= `E_reg;
      `G_reg <= `F_reg;
      `H_reg <= `G_reg;
      hkw    <= `G_reg + k_val + w_n;              // [NEW] H_{t+1} = G_t ; K_{t+1}, W_{t+1}
    end else if (LEGACY_EN && leg_prep) begin      // [NEW]
      hkw <= `H_reg + `K_reg + `W_reg;
    end else if (LEGACY_EN && leg_we) begin        // [NEW] padanan tulis register di project.v
      if (leg_idx <= 4'd9) register_file[leg_idx] <= leg_data;
    end
  end

  assign state_out = {`A_reg,`B_reg,`C_reg,`D_reg,`E_reg,`F_reg,`G_reg,`H_reg};  // [NEW]
  assign leg_w = `W_reg;                           // [NEW]
  assign leg_k = `K_reg;                           // [NEW]

endmodule

`undef A_reg                                       // [NEW] cegah kebocoran makro ke berkas lain
`undef B_reg
`undef C_reg
`undef D_reg
`undef E_reg
`undef F_reg
`undef G_reg
`undef H_reg
`undef W_reg
`undef K_reg
`default_nettype wire                              // [NEW] pulihkan (baseline tidak memulihkan)
