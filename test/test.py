# test.py
# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_router(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    for ch in range(3):
        L = ch + 1
        header = (L << 2) | ch
        data0 = 0xA0 + ch
        data1 = 0xB0 + ch
        parity = header ^ data0 ^ data1
        for b in [header, data0, data1, parity]:
            dut.ui_in.value = (b | 0x01)
            await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 2)
        await ClockCycles(dut.clk, 5)
        cp = int(dut.uo_out.value)
        assert ((cp >> (2 + ch)) & 1) == 1, f"Channel {ch} valid missing"
        assert (cp & 2) == 0, "Parity error flag set"
    dut._log.info("✅ All channel tests passed")
