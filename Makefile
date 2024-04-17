export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_unit_%:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s $* -g2012 src/$*.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

test_core:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s core -g2012 src/core.v src/alu.v src/decoder.v src/fetcher.v src/lsu.v src/memory.v src/pc.v src/registers.v src/warps.v

show_%: %.vcd %.gtkw
	gtkwave $^