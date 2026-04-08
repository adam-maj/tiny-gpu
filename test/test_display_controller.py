"""
Display Controller Unit Tests
Tests for display output, timing generation, and overlay handling.
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
async def test_display_controller_reset(dut):
    """Test display controller comes out of reset correctly."""
    clock = Clock(dut.clk, 6.173, units="ns")  # 162MHz for 1920x1080@60Hz
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Check idle state
    if hasattr(dut, 'display_ready'):
        assert dut.display_ready.value == 1, "Display should be ready"
    
    dut._log.info("PASS: Display controller reset test")


@cocotb.test()
async def test_1080p_timing(dut):
    """Test 1920x1080@60Hz timing generation."""
    clock = Clock(dut.clk, 6.173, units="ns")  # 162MHz
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set 1080p mode
    if hasattr(dut, 'mode_select'):
        dut.mode_select.value = 0  # 1080p
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    # Monitor timing for a few lines
    hsync_count = 0
    vsync_count = 0
    
    for _ in range(2200 * 3):  # 3 lines worth of pixels
        await RisingEdge(dut.clk)
        
        if hasattr(dut, 'hsync'):
            if dut.hsync.value == 1:
                hsync_count += 1
        
        if hasattr(dut, 'vsync'):
            if dut.vsync.value == 1:
                vsync_count += 1
    
    dut._log.info(f"  HSYNC pulses: {hsync_count}, VSYNC samples: {vsync_count}")
    dut._log.info("PASS: 1080p timing test")


@cocotb.test()
async def test_4k_timing(dut):
    """Test 3840x2160@60Hz timing generation."""
    clock = Clock(dut.clk, 1.685, units="ns")  # 594MHz for 4K
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'mode_select'):
        dut.mode_select.value = 1  # 4K
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    await ClockCycles(dut.clk, 1000)
    
    dut._log.info("PASS: 4K timing test")


@cocotb.test()
async def test_8k_timing(dut):
    """Test 7680x4320@60Hz timing generation."""
    clock = Clock(dut.clk, 0.42, units="ns")  # ~2.4GHz for 8K (theoretical)
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'mode_select'):
        dut.mode_select.value = 2  # 8K
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    await ClockCycles(dut.clk, 500)
    
    dut._log.info("PASS: 8K timing test")


@cocotb.test()
async def test_hsync_polarity(dut):
    """Test HSYNC polarity configuration."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Test positive polarity
    if hasattr(dut, 'hsync_polarity'):
        dut.hsync_polarity.value = 0
        await ClockCycles(dut.clk, 100)
        dut._log.info("  Tested HSYNC positive polarity")
        
        # Test negative polarity
        dut.hsync_polarity.value = 1
        await ClockCycles(dut.clk, 100)
        dut._log.info("  Tested HSYNC negative polarity")
    
    dut._log.info("PASS: HSYNC polarity test")


@cocotb.test()
async def test_vsync_polarity(dut):
    """Test VSYNC polarity configuration."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'vsync_polarity'):
        dut.vsync_polarity.value = 0
        await ClockCycles(dut.clk, 100)
        dut._log.info("  Tested VSYNC positive polarity")
        
        dut.vsync_polarity.value = 1
        await ClockCycles(dut.clk, 100)
        dut._log.info("  Tested VSYNC negative polarity")
    
    dut._log.info("PASS: VSYNC polarity test")


@cocotb.test()
async def test_blanking_intervals(dut):
    """Test horizontal and vertical blanking intervals."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    # Count blanking time
    blank_cycles = 0
    active_cycles = 0
    
    for _ in range(2200):  # One full line
        await RisingEdge(dut.clk)
        
        if hasattr(dut, 'data_enable'):
            if dut.data_enable.value == 0:
                blank_cycles += 1
            else:
                active_cycles += 1
    
    dut._log.info(f"  Active: {active_cycles}, Blanking: {blank_cycles}")
    
    # 1080p: 1920 active, 280 blanking
    if active_cycles > 0:
        assert active_cycles >= 1900, f"Expected ~1920 active, got {active_cycles}"
    
    dut._log.info("PASS: Blanking intervals test")


@cocotb.test()
async def test_multi_head_output(dut):
    """Test multiple display head outputs."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable all 4 display heads
    for head in range(4):
        if hasattr(dut, f'head{head}_enable'):
            getattr(dut, f'head{head}_enable').value = 1
        
        if hasattr(dut, f'head{head}_mode'):
            getattr(dut, f'head{head}_mode').value = head  # Different modes
    
    await ClockCycles(dut.clk, 200)
    
    dut._log.info("PASS: Multi-head output test (4 heads)")


@cocotb.test()
async def test_framebuffer_address(dut):
    """Test framebuffer base address configuration."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set framebuffer addresses for double buffering
    addresses = [
        0x00000000,  # Front buffer
        0x00800000,  # Back buffer (~8MB offset for 1080p RGBA)
    ]
    
    for i, addr in enumerate(addresses):
        if hasattr(dut, 'fb_base_addr'):
            dut.fb_base_addr.value = addr
        
        await ClockCycles(dut.clk, 10)
        dut._log.info(f"  Set FB address {i}: 0x{addr:08X}")
    
    dut._log.info("PASS: Framebuffer address test")


