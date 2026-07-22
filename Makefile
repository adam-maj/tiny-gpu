.PHONY: test compile test_all gui_% clean

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

BUILD_DIR := build

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

test_%: | $(BUILD_DIR)
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --lib-dir) -m libcocotbvpi_icarus build/sim.vvp

# Runs every kernel + feature regression test against the current RTL.
# Add new test_<name>.py files under test/ and they'll be picked up here.
test_all:
	make test_matadd
	make test_matmul
	make test_divergence
	make test_coalescing
	make test_icache
	make test_graphics
	make test_tt

compile:
	make compile_alu
	sv2v -I src/*.sv -w build/gpu.v
	echo "" >> build/gpu.v
	cat build/alu.v >> build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

compile_%: | $(BUILD_DIR)
	sv2v -w build/$*.v src/$*.sv

# Tiny Tapeout 7 adapter (src/tt/tt_um_tiny_gpu.sv), a separate top module that
# wraps `gpu` - built independently from the main `compile` target above.
compile_tt: | $(BUILD_DIR)
	make compile_alu
	sv2v -w build/tt_gpu.v $(filter-out src/alu.sv,$(wildcard src/*.sv)) src/tt/*.sv
	echo "" >> build/tt_gpu.v
	cat build/alu.v >> build/tt_gpu.v
	echo '`timescale 1ns/1ns' > build/temp_tt.v
	cat build/tt_gpu.v >> build/temp_tt.v
	mv build/temp_tt.v build/tt_gpu.v

test_tt: | $(BUILD_DIR)
	make compile_tt
	iverilog -o build/sim_tt.vvp -s tt_um_tiny_gpu -g2012 build/tt_gpu.v
	MODULE=test.test_tt_adapter vvp -M $$(cocotb-config --lib-dir) -m libcocotbvpi_icarus build/sim_tt.vvp

# Starts the live simulation dashboard server and runs the given kernel test
# with streaming enabled (TINYGPU_GUI=1), then prints the URL to open.
# Usage: make gui_matadd / make gui_matmul / make gui_graphics
# Requires: source scripts/env.sh  (so vvp / cocotb-config are on PATH)
gui_%: | $(BUILD_DIR)
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	@echo ""
	@echo "==> Dashboard will be at http://localhost:$${TINYGPU_GUI_HTTP_PORT:-8080}"
	@echo "==> Ctrl+C stops both the server and the simulation"
	@echo ""
	.venv/bin/python sim/server.py --run test.test_$* --sim-vvp build/sim.vvp

clean:
	rm -rf $(BUILD_DIR)

# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^
