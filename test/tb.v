`default_nettype none
`timescale 1ns / 1ps

module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  tt_um_protocol_emu user_project (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // Clock
  always #10 clk = ~clk;

  initial begin
    clk = 0;
    rst_n = 0;
    ena = 1;
    ui_in = 8'h00;
    uio_in = 8'hFF; // CS high (inactive)
    #100;
    rst_n = 1;
    #1000;
    $finish;
  end

endmodule
