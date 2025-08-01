# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    
    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    
    dut._log.info("Test project behavior")
    
    # Test 1: Check initial state after reset
    dut._log.info("Test 1: Initial state check")
    await ClockCycles(dut.clk, 1)
    
    # After reset, router should be idle (busy=0, err=0, vldout=000)
    # uo_out format: {3'b000, vldout[2:0], err, busy}
    expected_initial = 0b00000000  # All zeros
    assert dut.uo_out.value == expected_initial, f"Expected initial state 0x{expected_initial:02X}, got 0x{dut.uo_out.value:02X}"
    dut._log.info("✅ Initial state correct")
    
    # Test 2: Send packet to channel 0
    dut._log.info("Test 2: Send packet to channel 0")
    
    # Create packet: Header + Data + Parity
    # Header format: [5:2]=length, [1:0]=channel
    header = 0b00001000  # length=2, channel=0
    data1 = 0xAA
    data2 = 0x55
    parity = header ^ data1 ^ data2
    
    # Send header with packet_valid=1 (bit 0 of ui_in)
    dut.ui_in.value = header | 0x01  # Set packet_valid
    await ClockCycles(dut.clk, 1)
    
    # Router should now be busy
    assert (dut.uo_out.value & 0x01) == 1, "Router should be busy after receiving header"
    dut._log.info("✅ Router is busy")
    
    # Send first data byte
    dut.ui_in.value = data1 | 0x01
    await ClockCycles(dut.clk, 1)
    
    # Send second data byte
    dut.ui_in.value = data2 | 0x01
    await ClockCycles(dut.clk, 1)
    
    # Send parity byte
    dut.ui_in.value = parity | 0x01
    await ClockCycles(dut.clk, 1)
    
    # Clear packet_valid
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Wait for router to become idle
    for i in range(20):
        if (dut.uo_out.value & 0x01) == 0:  # busy bit cleared
            break
        await ClockCycles(dut.clk, 1)
    
    # Check if channel 0 has valid data and no error
    # uo_out[2] should be 1 (vldout[0]), uo_out[1] should be 0 (no error)
    expected_after_packet = 0b00000100  # vldout[0]=1, err=0, busy=0
    assert (dut.uo_out.value & 0x07) == 0x04, f"Expected channel 0 valid, got uo_out=0x{dut.uo_out.value:02X}"
    assert (dut.uo_out.value & 0x02) == 0, "No parity error should occur"
    dut._log.info("✅ Packet successfully routed to channel 0")
    
    # Test 3: Send packet to channel 1
    dut._log.info("Test 3: Send packet to channel 1")
    
    header = 0b00000101  # length=1, channel=1
    data1 = 0x33
    parity = header ^ data1
    
    # Send complete packet
    dut.ui_in.value = header | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = data1 | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = parity | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Wait for idle
    for i in range(20):
        if (dut.uo_out.value & 0x01) == 0:
            break
        await ClockCycles(dut.clk, 1)
    
    # Check if channel 1 has valid data (uo_out[3] should be 1)
    assert (dut.uo_out.value & 0x08) != 0, f"Channel 1 should have valid data, got uo_out=0x{dut.uo_out.value:02X}"
    dut._log.info("✅ Packet successfully routed to channel 1")
    
    # Test 4: Send packet to channel 2
    dut._log.info("Test 4: Send packet to channel 2")
    
    header = 0b00000110  # length=1, channel=2
    data1 = 0xFF
    parity = header ^ data1
    
    dut.ui_in.value = header | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = data1 | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = parity | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Wait for idle
    for i in range(20):
        if (dut.uo_out.value & 0x01) == 0:
            break
        await ClockCycles(dut.clk, 1)
    
    # Check if channel 2 has valid data (uo_out[4] should be 1)
    assert (dut.uo_out.value & 0x10) != 0, f"Channel 2 should have valid data, got uo_out=0x{dut.uo_out.value:02X}"
    dut._log.info("✅ Packet successfully routed to channel 2")
    
    # Test 5: Test parity error detection
    dut._log.info("Test 5: Test parity error detection")
    
    header = 0b00000100  # length=1, channel=0
    data1 = 0x42
    wrong_parity = 0xFF  # Intentionally wrong parity
    
    dut.ui_in.value = header | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = data1 | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = wrong_parity | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Wait for idle
    for i in range(20):
        if (dut.uo_out.value & 0x01) == 0:
            break
        await ClockCycles(dut.clk, 1)
    
    # Check if error is detected (uo_out[1] should be 1)
    assert (dut.uo_out.value & 0x02) != 0, f"Parity error should be detected, got uo_out=0x{dut.uo_out.value:02X}"
    dut._log.info("✅ Parity error correctly detected")
    
    # Test 6: Test reading from channel 0 (only accessible channel)
    dut._log.info("Test 6: Test reading from channel 0")
    
    # First, send a fresh packet to channel 0
    header = 0b00000100  # length=1, channel=0
    data1 = 0x77
    parity = header ^ data1
    
    dut.ui_in.value = header | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = data1 | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = parity | 0x01
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Wait for idle
    for i in range(20):
        if (dut.uo_out.value & 0x01) == 0:
            break
        await ClockCycles(dut.clk, 1)
    
    # Enable read from channel 0 using uio_in[0]
    dut.uio_in.value = 0x01  # read_enb[0] = 1
    await ClockCycles(dut.clk, 1)
    
    # Check if data is available on uio_out (should be the data byte we sent)
    if (dut.uo_out.value & 0x04) != 0:  # vldout[0] = 1
        read_data = dut.uio_out.value
        dut._log.info(f"✅ Read data from channel 0: 0x{read_data:02X}")
        
        # Give one more clock cycle to pop the FIFO
        await ClockCycles(dut.clk, 1)
    
    # Disable read
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 1)
    
    # Test 7: Test multiple packets to same channel
    dut._log.info("Test 7: Test multiple packets to same channel")
    
    # Send 3 small packets to channel 0
    for i in range(3):
        header = 0b00000100  # length=1, channel=0
        data1 = 0x10 + i
        parity = header ^ data1
        
        dut.ui_in.value = header | 0x01
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = data1 | 0x01
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = parity | 0x01
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 2)
    
    # Wait for all packets to be processed
    for i in range(30):
        if (dut.uo_out.value & 0x01) == 0:
            break
        await ClockCycles(dut.clk, 1)
    
    # Channel 0 should still have valid data
    assert (dut.uo_out.value & 0x04) != 0, "Channel 0 should have valid data after multiple packets"
    dut._log.info("✅ Multiple packets successfully stored")
    
    # Test 8: Final status check
    dut._log.info("Test 8: Final status check")
    
    await ClockCycles(dut.clk, 5)
    
    # Extract final status
    final_status = dut.uo_out.value
    busy = final_status & 0x01
    err = (final_status >> 1) & 0x01
    vldout = (final_status >> 2) & 0x07
    
    dut._log.info(f"Final status - Busy: {busy}, Error: {err}, Valid channels: {vldout:03b}")
    
    # Router should not be busy at the end
    assert busy == 0, "Router should be idle at end of test"
    
    # Should have valid data in at least channel 0
    assert (vldout & 0x01) != 0, "Channel 0 should have valid data"
    
    dut._log.info("✅ All tests passed!")
    dut._log.info("🎉 3-Port Router is working correctly and ready for TinyTapeout!")
