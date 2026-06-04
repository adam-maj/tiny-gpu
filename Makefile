# ============================================================
# Tiny GPU Build System
# ============================================================

.PHONY: help
help:
	@echo ""
	@echo "Tiny GPU Build Targets"
	@echo "======================"
	@echo ""
	@echo "make test           Run all regressions"
	@echo "make test-core      Run core regressions"
	@echo "make test-gpu       Run GPU regressions"
	@echo "make asm            Assemble all example programs"
	@echo "make clean          Remove build artifacts"
	@echo ""

# ============================================================
# Assembly Programs
# ============================================================

PROGRAMS = \
	programs/add.asm \
	programs/sub.asm \
	programs/mul.asm \
	programs/div.asm \
	programs/branch.asm \
	programs/load.asm \
	programs/store.asm

.PHONY: asm
asm:
	@echo "Assembling programs..."
	@for p in $(PROGRAMS); do \
		echo ""; \
		echo "$$p"; \
		python3 tools/assembler.py $$p; \
	done

# ============================================================
# Verification
# ============================================================

.PHONY: test
test: test-core test-gpu

.PHONY: test-core
test-core:
	pytest -s tb/run_core_programs.py

.PHONY: test-gpu
test-gpu:
	pytest -s tb/run_gpu_top.py

# ============================================================
# Cleanup
# ============================================================

.PHONY: clean
clean:
	rm -rf sim_build
	rm -rf build
	rm -rf .pytest_cache
	find . -name "__pycache__" -type d -exec rm -rf {} +
	find . -name "*.fst" -delete
	find . -name "*.vcd" -delete