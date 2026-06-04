import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CORE_EXECUTE = 5


async def reset_dut(dut):

    dut.enable.value = 0
    dut.reset.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


async def execute_op(
    dut,
    arithmetic_mux,
    output_mux,
    rs,
    rt
):

    dut.enable.value = 1
    dut.core_state.value = CORE_EXECUTE

    dut.decoded_alu_arithmetic_mux.value = arithmetic_mux
    dut.decoded_alu_output_mux.value = output_mux

    dut.rs.value = rs
    dut.rt.value = rt

    await Timer(1, unit="ns")

    print(
        "\nAFTER DRIVE:",
        f"enable={int(dut.enable.value)}",
        f"core_state={int(dut.core_state.value)}",
        f"alu_mux={int(dut.decoded_alu_arithmetic_mux.value)}",
        f"out_mux={int(dut.decoded_alu_output_mux.value)}",
        f"rs={int(dut.rs.value)}",
        f"rt={int(dut.rt.value)}"
    )

    await RisingEdge(dut.clk)

    print(
        "AFTER FIRST CLOCK:",
        f"alu_out={int(dut.alu_out.value)}"
    )

    await RisingEdge(dut.clk)

    print(
        "AFTER SECOND CLOCK:",
        f"alu_out={int(dut.alu_out.value)}"
    )

    return int(dut.alu_out.value)


@cocotb.test()
async def test_reset(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    assert int(dut.alu_out.value) == 0


@cocotb.test()
async def test_add(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=0,
        output_mux=0,
        rs=10,
        rt=20
    )

    assert result == 30


@cocotb.test()
async def test_sub(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=1,
        output_mux=0,
        rs=50,
        rt=20
    )

    assert result == 30


@cocotb.test()
async def test_mul(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=2,
        output_mux=0,
        rs=6,
        rt=7
    )

    assert result == 42


@cocotb.test()
async def test_div(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=3,
        output_mux=0,
        rs=40,
        rt=5
    )

    assert result == 8


@cocotb.test()
async def test_div_by_zero(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=3,
        output_mux=0,
        rs=55,
        rt=0
    )

    assert result == 0


@cocotb.test()
async def test_cmp_greater(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=0,
        output_mux=1,
        rs=20,
        rt=10
    )

    assert result == 0b00000100


@cocotb.test()
async def test_cmp_equal(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=0,
        output_mux=1,
        rs=15,
        rt=15
    )

    assert result == 0b00000010


@cocotb.test()
async def test_cmp_less(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    result = await execute_op(
        dut,
        arithmetic_mux=0,
        output_mux=1,
        rs=5,
        rt=10
    )

    assert result == 0b00000001


@cocotb.test()
async def test_disabled_no_update(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 0
    dut.core_state.value = CORE_EXECUTE

    dut.decoded_alu_arithmetic_mux.value = 0
    dut.decoded_alu_output_mux.value = 0

    dut.rs.value = 100
    dut.rt.value = 100

    await RisingEdge(dut.clk)

    assert int(dut.alu_out.value) == 0