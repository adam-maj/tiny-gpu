# matmul Execution Trace Walkthrough

## Goal of this report

This chapter explains the `matmul` execution trace in a way that is useful for a Verilog beginner.

This kernel is more interesting than `matadd` because it contains:

- address arithmetic
- a loop
- a compare instruction
- a branch instruction
- repeated loads and multiplies
- a final store after the loop finishes

All observations below are grounded in a fresh run:

- log: `test/logs/log_20260402201026.txt`
- completed in: `491 cycles`

## What this test is trying to prove

`test/test_matmul.py` multiplies two 2×2 matrices:

- matrix A at addresses `0..3` = `1 2 3 4`
- matrix B at addresses `4..7` = `1 2 3 4`
- output C at addresses `8..11`, initially zero

The expected result matrix is:

```text
7 10
15 22
```

The final memory dump confirms:

- `data[8..11] = 7, 10, 15, 22`

## One very important logging detail

Unlike `matadd`, this test does **not** log every thread’s full state.

It calls:

```python
format_cycle(dut, cycles, thread_id=1)
```

So the per-cycle trace is filtered to **logical thread 1 only**.

That means:

- register dumps are only for thread 1
- instruction/state lines are only for thread 1
- but `[memwrite]` lines still show all four lanes when the store happens

This is why the report focuses on thread 1 as the “main character,” then uses the final memwrite burst to show that all threads completed.

## What thread 1 is computing

For a 2×2 matrix multiply, there are 4 output elements, so there are 4 threads.

Thread 1 corresponds to global index `i = 1`.

The kernel computes:

- `row = i // N`
- `col = i % N`

with `N = 2`.

So for thread 1:

- `row = 0`
- `col = 1`

That means thread 1 is responsible for output element:

```text
C[0,1]
```

Mathematically:

```text
C[0,1] = A[0,0] * B[0,1] + A[0,1] * B[1,1]
       = 1 * 2 + 2 * 4
       = 10
```

The final trace shows thread 1 ends with `R8 = 10`, which matches that expected dot product.

## How to read the scheduler rhythm

Just like `matadd`, each ISA instruction goes through the same scheduler stages:

```text
FETCH -> DECODE -> REQUEST -> WAIT -> EXECUTE -> UPDATE
```

This is why even simple instructions like `CONST` appear across multiple cycles.

For example, around cycles `40..45`, the trace shows `CONST R2, #2` moving through:

- FETCH
- DECODE
- REQUEST
- WAIT
- EXECUTE
- UPDATE

Only after that does `R2` actually become `2` in the register dump.

That is the right beginner mental model:

> the trace is showing the scheduler’s control steps, not just the instruction list in assembly.

## Step 1: startup and first real instruction

As in `matadd`, the early cycles are not yet “real compute.”

At cycles `0..6`, thread 1 is still showing `NOP` while fetch is warming up.

At cycle 7, the first real instruction appears:

```text
PC: 0
Instruction: MUL R0, %blockIdx, %blockDim
```

Then the second instruction is:

```text
ADD R0, R0, %threadIdx
```

For thread 1, that gives:

```text
R0 = 1
```

which is its global thread index.

## Step 2: setting up constants and thread coordinates

The next few instructions establish the constants needed for matrix math:

- `R1 = 1`  → increment value for loop counter
- `R2 = 2`  → matrix dimension N
- `R3 = 0`  → base of A
- `R4 = 4`  → base of B
- `R5 = 8`  → base of C

Then the kernel computes thread-specific coordinates:

- `DIV R6, R0, R2` → row
- `MUL R7, R6, R2`
- `SUB R7, R0, R7` → col

For thread 1 the resulting interpretation is:

- `R6 = 0` → row 0
- `R7 = 1` → col 1

This exactly matches the expected output location `C[0,1]`.

## Step 3: the loop body starts at PC 12

The loop body begins at program counter 12.

Around cycle 296, after the first branch-back, the trace shows:

```text
PC: 12
Instruction: MUL R10, R6, R2
```

That is the first line of the loop body.

From there the loop computes two addresses:

1. address into A using `row * N + k + baseA`
2. address into B using `k * N + col + baseB`

Then it performs:

- `LDR R10, R10`
- `LDR R11, R11`
- `MUL R12, R10, R11`
- `ADD R8, R8, R12`

That is the classic dot-product inner loop.

## Step 4: understanding one loop iteration for thread 1

Thread 1 executes two loop iterations because `N = 2`.

### First iteration (`k = 0`)

The relevant values become:

- load `A[0,0] = 1`
- load `B[0,1] = 2`
- multiply → `1 * 2 = 2`
- accumulate → `R8 = 2`

You can see this state clearly near the first branch-back region.
Around cycles `284..291`, thread 1 has:

- `R8 = 2`
- `R9 = 1`
- `R10 = 1`
- `R11 = 2`
- `R12 = 2`

