# tiny-gpu Independent Module Guide

These notes explain both:

- the small, independent building-block modules in `src/`
- the two integration layers that assemble them: `core.sv` and `gpu.sv`

They are meant to be read **side by side with the SystemVerilog source**. The focus is not just "what this line does," but **what role the module plays in the whole GPU** and **how to mentally trace it over time**.

This set is grounded in:

- the actual RTL in `src/*.sv`
- the repo's DeepWiki architecture pages (`Overview`, `Architecture Overview`, `Execution Model`, `Hardware Modules`, `Memory System`)

## Recommended reading order

1. [`scheduler.md`](./scheduler.md) — the global per-instruction rhythm of a core
2. [`decoder.md`](./decoder.md) — how instruction bits become control signals
3. [`fetcher.md`](./fetcher.md) — instruction fetch handshake
4. [`registers.md`](./registers.md) — operand reads and writeback timing
5. [`alu.md`](./alu.md) — arithmetic and compare execution
6. [`pc.md`](./pc.md) — branch and NZP behavior
7. [`lsu.md`](./lsu.md) — per-thread data-memory access
8. [`controller.md`](./controller.md) — how many requesters share few memory channels
9. [`dispatch.md`](./dispatch.md) — how thread_count becomes blocks on cores
10. [`dcr.md`](./dcr.md) — where launch metadata comes from
11. [`core.md`](./core.md) — how one core combines shared control with replicated thread lanes
12. [`gpu.md`](./gpu.md) — how the whole chip is wired together

## Module list

- [`alu.md`](./alu.md)
- [`controller.md`](./controller.md)
- [`dcr.md`](./dcr.md)
- [`decoder.md`](./decoder.md)
- [`dispatch.md`](./dispatch.md)
- [`fetcher.md`](./fetcher.md)
- [`core.md`](./core.md)
- [`gpu.md`](./gpu.md)
- [`lsu.md`](./lsu.md)
- [`pc.md`](./pc.md)
- [`registers.md`](./registers.md)
- [`scheduler.md`](./scheduler.md)

## What is intentionally not covered here

- advanced GPU topics like warp scheduling, coalescing, or branch divergence handling

Those are better understood **after** the smaller modules feel natural.
