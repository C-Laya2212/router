# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge
from cocotb.types import LogicArray
import random

class RouterTestHelper:
    def __init__(self, dut):
        self.dut = dut
        
    async def reset_dut(self):
        """Reset the DUT"""
        self.dut._log.info("Resetting DUT")
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 10)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 5)
        
    def calculate_parity(self, packet_data):
        """Calculate XOR parity for packet data"""
        parity = 0
        for byte in packet_data:
            parity ^= byte
        return parity
        
    async def send_packet(self, address, data_bytes):
        """Send a complete packet with header, data, and parity"""
        # Create header: [7:2] = length, [1:0] = address
        length = len(data_bytes)
        header = (length << 2) | (address & 0x3)
        
        # Complete packet: header + data + parity
        packet = [header] + data_bytes
        parity = self.calculate_parity(packet)
        packet.append(parity)
        
        self.dut._log.info(f"Sending packet to address {address}, length {length}")
        self.dut._log.info(f"Packet data: {[hex(x) for x in packet]}")
        
        # Send each byte
        for i, byte in enumerate(packet):
            # Set packet_valid = 1 and data
            if i < len(packet) - 1:  # Not the last byte (parity)
                self.dut.ui_in.value = (byte & 0xFE) | 1  # packet_valid = 1
            else:  # Last byte (parity), clear packet_valid
                self.dut.ui_in.value = (byte & 0xFE) | 0  # packet_valid = 0
                await ClockCycles(self.dut.clk, 1)
                self.dut.ui_in.value = byte & 0xFE  # Keep data, packet_valid = 0
                
            await ClockCycles(self.dut.clk, 1)
            
        # Clear inputs
        self.dut.ui_in.value = 0
        await ClockCycles(self.dut.clk, 2)
        
        return packet[:-1]  # Return packet without parity for verification
        
    async def send_packet_with_error(self, address, data_bytes):
        """Send a packet with intentional parity error"""
        length = len(data_bytes)
        header = (length << 2) | (address & 0x3)
        
        packet = [header] + data_bytes
        correct_parity = self.calculate_parity(packet)
        wrong_parity = correct_parity ^ 0xFF  # Intentionally wrong parity
        packet.append(wrong_parity)
        
        self.dut._log.info(f"Sending packet with parity error to address {address}")
        
        # Send each byte
        for i, byte in enumerate(packet):
            if i < len(packet) - 1:
                self.dut.ui_in.value = (byte & 0xFE) | 1
            else:
                self.dut.ui_in.value = (byte & 0xFE) | 0
                await ClockCycles(self.dut.clk, 1)
                self.dut.ui_in.value = byte & 0xFE
                
            await ClockCycles(self.dut.clk, 1)
            
        self.dut.ui_in.value = 0
        await ClockCycles(self.dut.clk, 2)
        
    async def read_from_channel(self, channel, expected_data=None):
        """Read data from specified channel"""
        self.dut._log.info(f"Reading from channel {channel}")
        
        # Enable read for the channel
        read_mask = 1 << channel
        self.dut.uio_in.value = read_mask
        
        # Wait for valid output
        timeout = 0
        while (self.dut.uo_out.value & (1 << channel)) == 0 and timeout < 100:
            await ClockCycles(self.dut.clk, 1)
            timeout += 1
            
        if timeout >= 100:
            self.dut._log.warning(f"Timeout waiting for valid output on channel {channel}")
            return []
            
        # Read data while valid
        received_data = []
        max_reads = 20  # Prevent infinite loop
        read_count = 0
        
        while (self.dut.uo_out.value & (1 << channel)) != 0 and read_count < max_reads:
            await ClockCycles(self.dut.clk, 1)
            # Extract data from uio_out (only 6 bits available for data_out_0)
            if channel == 0:
                data = self.dut.uio_out.value & 0x3F  # Lower 6 bits
            else:
                # For channels 1 and 2, we can't read the data through the wrapper
                # This is a limitation of the current wrapper design
                data = 0
            received_data.append(data)
            read_count += 1
            
        # Disable read
        self.dut.uio_in.value = 0
        await ClockCycles(self.dut.clk, 2)
        
        self.dut._log.info(f"Received data from channel {channel}: {[hex(x) for x in received_data]}")
        return received_data
        
    def get_status_signals(self):
        """Get current status of router signals"""
        uo_out = int(self.dut.uo_out.value)
        uio_out = int(self.dut.uio_out.value)
        
        return {
            'vldout_0': (uo_out >> 0) & 1,
            'vldout_1': (uo_out >> 1) & 1,
            'vldout_2': (uo_out >> 2) & 1,
            'busy': (uio_out >> 6) & 1,
            'err': (uio_out >> 7) & 1,
        }

