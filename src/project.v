// project.v
// SPDX‑FileCopyrightText: © 2025 Laya
// SPDX‑License-Identifier: Apache‑2.0
`default_nettype none
`timescale 1ns/1ps

module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire pkt_v = ui_in[0];
    wire [7:0] din = ui_in & 8'hFE;
    wire [2:0] read_en = uio_in[2:0];

    wire [2:0] vld;
    wire err, busy;
    wire [7:0] dout0, dout1, dout2;

    router core (
        .clk(clk), .rst_n(rst_n),
        .pkt_v(pkt_v), .din(din),
        .read_en(read_en),
        .vld(vld), .err(err), .busy(busy),
        .dout0(dout0), .dout1(dout1), .dout2(dout2)
    );

    assign uo_out = {3'b000, vld, err, busy};
    assign uio_out = dout0;
    assign uio_oe  = 8'b11111000;
    // avoid warnings
    wire _unused = &{ena, uio_in[7:3], dout1, dout2, 1'b0};
endmodule

module router (
    input  wire        clk, rst_n, pkt_v,
    input  wire [7:0]  din,
    input  wire [2:0]  read_en,
    output reg  [2:0]  vld,
    output reg         err, busy,
    output wire [7:0]  dout0, dout1, dout2
);
    localparam MAXDEPTH = 4;
    reg [7:0] fifo0 [0:MAXDEPTH-1], fifo1 [0:MAXDEPTH-1], fifo2 [0:MAXDEPTH-1];
    reg [1:0] wr0, wr1, wr2, rd0, rd1, rd2;
    reg [2:0] cnt0, cnt1, cnt2;

    reg [7:0] header, parity_acc;
    reg [3:0] len_expected, len_cnt;
    reg expecting_parity, pkt_active;

    wire [1:0] ch = header[1:0];
    wire valid_ch = (ch <= 2);

    always @(posedge clk) begin
        if (!rst_n) begin
            header <= 0; parity_acc <= 0; len_expected <= 0;
            len_cnt <= 0; expecting_parity <= 0; pkt_active <= 0;
            err <= 0; busy <= 0;
        end else begin
            if (!pkt_active && pkt_v) begin
                header <= din;
                len_expected <= din[5:2];
                parity_acc <= din;
                len_cnt <= 0;
                expecting_parity <= 0;
                pkt_active <= 1;
                busy <= 1;
                err <= 0;
            end else if (pkt_active && pkt_v) begin
                if (!expecting_parity && len_cnt < len_expected) begin
                    parity_acc <= parity_acc ^ din;
                    len_cnt <= len_cnt + 1;
                    if (len_cnt + 1 == len_expected) expecting_parity <= 1;
                    if (valid_ch) begin
                        case (ch)
                            2'd0: if (cnt0 < MAXDEPTH) fifo0[wr0] <= din;
                            2'd1: if (cnt1 < MAXDEPTH) fifo1[wr1] <= din;
                            2'd2: if (cnt2 < MAXDEPTH) fifo2[wr2] <= din;
                        endcase
                    end
                end else if (expecting_parity) begin
                    err <= (parity_acc != din);
                    pkt_active <= 0;
                    busy <= 0;
                end
            end
        end
    end

    always @(posedge clk) if (rst_n) begin
        if (pkt_active && pkt_v && !expecting_parity && valid_ch && len_cnt <= len_expected) begin
            case (ch)
                2'd0: if (cnt0 < MAXDEPTH) begin wr0 <= wr0+1; cnt0 <= cnt0+1; end
                2'd1: if (cnt1 < MAXDEPTH) begin wr1 <= wr1+1; cnt1 <= cnt1+1; end
                2'd2: if (cnt2 < MAXDEPTH) begin wr2 <= wr2+1; cnt2 <= cnt2+1; end
            endcase
        end
        if (read_en[0] && cnt0 > 0) begin rd0 <= rd0+1; cnt0 <= cnt0-1; end
        if (read_en[1] && cnt1 > 0) begin rd1 <= rd1+1; cnt1 <= cnt1-1; end
        if (read_en[2] && cnt2 > 0) begin rd2 <= rd2+1; cnt2 <= cnt2-1; end
    end

    assign dout0 = (cnt0>0) ? fifo0[rd0] : 8'd0;
    assign dout1 = (cnt1>0) ? fifo1[rd1] : 8'd0;
    assign dout2 = (cnt2>0) ? fifo2[rd2] : 8'd0;

    always @* begin
        vld[0] = cnt0>0;
        vld[1] = cnt1>0;
        vld[2] = cnt2>0;
    end
endmodule
