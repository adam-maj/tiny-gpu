"""
Unit Tests for Atomic Operations Unit (atomic_unit.sv)
Tests atomic read-modify-write operations.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Operation codes (match RTL)
OP_ADD  = 0
OP_MIN  = 1
OP_MAX  = 2
OP_AND  = 3
OP_OR   = 4
OP_XOR  = 5
OP_SWAP = 6
OP_CAS  = 7

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset.value = 1
    dut.request_valid.value = 0
    dut.operation.value = 0
    dut.address.value = 0
    dut.operand.value = 0
    dut.compare_value.value = 0
    dut.mem_read_data.value = 0
    dut.mem_read_ready.value = 0
    dut.mem_write_ready.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

async def do_atomic_op(dut, op, addr, operand, compare=0, mem_value=0):
    """Helper to perform an atomic operation"""
    # Start request
    dut.request_valid.value = 1
    dut.operation.value = op
    dut.address.value = addr
    dut.operand.value = operand
    dut.compare_value.value = compare
    
    await RisingEdge(dut.clk)
    dut.request_valid.value = 0
    
    # Wait for memory read request
    timeout = 0
    while dut.mem_read_valid.value == 0:
        await RisingEdge(dut.clk)
        timeout += 1
        if timeout > 50:
            raise TimeoutError("Timeout waiting for memory read")
    
    # Provide memory data
    dut.mem_read_data.value = mem_value
    dut.mem_read_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_read_ready.value = 0
    
    # Wait for memory write request
    timeout = 0
    while dut.mem_write_valid.value == 0:
        await RisingEdge(dut.clk)
        timeout += 1
        if timeout > 50:
            raise TimeoutError("Timeout waiting for memory write")
    
    written_value = int(dut.mem_write_data.value)
    
    # Complete write
    dut.mem_write_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_write_ready.value = 0
    
    # Wait for completion
    while dut.request_ready.value == 0:
        await RisingEdge(dut.clk)
    
    old_value = int(dut.result.value)
    return old_value, written_value

@cocotb.test()
async def test_atomic_reset(dut):
    """Test that atomic unit resets properly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    assert dut.busy.value == 0, "Unit should not be busy after reset"
    assert dut.request_ready.value == 0, "Request should not be ready after reset"
    
    cocotb.log.info("Atomic reset test passed")

@cocotb.test()
async def test_atomic_add(dut):
    """Test atomic add operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 10, add 5 -> should become 15
    old_val, new_val = await do_atomic_op(dut, OP_ADD, 0x10, 5, mem_value=10)
    
    assert old_val == 10, f"Old value should be 10, got {old_val}"
    assert new_val == 15, f"New value should be 15, got {new_val}"
    
    cocotb.log.info("Atomic add test passed")

@cocotb.test()
async def test_atomic_min(dut):
    """Test atomic min operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 20, min with 15 -> should become 15
    old_val, new_val = await do_atomic_op(dut, OP_MIN, 0x20, 15, mem_value=20)
    
    assert old_val == 20, f"Old value should be 20, got {old_val}"
    assert new_val == 15, f"New value should be 15, got {new_val}"
    
    cocotb.log.info("Atomic min test passed")

@cocotb.test()
async def test_atomic_max(dut):
    """Test atomic max operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 20, max with 25 -> should become 25
    old_val, new_val = await do_atomic_op(dut, OP_MAX, 0x30, 25, mem_value=20)
    
    assert old_val == 20, f"Old value should be 20, got {old_val}"
    assert new_val == 25, f"New value should be 25, got {new_val}"
    
    cocotb.log.info("Atomic max test passed")

@cocotb.test()
async def test_atomic_and(dut):
    """Test atomic AND operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0xFF, AND with 0x0F -> should become 0x0F
    old_val, new_val = await do_atomic_op(dut, OP_AND, 0x40, 0x0F, mem_value=0xFF)
    
    assert old_val == 0xFF, f"Old value should be 0xFF, got {old_val}"
    assert new_val == 0x0F, f"New value should be 0x0F, got {new_val}"
    
    cocotb.log.info("Atomic AND test passed")

