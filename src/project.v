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
    
    // Input mapping to match test.py protocol
    wire packet_valid = ui_in[0];          // ui[0] for packet valid
    wire [7:0] datain = {ui_in[7:1], 1'b0};             // Full 8-bit data input (test sends data+valid together)
    
    // Read enables from uio_in (only when used as inputs)
    wire [2:0] read_enb = uio_in[2:0];     // uio[2:0] for read enables
    
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
    
    // Output mapping to match test.py expectations
    assign uo_out = {3'b000, vldout[2], vldout[1], vldout[0], err, busy};
    
    // Channel 0 data output on uio_out (full 8 bits available for data)
    assign uio_out = data_out_0; // Full channel 0 data
    assign uio_oe = 8'b11111000; // uio[7:3] as outputs, uio[2:0] as inputs for read enables
    
    // Unused signal to prevent warnings
    wire _unused = &{ena, uio_in[7:3], data_out_1, data_out_2, 1'b0};

endmodule

// Ultra-compact 3-channel router - FIXED VERSION
module router_ultra_compact(
    input clk, resetn, packet_valid,
    input [2:0] read_enb,
    input [7:0] datain, 
    output [2:0] vldout,
    output reg err, busy,
    output [7:0] data_out_0, data_out_1, data_out_2
);

    // Minimal state machine - 3 states
    reg [1:0] state;
    localparam IDLE = 2'b00, LOAD = 2'b01, CHECK = 2'b10;
    
    // Ultra-small FIFOs - depth 4
    reg [7:0] fifo_0 [0:3], fifo_1 [0:3], fifo_2 [0:3];
    reg [1:0] wr_ptr_0, wr_ptr_1, wr_ptr_2;
    reg [1:0] rd_ptr_0, rd_ptr_1, rd_ptr_2;
    reg [2:0] count_0, count_1, count_2;
    
    // Registers for packet processing
    reg [7:0] header;
    reg [1:0] dest_channel;
    reg [3:0] bytes_remaining;
    reg [7:0] calc_parity, recv_parity;
    reg expecting_parity;

    // Channel decode from address bits [1:0]
    always @(*) begin
        dest_channel = header[1:0];
    end

    // Variables for FIFO write control
    reg write_fifo_0, write_fifo_1, write_fifo_2;
    reg [7:0] write_data;

    // FIFO write logic separated from main state machine
    always @(*) begin
        write_fifo_0 = 1'b0;
        write_fifo_1 = 1'b0;
        write_fifo_2 = 1'b0;
        write_data = datain;
        
        if (state == LOAD && packet_valid && !expecting_parity) begin
            case (dest_channel)
                2'b00: write_fifo_0 = (count_0 < 4);
                2'b01: write_fifo_1 = (count_1 < 4);
                2'b10: write_fifo_2 = (count_2 < 4);
                default: begin
                    // Invalid channel
                end
            endcase
        end
    end

    // Main state machine
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            busy <= 1'b0;
            err <= 1'b0;
            expecting_parity <= 1'b0;
            calc_parity <= 8'h00;
            bytes_remaining <= 4'h0;
            header <= 8'h00;
        end
        else begin
            case (state)
            IDLE: begin
                busy <= 1'b0;
                err <= 1'b0;
                if (packet_valid) begin
                    header <= datain;
                    bytes_remaining <= datain[5:2]; // Extract length from header
                    calc_parity <= datain;
                    state <= LOAD;
                    busy <= 1'b1;
                    expecting_parity <= 1'b0;
                end
            end
            
            LOAD: begin
                if (packet_valid) begin
                    if (!expecting_parity) begin
                        calc_parity <= calc_parity ^ datain;
                        
                        if (bytes_remaining == 1) begin
                            expecting_parity <= 1'b1; // Next byte should be parity
                        end else begin
                            bytes_remaining <= bytes_remaining - 1;
                        end
                    end
                    else begin
                        // This is the parity byte
                        recv_parity <= datain;
                        state <= CHECK;
                    end
                end
                else begin
                    // Packet ended unexpectedly
                    state <= IDLE;
                    err <= 1'b1;
                end
            end
            
            CHECK: begin
                err <= (calc_parity != recv_parity);
                state <= IDLE;
            end
            
            default: state <= IDLE;
            endcase
        end
    end

    // FIFO management
    always @(posedge clk) begin
        if (!resetn) begin
            // Initialize all pointers and counters
            wr_ptr_0 <= 2'b00;
            wr_ptr_1 <= 2'b00;
            wr_ptr_2 <= 2'b00;
            rd_ptr_0 <= 2'b00; 
            rd_ptr_1 <= 2'b00; 
            rd_ptr_2 <= 2'b00;
            count_0 <= 3'b000; 
            count_1 <= 3'b000; 
            count_2 <= 3'b000;
            
            // Initialize FIFO contents to prevent X states
            fifo_0[0] <= 8'h00; fifo_0[1] <= 8'h00; fifo_0[2] <= 8'h00; fifo_0[3] <= 8'h00;
            fifo_1[0] <= 8'h00; fifo_1[1] <= 8'h00; fifo_1[2] <= 8'h00; fifo_1[3] <= 8'h00;
            fifo_2[0] <= 8'h00; fifo_2[1] <= 8'h00; fifo_2[2] <= 8'h00; fifo_2[3] <= 8'h00;
        end
        else begin
            // FIFO 0 operations
            if (write_fifo_0 && read_enb[0] && count_0 > 0) begin
                // Simultaneous read and write
                fifo_0[wr_ptr_0] <= write_data;
                wr_ptr_0 <= wr_ptr_0 + 1;
                rd_ptr_0 <= rd_ptr_0 + 1;
                // count stays the same
            end
            else if (write_fifo_0) begin
                // Write only
                fifo_0[wr_ptr_0] <= write_data;
                wr_ptr_0 <= wr_ptr_0 + 1;
                count_0 <= count_0 + 1;
            end
            else if (read_enb[0] && count_0 > 0) begin
                // Read only
                rd_ptr_0 <= rd_ptr_0 + 1;
                count_0 <= count_0 - 1;
            end
            
            // FIFO 1 operations
            if (write_fifo_1 && read_enb[1] && count_1 > 0) begin
                // Simultaneous read and write
                fifo_1[wr_ptr_1] <= write_data;
                wr_ptr_1 <= wr_ptr_1 + 1;
                rd_ptr_1 <= rd_ptr_1 + 1;
                // count stays the same
            end
            else if (write_fifo_1) begin
                // Write only
                fifo_1[wr_ptr_1] <= write_data;
                wr_ptr_1 <= wr_ptr_1 + 1;
                count_1 <= count_1 + 1;
            end
            else if (read_enb[1] && count_1 > 0) begin
                // Read only
                rd_ptr_1 <= rd_ptr_1 + 1;
                count_1 <= count_1 - 1;
            end
            
            // FIFO 2 operations
            if (write_fifo_2 && read_enb[2] && count_2 > 0) begin
                // Simultaneous read and write
                fifo_2[wr_ptr_2] <= write_data;
                wr_ptr_2 <= wr_ptr_2 + 1;
                rd_ptr_2 <= rd_ptr_2 + 1;
                // count stays the same  
            end
            else if (write_fifo_2) begin
                // Write only
                fifo_2[wr_ptr_2] <= write_data;
                wr_ptr_2 <= wr_ptr_2 + 1;
                count_2 <= count_2 + 1;
            end
            else if (read_enb[2] && count_2 > 0) begin
                // Read only
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