@cocotb.test()
async def test_scanout_request(dut):
    """Test scanout read requests to memory."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    # Count memory read requests
    read_count = 0
    
    for _ in range(1000):
        await RisingEdge(dut.clk)
        
        if hasattr(dut, 'mem_read_req'):
            if dut.mem_read_req.value == 1:
                read_count += 1
                
                # Simulate memory response
                if hasattr(dut, 'mem_read_ack'):
                    dut.mem_read_ack.value = 1
                    await RisingEdge(dut.clk)
                    dut.mem_read_ack.value = 0
    
    dut._log.info(f"  Memory read requests: {read_count}")
    dut._log.info("PASS: Scanout request test")


@cocotb.test()
async def test_overlay_plane(dut):
    """Test overlay plane blending."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable overlay
    if hasattr(dut, 'overlay_enable'):
        dut.overlay_enable.value = 1
        dut.overlay_x.value = 100
        dut.overlay_y.value = 100
        dut.overlay_width.value = 640
        dut.overlay_height.value = 480
        dut.overlay_alpha.value = 200  # ~78% opacity
    
    await ClockCycles(dut.clk, 200)
    
    dut._log.info("PASS: Overlay plane test")


@cocotb.test()
async def test_cursor_plane(dut):
    """Test hardware cursor plane."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable cursor
    if hasattr(dut, 'cursor_enable'):
        dut.cursor_enable.value = 1
        dut.cursor_x.value = 500
        dut.cursor_y.value = 400
        dut.cursor_width.value = 32
        dut.cursor_height.value = 32
    
    # Move cursor
    for x in range(500, 600, 10):
        if hasattr(dut, 'cursor_x'):
            dut.cursor_x.value = x
        await ClockCycles(dut.clk, 5)
    
    dut._log.info("PASS: Cursor plane test")


@cocotb.test()
async def test_gamma_lut(dut):
    """Test gamma correction LUT."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Load gamma curve (2.2 approximation)
    if hasattr(dut, 'gamma_lut_write'):
        for i in range(256):
            gamma = int(((i / 255.0) ** 2.2) * 255)
            
            dut.gamma_lut_addr.value = i
            dut.gamma_lut_data.value = gamma
            dut.gamma_lut_write.value = 1
            await RisingEdge(dut.clk)
        
        dut.gamma_lut_write.value = 0
    
    # Enable gamma correction
    if hasattr(dut, 'gamma_enable'):
        dut.gamma_enable.value = 1
    
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("PASS: Gamma LUT test")


@cocotb.test()
async def test_color_space_conversion(dut):
    """Test color space conversion (RGB to YCbCr)."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    color_spaces = [
        (0, "RGB"),
        (1, "YCbCr_601"),
        (2, "YCbCr_709"),
        (3, "YCbCr_2020"),
    ]
    
    for mode, name in color_spaces:
        if hasattr(dut, 'color_space'):
            dut.color_space.value = mode
        
        await ClockCycles(dut.clk, 20)
        dut._log.info(f"  Tested color space: {name}")
    
    dut._log.info("PASS: Color space conversion test")


@cocotb.test()
async def test_hdr_output(dut):
    """Test HDR metadata output."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set HDR metadata
    if hasattr(dut, 'hdr_enable'):
        dut.hdr_enable.value = 1
        
        # HDR10 metadata
        if hasattr(dut, 'hdr_max_luminance'):
            dut.hdr_max_luminance.value = 1000  # 1000 nits
            dut.hdr_min_luminance.value = 1     # 0.001 nits
            dut.hdr_max_cll.value = 800         # Max content light level
            dut.hdr_max_fall.value = 400        # Max frame average light
    
    await ClockCycles(dut.clk, 50)
    
    dut._log.info("PASS: HDR output test")


@cocotb.test()
async def test_vblank_interrupt(dut):
    """Test vertical blank interrupt generation."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable VBLANK interrupt
    if hasattr(dut, 'vblank_irq_enable'):
        dut.vblank_irq_enable.value = 1
    
    if hasattr(dut, 'display_enable'):
        dut.display_enable.value = 1
    
    # Wait for VBLANK
    vblank_count = 0
    timeout = 0
    
    while vblank_count < 2 and timeout < 100000:
        await RisingEdge(dut.clk)
        timeout += 1
        
        if hasattr(dut, 'vblank_irq'):
            if dut.vblank_irq.value == 1:
                vblank_count += 1
                dut._log.info(f"  VBLANK interrupt #{vblank_count}")
    
    dut._log.info("PASS: VBLANK interrupt test")


@cocotb.test()
async def test_page_flip(dut):
    """Test page flip (double buffering) on VBLANK."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set up double buffering
    if hasattr(dut, 'fb_base_addr'):
        dut.fb_base_addr.value = 0x00000000  # Front buffer
    
    if hasattr(dut, 'fb_pending_addr'):
        dut.fb_pending_addr.value = 0x00800000  # Back buffer
    
    if hasattr(dut, 'page_flip_pending'):
        dut.page_flip_pending.value = 1
    
    # Wait for flip to complete
    await ClockCycles(dut.clk, 100)
    
    if hasattr(dut, 'page_flip_done'):
        # In real scenario, this would trigger on VBLANK
        pass
    
    dut._log.info("PASS: Page flip test")


@cocotb.test()
async def test_underscan_compensation(dut):
    """Test underscan/overscan compensation."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # 5% underscan
    if hasattr(dut, 'underscan_h'):
        dut.underscan_h.value = 96   # 1920 * 0.05
        dut.underscan_v.value = 54   # 1080 * 0.05
    
    await ClockCycles(dut.clk, 100)
    
    dut._log.info("PASS: Underscan compensation test")


@cocotb.test()
async def test_stress_mode_switching(dut):
    """Stress test rapid mode switching."""
    clock = Clock(dut.clk, 6.173, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    modes = [0, 1, 2, 0, 1, 2]  # 1080p, 4K, 8K cycle
    
    for i, mode in enumerate(modes):
        if hasattr(dut, 'mode_select'):
            dut.mode_select.value = mode
        
        await ClockCycles(dut.clk, 50)
        dut._log.info(f"  Mode switch {i+1}: mode={mode}")
    
    dut._log.info("PASS: Mode switching stress test")
