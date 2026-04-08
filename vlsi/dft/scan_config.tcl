################################################################################
# LKG-GPU Scan Insertion Configuration
# DFT (Design for Test) Configuration for ASIC Production
# Tool: Synopsys DFT Compiler / Cadence Modus
################################################################################

#-------------------------------------------------------------------------------
# DFT Configuration
#-------------------------------------------------------------------------------

set_dft_configuration \
    -scan enable \
    -scan_compression enable \
    -memory_test enable \
    -boundary_scan enable \
    -test_points enable

#-------------------------------------------------------------------------------
# Clock Configuration
#-------------------------------------------------------------------------------

# Define scan clocks
set_dft_signal -view existing_dft \
    -type ScanClock \
    -timing {50 100} \
    -port ref_clk_100mhz

set_dft_signal -view existing_dft \
    -type ScanClock \
    -timing {50 100} \
    -port pcie_refclk

# All generated clocks treated as scan clocks
set_dft_signal -view existing_dft \
    -type ScanClock \
    -timing {50 100} \
    -port [get_pins u_clock_reset_controller/core_clk_o]

#-------------------------------------------------------------------------------
# Scan Enable and Data Signals
#-------------------------------------------------------------------------------

# Scan Enable
set_dft_signal -view spec \
    -type ScanEnable \
    -port scan_enable \
    -active_state 1

# Test Mode
set_dft_signal -view spec \
    -type TestMode \
    -port test_mode \
    -active_state 1

# Scan Data In ports (8 chains)
set_dft_signal -view spec -type ScanDataIn  -port scan_in[0]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[1]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[2]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[3]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[4]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[5]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[6]
set_dft_signal -view spec -type ScanDataIn  -port scan_in[7]

# Scan Data Out ports
set_dft_signal -view spec -type ScanDataOut -port scan_out[0]
set_dft_signal -view spec -type ScanDataOut -port scan_out[1]
set_dft_signal -view spec -type ScanDataOut -port scan_out[2]
set_dft_signal -view spec -type ScanDataOut -port scan_out[3]
set_dft_signal -view spec -type ScanDataOut -port scan_out[4]
set_dft_signal -view spec -type ScanDataOut -port scan_out[5]
set_dft_signal -view spec -type ScanDataOut -port scan_out[6]
set_dft_signal -view spec -type ScanDataOut -port scan_out[7]

#-------------------------------------------------------------------------------
# Scan Chain Configuration
#-------------------------------------------------------------------------------

# 8 balanced scan chains
set_scan_configuration \
    -chain_count 8 \
    -clock_mixing mix_clocks \
    -add_lockup enable \
    -create_dedicated_scan_out_ports true

# Target chain length
set_scan_configuration \
    -max_length 50000 \
    -min_length 40000

# Scan chain routing preference
set_scan_configuration \
    -internal_clocks multi \
    -replace_dedicated_clock_mux true

#-------------------------------------------------------------------------------
# Scan Chain Domain Assignment
#-------------------------------------------------------------------------------

# Chain 0-1: GPU Core domain
set_scan_path chain_0 \
    -view spec \
    -scan_data_in scan_in[0] \
    -scan_data_out scan_out[0] \
    -includes {u_command_processor u_geometry_engine}

set_scan_path chain_1 \
    -view spec \
    -scan_data_in scan_in[1] \
    -scan_data_out scan_out[1] \
    -includes {u_rasterizer u_render_output_unit u_texture_unit}

# Chain 2-5: Shader cores (4 chains, 4 CUs each)
set_scan_path chain_2 \
    -view spec \
    -scan_data_in scan_in[2] \
    -scan_data_out scan_out[2] \
    -includes {u_shader_core_0 u_shader_core_1 u_shader_core_2 u_shader_core_3}

set_scan_path chain_3 \
    -view spec \
    -scan_data_in scan_in[3] \
    -scan_data_out scan_out[3] \
    -includes {u_shader_core_4 u_shader_core_5 u_shader_core_6 u_shader_core_7}

set_scan_path chain_4 \
    -view spec \
    -scan_data_in scan_in[4] \
    -scan_data_out scan_out[4] \
    -includes {u_shader_core_8 u_shader_core_9 u_shader_core_10 u_shader_core_11}

set_scan_path chain_5 \
    -view spec \
    -scan_data_in scan_in[5] \
    -scan_data_out scan_out[5] \
    -includes {u_shader_core_12 u_shader_core_13 u_shader_core_14 u_shader_core_15}

# Chain 6: Memory and DMA
set_scan_path chain_6 \
    -view spec \
    -scan_data_in scan_in[6] \
    -scan_data_out scan_out[6] \
    -includes {u_memory_controller u_l2_cache u_dma_engine}

# Chain 7: PCIe, Display, Infrastructure
set_scan_path chain_7 \
    -view spec \
    -scan_data_in scan_in[7] \
    -scan_data_out scan_out[7] \
    -includes {u_pcie_controller u_display_controller u_clock_reset_controller \
               u_power_management_unit u_interrupt_controller u_debug_controller}

