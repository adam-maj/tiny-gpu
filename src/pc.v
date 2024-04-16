`default_nettype none
`timescale 1ns/1ns

module pc (
    input wire clk,
    input wire reset,

    decoded_instruction_if.consumer decoded_instruction,
    input wire [2:0] nzp_input_data,
    input wire [7:0] pc,
    output wire [7:0] next_pc
);
    reg [2:0] nzp_reg;

    always @(posedge clk) begin
        if (reset) begin
            nzp_reg <= 3'b0;
        end else if (decoded_instruction.nzp_write_enable) begin
            nzp_reg <= nzp_input_data;
        end
    end

    always @(*) begin
        assign next_pc = pc + 1
        if decoded_instruction.pc_mux == 1 begin
            if nzp_reg & decoded_instruction.nzp == 3'b0 begin
                next_pc = decoded_instruction.immediate
            end
        end
    end
endmodule