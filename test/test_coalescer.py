"""
Test for Memory Coalescing Unit

Tests that the coalescing unit correctly combines adjacent memory
requests from multiple threads into fewer memory transactions.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


@cocotb.test()
async def test_single_read(dut):
    """Test a single thread read request."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.thread_read_valid.value = 0
    dut.thread_write_valid.value = 0
    dut.mem_read_ready.value = 0
    dut.mem_write_ready.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Issue single read from thread 0
    dut.thread_read_valid.value = 0b0001
    dut.thread_read_address[0].value = 0x10
    await RisingEdge(dut.clk)
    dut.thread_read_valid.value = 0

    # Wait for memory request
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.mem_read_valid.value == 1:
            break

    assert dut.mem_read_valid.value == 1, "Memory read should be issued"
    dut._log.info(f"Read address: 0x{int(dut.mem_read_address.value):02X}")

    # Provide memory response
    dut.mem_read_data.value = 0xAB
    dut.mem_read_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_read_ready.value = 0

    # Wait for result distribution
    for _ in range(5):
        await RisingEdge(dut.clk)
        if dut.thread_read_ready.value & 0x1:
            break

    assert dut.thread_read_ready.value & 0x1, "Thread 0 should receive result"
    assert int(dut.thread_read_data[0].value) == 0xAB, "Thread 0 should get correct data"

    dut._log.info("Single read test passed")


@cocotb.test()
async def test_coalesced_same_address(dut):
    """Test that multiple threads reading the same address are coalesced."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Issue reads from all 4 threads to same address
    dut.thread_read_valid.value = 0b1111
    dut.thread_read_address[0].value = 0x20
    dut.thread_read_address[1].value = 0x20
    dut.thread_read_address[2].value = 0x20
    dut.thread_read_address[3].value = 0x20
    await RisingEdge(dut.clk)
    dut.thread_read_valid.value = 0

    # Count memory requests (should only be 1)
    mem_requests = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        if dut.mem_read_valid.value == 1:
            mem_requests += 1
            dut._log.info(f"Memory request #{mem_requests} to address 0x{int(dut.mem_read_address.value):02X}")
            
            # Provide response
            dut.mem_read_data.value = 0xCD
            dut.mem_read_ready.value = 1
            await RisingEdge(dut.clk)
            dut.mem_read_ready.value = 0
            break

    # Wait for distribution
    await ClockCycles(dut.clk, 5)

    dut._log.info(f"Total memory requests: {mem_requests}")
    assert mem_requests == 1, f"Expected 1 coalesced request, got {mem_requests}"

    dut._log.info("Coalesced same-address test passed")


@cocotb.test()
async def test_single_write(dut):
    """Test a single thread write request."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Issue write from thread 0
    dut.thread_write_valid.value = 0b0001
    dut.thread_write_address[0].value = 0x30
    dut.thread_write_data[0].value = 0xEF
    await RisingEdge(dut.clk)
    dut.thread_write_valid.value = 0

    # Wait for memory request
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.mem_write_valid.value == 1:
            break

    assert dut.mem_write_valid.value == 1, "Memory write should be issued"
    assert int(dut.mem_write_address.value) == 0x30, "Write address should match"
    assert int(dut.mem_write_data.value) == 0xEF, "Write data should match"

    # Provide write acknowledgment
    dut.mem_write_ready.value = 1
    await RisingEdge(dut.clk)
    dut.mem_write_ready.value = 0

    # Wait for completion
    for _ in range(5):
        await RisingEdge(dut.clk)
        if dut.thread_write_ready.value & 0x1:
            break

    assert dut.thread_write_ready.value & 0x1, "Thread 0 should receive completion"

    dut._log.info("Single write test passed")


@cocotb.test()
async def test_different_addresses(dut):
    """Test that different addresses result in separate requests."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Issue reads to different addresses (different alignment blocks)
    dut.thread_read_valid.value = 0b0011
    dut.thread_read_address[0].value = 0x00  # Block 0
    dut.thread_read_address[1].value = 0x10  # Block 4 (different)
    await RisingEdge(dut.clk)
    dut.thread_read_valid.value = 0

    # Count memory requests (should be 2 for different blocks)
    mem_requests = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        if dut.mem_read_valid.value == 1:
            mem_requests += 1
            dut._log.info(f"Memory request #{mem_requests}")
            
            # Provide response
            dut.mem_read_data.value = 0x11 * mem_requests
            dut.mem_read_ready.value = 1
            await RisingEdge(dut.clk)
            dut.mem_read_ready.value = 0
            
            if mem_requests >= 2:
                break

    dut._log.info(f"Total memory requests for different addresses: {mem_requests}")
    # With alignment=4, addresses 0x00 and 0x10 are in different blocks
    assert mem_requests == 2, f"Expected 2 requests for different blocks, got {mem_requests}"

    dut._log.info("Different addresses test passed")
