# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_router(dut):
    dut._log.info("Router begins")
    cocotb.start_soon(Clock(dut.clk, 10, units="us").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    for ch in [0,1,2]:
        dut._log.info(f"Testing channel {ch}")
        L = ch + 1
        header = ((L & 0xF) << 2) | ch
        data = [0xA0 + ch, 0xB0 + ch]
        parity = header ^ data[0] ^ data[1]
        for b in [header, data[0], data[1], parity]:
            dut.ui_in.value = b | 0x01
            await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 2)
        await ClockCycles(dut.clk, 5)
        cp = int(dut.uo_out.value)
        assert ((cp >> (2+ch)) & 1) == 1, f"Channel {ch} valid missing"
        assert ((cp & 2) == 0), "Parity error"
    dut._log.info("All channel tests passed")
