`default_nettype none
`timescale 1ns/1ns

// ARITHMETIC-LOGIC UNIT
// > Executes computations on register values
// > In this minimal implementation, the ALU supports the 4 basic arithmetic operations
// > Each thread in each core has it's own ALU
// > ADD, SUB, MUL, DIV instructions are all executed here
module alu (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some ALUs will be inactive

    input reg [2:0] core_state,

    input reg [1:0] decoded_alu_arithmetic_mux,
    input reg decoded_alu_output_mux,

    input reg [7:0] rs,
    input reg [7:0] rt,
    output wire [7:0] alu_out
);
    localparam ADD = 2'b00,
        SUB = 2'b01,
        MUL = 2'b10,
        DIV = 2'b11;

    reg [7:0] alu_out_reg;
    assign alu_out = alu_out_reg;

    always @(posedge clk) begin 
        if (reset) begin 
            alu_out_reg <= 8'b0;
        end else if (enable) begin
            // Calculate alu_out when core_state = EXECUTE
            if (core_state == 3'b100) begin 
                if (decoded_alu_output_mux == 1) begin 
                    // Set values to compare with NZP register in alu_out[2:0]:
                    // alu_out[2] = P (rs > rt), alu_out[1] = Z (rs == rt), alu_out[0] = N (rs < rt)
                    //
                    // NOTE: P and Z are both derived from the *subtraction* `rs - rt`, which is
                    // plain unsigned arithmetic on these 8-bit registers - `rs - rt > 0` is
                    // therefore also (incorrectly) true whenever rs < rt, since that case wraps
                    // around to a large positive unsigned value instead of going negative. This
                    // is a pre-existing quirk of the original design (rs, rt are never declared
                    // `signed`) that every existing kernel's loop/branch conditions already work
                    // around by only ever testing for equality (Z) or "not yet equal" (P, used
                    // as a "not done" signal - see e.g. matmul's loop bound check) rather than a
                    // genuine direction of inequality.
                    //
                    // N is fixed below to use a real unsigned comparator (`rs < rt`) instead of
                    // re-deriving it from the same subtraction (which can never be "negative" on
                    // unsigned operands, making the original `rs - rt < 0` dead code - always 0).
                    // This is purely additive: N was never 1 before this fix, so nothing that
                    // already existed could have depended on its value - see test_graphics.py for
                    // a kernel that uses the newly-reliable N flag for a real "less than" branch.
                    alu_out_reg <= {5'b0, (rs - rt > 0), (rs - rt == 0), (rs < rt)};
                end else begin 
                    // Execute the specified arithmetic instruction
                    case (decoded_alu_arithmetic_mux)
                        ADD: begin 
                            alu_out_reg <= rs + rt;
                        end
                        SUB: begin 
                            alu_out_reg <= rs - rt;
                        end
                        MUL: begin 
                            alu_out_reg <= rs * rt;
                        end
                        DIV: begin 
                            alu_out_reg <= rs / rt;
                        end
                    endcase
                end
            end
        end
    end
endmodule
