################################################################################
# LKG-GPU Top-Level Timing Constraints
# SDC Format - Compatible with Synopsys/Cadence/FPGA tools
# Target: ASIC (TSMC 7nm) or FPGA (Xilinx/Intel)
################################################################################

set sdc_version 2.1

################################################################################
# Clock Definitions
################################################################################

# Reference clock input (100 MHz)
create_clock -name ref_clk -period 10.000 -waveform {0 5} [get_ports ref_clk_100mhz]

# PCIe reference clock (100 MHz for Gen3/4/5)
create_clock -name pcie_refclk -period 10.000 -waveform {0 5} [get_ports pcie_refclk]

################################################################################
# Generated Clocks from PLLs
################################################################################

# Core clock (2.0 GHz)
create_generated_clock -name core_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 20 \
    -divide_by 1 \
    [get_pins u_clock_reset_controller/core_clk_o]

# Shader clock (2.0 GHz - same as core)
create_generated_clock -name shader_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 20 \
    -divide_by 1 \
    [get_pins u_clock_reset_controller/shader_clk_o]

# Memory clock (1.0 GHz)
create_generated_clock -name memory_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 10 \
    -divide_by 1 \
    [get_pins u_clock_reset_controller/memory_clk_o]

# Display pixel clocks (variable based on resolution)
# 1080p60: 148.5 MHz, 4K60: 594 MHz, 8K60: 2376 MHz (with DSC)
create_generated_clock -name display_clk_0 \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 594 \
    -divide_by 100 \
    [get_pins u_clock_reset_controller/display_clk_o[0]]

create_generated_clock -name display_clk_1 \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 594 \
    -divide_by 100 \
    [get_pins u_clock_reset_controller/display_clk_o[1]]

create_generated_clock -name display_clk_2 \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 594 \
    -divide_by 100 \
    [get_pins u_clock_reset_controller/display_clk_o[2]]

create_generated_clock -name display_clk_3 \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 594 \
    -divide_by 100 \
    [get_pins u_clock_reset_controller/display_clk_o[3]]

# PCIe user clock (250 MHz for Gen4/5)
create_generated_clock -name pcie_user_clk \
    -source [get_ports pcie_refclk] \
    -multiply_by 5 \
    -divide_by 2 \
    [get_pins u_pcie_controller/user_clk_o]

################################################################################
# Clock Groups - Asynchronous Clock Domains
################################################################################

set_clock_groups -asynchronous \
    -group [get_clocks {core_clk shader_clk}] \
    -group [get_clocks {memory_clk}] \
    -group [get_clocks {display_clk_0 display_clk_1 display_clk_2 display_clk_3}] \
    -group [get_clocks {pcie_refclk pcie_user_clk}] \
    -group [get_clocks {ref_clk}]

################################################################################
# Clock Uncertainty
################################################################################

# ASIC: Jitter + skew
set_clock_uncertainty -setup 0.050 [get_clocks core_clk]
set_clock_uncertainty -hold  0.020 [get_clocks core_clk]
set_clock_uncertainty -setup 0.050 [get_clocks shader_clk]
set_clock_uncertainty -hold  0.020 [get_clocks shader_clk]
set_clock_uncertainty -setup 0.080 [get_clocks memory_clk]
set_clock_uncertainty -hold  0.030 [get_clocks memory_clk]
set_clock_uncertainty -setup 0.100 [get_clocks {display_clk_*}]
set_clock_uncertainty -hold  0.040 [get_clocks {display_clk_*}]
set_clock_uncertainty -setup 0.100 [get_clocks pcie_user_clk]
set_clock_uncertainty -hold  0.040 [get_clocks pcie_user_clk]

################################################################################
# Clock Latency
################################################################################

set_clock_latency -source 0.100 [get_clocks core_clk]
set_clock_latency -source 0.100 [get_clocks memory_clk]
set_clock_latency -source 0.150 [get_clocks pcie_user_clk]

################################################################################
# Input Delays
################################################################################

# PCIe RX (relative to pcie_user_clk)
set_input_delay -clock pcie_user_clk -max 1.000 [get_ports pcie_rx_p[*]]
set_input_delay -clock pcie_user_clk -min 0.200 [get_ports pcie_rx_p[*]]
set_input_delay -clock pcie_user_clk -max 1.000 [get_ports pcie_rx_n[*]]
set_input_delay -clock pcie_user_clk -min 0.200 [get_ports pcie_rx_n[*]]

# Memory interface
set_input_delay -clock memory_clk -max 0.400 [get_ports mem_dq[*]]
set_input_delay -clock memory_clk -min 0.100 [get_ports mem_dq[*]]
set_input_delay -clock memory_clk -max 0.400 [get_ports mem_dqs_p[*]]
set_input_delay -clock memory_clk -min 0.100 [get_ports mem_dqs_p[*]]

# JTAG (slow interface)
set_input_delay -clock ref_clk -max 5.000 [get_ports {tck tms tdi}]
set_input_delay -clock ref_clk -min 0.500 [get_ports {tck tms tdi}]

