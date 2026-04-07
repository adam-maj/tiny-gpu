import re

import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger


# 这个测试文件验证的是“2x2 矩阵乘法”内核。
# 和 matadd 相比，它更能覆盖分支、循环、乘法和多次 load/store 的组合行为。
def parse_memwrite_records(log_contents: str):
    # 和 matadd 里同名函数作用相同：把日志中的内存写事务解析成结构化记录。
    pattern = re.compile(
        r"^\[memwrite\] data cycle=(\d+) lane=(\d+) addr=(\d+) old=(\d+) new=(\d+)$"
    )
    records = []
    for line in log_contents.splitlines():
        match = pattern.match(line.strip())
        if match:
            cycle, lane, addr, old, new = match.groups()
            records.append(
                {
                    "cycle": int(cycle),
                    "lane": int(lane),
                    "addr": int(addr),
                    "old": int(old),
                    "new": int(new),
                }
            )
    return records


@cocotb.test()
async def test_matadd(dut):
    # 函数名虽然写成了 test_matadd，但因为有 `@cocotb.test()` 装饰器，它仍会被当作一个独立测试执行。
    # 这里我只补解释，不改行为。

    # Program Memory
    program_memory = Memory(
        dut=dut, addr_bits=8, data_bits=16, channels=1, name="program"
    )
    # 这段程序实现的是 2x2 矩阵乘法内核：
    # 先根据线程号算出 row/col，再在 LOOP 里遍历 k，累加 A[row,k] * B[k,col]。
    program = [
        0b0101000011011110,  # MUL R0, %blockIdx, %blockDim
        0b0011000000001111,  # ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
        0b1001000100000001,  # CONST R1, #1                   ; increment
        0b1001001000000010,  # CONST R2, #2                   ; N (matrix inner dimension)
        0b1001001100000000,  # CONST R3, #0                   ; baseA (matrix A base address)
        0b1001010000000100,  # CONST R4, #4                   ; baseB (matrix B base address)
        0b1001010100001000,  # CONST R5, #8                   ; baseC (matrix C base address)
        0b0110011000000010,  # DIV R6, R0, R2                 ; row = i // N
        0b0101011101100010,  # MUL R7, R6, R2
        0b0100011100000111,  # SUB R7, R0, R7                 ; col = i % N
        0b1001100000000000,  # CONST R8, #0                   ; acc = 0
        0b1001100100000000,  # CONST R9, #0                   ; k = 0
        # LOOP:
        0b0101101001100010,  #   MUL R10, R6, R2
        0b0011101010101001,  #   ADD R10, R10, R9
        0b0011101010100011,  #   ADD R10, R10, R3             ; addr(A[i]) = row * N + k + baseA
        0b0111101010100000,  #   LDR R10, R10                 ; load A[i] from global memory
        0b0101101110010010,  #   MUL R11, R9, R2
        0b0011101110110111,  #   ADD R11, R11, R7
        0b0011101110110100,  #   ADD R11, R11, R4             ; addr(B[i]) = k * N + col + baseB
        0b0111101110110000,  #   LDR R11, R11                 ; load B[i] from global memory
        0b0101110010101011,  #   MUL R12, R10, R11
        0b0011100010001100,  #   ADD R8, R8, R12              ; acc = acc + A[i] * B[i]
        0b0011100110010001,  #   ADD R9, R9, R1               ; increment k
        0b0010000010010010,  #   CMP R9, R2
        0b0001100000001100,  #   BRn LOOP                     ; loop while k < N
        0b0011100101010000,  # ADD R9, R5, R0                 ; addr(C[i]) = baseC + i
        0b1000000010011000,  # STR R9, R8                     ; store C[i] in global memory
        0b1111000000000000,  # RET                            ; end of kernel
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        1,
        2,
        3,
        4,  # Matrix A (2 x 2)
        1,
        2,
        3,
        4,  # Matrix B (2 x 2)
    ]

    # Device Control
    # 2x2 结果矩阵有 4 个元素，因此这里启动 4 个线程，每个线程负责一个输出位置。
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads,
    )

    data_memory.display(12)

    cycles = 0
    while dut.done.value != 1:
        # 仿真主循环的结构和 matadd 相同：先驱动 memory model，再读稳定信号，最后推进时钟。
        data_memory.run(cycle=cycles)
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        # 这里把 thread_id=1 传进去，表示只重点打印一个线程的详细内部状态，避免日志过大。
        format_cycle(dut, cycles, thread_id=1)

        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(12)

    with open(logger.filename, "r") as log_file:
        log_contents = log_file.read()

    memwrite_records = parse_memwrite_records(log_contents)
    expected_addresses = set(range(8, 12))

    # 结果矩阵被约定写回到 data memory 的 8..11 地址范围。
    matching_records = [
        record for record in memwrite_records if record["addr"] in expected_addresses
    ]

    assert matching_records, "Expected [memwrite] data records for matmul writes"

    addresses_seen = {record["addr"] for record in matching_records}
    assert addresses_seen == expected_addresses, (
        "Expected memory write records for addresses 8..11"
    )

    # Assuming the matrices are 2x2 and the result is stored starting at address 9
    # 先把一维 data 列表重新切成两个 2x2 矩阵，便于直接写出数学期望值。
    matrix_a = [data[0:2], data[2:4]]  # First matrix (2x2)
    matrix_b = [data[4:6], data[6:8]]  # Second matrix (2x2)
    expected_results = [
        matrix_a[0][0] * matrix_b[0][0] + matrix_a[0][1] * matrix_b[1][0],  # C[0,0]
        matrix_a[0][0] * matrix_b[0][1] + matrix_a[0][1] * matrix_b[1][1],  # C[0,1]
        matrix_a[1][0] * matrix_b[0][0] + matrix_a[1][1] * matrix_b[1][0],  # C[1,0]
        matrix_a[1][0] * matrix_b[0][1] + matrix_a[1][1] * matrix_b[1][1],  # C[1,1]
    ]
    for i, expected in enumerate(expected_results):
        relevant_records = [
            record for record in matching_records if record["addr"] == i + 8
        ]
        assert any(
            record["old"] == 0 and record["new"] == expected
            for record in relevant_records
        ), (
            f"Expected at least one memory write record old=0 new={expected} at address {i + 8}"
        )

        # 和 matadd 一样，再直接检查最终 data memory 的实际落值。
        result = data_memory.memory[i + 8]  # Results start at address 9
        assert result == expected, (
            f"Result mismatch at index {i}: expected {expected}, got {result}"
        )
