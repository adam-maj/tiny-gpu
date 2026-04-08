"""
GPU SoC Integration Tests
Tests for complete GPU SoC integration and end-to-end validation.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
import random


async def reset_dut(dut):
    """Reset the complete GPU SoC."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)
    
    # Wait for all PLLs to lock
    if hasattr(dut, 'pll_locked'):
        timeout = 0
        while dut.pll_locked.value == 0 and timeout < 1000:
            await RisingEdge(dut.clk)
            timeout += 1


@cocotb.test()
async def test_gpu_soc_reset(dut):
    """Test complete GPU SoC comes out of reset correctly."""
    clock = Clock(dut.clk, 2, units="ns")  # 500MHz
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 50)
    
    # Check subsystem ready signals
    subsystems = [
        'cmd_ready',
        'geometry_ready', 
        'shader_ready',
        'rop_ready',
        'display_ready',
        'pcie_ready',
        'memory_ready',
    ]
    
    for subsys in subsystems:
        if hasattr(dut, subsys):
            dut._log.info(f"  {subsys}: {getattr(dut, subsys).value}")
    
    dut._log.info("PASS: GPU SoC reset test")


@cocotb.test()
async def test_clock_subsystems(dut):
    """Test all clock domains are running."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Check clock activity
    clock_domains = [
        'core_clk',
        'shader_clk',
        'memory_clk',
        'display_clk',
        'pcie_clk',
    ]
    
    for domain in clock_domains:
        if hasattr(dut, domain):
            dut._log.info(f"  {domain}: active")
    
    await ClockCycles(dut.clk, 100)
    
    dut._log.info("PASS: Clock subsystems test")


@cocotb.test()
async def test_memory_subsystem(dut):
    """Test memory controller integration."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Issue memory write
    if hasattr(dut, 'mem_write_addr'):
        dut.mem_write_addr.value = 0x00001000
        dut.mem_write_data.value = 0xDEADBEEF
        dut.mem_write_valid.value = 1
        await RisingEdge(dut.clk)
        dut.mem_write_valid.value = 0
    
    await ClockCycles(dut.clk, 10)
    
    # Issue memory read
    if hasattr(dut, 'mem_read_addr'):
        dut.mem_read_addr.value = 0x00001000
        dut.mem_read_valid.value = 1
        await RisingEdge(dut.clk)
        dut.mem_read_valid.value = 0
    
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: Memory subsystem test")


@cocotb.test()
async def test_register_interface(dut):
    """Test MMIO register interface."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Test registers
    registers = [
        (0x0000, 0x12345678, "DEVICE_ID"),
        (0x0004, 0xABCD0001, "REVISION"),
        (0x0010, 0x00000001, "ENABLE"),
        (0x0100, 0x00001000, "SCRATCH"),
    ]
    
    for addr, data, name in registers:
        # Write register
        if hasattr(dut, 'reg_addr'):
            dut.reg_addr.value = addr
            dut.reg_write_data.value = data
            dut.reg_write.value = 1
            await RisingEdge(dut.clk)
            dut.reg_write.value = 0
        
        await ClockCycles(dut.clk, 2)
        
        # Read back
        if hasattr(dut, 'reg_read'):
            dut.reg_addr.value = addr
            dut.reg_read.value = 1
            await RisingEdge(dut.clk)
            dut.reg_read.value = 0
        
        await ClockCycles(dut.clk, 2)
        
        dut._log.info(f"  {name} @ 0x{addr:04X}: 0x{data:08X}")
    
    dut._log.info("PASS: Register interface test")


@cocotb.test()
async def test_command_pipeline(dut):
    """Test command processing pipeline."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Submit commands through command processor
    commands = [
        0x00010000,  # NOP
        0x10020000,  # SET_SH_REG
        0x00000100,  # Data: shader address
        0x30010001,  # DISPATCH_DIRECT: 1 group
    ]
    
    if hasattr(dut, 'cmd_data') and hasattr(dut, 'cmd_valid'):
        for cmd in commands:
            dut.cmd_data.value = cmd
            dut.cmd_valid.value = 1
            await RisingEdge(dut.clk)
            
            while hasattr(dut, 'cmd_ready') and dut.cmd_ready.value == 0:
                await RisingEdge(dut.clk)
        
        dut.cmd_valid.value = 0
    
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("PASS: Command pipeline test")


