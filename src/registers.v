`default_nettype none
`timescale 1ns/1ns

module registers #(
    parameter BLOCK_ID,
    parameter THREAD_ID,
) (
    input wire clk,
    input wire reset,
    input wire [7:0] block_dim,

    input wire [7:0] rd,
    output wire [7:0] rs,
    output wire [7:0] rt,

    decoded_instruction_if.consumer decoded_instruction,
);
    reg [7:0] registers[0:15];

    assign rs = registers[decoded_instruction.rs_address];
    assign rt = registers[decoded_instruction.rt_address];

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
            if (decoded_instruction.reg_write_enable && rd_address < 13) begin
                // Only allow writing to R0 - R12
                registers[decoded_instruction.rd_address] <= rs;
            end

            if (block_dim != registers[14]) begin 
                register[14] <= block_dim;
            end
        end
    end
endmodule