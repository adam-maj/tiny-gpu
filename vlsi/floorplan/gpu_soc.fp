################################################################################
# LKG-GPU Floorplan Definition
# Target: ASIC Implementation
# Die Size: 25mm² (5mm x 5mm) - Estimation for TSMC 7nm
################################################################################

#-------------------------------------------------------------------------------
# Die/Core Area Definition
#-------------------------------------------------------------------------------

# Die dimensions (um)
set die_llx 0.0
set die_lly 0.0
set die_urx 5000.0
set die_ury 5000.0

# Core dimensions (leaving 100um for I/O ring)
set core_llx 100.0
set core_lly 100.0
set core_urx 4900.0
set core_ury 4900.0

# Define die area
create_die_area \
    -polygon [list \
        [list $die_llx $die_lly] \
        [list $die_urx $die_lly] \
        [list $die_urx $die_ury] \
        [list $die_llx $die_ury] \
    ]

# Define core area
create_core_area \
    -polygon [list \
        [list $core_llx $core_lly] \
        [list $core_urx $core_lly] \
        [list $core_urx $core_ury] \
        [list $core_llx $core_ury] \
    ]

#-------------------------------------------------------------------------------
# Floorplan Regions
#-------------------------------------------------------------------------------

# Region coordinates (x_ll, y_ll, x_ur, y_ur) in um

# Shader Cores - Large area in center (60% of die)
# 4x4 grid of shader CUs
create_region SHADER_REGION \
    -llx 600 -lly 600 \
    -urx 4400 -ury 4400 \
    -type exclusive

# Memory Controller - Bottom edge
create_region MEMORY_REGION \
    -llx 600 -lly 100 \
    -urx 4400 -ury 550 \
    -type exclusive

# PCIe Controller - Left edge
create_region PCIE_REGION \
    -llx 100 -lly 600 \
    -urx 550 -ury 2500 \
    -type exclusive

# Display Controller - Right edge
create_region DISPLAY_REGION \
    -llx 4450 -lly 600 \
    -urx 4900 -ury 2500 \
    -type exclusive

# Command Processor & Geometry - Top left
create_region FRONTEND_REGION \
    -llx 100 -lly 2550 \
    -urx 550 -ury 4400 \
    -type exclusive

# ROP - Top right  
create_region ROP_REGION \
    -llx 4450 -lly 2550 \
    -urx 4900 -ury 4400 \
    -type exclusive

# L2 Cache - Distributed around shader cores
create_region L2_CACHE_REGION_0 \
    -llx 600 -lly 4450 \
    -urx 2400 -ury 4900 \
    -type exclusive

create_region L2_CACHE_REGION_1 \
    -llx 2600 -lly 4450 \
    -urx 4400 -ury 4900 \
    -type exclusive

# Infrastructure (Clock/Reset, PMU, Interrupt, Debug) - Corners
create_region INFRA_REGION_0 \
    -llx 100 -lly 4450 \
    -urx 550 -ury 4900 \
    -type exclusive

create_region INFRA_REGION_1 \
    -llx 4450 -lly 4450 \
    -urx 4900 -ury 4900 \
    -type exclusive

#-------------------------------------------------------------------------------
# Module Placement
#-------------------------------------------------------------------------------

# Shader Core placement (4x4 = 16 cores)
# Each core approximately 900um x 900um
foreach i {0 1 2 3} {
    foreach j {0 1 2 3} {
        set core_idx [expr {$i * 4 + $j}]
        set x_offset [expr {700 + $j * 950}]
        set y_offset [expr {700 + $i * 950}]
        place_inst u_shader_core_$core_idx \
            -origin [list $x_offset $y_offset] \
            -orient R0 \
            -fixed
    }
}

# Memory Controller
place_inst u_memory_controller \
    -origin {700 150} \
    -orient R0 \
    -fixed

# DMA Engine (part of memory region)
place_inst u_dma_engine \
    -origin {2600 150} \
    -orient R0 \
    -fixed

# PCIe Controller
place_inst u_pcie_controller \
    -origin {150 700} \
    -orient R0 \
    -fixed

