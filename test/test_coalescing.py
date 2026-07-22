import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_coalescing(dut):
    """
    Every thread in the (single) block loads the SAME shared address, then writes
    a per-thread result out. Because all 4 threads issue their LDR in lockstep
    (SIMD), the memory controller sees 4 identical-address read requests in the
    very same cycle - exactly the case memory coalescing (controller.sv) is meant
    to fold into a single external-memory transaction instead of serving each
    thread's request separately across the controller's 4 channels.
    """
    # Program Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b1001000100000000, # CONST R1, #0                   ; shared address every thread reads
        0b0111001000010000, # LDR R2, R1                     ; load the shared value
        0b0011001100101111, # ADD R3, R2, %threadIdx          ; result = shared value + threadIdx
        0b1001010000001010, # CONST R4, #10                  ; base output address
        0b0011010101001111, # ADD R5, R4, %threadIdx          ; addr(out[i]) = base + threadIdx
        0b1000000001010011, # STR R5, R3                     ; store result
        0b1111000000000000, # RET                            ; end of kernel
    ]

    # Data Memory - address 0 holds the one shared value every thread will load
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    shared_value = 42
    data = [shared_value]

    # Device Control - single block, all 4 threads execute in lockstep
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(16)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(16)
    logger.info(f"Data memory read transactions: {data_memory.read_transactions}")
    logger.info(f"Data memory write transactions: {data_memory.write_transactions}")

    # Correctness: out[10+idx] = shared_value + idx
    for idx in range(threads):
        expected = shared_value + idx
        result = data_memory.memory[10 + idx]
        assert result == expected, f"Result mismatch at thread {idx}: expected {expected}, got {result}"

    # The whole point of coalescing: 4 threads reading the exact same address in the
    # same cycle should result in exactly ONE external memory read transaction, not 4.
    assert data_memory.read_transactions == 1, (
        f"Expected reads from 4 threads to the same address to coalesce into 1 "
        f"transaction, but the controller issued {data_memory.read_transactions}"
    )

    # The 4 STRs go to 4 *different* addresses (10..13), so those should NOT coalesce.
    assert data_memory.write_transactions == threads, (
        f"Expected {threads} separate write transactions (different addresses), "
        f"got {data_memory.write_transactions}"
    )
