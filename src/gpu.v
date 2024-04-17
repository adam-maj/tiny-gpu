`default_nettype none
`timescale 1ns/1ns

module gpu #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter NUM_CORES = 4,
    parameter MAX_WARPS_PER_CORE = 4,
    parameter THREADS_PER_WARP = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    // DEVICE CONTROL REGISTER
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // DATA MEMORY
    output wire data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address,
    input reg data_mem_read_ready,
    input reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data,
    output wire data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address,
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data,
    input reg data_mem_write_ready

    // PROGRAM MEMORY
    output wire program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input reg program_mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,
    output wire program_mem_write_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_write_address,
    output wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_write_data,
    input reg program_mem_write_ready
);
    reg [7:0] device_conrol_register;
    wire [7:0] thread_count;
    wire [7:0] block_dim;
    wire [NUM_CORES-1:0] core_done;

    assign thread_count = device_conrol_register[7:0];
    assign block_dim = (thread_count + NUM_CORES - 1) / NUM_CORES;
    
    // MEMORY CONTROLLERS
    controller data_memory_controller (
        .clk(clk),
        .reset(reset),

        // LSUs

        // Data Memory
        .mem_read_valid(data_mem_read_valid),
        .mem_read_address(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address(data_mem_write_address),
        .mem_write_data(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );

    // CORES
    genvar i;
    generate
        for (i = 0; i < CORES; i = i + 1) begin : cores
            localparam block_thread_count = (i == CORES - 1) 
                ? (thread_count - (BLOCK_DIM * i)) 
                : BLOCK_DIM;

            core #(
                .BLOCK_ID(i)
            ) core_instance (
                .clk(clk),
                .reset(reset),
                .start(start),
                .block_dim(block_dim),
                .thread_count(block_thread_count)
                .data_memory_control(data_memory_control),
                .program_memory_control(program_memory_control)
                .done(core_done[i])
            );
        end
    endgenerate

    // DEVICE CONTROL REGISTER
    always @(posedge clk) begin
        if (reset) begin
            device_conrol_register <= 8'b0;
        end else begin
            if (device_control_write_enable) begin 
                device_conrol_register <= device_control_data;
            end
        end
    end

    assign done = &(core_done);
endmodule