`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Drives the per-instruction stage machine for one core processing one block.
// > All active threads inside that core advance through the same high-level stages together.
// > Stage sequence used by this simple design:
//   1. FETCH   - request instruction from program memory
//   2. DECODE  - turn instruction bits into control signals
//   3. REQUEST - read source registers / launch LSU requests
//   4. WAIT    - stall until any memory operations complete
//   5. EXECUTE - compute ALU results and tentative next PCs
//   6. UPDATE  - write registers/NZP and commit next PC
// > Important simplification: the scheduler assumes all active threads reconverge to one PC.
//   Real GPUs must handle branch divergence much more carefully.
// 新手导读：
// 1. 这个模块是一个“核心级大状态机”，决定一个 core 当前在取指、译码、访存还是回写。
// 2. 它不是线程调度器意义上的复杂 GPU warp scheduler，而是这个教学工程里的每指令节拍控制器。
// 3. 其他模块大多会看 `core_state`，只在指定阶段做自己的工作，所以你可以把它当成全局节拍器。
// 4. `next_pc` 是一个数组，表示每个线程 lane 各自算出来的下一条 PC；这里最后只选一个代表值。
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // A few decoded instruction properties the scheduler cares about.
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,

    // Progress signals from the fetcher and per-thread LSUs.
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // The scheduler holds the converged current PC for the core and later chooses one next PC.
    output reg [7:0] current_pc,
    input reg [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Shared execution stage broadcast to the rest of the core.
    output reg [2:0] core_state,
    output reg done
);
    // Core-wide stage encodings.
    // 这些状态名帮助你把整个 core 的执行流程按时序串起来看。
    localparam IDLE = 3'b000, // Waiting to start
        FETCH = 3'b001,       // Fetch instructions from program memory
        DECODE = 3'b010,      // Decode instructions into control signals
        REQUEST = 3'b011,     // Request data from registers or memory
        WAIT = 3'b100,        // Wait for response from memory if necessary
        EXECUTE = 3'b101,     // Execute ALU and PC calculations
        UPDATE = 3'b110,      // Update registers, NZP, and PC
        DONE = 3'b111;        // Done executing this block
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
        end else begin 
            // 典型有限状态机主干：当前状态不同，下一拍转移规则也不同。
            case (core_state)
                IDLE: begin
                    // Reset entry point before a block begins.
                    if (start) begin 
                        // A new block starts at PC 0, so the first action is instruction fetch.
                        core_state <= FETCH;
                    end
                end
                FETCH: begin 
                    // Wait until the fetcher has latched the instruction.
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decoder updates its outputs on this cycle's clock edge.
                    core_state <= REQUEST;
                end
                REQUEST: begin 
                    // Register operands are sampled and any LSU operations are launched here.
                    core_state <= WAIT;
                end
                WAIT: begin
                    // For non-memory instructions, the LSUs stay idle and this stage exits quickly.
                    // For loads/stores, wait until every active LSU has finished.
                    // 这里在 always 块内部声明局部变量，是 SystemVerilog 允许的写法。
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        // REQUESTING or WAITING means this thread still has an in-flight memory op.
                        // `for (...)` 在这里是“描述硬件中的重复检查逻辑”，不是软件里那种耗时循环概念。
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    // Once all memory activity is settled, arithmetic / branch logic may proceed.
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // ALUs and PCs compute their outputs during this stage.
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        // RET ends execution for the whole block in this simplified SIMD model.
                        done <= 1;
                        core_state <= DONE;
                    end else begin 
                        // Major simplification: just trust that all active threads computed the same
                        // next PC, and pick one representative value.
                        // 这里直接取 `next_pc[THREADS_PER_BLOCK-1]`，前提是所有活跃线程已经重新收敛到同一个控制流。
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];

                        // Begin the next instruction.
                        core_state <= FETCH;
                    end
                end
                DONE: begin 
                    // Terminal state for this block until the dispatcher resets the core.
                end
            endcase
        end
    end
endmodule
