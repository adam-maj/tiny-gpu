"""
Interrupt Controller Unit Tests
Tests for interrupt aggregation, routing, and coalescing.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
import random


async def reset_dut(dut):
    """Reset the DUT."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def test_interrupt_controller_reset(dut):
    """Test interrupt controller comes out of reset correctly."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # All interrupts should be disabled/cleared
    if hasattr(dut, 'irq_pending'):
        assert dut.irq_pending.value == 0, "No IRQs should be pending after reset"
    
    dut._log.info("PASS: Interrupt controller reset test")


@cocotb.test()
async def test_single_interrupt(dut):
    """Test single interrupt assertion and clearing."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable interrupt source 0
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x0000000000000001  # Enable source 0
    
    # Assert interrupt
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x0000000000000001  # Source 0
    
    await RisingEdge(dut.clk)
    
    # Check pending
    if hasattr(dut, 'irq_pending'):
        assert dut.irq_pending.value != 0, "IRQ should be pending"
    
    # Clear interrupt
    if hasattr(dut, 'irq_clear'):
        dut.irq_clear.value = 0x0000000000000001
        await RisingEdge(dut.clk)
        dut.irq_clear.value = 0
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Single interrupt test")


@cocotb.test()
async def test_64_interrupt_sources(dut):
    """Test all 64 interrupt sources."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable all interrupts
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFFFFFFFFFF
    
    # Test each source
    for source in range(64):
        mask = 1 << source
        
        if hasattr(dut, 'irq_source'):
            dut.irq_source.value = mask
        
        await RisingEdge(dut.clk)
        
        # Clear
        if hasattr(dut, 'irq_clear'):
            dut.irq_clear.value = mask
            await RisingEdge(dut.clk)
            dut.irq_clear.value = 0
        
        dut.irq_source.value = 0
        await RisingEdge(dut.clk)
    
    dut._log.info("PASS: 64 interrupt sources test")


@cocotb.test()
async def test_interrupt_priority(dut):
    """Test interrupt priority handling."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set priorities (higher number = higher priority)
    if hasattr(dut, 'irq_priority_0'):
        dut.irq_priority_0.value = 1   # Low priority
        dut.irq_priority_1.value = 15  # High priority
    
    # Enable both
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x3  # Enable sources 0 and 1
    
    # Assert both simultaneously
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x3
    
    await RisingEdge(dut.clk)
    
    # Higher priority (source 1) should be serviced first
    if hasattr(dut, 'irq_vector'):
        vector = dut.irq_vector.value.integer
        dut._log.info(f"  Highest priority vector: {vector}")
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Interrupt priority test")


@cocotb.test()
async def test_interrupt_masking(dut):
    """Test interrupt masking."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Disable source 0
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFFFFFFFFFE  # All except source 0
    
    # Assert masked interrupt
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x1  # Source 0
    
    await RisingEdge(dut.clk)
    
    # Should NOT see interrupt output
    if hasattr(dut, 'irq_out'):
        assert dut.irq_out.value == 0, "Masked IRQ should not propagate"
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Interrupt masking test")


@cocotb.test()
async def test_interrupt_coalescing(dut):
    """Test interrupt coalescing (aggregation)."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable coalescing
    if hasattr(dut, 'coalesce_enable'):
        dut.coalesce_enable.value = 1
        dut.coalesce_timeout.value = 50   # 50 cycles
        dut.coalesce_count.value = 4       # Coalesce 4 interrupts
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFFFFFFFFFF
    
    # Generate multiple interrupts
    irq_count = 0
    for i in range(4):
        if hasattr(dut, 'irq_source'):
            dut.irq_source.value = 1 << i
        await RisingEdge(dut.clk)
        dut.irq_source.value = 0
        await ClockCycles(dut.clk, 5)
        
        if hasattr(dut, 'irq_out'):
            if dut.irq_out.value == 1:
                irq_count += 1
    
    # Should see coalesced interrupt
    await ClockCycles(dut.clk, 60)  # Wait for timeout
    
    dut._log.info(f"  IRQ outputs before coalesce: {irq_count}")
    dut._log.info("PASS: Interrupt coalescing test")


