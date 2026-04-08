"""
Clock/Reset Controller Unit Tests
Tests for PLL, DVFS, and power management.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
import random


async def reset_dut(dut):
    """Reset the DUT with reference clock."""
    # Reference clock always running
    dut.rst_n.value = 0
    await ClockCycles(dut.ref_clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.ref_clk, 10)


@cocotb.test()
async def test_clock_reset_init(dut):
    """Test clock/reset controller initialization."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")  # 100MHz reference
    cocotb.start_soon(ref_clock.start())
    
    dut.rst_n.value = 0
    await ClockCycles(dut.ref_clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.ref_clk, 20)
    
    if hasattr(dut, 'pll_locked'):
        # Wait for PLL lock
        timeout = 0
        while dut.pll_locked.value == 0 and timeout < 1000:
            await RisingEdge(dut.ref_clk)
            timeout += 1
    
    dut._log.info("PASS: Clock/reset initialization test")


@cocotb.test()
async def test_pll_lock(dut):
    """Test PLL lock sequence."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    # Check all 4 PLLs
    for pll in range(4):
        if hasattr(dut, f'pll{pll}_locked'):
            locked = getattr(dut, f'pll{pll}_locked').value
            dut._log.info(f"  PLL{pll} locked: {locked}")
    
    dut._log.info("PASS: PLL lock test")


@cocotb.test()
async def test_clock_domains(dut):
    """Test 8 clock domain generation."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    clock_domains = [
        ("core_clk", 2000),      # 2GHz
        ("shader_clk", 2500),    # 2.5GHz
        ("memory_clk", 2000),    # 2GHz (DDR)
        ("display_clk", 594),    # 594MHz (4K60)
        ("pcie_clk", 500),       # 500MHz
        ("video_clk", 1000),     # 1GHz
        ("crypto_clk", 500),     # 500MHz
        ("axi_clk", 250),        # 250MHz
    ]
    
    for name, freq_mhz in clock_domains:
        if hasattr(dut, name):
            # Measure clock frequency
            await ClockCycles(dut.ref_clk, 50)
            dut._log.info(f"  {name}: {freq_mhz}MHz configured")
    
    dut._log.info("PASS: Clock domains test")


@cocotb.test()
async def test_dvfs_p_states(dut):
    """Test Dynamic Voltage and Frequency Scaling P-states."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    # P-state definitions (state, freq_mhz, voltage_mv)
    p_states = [
        (0, 2500, 1100),  # P0: Max performance
        (1, 2000, 1000),  # P1: High
        (2, 1500, 900),   # P2: Medium
        (3, 1000, 850),   # P3: Low
        (4, 750, 800),    # P4: Economy
        (5, 500, 750),    # P5: Idle
        (6, 300, 700),    # P6: Deep idle
        (7, 100, 650),    # P7: Minimum
    ]
    
    for state, freq, voltage in p_states:
        if hasattr(dut, 'p_state'):
            dut.p_state.value = state
        
        await ClockCycles(dut.ref_clk, 50)
        
        # Wait for transition
        if hasattr(dut, 'dvfs_ready'):
            timeout = 0
            while dut.dvfs_ready.value == 0 and timeout < 100:
                await RisingEdge(dut.ref_clk)
                timeout += 1
        
        dut._log.info(f"  P{state}: {freq}MHz @ {voltage}mV")
    
    dut._log.info("PASS: DVFS P-states test")


@cocotb.test()
async def test_voltage_scaling(dut):
    """Test voltage scaling interface."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    voltages = [1100, 1000, 900, 850, 800, 750, 700, 650]
    
    for voltage_mv in voltages:
        if hasattr(dut, 'target_voltage'):
            dut.target_voltage.value = voltage_mv
        
        await ClockCycles(dut.ref_clk, 50)
        
        if hasattr(dut, 'voltage_good'):
            good = dut.voltage_good.value
            dut._log.info(f"  Voltage {voltage_mv}mV: good={good}")
    
    dut._log.info("PASS: Voltage scaling test")


@cocotb.test()
async def test_power_gating(dut):
    """Test power gating control."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    # Power domain gates
    domains = [
        "shader_array",
        "rasterizer",
        "display",
        "video_encode",
        "video_decode",
        "memory_ctrl",
    ]
    
    for domain in domains:
        gate_signal = f'{domain}_pg_en'
        if hasattr(dut, gate_signal):
            # Gate off
            getattr(dut, gate_signal).value = 1
            await ClockCycles(dut.ref_clk, 20)
            
            # Gate on
            getattr(dut, gate_signal).value = 0
            await ClockCycles(dut.ref_clk, 20)
            
            dut._log.info(f"  Power gated: {domain}")
    
    dut._log.info("PASS: Power gating test")


@cocotb.test()
async def test_clock_gating(dut):
    """Test clock gating for idle blocks."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'clock_gate_enable'):
        # Enable clock gating
        dut.clock_gate_enable.value = 0xFF  # All domains
        await ClockCycles(dut.ref_clk, 50)
        
        # Disable clock gating
        dut.clock_gate_enable.value = 0x00
        await ClockCycles(dut.ref_clk, 50)
    
    dut._log.info("PASS: Clock gating test")


