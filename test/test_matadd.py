import re

import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger


# 这个测试文件验证的是“向量加法”内核是否正确执行。
# 你可以把整个流程理解成：
# 1. 准备 program memory 和 data memory，
# 2. 启动 GPU 仿真，
# 3. 每拍驱动软件内存模型并打印内部状态，
# 4. 等待 dut.done 置位，
# 5. 最后同时检查日志里的写事务轨迹和内存里的最终结果。
def parse_memwrite_records(log_contents: str):
    # `re.compile(...)` 会预编译一个正则表达式，用来从日志文本中提取 `[memwrite]` 记录。
    pattern = re.compile(
        r"^\[memwrite\] data cycle=(\d+) lane=(\d+) addr=(\d+) old=(\d+) new=(\d+)$"
    )
    records = []
    # splitlines() 会把整个日志按行拆开，便于逐条匹配。
    for line in log_contents.splitlines():
        # strip() 去掉首尾空白后再匹配，减少格式噪声影响。
        match = pattern.match(line.strip())
        if match:
            # groups() 会把正则里每个 `(...)` 捕获到的字段按顺序取出来。
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
    # `@cocotb.test()` 是装饰器，告诉 cocotb：下面这个协程就是一个测试入口。

    # Program Memory
    # 这里创建的是 program memory 的 Python 模型，不是 RTL 里的真正 SRAM。
    program_memory = Memory(
        dut=dut, addr_bits=8, data_bits=16, channels=1, name="program"
    )
    # program 列表里的每个元素都是 16 bit 指令，和 decoder.sv 的指令格式对应。
    program = [
        0b0101000011011110,  # MUL R0, %blockIdx, %blockDim
        0b0011000000001111,  # ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
        0b1001000100000000,  # CONST R1, #0                   ; baseA (matrix A base address)
        0b1001001000001000,  # CONST R2, #8                   ; baseB (matrix B base address)
        0b1001001100010000,  # CONST R3, #16                  ; baseC (matrix C base address)
        0b0011010000010000,  # ADD R4, R1, R0                 ; addr(A[i]) = baseA + i
        0b0111010001000000,  # LDR R4, R4                     ; load A[i] from global memory
        0b0011010100100000,  # ADD R5, R2, R0                 ; addr(B[i]) = baseB + i
        0b0111010101010000,  # LDR R5, R5                     ; load B[i] from global memory
        0b0011011001000101,  # ADD R6, R4, R5                 ; C[i] = A[i] + B[i]
        0b0011011100110000,  # ADD R7, R3, R0                 ; addr(C[i]) = baseC + i
        0b1000000001110110,  # STR R7, R6                     ; store C[i] in global memory
        0b1111000000000000,  # RET                            ; end of kernel
    ]

    # Data Memory
    # data memory 是 8 bit 宽，支持 4 个并行访存通道，对应 GPU 顶层参数。
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,  # Matrix A (1 x 8)
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,  # Matrix B (1 x 8)
    ]

    # Device Control
    # 向量加法一共要启动 8 个线程，每个线程负责一个元素。
    threads = 8

    # setup() 会统一完成时钟、复位、预装内存、写 DCR 和拉起 start。
    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads,
    )

    # 先打印一次初始内存，便于和最终结果对比。
    data_memory.display(24)

    cycles = 0
    # `dut.done` 来自 GPU 顶层输出，表示整个 kernel 已经执行完成。
    while dut.done.value != 1:
        # 每拍都先让 Python 版 data/program memory 处理当前周期的读写请求。
        data_memory.run(cycle=cycles)
        program_memory.run()

        # `ReadOnly()` 表示等到当前仿真时刻所有 RTL 更新都稳定后，再去读取内部信号做日志。
        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        # 最后再等时钟上升沿，推进到下一拍。
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(24)

    # 打开当前测试生成的日志文件，准备做事后分析。
    with open(logger.filename, "r") as log_file:
        log_contents = log_file.read()

    memwrite_records = parse_memwrite_records(log_contents)
    # zip(data[0:8], data[8:16]) 会把 A 和 B 的对应元素两两配对，然后逐项相加得到期望结果。
    expected_results = [a + b for a, b in zip(data[0:8], data[8:16])]
    expected_addresses = set(range(16, 24))

    # 只保留写到结果区地址范围内的写事务。
    matching_records = [
        record for record in memwrite_records if record["addr"] in expected_addresses
    ]

    # assert 是 Python 里的断言；条件不成立时，测试会立刻失败并打印后面的错误信息。
    assert matching_records, "Expected [memwrite] data records for matadd writes"

    # 集合推导式 `{... for ... in ...}` 用于提取“实际被写到的地址集合”。
    addresses_seen = {record["addr"] for record in matching_records}
    assert addresses_seen == expected_addresses, (
        "Expected memory write records for addresses 16..23"
    )

    # 逐个地址检查：日志里至少出现过一次 old=0 -> new=expected 的写入。
    for i, expected in enumerate(expected_results):
        relevant_records = [
            record for record in matching_records if record["addr"] == i + 16
        ]
        assert any(
            record["old"] == 0 and record["new"] == expected
            for record in relevant_records
        ), (
            f"Expected at least one memory write record old=0 new={expected} at address {i + 16}"
        )

    # 最后再直接检查软件内存模型里的最终值，确保结果确实留在 data memory 中。
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 16]
        assert result == expected, (
            f"Result mismatch at index {i}: expected {expected}, got {result}"
        )
