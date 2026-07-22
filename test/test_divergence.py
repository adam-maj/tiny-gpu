import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_divergence(dut):
    """
    A genuinely divergent kernel: threads with threadIdx == 0 or 1 take a SHORT
    branch (THEN), threads with threadIdx == 2 or 3 take a LONGER branch (ELSE,
    2 extra instructions) before both paths reconverge on a common store+RET. This
    produces two different per-thread PC trajectories for a few rounds - exactly
    the case that would silently compute the wrong answer on hardware with a single
    shared PC (the old design always just took `next_pc[THREADS_PER_BLOCK-1]`, so
    every thread would end up following whichever branch the *last* thread took).

    NOTE: branches only use the CMP "Z" (equal) flag, not P/N, since alu.sv does
    plain unsigned `rs - rt`: when rs < rt this wraps around to a large positive
    value and (incorrectly) also sets P, making P indistinguishable from a genuine
    rs > rt. Z is unaffected by this and is what the *existing* kernels also rely on
    for their loop conditions. Basic branch divergence doesn't require fixing that
    pre-existing ALU quirk, so this test (deliberately) sticks to equality checks.

    Program (addresses in comments):
      0: CONST R1, #0                     ; compare value 0
      1: CMP R15, R1                      ; threadIdx == 0 ?
      2: BRnzp[Z] -> 8                    ; if threadIdx == 0, jump to THEN (addr 8)
      3: CONST R1, #1                     ; compare value 1
      4: CMP R15, R1                      ; threadIdx == 1 ?
      5: BRnzp[Z] -> 8                    ; if threadIdx == 1, jump to THEN (addr 8)
      6: CONST R2, #20                    ; ELSE (threadIdx 2 or 3): 2 extra
                                           ; instructions only ELSE threads execute
      7: BRnzp[NZP] -> 9                  ; unconditional jump to MERGE (addr 9)
      8: CONST R2, #10                    ; THEN (threadIdx 0 or 1): falls through
      9: CONST R3, #100                   ; MERGE: base output address
      10: ADD R4, R3, R15                 ; addr(out[i]) = base + threadIdx
      11: STR R4, R2                      ; store this thread's R2 (10 or 20)
      12: RET
    """
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b1001000100000000, # 0: CONST R1, #0
        0b0010000011110001, # 1: CMP R15, R1
        0b0001010000001000, # 2: BRnzp[Z] -> 8
        0b1001000100000001, # 3: CONST R1, #1
        0b0010000011110001, # 4: CMP R15, R1
        0b0001010000001000, # 5: BRnzp[Z] -> 8
        0b1001001000010100, # 6: CONST R2, #20
        0b0001111000001001, # 7: BRnzp[NZP] -> 9
        0b1001001000001010, # 8: CONST R2, #10
        0b1001001101100100, # 9: CONST R3, #100
        0b0011010000111111, # 10: ADD R4, R3, R15
        0b1000000001000010, # 11: STR R4, R2
        0b1111000000000000, # 12: RET
    ]

    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = []

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

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

    # threadIdx 0,1 take THEN (R2=10); threadIdx 2,3 take ELSE (R2=20)
    expected_results = [10, 10, 20, 20]
    for idx, expected in enumerate(expected_results):
        result = data_memory.memory[100 + idx]
        assert result == expected, (
            f"Thread {idx} took the wrong branch: expected {expected}, got {result}"
        )