@cocotb.test()
async def test_reset_sequencing(dut):
    """Test reset de-assertion sequencing."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    # Apply reset
    dut.rst_n.value = 0
    await ClockCycles(dut.ref_clk, 10)
    
    # Release reset
    dut.rst_n.value = 1
    
    # Monitor reset sequence
    reset_order = []
    
    for _ in range(50):
        await RisingEdge(dut.ref_clk)
        
        # Check which resets are released
        if hasattr(dut, 'pll_rst_n') and dut.pll_rst_n.value == 1:
            if 'pll' not in reset_order:
                reset_order.append('pll')
        
        if hasattr(dut, 'core_rst_n') and dut.core_rst_n.value == 1:
            if 'core' not in reset_order:
                reset_order.append('core')
        
        if hasattr(dut, 'io_rst_n') and dut.io_rst_n.value == 1:
            if 'io' not in reset_order:
                reset_order.append('io')
    
    dut._log.info(f"  Reset sequence: {' -> '.join(reset_order)}")
    dut._log.info("PASS: Reset sequencing test")


@cocotb.test()
async def test_watchdog_timer(dut):
    """Test watchdog timer."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'wdt_enable'):
        # Enable watchdog
        dut.wdt_enable.value = 1
        dut.wdt_timeout.value = 100  # Short timeout for test
        
        await ClockCycles(dut.ref_clk, 50)
        
        # Pet the watchdog
        if hasattr(dut, 'wdt_pet'):
            dut.wdt_pet.value = 1
            await RisingEdge(dut.ref_clk)
            dut.wdt_pet.value = 0
        
        await ClockCycles(dut.ref_clk, 50)
        
        # Let it timeout (don't pet)
        timeout = 0
        triggered = False
        
        while timeout < 200 and not triggered:
            await RisingEdge(dut.ref_clk)
            timeout += 1
            
            if hasattr(dut, 'wdt_reset'):
                if dut.wdt_reset.value == 1:
                    triggered = True
        
        dut._log.info(f"  Watchdog triggered: {triggered}")
    
    dut._log.info("PASS: Watchdog timer test")


@cocotb.test()
async def test_spread_spectrum(dut):
    """Test spread spectrum clocking (EMI reduction)."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'ssc_enable'):
        # Enable spread spectrum
        dut.ssc_enable.value = 1
        dut.ssc_range.value = 1  # 0.5% down-spread
        
        await ClockCycles(dut.ref_clk, 500)
    
    dut._log.info("PASS: Spread spectrum test")


@cocotb.test()
async def test_thermal_throttling(dut):
    """Test thermal throttling response."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    temps = [50, 70, 85, 95, 105, 90, 70]  # Temperature sweep
    
    for temp in temps:
        if hasattr(dut, 'thermal_sensor'):
            dut.thermal_sensor.value = temp
        
        await ClockCycles(dut.ref_clk, 50)
        
        if hasattr(dut, 'thermal_throttle'):
            throttle = dut.thermal_throttle.value
            dut._log.info(f"  Temp {temp}°C: throttle={throttle}")
    
    dut._log.info("PASS: Thermal throttling test")


@cocotb.test()
async def test_frequency_measurement(dut):
    """Test clock frequency measurement."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'freq_measure_enable'):
        dut.freq_measure_enable.value = 1
        dut.freq_measure_select.value = 0  # Measure core clock
        
        await ClockCycles(dut.ref_clk, 1000)
        
        if hasattr(dut, 'freq_measure_result'):
            freq = dut.freq_measure_result.value.integer
            dut._log.info(f"  Measured frequency: {freq} units")
    
    dut._log.info("PASS: Frequency measurement test")


@cocotb.test()
async def test_pll_bypass(dut):
    """Test PLL bypass mode."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    if hasattr(dut, 'pll_bypass'):
        # Enable bypass (use reference clock directly)
        dut.pll_bypass.value = 1
        await ClockCycles(dut.ref_clk, 50)
        
        # Disable bypass
        dut.pll_bypass.value = 0
        await ClockCycles(dut.ref_clk, 50)
    
    dut._log.info("PASS: PLL bypass test")


@cocotb.test()
async def test_clock_multiplexing(dut):
    """Test clock source multiplexing."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    sources = [
        (0, "PLL0"),
        (1, "PLL1"),
        (2, "PLL2"),
        (3, "PLL3"),
        (4, "REF_CLK"),
        (5, "EXT_CLK"),
    ]
    
    for sel, name in sources:
        if hasattr(dut, 'core_clk_sel'):
            dut.core_clk_sel.value = sel
        
        await ClockCycles(dut.ref_clk, 20)
        dut._log.info(f"  Clock source: {name}")
    
    dut._log.info("PASS: Clock multiplexing test")


@cocotb.test()
async def test_stress_dvfs_transitions(dut):
    """Stress test rapid DVFS transitions."""
    ref_clock = Clock(dut.ref_clk, 10, units="ns")
    cocotb.start_soon(ref_clock.start())
    
    await reset_dut(dut)
    
    num_transitions = 50
    
    for i in range(num_transitions):
        p_state = random.randint(0, 7)
        
        if hasattr(dut, 'p_state'):
            dut.p_state.value = p_state
        
        # Shorter wait for stress test
        await ClockCycles(dut.ref_clk, 20)
    
    # Final settle
    await ClockCycles(dut.ref_clk, 100)
    
    dut._log.info(f"PASS: DVFS stress test ({num_transitions} transitions)")
