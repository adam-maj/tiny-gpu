"""
Per-cycle DUT state snapshotting for the live simulation dashboard.

This factors the same VPI-signal extraction that test/helpers/format.py has
always used for text tracing into a JSON-serializable dict instead, so the
exact same values can be:
  - streamed live to a browser over a WebSocket (sim/server.py), and/or
  - appended to a .jsonl trace file for later replay (--replay mode),
without either consumer needing to know anything about cocotb/VPI handle
types.

Deliberately hardcodes the same NUM_CORES=2 / THREADS_PER_BLOCK=4 assumption
the rest of the test helpers already make (see format.py).
"""
from typing import Any, Dict, List, Optional

from .format import (
    _safe_int,
    format_core_state,
    format_fetcher_state,
    format_lsu_state,
    format_instruction,
)

THREADS_PER_BLOCK = 4


def _thread_snapshot(thread, core_thread_count: int, thread_slot: int) -> Dict[str, Any]:
    enabled = thread_slot < core_thread_count
    reg = thread.register_instance
    registers = [_safe_int(str(item.value)) for item in reg.registers]
    return {
        "slot": thread_slot,
        "enabled": enabled,
        "active": bool(_safe_int(str(thread.pc_instance.enable.value))) if hasattr(thread, "pc_instance") else None,
        "pc": _safe_int(str(thread.pc_instance.current_pc.value)),
        "registers": registers,
        "rs": _safe_int(str(reg.rs.value)),
        "rt": _safe_int(str(reg.rt.value)),
        "lsu_state": format_lsu_state(str(thread.lsu_instance.lsu_state.value)),
        "lsu_out": _safe_int(str(thread.lsu_instance.lsu_out.value)),
        "alu_out": _safe_int(str(thread.alu_instance.alu_out.value)),
    }


def _core_snapshot(core, core_id: int) -> Dict[str, Any]:
    ci = core.core_instance
    thread_count = _safe_int(str(ci.thread_count.value))
    active_mask_str = str(ci.active_mask.value).zfill(THREADS_PER_BLOCK)[-THREADS_PER_BLOCK:]
    # bit i (from the LSB / rightmost char) corresponds to thread i
    active_mask = [
        (c == "1") for c in active_mask_str[::-1]
    ] if all(c in "01" for c in active_mask_str) else [False] * THREADS_PER_BLOCK

    threads = [
        _thread_snapshot(thread, thread_count, i)
        for i, thread in enumerate(ci.threads)
    ]

    return {
        "id": core_id,
        "block_id": _safe_int(str(ci.block_id.value)),
        "thread_count": thread_count,
        "core_state": format_core_state(str(ci.core_state.value)),
        "current_pc": _safe_int(str(ci.current_pc.value)),
        "fetcher_state": format_fetcher_state(str(ci.fetcher_state.value)),
        "instruction": format_instruction(str(ci.instruction.value)),
        "active_mask": active_mask,
        "done": bool(_safe_int(str(ci.done.value))),
        "prefetch_hit": bool(_safe_int(str(ci.prefetch_hit.value))) if hasattr(ci, "prefetch_hit") else False,
        "threads": threads,
    }


def capture_snapshot(
    dut,
    cycle_id: int,
    data_memory=None,
    program_memory=None,
    max_data_bytes: int = 256,
) -> Dict[str, Any]:
    """
    Returns a plain-dict, JSON-serializable snapshot of the whole DUT (+ the
    external test-side data/program Memory models, if supplied) for this
    cycle. Safe to call every cycle - all VPI reads go through the same
    x/z-tolerant helpers format.py already uses for text tracing.
    """
    total_thread_count = _safe_int(str(dut.thread_count.value))

    cores: List[Dict[str, Any]] = []
    for core in dut.cores:
        core_id = int(core.i.value)
        # Same rough "does this core matter yet" heuristic as format.py
        if total_thread_count <= core_id * THREADS_PER_BLOCK and cores:
            continue
        cores.append(_core_snapshot(core, core_id))

    def _bit_list(signal, width_hint: int = 0) -> List[bool]:
        raw = str(signal.value)
        bits = []
        for c in raw[::-1]:
            bits.append(c == "1")
        if width_hint and len(bits) < width_hint:
            bits.extend([False] * (width_hint - len(bits)))
        return bits

    icache_hit = _bit_list(dut.icache_hit) if hasattr(dut, "icache_hit") else []
    icache_miss = _bit_list(dut.icache_miss) if hasattr(dut, "icache_miss") else []

    snapshot: Dict[str, Any] = {
        "cycle": cycle_id,
        "done": bool(_safe_int(str(dut.done.value))),
        "cores": cores,
        "icache_hit": icache_hit,
        "icache_miss": icache_miss,
    }

    if data_memory is not None:
        snapshot["data_memory"] = list(data_memory.memory[:max_data_bytes])
        snapshot["data_read_transactions"] = getattr(data_memory, "read_transactions", None)
        snapshot["data_write_transactions"] = getattr(data_memory, "write_transactions", None)

    if program_memory is not None:
        snapshot["program_read_transactions"] = getattr(program_memory, "read_transactions", None)

    return snapshot
