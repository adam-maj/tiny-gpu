import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CORE_DECODE = 2

OP_NOP   = 0x0
OP_BRNZP = 0x1
OP_CMP   = 0x2
OP_ADD   = 0x3
OP_SUB   = 0x4
OP_MUL   = 0x5
OP_DIV   = 0x6
OP_LDR   = 0x7
OP_STR   = 0x8
OP_CONST = 0x9
OP_RET   = 0xF


async def reset_dut(dut):

    dut.reset.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


async def decode_instruction(dut, instruction):

    dut.core_state.value = CORE_DECODE
    dut.instruction.value = instruction

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    assert int(dut.decoded_ret.value) == 0
    assert int(dut.decoded_mem_read_enable.value) == 0
    assert int(dut.decoded_mem_write_enable.value) == 0


@cocotb.test()
async def test_add_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_ADD << 12) | (1 << 8) | (2 << 4) | 3

    await decode_instruction(dut, instr)

    assert int(dut.decoded_rd_address.value) == 1
    assert int(dut.decoded_rs_address.value) == 2
    assert int(dut.decoded_rt_address.value) == 3

    assert int(dut.decoded_reg_write_enable.value) == 1
    assert int(dut.decoded_reg_input_mux.value) == 0
    assert int(dut.decoded_alu_arithmetic_mux.value) == 0


@cocotb.test()
async def test_sub_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_SUB << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_alu_arithmetic_mux.value) == 1


@cocotb.test()
async def test_mul_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_MUL << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_alu_arithmetic_mux.value) == 2


@cocotb.test()
async def test_div_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_DIV << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_alu_arithmetic_mux.value) == 3


@cocotb.test()
async def test_cmp_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_CMP << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_alu_output_mux.value) == 1
    assert int(dut.decoded_nzp_write_enable.value) == 1


@cocotb.test()
async def test_branch_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_BRNZP << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_pc_mux.value) == 1


@cocotb.test()
async def test_ldr_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_LDR << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_reg_write_enable.value) == 1
    assert int(dut.decoded_mem_read_enable.value) == 1
    assert int(dut.decoded_reg_input_mux.value) == 1


@cocotb.test()
async def test_str_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_STR << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_mem_write_enable.value) == 1


@cocotb.test()
async def test_const_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_CONST << 12) | 0x55

    await decode_instruction(dut, instr)

    assert int(dut.decoded_reg_write_enable.value) == 1
    assert int(dut.decoded_reg_input_mux.value) == 2
    assert int(dut.decoded_immediate.value) == 0x55


@cocotb.test()
async def test_ret_decode(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    instr = (OP_RET << 12)

    await decode_instruction(dut, instr)

    assert int(dut.decoded_ret.value) == 1