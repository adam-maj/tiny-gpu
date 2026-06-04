import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CORE_REQUEST = 3
CORE_UPDATE  = 6

LSU_IDLE       = 0
LSU_REQUESTING = 1
LSU_WAITING    = 2
LSU_DONE       = 3


async def reset_dut(dut):

    dut.enable.value = 0
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

    assert int(dut.lsu_state.value) == LSU_IDLE
    assert int(dut.lsu_out.value) == 0


@cocotb.test()
async def test_load_transaction(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_mem_read_enable.value = 1
    dut.decoded_mem_write_enable.value = 0

    dut.rs.value = 25

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_REQUESTING

    await RisingEdge(dut.clk)

    assert int(dut.mem_read_valid.value) == 1
    assert int(dut.mem_read_address.value) == 25
    assert int(dut.lsu_state.value) == LSU_WAITING

    dut.mem_read_data.value = 123
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_out.value) == 123
    assert int(dut.lsu_state.value) == LSU_DONE


@cocotb.test()
async def test_store_transaction(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_mem_read_enable.value = 0
    dut.decoded_mem_write_enable.value = 1

    dut.rs.value = 50
    dut.rt.value = 77

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_REQUESTING

    await RisingEdge(dut.clk)

    assert int(dut.mem_write_valid.value) == 1
    assert int(dut.mem_write_address.value) == 50
    assert int(dut.mem_write_data.value) == 77

    dut.mem_write_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_DONE


@cocotb.test()
async def test_done_to_idle_transition(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_mem_read_enable.value = 1
    dut.rs.value = 10

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.mem_read_data.value = 88
    dut.mem_read_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_DONE

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_IDLE


@cocotb.test()
async def test_no_operation(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_mem_read_enable.value = 0
    dut.decoded_mem_write_enable.value = 0

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_IDLE


@cocotb.test()
async def test_enable_gating(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 0

    dut.decoded_mem_read_enable.value = 1
    dut.rs.value = 99

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)

    assert int(dut.lsu_state.value) == LSU_IDLE