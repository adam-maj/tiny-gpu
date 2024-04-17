import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.binary import BinaryValue

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

async def setup(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

@cocotb.test()
async def test_initial_state(dut):
    await setup(dut)

    # Check initial state is IDLE
    assert dut.state.value == BinaryValue("00"), "Initial state should be IDLE"

@cocotb.test()
async def test_warp_addition(dut):
    await setup(dut)

    # Start the warps
    dut.start.value = 1
    await ClockCycles(dut.clk, 2)

    # Check if state has moved to FETCHING
    assert dut.state.value == BinaryValue("01"), "State should be FETCHING after start"

    # Simulate instruction ready for a warp
    dut.instruction_ready.value = 1
    await ClockCycles(dut.clk, 2)

    # Check if state has moved to PROCESSING
    assert dut.state.value == BinaryValue("10"), "State should be PROCESSING after instruction ready"