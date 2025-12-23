.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_%:
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

compile:
	mkdir -p build
	make compile_alu
	sv2v src/cache.sv src/controller.sv src/core.sv src/decoder.sv src/dispatcher.sv src/fetcher.sv src/gpu.sv src/lsu.sv src/lsu_cached.sv src/pc.sv src/registers.sv src/scheduler.sv -w build/gpu.v
	echo "" >> build/gpu.v
	cat build/alu.v >> build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

compile_%:
	mkdir -p build
	sv2v -w build/$*.v src/$*.sv

# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^