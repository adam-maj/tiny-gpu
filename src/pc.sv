`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// > Calculates the next PC for each thread slot.
// > This design gives each thread its own next_pc calculation and NZP register,
//   but the scheduler later assumes all threads converge back to the same PC.
// > The NZP register stores the result of the previous CMP instruction and is used
//   by BRnzp to decide whether to branch.
// 新手导读：
// 1. `#(...)` 是参数列表，表示这个模块在实例化时可以被配置成不同位宽。
// 2. 这个模块做两件事：一是在 EXECUTE 阶段算 next_pc，二是在 UPDATE 阶段更新 NZP 条件寄存器。
// 3. `decoded_pc_mux` 可以把它理解为“下一条 PC 走顺序执行还是走分支跳转”的选择开关。
// 4. `decoded_nzp` 是指令里写的分支条件掩码，`nzp` 是上一次 CMP 实际产生的条件标志。
// 5. `&` 是按位与，不是逻辑与；这里用它判断“指令要求的条件位”和“当前已保存的条件位”是否有重合。
module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some PCs will be inactive

    // Shared core execution stage.
    input reg [2:0] core_state,

    // Decoded branch / CMP-related control signals.
    input reg [2:0] decoded_nzp,
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    input reg decoded_nzp_write_enable,
    input reg decoded_pc_mux, 

    // ALU output. During CMP, alu_out[2:0] carries the comparison condition bits.
    input reg [DATA_MEM_DATA_BITS-1:0] alu_out,

    // Current converged PC from the scheduler, and this thread's locally computed next PC.
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);

    // Internal NZP register for this thread.
    // Bit usage in this design follows the ALU's comparison packing.
    // 每个线程 lane 都有自己独立的 nzp，因此不同线程理论上可以保留不同的分支条件状态。
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            // Reset clears both branch condition state and next_pc.
            nzp <= 3'b0;
            next_pc <= 0;
        end else if (enable) begin
            // Compute next_pc during the EXECUTE stage.
            if (core_state == 3'b101) begin 
                if (decoded_pc_mux == 1) begin 
                    // BRnzp is selected. We branch if any requested NZP condition bit matches
                    // the stored NZP state from a previous CMP.
                    // `!= 3'b0` 的意思是“按位与结果不是全 0”，也就是至少有一个条件位命中。
                    if (((nzp & decoded_nzp) != 3'b0)) begin 
                        // Take the branch by jumping to the immediate program address.
                        next_pc <= decoded_immediate;
                    end else begin 
                        // Branch not taken -> continue to the next instruction.
                        next_pc <= current_pc + 1;
                    end
                end else begin 
                    // Non-branch instructions advance sequentially.
                    next_pc <= current_pc + 1;
                end
            end   

            // Update the NZP register during UPDATE, after ALU comparison results are available.
            if (core_state == 3'b110) begin 
                // Only CMP-like instructions request an NZP update.
                if (decoded_nzp_write_enable) begin
                    // Copy the ALU's low 3 comparison bits into the NZP register.
                    // 这里逐位写入而不是整段赋值，只是为了把每一位语义写得更直观。
                    nzp[2] <= alu_out[2];
                    nzp[1] <= alu_out[1];
                    nzp[0] <= alu_out[0];
                end
            end      
        end
    end

endmodule