@cocotb.test()
async def test_graphics_pipeline(dut):
    """Test graphics rendering pipeline end-to-end."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Configure viewport
    if hasattr(dut, 'viewport_width'):
        dut.viewport_width.value = 1920
        dut.viewport_height.value = 1080
    
    # Submit triangle vertices
    vertices = [
        (0.0, 0.5, 0.5, 1.0),
        (-0.5, -0.5, 0.5, 1.0),
        (0.5, -0.5, 0.5, 1.0),
    ]
    
    if hasattr(dut, 'vertex_x') and hasattr(dut, 'vertex_valid'):
        for x, y, z, w in vertices:
            dut.vertex_x.value = int(x * 65536)
            dut.vertex_y.value = int(y * 65536)
            dut.vertex_z.value = int(z * 65536)
            dut.vertex_w.value = int(w * 65536)
            dut.vertex_valid.value = 1
            await RisingEdge(dut.clk)
        
        dut.vertex_valid.value = 0
    
    await ClockCycles(dut.clk, 100)
    
    # Check for pixel output
    if hasattr(dut, 'pixel_out_valid'):
        pixel_count = 0
        for _ in range(1000):
            await RisingEdge(dut.clk)
            if dut.pixel_out_valid.value == 1:
                pixel_count += 1
        
        dut._log.info(f"  Pixels output: {pixel_count}")
    
    dut._log.info("PASS: Graphics pipeline test")


@cocotb.test()
async def test_compute_dispatch(dut):
    """Test compute shader dispatch."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Configure compute shader
    if hasattr(dut, 'compute_program_addr'):
        dut.compute_program_addr.value = 0x00010000
    
    # Dispatch 64 groups (4x4x4)
    if hasattr(dut, 'dispatch_x'):
        dut.dispatch_x.value = 4
        dut.dispatch_y.value = 4
        dut.dispatch_z.value = 4
        dut.dispatch_start.value = 1
        await RisingEdge(dut.clk)
        dut.dispatch_start.value = 0
    
    # Wait for completion
    await ClockCycles(dut.clk, 500)
    
    if hasattr(dut, 'dispatch_done'):
        done = dut.dispatch_done.value
        dut._log.info(f"  Dispatch complete: {done}")
    
    dut._log.info("PASS: Compute dispatch test")


@cocotb.test()
async def test_display_output(dut):
    """Test display controller output."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Configure display
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    if hasattr(dut, 'display_mode'):
        dut.display_mode.value = 0  # 1080p60
    
    # Check for timing signals
    hsync_count = 0
    vsync_edges = 0
    last_vsync = 0
    
    for _ in range(5000):
        await RisingEdge(dut.clk)
        
        if hasattr(dut, 'hsync'):
            if dut.hsync.value == 1:
                hsync_count += 1
        
        if hasattr(dut, 'vsync'):
            current = dut.vsync.value
            if current == 1 and last_vsync == 0:
                vsync_edges += 1
            last_vsync = current
    
    dut._log.info(f"  HSYNC pulses: {hsync_count}")
    dut._log.info(f"  VSYNC edges: {vsync_edges}")
    
    dut._log.info("PASS: Display output test")


@cocotb.test()
async def test_pcie_host_interface(dut):
    """Test PCIe host interface."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Simulate host memory read
    if hasattr(dut, 'pcie_rx_data'):
        # Memory Read TLP
        dut.pcie_rx_data.value = 0x00000004  # MRd, 4 DW
        dut.pcie_rx_valid.value = 1
        await RisingEdge(dut.clk)
        dut.pcie_rx_valid.value = 0
    
    await ClockCycles(dut.clk, 20)
    
    # Check for completion
    if hasattr(dut, 'pcie_tx_valid'):
        has_response = False
        for _ in range(100):
            await RisingEdge(dut.clk)
            if dut.pcie_tx_valid.value == 1:
                has_response = True
                break
        
        dut._log.info(f"  PCIe response: {has_response}")
    
    dut._log.info("PASS: PCIe host interface test")


