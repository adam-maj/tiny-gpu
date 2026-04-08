"""
Test for Tiny Tapeout 7 GPU Adapter

Tests the serial command protocol for programming and controlling
the GPU through Tiny Tapeout's constrained I/O interface.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


# Command definitions (must match tt_um_tiny_gpu.sv)
CMD_NOP           = 0x0
CMD_SET_ADDR_LOW  = 0x1
CMD_SET_ADDR_HIGH = 0x2
CMD_WRITE_PROG    = 0x3
CMD_WRITE_DATA    = 0x4
CMD_READ_DATA     = 0x5
CMD_SET_THREADS   = 0x6
CMD_START         = 0x7
CMD_STOP          = 0x8
CMD_STATUS        = 0x9


async def send_command(dut, cmd, data=0):
    """Send a command with optional data nibble."""
    dut.ui_in.value = (cmd << 4) | (data & 0xF)
    await RisingEdge(dut.clk)


async def send_data(dut, data):
    """Send a data byte (follows a command)."""
    dut.ui_in.value = data
    await RisingEdge(dut.clk)


async def set_address(dut, addr):
    """Set the 16-bit address for memory operations."""
    await send_command(dut, CMD_SET_ADDR_LOW)
    await send_data(dut, addr & 0xFF)
    await send_command(dut, CMD_SET_ADDR_HIGH)
    await send_data(dut, (addr >> 8) & 0xFF)


async def write_program_word(dut, instruction):
    """Write a 16-bit instruction to program memory at current address."""
    await send_command(dut, CMD_WRITE_PROG)
    await send_data(dut, (instruction >> 8) & 0xFF)  # High byte first
    await send_data(dut, instruction & 0xFF)  # Low byte


async def write_data_byte(dut, data):
    """Write an 8-bit value to data memory at current address."""
    await send_command(dut, CMD_WRITE_DATA)
    await send_data(dut, data & 0xFF)


async def read_data_byte(dut):
    """Read an 8-bit value from data memory at current address."""
    await send_command(dut, CMD_READ_DATA)
    await send_data(dut, 0)  # Dummy cycle to complete read
    await RisingEdge(dut.clk)  # Extra cycle for output to stabilize
    return dut.uo_out.value


async def get_status(dut):
    """Get the GPU status register."""
    await send_command(dut, CMD_STATUS)
    await RisingEdge(dut.clk)
    return dut.uo_out.value


async def start_gpu(dut):
    """Start GPU execution."""
    await send_command(dut, CMD_START)


async def stop_gpu(dut):
    """Stop GPU execution."""
    await send_command(dut, CMD_STOP)


async def set_thread_count(dut, count):
    """Set the number of threads."""
    await send_command(dut, CMD_SET_THREADS)
    await send_data(dut, count)


@cocotb.test()
async def test_reset(dut):
    """Test that reset initializes the adapter correctly."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Apply reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)

    # Release reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Check status - should be idle and ready
    status = await get_status(dut)
    assert status & 0x04, f"Expected ready bit set, got status={status}"

    dut._log.info("Reset test passed")


@cocotb.test()
async def test_data_memory_write_read(dut):
    """Test writing and reading data memory."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Write test pattern to data memory
    test_data = [0xAA, 0x55, 0x12, 0x34, 0xDE, 0xAD, 0xBE, 0xEF]

    # Set address to 0
    await set_address(dut, 0)

    # Write test data
    for data in test_data:
        await write_data_byte(dut, data)

    # Set address back to 0 for reading
    await set_address(dut, 0)

    # Read and verify
    for i, expected in enumerate(test_data):
        read_val = await read_data_byte(dut)
        dut._log.info(f"Address {i}: wrote 0x{expected:02X}, read 0x{int(read_val):02X}")
        assert int(read_val) == expected, f"Data mismatch at address {i}"

    dut._log.info("Data memory write/read test passed")


@cocotb.test()
async def test_program_memory_write(dut):
    """Test writing to program memory."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Simple test program (NOP instructions)
    test_program = [
        0x0000,  # NOP
        0x0001,  # Some instruction
        0x1234,  # Some instruction
        0xABCD,  # Some instruction
    ]

    # Set address to 0
    await set_address(dut, 0)

    # Write program
    for instr in test_program:
        await write_program_word(dut, instr)
        dut._log.info(f"Wrote instruction 0x{instr:04X}")

    dut._log.info("Program memory write test passed")


@cocotb.test()
async def test_gpu_start_stop(dut):
    """Test starting and stopping the GPU."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Set thread count
    await set_thread_count(dut, 4)

    # Start GPU
    await start_gpu(dut)
    await ClockCycles(dut.clk, 2)

    # Check status - should be running
    status = await get_status(dut)
    dut._log.info(f"Status after start: 0x{int(status):02X}")

    # Wait for completion (4 threads = 4 cycles in simplified model)
    await ClockCycles(dut.clk, 10)

    # Check status - should be done
    status = await get_status(dut)
    dut._log.info(f"Status after completion: 0x{int(status):02X}")
    assert status & 0x02, f"Expected done bit set, got status={status}"

    # Stop GPU
    await stop_gpu(dut)
    await ClockCycles(dut.clk, 2)

    # Check status - should be idle
    status = await get_status(dut)
    assert status & 0x04, f"Expected ready bit set after stop, got status={status}"

    dut._log.info("GPU start/stop test passed")


@cocotb.test()
async def test_address_auto_increment(dut):
    """Test that address auto-increments after writes."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Set address to 0
    await set_address(dut, 0)

    # Write sequential values without setting address each time
    for i in range(16):
        await write_data_byte(dut, i)

    # Verify by reading back
    await set_address(dut, 0)
    for i in range(16):
        read_val = await read_data_byte(dut)
        assert int(read_val) == i, f"Expected {i}, got {int(read_val)}"

    dut._log.info("Address auto-increment test passed")
