# 3-Channel Router with FIFO and Error Detection

## How it works

This project implements a sophisticated 3-channel packet router designed for network-on-chip (NoC) applications. The router receives data packets, analyzes their destination addresses, and forwards them to the appropriate output channels while maintaining data integrity through parity checking.

### Core Architecture

The router consists of five main components working together:

**1. Router Register (router_reg)**
- Manages packet data flow and parity calculation
- Stores incoming packet headers and payload data
- Generates internal parity for error detection
- Controls data output timing to FIFOs

**2. Finite State Machine (router_fsm)**
- Controls the overall packet processing workflow
- Manages eight distinct states: decode_address, wait_till_empty, load_first_data, load_data, load_parity, fifo_full_state, load_after_full, and check_parity_error
- Generates control signals for other modules
- Handles busy status and flow control

**3. Synchronization Module (router_sync)**
- Manages FIFO write enables based on destination address
- Generates soft reset signals after 30 clock cycles of inactivity
- Provides valid output signals for each channel
- Handles address decoding for proper channel selection

**4. FIFO Modules (router_fifo x3)**
- Three independent 16-deep FIFO buffers (one per channel)
- 9-bit wide storage (8 data bits + 1 header indicator bit)
- Implements circular buffer with read/write pointers
- Provides full/empty status flags
- Supports soft reset functionality

**5. Top-level Integration (router_top)**
- Connects all sub-modules with proper signal routing
- Instantiates three FIFO channels using generate blocks
- Manages global control signals and data paths

### Packet Format

The router processes packets with the following structure:
- **Header Byte**: `[7:2]` = Payload length (1-63 bytes), `[1:0]` = Destination address (00, 01, 10)
- **Payload Data**: Variable length data bytes (1-63 bytes)
- **Parity Byte**: XOR of all previous bytes for error detection

### Operation Flow

1. **Packet Reception**: When `packet_valid` is asserted, the router begins receiving packet data
2. **Address Decode**: The header byte is analyzed to determine destination channel (0, 1, or 2)
3. **FIFO Check**: Router verifies if target FIFO has space available
4. **Data Transfer**: Payload bytes are written to the appropriate FIFO buffer
5. **Parity Verification**: Calculated parity is compared with received parity byte
6. **Output Generation**: Valid data becomes available on the target channel
7. **Error Handling**: Parity mismatches trigger error flag assertion

### Error Detection and Recovery

- **Parity Error**: Detected when calculated XOR doesn't match received parity
- **Soft Reset**: Automatically triggered after 30 clock cycles of channel inactivity
- **FIFO Overflow**: Handled through busy signal and flow control mechanisms
- **Invalid Address**: Packets with undefined addresses (11) are discarded

## How to test

### Basic Functionality Test

1. **Setup Phase**:
   - Apply reset (`rst_n = 0`) for at least 10 clock cycles
   - Release reset (`rst_n = 1`) and wait for stabilization
   - Ensure `ena = 1` (always required for operation)

2. **Send Test Packet**:
   ```
   Clock 1: ui_in = 8'b00000100 (header: length=4, addr=00), packet_valid=1
   Clock 2: ui_in = 8'b10101010 (data byte 1), packet_valid=1  
   Clock 3: ui_in = 8'b01010101 (data byte 2), packet_valid=1
   Clock 4: ui_in = 8'b11001100 (data byte 3), packet_valid=1
   Clock 5: ui_in = 8'b00110011 (data byte 4), packet_valid=1
   Clock 6: ui_in = 8'b[parity]0 (parity byte), packet_valid=0
   Clock 7: ui_in = 8'b00000000 (clear inputs)
   ```

3. **Monitor Status**:
   - Watch `uo_out[0]` for channel 0 valid output assertion
   - Check `uio_out[6]` for busy status during processing
   - Monitor `uio_out[7]` for any parity errors

4. **Read Data**:
   - Assert `uio_in[0] = 1` to enable reading from channel 0
   - Data appears on `uio_out[5:0]` (6 bits available due to pin constraints)
   - Continue reading while `uo_out[0] = 1`
   - Deassert `uio_in[0] = 0` when finished

### Multi-Channel Test

Test all three channels by sending packets with different addresses:
- Address `00`: Data appears on channel 0 (`uo_out[0]`, read via `uio_in[0]`)
- Address `01`: Data appears on channel 1 (`uo_out[1]`, read via `uio_in[1]`)  
- Address `10`: Data appears on channel 2 (`uo_out[2]`, read via `uio_in[2]`)

### Error Testing

1. **Parity Error Test**:
   - Send packet with intentionally incorrect parity byte
   - Verify `uio_out[7] = 1` (error flag asserted)

2. **Soft Reset Test**:
   - Send packet and don't read from output channel
   - Wait 30+ clock cycles without asserting read enable
   - Observe automatic channel reset

3. **Invalid Address Test**:
   - Send packet with address `11` 
   - Verify packet is discarded (no valid outputs asserted)

### Signal Monitoring

Key signals to monitor during testing:
- `uo_out[2:0]`: Valid output flags for channels 2, 1, 0
- `uio_out[7]`: Error flag (parity mismatch detected)
- `uio_out[6]`: Busy flag (router processing packet)
- `uio_out[5:0]`: Data output from channel 0 (when reading)

### Timing Considerations

- Allow 2-3 clock cycles for packet processing after transmission
- FIFO read operations require one clock cycle per byte
- Soft reset timeout occurs after exactly 30 clock cycles
- Parity checking completes within 2 clock cycles of packet end

## External hardware

This project is designed to operate entirely within the Tiny Tapeout ASIC and does not require any external hardware components. All functionality is implemented using the standard digital I/O pins provided by the Tiny Tapeout platform.

### Pin Usage Summary

**Input Pins (ui[7:0])**:
- No external drivers required
- Can be connected to logic analyzer, microcontroller, or test equipment
- Standard 3.3V CMOS logic levels

**Output Pins (uo[7:0])**:
- Can drive LEDs through current-limiting resistors (typical 330Ω-1kΩ)
- Compatible with logic analyzer probes for monitoring
- 3.3V CMOS output levels

**Bidirectional Pins (uio[7:0])**:
- Configured as outputs for status signals (busy, error)
- Configured as inputs for read enable controls
- No external pull-up/pull-down resistors required

### Optional Test Equipment

While not required for basic operation, the following equipment can enhance testing:

1. **Logic Analyzer**: For capturing and analyzing packet timing and data flow
2. **Function Generator**: For generating test packet sequences
3. **Oscilloscope**: For observing signal timing relationships
4. **Microcontroller Board**: For automated test sequence generation
5. **LEDs + Resistors**: For visual indication of channel activity and error status

### Power Requirements

- Standard Tiny Tapeout power supply (typically 3.3V)
- Low power consumption suitable for battery operation
- No external power supplies required

The router design is fully self-contained and can be tested using only the standard Tiny Tapeout development environment and basic digital test equipment.
