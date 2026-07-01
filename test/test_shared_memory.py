import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger

@cocotb.test()
async def test_shared_memory(dut):
    # Program Memory
    #
    # Each of the 4 threads in this single block writes its own %threadIdx into shared
    # memory at address %threadIdx, then reads back shared memory at address (3 -
    # threadIdx) - i.e. every thread reads a *different* thread's value, proving the
    # scratchpad is actually shared and visible across threads in the block (the
    # lockstep scheduler guarantees every thread's STS has completed before any
    # thread's LDS runs, acting as an implicit barrier between instructions).
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b1011000011111111, # STS %threadIdx, %threadIdx      ; shared[threadIdx] = threadIdx
        0b1001000100000011, # CONST R1, #3
        0b0100001000011111, # SUB R2, R1, %threadIdx           ; R2 = 3 - threadIdx
        0b1010001100100000, # LDS R3, R2                       ; R3 = shared[3 - threadIdx]
        0b1001010000001010, # CONST R4, #10
        0b0011010101001111, # ADD R5, R4, %threadIdx           ; addr(out[i]) = 10 + threadIdx
        0b1000000001010011, # STR R5, R3                       ; out[i] = shared[3 - threadIdx]
        0b1111000000000000, # RET
    ]

    # Data Memory - unused by this kernel but the memory model still needs to exist
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 24

    # Device Control
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(24)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(24)

    # thread i writes out[10+i] = shared[3-i] = (3-i), since shared[k] was set to k by thread k
    expected_results = [3, 2, 1, 0]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[10 + i]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"
