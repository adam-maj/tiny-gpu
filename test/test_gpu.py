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
        self.mem_write_valid = getattr(dut, f"{name}_mem_write_valid")
        self.mem_write_address = getattr(dut, f"{name}_mem_write_address")
        self.mem_write_data = getattr(dut, f"{name}_mem_write_data")
        self.mem_write_ready = getattr(dut, f"{name}_mem_write_ready")

    async def run(self):
        while True:
            await RisingEdge(self.dut.clk)
            if self.mem_write_valid.value == 1:
                address = int(self.mem_write_address.value)
                data = int(self.mem_write_data.value)
                self.memory[address] = data
                self.mem_write_ready.value = 1
            else:
                self.mem_write_ready.value = 0

            if self.mem_read_valid.value == 1:
                address = int(self.mem_read_address.value)
                self.mem_read_data.value = self.memory[address]
                self.mem_read_ready.value = 1
            else:
                self.mem_read_ready.value = 0

    def write_data(self, address, data):
        if address < len(self.memory):
            self.memory[address] = data

    def load_program(self, program):
        for address, data in enumerate(program):
            self.write_data(address, data)

    def display(self, decimal=True):
        print("\n")
        print(self.name.upper())
        print("+" + "-" * (self.addr_bits * 2 + 9) + "+")
        print("| Addr | Data |")
        print("+" + "-" * (self.addr_bits * 2 + 9) + "+")
        for i, data in enumerate(self.memory):
            if data != 0:
                if decimal:
                    print(f"| {i:<4} | {data:<4} |")
                else:
                    data_bin = format(data, f'0{self.data_bits}b')
                    print(f"| {i:<4} | {data_bin} |")
        print("+" + "-" * (self.addr_bits * 2 + 9) + "+")

async def reset(dut):
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

async def setup(dut):
    clock = Clock(dut.clk, 10, units="us")
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
    dut.device_control_data.value = 4  # 4 threads
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Load data into data memory
    data_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=8, name="data")
    matrix_a = [0, 1, 2, 3, 4, 5, 6, 7]
    matrix_b = [0, 1, 2, 3, 4, 5, 6, 7]
    for i, (a, b) in enumerate(zip(matrix_a, matrix_b)):
        data_memory.write_data(i, a)  # Matrix A
        data_memory.write_data(i + 8, b)  # Matrix B

    # Load program into program memory
    program_memory = MemoryInterface(dut=dut, addr_bits=8, data_bits=16, name="program")
    program_memory.load_program(program)

    data_memory.display()
    program_memory.display(decimal=False)

    # Start execution
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # # Wait for done signal
    await cocotb.triggers.ReadOnly()
    for i in range(1):
        await RisingEdge(dut.clk)

        # Display relevant signals/changes in the circuit
        await cocotb.triggers.ReadOnly()
        print(f"Time: {cocotb.utils.get_sim_time('ns')} ns")
        print(f"Device Control Register: {dut.device_conrol_register.value}")
        print(f"Thread Count: {dut.thread_count.value}")
        print(f"Block Dimension: {dut.block_dim.value}")

        #     core_done = dut.cores[i].core_done.value
        #     print(f"Core {i} Done: {core_done}")
        #     for j in range(int(dut.THREADS_PER_WARP.value)):
        #         lsu_read_valid = dut.cores[i].core_lsu_read_valid[j].value
        #         lsu_write_valid = dut.cores[i].core_lsu_write_valid[j].value
        #         print(f"  Thread {j} LSU Read Valid: {lsu_read_valid}, LSU Write Valid: {lsu_write_valid}")
        # print(f"Overall Done: {dut.done.value}")

    # # Verify results
    # expected_results = [a + b for a, b in zip(matrix_a, matrix_b)]
    # for i, expected in enumerate(expected_results):
    #     result = data_memory.memory[i + 16]  # Matrix C starts at address 16
    #     assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

