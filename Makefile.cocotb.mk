# Makefile

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Enable wakeform
WAVES=1

VERILOG_SOURCES += build/gpu.v

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = gpu

# MODULE is the basename of the Python test file
MODULE := test.test_matadd

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
