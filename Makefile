.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

TIMESTAMP := $(shell date +%Y%m%d%H%M%S)

test_%:
	mkdir -p build
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	cd test && mkdir -p runs
	cd ..
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp > test/runs/test_$*_$(TIMESTAMP).out

clean:
	rm -rf build/*
	rmdir build
	rm -rf test/runs/*
	rmdir test/runs

compile:
	make compile_alu
	sv2v -I src/* -w build/gpu.v
	echo "" >> build/gpu.v
	cat build/alu.v >> build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

compile_%:
	./sv2v/sv2v -w build/$*.v src/$*.sv

# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^
