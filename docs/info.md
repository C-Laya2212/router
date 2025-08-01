# 3-Port Packet Router

## How it works

This project implements a 3-port packet router optimized for TinyTapeout's area constraints. The router processes incoming packets and routes them to one of three output channels based on the destination address in the packet header.

### Architecture Overview

The router consists of several key components:

**Packet Processing Engine:**
- 3-state finite state machine (IDLE, LOAD, CHECK)
- Packet format: Header + Data Bytes + Parity
- Header format: `[7:6]` reserved, `[5:2]` length (0-15 bytes), `[1:0]` destination channel (0-2)
- XOR parity checking for error detection

**FIFO Buffers:**
- Three independent 4-deep FIFOs (one per output channel)
- 8-bit data width per FIFO
- Separate read/write pointers with overflow protection
- Valid data indicators for each channel

**Interface Logic:**
- 8-bit input data bus with packet valid signal
- Status outputs: busy, error, and per-channel valid flags
- Read enable inputs for controlled data extraction
- Channel 0 data output accessible via bidirectional pins

### Packet Format

```
Byte 0 (Header): [7:6]=Reserved [5:2]=Length [1:0]=Channel
Byte 1-N: Data bytes (N = length specified in header)
Byte N+1: XOR parity of all previous bytes
```

### Operation Flow

1. **Packet Reception:** Router receives header byte and transitions to LOAD state
2. **Data Loading:** Subsequent data bytes are stored in the appropriate channel FIFO
3. **Parity Check:** Final parity byte is compared against calculated XOR parity
4. **Status Update:** Router updates error flag and returns to IDLE state

The router supports simultaneous packet storage across all three channels and handles back-pressure through FIFO full conditions.

## How to test

### Basic Testing Procedure

1. **Reset the Router:**
   - Assert `rst_n` low for several clock cycles
   - Deassert reset and verify all outputs are zero

2. **Send Test Packets:**
   ```
   Header = 0b00001000  // Length=2, Channel=0
   Data1  = 0xAA
   Data2  = 0x55
   Parity = Header ^ Data1 ^ Data2
   ```

3. **Packet Transmission:**
   - Set `ui_in = {data_byte[7:1], 1'b1}` for each byte (bit 0 = packet_valid)
   - Send header, data bytes, then parity byte on consecutive clock cycles
   - Clear `ui_in` to zero after last byte

4. **Status Monitoring:**
   - Monitor `uo_out[0]` (BUSY) - should be high during packet processing
   - Check `uo_out[1]` (ERROR) - should be low for correct parity
   - Verify `uo_out[4:2]` (CHx_VALID) - appropriate channel should show valid data

5. **Data Readback (Channel 0 only):**
   - Set `uio_in[0] = 1` to enable channel 0 read
   - Read data from `uio_out` while `uo_out[2]` (CH0_VALID) is high
   - Data will automatically advance to next FIFO entry each clock cycle

### Test Scenarios

**Test 1 - Basic Routing:**
- Send packets to each channel (0, 1, 2)
- Verify correct channel valid flags are set
- Confirm no parity errors

**Test 2 - Parity Error Detection:**
- Send packet with intentionally incorrect parity
- Verify ERROR flag is asserted

**Test 3 - Multiple Packets:**
- Send multiple packets to same channel
- Verify FIFO can store up to 4 packets per channel

**Test 4 - All Channels:**
- Send packets to all three channels simultaneously
- Verify independent operation

### Expected Signal Behavior

| Phase | BUSY | ERROR | CH0_VALID | CH1_VALID | CH2_VALID |
|-------|------|-------|-----------|-----------|-----------|
| IDLE  | 0    | 0     | Data dependent | Data dependent | Data dependent |
| LOAD  | 1    | 0     | Data dependent | Data dependent | Data dependent |
| CHECK | 1    | Parity result | Updated | Updated | Updated |

### Pin Mapping Reference

**Input Pins (ui_in):**
- `ui_in[0]`: PKT_VALID - Packet valid signal
- `ui_in[7:0]`: 8-bit data input (note: bit 0 serves dual purpose)

**Output Pins (uo_out):**
- `uo_out[0]`: BUSY status
- `uo_out[1]`: ERROR flag  
- `uo_out[2]`: Channel 0 valid
- `uo_out[3]`: Channel 1 valid
- `uo_out[4]`: Channel 2 valid

**Bidirectional Pins (uio):**
- `uio_in[0:2]`: Read enable for channels 0-2
- `uio_out[7:0]`: Channel 0 data output

## External hardware

This project is entirely self-contained and does not require any external hardware beyond the basic TinyTapeout demo board connections. However, for comprehensive testing and demonstration, the following setup is recommended:

### Recommended Test Setup

**Microcontroller Interface:**
- Any microcontroller with GPIO pins (Arduino, Raspberry Pi, etc.)
- Connect microcontroller GPIO pins to TinyTapeout input pins
- Use microcontroller to generate test packet sequences
- Monitor output pins to verify router operation

**Logic Analyzer (Optional):**
- Connect to input/output pins for signal timing analysis
- Useful for debugging packet timing and state transitions
- Recommended for advanced testing and verification

**LED Indicators (Optional):**
- Connect LEDs to status output pins (`uo_out[4:0]`) through current-limiting resistors
- Provides visual indication of:
  - BUSY status (blinking during packet processing)
  - ERROR status (lights up on parity errors) 
  - Channel valid status (shows which channels have data)

**Oscilloscope (Optional):**
- Monitor clock and data signals
- Verify setup/hold timing requirements
- Analyze packet processing timing

### Connection Requirements

- **Power Supply:** Standard TinyTapeout 3.3V supply
- **Clock:** Use TinyTapeout's provided clock (adjustable frequency)
- **No external components required** - all logic is internal to the FPGA

The router operates entirely with digital logic and requires no analog components, external memory, or special power requirements beyond the standard TinyTapeout environment.
