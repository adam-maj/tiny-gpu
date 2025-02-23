TOPLEVEL_LANG = verilog

SIM ?= questa
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ns

DUT      = gpu
TOPLEVEL = $(DUT)
MODULE   = test.test_matadd

RTL_DIR = ./src

# VERILOG_SOURCES += $(RTL_DIR)/alu.sv
# VERILOG_SOURCES += $(RTL_DIR)/controller.sv
# VERILOG_SOURCES += $(RTL_DIR)/dcr.sv
# VERILOG_SOURCES += $(RTL_DIR)/decoder.sv
# VERILOG_SOURCES += $(RTL_DIR)/dispatch.sv
# VERILOG_SOURCES += $(RTL_DIR)/fetcher.sv
# VERILOG_SOURCES += $(RTL_DIR)/lsu.sv
# VERILOG_SOURCES += $(RTL_DIR)/pc.sv
# VERILOG_SOURCES += $(RTL_DIR)/registers.sv
# VERILOG_SOURCES += $(RTL_DIR)/scheduler.sv
# VERILOG_SOURCES += $(RTL_DIR)/core.sv
# VERILOG_SOURCES += $(RTL_DIR)/gpu.sv

VERILOG_SOURCES += build/gpu.v
COMPILE_ARGS += +define+SIM

ifeq ($(SIM), questa)
	COMPILE_ARGS += -sv
endif

ifeq ($(SIM), vcs)
	SIM_BUILD ?= .
	COMPILE_ARGS += -V -debug_access+r+w+nomemcbk -debug_region+cell +define+VCS
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	@rm -rf dump.fst $(TOPLEVEL).fst sim_build/runsim.do
