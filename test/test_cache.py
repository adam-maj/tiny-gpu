import cocotb
from cocotb.triggers import RisingEdge
from test.helpers.setup import setup
from test.helpers.memory import Memory
from test.helpers.format import format_cycle
from test.helpers.logger import logger

@cocotb.test()
async def test_cache_reuse(dut):
    # Program Memory - Each thread reads address 0 THREE times
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b1001000000000000, # CONST R0, #0           ; address to read
        0b1001000100000000, # CONST R1, #0           ; accumulator

        # Read 1
        0b0111001000000000, # LDR R2, R0             ; read from address 0
        0b0011000100010010, # ADD R1, R1, R2         ; accumulate

        # Read 2 (same address)
        0b0111001000000000, # LDR R2, R0             ; read from address 0 again
        0b0011000100010010, # ADD R1, R1, R2         ; accumulate

        # Read 3 (same address)
        0b0111001000000000, # LDR R2, R0             ; read from address 0 again
        0b0011000100010010, # ADD R1, R1, R2         ; accumulate

        # Store result
        0b1001001100010000, # CONST R3, #16          ; output base address
        0b0011010000111111, # ADD R4, R3, %threadIdx ; output address
        0b1000000001000001, # STR R4, R1             ; store result
        0b1111000000000000, # RET
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        10,                  # Address 0: value that will be read 3x by each thread
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0,          # Addresses 16-19: output
    ]

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    logger.info("="*80)
    logger.info("CACHE REUSE TEST - Each thread reads address 0 THREE times")
    logger.info("="*80)

    data_memory.display(20)

    cycles = 0

    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        await RisingEdge(dut.clk)
        cycles += 1

        if cycles > 10000:
            break

    print(f"\nCompleted in {cycles} cycles")
    logger.info(f"Completed in {cycles} cycles")

    data_memory.display(20)

    # Verify: each thread should output 30 (10 + 10 + 10)
    expected = 30
    for i in range(threads):
        addr = 16 + i
        result = data_memory.memory[addr]
        assert result == expected, f"Thread {i}: expected {expected}, got {result}"

    print(f"All outputs correct: {expected}")
    logger.info(f"All outputs correct: {expected}")
