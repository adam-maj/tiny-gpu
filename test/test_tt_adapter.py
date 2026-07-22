import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from .helpers.logger import logger

# ---------------------------------------------------------------------------
# Host-side Python model of the byte-serial protocol implemented by
# src/tt/tt_um_tiny_gpu.sv - see docs/tiny_tapeout.md for the full reference.
#
# Handshake pins (all on the bidirectional `uio` bus):
#   bit 0 = device_ready (device -> host)   bit 1 = host_valid (host -> device)
#   bit 2 = device_valid (device -> host)   bit 3 = host_ready (host -> device)
# ---------------------------------------------------------------------------
DEVICE_READY = 0x01
HOST_VALID   = 0x02
DEVICE_VALID = 0x04
HOST_READY   = 0x08

CMD_LOAD_PROGRAM = 0x01
CMD_LOAD_DATA    = 0x02
CMD_SET_THREADS  = 0x03
CMD_START        = 0x04
CMD_READ_DATA    = 0x05
CMD_READ_STATUS  = 0x06


async def _wait_for_flag(dut, mask):
    """
    Block until (uio_out & mask) != 0. Settles 1ns after each clock edge before
    sampling uio_out (it's combinationally derived from a register - see
    tt_um_tiny_gpu.sv - so it needs a moment to propagate after the edge), then
    returns while still in a writable simulation phase (unlike ReadOnly()) so
    callers can immediately drive ui_in/uio_in afterwards.
    """
    await Timer(1, units="ns")
    while not (int(dut.uio_out.value) & mask):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")


async def send_byte(dut, byte_val):
    """Send one byte to the device, waiting for device_ready first."""
    await _wait_for_flag(dut, DEVICE_READY)
    dut.ui_in.value = byte_val
    dut.uio_in.value = int(dut.uio_in.value) | HOST_VALID
    await RisingEdge(dut.clk)
    dut.uio_in.value = int(dut.uio_in.value) & ~HOST_VALID & 0xFF
    dut.ui_in.value = 0


async def read_byte(dut):
    """Read one response byte from the device, waiting for device_valid first."""
    await _wait_for_flag(dut, DEVICE_VALID)
    value = int(dut.uo_out.value)
    dut.uio_in.value = int(dut.uio_in.value) | HOST_READY
    await RisingEdge(dut.clk)
    dut.uio_in.value = int(dut.uio_in.value) & ~HOST_READY & 0xFF
    return value


async def load_program(dut, address, instruction):
    await send_byte(dut, CMD_LOAD_PROGRAM)
    await send_byte(dut, address)
    await send_byte(dut, (instruction >> 8) & 0xFF)
    await send_byte(dut, instruction & 0xFF)


async def load_data(dut, address, value):
    await send_byte(dut, CMD_LOAD_DATA)
    await send_byte(dut, address)
    await send_byte(dut, value)


async def set_threads(dut, count):
    await send_byte(dut, CMD_SET_THREADS)
    await send_byte(dut, count)


async def start_kernel(dut):
    await send_byte(dut, CMD_START)


async def read_status(dut):
    await send_byte(dut, CMD_READ_STATUS)
    return await read_byte(dut)


async def read_data(dut, address):
    await send_byte(dut, CMD_READ_DATA)
    await send_byte(dut, address)
    return await read_byte(dut)


@cocotb.test()
async def test_tt_adapter(dut):
    """
    Smoke test for the Tiny Tapeout 7 adapter: loads a small matrix-addition
    kernel (4 elements, 1 block, matching the adapter's minimal 1-core/4-thread
    config) and its operands entirely over the byte-serial protocol, starts the
    kernel, polls status until done, then reads results back the same way and
    checks them against the expected sums - end to end proof that the adapter's
    time-multiplexed pin protocol correctly drives the underlying `gpu` core.
    """
    clock = Clock(dut.clk, 25, units="us")
    cocotb.start_soon(clock.start())

    # Reset (active-low)
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Same kernel as test_matadd.py, but for 4 elements (baseA=0, baseB=4, baseC=8)
    # to match this adapter's 1-core/4-thread minimal config.
    program = [
        0b0101000011011110,  # 0:  MUL R0, %blockIdx, %blockDim
        0b0011000000001111,  # 1:  ADD R0, R0, %threadIdx      ; i = blockIdx*blockDim + threadIdx
        0b1001000100000000,  # 2:  CONST R1, #0                ; baseA
        0b1001001000000100,  # 3:  CONST R2, #4                ; baseB
        0b1001001100001000,  # 4:  CONST R3, #8                ; baseC
        0b0011010000010000,  # 5:  ADD R4, R1, R0              ; addr(A[i])
        0b0111010001000000,  # 6:  LDR R4, R4                  ; A[i]
        0b0011010100100000,  # 7:  ADD R5, R2, R0              ; addr(B[i])
        0b0111010101010000,  # 8:  LDR R5, R5                  ; B[i]
        0b0011011001000101,  # 9:  ADD R6, R4, R5              ; C[i] = A[i] + B[i]
        0b0011011100110000,  # 10: ADD R7, R3, R0              ; addr(C[i])
        0b1000000001110110,  # 11: STR R7, R6
        0b1111000000000000,  # 12: RET
    ]
    matrix_a = [10, 20, 30, 40]
    matrix_b = [1, 2, 3, 4]

    for addr, instr in enumerate(program):
        await load_program(dut, addr, instr)

    for i, value in enumerate(matrix_a):
        await load_data(dut, i, value)
    for i, value in enumerate(matrix_b):
        await load_data(dut, 4 + i, value)

    await set_threads(dut, 4)
    await start_kernel(dut)

    cycles = 0
    done = 0
    while done != 1 and cycles < 2000:
        done = await read_status(dut)
        cycles += 1
    assert done == 1, "Kernel did not report done within the expected cycle budget"
    logger.info(f"TT adapter kernel finished (polled status {cycles} times)")

    expected_results = [a + b for a, b in zip(matrix_a, matrix_b)]
    for i, expected in enumerate(expected_results):
        result = await read_data(dut, 8 + i)
        assert result == expected, f"Result mismatch at C[{i}]: expected {expected}, got {result}"

    logger.info(f"TT adapter results verified: {expected_results}")
