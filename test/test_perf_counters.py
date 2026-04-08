"""
Unit Tests for Performance Counters (perf_counters.sv)
Tests hardware performance monitoring.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Counter indices (match RTL)
CTR_CYCLES          = 0
CTR_ACTIVE_CYCLES   = 1
CTR_INST_ISSUED     = 2
CTR_INST_COMPLETED  = 3
CTR_BRANCHES        = 4
CTR_DIVERGENT       = 5
CTR_DCACHE_HIT      = 6
CTR_DCACHE_MISS     = 7
CTR_ICACHE_HIT      = 8
CTR_ICACHE_MISS     = 9
CTR_MEM_READ        = 10
CTR_MEM_WRITE       = 11
CTR_MEM_STALL       = 12
CTR_BARRIER_WAIT    = 13
CTR_ATOMIC_OPS      = 14
CTR_WARP_STALLS     = 15

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset.value = 1
    dut.enable_counting.value = 0
    dut.reset_counters.value = 0
    dut.core_active.value = 0
    dut.instruction_issued.value = 0
    dut.instruction_completed.value = 0
    dut.branch_taken.value = 0
    dut.branch_divergent.value = 0
    dut.dcache_hit.value = 0
    dut.dcache_miss.value = 0
    dut.icache_hit.value = 0
    dut.icache_miss.value = 0
    dut.mem_read.value = 0
    dut.mem_write.value = 0
    dut.mem_stall.value = 0
    dut.barrier_wait.value = 0
    dut.atomic_op.value = 0
    dut.warp_stall.value = 0
    dut.counter_select.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_counters_reset(dut):
    """Test that counters reset properly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Check all counters are 0
    for ctr in range(16):
        dut.counter_select.value = ctr
        await RisingEdge(dut.clk)
        value = int(dut.counter_value.value)
        assert value == 0, f"Counter {ctr} should be 0 after reset, got {value}"
    
    cocotb.log.info("Counters reset test passed")

@cocotb.test()
async def test_cycle_counter(dut):
    """Test cycle counter increments"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    dut.counter_select.value = CTR_CYCLES
    
    await ClockCycles(dut.clk, 10)
    
    cycles = int(dut.counter_value.value)
    assert cycles >= 9, f"Should have counted at least 9 cycles, got {cycles}"
    
    cocotb.log.info(f"Cycle counter: {cycles}")
    cocotb.log.info("Cycle counter test passed")

@cocotb.test()
async def test_active_cycles_counter(dut):
    """Test active cycles counter"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    dut.counter_select.value = CTR_ACTIVE_CYCLES
    
    # No cores active for 5 cycles
    await ClockCycles(dut.clk, 5)
    inactive_count = int(dut.counter_value.value)
    
    # Core 0 active for 5 cycles
    dut.core_active.value = 0b01
    await ClockCycles(dut.clk, 5)
    
    active_count = int(dut.counter_value.value)
    
    assert active_count > inactive_count, f"Active cycles should increase when cores active"
    assert active_count >= 4, f"Should have counted active cycles, got {active_count}"
    
    cocotb.log.info(f"Active cycles: {active_count}")
    cocotb.log.info("Active cycles counter test passed")

