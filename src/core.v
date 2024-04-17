`default_nettype none
`timescale 1ns/1ns

module core #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter BLOCK_ID = 0,
    parameter WARP_SIZE = 4,
    parameter MAX_WARPS = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    // KERNEL METADATA
    input wire [7:0] block_dim,
    input wire [7:0] thread_count,

    // DATA MEMORY
    output reg data_mem_read_valid,
    output reg [7:0] data_mem_read_address,
    input reg data_mem_read_ready,
    input reg [7:0] data_mem_read_data,

    output reg data_mem_write_valid,
    output reg [7:0] data_mem_write_address,
    output reg [7:0] data_mem_write_data,
    input reg data_mem_write_ready,

    // PROGRAM MEMORY
    output reg program_mem_read_valid,
    output reg [7:0] program_mem_read_address,
    input reg program_mem_read_ready,
    input reg [7:0] program_mem_read_data,

    output reg program_mem_write_valid,
    output reg [7:0] program_mem_write_address,
    output reg [7:0] program_mem_write_data,
    input reg program_mem_write_ready
);
    // STATE
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'b10, DONE = 2'b11; 
    reg [1:0] state = IDLE;

    // WARPS
    wire warp_count = (thread_count + WARP_SIZE - 1) / WARP_SIZE;
    reg [7:0] warp_pc [0:MAX_WARPS-1];
    reg warp_done [0:MAX_WARPS-1];
    reg [7:0] current_warp_id = 0;

    // INSTRUCTION
    wire [15:0] instruction;
    wire instruction_ready = 0;

    // DECODER
    wire [3:0] decoded_rd_address;
    wire [3:0] decoded_rs_address;
    wire [3:0] decoded_rt_address;
    wire [2:0] decoded_nzp;
    wire [7:0] decoded_immediate;
    wire decoded_reg_write_enable;           // Enable writing to a register
    wire decoded_mem_read_enable;            // Enable reading from memory
    wire decoded_mem_write_enable;           // Enable writing to memory
    wire decoded_nzp_write_enable;           // Enable writing to NZP register
    wire [1:0] decoded_reg_input_mux;        // Select input to register
    wire [1:0] decoded_alu_arithmetic_mux;   // Select arithmetic operation
    wire decoded_alu_output_mux;             // Select operation in ALU
    wire decoded_pc_mux;                     // Select source of next PC
    wire decoded_done;

    // EXECUTION
    wire [7:0] rs[WARP_SIZE-1:0];
    wire [7:0] rt[WARP_SIZE-1:0];
    wire [7:0] rd[WARP_SIZE-1:0];
    wire [7:0] alu_out[WARP_SIZE-1:0];
    wire [WARP_SIZE-1:0] lsu_state;
    wire [7:0] lsu_out[WARP_SIZE-1:0];
    wire [7:0] next_pc[WARP_SIZE-1:0];

    controller memory_controller (
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

    fetcher fetcher_instance (
        .clk(clk),
        .reset(reset),
        .fetch_enable(state == FETCHING),
        .current_pc(warp_pc[current_warp_id]),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .instruction_ready(instruction_ready),
        .instruction(instruction)
    );

    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
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
        .decoded_alu_output_mux(decoded_alu_output_mux)
    );

    warps #(
        .WARP_SIZE(WARP_SIZE),
        .MAX_WARPS(MAX_WARPS)
    ) warp_scheduler (
        .clk(clk),
        .reset(reset),
        .start(start),
        .instruction_ready(instruction_ready),
        .decoded_done(decoded_done),
        .lsu_state(lsu_state),
        .thread_count(thread_count),
        .next_pc(next_pc),
        .current_warp_id(current_warp_id),
        .done(done)
    );

    genvar i;
    generate
        for (i = 0; i < WARP_SIZE; i = i + 1) begin : threads
            registers #(
                .BLOCK_ID(BLOCK_ID),
                .THREAD_ID(i)
            ) register_instance (
                .clk(clk),
                .reset(reset),
                .block_dim(block_dim),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .rd(rd[i]),
                .rs(rs[i]),
                .rt(rt[i])
            );

            alu alu_instance (
                .clk(clk),
                .reset(reset),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .rs(rs[i]),
                .rt(rt[i]),
                .alu_out(alu_out[i])
            );

            lsu lsu_instance (
                .clk(clk),
                .reset(reset),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .mem_read_valid(data_mem_read_valid),
                .mem_read_address(data_mem_read_address),
                .mem_read_ready(data_mem_read_ready),
                .mem_read_data(data_mem_read_data),
                .mem_write_valid(data_mem_write_valid),
                .mem_write_address(data_mem_write_address),
                .mem_write_data(data_mem_write_data),
                .mem_write_ready(data_mem_write_ready),
                .rs(rs[i]),
                .rt(rt[i]),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            pc pc_instance (
                .clk(clk),
                .reset(reset),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_pc_mux(decoded_pc_mux),
                .nzp_input_data(alu_out[i][2:0]),
                .current_pc(warp_pc[current_warp_id]),
                .next_pc(next_pc[i])
            );

            assign rd[i] = (decoded_reg_input_mux == 2'b00) 
                ? alu_out[i] 
                : (decoded_reg_input_mux == 2'b01) 
                ? lsu_out[i] 
                : (decoded_reg_input_mux == 2'b10) 
                ? decoded_immediate 
                : alu_out[i];
        end
    endgenerate
endmodule

