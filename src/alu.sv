`default_nettype none
`timescale 1ns/1ns

// ALU
module alu (
    input wire clk,
    input wire reset,

    input wire [1:0] decoded_alu_arithmetic_mux,
    input wire decoded_alu_output_mux,

    input wire [7:0] rs,
    input wire [7:0] rt,
    output wire [7:0] alu_out
);
    assign alu_out = reset 
        ? 8'b0 
        : (decoded_alu_output_mux == 1 
            ? {5'b0, (rs - rt > 0), (rs - rt == 0), (rs - rt < 0)} 
            : decoded_alu_arithmetic_mux == 2'b00 ? rs + rt :
                decoded_alu_arithmetic_mux == 2'b01 ? rs - rt :
                decoded_alu_arithmetic_mux == 2'b10 ? rs * rt :
                decoded_alu_arithmetic_mux == 2'b11 ? rs / rt : 8'b0);
endmodule
