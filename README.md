# tiny-gpu

A minimal GPU implementation in Verilog optimized for learning about how GPUs work from the ground up.

Built with <15 files of fully documented Verilog, complete documentation on architecture & ISA, working matrix addition/multiplication kernels, and full support for kernel simulation & execution traces.

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU](#gpu)
  - [Memory](#memory)
  - [Core](#core)
- [ISA](#isa)
- [Execution](#execution)
  - [Core](#core-1)
  - [Thread](#thread)
- [Kernels](#kernels)
  - [Matrix Addition](#matrix-addition)
  - [Matrix Multiplication](#matrix-multiplication)
  - [Graphics](#graphics)
- [Simulation](#simulation)
- [Live Dashboard](#live-dashboard)
- [Tiny Tapeout](#tiny-tapeout)
- [Implemented Optimizations](#implemented-optimizations)
- [Advanced Functionality](#advanced-functionality)
- [Next Steps](#next-steps)
- [Changelog](CHANGELOG.md)

# Overview

If you want to learn how a CPU works all the way from architecture to control signals, there are many resources online to help you.

GPUs are not the same.

Because the GPU market is so competitive, low-level technical details for all modern architectures remain proprietary.

While there are lots of resources to learn about GPU programming, there's almost nothing available to learn about how GPU's work at a hardware level.

The best option is to go through open-source GPU implementations like [Miaow](https://github.com/VerticalResearchGroup/miaow) and [VeriGPU](https://github.com/hughperkins/VeriGPU/tree/main) and try to figure out what's going on. This is challenging since these projects aim at being feature complete and functional, so they're quite complex.

This is why I built `tiny-gpu`!

## What is tiny-gpu?

> [!IMPORTANT]
>
> **tiny-gpu** is a minimal GPU implementation optimized for learning about how GPUs work from the ground up.
>
> Specifically, with the trend toward general-purpose GPUs (GPGPUs) and ML-accelerators like Google's TPU, tiny-gpu focuses on highlighting the general principles of all of these architectures, rather than on the details of graphics-specific hardware.

With this motivation in mind, we can simplify GPUs by cutting out the majority of complexity involved with building a production-grade graphics card, and focus on the core elements that are critical to all of these modern hardware accelerators.

This project is primarily focused on exploring:

1. **Architecture** - What does the architecture of a GPU look like? What are the most important elements?
2. **Parallelization** - How is the SIMD progamming model implemented in hardware?
3. **Memory** - How does a GPU work around the constraints of limited memory bandwidth?

After understanding the fundamentals laid out in this project, you can checkout the [advanced functionality section](#advanced-functionality) to understand some of the most important optimizations made in production grade GPUs (that are more challenging to implement) which improve performance.

# Architecture

<p float="left">
  <img src="/docs/images/gpu.png" alt="GPU" width="48%">
  <img src="/docs/images/core.png" alt="Core" width="48%">
</p>

## GPU

tiny-gpu is built to execute a single kernel at a time.

In order to launch a kernel, we need to do the following:

1. Load global program memory with the kernel code
2. Load data memory with the necessary data
3. Specify the number of threads to launch in the device control register
4. Launch the kernel by setting the start signal to high.

The GPU itself consists of the following units:

1. Device control register
2. Dispatcher
3. Variable number of compute cores
4. Memory controllers for data memory & program memory
5. Cache

### Device Control Register

The device control register usually stores metadata specifying how kernels should be executed on the GPU.

In this case, the device control register just stores the `thread_count` - the total number of threads to launch for the active kernel.

### Dispatcher

Once a kernel is launched, the dispatcher is the unit that actually manages the distribution of threads to different compute cores.

The dispatcher organizes threads into groups that can be executed in parallel on a single core called **blocks** and sends these blocks off to be processed by available cores.

Once all blocks have been processed, the dispatcher reports back that the kernel execution is done.

## Memory

The GPU is built to interface with an external global memory. Here, data memory and program memory are separated out for simplicity.

### Global Memory

tiny-gpu data memory has the following specifications:

- 8 bit addressability (256 total rows of data memory)
- 8 bit data (stores values of <256 for each row)

tiny-gpu program memory has the following specifications:

- 8 bit addressability (256 rows of program memory)
- 16 bit data (each instruction is 16 bits as specified by the ISA)

### Memory Controllers

Global memory has fixed read/write bandwidth, but there may be far more incoming requests across all cores to access data from memory than the external memory is actually able to handle.

The memory controllers keep track of all the outgoing requests to memory from the compute cores, throttle requests based on actual external memory bandwidth, and relay responses from external memory back to the proper resources. When multiple consumers request a **read of the same address** in one arbitration round, the controller **coalesces** them into a single external transaction and broadcasts the response.

Each memory controller has a fixed number of channels based on the bandwidth of global memory.

### Instruction Cache

Each core's fetcher talks to a dedicated 16-line direct-mapped **instruction cache** (`src/icache.sv`) before the shared program-memory controller. Hits return the instruction without touching external program memory; misses fill the line and cost the same as an uncached fetch. Loop-heavy kernels (matmul) benefit the most — see `test/test_icache.py`.

## Core

Each core has a number of compute resources, often built around a certain number of threads it can support. In order to maximize parallelization, these resources need to be managed optimally to maximize resource utilization.

In this simplified GPU, each core processed one **block** at a time, and for each thread in a block, the core has a dedicated ALU, LSU, PC, and register file. Managing the execution of thread instructions on these resources is one of the most challening problems in GPUs.

### Scheduler

Each core has a single scheduler that manages the execution of threads.

The tiny-gpu scheduler executes instructions for a single block to completion before picking up a new block. With **branch divergence** support, each thread owns its own PC: each round the scheduler picks the lowest PC among unfinished threads, latches an `active_mask` of threads at that PC, and only those threads execute the fetched instruction. Diverged threads reconverge naturally when their PCs meet again.

Non-memory instructions skip the WAIT state entirely, and decoding is combinational so DECODE also covers what used to be a separate REQUEST cycle. The fetcher additionally **speculatively prefetches PC+1** during WAIT/EXECUTE/UPDATE (basic pipelining).

### Fetcher

Asynchronously fetches the instruction at the current program counter from program memory (most should actually be fetching from cache after a single block is executed).

### Decoder

Decodes the fetched instruction into control signals for thread execution.

### Register Files

Each thread has it's own dedicated set of register files. The register files hold the data that each thread is performing computations on, which enables the same-instruction multiple-data (SIMD) pattern.

Importantly, each register file contains a few read-only registers holding data about the current block & thread being executed locally, enabling kernels to be executed with different data based on the local thread id.

### ALUs

Dedicated arithmetic-logic unit for each thread to perform computations. Handles the `ADD`, `SUB`, `MUL`, `DIV` arithmetic instructions.

Also handles the `CMP` comparison instruction which actually outputs whether the result of the difference between two registers is negative, zero or positive - and stores the result in the `NZP` register in the PC unit.

### LSUs

Dedicated load-store unit for each thread to access global data memory.

Handles the `LDR` & `STR` instructions - and handles async wait times for memory requests to be processed and relayed by the memory controller.

### PCs

Dedicated program-counter for each unit to determine the next instructions to execute on each thread.

By default, the PC increments by 1 after every instruction.

With the `BRnzp` instruction, the NZP register checks to see if the NZP register (set by a previous `CMP` instruction) matches some case - and if it does, it will branch to a specific line of program memory. _This is how loops and conditionals are implemented._

Each thread owns its own PC and NZP flags, so divergent `BRnzp` outcomes are handled correctly — inactive threads simply sit out rounds until the scheduler picks their PC.

# ISA

![ISA](/docs/images/isa.png)

tiny-gpu implements a simple 11 instruction ISA built to enable simple kernels for proof-of-concept like matrix addition & matrix multiplication (implementation further down on this page).

For these purposes, it supports the following instructions:

- `BRnzp` - Branch instruction to jump to another line of program memory if the NZP register matches the `nzp` condition in the instruction.
- `CMP` - Compare the value of two registers and store the result in the NZP register to use for a later `BRnzp` instruction.
- `ADD`, `SUB`, `MUL`, `DIV` - Basic arithmetic operations to enable tensor math.
- `LDR` - Load data from global memory.
- `STR` - Store data into global memory.
- `CONST` - Load a constant value into a register.
- `RET` - Signal that the current thread has reached the end of execution.

Each register is specified by 4 bits, meaning that there are 16 total registers. The first 13 register `R0` - `R12` are free registers that support read/write. The last 3 registers are special read-only registers used to supply the `%blockIdx`, `%blockDim`, and `%threadIdx` critical to SIMD.

# Execution

### Core

Each core follows the following control flow going through different stages to execute each instruction:

1. `FETCH` - Fetch the next instruction at current program counter from program memory.
2. `DECODE` - Decode the instruction into control signals.
3. `REQUEST` - Request data from global memory if necessary (if `LDR` or `STR` instruction).
4. `WAIT` - Wait for data from global memory if applicable.
5. `EXECUTE` - Execute any computations on data.
6. `UPDATE` - Update register files and NZP register.

The control flow is laid out like this for the sake of simplicity and understandability.

In practice, several of these steps could be compressed to be optimize processing times, and the GPU could also use **pipelining** to stream and coordinate the execution of many instructions on a cores resources without waiting for previous instructions to finish.

### Thread

![Thread](/docs/images/thread.png)

Each thread within each core follows the above execution path to perform computations on the data in it's dedicated register file.

This resembles a standard CPU diagram, and is quite similar in functionality as well. The main difference is that the `%blockIdx`, `%blockDim`, and `%threadIdx` values lie in the read-only registers for each thread, enabling SIMD functionality.

# Kernels

I wrote a matrix addition and matrix multiplication kernel using my ISA as a proof of concept to demonstrate SIMD programming and execution with my GPU. The test files in this repository are capable of fully simulating the execution of these kernels on the GPU, producing data memory states and a complete execution trace.

### Matrix Addition

This matrix addition kernel adds two 1 x 8 matrices by performing 8 element wise additions in separate threads.

This demonstration makes use of the `%blockIdx`, `%blockDim`, and `%threadIdx` registers to show SIMD programming on this GPU. It also uses the `LDR` and `STR` instructions which require async memory management.

`matadd.asm`

```asm
.threads 8
.data 0 1 2 3 4 5 6 7          ; matrix A (1 x 8)
.data 0 1 2 3 4 5 6 7          ; matrix B (1 x 8)

MUL R0, %blockIdx, %blockDim
ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx

CONST R1, #0                   ; baseA (matrix A base address)
CONST R2, #8                   ; baseB (matrix B base address)
CONST R3, #16                  ; baseC (matrix C base address)

ADD R4, R1, R0                 ; addr(A[i]) = baseA + i
LDR R4, R4                     ; load A[i] from global memory

ADD R5, R2, R0                 ; addr(B[i]) = baseB + i
LDR R5, R5                     ; load B[i] from global memory

ADD R6, R4, R5                 ; C[i] = A[i] + B[i]

ADD R7, R3, R0                 ; addr(C[i]) = baseC + i
STR R7, R6                     ; store C[i] in global memory

RET                            ; end of kernel
```

### Matrix Multiplication

The matrix multiplication kernel multiplies two 2x2 matrices. It performs element wise calculation of the dot product of the relevant row and column and uses the `CMP` and `BRnzp` instructions to demonstrate branching within the threads (notably, all branches converge so this kernel works on the current tiny-gpu implementation).

`matmul.asm`

```asm
.threads 4
.data 1 2 3 4                  ; matrix A (2 x 2)
.data 1 2 3 4                  ; matrix B (2 x 2)

MUL R0, %blockIdx, %blockDim
ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx

CONST R1, #1                   ; increment
CONST R2, #2                   ; N (matrix inner dimension)
CONST R3, #0                   ; baseA (matrix A base address)
CONST R4, #4                   ; baseB (matrix B base address)
CONST R5, #8                   ; baseC (matrix C base address)

DIV R6, R0, R2                 ; row = i // N
MUL R7, R6, R2
SUB R7, R0, R7                 ; col = i % N

CONST R8, #0                   ; acc = 0
CONST R9, #0                   ; k = 0

LOOP:
  MUL R10, R6, R2
  ADD R10, R10, R9
  ADD R10, R10, R3             ; addr(A[i]) = row * N + k + baseA
  LDR R10, R10                 ; load A[i] from global memory

  MUL R11, R9, R2
  ADD R11, R11, R7
  ADD R11, R11, R4             ; addr(B[i]) = k * N + col + baseB
  LDR R11, R11                 ; load B[i] from global memory

  MUL R12, R10, R11
  ADD R8, R8, R12              ; acc = acc + A[i] * B[i]

  ADD R9, R9, R1               ; increment k

  CMP R9, R2
  BRn LOOP                    ; loop while k < N

ADD R9, R5, R0                 ; addr(C[i]) = baseC + i
STR R9, R8                     ; store C[i] in global memory

RET                            ; end of kernel
```

### Graphics

The graphics kernel (`kernels/graphics.asm`, `test/test_graphics.py`) treats data memory as a 16×15 grayscale framebuffer. Each of 240 threads paints one pixel: a filled circle via squared distance from center, using a divergent `CMP`/`BRn` path for inside vs outside intensity. Open it in the live dashboard (`make gui_graphics`) to watch the framebuffer fill in.

# Simulation

### Quick setup (no sudo)

```bash
bash scripts/setup.sh   # downloads iverilog + sv2v into .tools/, creates .venv
source scripts/env.sh
make test_all           # matadd, matmul, divergence, coalescing, icache, graphics, TT adapter
```

Or install [iverilog](https://steveicarus.github.io/iverilog/usage/installation.html), [sv2v](https://github.com/zachjs/sv2v/releases), and `pip install -r requirements.txt` (pins **cocotb 1.9.2**), then `mkdir -p build`.

Individual kernels: `make test_matadd`, `make test_matmul`, etc. Each run writes a text execution trace under `test/logs/`.

![execution trace](docs/images/trace.png)

# Live Dashboard

```bash
source scripts/env.sh
make gui_matadd      # or gui_matmul / gui_graphics
```

Opens a browser dashboard at [http://localhost:8080](http://localhost:8080) that streams per-cycle core/pipeline state, thread registers & active masks, i-cache activity, and a data-memory heatmap (framebuffer view for graphics). Pause / step / speed controls talk back to the simulator. Runs also save `build/traces/<kernel>.jsonl` for offline replay:

```bash
.venv/bin/python sim/server.py --replay build/traces/graphics.jsonl
```

See [docs/gui.md](docs/gui.md) for the WebSocket/TCP protocol.

# Tiny Tapeout

`src/tt/tt_um_tiny_gpu.sv` wraps a minimal GPU (1 core, 4 threads, 1 data channel) behind the Tiny Tapeout 7 pinout with a byte-serial memory/control protocol. Simulation-only scaffolding — see [docs/tiny_tapeout.md](docs/tiny_tapeout.md) and `make test_tt`.

# Implemented Optimizations

| Feature | Where | Effect (vs original 178 / 491 cycle baselines) |
|---|---|---|
| Control-flow fold (skip WAIT, combinational DECODE) | `scheduler.sv`, `decoder.sv`, `registers.sv` | Fewer cycles per ALU/branch/const op |
| Instruction cache | `icache.sv` | Loop-heavy fetches hit without program-mem traffic |
| Same-address read coalescing | `controller.sv` | Shared loads share one external transaction |
| Branch divergence | `scheduler.sv`, `pc.sv` | Correct divergent `BRnzp`; natural reconverge |
| Speculative PC+1 prefetch | `fetcher.sv` | Hides fetch latency on straight-line code |

Final measured cycles: **matadd 115**, **matmul 256** (see [CHANGELOG.md](CHANGELOG.md)).

# Advanced Functionality

Some production-GPU features are still out of scope for this teaching design:

### Multi-layered Cache & Shared Memory

tiny-gpu now has a per-core instruction cache, but no data cache hierarchy and no block-local shared memory. Those remain the next memory-system steps.

### Warp Scheduling

Breaking blocks into warps that interleave on one core while another waits on memory is not implemented — the current scheduler still runs one PC group at a time per core.

### Synchronization & Barriers

There is no `__syncthreads`-style barrier; threads only "meet" by natural PC reconvergence after divergence.

# Next Steps

Completed from the original roadmap:

- [x] Add a simple cache for instructions
- [x] Build an adapter to use GPU with Tiny Tapeout 7
- [x] Add basic branch divergence
- [x] Add basic memory coalescing
- [x] Add basic pipelining
- [x] Optimize control flow and use of registers to improve cycle time
- [x] Write a basic graphics kernel

Still interesting follow-ups:

- [ ] Data cache / shared memory
- [ ] Warp scheduling
- [ ] Deeper (multi-stage) instruction pipelining
- [ ] Native desktop (PyQt) dashboard reusing the same JSON snapshot protocol
- [ ] OpenLane / TT tapeout hardening beyond sim-only scaffolding

**For anyone curious to play around or make a contribution, feel free to put up a PR with any improvements you'd like to add 😄**
