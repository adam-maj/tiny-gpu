# Tiny GPU Next Architecture Overview

## Design Goals

Tiny GPU Next is a pedagogical SIMT GPU architecture implemented in SystemVerilog.

Primary goals:

* Architectural clarity
* Educational value
* Verification friendliness
* Incremental evolution
* Modern GPU concepts

Non-goals:

* Commercial competitiveness
* ISA compatibility with existing GPUs
* Maximum performance

---

# System Hierarchy

```text
GPU
 |
 +-- Block Dispatcher
 |
 +-- Warp Table
 |
 +-- Warp Scheduler
 |
 +-- Compute Core
 |
 +-- Memory System
```

---

# Component Responsibilities

## Block Dispatcher

Responsible for:

* Kernel launch processing
* Block allocation
* Warp creation

Not responsible for:

* Warp scheduling
* Instruction execution

---

## Warp Table

Responsible for:

* Storing active warp contexts
* Warp allocation
* Warp state updates

Acts as:

```text
Register File for Warps
```

---

## Warp Scheduler

Responsible for:

* Selecting READY warps
* Scheduling execution

Initial policy:

```text
Round Robin
```

---

## Compute Core

Responsible for:

* Fetch
* Decode
* Execute
* Load/Store

Not responsible for:

* Warp allocation

---

## Memory System

Future responsibilities:

* Shared Memory
* Coalescing
* Cache Hierarchy

---

# Execution Flow

```text
Kernel Launch
      |
      V
Block Dispatcher
      |
      V
Warp Table
      |
      V
Warp Scheduler
      |
      V
Compute Core
      |
      V
Memory System
```

---

# Architectural Evolution

Version 1

* Warp Scheduling

Version 2

* Shared Memory

Version 3

* Memory Coalescing

Version 4

* Cache Hierarchy

Version 5

* SIMT Divergence

Version 6

* Graphics Pipeline

```
```
