import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger
from .helpers.streaming import SimStreamer

# ---------------------------------------------------------------------------
# Tiny assembler helpers (see src/decoder.sv for the exact bit layout) - used
# instead of hand-written binary literals since this kernel is long enough
# that hand-encoding would be error-prone.
# ---------------------------------------------------------------------------
def _rrr(opcode, rd=0, rs=0, rt=0):
    """Register-register-register format: opcode[15:12] rd[11:8] rs[7:4] rt[3:0]."""
    return ((opcode & 0xF) << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4) | (rt & 0xF)

def CONST(rd, imm):
    """opcode[15:12] rd[11:8] immediate[7:0] - NOTE: rd lives in bits [11:8], distinct
    from BRnzp's nzp field below despite overlapping bit positions."""
    return (0b1001 << 12) | ((rd & 0xF) << 8) | (imm & 0xFF)

def ADD(rd, rs, rt): return _rrr(0b0011, rd, rs, rt)
def SUB(rd, rs, rt): return _rrr(0b0100, rd, rs, rt)
def MUL(rd, rs, rt): return _rrr(0b0101, rd, rs, rt)
def DIV(rd, rs, rt): return _rrr(0b0110, rd, rs, rt)
def CMP(rs, rt): return _rrr(0b0010, rd=0, rs=rs, rt=rt)
def STR(addr_reg, data_reg): return _rrr(0b1000, rd=0, rs=addr_reg, rt=data_reg)
def RET(): return _rrr(0b1111)

# NZP condition bits (matches alu_out[2:0] / pc.sv's nzp register): bit2=P (rs>rt),
# bit1=Z (rs==rt), bit0=N (rs<rt - only reliable after the alu.sv fix, see there).
N, Z, P = 0b001, 0b010, 0b100
def BR(nzp, target):
    """opcode[15:12] nzp[11:9] (bit8 unused) immediate[7:0]."""
    return (0b0001 << 12) | ((nzp & 0x7) << 9) | (target & 0xFF)

R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12 = range(13)
BLOCK_IDX, BLOCK_DIM, THREAD_IDX = 13, 14, 15

GRID = 16    # framebuffer width (row/col divisor used by the kernel itself)
HEIGHT = 15  # framebuffer height - 16x16=256 would overflow the 8-bit thread_count
             # device control register (max 255), so this renders a 16x15 window
             # instead (240 threads, still a full, clearly-round circle).
CENTER = 7
CENTER_SQ = CENTER * CENTER            # 49
TWO_CENTER = 2 * CENTER                # 14
RADIUS = 6
RADIUS_SQ_PLUS_1 = RADIUS * RADIUS + 1  # 37 -> branch fires for dist_sq <= 36
INTENSITY_IN = 255
INTENSITY_OUT = 50


