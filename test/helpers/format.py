from typing import List, Optional
from .logger import logger

def format_register(register: int) -> str:
    if register < 13:
        return f"R{register}"
    if register == 13:
        return f"%blockIdx"
    if register == 14:
        return f"%blockDim"
    if register == 15:
        return f"%threadIdx"
    
def format_instruction(instruction: str) -> str:
    opcode = instruction[0:4]
    rd = format_register(int(instruction[4:8], 2))
    rs = format_register(int(instruction[8:12], 2))
    rt = format_register(int(instruction[12:16], 2))
    n = "N" if instruction[4] == 1 else ""
    z = "Z" if instruction[5] == 1 else ""
    p = "P" if instruction[6] == 1 else ""
    imm = f"#{int(instruction[8:16], 2)}"

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

def format_registers(registers: List[str]) -> str:
    formatted_registers = []
    for i, reg_value in enumerate(registers):
        decimal_value = int(reg_value, 2)  # Convert binary string to decimal
        reg_idx = 15 - i # Register data is provided in reverse order
        formatted_registers.append(f"{format_register(reg_idx)} = {decimal_value}")
    formatted_registers.reverse()
    return ', '.join(formatted_registers)

def format_cycle(dut, cycle_id: int, thread_id: Optional[int] = None):
    logger.debug(f"\n================================== Cycle {cycle_id} ==================================")

    for core in dut.cores:
        # Not exactly accurate, but good enough for now
        if int(str(dut.thread_count.value), 2) <= core.i.value * dut.THREADS_PER_BLOCK.value:
            continue

        logger.debug(f"\n+--------------------- Core {core.i.value} ---------------------+")

        instruction = str(core.core_instance.instruction.value)
        for thread in core.core_instance.threads:
            if int(thread.i.value) < int(str(core.core_instance.thread_count.value), 2): # if enabled
                block_idx = core.core_instance.block_id.value
                block_dim = int(core.core_instance.THREADS_PER_BLOCK)
                thread_idx = thread.register_instance.THREAD_ID.value
                idx = block_idx * block_dim + thread_idx

                rs = int(str(thread.register_instance.rs.value), 2)
                rt = int(str(thread.register_instance.rt.value), 2)

                reg_input_mux = int(str(core.core_instance.decoded_reg_input_mux.value), 2)
                alu_out = int(str(thread.alu_instance.alu_out.value), 2)
                lsu_out = int(str(thread.lsu_instance.lsu_out.value), 2)
                constant = int(str(core.core_instance.decoded_immediate.value), 2)

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