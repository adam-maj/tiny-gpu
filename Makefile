export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

build_%:
	rm -rf build/vvp
	mkdir build/vvp
	iverilog -o build/vvp/sim.vvp -s $* -g2012 src/$*.v

test_unit_%:
	rm -rf build/vvp
	mkdir build/vvp
	iverilog -o build/vvp/sim.vvp -s $* -g2012 src/$*.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/vvp/sim.vvp

test_core:
	rm -rf build/vvp
	mkdir build/vvp
	iverilog -o build/vvp/sim.vvp -s core -g2012 src/core.v src/alu.v src/decoder.v src/fetcher.v src/lsu.v src/memory.v src/pc.v src/registers.v src/warps.v

test_gpu:
	rm -rf build/vvp
	mkdir build/vvp
	iverilog -o build/vvp/sim.vvp -s gpu -g2012 src/*
	# MODULE=test.test_gpu vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/vvp/sim.vvp

compile:
	sv2v -I src/* -w build/v/gpu.v

compile_core:
	sv2v -I src/* -w build/v/core.v

compile_%:
	sv2v -w build/v/$*.v src/$*.sv

show_%: %.vcd %.gtkw
	gtkwave $^