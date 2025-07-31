`timescale 1ns/1ps

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Router signals - 3 channels but minimal
    wire [2:0] vldout;
    wire err, busy;
    wire [7:0] data_out_0, data_out_1, data_out_2;
    
    // Input mapping
    wire packet_valid = ui_in[0];
    wire [7:0] datain = ui_in;
    
    // Read enables from uio_in
    wire [2:0] read_enb = uio_in[2:0];
    
    // Instantiate ultra-compact router
    router_ultra_compact router_inst (
        .clk(clk),
        .resetn(rst_n),
        .packet_valid(packet_valid),
        .read_enb(read_enb),
        .datain(datain),
        .vldout(vldout),
        .err(err),
        .busy(busy),
        .data_out_0(data_out_0),
        .data_out_1(data_out_1),
        .data_out_2(data_out_2)
    );
    
    // Output mapping
    assign uo_out = {3'b0, vldout[2], vldout[1], vldout[0], err, busy};
    assign uio_out = data_out_0; // Only output channel 0 data due to pin limitations
    assign uio_oe = 8'b11111111;
    
    // Unused signal to prevent warnings
    wire _unused = &{ena, uio_in[7:3], data_out_1[7:6], data_out_2[7:6], 1'b0};

endmodule

// Ultra-compact 3-channel router - maximum area optimization
module router_ultra_compact(
    input clk, resetn, packet_valid,
    input [2:0] read_enb,
    input [7:0] datain, 
    output [2:0] vldout,
    output reg err, busy,
    output [7:0] data_out_0, data_out_1, data_out_2
);

    // Minimal state machine - only 3 states!
    reg [1:0] state;
    parameter IDLE = 2'b00, LOAD = 2'b01, CHECK = 2'b10;
    
    // Ultra-small FIFOs - depth 4, no fancy features
    reg [7:0] fifo_0 [3:0], fifo_1 [3:0], fifo_2 [3:0];
    reg [1:0] wr_ptr_0, wr_ptr_1, wr_ptr_2;
    reg [1:0] rd_ptr_0, rd_ptr_1, rd_ptr_2;
    reg [2:0] count_0, count_1, count_2;
    
    // Minimal registers
    reg [7:0] header;
    reg [1:0] channel;
    reg [3:0] length;
    reg [7:0] calc_parity, recv_parity;
    reg parity_mode;

    // Channel decode - only look at address bits
    always @(*) begin
        case (datain[1:0])
            2'b00: channel = 2'b00;
            2'b01: channel = 2'b01; 
            2'b10: channel = 2'b10;
            default: channel = 2'b00;
        endcase
    end

    // Ultra-simple state machine
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            busy <= 0;
            err <= 0;
            parity_mode <= 0;
            calc_parity <= 0;
        end
        else begin
            case (state)
            IDLE: begin
                busy <= 0;
                if (packet_valid) begin
                    header <= datain;
                    length <= datain[5:2]; // Packet length from header
                    calc_parity <= datain;
                    state <= LOAD;
                    busy <= 1;
                    parity_mode <= 0;
                end
            end
            
            LOAD: begin
                if (packet_valid) begin
                    // Write to selected FIFO if not full
                    case (channel)
                        2'b00: if (count_0 < 4) begin
                            fifo_0[wr_ptr_0] <= datain;
                            wr_ptr_0 <= wr_ptr_0 + 1;
                            count_0 <= count_0 + 1;
                        end
                        2'b01: if (count_1 < 4) begin
                            fifo_1[wr_ptr_1] <= datain;
                            wr_ptr_1 <= wr_ptr_1 + 1;
                            count_1 <= count_1 + 1;
                        end
                        2'b10: if (count_2 < 4) begin
                            fifo_2[wr_ptr_2] <= datain;
                            wr_ptr_2 <= wr_ptr_2 + 1;
                            count_2 <= count_2 + 1;
                        end
                    endcase
                    
                    if (!parity_mode) begin
                        calc_parity <= calc_parity ^ datain;
                        if (length == 1)
                            parity_mode <= 1; // Next byte is parity
                        else
                            length <= length - 1;
                    end
                    else begin
                        recv_parity <= datain;
                        state <= CHECK;
                    end
                end
                else begin
                    state <= IDLE; // Packet ended unexpectedly
                end
            end
            
            CHECK: begin
                err <= (calc_parity != recv_parity);
                state <= IDLE;
            end
            endcase
        end
    end

    // FIFO read logic - simplified
    always @(posedge clk) begin
        if (!resetn) begin
            rd_ptr_0 <= 0; rd_ptr_1 <= 0; rd_ptr_2 <= 0;
            count_0 <= 0; count_1 <= 0; count_2 <= 0;
        end
        else begin
            // Channel 0
            if (read_enb[0] && count_0 > 0) begin
                rd_ptr_0 <= rd_ptr_0 + 1;
                count_0 <= count_0 - 1;
            end
            // Channel 1  
            if (read_enb[1] && count_1 > 0) begin
                rd_ptr_1 <= rd_ptr_1 + 1;
                count_1 <= count_1 - 1;
            end
            // Channel 2
            if (read_enb[2] && count_2 > 0) begin
                rd_ptr_2 <= rd_ptr_2 + 1;
                count_2 <= count_2 - 1;
            end
        end
    end

    // Output assignments
    assign data_out_0 = (count_0 > 0) ? fifo_0[rd_ptr_0] : 8'h00;
    assign data_out_1 = (count_1 > 0) ? fifo_1[rd_ptr_1] : 8'h00;
    assign data_out_2 = (count_2 > 0) ? fifo_2[rd_ptr_2] : 8'h00;
    
    assign vldout[0] = (count_0 > 0);
    assign vldout[1] = (count_1 > 0);
    assign vldout[2] = (count_2 > 0);

endmodule
