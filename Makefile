export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

build_%:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s $* -g2005 src/$*.v

test_unit_%:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s $* -g2005 src/$*.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

test_core:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s core -g2005 src/core.v src/alu.v src/decoder.v src/fetcher.v src/lsu.v src/memory.v src/pc.v src/registers.v src/warps.v

test_gpu:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s gpu -g2005 src/*
	# MODULE=test.test_gpu vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

show_%: %.vcd %.gtkw
	gtkwave $^