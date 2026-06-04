# Tiny GPU v0.1.0-alpha Release Notes

<div align = center>

![Release](https://img.shields.io/badge/release-v0.1.0--alpha-orange) ![Status](https://img.shields.io/badge/status-initial%20milestone-green)

</div>

> [!IMPORTANT]
> This release marks the first end-to-end executable Tiny GPU milestone.
>
> The repository has evolved from a collection of RTL building blocks into a complete executable GPU prototype with assembler support, memory integration, and automated verification.

---

# Executive Summary

## Major Achievement

This milestone demonstrates:

```text
Assembly Program
      ↓
Assembler
      ↓
Program Memory
      ↓
GPU Top
      ↓
Compute Core
      ↓
Execution
      ↓
Completion
```

The complete execution flow is now functional and verified.

---

# Before v0.1.0-alpha

Repository status before this milestone:

| Area | Status |
|--------|--------|
| ALU | Partial |
| Core Infrastructure | Partial |
| Program Execution | ❌ |
| GPU Integration | ❌ |
| Memory Controllers | ❌ |
| Assembly Workflow | ❌ |
| End-to-End Verification | ❌ |

The project consisted primarily of individual RTL components without a fully validated execution platform.

---

# Added In This Release

## GPU Integration

### Added

- GPU top-level integration
- Multi-core infrastructure
- Core interconnect wiring

Status: ✅ Functional

---

## Memory System

### Added

- Program memory controller
- Data memory controller
- External memory interfaces

Status: ✅ Functional

---

## Dispatch Infrastructure

### Added

- Device Control Register integration
- Block dispatch infrastructure
- Core launch mechanism

Status: ✅ Functional

---

## Program Execution

### Added

- End-to-end execution flow
- Instruction fetch pipeline
- Execution completion handling

Status: ✅ Functional

---

## Assembly Toolchain

### Added

- Assembly source files
- Program assembly workflow
- Executable workloads

Status: ✅ Functional

---

# Assembly Programs Added

| Program | Purpose |
|----------|----------|
| add.asm | Addition |
| sub.asm | Subtraction |
| mul.asm | Multiplication |
| div.asm | Division |
| branch.asm | Branch verification |
| load.asm | Memory load |
| store.asm | Memory store |

All programs execute successfully through the full RTL pipeline.

---

# Verification Added

## Core Regression

Validated:

- Arithmetic execution
- Branch execution
- Memory operations

Status: ✅ Passing

---

## GPU Regression

Validated:

- Multi-core integration
- Dispatch flow
- Memory interfaces
- Program execution

Status: ✅ Passing

---

# Current Instruction Support

## Arithmetic

- CONST
- CMP
- ADD
- SUB
- MUL
- DIV

## Memory

- LOAD
- STORE

## Branching

- BRN
- BRZ
- BRP

## Control

- RET

---

# Verification Results

Current regression status:

| Test Suite | Status |
|------------|---------|
| ALU Tests | ✅ |
| Decoder Tests | ✅ |
| Core Tests | ✅ |
| Program Tests | ✅ |
| GPU Tests | ✅ |

Overall Status:

```text
PASS
```

---

# Known Limitations

## ISA

Not yet implemented:

- AND
- OR
- XOR
- NOT
- SHL
- SHR

---

## GPU Features

Not yet implemented:

- Dynamic warp scheduling
- Occupancy tracking
- SIMD execution
- Cache hierarchy

---

## Verification

Not yet implemented:

- Architectural scoreboarding
- Functional coverage
- Random instruction generation

---

# Repository Impact

## RTL

Newly integrated subsystems:

- GPU Top
- Memory Controllers
- Dispatch Infrastructure

## Software

Newly added:

- Assembler workflow
- Assembly programs

## Verification

Newly added:

- Core regressions
- Program regressions
- GPU regressions

---

# Release Assessment

Current maturity:

| Area | Assessment |
|--------|-----------|
| Functionality | Good |
| Verification | Moderate |
| Documentation | Improving |
| FPGA Readiness | Low |
| Production Readiness | Low |

---

# Next Milestone

Planned work:

- Logic instructions
- Shift instructions
- Better assembler support
- Improved verification

---
<div align="center"> 
Tiny GPU v0.1.0-alpha

June 2026