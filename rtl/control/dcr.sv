`default_nettype none
`timescale 1ns/1ns

// ============================================================
// DEVICE CONTROL REGISTER
//
// Software-visible configuration register block.
//
// Current Functionality:
//   - Kernel Thread Count Configuration
//
// Future Evolution:
//   - Grid Dimensions
//   - Block Dimensions
//   - Kernel Launch Control
//   - Performance Counters
//   - Debug Controls
// ============================================================

module dcr (
    input  logic clk,
    input  logic reset,

    //----------------------------------------------------------
    // Device Configuration Interface
    //----------------------------------------------------------
    input  logic       device_control_write_enable,
    input  logic [7:0] device_control_data,

    //----------------------------------------------------------
    // Configuration Outputs
    //----------------------------------------------------------
    output logic [7:0] thread_count
);

    //----------------------------------------------------------
    // Device Control Register
    //----------------------------------------------------------
    logic [7:0] device_control_register;
    assign thread_count = device_control_register;

    //----------------------------------------------------------
    // Register Update
    //----------------------------------------------------------
    always_ff @(posedge clk) begin
        
        if (reset) begin
            device_control_register <= '0;
        end

        else begin
            if (device_control_write_enable) begin
                device_control_register <= device_control_data;
            end
        end
    end
endmodule

`default_nettype wire