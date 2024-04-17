`default_nettype none
`timescale 1ns/1ns

module registers #(
    parameter BLOCK_ID = 0,
    parameter THREAD_ID = 0
) (
    input wire clk,
    input wire reset,
    input wire [7:0] block_dim,

    input wire [3:0] decoded_rd_address,
    input wire [3:0] decoded_rs_address,
    input wire [3:0] decoded_rt_address,
    input wire decoded_reg_write_enable,

    input wire [7:0] rd,
    output wire [7:0] rs,
    output wire [7:0] rt
);
    reg [7:0] registers[0:15];

    assign rs = registers[decoded_rs_address];
    assign rt = registers[decoded_rt_address];

    always @(posedge clk) begin
        if (reset) begin
            // Initialize all free registers
            registers[0] <= 8'b0;
            registers[1] <= 8'b0;
            registers[2] <= 8'b0;
            registers[3] <= 8'b0;
            registers[4] <= 8'b0;
            registers[5] <= 8'b0;
            registers[6] <= 8'b0;
            registers[7] <= 8'b0;
            registers[8] <= 8'b0;
            registers[9] <= 8'b0;
            registers[10] <= 8'b0;
            registers[11] <= 8'b0;
            registers[12] <= 8'b0;
            // Initialize read-only registers
            registers[13] <= BLOCK_ID;
            registers[14] <= block_dim;
            registers[15] <= THREAD_ID;
        end else begin 
            if (decoded_reg_write_enable && decoded_rd_address < 13) begin
                // Only allow writing to R0 - R12
                registers[decoded_rd_address] <= rd;
            end

        if (block_dim != registers[14]) begin
            registers[14] <= block_dim;
        end
        end
    end
endmodule