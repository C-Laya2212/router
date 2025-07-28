`timescale 1ns/1ps

module tb_tt_um_example();

    // Testbench signals
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg ena;
    reg clk;
    reg rst_n;
    
    // Internal signals for easier monitoring
    wire packet_valid;
    wire [7:0] datain;
    wire read_enb_0, read_enb_1, read_enb_2;
    wire vldout_0, vldout_1, vldout_2;
    wire err, busy;
    wire [7:0] data_out_0, data_out_1, data_out_2;
    
    // Test variables
    reg [7:0] test_packet [0:20];
    integer i, j, packet_length;
    reg [7:0] expected_parity;
    
    // Extract signals for monitoring
    assign packet_valid = ui_in[0];
    assign datain = ui_in[7:0];
    assign read_enb_0 = uio_in[0];
    assign read_enb_1 = uio_in[1];
    assign read_enb_2 = uio_in[2];
    assign vldout_0 = uo_out[0];
    assign vldout_1 = uo_out[1];
    assign vldout_2 = uo_out[2];
    assign err = uio_out[7];
    assign busy = uio_out[6];
    assign data_out_0 = {2'b00, uio_out[5:0]}; // Only lower 6 bits available in wrapper
    
    // Instantiate DUT
    tt_um_example dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Initialize signals
    initial begin
        clk = 0;
        rst_n = 0;
        ena = 1;
        ui_in = 8'b0;
        uio_in = 8'b0;
        
        // Reset sequence
        #20 rst_n = 1;
        #10;
        
        $display("========== Router Testbench Started ==========");
        $display("Time\t\tState\t\tOperation");
        $display("----\t\t-----\t\t---------");
        
        // Test 1: Send packet to channel 0
        test_packet_to_channel_0();
        #50;
        
        // Test 2: Send packet to channel 1
        test_packet_to_channel_1();
        #50;
        
        // Test 3: Send packet to channel 2
        test_packet_to_channel_2();
        #50;
        
        // Test 4: Test parity error
        test_parity_error();
        #50;
        
        // Test 5: Test FIFO full condition
        test_fifo_full();
        #100;
        
        // Test 6: Test soft reset (timeout)
        test_soft_reset();
        #200;
        
        // Test 7: Test invalid address
        test_invalid_address();
        #50;
        
        $display("\n========== All Tests Completed ==========");
        $finish;
    end
    
    // Task to send a packet to channel 0
    task test_packet_to_channel_0();
        begin
            $display("\n=== Test 1: Packet to Channel 0 ===");
            
            // Create test packet: Header + Data + Parity
            test_packet[0] = 8'b00000100; // Header: length=4, address=00
            test_packet[1] = 8'hAA;       // Data 1
            test_packet[2] = 8'h55;       // Data 2
            test_packet[3] = 8'hCC;       // Data 3
            test_packet[4] = 8'h33;       // Data 4
            
            // Calculate parity
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3] ^ test_packet[4];
            test_packet[5] = expected_parity;
            
            // Send packet
            send_packet(6);
            
            // Read from channel 0
            #20;
            read_from_channel(0);
        end
    endtask
    
    // Task to send a packet to channel 1
    task test_packet_to_channel_1();
        begin
            $display("\n=== Test 2: Packet to Channel 1 ===");
            
            // Create test packet
            test_packet[0] = 8'b00001001; // Header: length=4, address=01
            test_packet[1] = 8'h11;
            test_packet[2] = 8'h22;
            test_packet[3] = 8'h44;
            test_packet[4] = 8'h88;
            
            // Calculate parity
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3] ^ test_packet[4];
            test_packet[5] = expected_parity;
            
            // Send packet
            send_packet(6);
            
            // Read from channel 1
            #20;
            read_from_channel(1);
        end
    endtask
    
    // Task to send a packet to channel 2
    task test_packet_to_channel_2();
        begin
            $display("\n=== Test 3: Packet to Channel 2 ===");
            
            // Create test packet
            test_packet[0] = 8'b00001010; // Header: length=4, address=10
            test_packet[1] = 8'hFF;
            test_packet[2] = 8'h00;
            test_packet[3] = 8'hAB;
            test_packet[4] = 8'hCD;
            
            // Calculate parity
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3] ^ test_packet[4];
            test_packet[5] = expected_parity;
            
            // Send packet
            send_packet(6);
            
            // Read from channel 2
            #20;
            read_from_channel(2);
        end
    endtask
    
    // Task to test parity error
    task test_parity_error();
        begin
            $display("\n=== Test 4: Parity Error Test ===");
            
            // Create test packet with wrong parity
            test_packet[0] = 8'b00000100; // Header: length=4, address=00
            test_packet[1] = 8'hAA;
            test_packet[2] = 8'h55;
            test_packet[3] = 8'hCC;
            test_packet[4] = 8'h33;
            test_packet[5] = 8'h00;       // Wrong parity (should cause error)
            
            // Send packet
            send_packet(6);
            
            // Wait and check for error
            #30;
            if (err) begin
                $display("%0t: PASS - Parity error detected correctly", $time);
            end else begin
                $display("%0t: FAIL - Parity error not detected", $time);
            end
        end
    endtask
    
    // Task to test FIFO full condition
    task test_fifo_full();
        begin
            $display("\n=== Test 5: FIFO Full Test ===");
            
            // Send multiple packets quickly to fill FIFO
            for (i = 0; i < 3; i = i + 1) begin
                test_packet[0] = 8'b00001000; // Header: length=8, address=00
                for (j = 1; j <= 8; j = j + 1) begin
                    test_packet[j] = 8'h10 + j + i;
                end
                
                // Calculate parity
                expected_parity = 8'h00;
                for (j = 0; j <= 8; j = j + 1) begin
                    expected_parity = expected_parity ^ test_packet[j];
                end
                test_packet[9] = expected_parity;
                
                // Send packet without reading (to fill FIFO)
                send_packet(10);
                #5; // Small delay between packets
            end
            
            // Now read from FIFO
            #20;
            read_from_channel(0);
        end
    endtask
    
    // Task to test soft reset (timeout condition)
    task test_soft_reset();
        begin
            $display("\n=== Test 6: Soft Reset Test ===");
            
            // Send a packet but don't read it for 30 cycles to trigger soft reset
            test_packet[0] = 8'b00000100;
            test_packet[1] = 8'hDE;
            test_packet[2] = 8'hAD;
            test_packet[3] = 8'hBE;
            test_packet[4] = 8'hEF;
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3] ^ test_packet[4];
            test_packet[5] = expected_parity;
            
            send_packet(6);
            
            // Wait for soft reset to occur (30 cycles without read)
            uio_in[2:0] = 3'b000; // No read enables
            #300; // Wait longer than soft reset timeout
            
            $display("%0t: Soft reset timeout test completed", $time);
        end
    endtask
    
    // Task to test invalid address
    task test_invalid_address();
        begin
            $display("\n=== Test 7: Invalid Address Test ===");
            
            // Send packet with invalid address (11)
            test_packet[0] = 8'b00000111; // Header: length=4, address=11 (invalid)
            test_packet[1] = 8'h12;
            test_packet[2] = 8'h34;
            test_packet[3] = 8'h56;
            test_packet[4] = 8'h78;
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3] ^ test_packet[4];
            test_packet[5] = expected_parity;
            
            send_packet(6);
            
            #50;
            $display("%0t: Invalid address test completed", $time);
        end
    endtask
    
    // Task to send a packet
    task send_packet(input integer length);
        begin
            $display("%0t: Sending packet of length %0d", $time, length);
            
            for (i = 0; i < length; i = i + 1) begin
                @(posedge clk);
                ui_in = {test_packet[i][7:1], 1'b1}; // Set packet_valid = 1
                $display("%0t: Sending byte[%0d] = 0x%02h", $time, i, test_packet[i]);
                
                // For last byte, clear packet_valid
                if (i == length - 1) begin
                    @(posedge clk);
                    ui_in = {test_packet[i][7:1], 1'b0}; // Clear packet_valid
                end
            end
            
            @(posedge clk);
            ui_in = 8'b0; // Clear all inputs
        end
    endtask
    
    // Task to read from a specific channel
    task read_from_channel(input integer channel);
        begin
            $display("%0t: Reading from channel %0d", $time, channel);
            
            // Enable read for the specified channel
            case (channel)
                0: uio_in[2:0] = 3'b001;
                1: uio_in[2:0] = 3'b010;
                2: uio_in[2:0] = 3'b100;
                default: uio_in[2:0] = 3'b000;
            endcase
            
            // Wait for valid output
            wait (uo_out[channel] == 1'b1);
            
            // Read data while valid
            while (uo_out[channel] == 1'b1) begin
                @(posedge clk);
                $display("%0t: Channel %0d data = 0x%02h", $time, channel, data_out_0);
            end
            
            // Disable read
            uio_in[2:0] = 3'b000;
            $display("%0t: Finished reading from channel %0d", $time, channel);
        end
    endtask
    
    // Monitor important signals
    initial begin
        $monitor("%0t: busy=%b, err=%b, vld_out={%b,%b,%b}, ui_in=0x%02h, uo_out=0x%02h", 
                 $time, busy, err, vldout_2, vldout_1, vldout_0, ui_in, uo_out);
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("router_tb.vcd");
        $dumpvars(0, tb_tt_um_example);
    end

endmodule
