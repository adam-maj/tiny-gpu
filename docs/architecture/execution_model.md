# Tiny GPU Next Execution Model

## Overview

Tiny GPU Next is a pedagogical SIMT (Single Instruction Multiple Threads) GPU architecture.

The objective is to demonstrate modern GPU execution concepts while maintaining a manageable RTL codebase suitable for learning, experimentation, and verification.

The architecture is inspired by:

* Tiny-GPU
* MIAOW
* VeriGPU
* Modern SIMT GPU architectures

while intentionally avoiding unnecessary complexity.

---

# Core Concepts

## Thread

A thread is the smallest execution entity.

Each thread owns:

* Program Counter (logical)
* Register State
* Execution State

Threads execute the same kernel program.

---

## Warp

A warp is the scheduling unit of the GPU.

A warp contains:

```text
8 Threads
```

Current architectural parameter:

```text
WARP_SIZE = 8
```

Example:

```text
Warp 0

Thread 0
Thread 1
Thread 2
Thread 3
Thread 4
Thread 5
Thread 6
Thread 7
```

All threads inside a warp execute the same instruction stream.

---

## Active Mask

The active mask indicates which lanes are currently participating in execution.

Example:

```text
11111111
```

All lanes active.

Example:

```text
00001111
```

Only lower four lanes active.

The active mask becomes important for:

* Branch divergence
* Predication
* Reconvergence

---

## Warp Context

Each warp owns:

| Field       | Description             |
| ----------- | ----------------------- |
| Valid       | Warp allocated          |
| PC          | Current program counter |
| Active Mask | Active execution lanes  |
| State       | Scheduler state         |

---

# Warp State Machine

A warp transitions through the following states.

```text
READY
  |
  v
RUNNING
  |
  +----------+
  |          |
  v          |
STALLED      |
  |          |
  +----------+
  |
  v
DONE
```

---

## READY

Warp is eligible for scheduling.

Requirements:

* Valid context
* Not waiting on memory
* Not completed

---

## RUNNING

Warp currently owns execution resources.

Instructions are actively being executed.

---

## STALLED

Warp is temporarily blocked.

Possible reasons:

* Memory latency
* Synchronization
* Resource dependency

Future revisions may introduce additional stall reasons.

---

## DONE

Warp execution completed.

Resources may be reclaimed.

---

# Scheduler Policy

Initial implementation uses:

```text
Round-Robin Warp Scheduling
```

Policy:

1. Scan warp table.
2. Select next READY warp.
3. Dispatch warp.
4. Advance scheduling pointer.

Goals:

* Deterministic behavior
* Simplicity
* Educational value

Future policies may include:

* Greedy-Then-Oldest
* Two-Level Scheduling
* Scoreboard-Aware Scheduling

---

# Warp Lifecycle

```text
Kernel Launch
      |
      v
Warp Allocation
      |
      v
READY
      |
      v
RUNNING
      |
      v
STALLED (optional)
      |
      v
RUNNING
      |
      v
DONE
```

---

# Architectural Assumptions

Version 1 intentionally excludes:

* Shared Memory
* Memory Coalescing
* Cache Hierarchy
* Branch Divergence
* Reconvergence
* Multi-Core Execution

These concepts are introduced incrementally in future milestones.

---

# Future Evolution

Version 2

* Shared Memory
* Barrier Synchronization

Version 3

* Memory Coalescing
* Cache Hierarchy

Version 4

* SIMT Divergence
* Reconvergence Stack

Version 5

* Graphics Pipeline Extensions

The execution model described here serves as the foundation for all future architectural development.
