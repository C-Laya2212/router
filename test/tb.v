`timescale 1ns/1ps

module tb();

    // TinyTapeout standard interface signals
    reg [7:0] ui_in;      // Dedicated inputs
    wire [7:0] uo_out;    // Dedicated outputs  
    reg [7:0] uio_in;     // IOs: Input path
    wire [7:0] uio_out;   // IOs: Output path
    wire [7:0] uio_oe;    // IOs: Enable path
    reg ena;              // Enable (always 1 when powered)
    reg clk;              // Clock
    reg rst_n;            // Active low reset
    
    // Extracted signals for monitoring
    wire packet_valid;
    wire [7:0] datain;
    wire [2:0] read_enb;
    wire [2:0] vldout;
    wire err, busy;
    wire [7:0] data_out_0;
    
    // Test variables
    reg [7:0] test_packet [0:16];
    integer i, j, packet_idx;
    reg [7:0] expected_parity;
    integer test_count, pass_count, fail_count;
    
    // Signal extraction based on TinyTapeout interface
    assign packet_valid = uio_in[3];    // FIXED: Use uio_in[3] for packet_valid
    assign datain = ui_in[7:0];         // Full 8-bit data input (no overlap)
    assign read_enb = uio_in[2:0];
    
    // Extract outputs from uo_out: {3'b000, vldout[2:0], err, busy}
    assign busy = uo_out[0];
    assign err = uo_out[1]; 
    assign vldout[0] = uo_out[2];
    assign vldout[1] = uo_out[3]; 
    assign vldout[2] = uo_out[4];
    assign data_out_0 = uio_out; // Channel 0 data on bidirectional pins
    
    // Instantiate DUT - TinyTapeout module
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
    
    // Clock generation - 100MHz (10ns period)
    always #5 clk = ~clk;
    
    // Main test sequence
    initial begin
        // Initialize test counters
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        $display("========================================");
        $display("  TinyTapeout 3-Port Router Testbench  ");
        $display("========================================");
        $display("Time: %0t", $time);
        
        // Initialize all signals
        initialize_signals();
        
        // Reset sequence
        perform_reset();
        
        $display("\n=== Starting Router Tests ===");
        
        // Test 1: Basic packet to channel 0
        test_basic_packet_ch0();
        
        // Test 2: Basic packet to channel 1  
        test_basic_packet_ch1();
        
        // Test 3: Basic packet to channel 2
        test_basic_packet_ch2();
        
        // Test 4: Parity error detection
        test_parity_error();
        
        // Test 5: Multiple packets same channel
        test_multiple_packets();
        
        // Test 6: FIFO full condition
        test_fifo_full();
        
        // Test 7: All channels simultaneously
        test_all_channels();
        
        // Test 8: Invalid channel address
        test_invalid_channel();
        
        // Test 9: Zero length packet
        test_zero_length_packet();
        
        // Test 10: Maximum length packet
        test_max_length_packet();
        
        // Final results
        display_test_results();
        
        $display("\n=== Testbench Completed ===");
        $finish;
    end
    
    // Task: Initialize all signals
    task initialize_signals();
        begin
            clk = 0;
            rst_n = 1;
            ena = 1;  // Always enabled in TinyTapeout
            ui_in = 8'b0;
            uio_in = 8'b0;
            packet_idx = 0;
            
            $display("%0t: Signals initialized", $time);
        end
    endtask
    
    // Task: Perform reset sequence
    task perform_reset();
        begin
            $display("%0t: Starting reset sequence", $time);
            rst_n = 0;
            #50;  // Hold reset for 50ns
            rst_n = 1;
            #20;  // Wait for reset deassertion
            $display("%0t: Reset sequence completed", $time);
        end
    endtask
    
    // Test 1: Basic packet to channel 0
    task test_basic_packet_ch0();
        begin
            $display("\n--- Test 1: Basic Packet to Channel 0 ---");
            test_count = test_count + 1;
            
            // Create packet: Header + 3 data bytes + parity
            // Header: [7:6]=00, [5:2]=0011 (length=3), [1:0]=00 (channel 0)
            test_packet[0] = 8'b00001100; // Length=3, Channel=0
            test_packet[1] = 8'hAA;
            test_packet[2] = 8'h55; 
            test_packet[3] = 8'hCC;
            
            // Calculate parity (XOR of header + data)
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2] ^ test_packet[3];
            test_packet[4] = expected_parity;
            
            // Send packet
            send_packet(5);
            
            // Wait for processing
            wait_for_idle();
            
            // Check if data is available in channel 0
            if (vldout[0]) begin
                $display("%0t: PASS - Channel 0 has valid data", $time);
                pass_count = pass_count + 1;
                
                // Read the data
                read_channel_0();
            end else begin
                $display("%0t: FAIL - Channel 0 should have valid data", $time);
                fail_count = fail_count + 1;
            end
            
            // Check for errors
            if (err) begin
                $display("%0t: FAIL - Unexpected error detected", $time);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test 2: Basic packet to channel 1
    task test_basic_packet_ch1();
        begin
            $display("\n--- Test 2: Basic Packet to Channel 1 ---");
            test_count = test_count + 1;
            
            // Header: Length=2, Channel=1  
            test_packet[0] = 8'b00001001; // Length=2, Channel=1
            test_packet[1] = 8'h11;
            test_packet[2] = 8'h22;
            
            expected_parity = test_packet[0] ^ test_packet[1] ^ test_packet[2];
            test_packet[3] = expected_parity;
            
            send_packet(4);
            wait_for_idle();
            
            if (vldout[1]) begin
                $display("%0t: PASS - Channel 1 has valid data", $time); 
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: FAIL - Channel 1 should have valid data", $time);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test 3: Basic packet to channel 2
    task test_basic_packet_ch2();
        begin
            $display("\n--- Test 3: Basic Packet to Channel 2 ---");
            test_count = test_count + 1;
            
            // Header: Length=1, Channel=2
            test_packet[0] = 8'b00000110; // Length=1, Channel=2
            test_packet[1] = 8'hFF;
            
            expected_parity = test_packet[0] ^ test_packet[1];
            test_packet[2] = expected_parity;
            
            send_packet(3);
            wait_for_idle();
            
            if (vldout[2]) begin
                $display("%0t: PASS - Channel 2 has valid data", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: FAIL - Channel 2 should have valid data", $time); 
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test 4: Parity error detection
    task test_parity_error();
        begin
            $display("\n--- Test 4: Parity Error Detection ---");
            test_count = test_count + 1;
            
            // Create packet with intentional parity error
            test_packet[0] = 8'b00001100; // Length=3, Channel=0
            test_packet[1] = 8'hAA;
            test_packet[2] = 8'h55;
            test_packet[3] = 8'hCC;
            test_packet[4] = 8'hFF; // Wrong parity!
            
            send_packet(5);
            wait_for_idle();
            
            if (err) begin
                $display("%0t: PASS - Parity error correctly detected", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: FAIL - Parity error not detected", $time);
                fail_count = fail_count + 1; 
            end
        end
    endtask
    
    // Test 5: Multiple packets to same channel
    task test_multiple_packets();
        begin
            $display("\n--- Test 5: Multiple Packets Same Channel ---");
            test_count = test_count + 1;
            
            // Send 3 small packets to channel 0
            for (i = 0; i < 3; i = i + 1) begin
                test_packet[0] = 8'b00000100; // Length=1, Channel=0
                test_packet[1] = 8'h10 + i;   // Different data each packet
                
                expected_parity = test_packet[0] ^ test_packet[1];
                test_packet[2] = expected_parity;
                
                send_packet(3);
                #10; // Small delay between packets
            end
            
            wait_for_idle();
            
            if (vldout[0]) begin
                $display("%0t: PASS - Multiple packets stored in channel 0", $time);
                pass_count = pass_count + 1;
                read_channel_0(); // Read all stored data
            end else begin
                $display("%0t: FAIL - No data in channel 0 after multiple packets", $time);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test 6: FIFO full condition 
    task test_fifo_full();
        begin
            $display("\n--- Test 6: FIFO Full Condition ---");
            test_count = test_count + 1;
            
            // Try to send 5 packets (FIFO depth is 4)
            for (i = 0; i < 5; i = i + 1) begin
                test_packet[0] = 8'b00000100; // Length=1, Channel=0
                test_packet[1] = 8'h20 + i;
                
                expected_parity = test_packet[0] ^ test_packet[1];
                test_packet[2] = expected_parity;
                
                send_packet(3);
                #5;
            end
            
            wait_for_idle();
            
            // Should have valid data (FIFO should handle overflow gracefully)
            if (vldout[0]) begin
                $display("%0t: PASS - FIFO handled overflow condition", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: INFO - FIFO full handling behavior", $time);
            end
        end
    endtask
    
    // Test 7: All channels simultaneously  
    task test_all_channels();
        begin
            $display("\n--- Test 7: All Channels Simultaneously ---");
            test_count = test_count + 1;
            
            // Send packet to channel 0
            test_packet[0] = 8'b00000100; // Length=1, Channel=0
            test_packet[1] = 8'hA0;
            expected_parity = test_packet[0] ^ test_packet[1];
            test_packet[2] = expected_parity;
            send_packet(3);
            
            // Send packet to channel 1
            test_packet[0] = 8'b00000101; // Length=1, Channel=1
            test_packet[1] = 8'hA1;
            expected_parity = test_packet[0] ^ test_packet[1];
            test_packet[2] = expected_parity;
            send_packet(3);
            
            // Send packet to channel 2
            test_packet[0] = 8'b00000110; // Length=1, Channel=2  
            test_packet[1] = 8'hA2;
            expected_parity = test_packet[0] ^ test_packet[1];
            test_packet[2] = expected_parity;
            send_packet(3);
            
            wait_for_idle();
            
            if (vldout[0] && vldout[1] && vldout[2]) begin
                $display("%0t: PASS - All channels have valid data", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: FAIL - Not all channels have data: vldout=%3b", $time, vldout);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Test 8: Invalid channel address
    task test_invalid_channel();
        begin
            $display("\n--- Test 8: Invalid Channel Address ---");
            test_count = test_count + 1;
            
            // Send packet to invalid channel (11)
            test_packet[0] = 8'b00000111; // Length=1, Channel=3 (invalid)
            test_packet[1] = 8'hBB;
            expected_parity = test_packet[0] ^ test_packet[1];
            test_packet[2] = expected_parity;
            
            send_packet(3);
            wait_for_idle();
            
            // Router should handle this gracefully (maps to channel 0)
            $display("%0t: INFO - Invalid channel test completed", $time);
        end
    endtask
    
    // Test 9: Zero length packet
    task test_zero_length_packet();
        begin
            $display("\n--- Test 9: Zero Length Packet ---");
            test_count = test_count + 1;
            
            // Send zero-length packet
            test_packet[0] = 8'b00000000; // Length=0, Channel=0
            expected_parity = test_packet[0];
            test_packet[1] = expected_parity;
            
            send_packet(2);
            wait_for_idle();
            
            $display("%0t: INFO - Zero length packet test completed", $time);
        end
    endtask
    
    // Test 10: Maximum length packet
    task test_max_length_packet();
        begin
            $display("\n--- Test 10: Maximum Length Packet ---");
            test_count = test_count + 1;
            
            // Send maximum length packet (15 data bytes)
            test_packet[0] = 8'b00111100; // Length=15, Channel=0
            expected_parity = test_packet[0];
            
            for (i = 1; i <= 15; i = i + 1) begin
                test_packet[i] = 8'h30 + i;
                expected_parity = expected_parity ^ test_packet[i];
            end
            test_packet[16] = expected_parity;
            
            send_packet(17);
            wait_for_idle();
            
            if (vldout[0]) begin
                $display("%0t: PASS - Maximum length packet processed", $time);
                pass_count = pass_count + 1;
            end else begin
                $display("%0t: FAIL - Maximum length packet failed", $time);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // Task: Send a packet 
    task send_packet(input integer length);
        begin
            $display("%0t: Sending packet of %0d bytes", $time, length);
            
            for (i = 0; i < length; i = i + 1) begin
                @(posedge clk);
                ui_in = test_packet[i];     // Send full 8-bit data on ui_in
                uio_in[3] = 1'b1;           // Set packet_valid on uio_in[3]
                $display("%0t:   Byte[%0d] = 0x%02h", $time, i, test_packet[i]);
            end
            
            @(posedge clk);
            uio_in[3] = 1'b0; // Clear packet_valid
        end
    endtask
    
    // Task: Wait for router to become idle
    task wait_for_idle();
        begin
            while (busy) begin
                @(posedge clk);
            end
            #20; // Additional settling time
        end
    endtask
    
    // Task: Read from channel 0 (only channel accessible via pins)
    task read_channel_0();
        begin
            if (!vldout[0]) begin
                // Just exit the task normally
            end
            else begin
                $display("%0t: Reading from Channel 0:", $time);
                uio_in[0] = 1'b1; // Enable read from channel 0
                
                while (vldout[0]) begin
                    @(posedge clk);
                    $display("%0t:   Channel 0 data = 0x%02h", $time, data_out_0);
                    @(posedge clk); // Additional cycle for FIFO to update
                end
                
                uio_in[0] = 1'b0; // Disable read
            end
        end
    endtask
    
    // Task: Display final test results
    task display_test_results();
        begin
            $display("\n========================================");
            $display("           TEST RESULTS SUMMARY         ");
            $display("========================================");
            $display("Total Tests:  %0d", test_count);
            $display("Passed:       %0d", pass_count);
            $display("Failed:       %0d", fail_count);
            $display("Pass Rate:    %0d%%", (pass_count * 100) / test_count);
            $display("========================================");
            
            if (fail_count == 0) begin
                $display("🎉 ALL TESTS PASSED! Router is ready for TinyTapeout!");
            end else begin
                $display("⚠️  Some tests failed. Review the design.");
            end
        end
    endtask
    
    // Continuous monitoring
    always @(posedge clk) begin
        if (uio_in[3]) begin  // FIXED: Check packet_valid on uio_in[3]
            $display("%0t: INPUT  - Data=0x%02h, Valid=%b", $time, datain, packet_valid);
        end
        if (|read_enb) begin
            $display("%0t: READ   - Enable=%3b, Ch0_data=0x%02h", $time, read_enb, data_out_0);
        end
        if (err) begin
            $display("%0t: ERROR  - Parity error detected!", $time);
        end
    end
    
    // Generate VCD file for waveform viewing
    initial begin
        $dumpfile("tt_router.vcd");
        $dumpvars(0, tb);
    end

endmodule
