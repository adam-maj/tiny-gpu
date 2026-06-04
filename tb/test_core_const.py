import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CONST_R0_55 = 0x9037
RET         = 0xF000


async def reset_dut(dut):

    dut.start.value = 0
    dut.reset.value = 1

    dut.block_id.value = 0
    dut.thread_count.value = 4

    dut.program_mem_read_ready.value = 0
    dut.program_mem_read_data.value = 0

    dut.data_mem_read_ready.value = 0
    dut.data_mem_write_ready.value = 0

    for i in range(4):
        dut.data_mem_read_data[i].value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


@cocotb.test()
async def test_const_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    dut.start.value = 1

    fetch_count = 0

    while True:

        await RisingEdge(dut.clk)

        if int(dut.program_mem_read_valid.value):

            addr = int(dut.program_mem_read_address.value)

            if addr == 0:
                dut.program_mem_read_data.value = CONST_R0_55

            elif addr == 1:
                dut.program_mem_read_data.value = RET

            else:
                dut.program_mem_read_data.value = RET

            dut.program_mem_read_ready.value = 1

            await RisingEdge(dut.clk)

            dut.program_mem_read_ready.value = 0

            fetch_count += 1

        if int(dut.done.value):
            break

    #
    # Reach inside DUT hierarchy
    #
    # Thread 0 register file
    #

    reg0 = int(
        dut.rootp.core_registers_0.register_file[0]
    )

    assert reg0 == 55

    assert int(dut.done.value) == 1