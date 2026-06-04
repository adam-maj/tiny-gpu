# Tiny GPU Instruction Set Architecture (ISA)

## Overview

Tiny GPU currently implements a compact 16-bit instruction set intended for simple SIMT-style execution.

Instruction execution is controlled by the core pipeline and executed by the ALU, LSU, and Program Counter subsystems.

---

## Instruction Format

All instructions are 16 bits wide.

General format:

15            12 11                      0
+---------------+------------------------+
|   OPCODE      |        OPERANDS        |
+---------------+------------------------+

The exact interpretation of operand fields depends on the instruction type.

---

## Register Model

The architecture provides sixteen general-purpose registers:

R0-R15

Special usage:

| Register | Purpose           |
| -------- | ----------------- |
| R13      | Block ID          |
| R14      | Threads Per Block |
| R15      | Thread ID         |

All other registers are available for software use.

---

# Arithmetic Instructions

## CONST

Description:

Load immediate value into a register.

Syntax:

CONST Rd, Imm

Example:

CONST R1, 10

Operation:

Rd ← Imm

---

## ADD

Description:

Add two source registers.

Syntax:

ADD Rd, Rs, Rt

Example:

ADD R0, R1, R2

Operation:

Rd ← Rs + Rt

---

## SUB

Description:

Subtract two source registers.

Syntax:

SUB Rd, Rs, Rt

Example:

SUB R0, R1, R2

Operation:

Rd ← Rs - Rt

---

## MUL

Description:

Multiply two source registers.

Syntax:

MUL Rd, Rs, Rt

Example:

MUL R0, R1, R2

Operation:

Rd ← Rs × Rt

---

## DIV

Description:

Divide two source registers.

Syntax:

DIV Rd, Rs, Rt

Example:

DIV R0, R1, R2

Operation:

Rd ← Rs / Rt

Division by zero returns zero.

---

# Compare Instructions

## CMP

Description:

Compare two registers and update NZP flags.

Syntax:

CMP Rs, Rt

Example:

CMP R1, R2

Operation:

NZP ← compare(Rs, Rt)

Generated Flags:

| Flag | Meaning |
| ---- | ------- |
| N    | Rs < Rt |
| Z    | Rs = Rt |
| P    | Rs > Rt |

---

# Branch Instructions

## BRN

Description:

Branch if negative flag is set.

Syntax:

BRN Address

Example:

BRN 20

Condition:

N == 1

---

## BRZ

Description:

Branch if zero flag is set.

Syntax:

BRZ Address

Example:

BRZ 20

Condition:

Z == 1

---

## BRP

Description:

Branch if positive flag is set.

Syntax:

BRP Address

Example:

BRP 20

Condition:

P == 1

---

# Memory Instructions

## LOAD

Description:

Load data from memory.

Syntax:

LOAD Rd, Address

Example:

LOAD R0, 10

Operation:

Rd ← MEM[Address]

---

## STORE

Description:

Store data to memory.

Syntax:

STORE Rs, Address

Example:

STORE R0, 10

Operation:

MEM[Address] ← Rs

---

# Control Instructions

## RET

Description:

Terminate kernel execution.

Syntax:

RET

Operation:

Signal completion and halt execution.

---

# Execution Example

Example program:

CONST R1, 10
CONST R2, 20
ADD R0, R1, R2
RET

Execution:

R1 ← 10
R2 ← 20
R0 ← 30

Program terminates at RET.

---

# Current ISA Summary

| Instruction | Category   |
| ----------- | ---------- |
| CONST       | Immediate  |
| CMP         | Compare    |
| ADD         | Arithmetic |
| SUB         | Arithmetic |
| MUL         | Arithmetic |
| DIV         | Arithmetic |
| LOAD        | Memory     |
| STORE       | Memory     |
| BRN         | Branch     |
| BRZ         | Branch     |
| BRP         | Branch     |
| RET         | Control    |

---

# Planned ISA Extensions

Future instructions:

* AND
* OR
* XOR
* NOT
* SHL
* SHR

Long-term extensions:

* SIMD arithmetic
* Floating point operations
* Vector instructions

---

Version: v0.1.0-alpha
