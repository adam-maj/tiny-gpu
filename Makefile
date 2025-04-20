.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
TOPLEVEL=gpu

test_%:
	make compile
	make iverilog_dump_$*.sv
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v -s iverilog_dump_$* iverilog_dump_$*.sv
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

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

iverilog_dump_%.sv:
	echo 'module iverilog_dump_$*();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$*.vcd");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

show_%: %.vcd
	gtkwave $^

clean:
	rm -rf build/*
	rm -f iverilog_dump*
	rm -f *.vcd
