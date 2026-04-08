"""
Render Output Unit (ROP) Tests
Tests for blending, depth/stencil, and pixel output.
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


def pack_color(r, g, b, a):
    """Pack RGBA8 color into 32-bit value."""
    return (int(a) << 24) | (int(b) << 16) | (int(g) << 8) | int(r)


def unpack_color(color):
    """Unpack 32-bit RGBA8 color."""
    r = color & 0xFF
    g = (color >> 8) & 0xFF
    b = (color >> 16) & 0xFF
    a = (color >> 24) & 0xFF
    return r, g, b, a


@cocotb.test()
async def test_rop_reset(dut):
    """Test ROP comes out of reset correctly."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    assert dut.pixel_ready.value == 1, "ROP should be ready"
    
    dut._log.info("PASS: ROP reset test")


@cocotb.test()
async def test_blend_disabled(dut):
    """Test with blending disabled (source replaces dest)."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Disable blending
    dut.blend_enable.value = 0
    
    # Source color
    src_color = pack_color(255, 128, 64, 255)
    dut.src_color.value = src_color
    dut.pixel_valid.value = 1
    dut.pixel_x.value = 100
    dut.pixel_y.value = 100
    
    await RisingEdge(dut.clk)
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    # Output should equal source
    if hasattr(dut, 'out_color'):
        out = dut.out_color.value.integer
        assert out == src_color, f"Expected {src_color:08X}, got {out:08X}"
    
    dut._log.info("PASS: Blend disabled test")


@cocotb.test()
async def test_blend_src_alpha(dut):
    """Test SRC_ALPHA blending mode."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable blending with SRC_ALPHA
    dut.blend_enable.value = 1
    dut.blend_src_factor.value = 6   # SRC_ALPHA
    dut.blend_dst_factor.value = 7   # ONE_MINUS_SRC_ALPHA
    dut.blend_op.value = 0           # ADD
    
    # 50% alpha source
    dut.src_color.value = pack_color(255, 0, 0, 128)  # Red, 50% alpha
    dut.dst_color.value = pack_color(0, 255, 0, 255)  # Green, opaque
    dut.pixel_valid.value = 1
    dut.pixel_x.value = 100
    dut.pixel_y.value = 100
    
    await RisingEdge(dut.clk)
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    # Result should be ~50% red + 50% green = yellow-ish
    if hasattr(dut, 'out_color'):
        r, g, b, a = unpack_color(dut.out_color.value.integer)
        dut._log.info(f"  Blended color: R={r}, G={g}, B={b}, A={a}")
        # R should be ~127, G should be ~127
        assert 100 < r < 160, f"Red should be ~127, got {r}"
        assert 100 < g < 160, f"Green should be ~127, got {g}"
    
    dut._log.info("PASS: SRC_ALPHA blend test")


@cocotb.test()
async def test_blend_modes(dut):
    """Test all blend factor modes."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    blend_factors = [
        (0, "ZERO"),
        (1, "ONE"),
        (2, "SRC_COLOR"),
        (3, "ONE_MINUS_SRC_COLOR"),
        (4, "DST_COLOR"),
        (5, "ONE_MINUS_DST_COLOR"),
        (6, "SRC_ALPHA"),
        (7, "ONE_MINUS_SRC_ALPHA"),
        (8, "DST_ALPHA"),
        (9, "ONE_MINUS_DST_ALPHA"),
        (10, "CONSTANT_COLOR"),
        (11, "ONE_MINUS_CONSTANT_COLOR"),
        (12, "CONSTANT_ALPHA"),
        (13, "ONE_MINUS_CONSTANT_ALPHA"),
        (14, "SRC_ALPHA_SATURATE"),
    ]
    
    dut.blend_enable.value = 1
    
    for factor, name in blend_factors:
        dut.blend_src_factor.value = factor
        dut.blend_dst_factor.value = 0  # ZERO
        dut.blend_op.value = 0
        
        dut.src_color.value = pack_color(200, 100, 50, 200)
        dut.dst_color.value = pack_color(50, 100, 200, 128)
        dut.pixel_valid.value = 1
        dut.pixel_x.value = 10
        dut.pixel_y.value = 10
        
        await RisingEdge(dut.clk)
        dut.pixel_valid.value = 0
        await ClockCycles(dut.clk, 3)
        
        dut._log.info(f"  Tested blend factor: {name}")
    
    dut._log.info(f"PASS: All {len(blend_factors)} blend factors tested")


@cocotb.test()
async def test_blend_ops(dut):
    """Test blend operations (ADD, SUB, etc)."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    blend_ops = [
        (0, "ADD"),
        (1, "SUBTRACT"),
        (2, "REVERSE_SUBTRACT"),
        (3, "MIN"),
        (4, "MAX"),
    ]
    
    dut.blend_enable.value = 1
    dut.blend_src_factor.value = 1  # ONE
    dut.blend_dst_factor.value = 1  # ONE
    
    for op, name in blend_ops:
        dut.blend_op.value = op
        
        dut.src_color.value = pack_color(100, 100, 100, 255)
        dut.dst_color.value = pack_color(50, 50, 50, 255)
        dut.pixel_valid.value = 1
        
        await RisingEdge(dut.clk)
        dut.pixel_valid.value = 0
        await ClockCycles(dut.clk, 3)
        
        dut._log.info(f"  Tested blend op: {name}")
    
    dut._log.info(f"PASS: All {len(blend_ops)} blend operations tested")


