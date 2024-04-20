from typing import List
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import datetime

class Logger:
    def __init__(self):
        self.filename = f"test/logs/log_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}.txt"

    def log(self, *messages):
        full_message = ' '.join(str(message) for message in messages)
        with open(self.filename, "a") as log_file:
            log_file.write(full_message + "\n")

logger = Logger()

class MemoryInterface:
    def __init__(self, dut, addr_bits, data_bits, name):
        self.dut = dut
        self.addr_bits = addr_bits
        self.data_bits = data_bits
        self.memory = [0] * (2**addr_bits)
        self.name = name

        self.mem_read_valid = getattr(dut, f"{name}_mem_read_valid")
        self.mem_read_address = getattr(dut, f"{name}_mem_read_address")
        self.mem_read_ready = getattr(dut, f"{name}_mem_read_ready")
        self.mem_read_data = getattr(dut, f"{name}_mem_read_data")

        if name != "program":
            self.mem_write_valid = getattr(dut, f"{name}_mem_write_valid")
            self.mem_write_address = getattr(dut, f"{name}_mem_write_address")
            self.mem_write_data = getattr(dut, f"{name}_mem_write_data")
            self.mem_write_ready = getattr(dut, f"{name}_mem_write_ready")

    def run(self):
        if self.mem_read_valid.value == 1:
            address = int(self.mem_read_address.value)
            self.mem_read_data.value = self.memory[address]
            self.mem_read_ready.value = 1
        else:
            self.mem_read_ready.value = 0

        if self.name != "program":
            if self.mem_write_valid.value == 1:
                address = int(self.mem_write_address.value)
                data = int(self.mem_write_data.value)
                self.memory[address] = data
                self.mem_write_ready.value = 1
            else:
                self.mem_write_ready.value = 0

    def write_data(self, address, data):
        if address < len(self.memory):
            self.memory[address] = data

    def load_program(self, program):
        for address, data in enumerate(program):
            self.write_data(address, data)

    def display(self, rows, decimal=True):
        pretty(rows, self.name, self.memory, decimal)

def pretty(rows, name, data, decimal=True):
    logger.log("\n")
    logger.log(name.upper())
    logger.log("+" + "-" * (8 * 2 + 9) + "+")
    logger.log("| Addr | Data ")
    logger.log("+" + "-" * (8 * 2 + 9) + "+")
    for i, data in enumerate(data):
        if i < rows:
            if decimal:
                logger.log(f"| {i:<4} | {data:<4} |")
            else:
                data_bin = format(data, f'0{16}b')
                logger.log(f"| {i:<4} | {data_bin} |")
    logger.log("+" + "-" * (8 * 2 + 9) + "+")

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

async def setup(dut):
    clock = Clock(dut.clk, 25, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

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
        "110": "UPDATE"
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
        "01": "WAITING",
        "10": "DONE"
    }
    return lsu_state_map[lsu_state]

def format_memory_controller_state(controller_state: str) -> str:
    controller_state_map = {
        "00": "IDLE",
        "01": "WAITING",
        "10": "RELAYING"
    }
    return controller_state_map[controller_state]

def format_registers(registers: List[str]) -> str:
    formatted_registers = []
    for i, reg_value in enumerate(registers):
        decimal_value = int(reg_value, 2)  # Convert binary string to decimal
        reg_idx = 15 - i # Register data is provided in reverse order
        formatted_registers.append(f"R{reg_idx} = {decimal_value}")
    formatted_registers.reverse()
    return ', '.join(formatted_registers)

