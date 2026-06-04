`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// REGISTER FILE
//
// Per-thread architectural register file.
//
// Register Map
// ------------
// R0-R12 : General Purpose Registers
// R13    : %blockIdx
// R14    : %blockDim
// R15    : %threadIdx
//
// Future Evolution:
// - Scoreboarding
// - Register Renaming
// - SIMD Register Banks
// ============================================================

module registers #(
    parameter int THREADS_PER_BLOCK = 4,
    parameter int THREAD_ID         = 0,
    parameter int DATA_BITS         = 8
)(
    input  logic clk,
    input  logic reset,
    input  logic enable,

    // Kernel Execution
    input  logic [7:0] block_id,

    // Execution State
    input  core_state_t core_state,

    // Decode Outputs
    input  logic [3:0] decoded_rd_address,
    input  logic [3:0] decoded_rs_address,
    input  logic [3:0] decoded_rt_address,

    // Control Signals
    input  logic decoded_reg_write_enable,
    input  logic [1:0] decoded_reg_input_mux,
    input  logic [DATA_BITS-1:0] decoded_immediate,

    // Execution Results
    input  logic [DATA_BITS-1:0] alu_out,
    input  logic [DATA_BITS-1:0] lsu_out,

    // Register Outputs
    output logic [DATA_BITS-1:0] rs,
    output logic [DATA_BITS-1:0] rt
);

    typedef enum logic [1:0] {
        REG_INPUT_ARITHMETIC = 2'b00,
        REG_INPUT_MEMORY     = 2'b01,
        REG_INPUT_CONSTANT   = 2'b10
    } reg_input_mux_t;

    logic [DATA_BITS-1:0] register_file [15:0];

    integer i;

    always_ff @(posedge clk) begin

        if (reset) begin

            rs <= '0;
            rt <= '0;

            //--------------------------------------------------
            // General Purpose Registers
            //--------------------------------------------------

            for (i = 0; i < 13; i++) begin
                register_file[i] <= '0;
            end

            //--------------------------------------------------
            // Read-Only Registers
            //--------------------------------------------------

            register_file[13] <= '0;                // %blockIdx
            register_file[14] <= DATA_BITS'(THREADS_PER_BLOCK);
            register_file[15] <= DATA_BITS'(THREAD_ID);

        end
        else if (enable) begin

            //--------------------------------------------------
            // Dynamic Special Registers
            //--------------------------------------------------

            register_file[13] <= block_id;

            //--------------------------------------------------
            // Operand Read
            //--------------------------------------------------

            if (core_state == CORE_REQUEST) begin

                rs <= register_file[decoded_rs_address];
                rt <= register_file[decoded_rt_address];

            end

            //--------------------------------------------------
            // Register Writeback
            //--------------------------------------------------

            if (core_state == CORE_UPDATE) begin

                if (decoded_reg_write_enable &&
                    (decoded_rd_address < 4'd13)) begin

                    case (decoded_reg_input_mux)

                        REG_INPUT_ARITHMETIC: begin
                            register_file[decoded_rd_address]
                                <= alu_out;
                        end

                        REG_INPUT_MEMORY: begin
                            register_file[decoded_rd_address]
                                <= lsu_out;
                        end

                        REG_INPUT_CONSTANT: begin
                            register_file[decoded_rd_address]
                                <= decoded_immediate;
                        end

                        default: begin
                            // no-op
                        end

                    endcase

                end

            end

        end

    end

endmodule

`default_nettype wire