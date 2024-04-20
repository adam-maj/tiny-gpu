from typing import List
from .logger import logger

class Memory:
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

    def write(self, address, data):
        if address < len(self.memory):
            self.memory[address] = data

    def load(self, rows: List[int]):
        for address, data in enumerate(rows):
            self.write(address, data)

    def display(self, rows, decimal=True):
        logger.info("\n")
        logger.info(f"{self.name.upper()} MEMORY")
        
        table_size = (8 * 2) + 3
        logger.info("+" + "-" * (table_size - 3) + "+")

        header = "| Addr | Data "
        logger.info(header + " " * (table_size - len(header) - 1) + "|")

        logger.info("+" + "-" * (table_size - 3) + "+")
        for i, data in enumerate(self.memory):
            if i < rows:
                if decimal:
                    row = f"| {i:<4} | {data:<4}"
                    logger.info(row + " " * (table_size - len(row) - 1) + "|")
                else:
                    data_bin = format(data, f'0{16}b')
                    row = f"| {i:<4} | {data_bin} |"
                    logger.info(row + " " * (table_size - len(row) - 1) + "|")
        logger.info("+" + "-" * (table_size - 3) + "+")