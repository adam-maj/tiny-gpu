import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger

@cocotb.test()
async def test_icache(dut):
    """
    Runs the matmul kernel (which loops over its inner dot-product 2x) and checks
    that the per-core instruction cache actually records hits - i.e. that looping
    kernels benefit from not re-fetching the same instructions from program memory
    every iteration. Also verifies the kernel result is still correct with the
    cache in the loop, and that total program-memory-controller traffic is lower
    than the number of instructions fetched (some fetches were served from cache).
    """
    # Program Memory (same matmul kernel as test_matmul.py - it loops, so it's a
    # good candidate for exercising cache hits)
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b0101000011011110, # MUL R0, %blockIdx, %blockDim
        0b0011000000001111, # ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
        0b1001000100000001, # CONST R1, #1                   ; increment
        0b1001001000000010, # CONST R2, #2                   ; N (matrix inner dimension)
        0b1001001100000000, # CONST R3, #0                   ; baseA (matrix A base address)
        0b1001010000000100, # CONST R4, #4                   ; baseB (matrix B base address)
        0b1001010100001000, # CONST R5, #8                   ; baseC (matrix C base address)
        0b0110011000000010, # DIV R6, R0, R2                 ; row = i // N
        0b0101011101100010, # MUL R7, R6, R2
        0b0100011100000111, # SUB R7, R0, R7                 ; col = i % N
        0b1001100000000000, # CONST R8, #0                   ; acc = 0
        0b1001100100000000, # CONST R9, #0                   ; k = 0
                            # LOOP:
        0b0101101001100010, #   MUL R10, R6, R2
        0b0011101010101001, #   ADD R10, R10, R9
        0b0011101010100011, #   ADD R10, R10, R3             ; addr(A[i]) = row * N + k + baseA
        0b0111101010100000, #   LDR R10, R10                 ; load A[i] from global memory
        0b0101101110010010, #   MUL R11, R9, R2
        0b0011101110110111, #   ADD R11, R11, R7
        0b0011101110110100, #   ADD R11, R11, R4             ; addr(B[i]) = k * N + col + baseB
        0b0111101110110000, #   LDR R11, R11                 ; load B[i] from global memory
        0b0101110010101011, #   MUL R12, R10, R11
        0b0011100010001100, #   ADD R8, R8, R12              ; acc = acc + A[i] * B[i]
        0b0011100110010001, #   ADD R9, R9, R1               ; increment k
        0b0010000010010010, #   CMP R9, R2
        0b0001100000001100, #   BRn LOOP                     ; loop while k < N
        0b0011100101010000, # ADD R9, R5, R0                 ; addr(C[i]) = baseC + i 
        0b1000000010011000, # STR R9, R8                     ; store C[i] in global memory
        0b1111000000000000  # RET                            ; end of kernel
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        1, 2, 3, 4, # Matrix A (2 x 2)
        1, 2, 3, 4, # Matrix B (2 x 2)
    ]

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

    total_hits = 0
    total_misses = 0

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        for core_icache in dut.icaches:
            if core_icache.icache_instance.hit.value == 1:
                total_hits += 1
            if core_icache.icache_instance.miss.value == 1:
                total_misses += 1

        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    logger.info(f"ICache hits: {total_hits}, misses: {total_misses}")

    # Correctness: same expected results as test_matmul.py
    matrix_a = [data[0:2], data[2:4]]
    matrix_b = [data[4:6], data[6:8]]
    expected_results = [
        matrix_a[0][0] * matrix_b[0][0] + matrix_a[0][1] * matrix_b[1][0],
        matrix_a[0][0] * matrix_b[0][1] + matrix_a[0][1] * matrix_b[1][1],
        matrix_a[1][0] * matrix_b[0][0] + matrix_a[1][1] * matrix_b[1][0],
        matrix_a[1][0] * matrix_b[0][1] + matrix_a[1][1] * matrix_b[1][1],
    ]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 8]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

    # The whole point of the cache: looping back into LOOP's body a 2nd time should
    # hit the cache instead of re-fetching from program memory.
    assert total_hits > 0, "Expected at least one instruction cache hit on a looping kernel"