def build_program():
    """
    Per-thread pixel math (all integer, done entirely with unsigned 8-bit ALU ops):
        i   = blockIdx * blockDim + threadIdx      ; linear pixel index, 0-255
        row = i / 16 ; col = i % 16                ; 2D coordinates in the grid
        dist_sq = (row - CENTER)^2 + (col - CENTER)^2

    (row - CENTER)^2 is computed as row^2 - row*(2*CENTER) + CENTER^2 - the
    algebraic expansion of the square, using only ADD/SUB/MUL. This works
    correctly under this ALU's *unsigned* subtraction (which wraps around
    instead of going negative - see alu.sv): row^2 - row*2*CENTER can wrap
    to a large intermediate value when row < CENTER, but since the true
    mathematical result of the full expression is always in [0, 255] for
    this grid, modular addition self-corrects once CENTER^2 is added back.
    E.g. row=7 (== CENTER): row^2=49, row*2*CENTER=98, 49-98 wraps to 207,
    207+49=256 which wraps to 0 - the correct answer, since (7-7)^2=0.

    Each thread then does exactly ONE comparison (dist_sq vs RADIUS^2+1) and
    branches on the ALU's N ("less than") flag to pick between two intensity
    levels, then every thread reconverges on a single common store - real
    branch divergence (see scheduler.sv) used for something visual.
    """
    return [
        MUL(R0, BLOCK_IDX, BLOCK_DIM),      # 0:  R0 = blockIdx * blockDim
        ADD(R0, R0, THREAD_IDX),            # 1:  R0 = i (stable - also the framebuffer address)
        CONST(R1, GRID),                    # 2:  R1 = 16
        DIV(R2, R0, R1),                    # 3:  R2 = row = i / 16
        MUL(R7, R2, R1),                    # 4:  R7 = row * 16 (temp)
        SUB(R3, R0, R7),                    # 5:  R3 = col = i - row*16
        CONST(R5, CENTER_SQ),               # 6:  R5 = CENTER^2 = 49
        CONST(R6, TWO_CENTER),              # 7:  R6 = 2*CENTER = 14
        MUL(R7, R2, R2),                    # 8:  R7 = row^2
        MUL(R8, R2, R6),                    # 9:  R8 = row * 2*CENTER
        SUB(R7, R7, R8),                    # 10: R7 = row^2 - row*2*CENTER (may wrap - see above)
        ADD(R7, R7, R5),                    # 11: R7 = dx_sq = (row-CENTER)^2
        MUL(R9, R3, R3),                    # 12: R9 = col^2
        MUL(R10, R3, R6),                   # 13: R10 = col * 2*CENTER
        SUB(R9, R9, R10),                   # 14: R9 = col^2 - col*2*CENTER
        ADD(R9, R9, R5),                    # 15: R9 = dy_sq = (col-CENTER)^2
        ADD(R11, R7, R9),                   # 16: R11 = dist_sq = dx_sq + dy_sq
        CONST(R12, RADIUS_SQ_PLUS_1),       # 17: R12 = RADIUS^2 + 1 = 37
        CMP(R11, R12),                      # 18: compare dist_sq, 37
        BR(N, 22),                          # 19: if dist_sq < 37 (i.e. <= 36) -> INSIDE @22
        CONST(R12, INTENSITY_OUT),          # 20: OUTSIDE: R12 = dim intensity
        BR(P | Z | N, 23),                 # 21: unconditional -> STORE @23 (skip INSIDE block)
        CONST(R12, INTENSITY_IN),           # 22: INSIDE: R12 = bright intensity (falls through)
        STR(R0, R12),                       # 23: framebuffer[i] = R12
        RET(),                              # 24
    ]


def expected_framebuffer():
    """Python reference model (true signed integer math, no ALU quirks) for
    the same circle - used to check the DUT's rendered output."""
    fb = [0] * (GRID * HEIGHT)
    for row in range(HEIGHT):
        for col in range(GRID):
            dist_sq = (row - CENTER) ** 2 + (col - CENTER) ** 2
            i = row * GRID + col
            fb[i] = INTENSITY_IN if dist_sq <= RADIUS * RADIUS else INTENSITY_OUT
    return fb


@cocotb.test()
async def test_graphics(dut):
    """
    Renders a filled circle into a 16x15 (240-byte) framebuffer window - one
    thread per pixel, 240 threads total (60 blocks of 4, spread across the 2
    cores; a full 16x16=256 grid would overflow the 8-bit thread_count device
    control register). See build_program()'s docstring for the per-thread math
    and how it uses the newly-fixed ALU "less than" flag for real branch
    divergence.
    """
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = build_program()

    # No inputs needed - the kernel only writes to data memory (the framebuffer)
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = []

    threads = GRID * HEIGHT  # 240 - one thread per rendered pixel

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    streamer = SimStreamer("graphics")
    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)
        await streamer.tick(dut, cycles, data_memory=data_memory, program_memory=program_memory)

        await RisingEdge(dut.clk)
        cycles += 1
    streamer.close()

    logger.info(f"Completed in {cycles} cycles")

    expected = expected_framebuffer()
    mismatches = []
    for i, expected_value in enumerate(expected):
        actual = data_memory.memory[i]
        if actual != expected_value:
            mismatches.append((i, expected_value, actual))

    # Render an ASCII preview of both framebuffers for a human-readable log
    def render(fb):
        lines = []
        for row in range(HEIGHT):
            line = ""
            for col in range(GRID):
                line += "#" if fb[row * GRID + col] >= INTENSITY_IN else "."
            lines.append(line)
        return "\n".join(lines)

    logger.info("Expected:\n" + render(expected))
    logger.info("Actual:\n" + render(data_memory.memory[:GRID * HEIGHT]))

    assert not mismatches, (
        f"{len(mismatches)} pixel mismatches (showing first 5): "
        f"{mismatches[:5]} (index, expected, actual)"
    )