# Display Controller
place_inst u_display_controller \
    -origin {4500 700} \
    -orient R0 \
    -fixed

# Command Processor
place_inst u_command_processor \
    -origin {150 2600} \
    -orient R0 \
    -fixed

# Geometry Engine
place_inst u_geometry_engine \
    -origin {150 3400} \
    -orient R0 \
    -fixed

# Rasterizer
place_inst u_rasterizer \
    -origin {150 4100} \
    -orient R0 \
    -fixed

# Render Output Unit (ROP)
place_inst u_render_output_unit \
    -origin {4500 2600} \
    -orient R0 \
    -fixed

# Texture Unit
place_inst u_texture_unit \
    -origin {4500 3400} \
    -orient R0 \
    -fixed

# L2 Cache Banks
place_inst u_l2_cache_bank_0 \
    -origin {700 4500} \
    -orient R0 \
    -fixed

place_inst u_l2_cache_bank_1 \
    -origin {1400 4500} \
    -orient R0 \
    -fixed

place_inst u_l2_cache_bank_2 \
    -origin {2700 4500} \
    -orient R0 \
    -fixed

place_inst u_l2_cache_bank_3 \
    -origin {3400 4500} \
    -orient R0 \
    -fixed

# Infrastructure
place_inst u_clock_reset_controller \
    -origin {150 4500} \
    -orient R0 \
    -fixed

place_inst u_power_management_unit \
    -origin {4500 4500} \
    -orient R0 \
    -fixed

place_inst u_interrupt_controller \
    -origin {4600 4600} \
    -orient R0 \
    -fixed

place_inst u_debug_controller \
    -origin {250 4600} \
    -orient R0 \
    -fixed

# Enterprise Features (interleaved with shader cores)
place_inst u_ray_tracing_unit \
    -origin {1600 1600} \
    -orient R0 \
    -fixed

place_inst u_tensor_processing_unit \
    -origin {2500 2500} \
    -orient R0 \
    -fixed

place_inst u_video_decode_unit \
    -origin {3400 1600} \
    -orient R0 \
    -fixed

#-------------------------------------------------------------------------------
# Placement Blockages
#-------------------------------------------------------------------------------

# Blockage for clock tree area
create_placement_blockage \
    -type hard \
    -llx 2350 -lly 2350 \
    -urx 2650 -ury 2650 \
    -name clock_blockage

# Blockage for power grid trunk
create_placement_blockage \
    -type partial \
    -blocked_percentage 50 \
    -llx 100 -lly 2450 \
    -urx 4900 -ury 2550 \
    -name power_h_trunk

create_placement_blockage \
    -type partial \
    -blocked_percentage 50 \
    -llx 2450 -lly 100 \
    -urx 2550 -ury 4900 \
    -name power_v_trunk

#-------------------------------------------------------------------------------
# Routing Blockages
#-------------------------------------------------------------------------------

# Block M10-M12 in memory region for memory macro routing
create_routing_blockage \
    -layers {M10 M11 M12} \
    -llx 600 -lly 100 \
    -urx 4400 -ury 550 \
    -name mem_route_block

#-------------------------------------------------------------------------------
# Pin Placement
#-------------------------------------------------------------------------------

# PCIe pins - Left side
edit_pin_placement -side left -offset 600 -pin_group pcie_group
place_pins -pins {pcie_rx_p[*] pcie_rx_n[*] pcie_tx_p[*] pcie_tx_n[*]} \
    -layer M10 -side left -start 700 -pitch 20

# Memory pins - Bottom side
edit_pin_placement -side bottom -offset 600 -pin_group mem_group
place_pins -pins {mem_clk_p mem_clk_n mem_addr[*] mem_ba[*] mem_dq[*] mem_dqs_*} \
    -layer M10 -side bottom -start 700 -pitch 15

# Display pins - Right side
edit_pin_placement -side right -offset 600 -pin_group display_group
place_pins -pins {dp_tx_p[*] dp_tx_n[*] hdmi_tx_p[*] hdmi_tx_n[*]} \
    -layer M10 -side right -start 700 -pitch 20