@cocotb.test()
async def test_matrix_addition_kernel(dut):
    await setup(dut)

    program = [
        0b0101000011011110,
        0b0011000000001111,
        0b1001000100000000,
        0b1001001000001000,
        0b1001001100010000,
        0b0011010000010000,
        0b0111010001000000,
        0b0011010100100000,
        0b0111010101010000,
        0b0011011001000101,
        0b0011011100110000,
        0b1000000001110110,
        0b1111000000000000,
    ]

    # DCR
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = 8
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Data
    data_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=8, name="data")
    matrix_a = [2, 3, 4, 5, 6, 7, 8, 9]
    matrix_b = [2, 3, 4, 5, 6, 7, 8, 9]
    for i, (a, b) in enumerate(zip(matrix_a, matrix_b)):
        data_memory.write_data(i, a)
        data_memory.write_data(i + 8, b)

    # Program
    program_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=16, name="program")
    program_memory.load_program(program)

    dut.start.value = 1
    for i in range(300):
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()

        for core in dut.cores:
            instruction = str(core.core_instance.instruction.value)
            for thread in core.core_instance.threads:
                block_idx = core.core_instance.CORE_ID.value
                block_dim = int(core.core_instance.block_dim)
                thread_idx = thread.register_instance.THREAD_ID.value
                idx = block_idx * block_dim + thread_idx

                rs = int(str(core.core_instance.rs[thread_idx].value), 2)
                rt = int(str(core.core_instance.rt[thread_idx].value), 2)

                reg_input_mux = int(str(core.core_instance.decoded_reg_input_mux.value), 2)
                alu_out = int(str(core.core_instance.alu_out[thread_idx].value), 2)
                lsu_out = int(str(core.core_instance.lsu_out[thread_idx].value), 2)
                constant = int(str(core.core_instance.decoded_immediate.value), 2)

                if idx == 1:
                    logger.log("\n+--------------------+")
                    logger.log("Thread ID:", thread_idx)
                    
                    warp_pc_str = str(core.core_instance.warp_pc.value)
                    warp_pc_values = [int(warp_pc_str[i:i+8], 2) for i in range(0, len(warp_pc_str), 8)]
                    logger.log("PC:", warp_pc_values)
                    
                    logger.log("Warp ID:", str(core.core_instance.current_warp_id.value))
                    logger.log("Instruction:", format_instruction(instruction))
                    logger.log("Core State:", format_core_state(str(core.core_instance.core_state.value)))
                    logger.log("Fetcher State:", format_fetcher_state(str(core.core_instance.fetcher_state.value)))

                    lsu_state_str = str(core.core_instance.lsu_state.value)
                    lsu_state_values = [lsu_state_str[i:i+2] for i in range(0, len(lsu_state_str), 2)]
                    logger.log("LSU State:", format_lsu_state(lsu_state_values[thread_idx]))
                    # logger.log("LSU Read Valid:", str(dut.lsu_read_valid))
                    # logger.log("LSU Read Ready:", str(dut.lsu_read_ready))

                    logger.log(
                        "Program Memory Controller State:", 
                        format_memory_controller_state(str(dut.program_memory_controller.controller_state.value))
                    )
                    logger.log(
                        "Program Memory Consumer Read Valid:",
                        str(dut.program_memory_controller.consumer_read_valid.value)
                    )
                    logger.log(
                        "Program Memory Consumer Read Ready:",
                        str(dut.program_memory_controller.consumer_read_ready.value)
                    )
                    logger.log(
                        "Data Memory Controller State:", 
                        format_memory_controller_state(str(dut.data_memory_controller.controller_state.value))
                    )
                    logger.log(
                        "Data Memory Consumer Read Valid:",
                        str(dut.data_memory_controller.consumer_read_valid.value)
                    )
                    logger.log(
                        "Data Memory Consumer Read Ready:",
                        str(dut.data_memory_controller.consumer_read_ready.value)
                    )

                    logger.log("Registers:", format_registers([str(item.value) for item in thread.register_instance.registers]))
                    logger.log(f"RS = {rs}, RT = {rt}")

                    if reg_input_mux == 0:
                        logger.log("ALU Out:", alu_out)
                    if reg_input_mux == 1:
                        logger.log("LSU Out:", lsu_out)
                    if reg_input_mux == 2:
                        logger.log("Constant:", constant)

        await RisingEdge(dut.clk)

    data_memory.display(24)

    # # Verify results
    # expected_results = [a + b for a, b in zip(matrix_a, matrix_b)]
    # for i, expected in enumerate(expected_results):
    #     result = data_memory.memory[i + 16]  # Matrix C starts at address 16
    #     assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

