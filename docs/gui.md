# Live Simulation Dashboard

The `sim/` package is a small web dashboard that visualizes a tiny-gpu
simulation cycle-by-cycle: pipeline stage per core, per-thread PCs /
registers / active-mask, instruction-cache hit/miss pulses, and the full
data memory (rendered as a 16-wide grayscale framebuffer for the graphics
kernel).

## Quick start

```bash
source scripts/env.sh
make gui_matadd      # or gui_matmul / gui_graphics
```

Open the printed URL (default [http://localhost:8080](http://localhost:8080)).
The server compiles nothing itself - `make gui_*` builds `build/sim.vvp`
first, then launches `sim/server.py --run test.test_<name> --sim-vvp ...`,
which starts the ingest socket, serves the frontend, and spawns `vvp` with
`TINYGPU_GUI=1` so the cocotb test streams snapshots live.

## Replay a saved trace

Every GUI run also writes `build/traces/<kernel>.jsonl`. Re-open it later
without re-simulating:

```bash
source scripts/env.sh
.venv/bin/python sim/server.py --replay build/traces/graphics.jsonl
```

Replay mode adds a scrub bar and step-back.

## Controls

| Control | Effect |
|---|---|
| Play / Pause | Start or freeze the live sim / replay |
| Step | Advance exactly one cycle |
| Step back | Previous cycle (replay only) |
| Restart | Replay: jump to cycle 0 and play. Live (`make gui_*`): kill and re-launch the simulation |
| Speed | Delay between cycles while playing |
| Scrub | Jump to an arbitrary cycle (replay only) |

## On-the-wire protocol

### Simulator → server (TCP ingest, line-delimited JSON)

```json
{"type": "hello", "kernel": "matadd"}
{"type": "snapshot", "data": { ...capture_snapshot()... }}
{"type": "done"}
```

Snapshot fields are produced by `test/helpers/snapshot.py` (cores, threads,
active_mask, icache hit/miss, data_memory, transaction counters, …).

### Browser ↔ server (WebSocket `/ws`)

Server → browser: `meta`, `hello`, `snapshot`, `done`.

Browser → server (relayed to the sim in live mode):

```json
{"type": "pause"}
{"type": "play"}
{"type": "step"}
{"type": "back"}
{"type": "restart", "value": 0.08}
{"type": "speed", "value": 0.08}
{"type": "scrub", "value": 42}
```

`restart` is handled by the server itself: in replay mode it seeks to cycle 0
and resumes playback; in live mode (with `--run`) it kills the current `vvp`
process and launches a fresh one. The optional `value` field is the current
speed-slider delay in seconds.

## Environment variables

| Var | Meaning |
|---|---|
| `TINYGPU_GUI=1` | Enable `SimStreamer` inside cocotb tests |
| `TINYGPU_GUI_HOST` / `TINYGPU_GUI_PORT` | Ingest socket (default `127.0.0.1:8765`) |
| `TINYGPU_GUI_TRACE` | Optional path to append a `.jsonl` trace |
| `TINYGPU_GUI_SPEED` | Initial per-cycle delay in seconds |
| `TINYGPU_GUI_HTTP_PORT` | Dashboard HTTP port (default `8080`) |

Plain `make test_*` leaves `TINYGPU_GUI` unset, so streaming is a complete
no-op and does not affect cycle counts or pass/fail.
