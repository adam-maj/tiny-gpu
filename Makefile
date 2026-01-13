.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
export PYGPI_PYTHON_BIN=$(shell cocotb-config --python-bin)

test_%:
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	COCOTB_TEST_MODULES=test.test_$* vvp -M $$(cocotb-config --lib-dir) -m libcocotbvpi_icarus build/sim.vvp

compile:
	make compile_alu
	sv2v -I src/* -w build/gpu.v
	echo "" >> build/gpu.v
	cat build/alu.v >> build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

compile_%:
	sv2v -w build/$*.v src/$*.sv

# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^
