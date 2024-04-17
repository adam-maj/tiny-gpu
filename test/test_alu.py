import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.binary import BinaryValue

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

@cocotb.test()
async def test_alu_operations(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Test ADD operation
    dut.decoded_alu_arithmetic_mux.value = BinaryValue("00")
    dut.decoded_alu_output_mux = 0
    dut.rs.value = 10
    dut.rt.value = 15
    await RisingEdge(dut.clk)
    assert dut.alu_out.value == 25, f"ADD operation failed: {dut.alu_out.value} != 25"

    # Test SUB operation
    dut.decoded_alu_arithmetic_mux.value = BinaryValue("01")
    dut.rs.value = 20
    dut.rt.value = 10
    await RisingEdge(dut.clk)
    assert dut.alu_out.value == 10, f"SUB operation failed: {dut.alu_out.value} != 10"

    # Test MUL operation
    dut.decoded_alu_arithmetic_mux.value = BinaryValue("10")
    dut.rs.value = 5
    dut.rt.value = 4
    await RisingEdge(dut.clk)
    assert dut.alu_out.value == 20, f"MUL operation failed: {dut.alu_out.value} != 20"

    # Test DIV operation
    dut.decoded_alu_arithmetic_mux.value = BinaryValue("11")
    dut.rs.value = 20
    dut.rt.value = 5
    await RisingEdge(dut.clk)
    assert dut.alu_out.value == 4, f"DIV operation failed: {dut.alu_out.value} != 4"

    # Test comparison operation (CMP, assuming it sets alu_output_mux for comparison)
    # Assuming CMP sets alu_output_mux to 1 for comparison result
    dut.decoded_alu_output_mux.value = 1
    dut.rs.value = 10
    dut.rt.value = 10
    await RisingEdge(dut.clk)
    print(dut.alu_out.value)
    assert dut.alu_out.value == 0b00000010, f"CMP operation failed: {dut.alu_out.value[7:5]} != 0b010 (equal)"

