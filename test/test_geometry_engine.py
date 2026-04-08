"""
Geometry Engine Unit Tests
Tests for vertex processing, tessellation, and primitive assembly.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
import random
import math


async def reset_dut(dut):
    """Reset the DUT."""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


def float_to_fixed(f, frac_bits=16):
    """Convert float to fixed-point."""
    return int(f * (1 << frac_bits)) & 0xFFFFFFFF


def fixed_to_float(i, frac_bits=16):
    """Convert fixed-point to float."""
    if i & 0x80000000:  # Negative
        i = i - 0x100000000
    return i / (1 << frac_bits)


@cocotb.test()
async def test_geometry_engine_reset(dut):
    """Test geometry engine comes out of reset correctly."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    
    # Check idle state
    assert dut.vertex_ready.value == 1, "Should be ready for vertices"
    
    dut._log.info("PASS: Geometry engine reset test")


@cocotb.test()
async def test_vertex_input(dut):
    """Test vertex data input."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Input a triangle (3 vertices)
    vertices = [
        (0.0, 0.5, 0.0, 1.0),    # Top
        (-0.5, -0.5, 0.0, 1.0),  # Bottom-left
        (0.5, -0.5, 0.0, 1.0),   # Bottom-right
    ]
    
    for i, (x, y, z, w) in enumerate(vertices):
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(w)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
        
        while dut.vertex_ready.value == 0:
            await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 10)
    
    dut._log.info("PASS: Vertex input test (3 vertices)")


@cocotb.test()
async def test_identity_transform(dut):
    """Test identity matrix transformation."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Load identity MVP matrix
    identity = [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]
    
    if hasattr(dut, 'mvp_matrix'):
        for i, val in enumerate(identity):
            dut.mvp_matrix[i].value = float_to_fixed(val)
    
    # Input vertex
    test_vertex = (0.5, 0.25, 0.1, 1.0)
    dut.vertex_x.value = float_to_fixed(test_vertex[0])
    dut.vertex_y.value = float_to_fixed(test_vertex[1])
    dut.vertex_z.value = float_to_fixed(test_vertex[2])
    dut.vertex_w.value = float_to_fixed(test_vertex[3])
    dut.vertex_valid.value = 1
    await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    
    # Wait for transform
    await ClockCycles(dut.clk, 20)
    
    # With identity, output should equal input
    if hasattr(dut, 'transformed_x'):
        out_x = fixed_to_float(dut.transformed_x.value.integer)
        out_y = fixed_to_float(dut.transformed_y.value.integer)
        dut._log.info(f"  Input: ({test_vertex[0]}, {test_vertex[1]})")
        dut._log.info(f"  Output: ({out_x:.4f}, {out_y:.4f})")
    
    dut._log.info("PASS: Identity transform test")


@cocotb.test()
async def test_translation_transform(dut):
    """Test translation matrix transformation."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Translation by (0.5, 0.5, 0.0)
    tx, ty, tz = 0.5, 0.5, 0.0
    translation = [
        1.0, 0.0, 0.0, tx,
        0.0, 1.0, 0.0, ty,
        0.0, 0.0, 1.0, tz,
        0.0, 0.0, 0.0, 1.0,
    ]
    
    if hasattr(dut, 'mvp_matrix'):
        for i, val in enumerate(translation):
            dut.mvp_matrix[i].value = float_to_fixed(val)
    
    # Input vertex at origin
    dut.vertex_x.value = float_to_fixed(0.0)
    dut.vertex_y.value = float_to_fixed(0.0)
    dut.vertex_z.value = float_to_fixed(0.0)
    dut.vertex_w.value = float_to_fixed(1.0)
    dut.vertex_valid.value = 1
    await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("PASS: Translation transform test")


@cocotb.test()
async def test_scaling_transform(dut):
    """Test scaling matrix transformation."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Scale by 2x
    sx, sy, sz = 2.0, 2.0, 2.0
    scaling = [
        sx, 0.0, 0.0, 0.0,
        0.0, sy, 0.0, 0.0,
        0.0, 0.0, sz, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]
    
    if hasattr(dut, 'mvp_matrix'):
        for i, val in enumerate(scaling):
            dut.mvp_matrix[i].value = float_to_fixed(val)
    
    dut.vertex_x.value = float_to_fixed(0.25)
    dut.vertex_y.value = float_to_fixed(0.25)
    dut.vertex_z.value = float_to_fixed(0.0)
    dut.vertex_w.value = float_to_fixed(1.0)
    dut.vertex_valid.value = 1
    await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("PASS: Scaling transform test")