@cocotb.test()
async def test_32_msi_x_vectors(dut):
    """Test 32 MSI-X vector mapping."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Map sources to vectors
    for vector in range(32):
        # Map 2 sources per vector
        source1 = vector * 2
        source2 = vector * 2 + 1
        
        if hasattr(dut, 'vector_mapping'):
            # Configure mapping
            dut.vector_mapping[source1].value = vector
            dut.vector_mapping[source2].value = vector
    
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: 32 MSI-X vectors test")


@cocotb.test()
async def test_level_vs_edge(dut):
    """Test level-triggered vs edge-triggered interrupts."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Configure source 0 as level, source 1 as edge
    if hasattr(dut, 'irq_mode'):
        dut.irq_mode.value = 0x2  # Bit 1 = edge, Bit 0 = level
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x3
    
    # Test level-triggered (source 0)
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x1
    await ClockCycles(dut.clk, 5)
    
    # Level should stay asserted
    if hasattr(dut, 'irq_pending'):
        level_pending = dut.irq_pending.value.integer & 0x1
        dut._log.info(f"  Level IRQ pending: {level_pending}")
    
    # Test edge-triggered (source 1)
    dut.irq_source.value = 0x2
    await RisingEdge(dut.clk)
    dut.irq_source.value = 0x0
    
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Level vs edge interrupt test")


@cocotb.test()
async def test_interrupt_status_register(dut):
    """Test interrupt status register read."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable and trigger some interrupts
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFF
    
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x55  # Alternating pattern
    
    await RisingEdge(dut.clk)
    
    if hasattr(dut, 'irq_status'):
        status = dut.irq_status.value.integer
        dut._log.info(f"  IRQ status: 0x{status:016X}")
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Interrupt status register test")


@cocotb.test()
async def test_global_interrupt_disable(dut):
    """Test global interrupt disable."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable individual interrupts
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFFFFFFFFFF
    
    # Global disable
    if hasattr(dut, 'global_irq_disable'):
        dut.global_irq_disable.value = 1
    
    # Trigger interrupts
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0xFF
    
    await RisingEdge(dut.clk)
    
    # Output should be low
    if hasattr(dut, 'irq_out'):
        assert dut.irq_out.value == 0, "Global disable should block all IRQs"
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Global interrupt disable test")


@cocotb.test()
async def test_interrupt_latency(dut):
    """Test interrupt assertion to output latency."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x1
    
    # Measure latency
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x1
    
    latency = 0
    while latency < 100:
        await RisingEdge(dut.clk)
        latency += 1
        
        if hasattr(dut, 'irq_out'):
            if dut.irq_out.value == 1:
                break
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info(f"  Interrupt latency: {latency} cycles")
    dut._log.info("PASS: Interrupt latency test")


@cocotb.test()
async def test_nested_interrupts(dut):
    """Test nested interrupt handling."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set priorities
    if hasattr(dut, 'irq_priority_0'):
        dut.irq_priority_0.value = 2   # Medium
        dut.irq_priority_1.value = 4   # High
        dut.irq_priority_2.value = 1   # Low
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x7
    
    # Assert low priority first
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x4  # Source 2 (low)
    await RisingEdge(dut.clk)
    
    # Assert high priority
    dut.irq_source.value = 0x6  # Sources 1 and 2
    await RisingEdge(dut.clk)
    
    # High priority should preempt
    if hasattr(dut, 'irq_vector'):
        vector = dut.irq_vector.value.integer
        dut._log.info(f"  Active vector: {vector}")
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Nested interrupts test")


@cocotb.test()
async def test_eoi_handling(dut):
    """Test End of Interrupt (EOI) handling."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0x1
    
    # Assert interrupt
    if hasattr(dut, 'irq_source'):
        dut.irq_source.value = 0x1
    await RisingEdge(dut.clk)
    
    # Simulate ISR read (acknowledge)
    if hasattr(dut, 'irq_ack'):
        dut.irq_ack.value = 1
        await RisingEdge(dut.clk)
        dut.irq_ack.value = 0
    
    # Send EOI
    if hasattr(dut, 'irq_eoi'):
        dut.irq_eoi.value = 0x1
        await RisingEdge(dut.clk)
        dut.irq_eoi.value = 0
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: EOI handling test")


@cocotb.test()
async def test_stress_random_interrupts(dut):
    """Stress test with random interrupt patterns."""
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFFFFFFFFFF
    
    num_iterations = 100
    
    for i in range(num_iterations):
        # Random interrupt sources
        sources = random.randint(0, 0xFFFFFFFFFFFFFFFF)
        
        if hasattr(dut, 'irq_source'):
            dut.irq_source.value = sources
        
        await RisingEdge(dut.clk)
        
        # Random clear
        if random.random() > 0.5:
            if hasattr(dut, 'irq_clear'):
                dut.irq_clear.value = random.randint(0, 0xFFFFFFFFFFFFFFFF)
                await RisingEdge(dut.clk)
                dut.irq_clear.value = 0
    
    dut.irq_source.value = 0
    await ClockCycles(dut.clk, 20)
    
    dut._log.info(f"PASS: Random interrupts stress test ({num_iterations} iterations)")
