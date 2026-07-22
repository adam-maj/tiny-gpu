# Changelog

All notable enhancements to tiny-gpu since the original learning-focused
baseline (matadd **178** cycles / matmul **491** cycles).

## [Unreleased] — Roadmap Overhaul

### Cycle counts (final, measured with local toolchain)

| Kernel / test | Baseline | Final | Δ |
|---|---:|---:|---:|
| `test_matadd` | 178 | **115** | −35% |
| `test_matmul` | 491 | **256** | −48% |
| `test_divergence` | — | 82 | new |
| `test_coalescing` | — | 60 | new |
| `test_icache` (matmul) | — | 256 | new |
| `test_graphics` (16×15 circle) | — | 5545 | new |
| `test_tt_adapter` | — | smoke pass | new |

### Added

- **Control-flow optimization** (`src/scheduler.sv`, `src/decoder.sv`, `src/registers.sv`):
  combinational decode folds the old REQUEST cycle into DECODE; WAIT is
  skipped entirely for non-memory ops; `%blockIdx` is latched once on
  core start instead of every cycle.
- **Instruction cache** (`src/icache.sv`): 16-line direct-mapped i-cache
  between each fetcher and the shared program-memory controller, with
  hit/miss pulses for the dashboard (`test/test_icache.py`).
- **Memory coalescing** (`src/controller.sv`): same-address reads in one
  arbitration round share a single external transaction and broadcast the
  response (`test/test_coalescing.py`).
- **Branch divergence** (`src/scheduler.sv`, `src/pc.sv`, `src/core.sv`):
  per-thread PCs + latched active-mask; lowest-PC scheduling with natural
  reconvergence; `RET` retires threads individually
  (`test/test_divergence.py`).
- **Basic pipelining** (`src/fetcher.sv`): speculative PC+1 prefetch during
  WAIT/EXECUTE/UPDATE; mispredicts discard and fall back to a normal fetch.
- **Tiny Tapeout 7 adapter** (`src/tt/tt_um_tiny_gpu.sv`): byte-serial
  protocol over the TT pinout, cocotb smoke test, `docs/tiny_tapeout.md`,
  `info.yaml` stub.
- **Graphics kernel** (`kernels/graphics.asm`, `test/test_graphics.py`):
  16×15 framebuffer circle using divergent CMP/BRn paths.
- **Live web dashboard** (`sim/server.py`, `sim/web/`): WebSocket streaming,
  pause/step/speed, replay of `.jsonl` traces, pipeline + register +
  memory/framebuffer views (`docs/gui.md`). `make gui_matadd` /
  `gui_matmul` / `gui_graphics`.
- **Snapshot helper** (`test/helpers/snapshot.py`, `streaming.py`): shared
  JSON extraction for text logs, live stream, and saved traces.
- **Build / tooling**: `requirements.txt` (cocotb 1.9.2, aiohttp), Makefile
  `--lib-dir`, `make test_all`, `scripts/setup.sh` + `scripts/env.sh` for a
  sudo-free local toolchain.

### Fixed

- ALU `CMP` N flag now uses a real unsigned `<` comparator (`src/alu.sv`)
  so "less than" branches work (previously always 0 on unsigned subtract).

### Future plans

- Native **desktop (PyQt)** dashboard reusing the same JSON snapshot
  protocol, with waveform-style scrubbing and multi-kernel comparison.
- Data cache, warp scheduling, and deeper pipelining beyond the one-deep
  speculative prefetch.
