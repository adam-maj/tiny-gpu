test:
	rm -rf build/
	mkdir build/
	iverilog -o build/sim.vvp -s gpu -s dump -g2012 src/gpu.v test/dump_gpu.v src/
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.testgpu vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp
	! grep failure results.xml

show_%: %.vcd %.gtkw
	gtkwave $^