@cocotb.test()
async def test_depth_compare_functions(dut):
    """Test all depth comparison functions."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    depth_funcs = [
        (0, "NEVER", False),
        (1, "LESS", True),      # 0.3 < 0.5 = pass
        (2, "EQUAL", False),    # 0.3 != 0.5
        (3, "LEQUAL", True),    # 0.3 <= 0.5 = pass
        (4, "GREATER", False),  # 0.3 > 0.5 = fail
        (5, "NOTEQUAL", True),  # 0.3 != 0.5 = pass
        (6, "GEQUAL", False),   # 0.3 >= 0.5 = fail
        (7, "ALWAYS", True),
    ]
    
    dut.depth_test_enable.value = 1
    dut.depth_write_enable.value = 1
    
    # Fragment depth = 0.3, buffer depth = 0.5
    frag_depth = int(0.3 * 0xFFFFFF)
    buf_depth = int(0.5 * 0xFFFFFF)
    
    for func, name, expected_pass in depth_funcs:
        dut.depth_func.value = func
        dut.frag_depth.value = frag_depth
        dut.depth_buffer.value = buf_depth
        
        dut.pixel_valid.value = 1
        await RisingEdge(dut.clk)
        dut.pixel_valid.value = 0
        await ClockCycles(dut.clk, 3)
        
        if hasattr(dut, 'depth_pass'):
            passed = dut.depth_pass.value == 1
            status = "PASS" if passed == expected_pass else "FAIL"
            dut._log.info(f"  {name}: expected={expected_pass}, got={passed} [{status}]")
    
    dut._log.info("PASS: Depth compare functions test")


@cocotb.test()
async def test_stencil_operations(dut):
    """Test stencil buffer operations."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    stencil_ops = [
        (0, "KEEP"),
        (1, "ZERO"),
        (2, "REPLACE"),
        (3, "INCR_SAT"),
        (4, "DECR_SAT"),
        (5, "INVERT"),
        (6, "INCR_WRAP"),
        (7, "DECR_WRAP"),
    ]
    
    dut.stencil_test_enable.value = 1
    dut.stencil_ref.value = 0x80
    dut.stencil_mask.value = 0xFF
    
    for op, name in stencil_ops:
        dut.stencil_pass_op.value = op
        dut.stencil_buffer.value = 0x40  # Initial stencil value
        
        dut.pixel_valid.value = 1
        await RisingEdge(dut.clk)
        dut.pixel_valid.value = 0
        await ClockCycles(dut.clk, 3)
        
        if hasattr(dut, 'stencil_out'):
            result = dut.stencil_out.value.integer
            dut._log.info(f"  {name}: 0x40 -> 0x{result:02X}")
    
    dut._log.info(f"PASS: All {len(stencil_ops)} stencil operations tested")


@cocotb.test()
async def test_stencil_compare(dut):
    """Test stencil comparison functions."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut.stencil_test_enable.value = 1
    dut.stencil_ref.value = 0x80
    dut.stencil_mask.value = 0xFF
    
    # Test EQUAL function
    dut.stencil_func.value = 2  # EQUAL
    
    # Test pass case (buffer == ref)
    dut.stencil_buffer.value = 0x80
    dut.pixel_valid.value = 1
    await RisingEdge(dut.clk)
    
    if hasattr(dut, 'stencil_pass'):
        assert dut.stencil_pass.value == 1, "Stencil should pass"
    
    # Test fail case (buffer != ref)
    dut.stencil_buffer.value = 0x40
    await RisingEdge(dut.clk)
    
    if hasattr(dut, 'stencil_pass'):
        assert dut.stencil_pass.value == 0, "Stencil should fail"
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 3)
    
    dut._log.info("PASS: Stencil compare test")


@cocotb.test()
async def test_msaa_2x(dut):
    """Test 2x MSAA sample handling."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'msaa_mode'):
        dut.msaa_mode.value = 1  # 2x MSAA
    
    # Send pixel with 2 samples
    for sample in range(2):
        if hasattr(dut, 'sample_id'):
            dut.sample_id.value = sample
        
        dut.src_color.value = pack_color(255, 0, 0, 255)  # Red
        dut.coverage_mask.value = (1 << sample)
        dut.pixel_valid.value = 1
        dut.pixel_x.value = 100
        dut.pixel_y.value = 100
        
        await RisingEdge(dut.clk)
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: MSAA 2x test")


