from typing import List, Optional
from .logger import logger


# 这个文件不参与功能逻辑，它的职责是“把仿真过程中难读的二进制/状态值格式化成人能看懂的文本”。
# 对调试 GPU 这种时序设计很有帮助，因为你可以直接从日志里看到：
# 当前执行了哪条指令、每个线程寄存器是多少、LSU 在什么状态、这拍是否完成等。
def format_register(register: int) -> str:
    # 普通寄存器 0~12 直接显示成 R0~R12。
    if register < 13:
        return f"R{register}"
    # 13~15 是这个设计里约定的特殊寄存器。
    if register == 13:
        return f"%blockIdx"
    if register == 14:
        return f"%blockDim"
    if register == 15:
        return f"%threadIdx"
    

# 这个函数把一条 16 bit 指令的二进制字符串，翻译成类似汇编的人类可读文本。
# 学习时可以把它和 decoder.sv 对照着看，会很容易理解指令编码格式。
def format_instruction(instruction: str) -> str:
    # Python 切片 `instruction[0:4]` 表示取前 4 个字符；这里假设输入是 16 位二进制字符串。
    opcode = instruction[0:4]
    rd = format_register(int(instruction[4:8], 2))
    rs = format_register(int(instruction[8:12], 2))
    rt = format_register(int(instruction[12:16], 2))

    # 下面三行把 BRnzp 指令里附带的 N/Z/P 条件位翻译成字母。
    # 例如只对负数分支时，可能得到 "N"；如果三个位都打开，就会得到 "NZP"。
    n = "N" if instruction[4] == 1 else ""
    z = "Z" if instruction[5] == 1 else ""
    p = "P" if instruction[6] == 1 else ""
    imm = f"#{int(instruction[8:16], 2)}"

    # 一长串 if/elif 相当于手写一个软件版 decoder。
    if opcode == "0000":
        return "NOP"
    elif opcode == "0001":
        return f"BRnzp {n}{z}{p}, {imm}"
    elif opcode == "0010":
        return f"CMP {rs}, {rt}"
    elif opcode == "0011":
        return f"ADD {rd}, {rs}, {rt}"
    elif opcode == "0100":
        return f"SUB {rd}, {rs}, {rt}"
    elif opcode == "0101":
        return f"MUL {rd}, {rs}, {rt}"
    elif opcode == "0110":
        return f"DIV {rd}, {rs}, {rt}"
    elif opcode == "0111":
        return f"LDR {rd}, {rs}"
    elif opcode == "1000":
        return f"STR {rs}, {rt}"
    elif opcode == "1001":
        return f"CONST {rd}, {imm}"
    elif opcode == "1111":
        return "RET"
    return "UNKNOWN"


# 下面几个函数都是“状态码 -> 字符串名字”的查表工具。
def format_core_state(core_state: str) -> str:
    core_state_map = {
        "000": "IDLE",
        "001": "FETCH",
        "010": "DECODE",
        "011": "REQUEST",
        "100": "WAIT",
        "101": "EXECUTE",
        "110": "UPDATE",
        "111": "DONE"
    }
    return core_state_map[core_state]

def format_fetcher_state(fetcher_state: str) -> str:
    fetcher_state_map = {
        "000": "IDLE",
        "001": "FETCHING",
        "010": "FETCHED"
    }
    return fetcher_state_map[fetcher_state]

def format_lsu_state(lsu_state: str) -> str:
    lsu_state_map = {
        "00": "IDLE",
        "01": "REQUESTING",
        "10": "WAITING",
        "11": "DONE"
    }
    return lsu_state_map[lsu_state]

def format_memory_controller_state(controller_state: str) -> str:
    controller_state_map = {
        "000": "IDLE",
        "010": "READ_WAITING",
        "011": "WRITE_WAITING",
        "100": "READ_RELAYING",
        "101": "WRITE_RELAYING"
    }
    return controller_state_map[controller_state]


# 这个函数把寄存器数组打印成一串“寄存器名 = 数值”的文本。
def format_registers(registers: List[str]) -> str:
    formatted_registers = []
    for i, reg_value in enumerate(registers):
        # cocotb 读出来通常是二进制字符串，这里先转成十进制方便看。
        decimal_value = int(reg_value, 2)
        # 这里减 15 的原因是：当前 register 数组输出顺序和逻辑寄存器编号顺序相反。
        reg_idx = 15 - i
        formatted_registers.append(f"{format_register(reg_idx)} = {decimal_value}")
    # reverse() 就地反转列表，让最终输出顺序重新变成 R0...R15。
    formatted_registers.reverse()
    return ', '.join(formatted_registers)


# 这个函数是调试核心：它在每个仿真周期把 core / thread 的关键内部状态打印到日志里。
def format_cycle(dut, cycle_id: int, thread_id: Optional[int] = None):
    logger.debug(f"\n================================== Cycle {cycle_id} ==================================")

    # dut.cores 来自 gpu.sv 里的 generate 块名字 `cores`，cocotb 会把它暴露成可遍历层级。
    for core in dut.cores:
        # Not exactly accurate, but good enough for now
        if int(str(dut.thread_count.value), 2) <= core.i.value * dut.THREADS_PER_BLOCK.value:
            continue

        logger.debug(f"\n+--------------------- Core {core.i.value} ---------------------+")

        # 取当前 core 正在执行的那条共享指令。
        instruction = str(core.core_instance.instruction.value)
        for thread in core.core_instance.threads:
            # 只显示当前 block 中真正启用的线程 lane。
            if int(thread.i.value) < int(str(core.core_instance.thread_count.value), 2):
                block_idx = core.core_instance.block_id.value
                block_dim = int(core.core_instance.THREADS_PER_BLOCK)
                thread_idx = thread.register_instance.THREAD_ID.value
                # 全局线程索引 = blockIdx * blockDim + threadIdx。
                idx = block_idx * block_dim + thread_idx

                rs = int(str(thread.register_instance.rs.value), 2)
                rt = int(str(thread.register_instance.rt.value), 2)

                reg_input_mux = int(str(core.core_instance.decoded_reg_input_mux.value), 2)
                alu_out = int(str(thread.alu_instance.alu_out.value), 2)
                lsu_out = int(str(thread.lsu_instance.lsu_out.value), 2)
                constant = int(str(core.core_instance.decoded_immediate.value), 2)

                # 如果 thread_id 是 None，就打印所有线程；否则只打印指定线程，方便聚焦调试。
                if (thread_id is None or thread_id == idx):
                    logger.debug(f"\n+-------- Thread {idx} --------+")

                    logger.debug("PC:", int(str(core.core_instance.current_pc.value), 2))
                    logger.debug("Instruction:", format_instruction(instruction))
                    logger.debug("Core State:", format_core_state(str(core.core_instance.core_state.value)))
                    logger.debug("Fetcher State:", format_fetcher_state(str(core.core_instance.fetcher_state.value)))
                    logger.debug("LSU State:", format_lsu_state(str(thread.lsu_instance.lsu_state.value)))
                    logger.debug("Registers:", format_registers([str(item.value) for item in thread.register_instance.registers]))
                    logger.debug(f"RS = {rs}, RT = {rt}")

                    if reg_input_mux == 0:
                        logger.debug("ALU Out:", alu_out)
                    if reg_input_mux == 1:
                        logger.debug("LSU Out:", lsu_out)
                    if reg_input_mux == 2:
                        logger.debug("Constant:", constant)

        logger.debug("Core Done:", str(core.core_instance.done.value))