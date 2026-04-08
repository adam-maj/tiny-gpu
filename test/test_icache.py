import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_icache(dut):
    """
    Test instruction cache effectiveness with a loop kernel.
    The kernel contains a loop that executes the same instructions multiple times,
    demonstrating instruction cache benefits.
    """
    # Program Memory - A simple loop that increments a counter
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        # Initialize
        0b0101000011011110, # MUL R0, %blockIdx, %blockDim     ; i = blockIdx * blockDim
        0b0011000000001111, # ADD R0, R0, %threadIdx           ; i += threadIdx
        0b1001000100000000, # CONST R1, #0                     ; counter = 0
        0b1001001000000100, # CONST R2, #4                     ; loop_limit = 4
        0b1001001100000001, # CONST R3, #1                     ; increment = 1

        # LOOP: (address 5-8 will be fetched 4 times each)
        0b0011000100010011, # ADD R1, R1, R3                   ; counter++
        0b0010010000010010, # CMP R4, R1, R2                   ; compare counter with limit
        0b0001100000000101, # BRn LOOP (jump to addr 5 if negative) ; if counter < limit, loop

        # Store result
        0b1001010100010000, # CONST R5, #16                    ; baseC = 16
        0b0011011001010000, # ADD R6, R5, R0                   ; addr = baseC + i
        0b1000000001100001, # STR R6, R1                       ; store counter at addr
        0b1111000000000000, # RET                              ; end
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 32  # Initialize with zeros

    # Device Control - 4 threads
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    logger.info("=" * 80)
    logger.info("INSTRUCTION CACHE TEST - Loop executes same instructions 4 times")
    logger.info("=" * 80)

    data_memory.display(24)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        await RisingEdge(dut.clk)
        cycles += 1

        if cycles > 5000:
            logger.error("Timeout - exceeded 5000 cycles")
            break

    logger.info(f"\nCompleted in {cycles} cycles")
    print(f"\nCompleted in {cycles} cycles")

    data_memory.display(24)

    # Verify results - each thread should have stored counter value of 4
    expected = 4
    for i in range(threads):
        addr = 16 + i
        result = data_memory.memory[addr]
        assert result == expected, f"Thread {i}: expected {expected}, got {result}"
        logger.info(f"Thread {i}: result = {result} (correct)")

    print(f"All threads completed with correct result: {expected}")
    logger.info(f"All threads completed with correct result: {expected}")
