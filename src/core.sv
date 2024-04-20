`default_nettype none
`timescale 1ns/1ns

module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter MAX_WARPS_PER_CORE = 2,
    parameter THREADS_PER_WARP = 2,
    parameter THREAD_ID_BITS = $clog2(THREADS_PER_WARP),
    parameter CORE_ID = 0
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    // KERNEL METADATA
    input wire [7:0] block_dim,
    input wire [7:0] thread_count,

    // PROGRAM MEMORY
    output reg program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input reg program_mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // DATA MEMORY
    output reg [THREADS_PER_WARP-1:0] data_mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_WARP-1:0],
    input reg [THREADS_PER_WARP-1:0] data_mem_read_ready,
    input reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_WARP-1:0],

    output reg [THREADS_PER_WARP-1:0] data_mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_WARP-1:0],
    output reg [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_WARP-1:0],
    input reg [THREADS_PER_WARP-1:0] data_mem_write_ready
);
    // WARPS
    reg [7:0] warp_pc [MAX_WARPS_PER_CORE-1:0];
    reg [THREAD_ID_BITS-1:0] current_warp_id;

    // STATE
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'b10, WAITING = 2'b11;
    reg [2:0] core_state;
    reg [2:0] fetcher_state;
    reg [15:0] instruction;

    // EXECUTION
    reg [7:0] rs[THREADS_PER_WARP-1:0];
    reg [7:0] rt[THREADS_PER_WARP-1:0];
    reg [1:0] lsu_state[THREADS_PER_WARP-1:0];
    reg [7:0] lsu_out[THREADS_PER_WARP-1:0];
    wire [7:0] next_pc[THREADS_PER_WARP-1:0];
    wire [7:0] alu_out[THREADS_PER_WARP-1:0];
    
    // DECODER
    reg [3:0] decoded_rd_address;
    reg [3:0] decoded_rs_address;
    reg [3:0] decoded_rt_address;
    reg [2:0] decoded_nzp;
    reg [7:0] decoded_immediate;
    reg decoded_reg_write_enable;           // Enable writing to a register
    reg decoded_mem_read_enable;            // Enable reading from memory
    reg decoded_mem_write_enable;           // Enable writing to memory
    reg decoded_nzp_write_enable;           // Enable writing to NZP register
    reg [1:0] decoded_reg_input_mux;        // Select input to register
    reg [1:0] decoded_alu_arithmetic_mux;   // Select arithmetic operation
    reg decoded_alu_output_mux;             // Select operation in ALU
    reg decoded_pc_mux;                     // Select source of next PC
    reg decoded_ret;

    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk),
        .reset(reset),
        .core_state(core_state),
        .current_pc(warp_pc[current_warp_id]),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction) 
    );

    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
        .core_state(core_state),
        .instruction(instruction),
        .decoded_rd_address(decoded_rd_address),
        .decoded_rs_address(decoded_rs_address),
        .decoded_rt_address(decoded_rt_address),
        .decoded_nzp(decoded_nzp),
        .decoded_immediate(decoded_immediate),
        .decoded_reg_write_enable(decoded_reg_write_enable),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_nzp_write_enable(decoded_nzp_write_enable),
        .decoded_reg_input_mux(decoded_reg_input_mux),
        .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
        .decoded_alu_output_mux(decoded_alu_output_mux),
        .decoded_pc_mux(decoded_pc_mux),
        .decoded_ret(decoded_ret)
    );

    warps #(
        .THREADS_PER_WARP(THREADS_PER_WARP),
        .MAX_WARPS_PER_CORE(MAX_WARPS_PER_CORE),
        .THREAD_ID_BITS(THREAD_ID_BITS)
    ) warp_scheduler (
        .clk(clk),
        .reset(reset),
        .start(start),
        .fetcher_state(fetcher_state),
        .core_state(core_state),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_ret(decoded_ret),
        .lsu_state(lsu_state),
        .thread_count(thread_count),
        .warp_pc(warp_pc),
        .next_pc(next_pc),
        .current_warp_id(current_warp_id),
        .done(done)
    );

    genvar i;
    generate
        for (i = 0; i < THREADS_PER_WARP; i = i + 1) begin : threads
            alu alu_instance (
                .clk(clk),
                .reset(reset),
                .core_state(core_state),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .rs(rs[i]),
                .rt(rt[i]),
                .alu_out(alu_out[i])
            );

            lsu lsu_instance (
                .clk(clk),
                .reset(reset),
                .core_state(core_state),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .mem_read_valid(data_mem_read_valid[i]),
                .mem_read_address(data_mem_read_address[i]),
                .mem_read_ready(data_mem_read_ready[i]),
                .mem_read_data(data_mem_read_data[i]),
                .mem_write_valid(data_mem_write_valid[i]),
                .mem_write_address(data_mem_write_address[i]),
                .mem_write_data(data_mem_write_data[i]),
                .mem_write_ready(data_mem_write_ready[i]),
                .rs(rs[i]),
                .rt(rt[i]),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            registers #(
                .BLOCK_ID(CORE_ID),
                .THREAD_ID(i),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) register_instance (
                .clk(clk),
                .reset(reset),
                .block_dim(block_dim),
                .core_state(core_state),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_immediate(decoded_immediate),
                .alu_out(alu_out[i]),
                .lsu_out(lsu_out[i]),
                .rs(rs[i]),
                .rt(rt[i])
            );

            pc #(
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
            ) pc_instance (
                .clk(clk),
                .reset(reset),
                .core_state(core_state),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_pc_mux(decoded_pc_mux),
                .alu_out(alu_out[i]),
                .current_pc(warp_pc[current_warp_id]),
                .next_pc(next_pc[i])
            );
        end
    endgenerate
endmodule
