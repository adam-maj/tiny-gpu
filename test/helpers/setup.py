from typing import List
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from .debug import maybe_enable_debugpy
from .memory import Memory


# 这个文件负责把“每个测试都要做的初始化步骤”收口到一个公共函数里。
# 对新手来说，可以把它理解成：
# 1. 启动时钟，
# 2. 拉一次 reset，
# 3. 预装程序和数据内存，
# 4. 写 device control register，
# 5. 拉起 start，正式开始跑 kernel。
async def setup(
    dut,
    program_memory: Memory,
    program: List[int],
    data_memory: Memory,
    data: List[int],
    threads: int,
):
    # `async def` 表示这是一个协程函数。
    # 在 cocotb 里，协程非常常见，因为仿真需要“等一个时钟边沿再继续往下执行”。

    maybe_enable_debugpy()

    # Setup Clock
    # `Clock(dut.clk, 25, units="us")` 的意思是给 dut.clk 这个信号挂一个周期为 25 微秒的时钟源。
    clock = Clock(dut.clk, 25, units="us")
    # `cocotb.start_soon(...)` 会把这个时钟协程在后台启动，让它持续翻转 clk。
    cocotb.start_soon(clock.start())

    # Reset
    # cocotb 里给信号赋值通常用 `.value = ...`。
    # 这里先把 reset 拉高，再等一个上升沿，模拟硬件复位过程。
    dut.reset.value = 1
    # `await RisingEdge(dut.clk)` 的意思是“暂停当前协程，直到 dut.clk 出现下一个上升沿”。
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    # Load Program Memory
    # 这一步不是通过总线一拍拍写进去，而是直接调用 Python 内存模型的辅助函数预装程序。
    program_memory.load(program)

    # Load Data Memory
    data_memory.load(data)

    # Device Control Register
    # 把线程总数写进 DCR，对应 RTL 里的 dcr.sv 模块。
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = threads
    # 等一个时钟上升沿，确保 DCR 在时序逻辑里真正采样到这次写入。
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Start
    # 把 start 拉高后，顶层 dispatch 就会开始把 block 分发到各个 core。
    dut.start.value = 1
