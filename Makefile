export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_memory:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s memory -g2012 src/memory.v src/
	MODULE=test.test_memory vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

show_%: %.vcd %.gtkw
	gtkwave $^