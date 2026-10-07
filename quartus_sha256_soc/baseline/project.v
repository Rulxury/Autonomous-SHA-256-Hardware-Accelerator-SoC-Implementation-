/*
 * SPDX-FileCopyrightText: Copyright (c) 2024 xenia dragon
 * SPDX-License-Identifier: Apache-2.0
 *
 * [usagi holding floppy disk.png] i'll just warn you right now, i don't know how to use a computer
 *
 * this is quite literally the first time i've written verilog. i have some VHDL experience but if
 * this code is spaghetti, i'm sorry ;____;
 */

`default_nettype none

module tt_um_xeniarose_sha256 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  // assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  // assign uio_out = 0;
  // assign uio_oe  = 0;

  wire [ 5 : 0 ] io_addr = ui_in[5 : 0];
  wire io_we = ui_in[6];
  wire io_clk = ui_in[7];

  reg io_ready;
  assign uo_out[0] = io_ready;

  assign uo_out[1] = io_we;
  assign uo_out[7 : 2] = 6'h0;
  assign uio_oe[0] = io_we;
  assign uio_oe[1] = io_we;
  assign uio_oe[2] = io_we;
  assign uio_oe[3] = io_we;
  assign uio_oe[4] = io_we;
  assign uio_oe[5] = io_we;
  assign uio_oe[6] = io_we;
  assign uio_oe[7] = io_we;

  reg [7 : 0] io_out;
  assign uio_out = io_out;

  reg [ 31 : 0 ] register_file [ 9 : 0 ];

  `define A_reg register_file[0]
  `define B_reg register_file[1]
  `define C_reg register_file[2]
  `define D_reg register_file[3]
  `define E_reg register_file[4]
  `define F_reg register_file[5]
  `define G_reg register_file[6]
  `define H_reg register_file[7]
  `define W_reg register_file[8]
  `define K_reg register_file[9]

  wire [ 31 : 0 ] s1 =
    {`E_reg[5:0],`E_reg[31:6]} ^ {`E_reg[10:0],`E_reg[31:11]} ^ {`E_reg[24:0],`E_reg[31:25]};
  wire [ 31 : 0 ] ch = (`E_reg & `F_reg) ^ ((~`E_reg) & `G_reg);
  wire [ 31 : 0 ] temp1 = `H_reg + s1 + ch + `K_reg + `W_reg;
  wire [ 31 : 0 ] s0 =
    {`A_reg[1:0],`A_reg[31:2]} ^ {`A_reg[12:0],`A_reg[31:13]} ^ {`A_reg[21:0],`A_reg[31:22]};
  wire [ 31 : 0 ] maj = (`A_reg & `B_reg) ^ (`A_reg & `C_reg) ^ (`B_reg & `C_reg);
  wire [ 31 : 0 ] temp2 = s0 + maj;

  always @(posedge clk or negedge rst_n) begin : io_proc
    if (!rst_n) begin
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

      io_out <= 8'h0;
      io_ready <= 0;
    end else begin
      io_ready <= 1;

      if (io_clk) begin
        if (!io_we) begin
          case (io_addr)
            63: begin
              `A_reg <= temp1 + temp2;
              `B_reg <= `A_reg;
              `C_reg <= `B_reg;
              `D_reg <= `C_reg;
              `E_reg <= `D_reg + temp1;
              `F_reg <= `E_reg;
              `G_reg <= `F_reg;
              `H_reg <= `G_reg;
            end

            default: begin
              case (io_addr[1:0])
                2'h0: begin register_file[io_addr[5:2]][7 : 0] <= uio_in; end
                2'h1: begin register_file[io_addr[5:2]][15 : 8] <= uio_in; end
                2'h2: begin register_file[io_addr[5:2]][23 : 16] <= uio_in; end
                2'h3: begin register_file[io_addr[5:2]][31 : 24] <= uio_in; end
              endcase
            end
          endcase
        end else begin
          case (io_addr)
            63: begin io_out <= 8'h0; end

            default: begin
              case (io_addr[1:0])
                2'h0: begin io_out <= register_file[io_addr[5:2]][7 : 0]; end
                2'h1: begin io_out <= register_file[io_addr[5:2]][15 : 8]; end
                2'h2: begin io_out <= register_file[io_addr[5:2]][23 : 16]; end
                2'h3: begin io_out <= register_file[io_addr[5:2]][31 : 24]; end
              endcase
            end
          endcase
        end
      end

    end
  end // rst_proc

endmodule
