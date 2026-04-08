################################################################################
# LKG-GPU FPGA Constraints for Xilinx Ultrascale+
# Target: Xilinx VU9P / VU13P (Alveo U200/U280)
# Tool: Vivado 2023.x
################################################################################

################################################################################
# Clock Constraints
################################################################################

# System reference clock (100 MHz)
create_clock -period 10.000 -name sys_clk_100 [get_ports ref_clk_100mhz]
set_property IOSTANDARD LVDS [get_ports ref_clk_100mhz]
set_property PACKAGE_PIN G31 [get_ports ref_clk_100mhz]

# PCIe reference clock (100 MHz)
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AF8 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AF7 [get_ports pcie_refclk_n]

# HBM reference clock (100 MHz) - for Alveo with HBM
create_clock -period 10.000 -name hbm_refclk [get_ports hbm_refclk]
set_property PACKAGE_PIN BJ43 [get_ports hbm_refclk]

################################################################################
# Generated Clocks
################################################################################

# Core clock from MMCM (500 MHz for FPGA - reduced from ASIC 2GHz)
create_generated_clock -name core_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 5 \
    [get_pins u_clock_gen/mmcm_inst/CLKOUT0]

# Memory interface clock (450 MHz for DDR4-2400)
create_generated_clock -name memory_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 9 -divide_by 2 \
    [get_pins u_clock_gen/mmcm_inst/CLKOUT1]

# Display clock (148.5 MHz for 1080p60)
create_generated_clock -name display_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 1485 -divide_by 1000 \
    [get_pins u_clock_gen/mmcm_display/CLKOUT0]

################################################################################
# Clock Domain Crossings
################################################################################

set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_100] \
    -group [get_clocks pcie_refclk] \
    -group [get_clocks core_clk] \
    -group [get_clocks memory_clk] \
    -group [get_clocks display_clk]

################################################################################
# PCIe Constraints
################################################################################

# PCIe hard block location
set_property LOC PCIE40E4_X1Y0 [get_cells u_pcie/pcie_inst]

# PCIe lane assignments (x16)
set_property PACKAGE_PIN AD2  [get_ports {pcie_rx_p[0]}]
set_property PACKAGE_PIN AD1  [get_ports {pcie_rx_n[0]}]
set_property PACKAGE_PIN AC4  [get_ports {pcie_tx_p[0]}]
set_property PACKAGE_PIN AC3  [get_ports {pcie_tx_n[0]}]
set_property PACKAGE_PIN AB2  [get_ports {pcie_rx_p[1]}]
set_property PACKAGE_PIN AB1  [get_ports {pcie_rx_n[1]}]
set_property PACKAGE_PIN AA4  [get_ports {pcie_tx_p[1]}]
set_property PACKAGE_PIN AA3  [get_ports {pcie_tx_n[1]}]
set_property PACKAGE_PIN Y2   [get_ports {pcie_rx_p[2]}]
set_property PACKAGE_PIN Y1   [get_ports {pcie_rx_n[2]}]
set_property PACKAGE_PIN W4   [get_ports {pcie_tx_p[2]}]
set_property PACKAGE_PIN W3   [get_ports {pcie_tx_n[2]}]
set_property PACKAGE_PIN V2   [get_ports {pcie_rx_p[3]}]
set_property PACKAGE_PIN V1   [get_ports {pcie_rx_n[3]}]
set_property PACKAGE_PIN U4   [get_ports {pcie_tx_p[3]}]
set_property PACKAGE_PIN U3   [get_ports {pcie_tx_n[3]}]
# ... continue for lanes 4-15

# PCIe persist signal
set_property PACKAGE_PIN K22 [get_ports pcie_perstn]
set_property IOSTANDARD LVCMOS18 [get_ports pcie_perstn]

################################################################################
# DDR4 Memory Interface
################################################################################

# DDR4 Controller placement
set_property LOC MMCM_X1Y6 [get_cells u_mig/u_ddr4_mem_intfc/u_ddr4_infrastructure/gen_mmcme*.u_mmcme_adv_inst]

# DDR4 address pins
set_property PACKAGE_PIN AY17 [get_ports {ddr4_addr[0]}]
set_property PACKAGE_PIN AY18 [get_ports {ddr4_addr[1]}]
set_property PACKAGE_PIN AW17 [get_ports {ddr4_addr[2]}]
set_property PACKAGE_PIN AW18 [get_ports {ddr4_addr[3]}]
set_property PACKAGE_PIN AV17 [get_ports {ddr4_addr[4]}]
set_property PACKAGE_PIN AV18 [get_ports {ddr4_addr[5]}]
# ... continue for remaining address pins

set_property IOSTANDARD POD12_DCI [get_ports {ddr4_addr[*]}]
set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports {ddr4_addr[*]}]

# DDR4 data pins (64-bit wide)
set_property PACKAGE_PIN BA15 [get_ports {ddr4_dq[0]}]
set_property PACKAGE_PIN BA16 [get_ports {ddr4_dq[1]}]
# ... continue for all DQ pins

set_property IOSTANDARD POD12_DCI [get_ports {ddr4_dq[*]}]
set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports {ddr4_dq[*]}]

# DDR4 strobe pins
set_property PACKAGE_PIN BB14 [get_ports {ddr4_dqs_p[0]}]
set_property PACKAGE_PIN BB13 [get_ports {ddr4_dqs_n[0]}]
# ... continue for all DQS pins

set_property IOSTANDARD DIFF_POD12_DCI [get_ports {ddr4_dqs_*}]

################################################################################
# HBM Constraints (for Alveo U280/U50)
################################################################################

# HBM stack 0 placement
set_property HBM_STACK 0 [get_cells u_hbm/hbm_inst]

