################################################################################
# LKG-GPU FPGA Constraints for Intel/Altera
# Target: Intel Agilex / Stratix 10 (DevKit or Custom Board)
# Tool: Quartus Prime Pro 23.x
################################################################################

################################################################################
# Clock Constraints
################################################################################

# System reference clock (100 MHz)
create_clock -name sys_clk_100 -period 10.000 [get_ports ref_clk_100mhz]
set_instance_assignment -name IO_STANDARD LVDS -to ref_clk_100mhz

# PCIe reference clock (100 MHz)
create_clock -name pcie_refclk -period 10.000 [get_ports pcie_refclk]
set_instance_assignment -name IO_STANDARD HCSL -to pcie_refclk

################################################################################
# Generated Clocks
################################################################################

# Core clock from PLL (500 MHz for FPGA)
create_generated_clock -name core_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 5 \
    [get_pins u_pll_core|outclk_0]

# Memory interface clock (400 MHz for DDR4-2400)
create_generated_clock -name memory_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 4 \
    [get_pins u_pll_mem|outclk_0]

# Display clock (148.5 MHz for 1080p60)
create_generated_clock -name display_clk \
    -source [get_ports ref_clk_100mhz] \
    -multiply_by 1485 -divide_by 1000 \
    [get_pins u_pll_display|outclk_0]

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
# Pin Assignments - Intel Agilex F-Series Dev Kit
################################################################################

# System clock
set_location_assignment PIN_BH28 -to ref_clk_100mhz
set_instance_assignment -name IO_STANDARD "TRUE DIFFERENTIAL SIGNALING" -to ref_clk_100mhz

# Reset
set_location_assignment PIN_BK30 -to ext_rst_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to ext_rst_n
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to ext_rst_n

################################################################################
# PCIe Constraints
################################################################################

# PCIe Hard IP location
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to |
set_global_assignment -name PCIE_IP_VERSION 1.0
set_global_assignment -name PCIE_IP_LANES X16
set_global_assignment -name PCIE_IP_GENERATION GEN4

# PCIe lane assignments (x16)
set_location_assignment PIN_AT52 -to "pcie_rx[0]"
set_location_assignment PIN_AU52 -to "pcie_rx[1]"
set_location_assignment PIN_AV52 -to "pcie_rx[2]"
set_location_assignment PIN_AW52 -to "pcie_rx[3]"
set_location_assignment PIN_AY52 -to "pcie_rx[4]"
set_location_assignment PIN_BA52 -to "pcie_rx[5]"
set_location_assignment PIN_BB52 -to "pcie_rx[6]"
set_location_assignment PIN_BC52 -to "pcie_rx[7]"
set_location_assignment PIN_BD52 -to "pcie_rx[8]"
set_location_assignment PIN_BE52 -to "pcie_rx[9]"
set_location_assignment PIN_BF52 -to "pcie_rx[10]"
set_location_assignment PIN_BG52 -to "pcie_rx[11]"
set_location_assignment PIN_BH52 -to "pcie_rx[12]"
set_location_assignment PIN_BJ52 -to "pcie_rx[13]"
set_location_assignment PIN_BK52 -to "pcie_rx[14]"
set_location_assignment PIN_BL52 -to "pcie_rx[15]"

set_location_assignment PIN_AT49 -to "pcie_tx[0]"
set_location_assignment PIN_AU49 -to "pcie_tx[1]"
set_location_assignment PIN_AV49 -to "pcie_tx[2]"
set_location_assignment PIN_AW49 -to "pcie_tx[3]"
set_location_assignment PIN_AY49 -to "pcie_tx[4]"
set_location_assignment PIN_BA49 -to "pcie_tx[5]"
set_location_assignment PIN_BB49 -to "pcie_tx[6]"
set_location_assignment PIN_BC49 -to "pcie_tx[7]"
set_location_assignment PIN_BD49 -to "pcie_tx[8]"
set_location_assignment PIN_BE49 -to "pcie_tx[9]"
set_location_assignment PIN_BF49 -to "pcie_tx[10]"
set_location_assignment PIN_BG49 -to "pcie_tx[11]"
set_location_assignment PIN_BH49 -to "pcie_tx[12]"
set_location_assignment PIN_BJ49 -to "pcie_tx[13]"
set_location_assignment PIN_BK49 -to "pcie_tx[14]"
set_location_assignment PIN_BL49 -to "pcie_tx[15]"

set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to pcie_rx[*]
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to pcie_tx[*]

# PCIe persist signal
set_location_assignment PIN_BR30 -to pcie_perstn
set_instance_assignment -name IO_STANDARD "1.8 V" -to pcie_perstn

################################################################################
# DDR4 Memory Interface
################################################################################

# DDR4 EMIF placement
set_instance_assignment -name HPS_DDR_IO_MODE "DDR4" -to ddr4

# DDR4 address pins
set_location_assignment PIN_C32 -to ddr4_addr[0]
set_location_assignment PIN_D32 -to ddr4_addr[1]
set_location_assignment PIN_E32 -to ddr4_addr[2]
set_location_assignment PIN_F32 -to ddr4_addr[3]
set_location_assignment PIN_G32 -to ddr4_addr[4]
set_location_assignment PIN_H32 -to ddr4_addr[5]
# ... continue for remaining address pins

