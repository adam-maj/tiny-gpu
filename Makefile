.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test:
	make compile
	iverilog -o build/sim.vvp -s gpu -g2005 build/gpu.v
	MODULE=test.test_gpu vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

test_%:
	make compile_$*
	iverilog -o build/sim.vvp -s $* -g2005 src/$*.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

compile:
	make compile_alu
	sv2v -I src/* -w build/gpu.v
	cat build/alu.v >> build/gpu.v
	sed -i '' '1s/^/`timescale 1ns\/1ns\n/' build/gpu.v

compile_%:
	sv2v -w build/$*.v src/$*.sv

# TODO: Get gtkwave visualizaiton
show_%: %.vcd %.gtkw
	gtkwave $^