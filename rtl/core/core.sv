`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// COMPUTE CORE
// ============================================================

module core #(
    parameter int DATA_MEM_ADDR_BITS    = 8,
    parameter int DATA_MEM_DATA_BITS    = 8,
    parameter int PROGRAM_MEM_ADDR_BITS = 8,
    parameter int PROGRAM_MEM_DATA_BITS = 16,
    parameter int THREADS_PER_BLOCK     = 4
)(
    input  logic clk,
    input  logic reset,

    //----------------------------------------------------------
    // Kernel Control
    //----------------------------------------------------------

    input  logic start,
    output logic done,

    //----------------------------------------------------------
    // Block Metadata
    //----------------------------------------------------------

    input  logic [7:0] block_id,

    input logic [$clog2(THREADS_PER_BLOCK+1)-1:0]
                thread_count,

    //----------------------------------------------------------
    // Program Memory
    //----------------------------------------------------------

    output logic program_mem_read_valid,

    output logic [PROGRAM_MEM_ADDR_BITS-1:0]
                 program_mem_read_address,

    input  logic program_mem_read_ready,

    input  logic [PROGRAM_MEM_DATA_BITS-1:0]
                 program_mem_read_data,

    //----------------------------------------------------------
    // Data Memory
    //----------------------------------------------------------

    output logic [THREADS_PER_BLOCK-1:0]
                 data_mem_read_valid,

    output logic [DATA_MEM_ADDR_BITS-1:0]
                 data_mem_read_address
                 [THREADS_PER_BLOCK-1:0],

    input  logic [THREADS_PER_BLOCK-1:0]
                 data_mem_read_ready,

    input  logic [DATA_MEM_DATA_BITS-1:0]
                 data_mem_read_data
                 [THREADS_PER_BLOCK-1:0],

    output logic [THREADS_PER_BLOCK-1:0]
                 data_mem_write_valid,

    output logic [DATA_MEM_ADDR_BITS-1:0]
                 data_mem_write_address
                 [THREADS_PER_BLOCK-1:0],

    output logic [DATA_MEM_DATA_BITS-1:0]
                 data_mem_write_data
                 [THREADS_PER_BLOCK-1:0],

    input  logic [THREADS_PER_BLOCK-1:0]
                 data_mem_write_ready
);

    //----------------------------------------------------------
    // Global Core State
    //----------------------------------------------------------

    core_state_t    core_state;
    fetcher_state_t fetcher_state;
    lsu_state_t     lsu_state [THREADS_PER_BLOCK-1:0];

    //----------------------------------------------------------
    // Instruction Flow
    //----------------------------------------------------------

    logic [PROGRAM_MEM_DATA_BITS-1:0] instruction;

    logic [PROGRAM_MEM_ADDR_BITS-1:0] current_pc;

    logic [PROGRAM_MEM_ADDR_BITS-1:0]
          next_pc [THREADS_PER_BLOCK-1:0];

    //----------------------------------------------------------
    // Thread Resources
    //----------------------------------------------------------

    logic [DATA_MEM_DATA_BITS-1:0]
          rs [THREADS_PER_BLOCK-1:0];

    logic [DATA_MEM_DATA_BITS-1:0]
          rt [THREADS_PER_BLOCK-1:0];

    logic [DATA_MEM_DATA_BITS-1:0]
          alu_out [THREADS_PER_BLOCK-1:0];

    logic [DATA_MEM_DATA_BITS-1:0]
          lsu_out [THREADS_PER_BLOCK-1:0];

    //----------------------------------------------------------
    // Decoder Outputs
    //----------------------------------------------------------

    logic [3:0] decoded_rd_address;
    logic [3:0] decoded_rs_address;
    logic [3:0] decoded_rt_address;

    logic [2:0] decoded_nzp;

    logic [DATA_MEM_DATA_BITS-1:0]
          decoded_immediate;

    logic       decoded_reg_write_enable;
    logic       decoded_mem_read_enable;
    logic       decoded_mem_write_enable;
    logic       decoded_nzp_write_enable;

    logic [1:0] decoded_reg_input_mux;
    logic [1:0] decoded_alu_arithmetic_mux;

    logic       decoded_alu_output_mux;
    logic       decoded_pc_mux;

    logic       decoded_ret;

    //----------------------------------------------------------
    // FETCH
    //----------------------------------------------------------

    fetch #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetch_instance (
        .clk               (clk),
        .reset             (reset),
        .core_state        (core_state),
        .current_pc        (current_pc),

        .mem_read_valid    (program_mem_read_valid),
        .mem_read_address  (program_mem_read_address),
        .mem_read_ready    (program_mem_read_ready),
        .mem_read_data     (program_mem_read_data),

        .fetcher_state     (fetcher_state),
        .instruction       (instruction)
    );

    //----------------------------------------------------------
    // DECODER
    //----------------------------------------------------------

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

    //----------------------------------------------------------
    // SCHEDULER
    //----------------------------------------------------------

    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .PC_WIDTH(PROGRAM_MEM_ADDR_BITS)
    ) scheduler_instance (
        .clk(clk),
        .reset(reset),
        .start(start),

        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_ret(decoded_ret),

        .fetcher_state(fetcher_state),
        .lsu_state(lsu_state),

        .current_pc(current_pc),
        .next_pc(next_pc),

        .core_state(core_state),
        .done(done)
    );

    //----------------------------------------------------------
    // THREAD RESOURCES
    //----------------------------------------------------------

    genvar i;

    generate
        for (i = 0; i < THREADS_PER_BLOCK; i++) begin : g_thread

            alu alu_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),

                .core_state(core_state),

                .decoded_alu_arithmetic_mux(
                    decoded_alu_arithmetic_mux
                ),

                .decoded_alu_output_mux(
                    decoded_alu_output_mux
                ),

                .rs(rs[i]),
                .rt(rt[i]),

                .alu_out(alu_out[i])
            );

            lsu lsu_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),

                .core_state(core_state),

                .decoded_mem_read_enable(
                    decoded_mem_read_enable
                ),

                .decoded_mem_write_enable(
                    decoded_mem_write_enable
                ),

                .rs(rs[i]),
                .rt(rt[i]),

                .mem_read_valid(
                    data_mem_read_valid[i]
                ),

                .mem_read_address(
                    data_mem_read_address[i]
                ),

                .mem_read_ready(
                    data_mem_read_ready[i]
                ),

                .mem_read_data(
                    data_mem_read_data[i]
                ),

                .mem_write_valid(
                    data_mem_write_valid[i]
                ),

                .mem_write_address(
                    data_mem_write_address[i]
                ),

                .mem_write_data(
                    data_mem_write_data[i]
                ),

                .mem_write_ready(
                    data_mem_write_ready[i]
                ),

                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            registers #(
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) register_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),

                .block_id(block_id),

                .core_state(core_state),

                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),

                .decoded_reg_write_enable(
                    decoded_reg_write_enable
                ),

                .decoded_reg_input_mux(
                    decoded_reg_input_mux
                ),

                .decoded_immediate(
                    decoded_immediate
                ),

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
                .enable(i < thread_count),

                .core_state(core_state),

                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),

                .decoded_nzp_write_enable(
                    decoded_nzp_write_enable
                ),

                .decoded_pc_mux(decoded_pc_mux),

                .alu_out(alu_out[i]),

                .current_pc(current_pc),
                .next_pc(next_pc[i])
            );

        end
    endgenerate

endmodule

`default_nettype wire