# HBM AXI interface clocking
set_property CLOCKING_MODE INDEPENDENT [get_cells u_hbm/hbm_inst]

################################################################################
# Display/Video Output
################################################################################

# DisplayPort TX GTH
set_property LOC GTH_QUAD_X0Y4 [get_cells u_dp_tx/gth_quad]
set_property PACKAGE_PIN E10 [get_ports dp_tx_p[0]]
set_property PACKAGE_PIN E9  [get_ports dp_tx_n[0]]
set_property PACKAGE_PIN F12 [get_ports dp_tx_p[1]]
set_property PACKAGE_PIN F11 [get_ports dp_tx_n[1]]
set_property PACKAGE_PIN G10 [get_ports dp_tx_p[2]]
set_property PACKAGE_PIN G9  [get_ports dp_tx_n[2]]
set_property PACKAGE_PIN H12 [get_ports dp_tx_p[3]]
set_property PACKAGE_PIN H11 [get_ports dp_tx_n[3]]

# DisplayPort aux channel
set_property PACKAGE_PIN P23 [get_ports dp_aux_p]
set_property PACKAGE_PIN P24 [get_ports dp_aux_n]
set_property IOSTANDARD LVDS [get_ports dp_aux_*]

# Hot plug detect
set_property PACKAGE_PIN R23 [get_ports dp_hpd]
set_property IOSTANDARD LVCMOS18 [get_ports dp_hpd]

################################################################################
# JTAG Debug Interface
################################################################################

set_property PACKAGE_PIN AJ28 [get_ports tck]
set_property PACKAGE_PIN AK28 [get_ports tms]
set_property PACKAGE_PIN AL28 [get_ports tdi]
set_property PACKAGE_PIN AM28 [get_ports tdo]
set_property PACKAGE_PIN AN28 [get_ports trst_n]

set_property IOSTANDARD LVCMOS18 [get_ports {tck tms tdi tdo trst_n}]
set_property PULLUP TRUE [get_ports trst_n]

################################################################################
# Reset
################################################################################

set_property PACKAGE_PIN L19 [get_ports ext_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports ext_rst_n]
set_property PULLUP TRUE [get_ports ext_rst_n]

################################################################################
# Status LEDs
################################################################################

set_property PACKAGE_PIN D32 [get_ports {status_led[0]}]
set_property PACKAGE_PIN D31 [get_ports {status_led[1]}]
set_property PACKAGE_PIN E32 [get_ports {status_led[2]}]
set_property PACKAGE_PIN E31 [get_ports {status_led[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {status_led[*]}]

################################################################################
# Timing Exceptions
################################################################################

# False paths for reset synchronizers
set_false_path -from [get_ports ext_rst_n]

# False paths for static configuration
set_false_path -from [get_cells u_*/config_*_reg[*]]

# CDC paths with async FIFO
set_max_delay -datapath_only 5.0 \
    -from [get_clocks core_clk] \
    -to [get_clocks memory_clk] \
    -through [get_cells u_*/async_fifo_*/wr_ptr_*]

set_max_delay -datapath_only 5.0 \
    -from [get_clocks memory_clk] \
    -to [get_clocks core_clk] \
    -through [get_cells u_*/async_fifo_*/rd_ptr_*]

################################################################################
# Physical Constraints
################################################################################

# Shader core placement (Pblocks)
create_pblock pblock_shader_0
add_cells_to_pblock [get_pblocks pblock_shader_0] [get_cells u_gpu_soc/u_shader_core_0]
add_cells_to_pblock [get_pblocks pblock_shader_0] [get_cells u_gpu_soc/u_shader_core_1]
add_cells_to_pblock [get_pblocks pblock_shader_0] [get_cells u_gpu_soc/u_shader_core_2]
add_cells_to_pblock [get_pblocks pblock_shader_0] [get_cells u_gpu_soc/u_shader_core_3]
resize_pblock [get_pblocks pblock_shader_0] -add {SLICE_X0Y300:SLICE_X60Y599}
resize_pblock [get_pblocks pblock_shader_0] -add {RAMB36_X0Y60:RAMB36_X3Y119}
resize_pblock [get_pblocks pblock_shader_0] -add {DSP48E2_X0Y120:DSP48E2_X4Y239}

create_pblock pblock_shader_1
add_cells_to_pblock [get_pblocks pblock_shader_1] [get_cells u_gpu_soc/u_shader_core_4]
add_cells_to_pblock [get_pblocks pblock_shader_1] [get_cells u_gpu_soc/u_shader_core_5]
add_cells_to_pblock [get_pblocks pblock_shader_1] [get_cells u_gpu_soc/u_shader_core_6]
add_cells_to_pblock [get_pblocks pblock_shader_1] [get_cells u_gpu_soc/u_shader_core_7]
resize_pblock [get_pblocks pblock_shader_1] -add {SLICE_X70Y300:SLICE_X130Y599}
resize_pblock [get_pblocks pblock_shader_1] -add {RAMB36_X4Y60:RAMB36_X7Y119}
resize_pblock [get_pblocks pblock_shader_1] -add {DSP48E2_X5Y120:DSP48E2_X9Y239}

# Memory controller placement
create_pblock pblock_memory
add_cells_to_pblock [get_pblocks pblock_memory] [get_cells u_gpu_soc/u_memory_controller]
add_cells_to_pblock [get_pblocks pblock_memory] [get_cells u_mig]
resize_pblock [get_pblocks pblock_memory] -add {SLICE_X0Y0:SLICE_X130Y100}

################################################################################
# Implementation Strategy
################################################################################

# High-performance implementation
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING auto [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.NO_LC false [get_runs synth_1]

set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreSequentialArea [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

################################################################################
# Bitstream Configuration
################################################################################

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8 [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]

################################################################################
# End of XDC
################################################################################
