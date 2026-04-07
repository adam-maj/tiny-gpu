# matadd Execution Trace Walkthrough

## Goal of this report

This chapter explains how to read the `matadd` simulation trace as a beginner.

Instead of translating every repeated log line, it focuses on the moments that actually teach you how the design works:

- how the testbench sets up the run
- what one scheduler cycle means
- why the first real instruction does not appear immediately
- how eight threads move through the same instruction stream
- when the actual data-memory writes happen

All observations below are grounded in the log file from a fresh run:

- log: `test/logs/log_20260402201022.txt`
- completed in: `178 cycles`

## What this test is trying to prove

`test/test_matadd.py` loads a tiny kernel which adds two 1×8 vectors stored in data memory.

The input layout is:

- addresses `0..7`: matrix A = `0 1 2 3 4 5 6 7`
- addresses `8..15`: matrix B = `0 1 2 3 4 5 6 7`
- addresses `16..23`: output buffer, initially all zero

The expected result is:

```text
0 2 4 6 8 10 12 14
```

The final memory dump in the log confirms exactly that:

- `data[16..23] = 0, 2, 4, 6, 8, 10, 12, 14`

## What the testbench does every cycle

The cocotb harness is simple but very important to understand.

From `test/helpers/setup.py` and `test/test_matadd.py`, the flow is:

1. start the clock
2. pulse reset
3. load program memory with the kernel instructions
4. load data memory with A and B
5. write `threads = 8` into the device control register
6. raise `start`
7. on every loop iteration:
   - `data_memory.run(cycle=cycles)` services data-memory reads/writes
   - `program_memory.run()` services instruction fetches
   - `format_cycle(dut, cycles)` logs the current machine state
   - then the test advances one rising edge

That means the trace is a combined view of:

- the RTL state inside the GPU
- the Python-side memory model acting like “external memory”

## How to read one trace block

Every cycle dump follows the same structure.

For each active core, and then for each active thread in that core, the logger shows:

- `PC`
- decoded `Instruction`
- `Core State`
- `Fetcher State`
- `LSU State`
- all register values
- selected datapath outputs like `ALU Out`, `LSU Out`, or `Constant`

For this design, the scheduler state machine is the key rhythm:

```text
FETCH -> DECODE -> REQUEST -> WAIT -> EXECUTE -> UPDATE
```

Even pure ALU or CONST instructions still pass through this full sequence, because the scheduler is intentionally simple and uniform.

## Step 1: initial memory state and idle machine

At the very top of the log, before cycle 0, the testbench prints the initial data memory table.

Then cycle 0 shows both cores still idle.

Important details from cycle 0:

- Core 0 contains logical threads `0..3`
- Core 1 contains logical threads `4..7`
- `%blockDim = 4`, so each core handles a block of four threads
- `%blockIdx = 0` on Core 0 and `%blockIdx = 1` on Core 1 once dispatch is active

At cycle 0 the trace still shows `Instruction: NOP` and `Core State: IDLE`. That is not a bug. It just means the kernel launch has been requested, but the fetch pipeline has not yet produced the first instruction word.

## Step 2: why the first real instruction appears at cycle 7

From cycles `0..6`, the machine transitions from `IDLE` into fetch activity.

At cycle 6, both cores are already in:

- `Core State: FETCH`
- `Fetcher State: FETCHING`

But the visible instruction is still `NOP`.

At cycle 7, the first real instruction appears:

```text
PC: 0
Instruction: MUL R0, %blockIdx, %blockDim
Core State: FETCH
Fetcher State: FETCHED
```

This is the first good example of how to read the fetcher:

- `FETCHING` means the request is still in flight
- `FETCHED` means the instruction bits have arrived and can now be decoded on later cycles

So the reason the log starts with several cycles of `NOP` is simply that the fetch pipeline takes a few cycles before the first instruction becomes visible in the core.

## Step 3: one instruction takes six scheduler phases

The first instruction is:

```text
MUL R0, %blockIdx, %blockDim
```

Conceptually, this computes the block base index:

```text
R0 = blockIdx * blockDim
```

In the trace, one instruction does **not** complete in one cycle.
It walks through the scheduler phases:

- `FETCH`
- `DECODE`
- `REQUEST`
- `WAIT`
- `EXECUTE`
- `UPDATE`

This is why a single kernel instruction occupies many trace entries. The trace is showing the scheduler micro-steps, not just ISA-level steps.

## Step 4: how the eight threads get different indices while sharing the same instruction stream

The second kernel instruction is:

```text
ADD R0, R0, %threadIdx
```

That is the classic GPU indexing step:

```text
i = blockIdx * blockDim + threadIdx
```

Because all threads execute the same instruction but each thread has a different `%threadIdx`, the register values diverge naturally.

For example:

- thread 0 ends with `R0 = 0`
- thread 1 ends with `R0 = 1`
- ...
- thread 7 ends with `R0 = 7`

This is one of the most important “GPU ideas” visible in the trace:

> same instruction stream, different per-thread register state

## Step 5: loading constants establishes the memory layout

The three `CONST` instructions load:

- `R1 = 0`  → base of A
- `R2 = 8`  → base of B
- `R3 = 16` → base of C

After that, each thread can compute addresses using only register arithmetic.