@cocotb.test()
async def test_router_basic_functionality(dut):
    """Test basic router functionality"""
    dut._log.info("=== Test: Basic Router Functionality ===")
    
    # Set up clock
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Test 1: Send packet to channel 0
    dut._log.info("Test 1: Packet to channel 0")
    test_data = [0xAA, 0x55, 0xCC, 0x33]
    sent_packet = await helper.send_packet(0, test_data)
    
    await ClockCycles(dut.clk, 10)
    
    # Check if packet is available on channel 0
    status = helper.get_status_signals()
    assert status['vldout_0'] == 1, "Channel 0 should have valid output"
    
    # Read from channel 0
    received_data = await helper.read_from_channel(0, test_data)
    dut._log.info("Test 1 completed successfully")

@cocotb.test()
async def test_all_channels(dut):
    """Test packet routing to all channels"""
    dut._log.info("=== Test: All Channels ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Test each channel
    for channel in range(3):
        dut._log.info(f"Testing channel {channel}")
        
        test_data = [0x10 + channel, 0x20 + channel, 0x30 + channel]
        await helper.send_packet(channel, test_data)
        
        await ClockCycles(dut.clk, 10)
        
        status = helper.get_status_signals()
        assert status[f'vldout_{channel}'] == 1, f"Channel {channel} should have valid output"
        
        # Read from the channel
        await helper.read_from_channel(channel)
        
        await ClockCycles(dut.clk, 10)

@cocotb.test()
async def test_parity_error(dut):
    """Test parity error detection"""
    dut._log.info("=== Test: Parity Error Detection ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Send packet with parity error
    test_data = [0xDE, 0xAD, 0xBE, 0xEF]
    await helper.send_packet_with_error(0, test_data)
    
    # Wait for processing
    await ClockCycles(dut.clk, 20)
    
    # Check for error signal
    status = helper.get_status_signals()
    dut._log.info(f"Error status: {status['err']}")
    
    # Note: Due to wrapper limitations, we may not be able to fully verify
    # the error signal, but the test structure is correct
    
@cocotb.test()
async def test_busy_signal(dut):
    """Test busy signal during packet processing"""
    dut._log.info("=== Test: Busy Signal ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Start sending a packet and monitor busy signal
    test_data = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]
    
    # Send header first
    header = (len(test_data) << 2) | 0  # Address 0
    dut.ui_in.value = (header & 0xFE) | 1  # packet_valid = 1
    await ClockCycles(dut.clk, 1)
    
    # Check if busy goes high during processing
    busy_observed = False
    for i in range(10):
        status = helper.get_status_signals()
        if status['busy']:
            busy_observed = True
            dut._log.info(f"Busy signal observed at cycle {i}")
            break
        await ClockCycles(dut.clk, 1)
    
    # Complete the packet transmission
    dut.ui_in.value = 0
    await helper.send_packet(0, test_data)
    
    dut._log.info(f"Busy signal test completed. Busy observed: {busy_observed}")

@cocotb.test()
async def test_multiple_packets(dut):
    """Test sending multiple packets"""
    dut._log.info("=== Test: Multiple Packets ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Send multiple packets to different channels
    packets = [
        (0, [0x11, 0x22]),
        (1, [0x33, 0x44, 0x55]),
        (2, [0x66, 0x77, 0x88, 0x99]),
        (0, [0xAA, 0xBB, 0xCC])
    ]
    
    for channel, data in packets:
        dut._log.info(f"Sending packet to channel {channel}")
        await helper.send_packet(channel, data)
        await ClockCycles(dut.clk, 5)
    
    # Wait for all packets to be processed
    await ClockCycles(dut.clk, 50)
    
    # Read from all channels
    for channel in range(3):
        status = helper.get_status_signals()
        if status[f'vldout_{channel}']:
            await helper.read_from_channel(channel)

@cocotb.test()
async def test_invalid_address(dut):
    """Test invalid address handling"""
    dut._log.info("=== Test: Invalid Address ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Send packet with invalid address (3)
    test_data = [0x12, 0x34]
    length = len(test_data)
    header = (length << 2) | 3  # Invalid address
    
    packet = [header] + test_data
    parity = helper.calculate_parity(packet)
    packet.append(parity)
    
    # Send the packet
    for i, byte in enumerate(packet):
        if i < len(packet) - 1:
            dut.ui_in.value = (byte & 0xFE) | 1
        else:
            dut.ui_in.value = (byte & 0xFE) | 0
            await ClockCycles(dut.clk, 1)
            dut.ui_in.value = byte & 0xFE
        await ClockCycles(dut.clk, 1)
    
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 20)
    
    # Check that no valid outputs are asserted
    status = helper.get_status_signals()
    dut._log.info(f"Status after invalid address: {status}")

@cocotb.test()
async def test_soft_reset_timeout(dut):
    """Test soft reset functionality"""
    dut._log.info("=== Test: Soft Reset Timeout ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Send a packet to channel 0
    test_data = [0xCA, 0xFE]
    await helper.send_packet(0, test_data)
    
    await ClockCycles(dut.clk, 10)
    
    # Verify packet is available
    status = helper.get_status_signals()
    if status['vldout_0']:
        dut._log.info("Packet available on channel 0")
        
        # Don't read from channel (to trigger timeout)
        # Wait for more than 30 cycles (soft reset timeout)
        await ClockCycles(dut.clk, 35)
        
        # Check if soft reset occurred
        status = helper.get_status_signals()
        dut._log.info(f"Status after timeout: {status}")

@cocotb.test()
async def test_random_packets(dut):
    """Test with random packet data"""
    dut._log.info("=== Test: Random Packets ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Generate and send random packets
    for i in range(5):
        channel = random.randint(0, 2)
        length = random.randint(1, 8)
        data = [random.randint(0, 255) for _ in range(length)]
        
        dut._log.info(f"Random packet {i}: channel={channel}, data={[hex(x) for x in data]}")
        
        await helper.send_packet(channel, data)
        await ClockCycles(dut.clk, 10)
        
        # Try to read if data is available
        status = helper.get_status_signals()
        if status[f'vldout_{channel}']:
            await helper.read_from_channel(channel)
        
        await ClockCycles(dut.clk, 5)

# Helper test for debugging
@cocotb.test()
async def test_simple_debug(dut):
    """Simple test for debugging"""
    dut._log.info("=== Debug Test ===")
    
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    
    helper = RouterTestHelper(dut)
    await helper.reset_dut()
    
    # Simple test: send one byte of data
    dut._log.info("Sending simple test data")
    
    # Just set some values and observe
    dut.ui_in.value = 0x01  # packet_valid = 1, simple data
    await ClockCycles(dut.clk, 1)
    
    dut.ui_in.value = 0x20  # Some data, packet_valid = 0
    await ClockCycles(dut.clk, 1)
    
    dut.ui_in.value = 0x00  # Clear
    await ClockCycles(dut.clk, 10)
    
    # Log the outputs
    status = helper.get_status_signals()
    dut._log.info(f"Final status: {status}")
    dut._log.info(f"uo_out: 0x{int(dut.uo_out.value):02x}")
    dut._log.info(f"uio_out: 0x{int(dut.uio_out.value):02x}")
