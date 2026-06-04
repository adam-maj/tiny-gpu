import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

LAST_STORE_ADDR = None
LAST_STORE_DATA = None

RET = 0xF000


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

    dut.data_mem_read_ready.value = 0
    dut.data_mem_write_ready.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.reset.value = 0

    await RisingEdge(dut.clk)


async def run_program(dut, program):

    global LAST_STORE_ADDR
    global LAST_STORE_DATA

    dut.start.value = 1

    timeout = 1000

    while timeout > 0:

        await RisingEdge(dut.clk)

        #
        # Program Memory
        #

        if int(dut.program_mem_read_valid.value):

            pc = int(dut.program_mem_read_address.value)

            if pc < len(program):
                instr = program[pc]
            else:
                instr = RET

            dut.program_mem_read_data.value = instr
            dut.program_mem_read_ready.value = 1

            await RisingEdge(dut.clk)

            dut.program_mem_read_ready.value = 0

        #
        # Thread 0 Data Memory Read
        #

        if int(dut.data_mem_read_valid.value):
            for i in range(4):
                if (int(dut.data_mem_read_valid.value) >> i) & 1:
                    addr = int(dut.data_mem_read_address[i].value)

                    if addr == 10:
                        dut.data_mem_read_data[i].value = 77
                    else:
                        dut.data_mem_read_data[i].value = 0

            dut.data_mem_read_ready.value = int(dut.data_mem_read_valid.value)
            await RisingEdge(dut.clk)
            dut.data_mem_read_ready.value = 0

        #
        # Thread 0 Data Memory Write
        #

        if int(dut.data_mem_write_valid.value) & 0x1:

            LAST_STORE_ADDR = int(
                dut.data_mem_write_address[0].value
            )

            LAST_STORE_DATA = int(
                dut.data_mem_write_data[0].value
            )

            dut.data_mem_write_ready.value = int(
                dut.data_mem_write_valid.value
            )

            await RisingEdge(dut.clk)

            dut.data_mem_write_ready.value = 0

        if int(dut.data_mem_read_valid.value):
            cocotb.log.info(f"READ VALID addr={int(dut.data_mem_read_address[0].value)}")

        if int(dut.data_mem_write_valid.value):
            for i in range(4):
                if (int(dut.data_mem_write_valid.value) >> i) & 1:
                    LAST_STORE_ADDR = int(dut.data_mem_write_address[i].value)
                    LAST_STORE_DATA = int(dut.data_mem_write_data[i].value)

            dut.data_mem_write_ready.value = int(dut.data_mem_write_valid.value)
            await RisingEdge(dut.clk)
            dut.data_mem_write_ready.value = 0


        #
        # Completion
        #


        if int(dut.done.value):
            return
        
        if timeout % 50 == 0:
            cocotb.log.info(
            f"core={int(dut.core_state.value)} "
            f"lsu0={int(dut.g_thread[0].lsu_instance.lsu_state.value)} "
            f"lsu1={int(dut.g_thread[1].lsu_instance.lsu_state.value)} "
            f"lsu2={int(dut.g_thread[2].lsu_instance.lsu_state.value)} "
            f"lsu3={int(dut.g_thread[3].lsu_instance.lsu_state.value)}"
            )
        timeout -= 1

    raise AssertionError("Program timeout")


def read_reg(dut, reg_idx):

    return int(
        dut.g_thread[0]
           .register_instance
           .register_file[reg_idx]
           .value
    )

def read_nzp(dut):

    return int(
        dut.g_thread[0]
           .pc_instance
           .nzp
           .value
    )

def clear_store_capture():

    global LAST_STORE_ADDR
    global LAST_STORE_DATA

    LAST_STORE_ADDR = None
    LAST_STORE_DATA = None

@cocotb.test()
async def test_cmp_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x910A,   # CONST R1,10
        0x9214,   # CONST R2,20
        0x2012,   # CMP R1,R2
        RET,
    ]

    await run_program(dut, program)

    #
    # 10 < 20
    #
    # Expected:
    # N=1 Z=0 P=0
    #

    assert read_nzp(dut) == 0b001

@cocotb.test()
async def test_const_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x9037,   # CONST R0,55
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 55


@cocotb.test()
async def test_add_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x910A,   # CONST R1,10
        0x9214,   # CONST R2,20
        0x3012,   # ADD R0,R1,R2
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 30


@cocotb.test()
async def test_sub_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x9132,   # CONST R1,50
        0x9214,   # CONST R2,20
        0x4012,   # SUB R0,R1,R2
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 30


@cocotb.test()
async def test_mul_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x910A,   # CONST R1,10
        0x9214,   # CONST R2,20
        0x5012,   # MUL R0,R1,R2
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 200


@cocotb.test()
async def test_div_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    program = [
        0x9114,   # CONST R1,20
        0x9204,   # CONST R2,4
        0x6012,   # DIV R0,R1,R2
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 5


@cocotb.test()
async def test_branch_taken(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    #
    # Program:
    #
    # 0: CONST R1,10
    # 1: CONST R2,20
    # 2: CMP R1,R2
    # 3: BRN 5
    # 4: CONST R0,99
    # 5: CONST R0,55
    # 6: RET
    #

    program = [
        0x910A,
        0x9214,
        0x2012,
        0xA405,
        0x9063,
        0x9037,
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 55

@cocotb.test()
async def test_load_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    await reset_dut(dut)

    #
    # R1 = 10
    # LDR R0,[R1]
    #

    program = [
        0x910A,
        0x7010,
        RET,
    ]

    await run_program(dut, program)

    assert read_reg(dut, 0) == 77

@cocotb.test()
async def test_store_program(dut):

    cocotb.start_soon(
        Clock(dut.clk, 10, unit="ns").start()
    )

    clear_store_capture()

    await reset_dut(dut)

    #
    # R1 = 10
    # R2 = 55
    # STR [R1],R2
    #

    program = [
        0x910A,
        0x9237,
        0x8012,
        RET,
    ]

    await run_program(dut, program)

    assert LAST_STORE_ADDR == 10
    assert LAST_STORE_DATA == 55