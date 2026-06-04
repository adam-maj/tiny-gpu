import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CORE_EXECUTE = 5
CORE_UPDATE  = 6


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

    assert int(dut.next_pc.value) == 0


@cocotb.test()
async def test_sequential_pc_increment(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.current_pc.value = 10

    dut.decoded_pc_mux.value = 0

    dut.core_state.value = CORE_EXECUTE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.next_pc.value) == 11


@cocotb.test()
async def test_branch_taken(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    #
    # Set NZP = Positive
    #
    dut.enable.value = 1

    dut.decoded_nzp_write_enable.value = 1
    dut.alu_out.value = 0b100

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    #
    # Execute branch
    #
    dut.decoded_nzp_write_enable.value = 0

    dut.current_pc.value = 20

    dut.decoded_pc_mux.value = 1
    dut.decoded_nzp.value = 0b100
    dut.decoded_immediate.value = 77

    dut.core_state.value = CORE_EXECUTE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.next_pc.value) == 77


@cocotb.test()
async def test_branch_not_taken(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    #
    # Set NZP = Positive
    #
    dut.enable.value = 1

    dut.decoded_nzp_write_enable.value = 1
    dut.alu_out.value = 0b100

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    #
    # Request Negative branch
    #
    dut.decoded_nzp_write_enable.value = 0

    dut.current_pc.value = 20

    dut.decoded_pc_mux.value = 1
    dut.decoded_nzp.value = 0b001
    dut.decoded_immediate.value = 77

    dut.core_state.value = CORE_EXECUTE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.next_pc.value) == 21


@cocotb.test()
async def test_nzp_negative(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_nzp_write_enable.value = 1
    dut.alu_out.value = 0b001

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    dut.current_pc.value = 50

    dut.decoded_pc_mux.value = 1
    dut.decoded_nzp.value = 0b001
    dut.decoded_immediate.value = 99

    dut.core_state.value = CORE_EXECUTE

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.next_pc.value) == 99


@cocotb.test()
async def test_enable_gating(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 0

    dut.current_pc.value = 33

    dut.decoded_pc_mux.value = 0

    dut.core_state.value = CORE_EXECUTE

    await RisingEdge(dut.clk)

    assert int(dut.next_pc.value) == 0