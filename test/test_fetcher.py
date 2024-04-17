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
async def test_fetcher_idle_state(dut):
    await setup(dut)

    # Ensure fetcher is in IDLE state initially
    assert dut.fetcher_state.value == BinaryValue("00"), "Fetcher should be in IDLE state on reset"

@cocotb.test()
async def test_fetcher_fetch_operation(dut):
    await setup(dut)

    # Simulate enabling fetch operation
    dut.fetch_enable.value = 1
    dut.pc.value = BinaryValue("00000001")  # Set program counter
    await ClockCycles(dut.clk, 2)
    assert dut.mem_read_valid.value == 1, "Memory read should be valid after enabling fetch"
    assert dut.mem_read_address.value == BinaryValue("00000001"), "Memory read address should match PC"

    # Simulate memory read ready with data
    dut.mem_read_ready.value = 1
    dut.mem_read_data.value = BinaryValue("00110011" + "11001100")  # Set fetched instruction data

    await ClockCycles(dut.clk, 2)
    assert dut.instruction_ready.value == 1, "Instruction should be ready after memory read"
    assert dut.instruction.value == BinaryValue("00110011" + "11001100"), "Fetched instruction should match the memory read data"

    # Reset fetch enable and check if fetcher returns to IDLE
    dut.fetch_enable.value = 0
    await ClockCycles(dut.clk, 2)
    assert dut.fetcher_state.value == BinaryValue("00"), "Fetcher should return to IDLE after operation"

@cocotb.test()
async def test_fetcher_reset_behavior(dut):
    await setup(dut)

    # Trigger a fetch operation first
    dut.fetch_enable.value = 1
    dut.pc.value = BinaryValue("00000010")
    await ClockCycles(dut.clk, 1)
    dut.fetch_enable.value = 0
    await ClockCycles(dut.clk, 1)

    # Now reset and check if fetcher goes to IDLE state and clears instruction
    await reset(dut)
    assert dut.fetcher_state.value == BinaryValue("00"), "Fetcher should be in IDLE state after reset"
    assert dut.instruction_ready.value == 0, "Instruction ready should be cleared after reset"
    assert dut.instruction.value == BinaryValue("00000000" + "00000000"), "Instruction should be cleared after reset"
