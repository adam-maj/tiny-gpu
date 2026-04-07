`default_nettype none
`timescale 1ns/1ns

// ARITHMETIC-LOGIC UNIT
// > Executes computations on register values for ONE thread slot inside ONE core.
// > In this minimal implementation, the ALU supports the 4 basic arithmetic operations
//   plus the compare path used by the CMP instruction.
// > Important mental model for beginners:
//   - This module is synchronous: it updates its output on the clock edge.
//   - It only does useful work when the scheduler has moved the core into EXECUTE.
//   - Every enabled thread has its own private ALU instance.
// 新手导读：
// 1. `module alu (...)` 表示定义一个独立硬件模块，圆括号里列的是它的输入输出端口。
// 2. `input wire` / `output wire` 常用于“连线型”信号；`reg` 常用于 always 块里被时序逻辑保存的信号。
// 3. `always @(posedge clk)` 表示“每个时钟上升沿执行一次下面的时序逻辑”，这是最常见的寄存器写法。
// 4. `<=` 是非阻塞赋值，适合时序电路；可以把它理解成“本拍决定，拍沿统一更新”。
// 5. 这个 ALU 不是组合逻辑直出，而是把结果先存进 `alu_out_reg`，所以输出会晚一个时钟边沿可见。
module alu (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has fewer active threads than capacity, some ALUs stay idle.

    // Shared core stage. The ALU only computes during the EXECUTE stage.
    input reg [2:0] core_state,

    // Decoder control signals:
    // - arithmetic_mux selects ADD/SUB/MUL/DIV
    // - output_mux selects arithmetic result vs comparison result
    input reg [1:0] decoded_alu_arithmetic_mux,
    input reg decoded_alu_output_mux,

    // Source operands read from this thread's register file.
    input reg [7:0] rs,
    input reg [7:0] rt,

    // Final ALU result visible to other units (register file / PC unit).
    output wire [7:0] alu_out
);
    // Small local encoding table for the arithmetic sub-operations.
    // `localparam` 是“只在本模块内部可见的常量”，适合给状态码、操作码取名字。
    localparam ADD = 2'b00,
        SUB = 2'b01,
        MUL = 2'b10,
        DIV = 2'b11;

    // Registered output: this ALU writes its result on the rising edge of clk.
    reg [7:0] alu_out_reg;
    // `assign` 表示连续赋值，相当于把输出线永久连接到内部寄存器上。
    assign alu_out = alu_out_reg;

    always @(posedge clk) begin 
        if (reset) begin 
            // Reset clears the stored ALU output.
            alu_out_reg <= 8'b0;
        end else if (enable) begin
            // Only perform ALU work during the EXECUTE stage of the core pipeline.
            if (core_state == 3'b101) begin 
                if (decoded_alu_output_mux == 1) begin 
                    // CMP uses the ALU comparison path instead of normal arithmetic.
                    // The low 3 bits are packed as condition flags for the PC/NZP logic:
                    //   alu_out[2] = (rs > rt)
                    //   alu_out[1] = (rs == rt)
                    //   alu_out[0] = (rs < rt)
                    // The upper 5 bits are padded with zeros because alu_out is 8 bits wide.
                    // `{a, b, c}` 是拼接运算符，表示把多个 bit/向量按顺序拼成一个更宽的向量。
                    alu_out_reg <= {5'b0, (rs - rt > 0), (rs - rt == 0), (rs - rt < 0)};
                end else begin 
                    // Normal arithmetic path selected by the decoder.
                    // `case (...)` 很像软件里的 switch，用来根据选择信号挑一种子操作。
                    case (decoded_alu_arithmetic_mux)
                        ADD: begin 
                            // R[rd] = rs + rt
                            alu_out_reg <= rs + rt;
                        end
                        SUB: begin 
                            // R[rd] = rs - rt
                            alu_out_reg <= rs - rt;
                        end
                        MUL: begin 
                            // R[rd] = rs * rt
                            alu_out_reg <= rs * rt;
                        end
                        DIV: begin 
                            // R[rd] = rs / rt
                            // This toy design assumes the program avoids divide-by-zero.
                            alu_out_reg <= rs / rt;
                        end
                    endcase
                end
            end
        end
    end
endmodule
