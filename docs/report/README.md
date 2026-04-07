# tiny-gpu Repository Analysis Report

This directory contains a source-verified documentation set for the `tiny-gpu` repository.

## Files

- `00-executive-overview.md` — project purpose, scope, major findings, and external toolchain summary
- `01-repository-structure.md` — top-level layout, module inventory, and hierarchy mapping
- `02-architecture-and-execution.md` — hardware organization, execution stages, and key module relationships
- `03-build-and-test-workflow.md` — compile flow, cocotb harness behavior, and simulator/tooling references
- `04-risks-open-questions.md` — confirmed limitations, documentation mismatches, and roadmap boundaries
- `05-matadd-trace-walkthrough.md` — cycle-by-cycle guided reading of the matrix-addition execution log
- `06-matmul-trace-walkthrough.md` — cycle-by-cycle guided reading of the matrix-multiplication execution log

## Method

This report was cross-checked against four sources of evidence:

1. the local checkout (`README.md`, `Makefile`, all RTL modules in `src/`, and cocotb code in `test/`)
2. the repository remote (`adam-maj/tiny-gpu`)
3. DeepWiki repository documentation for `adam-maj/tiny-gpu`
4. official tool documentation for `cocotb`, `iverilog`, `sv2v`, and `GTKWave`

## Reading guide

- Treat `src/` as the source of truth for implemented behavior.
- Treat `README.md` as the conceptual guide and roadmap.
- Treat external tool references in this report as usage context for the simulation flow, not as proof of repository behavior.

## Diagram note

Mermaid diagrams are included as source fences in the Markdown so the structure remains readable even when diagrams are not rendered by the viewer.
