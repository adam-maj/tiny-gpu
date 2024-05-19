`default_nettype none
`timescale 1ns/1ns

// ARITHMETIC-LOGIC UNIT
// > Executes computations on register values
// > In this minimal implementation, the ALU supports the 4 basic arithmetic operations
// > Each thread in each core has it's own ALU
// > ADD, SUB, MUL, DIV instructions are all executed here
//本模块定义了ALU的行为，包括对寄存器值的计算，支持4种基本算术运算，每个核心的每个线程都有自己的ALU，ADD，SUB，MUL，DIV指令都在这里执行
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
    localparam ADD = 2'b00, //定义了4种基本算术运算对应的编码，且采用了本地参数
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
            if (core_state == 3'b101) begin 
                if (decoded_alu_output_mux == 1) begin 
                    // Set values to compare with NZP register in alu_out[2:0]
                    alu_out_reg <= {5'b0, (rs - rt > 0), (rs - rt == 0), (rs - rt < 0)}; //alu_out的低3位分别存储了NZP寄存器的值
                end else begin 
                    // Execute the specified arithmetic instruction //执行指定的算术指令
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