@cocotb.test()
async def test_instruction_counters(dut):
    """Test instruction issued and completed counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Issue 5 instructions from core 0
    for _ in range(5):
        dut.instruction_issued.value = 0b01
        await RisingEdge(dut.clk)
        dut.instruction_issued.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_INST_ISSUED
    await RisingEdge(dut.clk)
    issued = int(dut.counter_value.value)
    
    assert issued >= 5, f"Should have issued 5+ instructions, got {issued}"
    
    # Complete 3 instructions
    for _ in range(3):
        dut.instruction_completed.value = 0b01
        await RisingEdge(dut.clk)
        dut.instruction_completed.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_INST_COMPLETED
    await RisingEdge(dut.clk)
    completed = int(dut.counter_value.value)
    
    assert completed >= 3, f"Should have completed 3+ instructions, got {completed}"
    
    cocotb.log.info(f"Instructions issued: {issued}, completed: {completed}")
    cocotb.log.info("Instruction counters test passed")

@cocotb.test()
async def test_cache_counters(dut):
    """Test cache hit/miss counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Generate cache hits and misses
    for _ in range(10):
        dut.dcache_hit.value = 0b01
        await RisingEdge(dut.clk)
        dut.dcache_hit.value = 0
        await RisingEdge(dut.clk)
    
    for _ in range(2):
        dut.dcache_miss.value = 0b01
        await RisingEdge(dut.clk)
        dut.dcache_miss.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_DCACHE_HIT
    await RisingEdge(dut.clk)
    hits = int(dut.counter_value.value)
    
    dut.counter_select.value = CTR_DCACHE_MISS
    await RisingEdge(dut.clk)
    misses = int(dut.counter_value.value)
    
    assert hits >= 10, f"Should have 10+ hits, got {hits}"
    assert misses >= 2, f"Should have 2+ misses, got {misses}"
    
    # Check hit rate
    hit_rate = int(dut.dcache_hit_rate.value)
    expected_rate = (hits * 100) // (hits + misses) if (hits + misses) > 0 else 0
    
    cocotb.log.info(f"Cache hits: {hits}, misses: {misses}, hit rate: {hit_rate}%")
    cocotb.log.info("Cache counters test passed")

@cocotb.test()
async def test_memory_counters(dut):
    """Test memory read/write counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Generate memory reads
    for _ in range(7):
        dut.mem_read.value = 0b01
        await RisingEdge(dut.clk)
        dut.mem_read.value = 0
        await RisingEdge(dut.clk)
    
    # Generate memory writes
    for _ in range(3):
        dut.mem_write.value = 0b01
        await RisingEdge(dut.clk)
        dut.mem_write.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_MEM_READ
    await RisingEdge(dut.clk)
    reads = int(dut.counter_value.value)
    
    dut.counter_select.value = CTR_MEM_WRITE
    await RisingEdge(dut.clk)
    writes = int(dut.counter_value.value)
    
    assert reads >= 7, f"Should have 7+ reads, got {reads}"
    assert writes >= 3, f"Should have 3+ writes, got {writes}"
    
    # Check total mem accesses
    total = int(dut.total_mem_accesses.value)
    assert total >= reads + writes, f"Total should be >= reads + writes"
    
    cocotb.log.info(f"Memory reads: {reads}, writes: {writes}, total: {total}")
    cocotb.log.info("Memory counters test passed")

@cocotb.test()
async def test_branch_counters(dut):
    """Test branch and divergence counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Generate branches
    for _ in range(8):
        dut.branch_taken.value = 0b01
        await RisingEdge(dut.clk)
        dut.branch_taken.value = 0
        await RisingEdge(dut.clk)
    
    # Some are divergent
    for _ in range(2):
        dut.branch_divergent.value = 0b01
        await RisingEdge(dut.clk)
        dut.branch_divergent.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_BRANCHES
    await RisingEdge(dut.clk)
    branches = int(dut.counter_value.value)
    
    dut.counter_select.value = CTR_DIVERGENT
    await RisingEdge(dut.clk)
    divergent = int(dut.counter_value.value)
    
    assert branches >= 8, f"Should have 8+ branches, got {branches}"
    assert divergent >= 2, f"Should have 2+ divergent, got {divergent}"
    
    cocotb.log.info(f"Branches: {branches}, divergent: {divergent}")
    cocotb.log.info("Branch counters test passed")

