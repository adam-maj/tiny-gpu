import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.binary import BinaryValue

async def reset(dut):
    dut.block_dim = 8
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

@cocotb.test()
async def test_register_reset(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # After reset, all registers except read-only should be 0
    for i in range(13):
        dut.decoded_rs_address.value = i
        await RisingEdge(dut.clk)
        assert dut.rs.value == 0, f"Register {i} not reset correctly"

    # Check read-only registers for correct initialization
    dut.decoded_rs_address.value = 13
    await RisingEdge(dut.clk)
    assert dut.rs.value == dut.BLOCK_ID.value, "BLOCK_ID register not initialized correctly"
    
    dut.decoded_rs_address.value = 14
    await RisingEdge(dut.clk)
    assert dut.rs.value == 8, "block_dim register not initialized correctly"
    
    dut.decoded_rs_address.value = 15
    await RisingEdge(dut.clk)
    assert dut.rs.value == dut.THREAD_ID.value, "THREAD_ID register not initialized correctly"

@cocotb.test()
async def test_register_write_and_read(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Test writing and then reading for each writable register
    for i in range(13):  # Only registers 0-12 are writable
        test_value = i + 1
        dut.decoded_rd_address.value = i
        dut.decoded_rs_address.value = i
        dut.decoded_reg_write_enable.value = 1
        dut.rd.value = test_value
        await RisingEdge(dut.clk)
        dut.decoded_reg_write_enable.value = 0
        await RisingEdge(dut.clk)
        assert dut.rs.value == test_value, f"Register {i} did not store {test_value} correctly. Received {dut.rs.value} instead."

@cocotb.test()
async def test_block_dim_update(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Update block_dim and check if register 14 updates accordingly
    new_block_dim = 16
    dut.block_dim = new_block_dim
    await RisingEdge(dut.clk)
    dut.decoded_rs_address.value = 14
    await RisingEdge(dut.clk)
    assert dut.rs.value == new_block_dim, f"block_dim register did not update to {new_block_dim}"

@cocotb.test()
async def test_reset_behavior(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Verify that after a reset, all writable registers are set to 0
    for i in range(13):  # Only registers 0-12 are writable
        dut.decoded_rs_address.value = i
        await RisingEdge(dut.clk)
        assert dut.rs.value == 0, f"Register {i} was not reset to 0"

    # Verify read-only registers are set to their specific values after reset
    dut.decoded_rs_address.value = 13
    await RisingEdge(dut.clk)
    assert dut.rs.value == dut.BLOCK_ID.value, "BLOCK_ID register not reset correctly"

    dut.decoded_rs_address.value = 14
    await RisingEdge(dut.clk)
    assert dut.rs.value == 8, "block_dim register not reset correctly"  # Initial block_dim is 8

    dut.decoded_rs_address.value = 15
    await RisingEdge(dut.clk)
    assert dut.rs.value == dut.THREAD_ID.value, "THREAD_ID register not reset correctly"
