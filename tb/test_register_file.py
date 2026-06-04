import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CORE_REQUEST = 3
CORE_UPDATE  = 6

REG_INPUT_ARITHMETIC = 0
REG_INPUT_MEMORY     = 1
REG_INPUT_CONSTANT   = 2


async def reset_dut(dut):

    dut.enable.value = 0
    dut.reset.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


async def write_register(
    dut,
    rd,
    value,
    source_mux
):

    dut.enable.value = 1

    dut.decoded_rd_address.value = rd
    dut.decoded_reg_write_enable.value = 1
    dut.decoded_reg_input_mux.value = source_mux

    if source_mux == REG_INPUT_ARITHMETIC:
        dut.alu_out.value = value

    elif source_mux == REG_INPUT_MEMORY:
        dut.lsu_out.value = value

    elif source_mux == REG_INPUT_CONSTANT:
        dut.decoded_immediate.value = value

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    dut.decoded_reg_write_enable.value = 0


async def read_register(
    dut,
    rs_addr,
    rt_addr
):

    dut.decoded_rs_address.value = rs_addr
    dut.decoded_rt_address.value = rt_addr

    dut.core_state.value = CORE_REQUEST

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    return (
        int(dut.rs.value),
        int(dut.rt.value)
    )


@cocotb.test()
async def test_reset_state(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    assert int(dut.rs.value) == 0
    assert int(dut.rt.value) == 0


@cocotb.test()
async def test_special_registers(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    rs, rt = await read_register(
        dut,
        14,
        15
    )

    assert rs == 4
    assert rt == 0


@cocotb.test()
async def test_constant_write(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    await write_register(
        dut,
        rd=0,
        value=55,
        source_mux=REG_INPUT_CONSTANT
    )

    rs, _ = await read_register(
        dut,
        0,
        0
    )

    assert rs == 55


@cocotb.test()
async def test_alu_write(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    await write_register(
        dut,
        rd=1,
        value=99,
        source_mux=REG_INPUT_ARITHMETIC
    )

    rs, _ = await read_register(
        dut,
        1,
        1
    )

    assert rs == 99


@cocotb.test()
async def test_memory_write(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    await write_register(
        dut,
        rd=2,
        value=77,
        source_mux=REG_INPUT_MEMORY
    )

    rs, _ = await read_register(
        dut,
        2,
        2
    )

    assert rs == 77


@cocotb.test()
async def test_read_only_register_protection(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    await write_register(
        dut,
        rd=14,
        value=123,
        source_mux=REG_INPUT_CONSTANT
    )

    rs, _ = await read_register(
        dut,
        14,
        14
    )

    assert rs == 4


@cocotb.test()
async def test_block_id_update(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1
    dut.block_id.value = 9

    await RisingEdge(dut.clk)

    rs, _ = await read_register(
        dut,
        13,
        13
    )

    assert rs == 9


@cocotb.test()
async def test_write_disabled(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 1

    dut.decoded_rd_address.value = 0
    dut.decoded_reg_write_enable.value = 0
    dut.decoded_reg_input_mux.value = REG_INPUT_CONSTANT
    dut.decoded_immediate.value = 88

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    rs, _ = await read_register(
        dut,
        0,
        0
    )

    assert rs == 0


@cocotb.test()
async def test_enable_gating(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.enable.value = 0

    dut.decoded_rd_address.value = 0
    dut.decoded_reg_write_enable.value = 1
    dut.decoded_reg_input_mux.value = REG_INPUT_CONSTANT
    dut.decoded_immediate.value = 66

    dut.core_state.value = CORE_UPDATE

    await RisingEdge(dut.clk)

    dut.enable.value = 1

    rs, _ = await read_register(
        dut,
        0,
        0
    )

    assert rs == 0