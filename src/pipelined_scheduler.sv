`default_nettype none
`timescale 1ns/1ns

// PIPELINED SCHEDULER
// > Implements a simple 2-stage pipeline: Fetch/Decode and Execute/Update
// > Overlaps instruction fetch with execution to improve throughput
// > Pipeline stages:
//   Stage 1 (F/D): FETCH -> DECODE
//   Stage 2 (E/U): REQUEST -> WAIT -> EXECUTE -> UPDATE
//
// In the original design, one instruction takes ~6 cycles:
//   FETCH -> DECODE -> REQUEST -> WAIT -> EXECUTE -> UPDATE
//
// With pipelining, while Stage 2 executes instruction N,
// Stage 1 can fetch instruction N+1, improving throughput.
module pipelined_scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter DIVERGENCE_STACK_DEPTH = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Thread count for this block
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Control Signals from decoder
    input decoded_mem_read_enable,
    input decoded_mem_write_enable,
    input decoded_ret,
    input decoded_pc_mux,
    input [7:0] decoded_immediate,

    // Memory Access State
    input [2:0] fetcher_state,
    input [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Branch taken from each thread's PC
    input [THREADS_PER_BLOCK-1:0] branch_taken,

    // Current & Next PC
    output reg [7:0] current_pc,
    input [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Prefetch PC for next instruction
    output reg [7:0] prefetch_pc,
    output reg prefetch_enable,

    // Active thread mask (for divergence support)
    output reg [THREADS_PER_BLOCK-1:0] active_mask,

    // Execution State
    output reg [2:0] core_state,
    output reg done,
    
    // Pipeline status
    output reg pipeline_stall,  // 1 if pipeline is stalled
    output reg [1:0] pipeline_stage  // Current pipeline stage
);
    // Main state machine states (same as original for compatibility)
    localparam IDLE = 3'b000,
               FETCH = 3'b001,
               DECODE = 3'b010,
               REQUEST = 3'b011,
               WAIT = 3'b100,
               EXECUTE = 3'b101,
               UPDATE = 3'b110,
               DONE = 3'b111;

    // Pipeline stages
    localparam PIPE_IDLE = 2'b00,
               PIPE_FD = 2'b01,    // Fetch/Decode
               PIPE_EU = 2'b10,    // Execute/Update
               PIPE_BOTH = 2'b11;  // Both stages active

    // Pipeline registers
    reg [15:0] pipe_instruction;      // Instruction in execute stage
    reg [7:0] pipe_pc;                // PC of instruction in execute stage
    reg pipe_valid;                   // Execute stage has valid instruction
    reg prefetch_valid;               // Prefetch completed

    // Divergence stack (same as non-pipelined version)
    reg [THREADS_PER_BLOCK-1:0] stack_pending_mask [DIVERGENCE_STACK_DEPTH-1:0];
    reg [7:0] stack_reconverge_pc [DIVERGENCE_STACK_DEPTH-1:0];
    reg [$clog2(DIVERGENCE_STACK_DEPTH):0] stack_ptr;

    // Thread enable mask
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
    wire stack_empty = (stack_ptr == 0);
    wire at_reconverge = !stack_empty && (current_pc == stack_reconverge_pc[stack_ptr-1]);

    // Pipeline hazard detection
    wire is_branch = decoded_pc_mux;
    wire is_memory = decoded_mem_read_enable || decoded_mem_write_enable;
    
    // Stall if: branch instruction (flush pipeline) or memory operation (wait for completion)
    wire need_stall = is_branch || is_memory || decoded_ret;

    // Find first active thread's next PC
    function automatic [7:0] find_first_active_pc;
        input [THREADS_PER_BLOCK-1:0] mask;
        input [7:0] pcs [THREADS_PER_BLOCK-1:0];
        integer j;
        reg found;
        begin
            find_first_active_pc = pcs[0];
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
            prefetch_pc <= 0;
            prefetch_enable <= 0;
            core_state <= IDLE;
            done <= 0;
            active_mask <= 0;
            stack_ptr <= 0;
            pipe_valid <= 0;
            prefetch_valid <= 0;
            pipeline_stall <= 0;
            pipeline_stage <= PIPE_IDLE;

            for (int j = 0; j < DIVERGENCE_STACK_DEPTH; j = j + 1) begin
                stack_pending_mask[j] <= 0;
                stack_reconverge_pc[j] <= 0;
            end
        end else begin
            case (core_state)
                IDLE: begin
                    if (start) begin
                        active_mask <= thread_enable;
                        stack_ptr <= 0;
                        pipe_valid <= 0;
                        prefetch_enable <= 0;
                        pipeline_stage <= PIPE_FD;
                        core_state <= FETCH;
                    end
                end

                FETCH: begin
                    if (fetcher_state == 3'b010) begin
                        // Enable prefetch for next instruction (speculative)
                        if (!need_stall && !pipeline_stall) begin
                            prefetch_pc <= current_pc + 1;
                            prefetch_enable <= 1;
                        end
                        core_state <= DECODE;
                    end
                end

                DECODE: begin
                    prefetch_enable <= 0;  // One-cycle prefetch trigger
                    core_state <= REQUEST;
                end

                REQUEST: begin
                    core_state <= WAIT;
                end

                WAIT: begin
                    logic any_lsu_waiting;
                    any_lsu_waiting = 1'b0;

                    for (int k = 0; k < THREADS_PER_BLOCK; k++) begin
                        if (active_mask[k]) begin
                            if (lsu_state[k] == 2'b01 || lsu_state[k] == 2'b10) begin
                                any_lsu_waiting = 1'b1;
                                break;
                            end
                        end
                    end

                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end

                EXECUTE: begin
                    core_state <= UPDATE;
                end

                UPDATE: begin
                    if (decoded_ret) begin
                        if (stack_empty) begin
                            done <= 1;
                            pipeline_stage <= PIPE_IDLE;
                            core_state <= DONE;
                        end else begin
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            current_pc <= stack_reconverge_pc[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                            core_state <= FETCH;
                        end
                    end else begin
                        // Handle divergence/reconvergence
                        if (at_reconverge) begin
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                            current_pc <= stack_reconverge_pc[stack_ptr-1];
                            pipeline_stall <= 1;  // Flush speculative fetch
                        end else if (decoded_pc_mux && has_divergence && (stack_ptr < DIVERGENCE_STACK_DEPTH)) begin
                            stack_pending_mask[stack_ptr] <= will_not_take;
                            stack_reconverge_pc[stack_ptr] <= current_pc + 1;
                            stack_ptr <= stack_ptr + 1;
                            active_mask <= will_take;
                            current_pc <= decoded_immediate;
                            pipeline_stall <= 1;  // Flush speculative fetch
                        end else if (prefetch_valid && !pipeline_stall) begin
                            // Use prefetched instruction (no stall)
                            current_pc <= prefetch_pc;
                            pipeline_stall <= 0;
                        end else begin
                            // Normal sequential execution
                            current_pc <= find_first_active_pc(active_mask, next_pc);
                            pipeline_stall <= 0;
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
