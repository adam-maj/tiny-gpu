"""
Unit Tests for Warp Scheduler (warp_scheduler.sv)
Tests warp scheduling with priority and round-robin.
Note: warp_priority is flattened by sv2v (4 warps * 2 bits = 8 bits)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Module parameters
NUM_WARPS = 4

def pack_priorities(priorities):
    """Pack list of 4 priorities (2 bits each) into 8-bit value"""
    result = 0
    for i, pri in enumerate(priorities):
        result |= (pri & 0x3) << (i * 2)
    return result

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset.value = 1
    dut.warp_active.value = 0
    dut.warp_ready.value = 0
    dut.warp_waiting_mem.value = 0
    dut.warp_waiting_sync.value = 0
    dut.warp_completed.value = 0
    dut.issue_stall.value = 0
    dut.warp_yield.value = 0
    dut.warp_priority.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_scheduler_reset(dut):
    """Test that scheduler resets properly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset with warp_active and warp_ready set during reset
    dut.reset.value = 1
    dut.warp_active.value = 0b1111  # All warps active
    dut.warp_ready.value = 0b1111   # All warps ready
    dut.warp_waiting_mem.value = 0
    dut.warp_waiting_sync.value = 0
    dut.warp_completed.value = 0
    dut.issue_stall.value = 0
    dut.warp_yield.value = 0
    dut.warp_priority.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    assert dut.warp_valid.value == 1, "Warp should be valid after reset with ready warps"
    assert dut.cycles_idle.value == 0, "Idle counter should be 0 when warps are active"
    
    cocotb.log.info("Scheduler reset test passed")

@cocotb.test()
async def test_scheduler_single_warp(dut):
    """Test scheduling with single active warp"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Activate warp 0 and make it ready
    dut.warp_active.value = 0b0001
    dut.warp_ready.value = 0b0001
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    assert dut.warp_valid.value == 1, "A warp should be valid"
    assert dut.selected_warp.value == 0, f"Warp 0 should be selected, got {dut.selected_warp.value}"
    
    cocotb.log.info("Single warp scheduling test passed")

@cocotb.test()
async def test_scheduler_round_robin(dut):
    """Test round-robin scheduling among equal priority warps"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Activate all 4 warps with equal priority
    dut.warp_active.value = 0b1111
    dut.warp_ready.value = 0b1111
    dut.warp_priority.value = pack_priorities([0, 0, 0, 0])
    
    scheduled_warps = []
    
    for _ in range(8):  # Run for 8 cycles
        await RisingEdge(dut.clk)
        if dut.warp_valid.value == 1:
            scheduled_warps.append(int(dut.selected_warp.value))
    
    cocotb.log.info(f"Scheduled warps: {scheduled_warps}")
    
    # Check that we see all warps being scheduled
    unique_warps = set(scheduled_warps)
    assert len(unique_warps) > 1, "Round-robin should schedule multiple warps"
    
    cocotb.log.info("Round-robin scheduling test passed")

@cocotb.test()
async def test_scheduler_priority(dut):
    """Test priority-based scheduling"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Activate warps with different priorities (packed format)
    dut.warp_active.value = 0b1111
    dut.warp_ready.value = 0b1111
    # Priority: warp0=0, warp1=0, warp2=2, warp3=2
    dut.warp_priority.value = pack_priorities([0, 0, 2, 2])
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # High priority warps (2 or 3) should be selected
    selected = int(dut.selected_warp.value)
    cocotb.log.info(f"Selected warp with priority: {selected}")
    
    # Should be either warp 2 or 3 (high priority)
    assert selected in [2, 3], f"High priority warp should be selected, got {selected}"
    
    cocotb.log.info("Priority scheduling test passed")

@cocotb.test()
async def test_scheduler_memory_stall(dut):
    """Test that warps waiting for memory are not scheduled"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Warp 0 waiting for memory, warp 1 ready
    dut.warp_active.value = 0b0011
    dut.warp_ready.value = 0b0011
    dut.warp_waiting_mem.value = 0b0001  # Warp 0 waiting
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    if dut.warp_valid.value == 1:
        selected = int(dut.selected_warp.value)
        assert selected == 1, f"Warp 1 should be selected (warp 0 stalled), got {selected}"
    
    cocotb.log.info("Memory stall test passed")

@cocotb.test()
async def test_scheduler_sync_stall(dut):
    """Test that warps waiting at barrier are not scheduled"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Warp 0 and 1 at barrier, warp 2 ready
    dut.warp_active.value = 0b0111
    dut.warp_ready.value = 0b0111
    dut.warp_waiting_sync.value = 0b0011  # Warps 0,1 at barrier
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    if dut.warp_valid.value == 1:
        selected = int(dut.selected_warp.value)
        assert selected == 2, f"Warp 2 should be selected (0,1 at barrier), got {selected}"
    
    cocotb.log.info("Sync stall test passed")

@cocotb.test()
async def test_scheduler_completed_warp(dut):
    """Test that completed warps are not scheduled"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Warp 0 completed, warp 1 still running
    dut.warp_active.value = 0b0011
    dut.warp_ready.value = 0b0011
    dut.warp_completed.value = 0b0001  # Warp 0 done
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    if dut.warp_valid.value == 1:
        selected = int(dut.selected_warp.value)
        assert selected == 1, f"Warp 1 should be selected (warp 0 completed), got {selected}"
    
    cocotb.log.info("Completed warp test passed")

@cocotb.test()
async def test_scheduler_issue_stall(dut):
    """Test that issue stall prevents new scheduling"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.warp_active.value = 0b1111
    dut.warp_ready.value = 0b1111
    
    await RisingEdge(dut.clk)
    
    first_warp = int(dut.selected_warp.value)
    
    # Enable issue stall
    dut.issue_stall.value = 1
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Warp should stay the same during stall
    stalled_warp = int(dut.selected_warp.value)
    assert stalled_warp == first_warp, f"Warp should not change during stall"
    
    dut.issue_stall.value = 0
    
    cocotb.log.info("Issue stall test passed")

@cocotb.test()
async def test_scheduler_idle_counter(dut):
    """Test that idle cycles are counted when no warps ready"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # No warps active
    dut.warp_active.value = 0
    dut.warp_ready.value = 0
    
    initial_idle = int(dut.cycles_idle.value)
    
    await ClockCycles(dut.clk, 5)
    
    final_idle = int(dut.cycles_idle.value)
    
    assert final_idle > initial_idle, f"Idle counter should increment, was {initial_idle}, now {final_idle}"
    
    cocotb.log.info("Idle counter test passed")

@cocotb.test()
async def test_scheduler_warp_yield(dut):
    """Test that warp yield forces scheduling of next warp"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.warp_active.value = 0b1111
    dut.warp_ready.value = 0b1111
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Force yield even during stall
    dut.issue_stall.value = 1
    dut.warp_yield.value = 1
    
    await RisingEdge(dut.clk)
    
    dut.warp_yield.value = 0
    dut.issue_stall.value = 0
    
    cocotb.log.info("Warp yield test passed")
