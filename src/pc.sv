`default_nettype none
`timescale 1ns/1ns

module pc (
    input wire clk,
    input wire reset,

    input wire [2:0] decoded_nzp,
    input wire [7:0] decoded_immediate,
    input wire decoded_nzp_write_enable,
    input wire decoded_pc_mux, 

    input wire [2:0] nzp_input_data,
    input wire [7:0] current_pc,
    output reg [7:0] next_pc
);
    reg [2:0] nzp_reg;

    always @(posedge clk) begin
        if (reset) begin
            nzp_reg <= 3'b0;
        end else begin
            if (decoded_pc_mux == 1 && ((nzp_reg & decoded_nzp) != 3'b0)) begin 
                next_pc <= decoded_immediate;
            end else begin 
                next_pc <= current_pc + 1;
            end

            if (decoded_nzp_write_enable) begin
                nzp_reg <= nzp_input_data;
            end
        end
    end

endmodule
