export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_memory:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s memory -g2012 src/memory.v
	MODULE=test.test_memory vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

test_alu:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s alu -g2012 src/alu.v
	MODULE=test.test_alu vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

test_registers:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s registers -g2012 src/registers.v
	MODULE=test.test_registers vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp


test_decoder:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s decoder -g2012 src/decoder.v
	MODULE=test.test_decoder vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp


# test_%:
# 	rm -rf build/
# 	mkdir build/
# 	iverilog -o build/sim.vvp -s $* -g2012 src/$*.v src/*.v
# 	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp


show_%: %.vcd %.gtkw
	gtkwave $^