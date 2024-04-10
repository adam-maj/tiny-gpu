`default_nettype none
`timescale 1ns/1ns

// GPU
module gpu #(
    parameter BITS = 32
) (
    // Control
    input wire clk,
    input wire reset,

    // Execution
    input wire start,
    output wire done,

    // Memory
    input wire [BITS-1:0] mem_read_address,
    output wire [BITS-1:0] mem_read_data,
    input wire [BITS-1:0] mem_write_address,
    input wire [BITS-1:0] mem_write_data,
);
    // Global Memory

    // Dispatcher

    // Streaming Multiprocessors
endmodule