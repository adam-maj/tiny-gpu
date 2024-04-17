import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.binary import BinaryValue

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

@cocotb.test()
async def test_pc_increment(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    initial_pc = 0
    dut.current_pc.value = initial_pc
    await RisingEdge(dut.clk)
    assert dut.next_pc.value == initial_pc + 1, f"PC did not increment correctly. Expected {initial_pc + 1}, got {dut.next_pc.value}"

@cocotb.test()
async def test_pc_branch_taken(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # CMP
    dut.nzp_input_data.value = 0b001
    dut.decoded_nzp_write_enable.value = 1
    await RisingEdge(dut.clk)

    # BRnzp
    dut.decoded_nzp_write_enable.value = 0
    dut.decoded_pc_mux.value = 1
    dut.decoded_nzp.value = 0b001
    dut.decoded_immediate.value = 20
    await RisingEdge(dut.clk)
    assert dut.next_pc.value == 20, "PC did not branch to the correct address when branch was taken."

@cocotb.test()
async def test_pc_branch_not_taken(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    initial_pc = 0
    dut.current_pc.value = initial_pc
    dut.nzp_input_data.value = 0b001
    dut.decoded_nzp_write_enable.value = 1
    await RisingEdge(dut.clk)

    dut.decoded_nzp_write_enable.value = 0
    dut.decoded_pc_mux.value = 1
    dut.decoded_nzp.value = 0b100  # Condition for branch not taken
    dut.decoded_immediate.value = 20
    await RisingEdge(dut.clk)
    assert dut.next_pc.value == initial_pc + 1, "PC did not increment correctly when branch was not taken."