#-------------------------------------------------------------------------------
# Scan Compression
#-------------------------------------------------------------------------------

# Enable scan compression (EDT or similar)
set_scan_compression_configuration \
    -ratio 32 \
    -mode_signal comp_enable \
    -inputs 8 \
    -outputs 8

# Compression exclusions (analog, clock generators)
set_scan_compression_configuration \
    -exclude [get_cells u_clock_reset_controller/pll_*]

#-------------------------------------------------------------------------------
# Test Points
#-------------------------------------------------------------------------------

# Add observation points for hard-to-test logic
set_testpoint_configuration \
    -observation enable \
    -control enable

# Add test points at low observability nodes
identify_test_points \
    -observability \
    -detectability_low 0.3

#-------------------------------------------------------------------------------
# Memory BIST
#-------------------------------------------------------------------------------

# Enable MBIST for all SRAMs
set_dft_configuration -memory_test enable

set_dft_signal -view spec -type MbistMode   -port mbist_mode
set_dft_signal -view spec -type MbistStart  -port mbist_start
set_dft_signal -view spec -type MbistDone   -port mbist_done
set_dft_signal -view spec -type MbistFail   -port mbist_fail
set_dft_signal -view spec -type MbistDiag   -port mbist_diag_data[*]

# MBIST configuration
set_memory_bist_configuration \
    -algorithm MarchC+ \
    -retention_test enable \
    -interface_style bus \
    -comparator_sharing all

# Memory groups for MBIST
create_memory_group L1_CACHE_MEM \
    -memories [get_cells u_shader_core_*/u_dcache/mem_array* \
               u_shader_core_*/u_icache/mem_array*]

create_memory_group L2_CACHE_MEM \
    -memories [get_cells u_l2_cache/cache_bank_*/mem_array*]

create_memory_group REG_FILE_MEM \
    -memories [get_cells u_shader_core_*/u_register_file/rf_array*]

#-------------------------------------------------------------------------------
# Boundary Scan (JTAG)
#-------------------------------------------------------------------------------

# JTAG signals already defined in design
set_dft_signal -view existing_dft -type tck  -port tck
set_dft_signal -view existing_dft -type tms  -port tms
set_dft_signal -view existing_dft -type tdi  -port tdi
set_dft_signal -view existing_dft -type tdo  -port tdo
set_dft_signal -view existing_dft -type trst -port trst_n -active_state 0

# JTAG TAP configuration
set_boundary_scan_configuration \
    -device_id 32'h14970001 \
    -manufacturer_id 11'h4CB \
    -part_number 16'h7001 \
    -version 4'h1

#-------------------------------------------------------------------------------
# DFT Exclusions
#-------------------------------------------------------------------------------

# Exclude analog blocks
set_scan_element false [get_cells u_clock_reset_controller/pll_*]
set_scan_element false [get_cells u_pcie_controller/serdes_*]
set_scan_element false [get_cells u_display_controller/phy_*]

# Exclude async FIFOs (handled separately)
set_scan_element false [get_cells -hier *async_fifo*/*gray_ptr*]

# Exclude clock gating cells (special handling)
set_scan_element false [get_cells -hier *clk_gate*]

#-------------------------------------------------------------------------------
# DFT Rules and Checks
#-------------------------------------------------------------------------------

# Run DFT DRC
set_dft_drc_configuration \
    -internal_pins enable \
    -bidirectional_pins warn \
    -combinational_feedback error

# Check for issues
dft_drc

# Preview scan insertion
preview_dft

#-------------------------------------------------------------------------------
# Insert DFT
#-------------------------------------------------------------------------------

# Insert scan chains
insert_dft

# Insert MBIST
insert_memory_test

# Insert boundary scan
insert_boundary_scan

#-------------------------------------------------------------------------------
# Post-DFT Reports
#-------------------------------------------------------------------------------

# Report scan chain information
report_scan_chains > reports/scan_chains.rpt

# Report coverage
report_dft_coverage > reports/dft_coverage.rpt

# Report MBIST
report_memory_bist > reports/mbist.rpt

# Report boundary scan
report_boundary_scan > reports/boundary_scan.rpt

#-------------------------------------------------------------------------------
# ATPG Configuration
#-------------------------------------------------------------------------------

# ATPG settings for pattern generation
set_atpg_configuration \
    -patterns_per_scan_load 1 \
    -launch_capture_clock system \
    -pattern_type static_sequential

# Fault coverage targets
set_atpg_configuration \
    -coverage_target 98.0 \
    -abort_limit 10

# Generate patterns (run separately)
# create_patterns -output patterns/scan_patterns.stil

#-------------------------------------------------------------------------------
# End of DFT Configuration
#-------------------------------------------------------------------------------

puts "==========================================="
puts "LKG-GPU DFT Configuration Complete"
puts "==========================================="
puts "Scan Chains: 8"
puts "Compression Ratio: 32:1"
puts "MBIST: Enabled"
puts "Boundary Scan: IEEE 1149.1"
puts "Target Coverage: 98%"
puts "==========================================="
