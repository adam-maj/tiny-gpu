`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Manages the entire control flow of a single compute core processing 1 block
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into the relevant control signals
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs
// 4. WAIT - Wait for all async memory requests to resolve (if applicable)
// 5. EXECUTE - Execute computations on retrieved data from registers / memory
// 6. UPDATE - Update register values (including NZP register) and program counter
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.
// > Technically, different instructions can branch to different PCs, requiring "branch divergence." In
//   this minimal implementation, we assume no branch divergence (naive approach for simplicity)
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,

    // Memory Access State
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Current & Next PC
    output reg [7:0] current_pc,
    input reg [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Execution State
    output reg [2:0] core_state,
    output reg done
);
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
            case (core_state)
                IDLE: begin
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    if (start) begin 
                        // Start by fetching the next instruction for this block based on PC
                        core_state <= FETCH;
                    end
                end
                FETCH: begin 
                    // Move on once fetcher_state = FETCHED
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decode is synchronous so we move on after one cycle
                    core_state <= REQUEST;
                end
                REQUEST: begin 
                    // Request is synchronous so we move on after one cycle
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Wait for all LSUs to finish their request before continuing
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        // Make sure no lsu_state = REQUESTING or WAITING
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    // If no LSU is waiting for a response, move onto the next stage
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // Execute is synchronous so we move on after one cycle
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        // If we reach a RET instruction, this block is done executing
                        done <= 1;
                        core_state <= DONE;
                    end else begin 
                        // TODO: Branch divergence. For now assume all next_pc converge
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];

                        // Update is synchronous so we move on after one cycle
                        core_state <= FETCH;
                    end
                end
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule
