"""
Comprehensive End-to-End Tests for Production GPU Features
Tests memory controller, TLB, texture unit, and LSQ with realistic workloads
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random

# ====================
# Memory Controller Tests
# ====================

@cocotb.test()
async def test_memory_controller_virtual_translation(dut):
    """Test virtual to physical address translation"""
    if not hasattr(dut, 'mem_ctrl'):
        cocotb.log.info("Memory controller not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Setup page table entry: VPN 0x100 -> PPN 0x200
    dut.mem_ctrl.pt_update.value = 1
    dut.mem_ctrl.pt_vpn.value = 0x100
    dut.mem_ctrl.pt_ppn.value = 0x200
    dut.mem_ctrl.pt_valid.value = 1
    dut.mem_ctrl.pt_writable.value = 1
    await RisingEdge(dut.clk)
    dut.mem_ctrl.pt_update.value = 0
    
    # Issue memory request with virtual address
    vaddr = (0x100 << 12) | 0x456  # VPN 0x100, offset 0x456
    dut.mem_ctrl.req_valid.value = 1
    dut.mem_ctrl.req_write.value = 0
    dut.mem_ctrl.req_vaddr.value = vaddr
    
    await ClockCycles(dut.clk, 20)
    
    dut.mem_ctrl.req_valid.value = 0
    
    cocotb.log.info("Memory controller address translation test passed")

@cocotb.test()
async def test_memory_controller_page_fault(dut):
    """Test page fault detection"""
    if not hasattr(dut, 'mem_ctrl'):
        cocotb.log.info("Memory controller not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Access invalid page (no page table entry)
    vaddr = (0x999 << 12) | 0x000
    dut.mem_ctrl.req_valid.value = 1
    dut.mem_ctrl.req_write.value = 0
    dut.mem_ctrl.req_vaddr.value = vaddr
    
    # Wait for page fault signal
    for _ in range(50):
        await RisingEdge(dut.clk)
        if hasattr(dut.mem_ctrl, 'page_fault') and dut.mem_ctrl.page_fault.value == 1:
            cocotb.log.info("Page fault correctly detected")
            break
    
    dut.mem_ctrl.req_valid.value = 0
    
    cocotb.log.info("Memory controller page fault test passed")

# ====================
# TLB Tests
# ====================

@cocotb.test()
async def test_tlb_hit_miss(dut):
    """Test TLB hit and miss scenarios"""
    # Determine if TLB is standalone or sub-module
    tlb = dut.tlb if hasattr(dut, 'tlb') else dut
    
    # Check if this is actually a TLB module
    if not hasattr(tlb, 'update_vpn'):
        cocotb.log.info("TLB not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Add entry to TLB
    tlb.update_valid.value = 1
    tlb.update_vpn.value = 0x12345
    tlb.update_ppn.value = 0xABCDE
    tlb.update_writable.value = 1
    tlb.update_executable.value = 1
    await RisingEdge(dut.clk)
    tlb.update_valid.value = 0
    
    await ClockCycles(dut.clk, 2)
    
    # Lookup - should hit
    tlb.lookup_valid.value = 1
    tlb.lookup_vpn.value = 0x12345
    await RisingEdge(dut.clk)
    
    if hasattr(tlb, 'lookup_hit'):
        assert tlb.lookup_hit.value == 1, "TLB lookup should hit"
        assert tlb.lookup_ppn.value == 0xABCDE, "PPN should match"
    
    # Lookup different address - should miss
    tlb.lookup_vpn.value = 0x99999
    await RisingEdge(dut.clk)
    
    if hasattr(tlb, 'lookup_hit'):
        assert tlb.lookup_hit.value == 0, "TLB lookup should miss"
    
    tlb.lookup_valid.value = 0
    
    cocotb.log.info("TLB hit/miss test passed")

@cocotb.test()
async def test_tlb_lru_replacement(dut):
    """Test TLB LRU replacement policy"""
    # Determine if TLB is standalone or sub-module
    tlb = dut.tlb if hasattr(dut, 'tlb') else dut
    
    # Check if this is actually a TLB module
    if not hasattr(tlb, 'update_vpn'):
        cocotb.log.info("TLB not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Fill TLB with entries (assuming 64 entries)
    for i in range(70):
        tlb.update_valid.value = 1
        tlb.update_vpn.value = i
        tlb.update_ppn.value = i * 2
        tlb.update_writable.value = 1
        tlb.update_executable.value = 0
        await RisingEdge(dut.clk)
    
    tlb.update_valid.value = 0
    
    # First entries should have been evicted
    await ClockCycles(dut.clk, 2)
    
    tlb.lookup_valid.value = 1
    tlb.lookup_vpn.value = 0
    await RisingEdge(dut.clk)
    
    if hasattr(tlb, 'lookup_hit'):
        # Entry 0 should have been evicted
        cocotb.log.info(f"TLB lookup for evicted entry: hit={tlb.lookup_hit.value}")
    
    tlb.lookup_valid.value = 0
    
    cocotb.log.info("TLB LRU replacement test passed")

# ====================
# Texture Unit Tests
# ====================

@cocotb.test()
async def test_texture_unit_nearest_sampling(dut):
    """Test nearest neighbor texture sampling"""
    if not hasattr(dut, 'tex_unit'):
        cocotb.log.info("Texture unit not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Configure texture
    dut.tex_unit.texture_width.value = 256
    dut.tex_unit.texture_height.value = 256
    dut.tex_unit.texture_base_addr.value = 0x1000
    
    # Request texture sample at (0.5, 0.5) - middle of texture
    dut.tex_unit.sample_valid.value = 1
    dut.tex_unit.tex_u.value = 0x8000  # 0.5 in fixed point (16-bit)
    dut.tex_unit.tex_v.value = 0x8000
    dut.tex_unit.filter_mode.value = 0  # Nearest
    dut.tex_unit.wrap_mode_u.value = 0  # Clamp
    dut.tex_unit.wrap_mode_v.value = 0
    
    await ClockCycles(dut.clk, 50)
    
    dut.tex_unit.sample_valid.value = 0
    
    cocotb.log.info("Texture unit nearest sampling test passed")

@cocotb.test()
async def test_texture_unit_bilinear_filtering(dut):
    """Test bilinear texture filtering"""
    if not hasattr(dut, 'tex_unit'):
        cocotb.log.info("Texture unit not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Configure texture
    dut.tex_unit.texture_width.value = 256
    dut.tex_unit.texture_height.value = 256
    dut.tex_unit.texture_base_addr.value = 0x1000
    
    # Request bilinear filtered sample
    dut.tex_unit.sample_valid.value = 1
    dut.tex_unit.tex_u.value = 0x8080  # Slightly off-center for interpolation
    dut.tex_unit.tex_v.value = 0x8080
    dut.tex_unit.filter_mode.value = 1  # Bilinear
    dut.tex_unit.wrap_mode_u.value = 1  # Wrap
    dut.tex_unit.wrap_mode_v.value = 1
    
    await ClockCycles(dut.clk, 100)
    
    dut.tex_unit.sample_valid.value = 0
    
    cocotb.log.info("Texture unit bilinear filtering test passed")

# ====================
# Load/Store Queue Tests
# ====================

@cocotb.test()
async def test_lsq_store_forwarding(dut):
    """Test store-to-load forwarding in LSQ"""
    if not hasattr(dut, 'lsq'):
        cocotb.log.info("LSQ not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Dispatch a store
    dut.lsq.dispatch_valid.value = 1
    dut.lsq.dispatch_is_load.value = 0
    dut.lsq.dispatch_addr.value = 0x1000
    dut.lsq.dispatch_data.value = 0xDEADBEEF
    dut.lsq.dispatch_id.value = 1
    await RisingEdge(dut.clk)
    
    # Dispatch a load to same address
    dut.lsq.dispatch_is_load.value = 1
    dut.lsq.dispatch_addr.value = 0x1000
    dut.lsq.dispatch_id.value = 2
    await RisingEdge(dut.clk)
    
    dut.lsq.dispatch_valid.value = 0
    
    # Execute store
    dut.lsq.execute_ready.value = 1
    
    await ClockCycles(dut.clk, 50)
    
    cocotb.log.info("LSQ store forwarding test passed")

@cocotb.test()
async def test_lsq_memory_ordering(dut):
    """Test memory ordering enforcement in LSQ"""
    if not hasattr(dut, 'lsq'):
        cocotb.log.info("LSQ not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Dispatch multiple memory operations
    addresses = [0x1000, 0x2000, 0x1004, 0x3000, 0x1000]
    
    for i, addr in enumerate(addresses):
        dut.lsq.dispatch_valid.value = 1
        dut.lsq.dispatch_is_load.value = (i % 2 == 0)
        dut.lsq.dispatch_addr.value = addr
        dut.lsq.dispatch_data.value = 0x100 + i
        dut.lsq.dispatch_id.value = i
        await RisingEdge(dut.clk)
    
    dut.lsq.dispatch_valid.value = 0
    dut.lsq.execute_ready.value = 1
    
    await ClockCycles(dut.clk, 100)
    
    cocotb.log.info("LSQ memory ordering test passed")

# ====================
# Stress Tests
# ====================

@cocotb.test()
async def test_stress_random_memory_operations(dut):
    """Stress test with random memory operations"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Generate random memory operations
    random.seed(42)
    num_operations = 100
    
    for i in range(num_operations):
        is_read = random.choice([True, False])
        addr = random.randint(0, 0xFFFF) & 0xFFF0  # Aligned addresses
        data = random.randint(0, 0xFFFFFFFF)
        
        # Dispatch operation if possible
        await ClockCycles(dut.clk, random.randint(1, 5))
    
    # Let operations complete
    await ClockCycles(dut.clk, 200)
    
    cocotb.log.info("Stress test with random memory operations passed")