This is why later `ADD` instructions are easy to interpret:

- `ADD R4, R1, R0` means “address of A[i]”
- `ADD R5, R2, R0` means “address of B[i]”
- `ADD R7, R3, R0` means “address of C[i]”

## Step 6: the first real memory-dependent phase is `LDR R4, R4`

A very educational trace point appears around cycle 73.

At that point, Core 0 shows:

```text
PC: 6
Instruction: LDR R4, R4
```

And each thread already has a different `R4`:

- thread 0: `R4 = 0`
- thread 1: `R4 = 1`
- thread 2: `R4 = 2`
- thread 3: `R4 = 3`

So this one ISA instruction means:

- thread 0 loads `A[0]`
- thread 1 loads `A[1]`
- thread 2 loads `A[2]`
- thread 3 loads `A[3]`

At this point the LSU becomes interesting, because `LDR` and `STR` are the instructions that actually interact with the external Python memory model.

When reading these parts of the log, pay attention to:

- `LSU State`
- `Core State: WAIT`

Those two fields tell you when the machine is stalled waiting for memory rather than computing.

## Step 7: why stores show up as `[memwrite]` lines

The actual memory writes are not only visible through thread state. They are also explicitly emitted by `test/helpers/memory.py` as lines like:

```text
[memwrite] data cycle=151 lane=0 addr=19 old=0 new=6
```

These lines are generated by the Python memory model when it sees a valid data-memory write request.

That makes them the clearest proof of “the kernel has written its results.”

## Step 8: the first result-store burst happens at cycle 151

The first store burst in the log is:

```text
[memwrite] data cycle=151 lane=0 addr=19 old=0 new=6
[memwrite] data cycle=151 lane=1 addr=18 old=0 new=4
[memwrite] data cycle=151 lane=2 addr=17 old=0 new=2
[memwrite] data cycle=151 lane=3 addr=16 old=0 new=0
```

This is Core 0 writing results for threads `0..3`.

Notice two things:

1. the addresses are reversed by lane order in the log output (`19, 18, 17, 16`)
2. but the values are exactly the expected sums for the first four elements:

- `C[0] = 0 + 0 = 0`
- `C[1] = 1 + 1 = 2`
- `C[2] = 2 + 2 = 4`
- `C[3] = 3 + 3 = 6`

Around this same point, the threads are sitting on:

```text
Instruction: STR R7, R6
Core State: WAIT
LSU State: WAITING
```

That combination tells you the core has already issued the store and is waiting for the memory-side handshake to complete.

## Step 9: the second result-store burst happens at cycle 158

The second store burst is:

```text
[memwrite] data cycle=158 lane=0 addr=23 old=0 new=14
[memwrite] data cycle=158 lane=1 addr=22 old=0 new=12
[memwrite] data cycle=158 lane=2 addr=21 old=0 new=10
[memwrite] data cycle=158 lane=3 addr=20 old=0 new=8
```

This is Core 1 writing results for threads `4..7`:

- `C[4] = 4 + 4 = 8`
- `C[5] = 5 + 5 = 10`
- `C[6] = 6 + 6 = 12`
- `C[7] = 7 + 7 = 14`

So the two cores finish their store phases in two distinct bursts:

- Core 0 writes addresses `16..19`
- Core 1 writes addresses `20..23`

This is a nice concrete example of how the blocks are split across cores.

## Step 10: why there are duplicate-looking memwrite lines on the next cycle

You also see another burst immediately after each first burst:

```text
[memwrite] data cycle=152 ... old=6 new=6
...
[memwrite] data cycle=159 ... old=14 new=14
```

These look redundant because they are redundant from a data-content perspective.

The most useful beginner interpretation is:

> the memory model is still observing asserted write-valid behavior across another cycle, so it logs another write handshake even though the stored value is unchanged.

The important lesson is not “there are two different mathematical writes.”
The important lesson is:

- the first burst proves the result values were produced
- the second burst is a protocol-level repeat, not a second different answer

## Step 11: end of execution

Near the end of the log, the machine returns to idle and the logger prints:

```text
Completed in 178 cycles
```

Then the final data-memory table shows:

```text
Addr 16..23 = 0, 2, 4, 6, 8, 10, 12, 14
```

So the full story of the run is:

1. launch two 4-thread blocks
2. fetch the kernel
3. compute each thread’s global index
4. load A[i]
5. load B[i]
6. add them into `R6`
7. compute destination address in `R7`
8. store to output buffer
9. return

## What to focus on when you read this log yourself

If you reopen the log, do **not** try to understand every line equally.

Read in this order:

1. initial data-memory dump
2. cycle 7 — first real fetched instruction
3. the first `ADD R0, R0, %threadIdx` sequence
4. the first `LDR` sequence around cycle 73
5. the `[memwrite]` bursts at cycles 151 and 158
6. final data-memory dump

That reading order gives you the high-level execution story first.

## Beginner takeaway

This trace is a good example of SIMD execution in a tiny GPU:

- one shared control flow per core
- one private register file per thread
- identical instructions across threads
- different data because `%threadIdx` and `%blockIdx` differ
- memory latency exposed through `WAIT` and `LSU State`

Once that picture clicks, the log becomes much easier to read.
