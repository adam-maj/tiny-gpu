import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CORE_IDLE    = 0
CORE_FETCH   = 1
CORE_DECODE  = 2
CORE_REQUEST = 3
CORE_WAIT    = 4
CORE_EXECUTE = 5
CORE_UPDATE  = 6
CORE_DONE    = 7

FETCHER_IDLE     = 0
FETCHER_FETCHING = 1
FETCHER_FETCHED  = 2

LSU_IDLE = 0


async def reset_dut(dut):

    dut.start.value = 0
    dut.reset.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    assert int(dut.core_state.value) == CORE_IDLE
    assert int(dut.current_pc.value) == 0
    assert int(dut.done.value) == 0


@cocotb.test()
async def test_idle_to_fetch(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_FETCH


@cocotb.test()
async def test_fetch_to_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.fetcher_state.value = FETCHER_FETCHED

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_DECODE


@cocotb.test()
async def test_pipeline_without_memory_access(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    await RisingEdge(dut.clk)

    dut.fetcher_state.value = FETCHER_FETCHED

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_DECODE

    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_REQUEST

    dut.decoded_mem_read_enable.value = 0
    dut.decoded_mem_write_enable.value = 0

    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_EXECUTE

    await RisingEdge(dut.clk)

    assert int(dut.core_state.value) == CORE_UPDATE


@cocotb.test()
async def test_done_transition(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    await RisingEdge(dut.clk)

    dut.fetcher_state.value = FETCHER_FETCHED

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.decoded_ret.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.done.value) == 1