`default_nettype none
`timescale 1ns/1ns

module alu (
    input wire clk,
    input wire reset,

    decoded_instruction_if.consumer decoded_instruction,

    input wire [7:0] rs,
    input wire [7:0] rt,
    output wire [7:0] alu_out
);
    wire [7:0] arith_out;
    wire [2:0] cmp_out;

    always @(posedge clk) begin
        if (reset) begin
            arith_out <= 8'b0;
            cmp_out <= 3'b0;
            alu_out <= 8'b0;
        end else begin
            case (decoded_instruction.alu_arithmetic_mux)
                2'b00: arith_out = rs + rt;
                2'b01: arith_out = rs - rt;
                2'b10: arith_out = rs * rt;
                2'b11: arith_out = rs / rt;
                default: arith_out = 8'b0;
            endcase

            cmp_out[1] = (rs - rt > 0);  // N
            cmp_out[2] = (rs - rt == 0); // Z
            cmp_out[0] = (rs - rt < 0);  // P

            case (decoded_instruction.alu_output_mux)
                1'b0: alu_out = arith_out;
                1'b1: alu_out = {5'b0, cmp_out};
            endcase
        end
    end


endmodule