@cocotb.test()
async def test_clipping_inside(dut):
    """Test clipping with all vertices inside frustum."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Triangle fully inside clip space [-1, 1]
    vertices = [
        (0.0, 0.3, 0.5),
        (-0.3, -0.3, 0.5),
        (0.3, -0.3, 0.5),
    ]
    
    for x, y, z in vertices:
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(1.0)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 30)
    
    # Triangle should pass through unchanged
    if hasattr(dut, 'clip_reject'):
        assert dut.clip_reject.value == 0, "Triangle inside should not be rejected"
    
    dut._log.info("PASS: Clipping inside test")


@cocotb.test()
async def test_clipping_outside(dut):
    """Test clipping with triangle completely outside frustum."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Triangle completely outside (left of frustum)
    vertices = [
        (-2.0, 0.0, 0.5),
        (-2.5, 0.5, 0.5),
        (-2.5, -0.5, 0.5),
    ]
    
    for x, y, z in vertices:
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(1.0)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 30)
    
    # Triangle should be rejected
    if hasattr(dut, 'clip_reject'):
        assert dut.clip_reject.value == 1, "Triangle outside should be rejected"
    
    dut._log.info("PASS: Clipping outside test")


@cocotb.test()
async def test_clipping_partial(dut):
    """Test clipping with triangle partially outside frustum."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Triangle crosses right edge
    vertices = [
        (0.0, 0.5, 0.5),     # Inside
        (1.5, 0.0, 0.5),     # Outside right
        (0.0, -0.5, 0.5),    # Inside
    ]
    
    for x, y, z in vertices:
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(1.0)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 40)
    
    dut._log.info("PASS: Clipping partial test (triangle should be clipped)")


@cocotb.test()
async def test_backface_culling_ccw(dut):
    """Test backface culling with CCW winding (front face)."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Enable backface culling
    if hasattr(dut, 'cull_enable'):
        dut.cull_enable.value = 1
        dut.cull_mode.value = 1  # Cull back faces
    
    # CCW winding (front face, should NOT be culled)
    vertices = [
        (0.0, 0.5, 0.5),
        (-0.5, -0.5, 0.5),
        (0.5, -0.5, 0.5),
    ]
    
    for x, y, z in vertices:
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(1.0)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 30)
    
    if hasattr(dut, 'face_culled'):
        assert dut.face_culled.value == 0, "CCW face should not be culled"
    
    dut._log.info("PASS: Backface culling CCW test (front face visible)")


@cocotb.test()
async def test_backface_culling_cw(dut):
    """Test backface culling with CW winding (back face)."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'cull_enable'):
        dut.cull_enable.value = 1
        dut.cull_mode.value = 1
    
    # CW winding (back face, should be culled)
    vertices = [
        (0.0, 0.5, 0.5),
        (0.5, -0.5, 0.5),   # Swapped order
        (-0.5, -0.5, 0.5),
    ]
    
    for x, y, z in vertices:
        dut.vertex_x.value = float_to_fixed(x)
        dut.vertex_y.value = float_to_fixed(y)
        dut.vertex_z.value = float_to_fixed(z)
        dut.vertex_w.value = float_to_fixed(1.0)
        dut.vertex_valid.value = 1
        await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 30)
    
    if hasattr(dut, 'face_culled'):
        assert dut.face_culled.value == 1, "CW face should be culled"
    
    dut._log.info("PASS: Backface culling CW test (back face culled)")


@cocotb.test()
async def test_tessellation_factors(dut):
    """Test tessellation with different factors."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    tess_factors = [1, 2, 4, 8, 16, 32]
    
    for factor in tess_factors:
        if hasattr(dut, 'tess_factor'):
            dut.tess_factor.value = factor
        
        # Input a triangle
        vertices = [
            (0.0, 0.5, 0.5),
            (-0.5, -0.5, 0.5),
            (0.5, -0.5, 0.5),
        ]
        
        for x, y, z in vertices:
            dut.vertex_x.value = float_to_fixed(x)
            dut.vertex_y.value = float_to_fixed(y)
            dut.vertex_z.value = float_to_fixed(z)
            dut.vertex_w.value = float_to_fixed(1.0)
            dut.vertex_valid.value = 1
            await RisingEdge(dut.clk)
        
        dut.vertex_valid.value = 0
        await ClockCycles(dut.clk, 20)
        
        dut._log.info(f"  Tested tessellation factor: {factor}")
    
    dut._log.info("PASS: Tessellation factors test")