That register snapshot is exactly what you want after the first dot-product term has been accumulated.

### First branch decision: loop continues

At cycle 284 the trace is approaching the loop branch logic:

```text
PC: 24
Instruction: CMP R9, R2
```

At this point:

- `R9 = 1`
- `R2 = 2`

So the comparison means “is `k` still less than `N`?”

The following branch sequence is visible in cycles `285..291`:

- branch instruction fetched and executed
- at cycle 291, `PC` jumps back to `12`

That jump back to `PC: 12` is the proof that the loop continues for another iteration.

## Step 5: second iteration (`k = 1`)

In the second loop round, thread 1 should use:

- `A[0,1] = 2`
- `B[1,1] = 4`

So the second product is:

```text
2 * 4 = 8
```

Adding that to the previous accumulator value gives:

```text
R8 = 2 + 8 = 10
```

By the time the loop-exit compare happens later, the trace confirms exactly that state.

Near cycles `432..447`, thread 1 shows:

- `R8 = 10`
- `R9 = 2`
- `R10 = 2`
- `R11 = 4`
- `R12 = 8`

This is the clearest “the dot product is finished” snapshot in the trace.

## Step 6: second branch decision means loop exit

The second compare/branch sequence appears around cycles `432..447`.

This time the key values are:

- `R9 = 2`
- `R2 = 2`

So `k` has reached `N`.

The branch no longer goes back to the loop body.

You can see the difference in the PC progression:

- after the branch update, the trace moves to `PC: 25`, then `PC: 26`
- it does **not** jump back to `PC: 12`

That is how the log shows “loop exit” without printing a high-level English sentence.

For beginners, this is the most important branch-reading trick in the whole file:

> watch where the PC goes after the branch completes.

- if it returns to `PC 12`, the loop continues
- if it advances to `PC 25/26`, the loop is over

## Step 7: computing the output address

After the loop exits, the kernel computes the destination address for C.

Around cycle 459 the trace shows:

```text
PC: 26
Instruction: ADD R9, R5, R0
```

At this moment:

- `R5 = 8`  → base of output matrix
- `R0 = 1`  → thread/global output index

So thread 1 computes:

```text
R9 = 9
```

That is exactly the correct address for output element `C[0,1]`.

## Step 8: final store and the all-thread memwrite burst

At cycle 464 the next real instruction becomes:

```text
Instruction: STR R9, R8
```

For thread 1, that means:

- store to address `R9 = 9`
- store value `R8 = 10`

Then the `[memwrite]` lines show that **all four lanes** write their results at cycle 471:

```text
[memwrite] data cycle=471 lane=0 addr=11 old=0 new=22
[memwrite] data cycle=471 lane=1 addr=10 old=0 new=15
[memwrite] data cycle=471 lane=2 addr=9 old=0 new=10
[memwrite] data cycle=471 lane=3 addr=8 old=0 new=7
```

Even though the per-cycle trace only logs thread 1, these four memwrite lines reveal the final outputs of all threads:

- addr 8  → 7
- addr 9  → 10
- addr 10 → 15
- addr 11 → 22

So the final matrix result is visible in one compact burst.

Just like `matadd`, the next cycle also shows repeated writes with unchanged values:

```text
[memwrite] data cycle=472 ... old=22 new=22
...
```

The safest interpretation is again that the write handshake remains visible for another cycle, not that the mathematical result changed.

## Step 9: return and completion

Near the end of the log, thread 1 reaches:

```text
PC: 27
Instruction: RET
Core State: DONE
Core Done: 1
```

Then the test prints:

```text
Completed in 491 cycles
```

And the final memory table confirms:

```text
data[8..11] = 7, 10, 15, 22
```

## What to focus on when you read this log yourself

A good reading order is:

1. initial data-memory dump
2. cycle 7 — first real fetched instruction
3. the `DIV` / `SUB` steps that establish row and column
4. the first `LDR R10` / `LDR R11` sequence
5. the first `CMP` + branch-back sequence around cycles `284..291`
6. the second `CMP` + branch-exit sequence around cycles `432..447`
7. the final `STR R9, R8` sequence around cycles `464..471`
8. final data-memory dump

That reading order lets you see the kernel as:

- setup
- loop iteration 1
- loop iteration 2
- loop exit
- final writeback

## Beginner takeaway

This trace is valuable because it shows how a tiny GPU kernel can still express a real control-flow pattern:

- per-thread indexing
- address generation
- repeated loads from memory
- accumulation in a register
- a compare-and-branch loop
- final store to global memory

If `matadd` teaches “same instruction, different thread data,” then `matmul` teaches the next layer:

> a GPU thread can also run a local sequential algorithm, and the trace shows exactly how that algorithm unfolds through fetch, wait, execute, and update phases.
