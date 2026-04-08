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
// > Supports branch divergence: when threads take different branches, the scheduler
//   tracks active threads and manages reconvergence using a divergence stack.
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter DIVERGENCE_STACK_DEPTH = 4  // Max nesting depth for divergent branches
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Thread count for this block
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Control Signals
    input decoded_mem_read_enable,
    input decoded_mem_write_enable,
    input decoded_ret,
    input decoded_pc_mux,  // Branch instruction indicator
    input [7:0] decoded_immediate,  // Branch target

    // Memory Access State
    input [2:0] fetcher_state,
    input [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Branch taken from each thread's PC
    input [THREADS_PER_BLOCK-1:0] branch_taken,

    // Current & Next PC
    output reg [7:0] current_pc,
    input [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Active thread mask (for divergence support)
    output reg [THREADS_PER_BLOCK-1:0] active_mask,

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

    // ========================================================================
    // Divergence Stack for Branch Divergence Support
    // ========================================================================
    // Stack entry: {pending_mask, reconverge_pc}
    reg [THREADS_PER_BLOCK-1:0] stack_pending_mask [DIVERGENCE_STACK_DEPTH-1:0];
    reg [7:0] stack_reconverge_pc [DIVERGENCE_STACK_DEPTH-1:0];
    reg [$clog2(DIVERGENCE_STACK_DEPTH):0] stack_ptr;

    // Thread enable mask based on block's thread count
    wire [THREADS_PER_BLOCK-1:0] thread_enable;
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : gen_enable
            assign thread_enable[i] = (i < thread_count);
        end
    endgenerate

    // Divergence detection
    wire [THREADS_PER_BLOCK-1:0] will_take = branch_taken & active_mask;
    wire [THREADS_PER_BLOCK-1:0] will_not_take = (~branch_taken) & active_mask;
    wire has_divergence = (|will_take) && (|will_not_take);

    // Reconvergence detection
    wire stack_empty = (stack_ptr == 0);
    wire at_reconverge = !stack_empty && 
                         (current_pc == stack_reconverge_pc[stack_ptr-1]);

    // Find first active thread for PC selection
    function automatic [7:0] find_first_active_pc;
        input [THREADS_PER_BLOCK-1:0] mask;
        input [7:0] pcs [THREADS_PER_BLOCK-1:0];
        integer j;
        reg found;
        begin
            find_first_active_pc = pcs[0];  // Default
            found = 0;
            for (j = 0; j < THREADS_PER_BLOCK; j = j + 1) begin
                if (mask[j] && !found) begin
                    find_first_active_pc = pcs[j];
                    found = 1;
                end
            end
        end
    endfunction
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
            active_mask <= 0;
            stack_ptr <= 0;
            
            // Clear divergence stack
            for (int j = 0; j < DIVERGENCE_STACK_DEPTH; j = j + 1) begin
                stack_pending_mask[j] <= 0;
                stack_reconverge_pc[j] <= 0;
            end
        end else begin 
            case (core_state)
                IDLE: begin
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    if (start) begin 
                        // Initialize active mask with all enabled threads
                        active_mask <= thread_enable;
                        stack_ptr <= 0;
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
                    // Wait for all active LSUs to finish their request before continuing
                    logic any_lsu_waiting;
                    any_lsu_waiting = 1'b0;

                    for (int k = 0; k < THREADS_PER_BLOCK; k++) begin
                        // Only check active threads
                        if (active_mask[k]) begin
                            // Make sure no lsu_state = REQUESTING or WAITING
                            if (lsu_state[k] == 2'b01 || lsu_state[k] == 2'b10) begin
                                any_lsu_waiting = 1'b1;
                                break;
                            end
                        end
                    end

                    // If no active LSU is waiting for a response, move onto the next stage
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
                        // If we reach a RET instruction with all threads, block is done
                        if (stack_empty) begin
                            done <= 1;
                            core_state <= DONE;
                        end else begin
                            // Some threads still pending - pop and continue
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            current_pc <= stack_reconverge_pc[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                            core_state <= FETCH;
                        end
                    end else begin
                        // Check for reconvergence first
                        if (at_reconverge) begin
                            // Pop stack and restore pending threads
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                            // Use the reconverge PC
                            current_pc <= stack_reconverge_pc[stack_ptr-1];
                        end
                        // Check for divergence on branch instruction
                        else if (decoded_pc_mux && has_divergence && (stack_ptr < DIVERGENCE_STACK_DEPTH)) begin
                            // Push not-taken threads to stack
                            stack_pending_mask[stack_ptr] <= will_not_take;
                            // Reconverge at fall-through (PC + 1)
                            stack_reconverge_pc[stack_ptr] <= current_pc + 1;
                            stack_ptr <= stack_ptr + 1;
                            
                            // Mask off not-taken threads, execute taken path first
                            active_mask <= will_take;
                            current_pc <= decoded_immediate;  // Branch target
                        end
                        // Normal execution - use first active thread's next PC
                        else begin
                            current_pc <= find_first_active_pc(active_mask, next_pc);
                        end

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
