`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// ARITHMETIC LOGIC UNIT
//
// Executes arithmetic and comparison operations.
//
// Current Operations:
//   ADD
//   SUB
//   MUL
//   DIV
//   CMP (NZP)
//
// Future Evolution:
//   Bitwise Logic
//   Shift Operations
//   SIMD Arithmetic
//   Floating Point Support
// ============================================================

module alu (

    input  logic clk,
    input  logic reset,
    input  logic enable,

    // Execution State
    input  core_state_t core_state,

    // Decode Control
    input  logic [1:0] decoded_alu_arithmetic_mux,
    input  logic       decoded_alu_output_mux,

    // Operands
    input  logic [7:0] rs,
    input  logic [7:0] rt,

    // Result
    output logic [7:0] alu_out
);

    typedef enum logic [1:0] {
        ALU_ADD = 2'b00,
        ALU_SUB = 2'b01,
        ALU_MUL = 2'b10,
        ALU_DIV = 2'b11
    } alu_op_t;

    always_ff @(posedge clk) begin

        if (reset) begin

            alu_out <= '0;

        end
        else if (enable) begin

            if (core_state == CORE_EXECUTE) begin

                //--------------------------------------------------
                // CMP
                //--------------------------------------------------

                if (decoded_alu_output_mux) begin

                    alu_out <= {
                        5'b0,
                        (rs > rt),
                        (rs == rt),
                        (rs < rt)
                    };

                end

                //--------------------------------------------------
                // Arithmetic
                //--------------------------------------------------

                else begin

                    case (decoded_alu_arithmetic_mux)

                        ALU_ADD:
                            alu_out <= rs + rt;

                        ALU_SUB:
                            alu_out <= rs - rt;

                        ALU_MUL:
                            alu_out <= rs * rt;

                        ALU_DIV:
                            alu_out <= (rt == 0)
                                ? 8'h00
                                : rs / rt;

                        default:
                            alu_out <= '0;

                    endcase

                end
            end
        end
    end

endmodule

`default_nettype wire

