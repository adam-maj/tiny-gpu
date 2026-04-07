# Repository Structure

## Top-level layout

Confirmed from the local checkout:

```text
.
├── docs/
│   ├── images/
│   └── report/
├── gds/
│   ├── 0/gpu.gds
│   └── 1/gpu.gds
├── Makefile
├── README.md
├── src/
└── test/
```

## Directory roles

### `src/`

This is the complete checked-in RTL implementation:

- `gpu.sv` — top-level integration and external memory/control interface
- `core.sv` — per-core composition boundary
- `dispatch.sv` — block dispatch and completion tracking
- `controller.sv` — shared memory arbitration primitive for program/data memory
- `dcr.sv` — device control register storing `thread_count`
- `scheduler.sv` — core execution state machine
- `fetcher.sv` — instruction fetch unit
- `decoder.sv` — ISA decode logic
- `registers.sv` — per-thread register file plus SIMD metadata registers
- `pc.sv` — next-PC and NZP handling
- `lsu.sv` — per-thread load/store unit
- `alu.sv` — per-thread arithmetic unit

There is no `cache.sv` or similar cache implementation in the current tree.

### `test/`

This directory holds the cocotb testbench and helper code:

- `test_matadd.py` — matrix-add kernel simulation
- `test_matmul.py` — matrix-multiply kernel simulation
- `helpers/setup.py` — clock/reset/program/data/thread-count setup
- `helpers/memory.py` — software-backed program/data memory model
- `helpers/format.py` — trace-format helpers
- `helpers/logger.py` — log writer for execution traces
- `logs/.gitkeep` — retained log output directory

The tests act as the “host system” for the GPU by loading memory contents, writing the thread count through the device-control interface, asserting `start`, and then emulating memory readiness and responses in Python.

### `docs/`

- `docs/images/` contains the static diagrams referenced by the project README.
- `docs/report/` contains this source-verified narrative analysis set.

### `gds/`

`gds/0/gpu.gds` and `gds/1/gpu.gds` are physical-layout artifacts. The repository does not explain how they were generated or what distinguishes the two directories, so they should be treated as concrete artifacts with undocumented provenance.

## Supporting project files

### `README.md`

Acts as the main conceptual document. It explains the motivation for the project, the top-level architecture, the ISA, the example kernels, the simulation flow, and a roadmap of future enhancements.

### `Makefile`

Encodes the practical compile and test entrypoints. It transpiles SystemVerilog with `sv2v`, compiles the generated Verilog with `iverilog`, and launches cocotb via `vvp`.

### `.gitignore`

Ignores Python caches, `build/`, generated logs, some generated GDS-adjacent artifacts, `.DS_Store`, and `results.xml`.

## Module hierarchy snapshot

```mermaid
flowchart TD
    GPU[gpu.sv] --> DCR[dcr.sv]
    GPU --> Dispatch[dispatch.sv]
    GPU --> CtrlData[controller.sv\n(data memory)]
    GPU --> CtrlProg[controller.sv\n(program memory)]
    GPU --> Core[core.sv x NUM_CORES]

    Core --> Scheduler[scheduler.sv]
    Core --> Fetcher[fetcher.sv]
    Core --> Decoder[decoder.sv]
    Core --> ALU[alu.sv x THREADS_PER_BLOCK]
    Core --> LSU[lsu.sv x THREADS_PER_BLOCK]
    Core --> Regs[registers.sv x THREADS_PER_BLOCK]
    Core --> PC[pc.sv x THREADS_PER_BLOCK]
```

## Architecture seams that map cleanly to documentation

- **Host/control seam** — `start`, `done`, and the device control register
- **Dispatch seam** — block formation and assignment to cores
- **Core execution seam** — fetch/decode/schedule/update lifecycle
- **Memory seam** — internal requesters versus external memory interfaces
- **Thread-local seam** — replicated ALU/LSU/register/PC resources under shared scheduling
- **Verification seam** — RTL DUT versus Python memory model and trace logging
