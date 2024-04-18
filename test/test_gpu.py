import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

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
    print("\n")
    print(name.upper())
    print("+" + "-" * (8 * 2 + 9) + "+")
    print("| Addr | Data ")
    print("+" + "-" * (8 * 2 + 9) + "+")
    for i, data in enumerate(data):
        if i < rows:
            if decimal:
                print(f"| {i:<4} | {data:<4} |")
            else:
                data_bin = format(data, f'0{16}b')
                print(f"| {i:<4} | {data_bin} |")
    print("+" + "-" * (8 * 2 + 9) + "+")

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

async def setup(dut):
    clock = Clock(dut.clk, 25, units="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

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

    # Set threads in the DCR
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = 8 # 4 threads
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Load data into data memory
    data_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=8, name="data")
    matrix_a = [0, 1, 2, 3, 4, 5, 6, 7]
    matrix_b = [0, 1, 2, 3, 3, 4, 6, 7]
    for i, (a, b) in enumerate(zip(matrix_a, matrix_b)):
        data_memory.write_data(i, a)  # Matrix A
        data_memory.write_data(i + 8, b)  # Matrix B

    # Load program into program memory
    program_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=16, name="program")
    program_memory.load_program(program)

    data_memory.display(24)
    program_memory.display(13, decimal=False)

    # Start execution
    dut.start.value = 1

    # # Wait for done signal
    waiting_for_lsu = 0
    for i in range(500):
        data_memory.run()
        program_memory.run()

        # Display relevant signals/changes in the circuit
        await cocotb.triggers.ReadOnly()

        for core in dut.cores:
            instruction = core.core_instance.instruction.value
            for thread in core.core_instance.threads:
                r = thread.register_instance.registers
                block_idx = core.core_instance.CORE_ID.value
                block_dim = int(core.core_instance.block_dim)
                thread_idx = thread.register_instance.THREAD_ID.value
                idx = block_idx * block_dim + thread_idx

                rd = int(core.core_instance.rd[thread_idx].value)
                rs = int(core.core_instance.rs[thread_idx].value)
                rt = int(core.core_instance.rt[thread_idx].value)

                def log(machine, assembly):
                    if str(instruction) == machine:
                        print("\n")
                        print(assembly)
                        print(f"Index: {idx}, Block: {block_idx}")
                        print(f"rd = {rd}, rs = {rs}, rt = {rt}")
                        reg_values = ""
                        for i in range(16):
                            reg_values += f"r{i} = {int(r[i].value)}, "
                        print(reg_values)
                        print("num warps:", int(core.core_instance.warp_scheduler.NUM_WARPS.value))
                
                if idx == 1:
                    # print("current_warp_id", core.core_instance.current_warp_id.value)
                    # if thread.lsu_instance.lsu_state.value != 0 and thread.lsu_instance.mem_read_ready.value == 1:
                    #     print("\nlsu_state", thread.lsu_instance.lsu_state.value)
                    #     print("instruction", core.core_instance.instruction.value)
                    #     # print("lsu_out_reg", thread.lsu_instance.lsu_out_reg.value)
                    #     # print("dmem_ctrl.consumer_read_ready", dut.data_memory_controller.consumer_read_ready.value)
                    #     print("lsu_mem_read_ready", thread.lsu_instance.mem_read_ready.value)
                    #     print("lsu_mem_read_data", thread.lsu_instance.mem_read_data.value)
                    #     print("decoded_mem_read_enable", core.core_instance.warp_scheduler.decoded_mem_read_enable.value)
                    #     print("warp_state", core.core_instance.warp_scheduler.state.value)
                    #     waiting_for_lsu = 3
                    # elif waiting_for_lsu > 0:
                    #     print("\nlsu_state", thread.lsu_instance.lsu_state.value)
                    #     # print("lsu_out_reg", thread.lsu_instance.lsu_out_reg.value)
                    #     print("dmem_ctrl.consumer_read_ready", dut.data_memory_controller.consumer_read_ready.value)
                    #     print("lsu_mem_read_ready", thread.lsu_instance.mem_read_ready.value)
                    #     print("lsu_mem_read_data", thread.lsu_instance.mem_read_data.value)
                    #     print("decoded_mem_read_enable", core.core_instance.warp_scheduler.decoded_mem_read_enable.value)
                    #     print("warp_state", core.core_instance.warp_scheduler.state.value)
                    #     waiting_for_lsu -= 1

                    # print("lsu_state", thread.lsu_instance.lsu_state.value)
                    # log("0101000011011110", "MUL R0, $blockIdx, $blockDim")
                    log("0011000000001111", "ADD R0, R0, $threadIdx")

                    log("1001000100000000", f"CONST R1, #{int(core.core_instance.decoder_instance.decoded_immediate.value)}")
                    log("1001001000001000", f"CONST R2, #{int(core.core_instance.decoder_instance.decoded_immediate.value)}")
                    log("1001001100010000", f"CONST R3, #{int(core.core_instance.decoder_instance.decoded_immediate.value)}")

                    log("0011010000010000", "ADD R4, R1, R0")
                    log("0111010001000000", "LDR R4, R4")

                    log("0011010100100000", "ADD R5, R2, R0")
                    log("0111010101010000", "LDR R5, R5")

                    log("0011011001000101", "ADD R6, R4, R5")
                    log("0011011100110000", "ADD R7, R3, R0")

                    log("1000000001110110", "STR R7, R6")

        if False:
            print("+---------------------+")
            # print(f"TIME - {cocotb.utils.get_sim_time('ns')} ns")
            # print(f"THREAD COUNT - {dut.cores[0].core_instance.thread_count.value}")
            # print(f"NUM WARPS - {dut.cores[0].core_instance.warp_scheduler.NUM_WARPS.value}")
            # print(f"CURRENT PC - {dut.cores[0].core_instance.warp_pc[0].value}")
            print(f"CURRENT PC - {[item.value for item in dut.cores[0].core_instance.warp_pc]}")
            # print(f"CURRENT WARP ID - {dut.cores[0].core_instance.current_warp_id.value}")
            # print(f"NUM WARPS - {dut.cores[0].core_instance.warp_scheduler.NUM_WARPS.value}")
            # print(f"DECODED DONE - {dut.cores[0].core_instance.warp_scheduler.decoded_done.value}")
            print(f"INSTRUCTION - {dut.cores[0].core_instance.instruction.value}")
            # print(f"ALU OUT - {[item.value for item in dut.cores[0].core_instance.alu_out]}")
            # print(f"NEXT PC - {dut.cores[0].core_instance.next_pc[0].value}")
            print("NEXT PC - ", [item.value for item in dut.cores[0].core_instance.next_pc])
            print("CORE DONE - ", dut.cores[0].core_instance.done)
            # print(f"STATE - {dut.cores[0].core_instance.state.value}")
            # print("pmem_ctrl.current_consumer", dut.program_memory_controller.current_consumer.value)
            # print("pmem_ctrl.mem_read_valid", dut.program_memory_controller.mem_read_valid.value)
            # print("pmem_ctrl.mem_read_address", dut.program_memory_controller.mem_read_address.value)
            # print("pmem_ctrl.mem_read_ready", dut.program_memory_controller.mem_read_ready.value)
            # print("pmem_ctrl.mem_read_data", dut.program_memory_controller.mem_read_data.value)
            # print(f"FETCH ENABLE - {dut.cores[0].core_instance.fetcher_instance.fetch_enable.value}")
            # print(f"FETCHER STATE - {dut.cores[0].core_instance.fetcher_instance.state.value}")
            # print(f"GLOBAL PMEM READ VALID - {dut.program_mem_read_valid.value}")
            # print(f"GLOBAL PMEM READ ADDRESS - {dut.program_mem_read_address.value}")
            # print(f"GLOBAL PMEM READ READY - {dut.program_mem_read_ready.value}")
            # print(f"GLOBAL PMEM READ DATA - {dut.program_mem_read_data.value}")
            # print(f"PMEM READ VALID - {dut.cores[0].core_instance.program_mem_read_valid.value}")
            # print(f"PMEM READ ADDRESS - {dut.cores[0].core_instance.program_mem_read_address.value}")
            # print(f"PMEM READ READY - {dut.cores[0].core_instance.program_mem_read_ready.value}")
            # print(f"PMEM READ DATA - {dut.cores[0].core_instance.program_mem_read_data.value}")
            # print(f"GLOBAL MEM READ VALID - {dut.program_mem_read_valid.value}")
            # print(f"GLOBAL MEM READ READY - {dut.program_mem_read_ready.value}")
            # print(f"CONTROLLER_READ_VALID - {dut.program_mem_read_valid.value}")
            # print(f"BLOCK DIM - {dut.cores[0].core_instance.threads[0].register_instance.block_dim.value}")
            # print(f"R13 - {dut.cores[0].core_instance.threads[0].register_instance.registers[13].value}")
            # print(f"R14 - {dut.cores[0].core_instance.threads[0].register_instance.registers[14].value}")
            # print(f"R15 - {dut.cores[0].core_instance.threads[0].register_instance.registers[15].value}")
            # print(f"RD - Address: {dut.cores[0].core_instance.decoded_rd_address}; Value: {dut.cores[0].core_instance.rd[0].value}")
            # print(f"RS - Address: {dut.cores[0].core_instance.decoded_rs_address}; Value: {dut.cores[0].core_instance.rs[0].value}")
            # print(f"RT - Address: {dut.cores[0].core_instance.decoded_rt_address}; Value: {dut.cores[0].core_instance.rt[0].value}")
            # print(f"INSTRUCTION READY - {dut.cores[0].core_instance.instruction_ready.value}")

        await RisingEdge(dut.clk)

    data_memory.display(24)

    # # Verify results
    # expected_results = [a + b for a, b in zip(matrix_a, matrix_b)]
    # for i, expected in enumerate(expected_results):
    #     result = data_memory.memory[i + 16]  # Matrix C starts at address 16
    #     assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

