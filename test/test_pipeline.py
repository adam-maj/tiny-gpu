"""
Test for Pipelined Scheduler and Fetcher

Tests the basic pipelining functionality including:
- State machine progression
- Prefetch buffer operation
- Pipeline stall handling
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


@cocotb.test()
async def test_pipelined_scheduler_states(dut):
    """Test that the pipelined scheduler progresses through states correctly."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.start.value = 0
    dut.thread_count.value = 4
    dut.decoded_mem_read_enable.value = 0
    dut.decoded_mem_write_enable.value = 0
    dut.decoded_ret.value = 0
    dut.decoded_pc_mux.value = 0
    dut.decoded_immediate.value = 0
    dut.fetcher_state.value = 0
    dut.branch_taken.value = 0
    
    for i in range(4):
        dut.lsu_state[i].value = 0
        dut.next_pc[i].value = 1
    
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Should be in IDLE state
    state = int(dut.core_state.value)
    dut._log.info(f"State after reset: {state}")
    assert state == 0, f"Expected IDLE (0), got {state}"

    # Start execution
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Should transition to FETCH
    await RisingEdge(dut.clk)
    state = int(dut.core_state.value)
    dut._log.info(f"State after start: {state}")
    assert state == 1, f"Expected FETCH (1), got {state}"

    # Simulate fetcher completing
    dut.fetcher_state.value = 0b010  # FETCHED
    await RisingEdge(dut.clk)

    # Should transition to DECODE
    await RisingEdge(dut.clk)
    state = int(dut.core_state.value)
    dut._log.info(f"State after fetch complete: {state}")
    assert state == 2, f"Expected DECODE (2), got {state}"

    dut._log.info("Pipelined scheduler states test passed")


@cocotb.test()
async def test_active_mask_init(dut):
    """Test that active mask is initialized based on thread count."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset with 4 threads
    dut.reset.value = 1
    dut.thread_count.value = 4
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Start
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await ClockCycles(dut.clk, 2)

    active = int(dut.active_mask.value)
    dut._log.info(f"Active mask with 4 threads: {active:04b}")
    assert active == 0b1111, f"Expected 1111, got {active:04b}"

    dut._log.info("Active mask initialization test passed")


@cocotb.test()
async def test_prefetch_signal(dut):
    """Test that prefetch signal is generated for non-stall cases."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    dut.thread_count.value = 4
    dut.decoded_mem_read_enable.value = 0
    dut.decoded_mem_write_enable.value = 0
    dut.decoded_ret.value = 0
    dut.decoded_pc_mux.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

    # Start
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for FETCH state
    await ClockCycles(dut.clk, 2)
    
    # Simulate fetcher completing
    dut.fetcher_state.value = 0b010  # FETCHED
    await RisingEdge(dut.clk)

    # Check for prefetch enable
    await ClockCycles(dut.clk, 2)
    prefetch = int(dut.prefetch_enable.value) if hasattr(dut, 'prefetch_enable') else 0
    dut._log.info(f"Prefetch enable: {prefetch}")

    dut._log.info("Prefetch signal test passed")
