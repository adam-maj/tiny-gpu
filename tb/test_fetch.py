import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CORE_FETCH  = 1
CORE_DECODE = 2

FETCHER_IDLE      = 0
FETCHER_FETCHING  = 1
FETCHER_FETCHED   = 2


async def reset_dut(dut):

    dut.reset.value = 1

    dut.mem_read_ready.value = 0
    dut.mem_read_data.value = 0

    dut.current_pc.value = 0
    dut.core_state.value = 0

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

    assert int(dut.fetcher_state.value) == FETCHER_IDLE
    assert int(dut.mem_read_valid.value) == 0
    assert int(dut.instruction.value) == 0


@cocotb.test()
async def test_fetch_request_generation(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.current_pc.value = 25
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_FETCHING
    assert int(dut.mem_read_valid.value) == 1
    assert int(dut.mem_read_address.value) == 25


@cocotb.test()
async def test_fetch_completion(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.current_pc.value = 42
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.mem_read_data.value = 0xABCD
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_FETCHED
    assert int(dut.mem_read_valid.value) == 0
    assert int(dut.instruction.value) == 0xABCD


@cocotb.test()
async def test_return_to_idle_after_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.current_pc.value = 11
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.mem_read_data.value = 0x1234
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_FETCHED

    dut.core_state.value = CORE_DECODE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_IDLE


@cocotb.test()
async def test_wait_for_memory_response(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.mem_read_ready.value = 0

    dut.current_pc.value = 99
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_FETCHING
    assert int(dut.mem_read_valid.value) == 1


@cocotb.test()
async def test_multiple_fetches(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    #
    # First Fetch
    #

    dut.current_pc.value = 5
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.mem_read_data.value = 0xAAAA
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.instruction.value) == 0xAAAA

    dut.core_state.value = CORE_DECODE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    #
    # Second Fetch
    #

    dut.mem_read_ready.value = 0

    dut.current_pc.value = 6
    dut.core_state.value = CORE_FETCH

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.mem_read_data.value = 0xBBBB
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.instruction.value) == 0xBBBB


@cocotb.test()
async def test_no_fetch_when_not_in_fetch_state(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.mem_read_ready.value = 0

    dut.current_pc.value = 55
    dut.core_state.value = CORE_DECODE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.fetcher_state.value) == FETCHER_IDLE
    assert int(dut.mem_read_valid.value) == 0