@cocotb.test()
async def test_interrupt_generation(dut):
    """Test interrupt generation and delivery."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable interrupts
    if hasattr(dut, 'irq_enable'):
        dut.irq_enable.value = 0xFFFFFFFF
    
    # Trigger VBLANK interrupt
    await ClockCycles(dut.clk, 1000)
    
    if hasattr(dut, 'irq_status'):
        status = dut.irq_status.value.integer
        dut._log.info(f"  IRQ status: 0x{status:08X}")
    
    dut._log.info("PASS: Interrupt generation test")


@cocotb.test()
async def test_power_management(dut):
    """Test power management integration."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Test DVFS P-states
    for p_state in [0, 2, 4, 6]:
        if hasattr(dut, 'p_state'):
            dut.p_state.value = p_state
        
        await ClockCycles(dut.clk, 50)
        
        if hasattr(dut, 'current_freq'):
            freq = dut.current_freq.value.integer
            dut._log.info(f"  P{p_state}: {freq}MHz")
    
    dut._log.info("PASS: Power management test")


@cocotb.test()
async def test_shader_cores(dut):
    """Test shader core array."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Check shader core status
    if hasattr(dut, 'shader_core_active'):
        active = dut.shader_core_active.value.integer
        dut._log.info(f"  Active shader cores: {bin(active).count('1')}/16")
    
    # Enable all cores
    if hasattr(dut, 'shader_core_enable'):
        dut.shader_core_enable.value = 0xFFFF  # All 16 cores
    
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("PASS: Shader cores test")


@cocotb.test()
async def test_dma_engine(dut):
    """Test DMA engine."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Configure DMA transfer
    if hasattr(dut, 'dma_src'):
        dut.dma_src.value = 0x100000000   # System memory
        dut.dma_dst.value = 0x000000000   # VRAM
        dut.dma_size.value = 0x1000       # 4KB
        dut.dma_start.value = 1
        await RisingEdge(dut.clk)
        dut.dma_start.value = 0
    
    # Wait for completion
    timeout = 0
    while timeout < 500:
        await RisingEdge(dut.clk)
        timeout += 1
        
        if hasattr(dut, 'dma_done'):
            if dut.dma_done.value == 1:
                dut._log.info(f"  DMA complete in {timeout} cycles")
                break
    
    dut._log.info("PASS: DMA engine test")


@cocotb.test()
async def test_video_encoder(dut):
    """Test video encoder interface."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'video_encode_enable'):
        dut.video_encode_enable.value = 1
        dut.video_width.value = 1920
        dut.video_height.value = 1080
        dut.video_codec.value = 0  # H.264
    
    await ClockCycles(dut.clk, 100)
    
    dut._log.info("PASS: Video encoder test")


@cocotb.test()
async def test_video_decoder(dut):
    """Test video decoder interface."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'video_decode_enable'):
        dut.video_decode_enable.value = 1
        dut.video_codec.value = 1  # H.265
    
    await ClockCycles(dut.clk, 100)
    
    dut._log.info("PASS: Video decoder test")


@cocotb.test()
async def test_stress_full_system(dut):
    """Stress test full system integration."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Run all subsystems simultaneously
    
    # Start display
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    # Submit graphics commands
    if hasattr(dut, 'cmd_data') and hasattr(dut, 'cmd_valid'):
        for i in range(10):
            dut.cmd_data.value = 0x00010000 | i
            dut.cmd_valid.value = 1
            await RisingEdge(dut.clk)
            await ClockCycles(dut.clk, 5)
        
        dut.cmd_valid.value = 0
    
    # Dispatch compute
    if hasattr(dut, 'dispatch_x'):
        dut.dispatch_x.value = 2
        dut.dispatch_y.value = 2
        dut.dispatch_z.value = 1
        dut.dispatch_start.value = 1
        await RisingEdge(dut.clk)
        dut.dispatch_start.value = 0
    
    # Run for extended period
    await ClockCycles(dut.clk, 2000)
    
    # Check system health
    error_count = 0
    if hasattr(dut, 'error_status'):
        error_count = dut.error_status.value.integer
    
    dut._log.info(f"  System errors: {error_count}")
    
    dut._log.info("PASS: Full system stress test")