@cocotb.test()
async def test_atomic_or(dut):
    """Test atomic OR operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0xF0, OR with 0x0F -> should become 0xFF
    old_val, new_val = await do_atomic_op(dut, OP_OR, 0x50, 0x0F, mem_value=0xF0)
    
    assert old_val == 0xF0, f"Old value should be 0xF0, got {old_val}"
    assert new_val == 0xFF, f"New value should be 0xFF, got {new_val}"
    
    cocotb.log.info("Atomic OR test passed")

@cocotb.test()
async def test_atomic_xor(dut):
    """Test atomic XOR operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0xAA, XOR with 0xFF -> should become 0x55
    old_val, new_val = await do_atomic_op(dut, OP_XOR, 0x60, 0xFF, mem_value=0xAA)
    
    assert old_val == 0xAA, f"Old value should be 0xAA, got {old_val}"
    assert new_val == 0x55, f"New value should be 0x55, got {new_val}"
    
    cocotb.log.info("Atomic XOR test passed")

@cocotb.test()
async def test_atomic_swap(dut):
    """Test atomic swap operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0x12, swap with 0x34 -> should become 0x34
    old_val, new_val = await do_atomic_op(dut, OP_SWAP, 0x70, 0x34, mem_value=0x12)
    
    assert old_val == 0x12, f"Old value should be 0x12, got {old_val}"
    assert new_val == 0x34, f"New value should be 0x34, got {new_val}"
    
    cocotb.log.info("Atomic swap test passed")

@cocotb.test()
async def test_atomic_cas_success(dut):
    """Test atomic compare-and-swap when values match"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0x50, compare with 0x50, swap to 0x60 -> should succeed
    old_val, new_val = await do_atomic_op(dut, OP_CAS, 0x80, 0x60, compare=0x50, mem_value=0x50)
    
    assert old_val == 0x50, f"Old value should be 0x50, got {old_val}"
    assert new_val == 0x60, f"New value should be 0x60 (CAS succeeded), got {new_val}"
    
    cocotb.log.info("Atomic CAS success test passed")

@cocotb.test()
async def test_atomic_cas_failure(dut):
    """Test atomic compare-and-swap when values don't match"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Memory has 0x50, compare with 0x40, swap to 0x60 -> should fail (keep 0x50)
    old_val, new_val = await do_atomic_op(dut, OP_CAS, 0x90, 0x60, compare=0x40, mem_value=0x50)
    
    assert old_val == 0x50, f"Old value should be 0x50, got {old_val}"
    assert new_val == 0x50, f"New value should be 0x50 (CAS failed), got {new_val}"
    
    cocotb.log.info("Atomic CAS failure test passed")

@cocotb.test()
async def test_atomic_busy_flag(dut):
    """Test that busy flag is set during operation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Start a request
    dut.request_valid.value = 1
    dut.operation.value = OP_ADD
    dut.address.value = 0x10
    dut.operand.value = 5
    
    await RisingEdge(dut.clk)
    dut.request_valid.value = 0
    
    await RisingEdge(dut.clk)
    
    # Should be busy now
    assert dut.busy.value == 1, "Unit should be busy during operation"
    
    # Complete the operation
    while dut.mem_read_valid.value == 0:
        await RisingEdge(dut.clk)
    
    dut.mem_read_data.value = 10
    dut.mem_read_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_read_ready.value = 0
    
    while dut.mem_write_valid.value == 0:
        await RisingEdge(dut.clk)
    
    dut.mem_write_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_write_ready.value = 0
    
    while dut.request_ready.value == 0:
        await RisingEdge(dut.clk)
    
    await RisingEdge(dut.clk)
    
    # Should not be busy anymore
    assert dut.busy.value == 0, "Unit should not be busy after completion"
    
    cocotb.log.info("Atomic busy flag test passed")
