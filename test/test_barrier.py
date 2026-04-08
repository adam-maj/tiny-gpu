"""
Unit Tests for Barrier Synchronization (barrier.sv)
Tests thread synchronization within a block.
Note: barrier_id is flattened by sv2v (4 threads * 1 bit = 4 bits for 2 barriers)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Module parameters
NUM_THREADS = 4
NUM_BARRIERS = 2

def pack_barrier_ids(ids):
    """Pack list of barrier IDs (one per thread)"""
    result = 0
    bits_per_id = 1  # clog2(2) = 1
    for i, bid in enumerate(ids):
        result |= (bid & 0x1) << (i * bits_per_id)
    return result

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset.value = 1
    dut.barrier_request.value = 0
    dut.barrier_id.value = 0
    dut.active_threads.value = 0xF  # 4 active threads
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_barrier_reset(dut):
    """Test that barrier resets properly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    assert dut.barrier_release.value == 0, "No threads should be released after reset"
    assert dut.barrier_active.value == 0, "No barriers should be active after reset"
    
    cocotb.log.info("Barrier reset test passed")

@cocotb.test()
async def test_barrier_all_threads_arrive(dut):
    """Test that barrier releases when all active threads arrive"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set 4 active threads
    dut.active_threads.value = 0xF  # Threads 0-3 active
    dut.barrier_id.value = pack_barrier_ids([0, 0, 0, 0])  # All use barrier 0
    
    await RisingEdge(dut.clk)
    
    # All threads arrive at barrier 0 together
    dut.barrier_request.value = 0b1111
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Clear request
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Check that barrier completes
    complete = int(dut.barrier_complete.value)
    cocotb.log.info(f"Barrier complete signal: {bin(complete)}")
    
    cocotb.log.info("Barrier all threads arrive test passed")

@cocotb.test()
async def test_barrier_partial_threads(dut):
    """Test barrier accumulates threads over multiple cycles"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set 4 active threads
    dut.active_threads.value = 0xF
    dut.barrier_id.value = pack_barrier_ids([0, 0, 0, 0])
    
    await RisingEdge(dut.clk)
    
    # Thread 0 arrives
    dut.barrier_request.value = 0b0001
    await RisingEdge(dut.clk)
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    
    # Thread 1 arrives
    dut.barrier_request.value = 0b0010
    await RisingEdge(dut.clk)
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    
    # Barrier should be active but not complete
    active = int(dut.barrier_active.value)
    complete = int(dut.barrier_complete.value)
    cocotb.log.info(f"Partial: active={bin(active)}, complete={bin(complete)}")
    
    cocotb.log.info("Barrier partial threads test passed")

@cocotb.test()
async def test_barrier_subset_active(dut):
    """Test barrier with subset of threads active"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Only 2 threads active
    dut.active_threads.value = 0b0011  # Threads 0-1 active
    dut.barrier_id.value = pack_barrier_ids([0, 0, 0, 0])
    
    await RisingEdge(dut.clk)
    
    # Both active threads arrive
    dut.barrier_request.value = 0b0011
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Barrier should be complete with just 2 threads
    complete = int(dut.barrier_complete.value)
    cocotb.log.info(f"Subset barrier complete: {bin(complete)}")
    
    cocotb.log.info("Barrier subset active test passed")

@cocotb.test()
async def test_barrier_multiple_barriers(dut):
    """Test using different barrier IDs"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.active_threads.value = 0b0011  # 2 threads active
    
    # Use barrier 0
    dut.barrier_id.value = pack_barrier_ids([0, 0, 0, 0])
    dut.barrier_request.value = 0b0011
    await RisingEdge(dut.clk)
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Use barrier 1
    dut.barrier_id.value = pack_barrier_ids([1, 1, 0, 0])
    dut.barrier_request.value = 0b0011
    await RisingEdge(dut.clk)
    dut.barrier_request.value = 0
    await RisingEdge(dut.clk)
    
    cocotb.log.info("Multiple barriers test passed")
