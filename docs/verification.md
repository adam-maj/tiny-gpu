# <div align="center">  Verification Strategy

<div align="center">  

![Status](https://img.shields.io/badge/status-active-green) ![Framework](https://img.shields.io/badge/framework-Cocotb-blue) ![Simulator](https://img.shields.io/badge/simulator-Verilator-red)
</div>

> [!IMPORTANT]
> Tiny GPU uses Cocotb and Verilator for functional verification.
>
> Verification is focused on proving end-to-end execution correctness across the compute core, memory subsystem, assembler workflow, and GPU integration.

---

# Overview

The verification environment is designed to validate:

* RTL correctness
* Instruction execution
* Memory transactions
* Program execution
* GPU integration

Verification is performed using:

| Tool      | Purpose                   |
| --------- | ------------------------- |
| Verilator | RTL simulation            |
| Cocotb    | Python-based verification |
| Pytest    | Regression execution      |

---

# Verification Philosophy

Tiny GPU verification follows three layers:

```text
Unit Verification
      ↓
Program Verification
      ↓
System Verification
```

---

## Layer 1 — Unit Verification

Validates individual RTL modules.

Examples:

* ALU
* Decoder
* Register File
* Fetch Unit

Goal:

```text
Verify module functionality in isolation.
```

---

## Layer 2 — Program Verification

Validates complete instruction execution.

Examples:

* Arithmetic programs
* Branch programs
* Load/store programs

Goal:

```text
Verify instruction sequences execute correctly.
```

---

## Layer 3 — System Verification

Validates complete GPU execution.

Examples:

* GPU top-level integration
* Memory subsystem interaction
* Dispatch flow

Goal:

```text
Verify end-to-end execution.
```

---

# Verification Environment

```text
Python
   ↓
Pytest
   ↓
Cocotb
   ↓
Verilator
   ↓
RTL
```

---

# Test Structure

```text
tb/
├── run_alu.py
├── run_decoder.py
├── run_core.py
├── run_core_programs.py
└── run_gpu_top.py
```

---

# Unit Verification

## ALU Verification

Purpose:

* Arithmetic operation validation
* Compare operation validation

Verified Operations:

| Operation | Status |
| --------- | ------ |
| ADD       | ✅      |
| SUB       | ✅      |
| MUL       | ✅      |
| DIV       | ✅      |
| CMP       | ✅      |

---

## Decoder Verification

Purpose:

* Instruction decode validation
* Control signal generation

Checks:

* Opcode decoding
* Register selection
* Immediate extraction
* Branch control generation

Status: ✅ Verified

---

# Core Verification

## Core Execution Test

Purpose:

Verify complete instruction execution flow.

Pipeline stages exercised:

```text
FETCH
DECODE
REQUEST
WAIT
EXECUTE
UPDATE
```

Status: ✅ Verified

---

# Program Verification

The following assembly programs are currently executed during regression.

| Program    | Purpose               | Status |
| ---------- | --------------------- | ------ |
| add.asm    | Addition              | ✅      |
| sub.asm    | Subtraction           | ✅      |
| mul.asm    | Multiplication        | ✅      |
| div.asm    | Division              | ✅      |
| branch.asm | Conditional Branching | ✅      |
| load.asm   | Memory Read           | ✅      |
| store.asm  | Memory Write          | ✅      |

---

## Example Program Flow

```asm
CONST R1, 10
CONST R2, 20
ADD R0, R1, R2
RET
```

Execution:

```text
Fetch instruction
Decode instruction
Execute instruction
Write result
Terminate
```

---

# GPU Verification

## GPU Top Regression

Purpose:

Verify complete GPU execution.

Subsystems exercised:

* Device Control Register
* Program Memory Controller
* Data Memory Controller
* Block Dispatcher
* Compute Core

Status: ✅ Passing

---

## Memory Interface Verification

Validated Interfaces:

| Interface            | Status |
| -------------------- | ------ |
| Program Memory Reads | ✅      |
| Data Memory Reads    | ✅      |
| Data Memory Writes   | ✅      |

---

## Dispatch Verification

Validated Features:

* Core activation
* Block assignment
* Completion detection

Status: ✅ Passing

---

# Running Regressions

## Core Program Regression

```bash
pytest -s tb/run_core_programs.py
```

Expected:

```text
PASS
```

---

## GPU Integration Regression

```bash
pytest -s tb/run_gpu_top.py
```

Expected:

```text
PASS
```

---

## Full Regression

```bash
pytest -s tb/
```

Expected:

```text
All tests pass
```

---

# Verification Status Summary

| Area              | Status |
| ----------------- | ------ |
| ALU               | ✅      |
| Decoder           | ✅      |
| Core              | ✅      |
| Program Execution | ✅      |
| GPU Top           | ✅      |
| Memory Interfaces | ✅      |
| Branching         | ✅      |
| Load/Store        | ✅      |

---

# Known Verification Gaps

> [!WARNING]
> The following areas are not yet fully verified.

* Architectural register scoreboarding
* Functional coverage
* Randomized instruction generation
* Memory stress testing
* Multi-core stress workloads
* Warp scheduling validation

---

# Future Verification Roadmap

## v0.2.0

* [ ] Architectural scoreboarding
* [ ] Register-state validation
* [ ] Enhanced instruction checking

## v0.3.0

* [ ] Randomized testing
* [ ] Memory stress testing
* [ ] Multi-program regressions

## v0.4.0

* [ ] Functional coverage
* [ ] Coverage closure

## v0.5.0

* [ ] FPGA validation
* [ ] Hardware bring-up testing

---

# Verification Maturity

| Area                 | Maturity    |
| -------------------- | ----------- |
| Unit Verification    | High        |
| Program Verification | Medium      |
| System Verification  | Medium      |
| Coverage             | Low         |
| FPGA Validation      | Not Started |

> [!NOTE]
> Current verification demonstrates successful end-to-end execution but does not yet provide full architectural scoreboarding or coverage closure.

---
<div align="center">  Version: v0.1.0-alpha
