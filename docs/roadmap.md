# <div align="center"> Roadmap

<div align="center"> 

![Version](https://img.shields.io/badge/version-v0.1.0--alpha-orange) ![Status](https://img.shields.io/badge/status-active-green)
</div>

> [!IMPORTANT]
> This roadmap tracks the planned evolution of Tiny GPU from an educational prototype into a more capable GPU architecture.

---

# Current State

## v0.1.0-alpha

Current capabilities:

- [x] Multi-core GPU integration
- [x] Program execution
- [x] Arithmetic instructions
- [x] Branch instructions
- [x] Load/store instructions
- [x] External memory interfaces
- [x] Cocotb verification
- [x] Assembly toolchain

Current limitations:

- [ ] No logical instructions
- [ ] No shift instructions
- [ ] No SIMD support
- [ ] No cache hierarchy
- [ ] No scoreboarding
- [ ] No FPGA deployment

---

# v0.2.0 — ISA Expansion

Goal:

Add missing basic ISA functionality.

## Planned Features

### Logic Instructions

- [ ] AND
- [ ] OR
- [ ] XOR
- [ ] NOT

### Shift Instructions

- [ ] SHL
- [ ] SHR

### Assembler Improvements

- [ ] Labels
- [ ] Named branch targets
- [ ] Better diagnostics

### Verification

- [ ] Logic instruction regressions
- [ ] Shift instruction regressions

Success Criteria:

```text
Complete baseline scalar ISA.
```

---

# v0.3.0 — Architectural Verification

Goal:

Move beyond execution-only validation.

## Planned Features

### Architectural Scoreboard

- [ ] Register tracking
- [ ] Memory tracking
- [ ] Instruction tracking

### Verification Improvements

- [ ] Randomized instruction generation
- [ ] Directed-random testing
- [ ] Self-checking regressions

### Metrics

- [ ] Functional coverage
- [ ] Verification dashboards

Success Criteria:

```text
Architectural correctness independently verified.
```

---

# v0.4.0 — GPU Scheduling

Goal:

Improve execution resource utilization.

## Planned Features

### Warp Scheduling

- [ ] Dynamic warp switching
- [ ] Occupancy tracking
- [ ] Ready warp selection

### Dispatch

- [ ] Improved block allocation
- [ ] Load balancing

### Performance

- [ ] Execution statistics
- [ ] Scheduler metrics

Success Criteria:

```text
More realistic GPU execution behavior.
```

---

# v0.5.0 — Memory System

Goal:

Reduce memory bottlenecks.

## Planned Features

### Cache Architecture

- [ ] Instruction cache
- [ ] Data cache

### Memory Features

- [ ] Cache controller
- [ ] Cache statistics
- [ ] Miss handling

Success Criteria:

```text
Cache-backed execution platform.
```

---

# v0.6.0 — SIMD Execution

Goal:

Introduce data parallel execution.

## Planned Features

### Vector ISA

- [ ] Vector registers
- [ ] Vector arithmetic
- [ ] Vector memory operations

### Execution Units

- [ ] SIMD ALU
- [ ] SIMD scheduler support

Success Criteria:

```text
True vectorized execution.
```

---

# v0.7.0 — FPGA Deployment

Goal:

Run Tiny GPU on real hardware.

## Planned Features

### FPGA Support

- [ ] Vivado flow
- [ ] Timing closure
- [ ] Resource analysis

### Validation

- [ ] FPGA execution tests
- [ ] Hardware debugging

Success Criteria:

```text
Tiny GPU running on FPGA.
```

---

# Long-Term Vision

## Research Platform

Tiny GPU should eventually support:

- SIMD execution
- Warp scheduling
- Cache hierarchy
- Performance measurement
- Hardware experimentation

## Educational Platform

Tiny GPU should remain:

- Easy to understand
- Easy to modify
- Easy to verify
- Easy to extend

---

# Milestone Summary

| Version | Focus |
|----------|----------|
| v0.1.0 | Executable GPU |
| v0.2.0 | ISA Expansion |
| v0.3.0 | Verification |
| v0.4.0 | Scheduling |
| v0.5.0 | Memory System |
| v0.6.0 | SIMD |
| v0.7.0 | FPGA |