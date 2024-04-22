from typing import List
from .logger import logger

class Memory:
    def __init__(self, dut, addr_bits, data_bits, channels, name):
        self.dut = dut
        self.addr_bits = addr_bits
        self.data_bits = data_bits
        self.memory = [0] * (2**addr_bits)
        self.channels = channels
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
        mem_read_valid = [
            int(str(self.mem_read_valid.value)[i:i+1], 2)
            for i in range(0, len(str(self.mem_read_valid.value)), 1)
        ]

        mem_read_address = [
            int(str(self.mem_read_address.value)[i:i+self.addr_bits], 2)
            for i in range(0, len(str(self.mem_read_address.value)), self.addr_bits)
        ]
        mem_read_ready = [0] * self.channels
        mem_read_data = [0] * self.channels

        for i in range(self.channels):
            if mem_read_valid[i] == 1:
                mem_read_data[i] = self.memory[mem_read_address[i]]
                mem_read_ready[i] = 1
            else:
                mem_read_ready[i] = 0

        self.mem_read_data.value = int(''.join(format(d, '0' + str(self.data_bits) + 'b') for d in mem_read_data), 2)
        self.mem_read_ready.value = int(''.join(format(r, '01b') for r in mem_read_ready), 2)

        if self.name != "program":
            mem_write_valid = [
                int(str(self.mem_write_valid.value)[i:i+1], 2)
                for i in range(0, len(str(self.mem_write_valid.value)), 1)
            ]
            mem_write_address = [
                int(str(self.mem_write_address.value)[i:i+self.addr_bits], 2)
                for i in range(0, len(str(self.mem_write_address.value)), self.addr_bits)
            ]
            mem_write_data = [
                int(str(self.mem_write_data.value)[i:i+self.data_bits], 2)
                for i in range(0, len(str(self.mem_write_data.value)), self.data_bits)
            ]
            mem_write_ready = [0] * self.channels

            for i in range(self.channels):
                if mem_write_valid[i] == 1:
                    self.memory[mem_write_address[i]] = mem_write_data[i]
                    mem_write_ready[i] = 1
                else:
                    mem_write_ready[i] = 0

            self.mem_write_ready.value = int(''.join(format(w, '01b') for w in mem_write_ready), 2)

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