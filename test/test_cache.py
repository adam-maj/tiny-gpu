import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger

@cocotb.test()
async def test_cache_reuse(dut):
    # Program Memory
    #
    # All 4 threads in this single block independently loop, each loading the *same*
    # data memory address 5 times. The first load (across all threads) is a cold miss
    # that fills the L1 cache line; every subsequent load to that same address - by any
    # thread - should be served straight out of the L1 cache. Each thread stores its
    # final loaded value to its own output slot, so we check both functional
    # correctness (the loaded value is right every time, for every thread) and that the
    # cache actually recorded hits, so this is a real test of the caching behavior and
    # not just of the underlying memory path.
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b1001000100000000, # CONST R1, #0     ; addr = 0
        0b1001001000000000, # CONST R2, #0     ; counter = 0
        0b1001001100000101, # CONST R3, #5     ; limit = 5
        0b1001010000000001, # CONST R4, #1     ; increment
        0b0111010100010000, # LOOP: LDR R5, R1 ; read the same address every iteration
        0b0011001000100100, # ADD R2, R2, R4   ; counter++
        0b0010000000100011, # CMP R2, R3
        0b0001100000000100, # BRn LOOP         ; loop while counter < limit
        0b1001011000010100, # CONST R6, #20
        0b0011011101101111, # ADD R7, R6, %threadIdx ; addr(out[i]) = 20 + threadIdx
        0b1000000001110101, # STR R7, R5       ; out[i] = last loaded value
        0b1111000000000000, # RET
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [42] + [0] * 23

    # Device Control - a full block, so every thread's PC advances correctly
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

    # The core resets (and flushes its L1, along with the rest of its state) the moment
    # its last block finishes, so we track hit/miss counts as we go rather than reading
    # them after dut.done - by then they'd already have been zeroed alongside the core.
    max_l1_hits = 0
    max_l1_misses = 0

    def safe_int(sig):
        s = str(sig.value)
        return int(s, 2) if "x" not in s and "z" not in s else 0

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        max_l1_hits = max(max_l1_hits, safe_int(dut.cores[0].core_l1_hit_count))
        max_l1_misses = max(max_l1_misses, safe_int(dut.cores[0].core_l1_miss_count))
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(24)

    for i in range(4):
        result = data_memory.memory[20 + i]
        assert result == 42, f"Result mismatch at thread {i}: expected 42, got {result}"

    l1_hits = max_l1_hits
    l1_misses = max_l1_misses
    logger.info(f"L1 (core 0): hits={l1_hits} misses={l1_misses}")

    assert l1_misses >= 1, f"Expected at least 1 L1 miss (the cold load), got {l1_misses}"
    assert l1_hits >= 4, f"Expected several L1 hits (the repeat loads across all 4 threads), got {l1_hits}"