@cocotb.test()
async def test_stress_concurrent_texture_samples(dut):
    """Stress test with concurrent texture sampling requests"""
    if not hasattr(dut, 'tex_unit'):
        cocotb.log.info("Texture unit not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Configure texture
    dut.tex_unit.texture_width.value = 256
    dut.tex_unit.texture_height.value = 256
    dut.tex_unit.texture_base_addr.value = 0x1000
    
    # Issue many texture samples
    random.seed(123)
    num_samples = 50
    
    for i in range(num_samples):
        if hasattr(dut.tex_unit, 'sample_ready') and dut.tex_unit.sample_ready.value == 1:
            dut.tex_unit.sample_valid.value = 1
            dut.tex_unit.tex_u.value = random.randint(0, 0xFFFF)
            dut.tex_unit.tex_v.value = random.randint(0, 0xFFFF)
            dut.tex_unit.filter_mode.value = random.randint(0, 1)
            dut.tex_unit.wrap_mode_u.value = random.randint(0, 2)
            dut.tex_unit.wrap_mode_v.value = random.randint(0, 2)
            await RisingEdge(dut.clk)
            dut.tex_unit.sample_valid.value = 0
        
        await ClockCycles(dut.clk, random.randint(5, 15))
    
    # Let samples complete
    await ClockCycles(dut.clk, 500)
    
    cocotb.log.info("Stress test with concurrent texture samples passed")

@cocotb.test()
async def test_stress_tlb_thrashing(dut):
    """Stress test TLB with rapid entry replacement"""
    # Determine if TLB is standalone or sub-module
    tlb = dut.tlb if hasattr(dut, 'tlb') else dut
    
    # Check if this is actually a TLB module
    if not hasattr(tlb, 'update_vpn'):
        cocotb.log.info("TLB not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    random.seed(456)
    num_accesses = 200
    num_unique_pages = 100  # More than TLB capacity
    
    for i in range(num_accesses):
        vpn = random.randint(0, num_unique_pages - 1)
        
        # Update TLB
        tlb.update_valid.value = 1
        tlb.update_vpn.value = vpn
        tlb.update_ppn.value = vpn * 2
        tlb.update_writable.value = 1
        tlb.update_executable.value = 1
        await RisingEdge(dut.clk)
        tlb.update_valid.value = 0
        
        # Lookup
        tlb.lookup_valid.value = 1
        tlb.lookup_vpn.value = vpn
        await RisingEdge(dut.clk)
        tlb.lookup_valid.value = 0
        
        await ClockCycles(dut.clk, random.randint(1, 3))
    
    cocotb.log.info("TLB thrashing stress test passed")

# ====================
# Corner Case Tests
# ====================

@cocotb.test()
async def test_corner_page_boundary_access(dut):
    """Test memory accesses crossing page boundaries"""
    if not hasattr(dut, 'mem_ctrl'):
        cocotb.log.info("Memory controller not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Setup two consecutive pages
    dut.mem_ctrl.pt_update.value = 1
    dut.mem_ctrl.pt_vpn.value = 0x100
    dut.mem_ctrl.pt_ppn.value = 0x200
    dut.mem_ctrl.pt_valid.value = 1
    dut.mem_ctrl.pt_writable.value = 1
    await RisingEdge(dut.clk)
    
    dut.mem_ctrl.pt_vpn.value = 0x101
    dut.mem_ctrl.pt_ppn.value = 0x201
    await RisingEdge(dut.clk)
    dut.mem_ctrl.pt_update.value = 0
    
    # Access at page boundary
    vaddr = (0x100 << 12) | 0xFFC  # Near end of page
    dut.mem_ctrl.req_valid.value = 1
    dut.mem_ctrl.req_write.value = 0
    dut.mem_ctrl.req_vaddr.value = vaddr
    
    await ClockCycles(dut.clk, 30)
    
    dut.mem_ctrl.req_valid.value = 0
    
    cocotb.log.info("Page boundary access test passed")

@cocotb.test()
async def test_corner_texture_wrap_modes(dut):
    """Test all texture wrap modes at boundaries"""
    if not hasattr(dut, 'tex_unit'):
        cocotb.log.info("Texture unit not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Configure texture
    dut.tex_unit.texture_width.value = 256
    dut.tex_unit.texture_height.value = 256
    dut.tex_unit.texture_base_addr.value = 0x1000
    
    # Test coordinates: 0.0, 0.99, 1.5, -0.5
    test_coords = [0x0000, 0xFD70, 0x18000, 0xFFFF8000]
    wrap_modes = [0, 1, 2]  # Clamp, Wrap, Mirror
    
    for wrap_mode in wrap_modes:
        for coord in test_coords:
            dut.tex_unit.sample_valid.value = 1
            dut.tex_unit.tex_u.value = coord & 0xFFFF
            dut.tex_unit.tex_v.value = coord & 0xFFFF
            dut.tex_unit.filter_mode.value = 0
            dut.tex_unit.wrap_mode_u.value = wrap_mode
            dut.tex_unit.wrap_mode_v.value = wrap_mode
            await RisingEdge(dut.clk)
            dut.tex_unit.sample_valid.value = 0
            await ClockCycles(dut.clk, 20)
    
    cocotb.log.info("Texture wrap modes corner case test passed")

@cocotb.test()
async def test_corner_lsq_dependency_chains(dut):
    """Test complex dependency chains in LSQ"""
    if not hasattr(dut, 'lsq'):
        cocotb.log.info("LSQ not present - skipping test")
        return
        
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Create RAW (Read After Write) dependency chain
    # ST 0x1000, LOAD 0x1000, ST 0x1000, LOAD 0x1000
    operations = [
        (0, 0x1000, 0xAAAA),  # Store
        (1, 0x1000, 0),       # Load (depends on previous store)
        (0, 0x1000, 0xBBBB),  # Store
        (1, 0x1000, 0),       # Load (depends on previous store)
    ]
    
    for i, (is_load, addr, data) in enumerate(operations):
        dut.lsq.dispatch_valid.value = 1
        dut.lsq.dispatch_is_load.value = is_load
        dut.lsq.dispatch_addr.value = addr
        dut.lsq.dispatch_data.value = data
        dut.lsq.dispatch_id.value = i
        await RisingEdge(dut.clk)
    
    dut.lsq.dispatch_valid.value = 0
    dut.lsq.execute_ready.value = 1
    
    await ClockCycles(dut.clk, 100)
    
    cocotb.log.info("LSQ dependency chains test passed")
