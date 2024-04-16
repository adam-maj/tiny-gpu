import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

async def reset(dut):
    dut.reset.value = 1
    dut.mem_read_enable.value = 0
    dut.mem_read_address.value = 0
    dut.mem_write_enable.value = 0
    dut.mem_write_address.value = 0
    dut.mem_write_data.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0

@cocotb.test()
async def test(dut):
    # Initialize
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Should read memory[0] = 0
    dut.mem_read_enable.value = 1
    dut.mem_read_address.value = 0
    await RisingEdge(dut.clk)
    assert dut.mem_read_data.value == 0

    # Should write memory[0] = 2
    dut.mem_read_enable.value = 0
    dut.mem_write_enable.value = 1
    dut.mem_write_address.value = 0
    dut.mem_write_data.value = 2
    await RisingEdge(dut.clk)

    # Should read memory[0] = 2
    dut.mem_read_enable.value = 1
    dut.mem_write_enable.value = 0
    await RisingEdge(dut.clk)
    assert dut.mem_read_data.value == 2

    # Should reset & read memory[0] = 0
    await reset(dut)
    dut.mem_read_enable.value = 1
    await RisingEdge(dut.clk)
    assert dut.mem_read_data == 0
