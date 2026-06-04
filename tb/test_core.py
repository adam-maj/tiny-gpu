import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

RET_INSTRUCTION = 0xF000


async def reset_dut(dut):

    dut.start.value = 0
    dut.reset.value = 1

    dut.block_id.value = 0
    dut.thread_count.value = 4

    dut.program_mem_read_ready.value = 0
    dut.program_mem_read_data.value = 0

    dut.data_mem_read_ready.value = 0b0000
    dut.data_mem_write_ready.value = 0b0000

    for i in range(4):
        dut.data_mem_read_data[i].value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


@cocotb.test()
async def test_ret_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    #
    # Wait for instruction fetch request
    #

    timeout = 100

    while timeout > 0:

        await RisingEdge(dut.clk)

        if int(dut.program_mem_read_valid.value):
            break

        timeout -= 1

    assert timeout > 0, "Program memory request never occurred"

    #
    # Return RET instruction
    #

    dut.program_mem_read_data.value = RET_INSTRUCTION
    dut.program_mem_read_ready.value = 1

    await RisingEdge(dut.clk)

    dut.program_mem_read_ready.value = 0

    #
    # Allow core to execute
    #

    timeout = 100

    while timeout > 0:

        await RisingEdge(dut.clk)

        if int(dut.done.value):
            break

        timeout -= 1

    assert timeout > 0, "Core never reached DONE state"

    assert int(dut.done.value) == 1