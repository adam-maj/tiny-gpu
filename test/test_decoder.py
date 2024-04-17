import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.binary import BinaryValue

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

async def setup(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)


@cocotb.test()
async def test_decoder_nop(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0000" + "0000" + "0000" + "0000")  # NOP
    await RisingEdge(dut.clk)
    assert dut.decoded_done.value == 0, "NOP operation failed to not set done"

@cocotb.test()
async def test_decoder_brnzp(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0001" + "0000" + "0000" + "0000")  # BRnzp
    await RisingEdge(dut.clk)
    assert dut.decoded_pc_mux.value == 1, "BRnzp operation failed to set PC mux"

@cocotb.test()
async def test_decoder_cmp(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0010" + "0000" + "0000" + "0000")  # CMP
    await RisingEdge(dut.clk)
    assert dut.decoded_alu_output_mux.value == 1, "CMP operation failed to set ALU output mux"
    assert dut.decoded_nzp_write_enable.value == 1, "CMP operation failed to set NZP write enable"

@cocotb.test()
async def test_decoder_add(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0011" + "0000" + "0000" + "0000")  # ADD
    await RisingEdge(dut.clk)
    assert dut.decoded_alu_arithmetic_mux.value == BinaryValue("00"), "ADD operation failed to set ALU arithmetic mux"

@cocotb.test()
async def test_decoder_sub(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0100" + "0000" + "0000" + "0000")  # SUB
    await RisingEdge(dut.clk)
    assert dut.decoded_alu_arithmetic_mux.value == BinaryValue("01"), "SUB operation failed to set ALU arithmetic mux"

@cocotb.test()
async def test_decoder_mul(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0101" + "0000" + "0000" + "0000")  # MUL
    await RisingEdge(dut.clk)
    assert dut.decoded_alu_arithmetic_mux.value == BinaryValue("10"), "MUL operation failed to set ALU arithmetic mux"

@cocotb.test()
async def test_decoder_div(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0110" + "0000" + "0000" + "0000")  # DIV
    await RisingEdge(dut.clk)
    assert dut.decoded_alu_arithmetic_mux.value == BinaryValue("11"), "DIV operation failed to set ALU arithmetic mux"

@cocotb.test()
async def test_decoder_ldr(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("0111" + "0000" + "0000" + "0000")  # LDR
    await RisingEdge(dut.clk)
    assert dut.decoded_mem_read_enable.value == 1, "LDR operation failed to set memory read enable"

@cocotb.test()
async def test_decoder_str(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("1000" + "0000" + "0000" + "0000")  # STR
    await RisingEdge(dut.clk)
    assert dut.decoded_mem_write_enable.value == 1, "STR operation failed to set memory write enable"

@cocotb.test()
async def test_decoder_const(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("1001" + "0000" + "0000" + "0000")  # CONST
    await RisingEdge(dut.clk)
    assert dut.decoded_reg_input_mux.value == BinaryValue("10"), "CONST operation failed to set reg input mux"

@cocotb.test()
async def test_decoder_ret(dut):
    await setup(dut)

    dut.instruction.value = BinaryValue("1111" + "0000" + "0000" + "0000")  # RET
    await RisingEdge(dut.clk)
    assert dut.decoded_done.value == 1, "RET operation failed to set done"
