`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// > Each thread slot in a core owns a private 16-entry register file.
// > Registers R0-R12 are normal read/write registers for kernel code.
// > Registers R13-R15 are special read-only metadata registers:
//   - R13 = %blockIdx   (which block this core is currently executing)
//   - R14 = %blockDim   (threads per block in this hardware configuration)
//   - R15 = %threadIdx  (this thread slot's local index inside the block)
// > Beginner mental model:
//   each generated thread gets its own little bank of registers, so all threads can run
//   the same instruction at once but on different data.
// 新手导读：
// 1. 这个模块是“每个线程私有的一组寄存器”，所以同一个 core 里会实例化很多份。
// 2. `reg [7:0] registers[15:0];` 要分两层看：左边 `[7:0]` 是每个元素的位宽，右边 `[15:0]` 是数组有 16 个元素。
// 3. REQUEST 阶段负责读源操作数，UPDATE 阶段负责把 ALU/LSU/立即数写回目标寄存器。
// 4. R13-R15 被设计成只读特殊寄存器，分别保存 blockIdx、blockDim、threadIdx。
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some registers will be inactive

    // Block metadata currently assigned to this core.
    input reg [7:0] block_id,

    // Shared core state from the scheduler.
    input reg [2:0] core_state,

    // Register addresses extracted by the decoder from the current instruction.
    input reg [3:0] decoded_rd_address,
    input reg [3:0] decoded_rs_address,
    input reg [3:0] decoded_rt_address,

    // Register write-back control from the decoder.
    input reg decoded_reg_write_enable,
    input reg [1:0] decoded_reg_input_mux,
    input reg [DATA_BITS-1:0] decoded_immediate,

    // Candidate write-back values produced by this thread's other execution units.
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,

    // Source operands exposed to the ALU / LSU for the current instruction.
    output reg [7:0] rs,
    output reg [7:0] rt
);
    // Selects which producer writes back into rd during UPDATE.
    // 这里相当于给“寄存器写回来源选择器”定义三个枚举值。
    localparam ARITHMETIC = 2'b00,
        MEMORY = 2'b01,
        CONSTANT = 2'b10;

    // Physical storage array for this one thread's architectural registers.
    // 读法：16 个寄存器槽位，每个槽位 8 bit。
    reg [7:0] registers[15:0];

    always @(posedge clk) begin
        if (reset) begin
            // Clear the currently presented source operands.
            rs <= 0;
            rt <= 0;
            // Initialize all general-purpose registers.
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
            // Initialize the special metadata registers.
            // These are read by kernel code but should never be overwritten by instructions.
            registers[13] <= 8'b0;              // %blockIdx
            registers[14] <= THREADS_PER_BLOCK; // %blockDim
            registers[15] <= THREAD_ID;         // %threadIdx
        end else if (enable) begin 
            // Keep %blockIdx synchronized with the block currently assigned to this core.
            // The original author notes this is a simple-but-inelegant approach because it is
            // rewritten every cycle instead of only when a new block arrives.
            // 这也说明寄存器并不一定只在“写回阶段”更新，某些特殊寄存器可以由控制逻辑持续维护。
            registers[13] <= block_id;
            
            // During REQUEST, snapshot the source operands named by the decoded instruction.
            // Those values will then feed the ALU / LSU in later stages.
            if (core_state == 3'b011) begin 
                // 读寄存器在这里表现成“按地址索引数组”。
                rs <= registers[decoded_rs_address];
                rt <= registers[decoded_rt_address];
            end

            // During UPDATE, commit the chosen result into rd.
            if (core_state == 3'b110) begin 
                // Protect the three metadata registers by only allowing writes to R0-R12.
                if (decoded_reg_write_enable && decoded_rd_address < 13) begin
                    // `decoded_rd_address < 13` 用来保护 R13-R15，不允许普通指令把特殊寄存器覆盖掉。
                    case (decoded_reg_input_mux)
                        ARITHMETIC: begin 
                            // Arithmetic result from this thread's ALU.
                            registers[decoded_rd_address] <= alu_out;
                        end
                        MEMORY: begin 
                            // Load result returned by this thread's LSU.
                            registers[decoded_rd_address] <= lsu_out;
                        end
                        CONSTANT: begin 
                            // Immediate constant embedded directly in the instruction.
                            registers[decoded_rd_address] <= decoded_immediate;
                        end
                    endcase
                end
            end
        end
    end
endmodule