################################################################################
# Output Delays
################################################################################

# PCIe TX
set_output_delay -clock pcie_user_clk -max 1.000 [get_ports pcie_tx_p[*]]
set_output_delay -clock pcie_user_clk -min 0.200 [get_ports pcie_tx_p[*]]
set_output_delay -clock pcie_user_clk -max 1.000 [get_ports pcie_tx_n[*]]
set_output_delay -clock pcie_user_clk -min 0.200 [get_ports pcie_tx_n[*]]

# Memory interface
set_output_delay -clock memory_clk -max 0.400 [get_ports mem_addr[*]]
set_output_delay -clock memory_clk -min 0.100 [get_ports mem_addr[*]]
set_output_delay -clock memory_clk -max 0.400 [get_ports mem_ba[*]]
set_output_delay -clock memory_clk -min 0.100 [get_ports mem_ba[*]]
set_output_delay -clock memory_clk -max 0.400 [get_ports {mem_ras_n mem_cas_n mem_we_n}]
set_output_delay -clock memory_clk -min 0.100 [get_ports {mem_ras_n mem_cas_n mem_we_n}]
set_output_delay -clock memory_clk -max 0.400 [get_ports mem_dq[*]]
set_output_delay -clock memory_clk -min 0.100 [get_ports mem_dq[*]]

# Display outputs (relative to display clocks)
set_output_delay -clock display_clk_0 -max 1.000 [get_ports dp_tx_p[0][*]]
set_output_delay -clock display_clk_0 -min 0.100 [get_ports dp_tx_p[0][*]]

# JTAG TDO
set_output_delay -clock ref_clk -max 5.000 [get_ports tdo]
set_output_delay -clock ref_clk -min 0.500 [get_ports tdo]

# Status LEDs (no timing critical)
set_output_delay -clock ref_clk -max 5.000 [get_ports status_led[*]]
set_output_delay -clock ref_clk -min 0.000 [get_ports status_led[*]]

################################################################################
# False Paths
################################################################################

# Reset synchronizers
set_false_path -from [get_ports ext_rst_n]

# Static configuration (set once and stable)
set_false_path -from [get_cells u_*/config_reg*]

# Test mode signals
set_false_path -from [get_ports scan_enable]
set_false_path -from [get_ports scan_in*]
set_false_path -to [get_ports scan_out*]

# JTAG (asynchronous protocol)
set_false_path -from [get_ports trst_n]

################################################################################
# Multi-Cycle Paths
################################################################################

# Memory read latency (3 cycles)
set_multicycle_path -setup 3 -from [get_pins u_memory_controller/rd_data_reg*] \
                             -to [get_pins u_*/rd_data_*]
set_multicycle_path -hold 2 -from [get_pins u_memory_controller/rd_data_reg*] \
                            -to [get_pins u_*/rd_data_*]

# Shader operand fetch (2 cycles)
set_multicycle_path -setup 2 -from [get_pins u_shader_core_*/operand_reg*] \
                             -to [get_pins u_shader_core_*/alu_result*]
set_multicycle_path -hold 1 -from [get_pins u_shader_core_*/operand_reg*] \
                            -to [get_pins u_shader_core_*/alu_result*]

################################################################################
# Max Delay Constraints
################################################################################

# Clock domain crossing FIFOs
set_max_delay 2.0 -from [get_clocks core_clk] -to [get_clocks memory_clk] \
    -through [get_pins u_*/async_fifo_*/wr_ptr*]

set_max_delay 2.0 -from [get_clocks memory_clk] -to [get_clocks core_clk] \
    -through [get_pins u_*/async_fifo_*/rd_ptr*]

################################################################################
# Disable Timing
################################################################################

# Unused clock mux paths
set_disable_timing [get_cells u_clock_reset_controller/clk_mux_*] -from S -to Y

################################################################################
# Case Analysis (for mode-dependent timing)
################################################################################

# Normal operating mode (not test mode)
set_case_analysis 0 [get_ports scan_enable]
set_case_analysis 0 [get_ports test_mode]

################################################################################
# Operating Conditions
################################################################################

# Slow corner (worst case setup)
# set_operating_conditions -max slow_125c_0p72v -max_library slow_lib

# Fast corner (worst case hold)
# set_operating_conditions -min fast_m40c_0p88v -min_library fast_lib

################################################################################
# Design Rule Constraints
################################################################################

set_max_transition 0.100 [current_design]
set_max_fanout 32 [current_design]
set_max_capacitance 0.100 [current_design]

# High-drive outputs
set_driving_cell -lib_cell BUFX16 [get_ports pcie_tx_*]
set_driving_cell -lib_cell BUFX16 [get_ports mem_*]
set_driving_cell -lib_cell BUFX8  [get_ports dp_tx_*]

# Input loads
set_load 0.050 [get_ports pcie_tx_*]
set_load 0.020 [get_ports mem_*]
set_load 0.030 [get_ports dp_tx_*]

################################################################################
# End of SDC
################################################################################
