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

    // PROGRAM MEMORY
    output wire program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input reg program_mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,
    output wire program_mem_write_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_write_address,
    output wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_write_data,
    input reg program_mem_write_ready,

    // DATA MEMORY
    output wire data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address,
    input reg data_mem_read_ready,
    input reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data,
    output wire data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address,
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data,
    input reg data_mem_write_ready
);
    // CONTROL
    reg [7:0] device_conrol_register;
    wire [7:0] thread_count;
    wire [7:0] block_dim;
    wire [7:0] block_thread_count [NUM_CORES-1:0];
    wire [NUM_CORES-1:0] core_done;

    assign thread_count = device_conrol_register[7:0];
    assign block_dim = (thread_count + NUM_CORES - 1) / NUM_CORES;

    genvar j;
    generate
        for (j = 0; j < NUM_CORES; j = j + 1) begin : block_thread_count_assignment
            assign block_thread_count[j] = (j == NUM_CORES - 1) 
                ? (thread_count - (block_dim * j)) 
                : block_dim;
        end
    endgenerate

    // MEMORY ACCESS
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_WARP;
    wire [NUM_LSUS-1:0] lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] lsu_read_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [NUM_LSUS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data [NUM_LSUS-1:0];
    wire [NUM_LSUS-1:0] lsu_write_ready;

    localparam NUM_FETCHERS = NUM_CORES;
    wire [NUM_FETCHERS-1:0] fetcher_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcher_read_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcher_write_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_write_address [NUM_FETCHERS-1:0];
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcher_write_data [NUM_FETCHERS-1:0];
    wire [NUM_FETCHERS-1:0] fetcher_write_ready;
    
    // MEMORY CONTROLLERS
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_LSUS)
    ) data_memory_controller (
        .clk(clk),
        .reset(reset),

        // LSUs
        .consumer_read_valid(lsu_read_valid),
        .consumer_read_address(lsu_read_address),
        .consumer_read_ready(lsu_read_ready),
        .consumer_read_data(lsu_read_data),
        .consumer_write_valid(lsu_write_valid),
        .consumer_write_address(lsu_write_address),
        .consumer_write_data(lsu_write_data),
        .consumer_write_ready(lsu_write_ready),

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

    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS)
    ) program_memory_controller (
        .clk(clk),
        .reset(reset),

        // Fetchers
        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address(fetcher_read_address),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data(fetcher_read_data),
        .consumer_write_valid(fetcher_write_valid),
        .consumer_write_address(fetcher_write_address),
        .consumer_write_data(fetcher_write_data),
        .consumer_write_ready(fetcher_write_ready),

        // Data Memory
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .mem_write_valid(program_mem_write_valid),
        .mem_write_address(program_mem_write_address),
        .mem_write_data(program_mem_write_data),
        .mem_write_ready(program_mem_write_ready)
    );

    // CORES
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            wire [THREADS_PER_WARP-1:0] core_lsu_read_valid;
            wire [DATA_MEM_ADDR_BITS-1:0] core_lsu_read_address [THREADS_PER_WARP-1:0];
            wire [THREADS_PER_WARP-1:0] core_lsu_read_ready;
            wire [DATA_MEM_DATA_BITS-1:0] core_lsu_read_data [THREADS_PER_WARP-1:0];
            wire [THREADS_PER_WARP-1:0] core_lsu_write_valid;
            wire [DATA_MEM_ADDR_BITS-1:0] core_lsu_write_address [THREADS_PER_WARP-1:0];
            wire [DATA_MEM_DATA_BITS-1:0] core_lsu_write_data [THREADS_PER_WARP-1:0];
            wire [THREADS_PER_WARP-1:0] core_lsu_write_ready;

            genvar j;
            for (j = 0; j < THREADS_PER_WARP; j = j + 1) begin
                localparam lsu_index = i * THREADS_PER_WARP + j;
                assign lsu_read_valid[lsu_index] = core_lsu_read_valid[j];
                assign lsu_read_address[lsu_index] = core_lsu_read_address[j];
                assign core_lsu_read_ready[j] = lsu_read_ready[lsu_index];
                assign core_lsu_read_data[j] = lsu_read_data[lsu_index];

                assign lsu_write_valid[lsu_index] = core_lsu_write_valid[j];
                assign lsu_write_address[lsu_index] = core_lsu_write_address[j];
                assign lsu_write_data[lsu_index] = core_lsu_write_data[j];
                assign core_lsu_write_ready[j] = lsu_write_ready[lsu_index];
            end

            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .MAX_WARPS_PER_CORE(MAX_WARPS_PER_CORE),
                .THREADS_PER_WARP(THREADS_PER_WARP),
                .CORE_ID(i)
            ) core_instance (
                .clk(clk),
                .reset(reset),
                .start(start),
                .done(core_done[i]),
                .block_dim(block_dim),
                .thread_count(block_thread_count[i]),
                
                // Program Memory
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),
                .program_mem_write_valid(fetcher_write_valid[i]),
                .program_mem_write_address(fetcher_write_address[i]),
                .program_mem_write_data(fetcher_write_data[i]),
                .program_mem_write_ready(fetcher_write_ready[i]),

                // Data Memory
                .data_mem_read_valid(core_lsu_read_valid),
                .data_mem_read_address(core_lsu_read_address),
                .data_mem_read_ready(core_lsu_read_ready),
                .data_mem_read_data(core_lsu_read_data),
                .data_mem_write_valid(core_lsu_write_valid),
                .data_mem_write_address(core_lsu_write_address),
                .data_mem_write_data(core_lsu_write_data),
                .data_mem_write_ready(core_lsu_write_ready)
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