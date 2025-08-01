# 3-Port Packet Router

## How it works

The 3-Port Packet Router is a digital circuit that routes data packets to one of three output channels based on the destination address embedded in the packet header. It is specifically designed to meet Tiny Tapeout area and IO constraints, using FIFO buffers for temporary storage and a finite state machine (FSM) for control logic.

### Packet Format

- **Header Byte (8 bits):**
  - Bits `[1:0]` – Destination Address (00, 01, 10 → Channel 0, 1, 2)
  - Bits `[5:2]` – Payload length (number of data bytes)
- **Payload Bytes** – Actual data to be transmitted
- **Parity Byte** – XOR of all previous bytes (header + data), used for error detection

### Architecture

The architecture is divided into four key blocks:

1. **Router Top Module (`router_top`):**  
   - Interfaces with IO pins and manages the overall data flow.
   - Controls signal routing between input logic and output FIFOs.

2. **Finite State Machine (`router_fsm`):**  
   - Controls the state transitions:
     - `IDLE` – Waiting for packet
     - `LOAD` – Receiving data
     - `CHECK` – Parity check and routing
   - Generates control signals like `pkt_valid`, `parity_done`, `fifo_full`, and `error`.

3. **FIFO Buffers (`router_fifo`):**  
   - Three independent 4-depth FIFO buffers (one per channel).
   - Support `write_en`, `read_en`, `empty`, and `full` status flags.
   - Stores packet data temporarily before being read.

4. **Register Block (`router_reg`):**  
   - Stores the current byte being processed.
   - Calculates parity on the fly.

### Parity Check Logic

- Parity is computed cumulatively across header and payload.
- On receiving the final parity byte, it is compared with computed parity.
- If mismatch → `error` flag is set, and packet is dropped.

### Output Channels

- Channel selection is decoded from header bits `[1:0]`.
- Data is written to the appropriate FIFO.
- Each channel has:
  - `CHx_DATA` (output data)
  - `CHx_VALID` (data valid signal)
  - `CHx_READ` (input read signal from user)

## How to test

You can simulate or test the router by sending a well-formatted packet and checking the correct output channel.

### Testing Procedure

1. **Reset:**  
   - Assert `rst_n = 0` for a few clock cycles, then set to `1`.

2. **Send Packet:**  
   - Provide 1 byte per clock cycle on `ui_in[7:0]`.
   - Assert `ui_in[0] = 1` (packet valid) for all except the parity byte.

3. **Observe:**
   - `uo_out[0] = BUSY` signal is high during processing.
   - `uo_out[1] = ERROR` is high if parity fails.
   - `uo_out[4:2] = CH2_VALID, CH1_VALID, CH0_VALID`
   - `uio_out[7:0]` will have data when the respective FIFO is read.

4. **Read FIFO:**
   - Set corresponding `uio_in[x] = 1` to read from channel x (0 to 2).
   - Data will be available on `uio_out`.

### Example Packet

| Byte         | Value     | Description                    |
|--------------|-----------|--------------------------------|
| Header       | 0b00001000 | Length = 2, Channel = 0       |
| Payload[0]   | 0xAA      | Data byte 1                    |
| Payload[1]   | 0x55      | Data byte 2                    |
| Parity Byte  | 0xFD      | XOR of all previous bytes      |

## External hardware

No external hardware is required.

### Optional Tools for Demo:

- LED indicators for channel valid and error signals
- Logic analyzer to observe internal behavior
- Microcontroller or Raspberry Pi to feed input packets

## Design Theory

The design implements a simplified version of a **Network-on-Chip (NoC) style router**. This small-scale router mimics the real-world routers used in multi-core processors to handle inter-processor communication efficiently.

- **Routing Mechanism:** Based on static destination decoding
- **Data Integrity:** Ensured through parity checking
- **Scalability:** Modular FIFO-based architecture can be extended to more ports
- **Throughput:** Processes one byte per clock cycle

The core goal is to efficiently direct packets from a single source to one of three destinations, with minimal latency and hardware cost—ideal for silicon-constrained applications like the Tiny Tapeout platform.