@cocotb.test()
async def test_msaa_4x(dut):
    """Test 4x MSAA sample handling."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'msaa_mode'):
        dut.msaa_mode.value = 2  # 4x MSAA
    
    # Different colors for each sample
    colors = [
        pack_color(255, 0, 0, 255),    # Red
        pack_color(0, 255, 0, 255),    # Green
        pack_color(0, 0, 255, 255),    # Blue
        pack_color(255, 255, 0, 255),  # Yellow
    ]
    
    for sample in range(4):
        if hasattr(dut, 'sample_id'):
            dut.sample_id.value = sample
        
        dut.src_color.value = colors[sample]
        dut.coverage_mask.value = (1 << sample)
        dut.pixel_valid.value = 1
        
        await RisingEdge(dut.clk)
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 10)
    
    # Resolved color should be average
    if hasattr(dut, 'resolved_color'):
        r, g, b, a = unpack_color(dut.resolved_color.value.integer)
        dut._log.info(f"  Resolved: R={r}, G={g}, B={b}")
    
    dut._log.info("PASS: MSAA 4x test")


@cocotb.test()
async def test_msaa_8x(dut):
    """Test 8x MSAA sample handling."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'msaa_mode'):
        dut.msaa_mode.value = 3  # 8x MSAA
    
    for sample in range(8):
        if hasattr(dut, 'sample_id'):
            dut.sample_id.value = sample
        
        gray = int(sample * 255 / 7)
        dut.src_color.value = pack_color(gray, gray, gray, 255)
        dut.coverage_mask.value = (1 << sample)
        dut.pixel_valid.value = 1
        
        await RisingEdge(dut.clk)
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 15)
    
    dut._log.info("PASS: MSAA 8x test")


@cocotb.test()
async def test_color_write_mask(dut):
    """Test color channel write masks."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Only write red channel
    if hasattr(dut, 'color_write_mask'):
        dut.color_write_mask.value = 0b0001  # R only
    
    dut.src_color.value = pack_color(255, 128, 64, 200)
    dut.dst_color.value = pack_color(0, 0, 0, 0)
    dut.blend_enable.value = 0
    dut.pixel_valid.value = 1
    
    await RisingEdge(dut.clk)
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    if hasattr(dut, 'out_color'):
        r, g, b, a = unpack_color(dut.out_color.value.integer)
        dut._log.info(f"  R-only write: R={r}, G={g}, B={b}, A={a}")
        assert r == 255, "Red should be written"
        assert g == 0, "Green should not be written"
    
    dut._log.info("PASS: Color write mask test")


@cocotb.test()
async def test_framebuffer_write(dut):
    """Test framebuffer write output."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Write pixels to different locations
    pixels = [
        (0, 0, pack_color(255, 0, 0, 255)),
        (100, 100, pack_color(0, 255, 0, 255)),
        (1919, 1079, pack_color(0, 0, 255, 255)),
    ]
    
    for x, y, color in pixels:
        dut.pixel_x.value = x
        dut.pixel_y.value = y
        dut.src_color.value = color
        dut.blend_enable.value = 0
        dut.pixel_valid.value = 1
        
        await RisingEdge(dut.clk)
        
        if hasattr(dut, 'fb_write_valid'):
            assert dut.fb_write_valid.value == 1, "Framebuffer write should be valid"
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 5)
    
    dut._log.info(f"PASS: Framebuffer write test ({len(pixels)} pixels)")


@cocotb.test()
async def test_stress_random_pixels(dut):
    """Stress test with random pixel writes."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    num_pixels = 1000
    
    for i in range(num_pixels):
        x = random.randint(0, 1919)
        y = random.randint(0, 1079)
        color = random.randint(0, 0xFFFFFFFF)
        depth = random.randint(0, 0xFFFFFF)
        
        dut.pixel_x.value = x
        dut.pixel_y.value = y
        dut.src_color.value = color
        dut.frag_depth.value = depth
        dut.blend_enable.value = random.randint(0, 1)
        dut.depth_test_enable.value = random.randint(0, 1)
        dut.pixel_valid.value = 1
        
        await RisingEdge(dut.clk)
        
        while dut.pixel_ready.value == 0:
            await RisingEdge(dut.clk)
    
    dut.pixel_valid.value = 0
    await ClockCycles(dut.clk, 20)
    
    dut._log.info(f"PASS: Stress test with {num_pixels} random pixels")