# Power/Clock pins - Top side
edit_pin_placement -side top -offset 100 -pin_group power_group
place_pins -pins {ref_clk_100mhz pcie_refclk ext_rst_n VDD VSS VDD_AON} \
    -layer M10 -side top -start 200 -pitch 100

# Debug pins (JTAG) - Top side
place_pins -pins {tck tms tdi tdo trst_n} \
    -layer M10 -side top -start 4500 -pitch 50

# Status pins - Top side
place_pins -pins {status_led[*]} \
    -layer M10 -side top -start 4700 -pitch 20

#-------------------------------------------------------------------------------
# Power Planning
#-------------------------------------------------------------------------------

# Core power ring
add_power_ring \
    -nets {VDD VSS} \
    -width 10 \
    -spacing 5 \
    -layer_pair {M11 M12} \
    -offset 5

# Power stripes
add_power_stripes \
    -nets {VDD VSS} \
    -direction vertical \
    -width 5 \
    -pitch 200 \
    -start 200 \
    -layer M12

add_power_stripes \
    -nets {VDD VSS} \
    -direction horizontal \
    -width 5 \
    -pitch 200 \
    -start 200 \
    -layer M11

# Memory domain power ring
add_power_ring \
    -nets {VDD_MEM VSS} \
    -width 5 \
    -spacing 3 \
    -layer_pair {M9 M10} \
    -region MEMORY_REGION

# Shader domain power mesh
add_power_mesh \
    -nets {VDD_SHADER VSS} \
    -layer_pair {M9 M10} \
    -width 3 \
    -pitch 100 \
    -region SHADER_REGION

#-------------------------------------------------------------------------------
# Clock Tree Anchor Points
#-------------------------------------------------------------------------------

# Central clock distribution point
create_clock_tree_anchor \
    -point {2500 2500} \
    -name clk_anchor_center

# Quadrant clock anchors for balanced skew
create_clock_tree_anchor -point {1500 1500} -name clk_anchor_q0
create_clock_tree_anchor -point {3500 1500} -name clk_anchor_q1
create_clock_tree_anchor -point {1500 3500} -name clk_anchor_q2
create_clock_tree_anchor -point {3500 3500} -name clk_anchor_q3

#-------------------------------------------------------------------------------
# Macro Halos
#-------------------------------------------------------------------------------

# Memory controller macro halo
create_inst_halo \
    -inst u_memory_controller \
    -halo {10 10 10 10}

# L2 cache bank halos
foreach bank {0 1 2 3} {
    create_inst_halo \
        -inst u_l2_cache_bank_$bank \
        -halo {5 5 5 5}
}

# Shader core halos
foreach core [range 0 15] {
    create_inst_halo \
        -inst u_shader_core_$core \
        -halo {3 3 3 3}
}

#-------------------------------------------------------------------------------
# DFT Scan Chain Routing Channels
#-------------------------------------------------------------------------------

# Vertical scan chain channels
create_routing_channel \
    -type scan \
    -llx 580 -lly 100 \
    -urx 600 -ury 4900 \
    -name scan_v_left

create_routing_channel \
    -type scan \
    -llx 4400 -lly 100 \
    -urx 4420 -ury 4900 \
    -name scan_v_right

# Horizontal scan chain channels
create_routing_channel \
    -type scan \
    -llx 100 -lly 580 \
    -urx 4900 -ury 600 \
    -name scan_h_bottom

create_routing_channel \
    -type scan \
    -llx 100 -lly 4400 \
    -urx 4900 -ury 4420 \
    -name scan_h_top

#-------------------------------------------------------------------------------
# End of Floorplan
#-------------------------------------------------------------------------------

# Summary
puts "==========================================="
puts "LKG-GPU Floorplan Summary"
puts "==========================================="
puts "Die Size: 5mm x 5mm = 25mm²"
puts "Core Area: 4.8mm x 4.8mm = 23.04mm²"
puts "Shader Cores: 16 (4x4 array)"
puts "L2 Cache Banks: 4"
puts "Power Domains: 7"
puts "==========================================="