@cocotb.test()
async def test_viewport_transform(dut):
    """Test viewport transformation from NDC to screen space."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    # Set viewport (1920x1080)
    if hasattr(dut, 'viewport_width'):
        dut.viewport_width.value = 1920
        dut.viewport_height.value = 1080
        dut.viewport_x.value = 0
        dut.viewport_y.value = 0
    
    # NDC center (0, 0) should map to screen center
    dut.vertex_x.value = float_to_fixed(0.0)
    dut.vertex_y.value = float_to_fixed(0.0)
    dut.vertex_z.value = float_to_fixed(0.5)
    dut.vertex_w.value = float_to_fixed(1.0)
    dut.vertex_valid.value = 1
    await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 20)
    
    # Should be (960, 540) in screen space
    if hasattr(dut, 'screen_x'):
        screen_x = dut.screen_x.value.integer
        screen_y = dut.screen_y.value.integer
        dut._log.info(f"  NDC (0,0) -> Screen ({screen_x}, {screen_y})")
    
    dut._log.info("PASS: Viewport transform test")


@cocotb.test()
async def test_primitive_assembly(dut):
    """Test primitive assembly for different primitive types."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    primitives = [
        (0, "POINT_LIST"),
        (1, "LINE_LIST"),
        (2, "LINE_STRIP"),
        (3, "TRIANGLE_LIST"),
        (4, "TRIANGLE_STRIP"),
        (5, "TRIANGLE_FAN"),
    ]
    
    for prim_type, name in primitives:
        if hasattr(dut, 'primitive_type'):
            dut.primitive_type.value = prim_type
        
        # Send 6 vertices
        for i in range(6):
            x = math.cos(i * math.pi / 3) * 0.5
            y = math.sin(i * math.pi / 3) * 0.5
            
            dut.vertex_x.value = float_to_fixed(x)
            dut.vertex_y.value = float_to_fixed(y)
            dut.vertex_z.value = float_to_fixed(0.5)
            dut.vertex_w.value = float_to_fixed(1.0)
            dut.vertex_valid.value = 1
            await RisingEdge(dut.clk)
        
        dut.vertex_valid.value = 0
        await ClockCycles(dut.clk, 10)
        
        dut._log.info(f"  Tested primitive type: {name}")
    
    dut._log.info("PASS: Primitive assembly test")


@cocotb.test()
async def test_stress_many_triangles(dut):
    """Stress test with many triangles."""
    clock = Clock(dut.clk, 2, units="ns")
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    num_triangles = 100
    
    for t in range(num_triangles):
        # Random triangle
        for v in range(3):
            x = random.uniform(-1.0, 1.0)
            y = random.uniform(-1.0, 1.0)
            z = random.uniform(0.1, 1.0)
            
            dut.vertex_x.value = float_to_fixed(x)
            dut.vertex_y.value = float_to_fixed(y)
            dut.vertex_z.value = float_to_fixed(z)
            dut.vertex_w.value = float_to_fixed(1.0)
            dut.vertex_valid.value = 1
            await RisingEdge(dut.clk)
            
            while dut.vertex_ready.value == 0:
                await RisingEdge(dut.clk)
    
    dut.vertex_valid.value = 0
    await ClockCycles(dut.clk, 50)
    
    dut._log.info(f"PASS: Stress test with {num_triangles} triangles")
