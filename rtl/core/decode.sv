`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// INSTRUCTION DECODER
//
// Decodes instructions into the control signals required by
// the execution units.
//
// Supported ISA (Adam Maj Tiny GPU):
//
// NOP
// BRnzp
// CMP
// ADD
// SUB
// MUL
// DIV
// LDR
// STR
// CONST
// RET
//
// Future Evolution:
// - ISA extensions
// - SIMD instructions
// - Graphics operations
// - Synchronization primitives
// ============================================================

module decoder (

    input  logic clk,
    input  logic reset,

    input  core_state_t core_state,
    input  logic [15:0] instruction,

    //----------------------------------------------------------
    // Instruction Fields
    //----------------------------------------------------------

    output logic [3:0] decoded_rd_address,
    output logic [3:0] decoded_rs_address,
    output logic [3:0] decoded_rt_address,

    output logic [2:0] decoded_nzp,
    output logic [7:0] decoded_immediate,

    //----------------------------------------------------------
    // Control Signals
    //----------------------------------------------------------

    output logic decoded_reg_write_enable,
    output logic decoded_mem_read_enable,
    output logic decoded_mem_write_enable,
    output logic decoded_nzp_write_enable,

    output logic [1:0] decoded_reg_input_mux,
    output logic [1:0] decoded_alu_arithmetic_mux,

    output logic decoded_alu_output_mux,
    output logic decoded_pc_mux,

    //----------------------------------------------------------
    // Thread Completion
    //----------------------------------------------------------

    output logic decoded_ret
);

    //----------------------------------------------------------
    // ISA Opcodes
    //----------------------------------------------------------

    typedef enum logic [3:0] {

        OP_NOP   = 4'b0000,
        OP_BRNZP = 4'b0001,
        OP_CMP   = 4'b0010,
        OP_ADD   = 4'b0011,
        OP_SUB   = 4'b0100,
        OP_MUL   = 4'b0101,
        OP_DIV   = 4'b0110,
        OP_LDR   = 4'b0111,
        OP_STR   = 4'b1000,
        OP_CONST = 4'b1001,
        OP_RET   = 4'b1111

    } opcode_t;

    //----------------------------------------------------------
    // Decode Logic
    //----------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            decoded_rd_address         <= '0;
            decoded_rs_address         <= '0;
            decoded_rt_address         <= '0;

            decoded_immediate          <= '0;
            decoded_nzp                <= '0;

            decoded_reg_write_enable   <= 1'b0;
            decoded_mem_read_enable    <= 1'b0;
            decoded_mem_write_enable   <= 1'b0;
            decoded_nzp_write_enable   <= 1'b0;

            decoded_reg_input_mux      <= '0;
            decoded_alu_arithmetic_mux <= '0;

            decoded_alu_output_mux     <= 1'b0;
            decoded_pc_mux             <= 1'b0;

            decoded_ret                <= 1'b0;

        end
        else begin

            if (core_state == CORE_DECODE) begin

                //--------------------------------------------------
                // Instruction Fields
                //--------------------------------------------------

                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];

                decoded_immediate  <= instruction[7:0];
                decoded_nzp        <= instruction[11:9];

                //--------------------------------------------------
                // Default Controls
                //--------------------------------------------------

                decoded_reg_write_enable   <= 1'b0;
                decoded_mem_read_enable    <= 1'b0;
                decoded_mem_write_enable   <= 1'b0;
                decoded_nzp_write_enable   <= 1'b0;

                decoded_reg_input_mux      <= 2'b00;
                decoded_alu_arithmetic_mux <= 2'b00;

                decoded_alu_output_mux     <= 1'b0;
                decoded_pc_mux             <= 1'b0;

                decoded_ret                <= 1'b0;

                //--------------------------------------------------
                // Opcode Decode
                //--------------------------------------------------

                case (instruction[15:12])

                    OP_NOP: begin
                        // no-op
                    end

                    OP_BRNZP: begin
                        decoded_pc_mux <= 1'b1;
                    end

                    OP_CMP: begin
                        decoded_alu_output_mux   <= 1'b1;
                        decoded_nzp_write_enable <= 1'b1;
                    end

                    OP_ADD: begin
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_mux      <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b00;
                    end

                    OP_SUB: begin
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_mux      <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b01;
                    end

                    OP_MUL: begin
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_mux      <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b10;
                    end

                    OP_DIV: begin
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_mux      <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b11;
                    end

                    OP_LDR: begin
                        decoded_reg_write_enable <= 1'b1;
                        decoded_reg_input_mux    <= 2'b01;
                        decoded_mem_read_enable  <= 1'b1;
                    end

                    OP_STR: begin
                        decoded_mem_write_enable <= 1'b1;
                    end

                    OP_CONST: begin
                        decoded_reg_write_enable <= 1'b1;
                        decoded_reg_input_mux    <= 2'b10;
                    end

                    OP_RET: begin
                        decoded_ret <= 1'b1;
                    end

                    default: begin
                        // Reserved / Illegal Opcode
                    end

                endcase

            end

        end

    end

endmodule

`default_nettype wire