set_instance_assignment -name IO_STANDARD "SSTL-12" -to ddr4_addr[*]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 40 OHM" -to ddr4_addr[*]

# DDR4 data pins
set_location_assignment PIN_A34 -to ddr4_dq[0]
set_location_assignment PIN_B34 -to ddr4_dq[1]
# ... continue for all DQ pins

set_instance_assignment -name IO_STANDARD "POD12" -to ddr4_dq[*]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 40 OHM" -to ddr4_dq[*]

# DDR4 strobe pins
set_location_assignment PIN_A33 -to ddr4_dqs_p[0]
set_location_assignment PIN_B33 -to ddr4_dqs_n[0]
# ... continue for all DQS pins

set_instance_assignment -name IO_STANDARD "DIFFERENTIAL POD12" -to ddr4_dqs_*

################################################################################
# JTAG Debug Interface
################################################################################

set_location_assignment PIN_CA30 -to tck
set_location_assignment PIN_CB30 -to tms
set_location_assignment PIN_CC30 -to tdi
set_location_assignment PIN_CD30 -to tdo
set_location_assignment PIN_CE30 -to trst_n

set_instance_assignment -name IO_STANDARD "1.8 V" -to tck
set_instance_assignment -name IO_STANDARD "1.8 V" -to tms
set_instance_assignment -name IO_STANDARD "1.8 V" -to tdi
set_instance_assignment -name IO_STANDARD "1.8 V" -to tdo
set_instance_assignment -name IO_STANDARD "1.8 V" -to trst_n
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to trst_n

################################################################################
# Status LEDs
################################################################################

set_location_assignment PIN_BM26 -to status_led[0]
set_location_assignment PIN_BN26 -to status_led[1]
set_location_assignment PIN_BP26 -to status_led[2]
set_location_assignment PIN_BR26 -to status_led[3]

set_instance_assignment -name IO_STANDARD "1.8 V" -to status_led[*]
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to status_led[*]

################################################################################
# Timing Exceptions
################################################################################

# False paths for reset synchronizers
set_false_path -from [get_ports ext_rst_n]

# False paths for static configuration
set_false_path -from [get_registers {u_*|config_*[*]}]

# CDC constraints
set_max_delay 5.0 \
    -from [get_clocks core_clk] \
    -to [get_clocks memory_clk]

set_max_delay 5.0 \
    -from [get_clocks memory_clk] \
    -to [get_clocks core_clk]

################################################################################
# Logic Placement (Logic Lock Regions)
################################################################################

# Shader cores region
set_instance_assignment -name LOGIC_LOCK_REGION ON -to u_gpu_soc|u_shader_core_*
set_instance_assignment -name LOGIC_LOCK_ORIGIN X50_Y100 -to u_gpu_soc|u_shader_core_0
set_instance_assignment -name LOGIC_LOCK_WIDTH 100 -to u_gpu_soc|u_shader_core_*
set_instance_assignment -name LOGIC_LOCK_HEIGHT 50 -to u_gpu_soc|u_shader_core_*

# Memory controller region  
set_instance_assignment -name LOGIC_LOCK_REGION ON -to u_gpu_soc|u_memory_controller
set_instance_assignment -name LOGIC_LOCK_ORIGIN X0_Y0 -to u_gpu_soc|u_memory_controller
set_instance_assignment -name LOGIC_LOCK_WIDTH 200 -to u_gpu_soc|u_memory_controller
set_instance_assignment -name LOGIC_LOCK_HEIGHT 40 -to u_gpu_soc|u_memory_controller

################################################################################
# Optimization Settings
################################################################################

# Enable physical synthesis
set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC ON
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_RETIMING ON
set_global_assignment -name PHYSICAL_SYNTHESIS_ASYNCHRONOUS_SIGNAL_PIPELINING ON
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON

# Fitter effort
set_global_assignment -name FITTER_EFFORT "STANDARD FIT"
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE PERFORMANCE"

# Auto RAM recognition
set_global_assignment -name AUTO_RAM_RECOGNITION ON
set_global_assignment -name AUTO_DSP_RECOGNITION ON

# Retiming
set_global_assignment -name ALLOW_REGISTER_RETIMING ON
set_global_assignment -name ALLOW_ANY_RAM_SIZE_FOR_RECOGNITION ON

################################################################################
# Power Analysis Settings
################################################################################

set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
set_global_assignment -name POWER_DEFAULT_INPUT_IO_TOGGLE_RATE "12.5 %"
set_global_assignment -name POWER_USE_PVA ON

################################################################################
# SignalTap Debug (Optional)
################################################################################

# Enable SignalTap for debug
# set_global_assignment -name ENABLE_SIGNALTAP ON
# set_global_assignment -name USE_SIGNALTAP_FILE debug.stp

################################################################################
# Configuration
################################################################################

set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "AVST X16"
set_global_assignment -name GENERATE_RBF_FILE ON
set_global_assignment -name GENERATE_SOF_FILE ON
set_global_assignment -name ON_CHIP_BITSTREAM_DECOMPRESSION ON

################################################################################
# End of SDC/QSF
################################################################################
