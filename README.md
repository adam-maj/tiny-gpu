# <div align="center"> Tiny GPU

<div align="center">

![Version](https://img.shields.io/badge/version-v0.1.0--alpha-orange) ![RTL](https://img.shields.io/badge/RTL-SystemVerilog-blue) ![Verification](https://img.shields.io/badge/Verification-Cocotb-green) ![Simulator](https://img.shields.io/badge/Simulator-Verilator-red)

</div>

A lightweight educational GPU architecture written in SystemVerilog.

Tiny GPU is designed to demonstrate the fundamental building blocks of modern GPU architectures without the complexity typically found in production-grade designs. The project focuses on execution flow, scheduling, memory systems, and parallel execution while remaining small enough for a single engineer to understand and extend.

> [!NOTE]
> This project is not intended to compete with production GPU architectures. The goal is to provide a complete, executable, and verifiable GPU implementation that can be studied, modified, and extended.

---

## Why Tiny GPU?

Learning how CPUs work is relatively straightforward. There are countless open-source processors, textbooks, and educational resources available.

GPUs are different.

Modern GPU architectures are extremely complex, and most publicly available implementations are either research projects or production-oriented designs containing hundreds of modules and advanced optimizations.

Tiny GPU takes a different approach.

Rather than focusing on performance, it focuses on clarity.

The objective is to answer questions such as:

* What does a GPU actually look like internally?
* How are threads scheduled?
* How are instructions fetched and executed?
* How do memory systems interact with execution units?
* What makes GPU execution different from CPU execution?

---

## Current Capabilities

### Compute

* Multi-core execution
* Thread-level execution
* Arithmetic operations
* Branch execution
* Load/store operations

### Memory

* Program memory subsystem
* Data memory subsystem
* Memory arbitration controllers
* External memory interfaces

### Software

* Assembly toolchain
* Assembly test programs
* End-to-end execution flow

### Verification

* Cocotb verification environment
* Core-level regressions
* Program execution regressions
* GPU integration regressions

---

## Architecture

At a high level, Tiny GPU consists of a dispatcher, memory subsystem, and one or more compute cores.
<p float="left">
  <img src="/docs/images/gpu.png" alt="GPU" width="48%" style="margin-right: 20px;">
  <img src="/docs/images/core.png" alt="Core" width="48%">
</p>
Execution begins when a kernel is loaded into program memory and launched through the Device Control Register. The dispatcher allocates work to available cores, and each core independently executes instructions while interacting with the shared memory subsystem.

---

## Compute Core

Each compute core contains the following modules:

| Module        | Responsibility        |
| ------------- | --------------------- |
| Fetch         | Instruction retrieval |
| Decode        | Instruction decoding  |
| Scheduler     | Execution control     |
| Register File | Thread-local state    |
| ALU           | Arithmetic operations |
| LSU           | Memory operations     |
| PC            | Program flow control  |

Execution is managed by a simple scheduler-driven state machine.

```text
FETCH
  ↓
DECODE
  ↓
REQUEST
  ↓
WAIT
  ↓
EXECUTE
  ↓
UPDATE
  ↓
FETCH
```

The current implementation prioritizes understandability over performance. Future versions may introduce pipelining, warp scheduling, and more advanced execution models.

---

## Memory System

Tiny GPU separates program memory from data memory.

### Program Memory

Stores executable instructions.

| Property      | Value            |
| ------------- | ---------------- |
| Address Width | 8 bits           |
| Capacity      | 256 Instructions |
| Data Width    | 16 bits          |

### Data Memory

Stores application data.

| Property      | Value       |
| ------------- | ----------- |
| Address Width | 8 bits      |
| Capacity      | 256 Entries |
| Data Width    | 8 bits      |

Memory access is coordinated through dedicated memory controllers which arbitrate requests originating from compute cores.

> [!IMPORTANT]
> Tiny GPU assumes memory exists externally to the GPU. The RTL communicates through memory interfaces rather than implementing memory arrays internally.

---

## Instruction Set

The current ISA supports:

| Category   | Instructions       |
| ---------- | ------------------ |
| Immediate  | CONST              |
| Arithmetic | ADD, SUB, MUL, DIV |
| Compare    | CMP                |
| Branch     | BRN, BRZ, BRP      |
| Memory     | LOAD, STORE        |
| Control    | RET                |

Additional ISA details are available in `docs/ISA.md`.

---

## Example Program

```asm
CONST R1, 10
CONST R2, 20

ADD R0, R1, R2

RET
```

Result:

```text
R0 = 30
```

Programs are assembled using the Tiny GPU assembler and executed through the RTL simulation environment.

---

## Verification

Verification is performed using Cocotb and Verilator.

Current regression suites validate:

| Area                  | Status |
| --------------------- | ------ |
| ALU Operations        | ✅      |
| Decoder               | ✅      |
| Core Execution        | ✅      |
| Program Execution     | ✅      |
| GPU Integration       | ✅      |
| Branch Execution      | ✅      |
| Load/Store Operations | ✅      |

Run the primary regressions:

```bash
pytest -s tb/run_core_programs.py
pytest -s tb/run_gpu_top.py
```



---

## Repository Layout

```text
rtl/
├── cache/
├── common/
├── control/
├── core/
├── dispatch/
├── scheduler/
└── top/

tb/
├── run_core.py
├── run_core_programs.py
└── run_gpu_top.py

tools/
└── assembler.py

programs/
├── add.asm
├── sub.asm
├── mul.asm
├── div.asm
├── branch.asm
├── load.asm
└── store.asm
```

---

## Documentation

| Document                     | Description                       |
| ---------------------------- | --------------------------------- |
| docs/ARCHITECTURE.md         | Detailed architecture description |
| docs/VERIFICATION.md         | Verification methodology          |
| docs/PROJECT_STATUS.md       | Current implementation status     |
| docs/ROADMAP.md              | Planned development roadmap       |
| docs/RELEASE_NOTES_v0.1.0.md | Release summary                   |

---

## Current Limitations

The project is still in an early stage of development.

Not currently implemented:

* Logic instructions
* Shift instructions
* Warp scheduling
* Cache hierarchy
* SIMD execution
* Architectural scoreboarding
* FPGA deployment

These limitations are intentional at this stage and help keep the implementation compact and understandable.

---

## Roadmap

<table>
<tr>
<td width="50%" valign="top">

### v0.2.0
- Logic instructions
- Shift instructions
- Improved assembler support

</td>
<td width="50%" valign="top">

### v0.3.0
- Architectural scoreboarding
- Enhanced verification

</td>
</tr>

<tr>
<td width="50%" valign="top">

### v0.4.0
- Improved scheduling
- Occupancy management

</td>
<td width="50%" valign="top">

### v0.5.0+
- Cache hierarchy
- SIMD execution
- FPGA deployment

</td>
</tr>
</table>