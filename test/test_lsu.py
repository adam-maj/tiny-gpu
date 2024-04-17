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
async def test_lsu_idle_state(dut):
    await setup(dut)

    # Ensure LSU is in IDLE state initially
    assert dut.lsu_state.value == BinaryValue("00"), "LSU should be in IDLE state on reset"

@cocotb.test()
async def test_lsu_read_operation(dut):
    await setup(dut)

    # Simulate enabling memory read
    dut.decoded_mem_read_enable.value = 1
    dut.rs.value = BinaryValue("0000" + "0001")  # Set source register to simulate address
    await ClockCycles(dut.clk, 2)
    assert dut.mem_read_valid.value == 1, "Memory read should be valid after enabling read"
    assert dut.mem_read_address.value == BinaryValue("0001"), "Memory read address should match RS"

    # Simulate memory read ready
    dut.mem_read_ready.value = 1
    dut.mem_read_data.value = BinaryValue("0011" + "1100")

    await ClockCycles(dut.clk, 2)
    assert dut.lsu_out.value == BinaryValue("0011" + "1100"), "LSU output should match the memory read data"
    
    # Should go back to IDLE
    dut.mem_read_valid.value = 0
    await ClockCycles(dut.clk, 2)
    assert dut.lsu_state.value == 0, "LSU should return to IDLE after read"

@cocotb.test()
async def test_lsu_write_operation(dut):
    await setup(dut)

    # Simulate enabling memory write
    dut.decoded_mem_write_enable.value = 1
    dut.rs.value = BinaryValue("0000" + "0010")  # Set source register to simulate address
    dut.rt.value = BinaryValue("0101" + "1010")  # Set data to write

    await ClockCycles(dut.clk, 2)
    assert dut.mem_write_valid.value == 1, "Memory write should be valid after enabling write"
    assert dut.mem_write_address.value == BinaryValue("0010"), "Memory write address should match RS"
    assert dut.mem_write_data.value == BinaryValue("0101" + "1010"), "Memory write data should match RT"
    assert dut.lsu_state.value == 1, "LSU should be WAITING"

    # Simulate memory write ready
    dut.mem_write_ready.value = 1
    await ClockCycles(dut.clk, 2)
    assert dut.mem_write_valid.value == 0, "LSU should set write valid back to low"
    assert dut.lsu_state.value == 0, "LSU should return to IDLE after write"
