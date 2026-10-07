// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// tb_baseline_equiv.sv — T1: Ekuivalensi mc.v vs tt_um_xeniarose_sha256 asli
//
// Menjalankan ≥ 10.000 round acak pada kedua modul dengan stimulus identik:
// - Tulis A..H, W, K acak (baseline: byte per byte; mc: leg_we per word)
// - Picu satu round (baseline: io_clk=1, io_we=0, io_addr=63; mc: leg_prep lalu round_en)
// - Bandingkan register_file[i] untuk i=0..7 (A..H)
// Lulus bila ZERO mismatch.
//
// CATATAN KOMPILASI: baseline/project.v harus dikompilasi dalam unit terpisah
// (misalnya: vlog -work baseline_lib baseline/project.v)
// agar `default_nettype none di project.v tidak mempengaruhi mc.v.

`timescale 1ns/1ps

module tb_baseline_equiv;

  // DUT clocks / resets
  reg clk, rst_n;

  // ----- Baseline DUT (tt_um_xeniarose_sha256) -----
  reg  [7:0] ui_in_b;
  wire [7:0] uo_out_b;
  reg  [7:0] uio_in_b;
  wire [7:0] uio_out_b;
  wire [7:0] uio_oe_b;

  tt_um_xeniarose_sha256 u_baseline (
    .ui_in   (ui_in_b),
    .uo_out  (uo_out_b),
    .uio_in  (uio_in_b),
    .uio_out (uio_out_b),
    .uio_oe  (uio_oe_b),
    .ena     (1'b1),
    .clk     (clk),
    .rst_n   (rst_n)
  );

  // ----- MC DUT -----
  reg         load_mc, round_en_mc;
  reg  [255:0] h_base_mc;
  reg  [31:0] k_val_mc, w_n_mc;
  reg         leg_prep_mc, leg_we_mc;
  reg  [3:0]  leg_idx_mc;
  reg  [31:0] leg_data_mc;
  wire [31:0] leg_w_mc, leg_k_mc;
  wire [255:0] state_out_mc;

  mc #(.LEGACY_EN(1)) u_mc (
    .clk      (clk),
    .rst_n    (rst_n),
    .load     (load_mc),
    .round_en (round_en_mc),
    .h_base   (h_base_mc),
    .k_val    (k_val_mc),
    .w_n      (w_n_mc),
    .leg_prep (leg_prep_mc),
    .leg_we   (leg_we_mc),
    .leg_idx  (leg_idx_mc),
    .leg_data (leg_data_mc),
    .leg_w    (leg_w_mc),
    .leg_k    (leg_k_mc),
    .state_out(state_out_mc)
  );

  // ----- Clock -----
  initial clk = 0;
  always #5 clk = ~clk;

  // ----- Counters -----
  integer mismatch_cnt;
  integer round_cnt;
  integer seed;
  integer i;

  // ----- Task: write one byte to baseline register_file -----
  task baseline_write_byte;
    input [5:0] addr;
    input [7:0] data;
    begin
      @(negedge clk);
      ui_in_b  = {1'b1, 1'b0, addr};  // io_clk=1, io_we=0, addr
      uio_in_b = data;
      @(posedge clk); #1;
      ui_in_b  = 8'h0;
      uio_in_b = 8'h0;
    end
  endtask

  // Write full 32-bit word to baseline (4 bytes, little-endian byte lanes)
  task baseline_write_word;
    input [3:0] reg_idx;   // register file index (0..9)
    input [31:0] val;
    begin
      baseline_write_byte({reg_idx, 2'b00}, val[7:0]);
      baseline_write_byte({reg_idx, 2'b01}, val[15:8]);
      baseline_write_byte({reg_idx, 2'b10}, val[23:16]);
      baseline_write_byte({reg_idx, 2'b11}, val[31:24]);
    end
  endtask

  // Trigger one round on baseline (write addr=63, io_we=0)
  task baseline_run_round;
    begin
      @(negedge clk);
      ui_in_b  = {1'b1, 1'b0, 6'd63};  // io_clk=1, io_we=0, addr=63
      uio_in_b = 8'h0;
      @(posedge clk); #1;
      ui_in_b  = 8'h0;
    end
  endtask

  // Write word to mc via leg_we
  task mc_write_word;
    input [3:0] idx;
    input [31:0] val;
    begin
      @(negedge clk);
      leg_we_mc   = 1'b1;
      leg_idx_mc  = idx;
      leg_data_mc = val;
      @(posedge clk); #1;
      leg_we_mc   = 1'b0;
    end
  endtask

  // Run one round on mc: LPREP then round_en
  task mc_run_round;
    begin
      // LPREP
      @(negedge clk);
      leg_prep_mc = 1'b1;
      @(posedge clk); #1;
      leg_prep_mc = 1'b0;
      // LRND
      @(negedge clk);
      round_en_mc = 1'b1;
      @(posedge clk); #1;
      round_en_mc = 1'b0;
    end
  endtask

  // Read A..H from baseline via hierarchical access
  // (direct: u_baseline.register_file[i])

  // ----- Main test -----
  initial begin
    $display("T1: tb_baseline_equiv — ekuivalensi mc vs tt_um_xeniarose_sha256");
    $display("Target: >= 10000 round, 0 mismatch");

    // Init signals
    rst_n       = 1'b0;
    ui_in_b     = 8'h0;
    uio_in_b    = 8'h0;
    load_mc     = 1'b0;
    round_en_mc = 1'b0;
    leg_prep_mc = 1'b0;
    leg_we_mc   = 1'b0;
    leg_idx_mc  = 4'h0;
    leg_data_mc = 32'h0;
    h_base_mc   = 256'h0;
    k_val_mc    = 32'h0;
    w_n_mc      = 32'h0;
    mismatch_cnt = 0;
    round_cnt    = 0;
    seed         = 42;

    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // ================================================================
    // TEST LOOP: 10000+ random rounds
    // ================================================================
    begin : test_loop
      reg [31:0] regs [0:9];  // A..H, W, K
      reg [31:0] base_A, base_B, base_C, base_D, base_E, base_F, base_G, base_H;

      repeat (10010) begin : one_round
        // Generate random register values
        for (i = 0; i < 10; i = i + 1) begin
          seed    = seed * 1664525 + 1013904223;
          regs[i] = seed;
        end
        // Also test extremes every 1000 rounds
        if (round_cnt % 1000 == 0) begin
          regs[0] = 32'hFFFFFFFF; regs[1] = 32'h0;
          regs[7] = 32'h80000000; regs[8] = 32'hDEADBEEF;
          regs[9] = 32'hCAFEBABE;
        end

        // ---- Write to baseline ----
        for (i = 0; i < 10; i = i + 1)
          baseline_write_word(i[3:0], regs[i]);

        // ---- Write to mc ----
        for (i = 0; i < 10; i = i + 1)
          mc_write_word(i[3:0], regs[i]);

        // ---- Run one round on each ----
        baseline_run_round();
        mc_run_round();

        // ---- Compare A..H ----
        @(posedge clk); #1;

        // Check each register
        if (u_baseline.register_file[0] !== u_mc.register_file[0]) begin
          $display("MISMATCH round %0d: A baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[0], u_mc.register_file[0]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[1] !== u_mc.register_file[1]) begin
          $display("MISMATCH round %0d: B baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[1], u_mc.register_file[1]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[2] !== u_mc.register_file[2]) begin
          $display("MISMATCH round %0d: C baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[2], u_mc.register_file[2]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[3] !== u_mc.register_file[3]) begin
          $display("MISMATCH round %0d: D baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[3], u_mc.register_file[3]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[4] !== u_mc.register_file[4]) begin
          $display("MISMATCH round %0d: E baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[4], u_mc.register_file[4]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[5] !== u_mc.register_file[5]) begin
          $display("MISMATCH round %0d: F baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[5], u_mc.register_file[5]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[6] !== u_mc.register_file[6]) begin
          $display("MISMATCH round %0d: G baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[6], u_mc.register_file[6]);
          mismatch_cnt = mismatch_cnt + 1;
        end
        if (u_baseline.register_file[7] !== u_mc.register_file[7]) begin
          $display("MISMATCH round %0d: H baseline=%08h mc=%08h",
                   round_cnt, u_baseline.register_file[7], u_mc.register_file[7]);
          mismatch_cnt = mismatch_cnt + 1;
        end

        round_cnt = round_cnt + 1;
        if (round_cnt % 2000 == 0)
          $display("  Progress: %0d / 10010 rounds completed...", round_cnt);
      end // one_round
    end // test_loop

    $display("");
    $display("T1 RESULT: %0d rounds checked, %0d mismatch(es)", round_cnt, mismatch_cnt);
    if (mismatch_cnt == 0)
      $display("T1 PASS");
    else
      $display("T1 FAIL");

    $finish;
  end

  // Timeout watchdog
  initial begin
    #15000000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
