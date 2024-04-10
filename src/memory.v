`default_nettype none
`timescale 1ns/1ns

// GLOBAL DATA MEMORY (0-N) & GLOBAL PROGRAM MEMORY (N-Z)
module memory #(
    parameter BITS = 32
) (
    // Control
    input wire clk,
    input wire reset,

    // Memory
    input wire [BITS-1:0] mem_read_address,
    output wire [BITS-1:0] mem_read_data,
    input wire [BITS-1:0] mem_write_address,
    input wire [BITS-1:0] mem_write_data,
);

endmodule