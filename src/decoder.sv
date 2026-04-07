`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Converts one 16-bit instruction into the control signals that drive the whole core.
// > Each core has one shared decoder because all active threads in that core execute the
//   same instruction together.
// > Beginner mental model:
//   the decoder is the "meaning extractor" for the raw instruction bits. It does not
//   perform the work itself; it tells the other units what kind of work to do next.
// 新手导读：
// 1. 译码器的核心工作是“看 instruction 的不同 bit 段，然后产出控制信号”。
// 2. `instruction[15:12]` 这种写法表示取位切片；这里高 4 bit 被当成 opcode。
// 3. 同一条 16 bit 指令，不同模块会复用其中某些字段，例如 rd/rs/rt/immediate/nzp。
// 4. 这个模块在 DECODE 阶段才更新，因此其他模块默认在后续阶段消费这些控制信号。
// 5. 先把所有控制信号清零、再按 opcode 拉高需要的信号，是硬件里很常见的防“脏状态残留”写法。
module decoder (
    input wire clk,
    input wire reset,

    // Decoder only acts during the DECODE stage.
    input reg [2:0] core_state,
    input reg [15:0] instruction,
    
    // Raw fields pulled directly out of the instruction encoding.
    output reg [3:0] decoded_rd_address,
    output reg [3:0] decoded_rs_address,
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control signals consumed by register file, ALU, LSU, and PC logic.
    output reg decoded_reg_write_enable,           // Enable writing to a register
    output reg decoded_mem_read_enable,            // Enable reading from memory
    output reg decoded_mem_write_enable,           // Enable writing to memory
    output reg decoded_nzp_write_enable,           // Enable writing to NZP register
    output reg [1:0] decoded_reg_input_mux,        // Select input to register
    output reg [1:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output reg decoded_alu_output_mux,             // Select operation in ALU
    output reg decoded_pc_mux,                     // Select source of next PC

    // Return (finished executing thread)
    output reg decoded_ret
);
    // Opcode table. instruction[15:12] selects one of these operations.
    // 这些名字是给 opcode 编码取别名，方便后面的 case 语句阅读。
    localparam NOP = 4'b0000,
        BRnzp = 4'b0001,
        CMP = 4'b0010,
        ADD = 4'b0011,
        SUB = 4'b0100,
        MUL = 4'b0101,
        DIV = 4'b0110,
        LDR = 4'b0111,
        STR = 4'b1000,
        CONST = 4'b1001,
        RET = 4'b1111;

    always @(posedge clk) begin 
        if (reset) begin 
            // Reset clears all remembered instruction fields and control outputs.
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;
            decoded_ret <= 0;
        end else begin 
            // Decode exactly once per instruction, during the core's DECODE stage.
            if (core_state == 3'b010) begin 
                // Split the instruction into its reusable fields.
                // Different instruction formats overlap these bit positions, so the same raw
                // slices are later interpreted differently by different instructions.
                // `decoded_rd_address <= instruction[11:8];` 这种写法就是“把位段直接拆出来”。
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate <= instruction[7:0];
                decoded_nzp <= instruction[11:9];

                // Important pattern: first clear every control signal, then only assert the ones
                // needed by this opcode. This avoids accidentally carrying old control values
                // forward from the previous instruction.
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_pc_mux <= 0;
                decoded_ret <= 0;

                // Raise the specific controls required by the chosen opcode.
                // 这里的 `case` 是译码器最核心的部分：opcode 不同，整个数据通路的控制方式就不同。
                case (instruction[15:12])
                    NOP: begin 
                        // NOP intentionally leaves every control signal deasserted.
                    end
                    BRnzp: begin 
                        // Tell the PC unit to use branch logic instead of plain PC+1.
                        decoded_pc_mux <= 1;
                    end
                    CMP: begin 
                        // CMP uses the ALU comparison path and writes the result into NZP,
                        // not into the general-purpose register file.
                        decoded_alu_output_mux <= 1;
                        decoded_nzp_write_enable <= 1;
                    end
                    ADD: begin 
                        // Write back arithmetic result selected from the ALU ADD sub-op.
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b00;
                    end
                    SUB: begin 
                        // Same datapath as ADD, but different ALU sub-op.
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b01;
                    end
                    MUL: begin 
                        // Same arithmetic datapath, using multiply mode.
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b10;
                    end
                    DIV: begin 
                        // Same arithmetic datapath, using divide mode.
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b11;
                    end
                    LDR: begin 
                        // LDR both requests a memory read and later writes the returned value
                        // into rd through the MEMORY register-input mux path.
                        // `decoded_reg_input_mux <= 2'b01` 的意思是让寄存器写回来源选到 LSU 输出。
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b01;
                        decoded_mem_read_enable <= 1;
                    end
                    STR: begin 
                        // STR only triggers a memory write. No register write-back occurs.
                        decoded_mem_write_enable <= 1;
                    end
                    CONST: begin 
                        // CONST writes the immediate byte directly into rd.
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b10;
                    end
                    RET: begin 
                        // RET is consumed by the scheduler to mark block completion.
                        decoded_ret <= 1;
                    end
                endcase
            end
        end
    end
endmodule
