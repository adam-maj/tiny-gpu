import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

async def reset(dut):
    dut.reset.value = 1
    dut.mem_read_valid.value = 0
    dut.mem_read_address.value = 0
    dut.mem_write_valid.value = 0
    dut.mem_write_address.value = 0
    dut.mem_write_data.value = 0
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)  # Ensure reset is registered in the DUT

@cocotb.test()
async def test_memory_operations(dut):
    # Initialize
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Test write operation
    dut.mem_write_valid.value = 1
    dut.mem_write_address.value = 0
    dut.mem_write_data.value = 12345
    await RisingEdge(dut.clk)
    assert dut.mem_write_ready.value == 0 

    while dut.mem_write_ready != 1:
        await RisingEdge(dut.clk)

    assert dut.mem_write_ready.value == 1
    dut.mem_write_valid.value = 0
    await ClockCycles(dut.clk, 2)
    assert dut.mem_write_ready.value == 0

    # Test read operation after write
    dut.mem_read_valid.value = 1
    dut.mem_read_address.value = 0
    await ClockCycles(dut.clk, 6)
    assert dut.mem_read_data.value == 12345, f"Memory read data {dut.mem_read_data.value} does not match expected value 12345"

    # Test reset behavior
    await reset(dut)
    dut.mem_read_valid.value = 1
    dut.mem_read_address.value = 0
    
    while dut.mem_read_ready != 1:
        await RisingEdge(dut.clk) 
    
    dut.mem_read_valid.value = 0
    await RisingEdge(dut.clk) 
    assert dut.mem_read_data.value == 0, f"Memory read data {dut.mem_read_data.value} does not match expected value 0 after reset"

    # Test read and write operations with latency consideration
    # Write to memory[1] = 54321
    dut.mem_write_valid.value = 1
    dut.mem_write_address.value = 1
    dut.mem_write_data.value = 54321
    await RisingEdge(dut.clk)
    dut.mem_write_valid.value = 0
    await RisingEdge(dut.clk)  # Wait for memory write to complete

    # Read from memory[1]
    dut.mem_read_valid.value = 1
    dut.mem_read_address.value = 1

    while dut.mem_read_ready != 1:
        await RisingEdge(dut.clk) 
        
    assert dut.mem_read_data.value == 54321, f"Memory read data {dut.mem_read_data.value} does not match expected value 54321"
