# <div align="center">  Project Status

<div align="center"> 

![Version](https://img.shields.io/badge/version-v0.1.0--alpha-orange) ![RTL](https://img.shields.io/badge/RTL-SystemVerilog-blue) ![Status](https://img.shields.io/badge/status-active-green)

</div>

> [!IMPORTANT]
> This document tracks the current implementation status of Tiny GPU.

---

# Executive Summary

Current project maturity:

| Area                       | Status         |
| -------------------------- | -------------- |
| Core RTL                   | ✅ Implemented |
| GPU Integration            | ✅ Implemented |
| Assembler                  | ✅ Implemented |
| Verification               | ✅ Implemented |
| Multi-Core Infrastructure  | ✅ Implemented |
| Warp Scheduling            | ⚠️ Partial     |
| Architectural Verification | ⚠️ Partial     |
| FPGA Bring-Up              | ❌ Not Started |
| Performance Analysis       | ❌ Not Started |

---

# Implemented Features

## Compute Core

* [x] Fetch Unit
* [x] Decode Unit
* [x] Scheduler
* [x] Register File
* [x] Program Counter
* [x] ALU
* [x] LSU

Status: ✅ Functional

---

## Arithmetic Operations

* [x] CONST
* [x] CMP
* [x] ADD
* [x] SUB
* [x] MUL
* [x] DIV

Status: ✅ Verified

---

## Memory Operations

* [x] LOAD
* [x] STORE

Status: ✅ Verified

---

## Branching

* [x] BRN
* [x] BRZ
* [x] BRP

Status: ✅ Verified

---

## GPU Top

* [x] Device Control Register
* [x] Block Dispatcher
* [x] Memory Controllers
* [x] Multi-Core Integration

Status: ✅ Functional

---

## Toolchain

* [x] Assembler
* [x] Program Loading Flow
* [x] Assembly Regression Programs

Status: ✅ Functional

---

# Partially Implemented

## Warp Scheduling

Current:

* Warp structures exist
* Scheduling infrastructure exists

Missing:

* Dynamic warp switching
* Occupancy management
* Advanced scheduling policies

Status: ⚠️ Infrastructure Only

---

## Architectural Verification

Current:

* End-to-end execution verification
* Program completion verification

Missing:

* Full register scoreboarding
* Memory scoreboarding
* Functional coverage

Status: ⚠️ Partial

---

# Not Yet Implemented

## ISA Extensions

* [ ] AND
* [ ] OR
* [ ] XOR
* [ ] NOT
* [ ] SHL
* [ ] SHR

---

## Advanced GPU Features

* [ ] Warp switching
* [ ] Occupancy tracking
* [ ] Divergence handling
* [ ] Shared memory
* [ ] Cache hierarchy

---

## Verification Enhancements

* [ ] Architectural scoreboard
* [ ] Random instruction generation
* [ ] Functional coverage
* [ ] Coverage closure

---

## Physical Implementation

* [ ] FPGA synthesis
* [ ] Timing analysis
* [ ] Resource utilization analysis
* [ ] Hardware bring-up

---

# Known Issues

## Register Visibility Investigation

During architectural verification work, register contents were not observable through the expected Cocotb hierarchy despite successful program execution.

Current impact:

* Does not affect execution
* Does not affect regressions
* Does affect architectural scoreboarding

Priority: Low

---

# Current Repository State

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
├── run_decoder.py
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

# Release Readiness

| Item                      | Status                   |
| ------------------------- | ------------------------ |
| Builds Successfully       | ✅                        |
| Regressions Pass          | ✅                        |
| Documentation In Progress | ⚠️                       |
| PR Ready                  | ⚠️ Pending Documentation |
| Release Ready             | ⚠️ Alpha Only            |

---
<div align="center"> 
v0.1.0-alpha

