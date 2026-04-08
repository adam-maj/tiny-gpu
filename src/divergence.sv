`default_nettype none
`timescale 1ns/1ns

// BRANCH DIVERGENCE UNIT
// > Manages thread divergence and reconvergence when threads take different branches
// > Uses a divergence stack to track pending reconvergence points
// > Active thread mask indicates which threads are currently executing
//
// When threads diverge:
// 1. Push reconvergence PC and active mask for "not taken" threads to stack
// 2. Execute "taken" threads first (mask updated)
// 3. When reaching reconvergence point, pop stack and restore threads
//
// This implements a simple SIMT (Single Instruction Multiple Thread) divergence model
module divergence #(
    parameter THREADS_PER_BLOCK = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter STACK_DEPTH = 4  // Max nesting depth of divergent branches
) (
    input wire clk,
    input wire reset,
    
    // Core state
    input wire [2:0] core_state,
    
    // Branch information from each thread's PC module
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0],
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    
    // Branch signals from decoder
    input wire decoded_pc_mux,           // 1 = branch instruction
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] branch_target,  // Branch target PC
    
    // Thread enable from block dispatcher
    input wire [THREADS_PER_BLOCK-1:0] thread_enable,
    
    // Thread branch taken indicators (from PC modules)
    input wire [THREADS_PER_BLOCK-1:0] branch_taken,
    
    // Outputs
    output reg [THREADS_PER_BLOCK-1:0] active_mask,  // Which threads execute this cycle
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] unified_pc,  // PC all active threads use
    output reg diverged                              // 1 if threads are diverged
);

    // Divergence stack entry
    typedef struct packed {
        logic [THREADS_PER_BLOCK-1:0] pending_mask;        // Threads waiting at reconvergence
        logic [PROGRAM_MEM_ADDR_BITS-1:0] reconverge_pc;   // PC where threads reconverge
    } stack_entry_t;

    // Stack storage
    stack_entry_t divergence_stack [STACK_DEPTH-1:0];
    reg [$clog2(STACK_DEPTH):0] stack_ptr;  // Points to next free slot

    // State machine
    localparam S_NORMAL    = 2'b00,  // All threads executing same path
               S_DIVERGED  = 2'b01,  // Some threads masked off
               S_RECONVERGE = 2'b10; // Restoring masked threads
    
    reg [1:0] div_state;
    
    // Internal signals
    wire stack_empty = (stack_ptr == 0);
    wire stack_full = (stack_ptr == STACK_DEPTH);
    
    // Detect if a branch will cause divergence
    wire [THREADS_PER_BLOCK-1:0] will_take = branch_taken & active_mask;
    wire [THREADS_PER_BLOCK-1:0] will_not_take = (~branch_taken) & active_mask;
    wire has_divergence = (|will_take) && (|will_not_take);
    
    // Check if current PC matches top-of-stack reconvergence point
    wire at_reconverge = !stack_empty && 
                         (current_pc == divergence_stack[stack_ptr-1].reconverge_pc);

    // Execution state from core
    localparam EXECUTE = 3'b101;
    localparam UPDATE = 3'b110;

    always @(posedge clk) begin
        if (reset) begin
            active_mask <= thread_enable;  // Start with all enabled threads active
            unified_pc <= 0;
            diverged <= 0;
            stack_ptr <= 0;
            div_state <= S_NORMAL;
            
            // Clear stack
            for (int i = 0; i < STACK_DEPTH; i++) begin
                divergence_stack[i].pending_mask <= 0;
                divergence_stack[i].reconverge_pc <= 0;
            end
        end else begin
            // Handle divergence and reconvergence in UPDATE phase
            if (core_state == UPDATE) begin
                
                // Check for reconvergence first
                if (at_reconverge) begin
                    // Pop stack and restore pending threads
                    active_mask <= active_mask | divergence_stack[stack_ptr-1].pending_mask;
                    stack_ptr <= stack_ptr - 1;
                    
                    if (stack_ptr == 1) begin
                        // This was the last divergent branch
                        diverged <= 0;
                        div_state <= S_NORMAL;
                    end
                end
                // Check for new divergence on branch instruction
                else if (decoded_pc_mux && has_divergence && !stack_full) begin
                    // Push not-taken threads to stack
                    divergence_stack[stack_ptr].pending_mask <= will_not_take;
                    // Reconverge at fall-through (PC + 1)
                    divergence_stack[stack_ptr].reconverge_pc <= current_pc + 1;
                    stack_ptr <= stack_ptr + 1;
                    
                    // Mask off not-taken threads, execute taken path first
                    active_mask <= will_take;
                    unified_pc <= branch_target;
                    
                    diverged <= 1;
                    div_state <= S_DIVERGED;
                end
                // Normal execution - use thread 0's next PC or first active thread
                else begin
                    // Find first active thread's next PC
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        if (active_mask[i]) begin
                            unified_pc <= next_pc[i];
                            break;
                        end
                    end
                end
            end
            
            // Update active mask when new block starts
            if (core_state == 3'b000 && thread_enable != 0) begin
                // Reset on new block
                active_mask <= thread_enable;
                diverged <= 0;
                stack_ptr <= 0;
            end
        end
    end

    // Compute number of active threads (for debug/monitoring)
    wire [$clog2(THREADS_PER_BLOCK):0] active_count;
    integer j;
    reg [$clog2(THREADS_PER_BLOCK):0] count_temp;
    always @(*) begin
        count_temp = 0;
        for (j = 0; j < THREADS_PER_BLOCK; j++) begin
            count_temp = count_temp + active_mask[j];
        end
    end
    assign active_count = count_temp;

endmodule
