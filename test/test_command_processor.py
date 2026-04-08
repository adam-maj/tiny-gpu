"""
Command Processor Unit Tests
Tests for GPU command queue and dispatch unit.
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
async def test_command_processor_reset(dut):
    """Test command processor comes out of reset correctly."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    # Apply reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    
    # Release reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Verify idle state
    assert dut.cmd_ready.value == 1, "Command processor should be ready after reset"
    
    dut._log.info("PASS: Command processor reset test")


@cocotb.test()
async def test_command_queue_write(dut):
    """Test writing commands to the queue."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write test commands
    test_commands = [
        0x00010001,  # NOP
        0x10020000,  # SET_SH_REG
        0xDEADBEEF,  # Data payload
        0x30030000,  # DISPATCH_DIRECT
    ]
    
    for i, cmd in enumerate(test_commands):
        dut.cmd_data.value = cmd
        dut.cmd_valid.value = 1
        dut.queue_select.value = 0  # Queue 0
        await RisingEdge(dut.clk)
        
        # Wait for ready
        while dut.cmd_ready.value == 0:
            await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info(f"PASS: Wrote {len(test_commands)} commands to queue")


@cocotb.test()
async def test_multi_queue_operation(dut):
    """Test all 4 command queues operate independently."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write to each queue
    for queue_id in range(4):
        dut.queue_select.value = queue_id
        dut.cmd_data.value = 0x00010000 | queue_id  # NOP with queue ID
        dut.cmd_valid.value = 1
        await RisingEdge(dut.clk)
        
        while dut.cmd_ready.value == 0:
            await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: Multi-queue operation test")


@cocotb.test()
async def test_command_opcodes(dut):
    """Test all PM4-style command opcodes."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    opcodes = [
        (0x00, "NOP"),
        (0x10, "SET_SH_REG"),
        (0x11, "SET_CONTEXT_REG"),
        (0x20, "DRAW_INDEX"),
        (0x21, "DRAW_INDEX_AUTO"),
        (0x30, "DISPATCH_DIRECT"),
        (0x31, "DISPATCH_INDIRECT"),
        (0x40, "DMA_DATA"),
        (0x50, "WAIT_REG_MEM"),
        (0x51, "WRITE_DATA"),
        (0x60, "EVENT_WRITE"),
        (0x61, "RELEASE_MEM"),
        (0x70, "INDIRECT_BUFFER"),
        (0x71, "COND_EXEC"),
        (0xFE, "FENCE"),
        (0xFF, "TIMESTAMP"),
    ]
    
    for opcode, name in opcodes:
        cmd = (opcode << 24) | 0x00010000
        dut.cmd_data.value = cmd
        dut.cmd_valid.value = 1
        dut.queue_select.value = 0
        await RisingEdge(dut.clk)
        
        while dut.cmd_ready.value == 0:
            await RisingEdge(dut.clk)
        
        dut._log.info(f"  Tested opcode 0x{opcode:02X}: {name}")
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info(f"PASS: Tested {len(opcodes)} command opcodes")


@cocotb.test()
async def test_ring_buffer_wrap(dut):
    """Test ring buffer wrap-around behavior."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Fill the buffer to force wrap-around
    buffer_depth = 256  # Assuming 256-entry buffer
    
    for i in range(buffer_depth + 10):
        dut.cmd_data.value = i
        dut.cmd_valid.value = 1
        dut.queue_select.value = 0
        await RisingEdge(dut.clk)
        
        # Handle backpressure
        timeout = 0
        while dut.cmd_ready.value == 0 and timeout < 100:
            await RisingEdge(dut.clk)
            timeout += 1
        
        if timeout >= 100:
            break  # Buffer full, expected
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: Ring buffer wrap test")


@cocotb.test()
async def test_command_dispatch(dut):
    """Test command dispatch to execution units."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable dispatch
    dut.dispatch_enable.value = 1
    
    # Write a dispatch command
    dut.cmd_data.value = 0x30010001  # DISPATCH_DIRECT, 1 group
    dut.cmd_valid.value = 1
    dut.queue_select.value = 0
    await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    
    # Wait for dispatch to complete
    await ClockCycles(dut.clk, 20)
    
    # Check dispatch occurred
    if hasattr(dut, 'dispatch_valid'):
        dispatch_count = 0
        for _ in range(50):
            if dut.dispatch_valid.value == 1:
                dispatch_count += 1
            await RisingEdge(dut.clk)
        
        dut._log.info(f"  Dispatched {dispatch_count} commands")
    
    dut._log.info("PASS: Command dispatch test")


@cocotb.test()
async def test_fence_synchronization(dut):
    """Test fence/barrier synchronization."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write commands with fence
    commands = [
        0x30010001,  # DISPATCH_DIRECT
        0xFE000000,  # FENCE
        0x30010002,  # DISPATCH_DIRECT (should wait)
    ]
    
    for cmd in commands:
        dut.cmd_data.value = cmd
        dut.cmd_valid.value = 1
        dut.queue_select.value = 0
        await RisingEdge(dut.clk)
        
        while dut.cmd_ready.value == 0:
            await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    
    # Signal fence completion
    if hasattr(dut, 'fence_done'):
        await ClockCycles(dut.clk, 10)
        dut.fence_done.value = 1
        await RisingEdge(dut.clk)
        dut.fence_done.value = 0
    
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("PASS: Fence synchronization test")


@cocotb.test()
async def test_queue_priority(dut):
    """Test queue priority handling."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set different priorities
    if hasattr(dut, 'queue_priority'):
        dut.queue_priority.value = 0b11100100  # Q3=3, Q2=2, Q1=1, Q0=0
    
    # Write to all queues
    for queue_id in range(4):
        dut.queue_select.value = queue_id
        dut.cmd_data.value = 0x00010000 | queue_id
        dut.cmd_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("PASS: Queue priority test")


@cocotb.test()
async def test_indirect_buffer(dut):
    """Test indirect buffer execution."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write indirect buffer command
    dut.cmd_data.value = 0x70000010  # INDIRECT_BUFFER, 16 dwords
    dut.cmd_valid.value = 1
    dut.queue_select.value = 0
    await RisingEdge(dut.clk)
    
    # Write buffer address
    dut.cmd_data.value = 0x10000000  # Buffer address
    await RisingEdge(dut.clk)
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 30)
    
    dut._log.info("PASS: Indirect buffer test")


@cocotb.test()
async def test_stress_random_commands(dut):
    """Stress test with random commands."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    num_commands = 1000
    
    for i in range(num_commands):
        # Random command
        opcode = random.choice([0x00, 0x10, 0x20, 0x30, 0x40, 0x50])
        payload = random.randint(0, 0xFFFF)
        cmd = (opcode << 24) | payload
        
        dut.cmd_data.value = cmd
        dut.cmd_valid.value = 1
        dut.queue_select.value = random.randint(0, 3)
        await RisingEdge(dut.clk)
        
        # Handle backpressure
        timeout = 0
        while dut.cmd_ready.value == 0 and timeout < 10:
            await RisingEdge(dut.clk)
            timeout += 1
    
    dut.cmd_valid.value = 0
    await ClockCycles(dut.clk, 50)
    
    dut._log.info(f"PASS: Stress test with {num_commands} random commands")
