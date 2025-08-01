// tb.v
`default_nettype none
`timescale 1ns/1ps

module tb();
  reg clk = 0;
  always #5 clk = ~clk;

  reg rst_n = 0;
  reg ena = 1;
  reg [7:0] ui_in = 0;
  reg [7:0] uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_example dut (
    .clk(clk), .rst_n(rst_n), .ena(ena),
    .ui_in(ui_in), .uio_in(uio_in),
    .uo_out(uo_out), .uio_out(uio_out), .uio_oe(uio_oe)
  );

  initial begin
    #20 rst_n = 1;
    send_pkt(2, 0);
    #100;
    send_pkt(1, 2);
    #100;
    send_pkt(3, 1);
    #100;
    $finish;
  end

  task send_pkt(input [3:0] L, input [1:0] ch);
    integer i;
    reg [7:0] hdr, parity, data;
    hdr = {2'b00, L, ch};
    parity = hdr;
    ui_in = hdr | 8'h01; @(posedge clk);
    for (i = 0; i < L; i = i + 1) begin
      data = 8'hA0 + {ch, i};
      parity = parity ^ data;
      ui_in = data | 8'h01; @(posedge clk);
    end
    ui_in = parity | 8'h01; @(posedge clk);
    ui_in = 0; @(posedge clk);
  endtask
endmodule
