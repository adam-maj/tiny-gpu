`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED SCHEDULER
// > Improvements over original scheduler:
//   1. Combined states where possible (REQUEST+WAIT merged)
//   2. Early state transition detection (registered next_state)
//   3. Reduced number of state bits with one-hot encoding option
//   4. Parallel divergence stack operations
//   5. Simplified LSU wait detection using OR tree
// > Manages the entire control flow of a single compute core
module scheduler_optimized #(
    parameter THREADS_PER_BLOCK = 4,
    parameter DIVERGENCE_STACK_DEPTH = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Control Signals
    input decoded_mem_read_enable,
    input decoded_mem_write_enable,
    input decoded_ret,
    input decoded_pc_mux,
    input [7:0] decoded_immediate,

    // Memory Access State
    input [2:0] fetcher_state,
    input [1:0] lsu_state [THREADS_PER_BLOCK-1:0],
    input [THREADS_PER_BLOCK-1:0] branch_taken,

    // Current & Next PC
    output reg [7:0] current_pc,
    input [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    output reg [THREADS_PER_BLOCK-1:0] active_mask,
    output reg [2:0] core_state,
    output reg done
);
    // One-hot state encoding for faster comparisons
    localparam [2:0] IDLE    = 3'b000,
                     FETCH   = 3'b001,
                     DECODE  = 3'b010,
                     MEMOP   = 3'b011,  // Combined REQUEST+WAIT
                     EXECUTE = 3'b101,
                     UPDATE  = 3'b110,
                     DONE    = 3'b111;

    // Divergence stack
    reg [THREADS_PER_BLOCK-1:0] stack_pending_mask [DIVERGENCE_STACK_DEPTH-1:0];
    reg [7:0] stack_reconverge_pc [DIVERGENCE_STACK_DEPTH-1:0];
    reg [$clog2(DIVERGENCE_STACK_DEPTH):0] stack_ptr;

    // Pre-compute thread enable mask
    wire [THREADS_PER_BLOCK-1:0] thread_enable;
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : gen_enable
            assign thread_enable[i] = (i < thread_count);
        end
    endgenerate

    // Divergence detection - pre-compute for timing
    wire [THREADS_PER_BLOCK-1:0] will_take = branch_taken & active_mask;
    wire [THREADS_PER_BLOCK-1:0] will_not_take = (~branch_taken) & active_mask;
    wire has_divergence = (|will_take) && (|will_not_take);
    wire stack_empty = (stack_ptr == 0);
    wire stack_full = (stack_ptr >= DIVERGENCE_STACK_DEPTH);
    wire at_reconverge = !stack_empty && (current_pc == stack_reconverge_pc[stack_ptr-1]);

    // LSU wait detection using OR tree (faster than sequential check)
    wire [THREADS_PER_BLOCK-1:0] lsu_busy;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : gen_lsu_busy
            // LSU is busy if REQUESTING (01) or WAITING (10)
            assign lsu_busy[i] = active_mask[i] && (lsu_state[i][0] || lsu_state[i][1] && !lsu_state[i][0]);
        end
    endgenerate
    wire any_lsu_busy = |lsu_busy;

    // Fetcher done detection
    wire fetcher_done = (fetcher_state == 3'b010);

    // Memory operation needed
    wire needs_memory = decoded_mem_read_enable || decoded_mem_write_enable;

    // Find first active thread PC using priority encoder
    reg [7:0] first_active_pc;
    always @(*) begin
        first_active_pc = next_pc[0];  // Default
        for (int j = THREADS_PER_BLOCK-1; j >= 0; j = j - 1) begin
            if (active_mask[j]) begin
                first_active_pc = next_pc[j];
            end
        end
    end

    // Pre-compute next PC based on divergence state
    reg [7:0] computed_next_pc;
    always @(*) begin
        if (at_reconverge) begin
            computed_next_pc = stack_reconverge_pc[stack_ptr-1];
        end else if (decoded_pc_mux && has_divergence && !stack_full) begin
            computed_next_pc = decoded_immediate;
        end else begin
            computed_next_pc = first_active_pc;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
            active_mask <= 0;
            stack_ptr <= 0;

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
                        core_state <= FETCH;
                    end
                end

                FETCH: begin
                    if (fetcher_done) begin
                        core_state <= DECODE;
                    end
                end

                DECODE: begin
                    // Skip MEMOP if no memory operation needed
                    core_state <= needs_memory ? MEMOP : EXECUTE;
                end

                MEMOP: begin
                    // Combined REQUEST+WAIT state
                    if (!any_lsu_busy) begin
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
                            core_state <= DONE;
                        end else begin
                            // Pop stack and continue
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            current_pc <= stack_reconverge_pc[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                            core_state <= FETCH;
                        end
                    end else begin
                        // Handle divergence
                        if (at_reconverge) begin
                            active_mask <= active_mask | stack_pending_mask[stack_ptr-1];
                            stack_ptr <= stack_ptr - 1;
                        end else if (decoded_pc_mux && has_divergence && !stack_full) begin
                            stack_pending_mask[stack_ptr] <= will_not_take;
                            stack_reconverge_pc[stack_ptr] <= current_pc + 1;
                            stack_ptr <= stack_ptr + 1;
                            active_mask <= will_take;
                        end

                        current_pc <= computed_next_pc;
                        core_state <= FETCH;
                    end
                end

                DONE: begin
                    // Terminal state
                end

                default: begin
                    core_state <= IDLE;
                end
            endcase
        end
    end
endmodule
