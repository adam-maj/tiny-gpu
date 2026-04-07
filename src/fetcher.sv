`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from program memory.
// > Each core has one fetcher shared by all threads in that core.
// > Beginner mental model:
//   - The scheduler says "go fetch" by moving the core into FETCH state.
//   - The fetcher raises a read request for current_pc.
//   - When memory returns the instruction, the fetcher stores it locally.
// 新手导读：
// 1. 这个模块就是“取指单元”，负责把 current_pc 送到程序存储器，然后把返回的指令缓存起来。
// 2. 它内部也有一个小状态机 `fetcher_state`，所以不是单纯一拍就完成，而是会经历请求中、已取回等状态。
// 3. `mem_read_valid` / `mem_read_ready` 是典型握手机制：valid 表示我发请求，ready 表示对方已经响应。
// 4. `instruction` 是寄存后的输出，所以 decoder 读取的是“已经稳定保存的一条指令”。
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    
    // Shared core execution state and the current converged PC for this core.
    input reg [2:0] core_state,
    input reg [7:0] current_pc,

    // Program memory handshake interface.
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher outputs back into the core.
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction,
);
    // Small fetcher-local FSM:
    // IDLE     -> waiting for the scheduler to enter FETCH
    // FETCHING -> request has been sent, waiting for memory response
    // FETCHED  -> instruction captured, waiting for core to move on to DECODE
    // 用 `localparam` 给状态编码命名，比直接写 3'b001、3'b010 更容易读懂状态机。
    localparam IDLE = 3'b000, 
        FETCHING = 3'b001, 
        FETCHED = 3'b010;
    
    always @(posedge clk) begin
        if (reset) begin
            // Reset puts the fetcher back into its idle state and clears outputs.
            fetcher_state <= IDLE;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            // `case (fetcher_state)` 表示根据当前状态执行不同分支，这是写有限状态机最常见的写法。
            case (fetcher_state)
                IDLE: begin
                    // Start a fetch only when the core scheduler enters FETCH.
                    // We sample current_pc here and use it as the program memory address.
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        mem_read_valid <= 1;
                        mem_read_address <= current_pc;
                    end
                end
                FETCHING: begin
                    // Wait until program memory acknowledges the request and returns data.
                    if (mem_read_ready) begin
                        fetcher_state <= FETCHED;
                        // Latch the fetched instruction so the decoder can read it next.
                        // 这一步很关键：即使后面 program memory 总线变了，decoder 看到的仍是这拍锁存下来的值。
                        instruction <= mem_read_data;
                        mem_read_valid <= 0;
                    end
                end
                FETCHED: begin
                    // Once the core has moved into DECODE, this fetch cycle is complete.
                    // The fetcher can safely go back to IDLE and wait for the next PC.
                    if (core_state == 3'b010) begin 
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