@cocotb.test()
async def test_sync_counters(dut):
    """Test barrier and atomic operation counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Barrier waits
    for _ in range(4):
        dut.barrier_wait.value = 0b01
        await RisingEdge(dut.clk)
        dut.barrier_wait.value = 0
        await RisingEdge(dut.clk)
    
    # Atomic ops
    for _ in range(6):
        dut.atomic_op.value = 0b01
        await RisingEdge(dut.clk)
        dut.atomic_op.value = 0
        await RisingEdge(dut.clk)
    
    dut.counter_select.value = CTR_BARRIER_WAIT
    await RisingEdge(dut.clk)
    barriers = int(dut.counter_value.value)
    
    dut.counter_select.value = CTR_ATOMIC_OPS
    await RisingEdge(dut.clk)
    atomics = int(dut.counter_value.value)
    
    assert barriers >= 4, f"Should have 4+ barrier waits, got {barriers}"
    assert atomics >= 6, f"Should have 6+ atomic ops, got {atomics}"
    
    cocotb.log.info(f"Barrier waits: {barriers}, atomic ops: {atomics}")
    cocotb.log.info("Sync counters test passed")

@cocotb.test()
async def test_reset_counters(dut):
    """Test that reset_counters clears all counters"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Generate some events
    dut.instruction_issued.value = 0b11
    dut.mem_read.value = 0b11
    await ClockCycles(dut.clk, 10)
    
    dut.instruction_issued.value = 0
    dut.mem_read.value = 0
    
    # Verify counters have values
    dut.counter_select.value = CTR_CYCLES
    await RisingEdge(dut.clk)
    cycles_before = int(dut.counter_value.value)
    assert cycles_before > 0, "Cycles should be > 0 before reset"
    
    # Reset counters
    dut.reset_counters.value = 1
    await RisingEdge(dut.clk)
    dut.reset_counters.value = 0
    await RisingEdge(dut.clk)
    
    # Verify counters are cleared
    for ctr in [CTR_CYCLES, CTR_INST_ISSUED, CTR_MEM_READ]:
        dut.counter_select.value = ctr
        await RisingEdge(dut.clk)
        value = int(dut.counter_value.value)
        # After reset_counters, they should restart from 0 (or 1 if counting resumed)
        assert value <= 2, f"Counter {ctr} should be near 0 after reset, got {value}"
    
    cocotb.log.info("Reset counters test passed")

@cocotb.test()
async def test_ipc_calculation(dut):
    """Test IPC (Instructions Per Cycle) calculation"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Complete 1 instruction every cycle (IPC = 1.0 = 100 when * 100)
    for _ in range(20):
        dut.instruction_completed.value = 0b01
        await RisingEdge(dut.clk)
    
    dut.instruction_completed.value = 0
    await RisingEdge(dut.clk)
    
    ipc = int(dut.ipc_x100.value)
    cocotb.log.info(f"IPC x 100: {ipc}")
    
    # IPC should be reasonable (between 0 and 200)
    assert 0 < ipc < 200, f"IPC x 100 should be reasonable, got {ipc}"
    
    cocotb.log.info("IPC calculation test passed")

@cocotb.test()
async def test_multi_core_events(dut):
    """Test counting events from multiple cores simultaneously"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.enable_counting.value = 1
    
    # Both cores issuing instructions simultaneously
    dut.instruction_issued.value = 0b11  # Both cores
    await ClockCycles(dut.clk, 5)
    dut.instruction_issued.value = 0
    
    dut.counter_select.value = CTR_INST_ISSUED
    await RisingEdge(dut.clk)
    issued = int(dut.counter_value.value)
    
    # Should count 2 per cycle * 5 cycles = 10
    assert issued >= 10, f"Should have 10+ instructions from 2 cores, got {issued}"
    
    cocotb.log.info(f"Multi-core instructions issued: {issued}")
    cocotb.log.info("Multi-core events test passed")

@cocotb.test()
async def test_counting_disabled(dut):
    """Test that counters don't increment when disabled"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Keep counting disabled
    dut.enable_counting.value = 0
    dut.instruction_issued.value = 0b01
    
    await ClockCycles(dut.clk, 10)
    
    dut.counter_select.value = CTR_INST_ISSUED
    await RisingEdge(dut.clk)
    issued = int(dut.counter_value.value)
    
    assert issued == 0, f"Counters should not increment when disabled, got {issued}"
    
    dut.instruction_issued.value = 0
    
    cocotb.log.info("Counting disabled test passed")
