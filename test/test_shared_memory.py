"""
Unit Tests for Shared Memory (shared_memory.sv)
Tests multi-banked memory access and bank conflict detection.
Note: sv2v flattens arrays, so read_addr is 32-bit (4 ports * 8 bits)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Constants matching the module parameters
NUM_PORTS = 4
ADDR_BITS = 8
DATA_BITS = 8

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset.value = 1
    dut.read_valid.value = 0
    dut.write_valid.value = 0
    dut.read_addr.value = 0
    dut.write_addr.value = 0
    dut.write_data.value = 0
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)

def pack_addrs(addrs):
    """Pack list of 4 addresses into a single 32-bit value"""
    result = 0
    for i, addr in enumerate(addrs):
        result |= (addr & 0xFF) << (i * 8)
    return result

def pack_data(data_list):
    """Pack list of 4 data values into a single 32-bit value"""
    result = 0
    for i, data in enumerate(data_list):
        result |= (data & 0xFF) << (i * 8)
    return result

def unpack_data(packed, index):
    """Unpack a single data value from packed 32-bit"""
    return (packed >> (index * 8)) & 0xFF

@cocotb.test()
async def test_shared_memory_reset(dut):
    """Test that shared memory resets properly"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # All read data should be 0 after reset
    assert dut.bank_conflict.value == 0, "No bank conflicts after reset"
    
    cocotb.log.info("Shared memory reset test passed")

@cocotb.test()
async def test_shared_memory_write_read(dut):
    """Test basic write and read operations"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    test_addr = 0x04  # Bank 0 (addr % 4 == 0)
    test_data = 0x55
    
    # Write through port 0 (address in lower 8 bits)
    dut.write_valid.value = 0b0001
    dut.write_addr.value = pack_addrs([test_addr, 0, 0, 0])
    dut.write_data.value = pack_data([test_data, 0, 0, 0])
    await RisingEdge(dut.clk)
    dut.write_valid.value = 0
    await RisingEdge(dut.clk)
    
    # Read through port 0
    dut.read_valid.value = 0b0001
    dut.read_addr.value = pack_addrs([test_addr, 0, 0, 0])
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Verify read data (port 0 is in lower 8 bits)
    read_value = unpack_data(int(dut.read_data.value), 0)
    assert read_value == test_data, f"Read mismatch: got {read_value}, expected {test_data}"
    
    dut.read_valid.value = 0
    
    cocotb.log.info("Shared memory write/read test passed")

@cocotb.test()
async def test_shared_memory_multiple_ports(dut):
    """Test writing through different ports to different banks"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write different values through different ports to different banks
    test_data = [0xAA, 0xBB, 0xCC, 0xDD]
    test_addrs = [0x00, 0x01, 0x02, 0x03]  # Each to different bank
    
    # Write all at once (no conflicts since different banks)
    dut.write_valid.value = 0b1111
    dut.write_addr.value = pack_addrs(test_addrs)
    dut.write_data.value = pack_data(test_data)
    
    await RisingEdge(dut.clk)
    
    # Disable writes
    dut.write_valid.value = 0
    
    await RisingEdge(dut.clk)
    
    cocotb.log.info("Shared memory multiple ports test passed")

@cocotb.test()
async def test_shared_memory_bank_conflict(dut):
    """Test bank conflict detection"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Access same bank from two ports (addresses that map to same bank)
    # Bank = addr[1:0], so 0x00 and 0x04 both go to bank 0
    conflict_addr1 = 0x00
    conflict_addr2 = 0x04
    
    dut.read_valid.value = 0b0011  # Ports 0 and 1
    dut.read_addr.value = pack_addrs([conflict_addr1, conflict_addr2, 0, 0])
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Check if bank conflict is signaled
    conflict_detected = int(dut.bank_conflict.value)
    cocotb.log.info(f"Bank conflict signal: {bin(conflict_detected)}")
    
    # At least one port should report a conflict
    assert conflict_detected != 0, "Bank conflict should be detected for same-bank access"
    
    dut.read_valid.value = 0
    
    cocotb.log.info("Shared memory bank conflict test passed")

@cocotb.test()
async def test_shared_memory_no_conflict(dut):
    """Test access to different banks (no conflict)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Access different banks from two ports
    # Addresses that map to different banks
    addr1 = 0x00  # Bank 0
    addr2 = 0x01  # Bank 1
    
    dut.read_valid.value = 0b0011  # Ports 0 and 1
    dut.read_addr.value = pack_addrs([addr1, addr2, 0, 0])
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # No conflict expected
    conflict_detected = int(dut.bank_conflict.value)
    assert conflict_detected == 0, f"No bank conflict expected for different banks, got {bin(conflict_detected)}"
    
    dut.read_valid.value = 0
    
    cocotb.log.info("Shared memory no-conflict test passed")
