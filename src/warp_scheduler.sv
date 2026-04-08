`default_nettype none
`timescale 1ns/1ns

// WARP SCHEDULER
// > Manages execution of multiple warps
// > Implements round-robin scheduling with priority support
// > Handles warp stalls and dependency tracking
module warp_scheduler #(
    parameter NUM_WARPS = 4,           // Number of warps to manage
    parameter THREADS_PER_WARP = 8,    // Threads per warp
    parameter DATA_BITS = 8,           // Data width
    parameter PC_BITS = 8              // Program counter bits
) (
    input wire clk,
    input wire reset,
    
    // Warp status inputs (per-warp)
    input wire [NUM_WARPS-1:0] warp_active,        // Which warps are active
    input wire [NUM_WARPS-1:0] warp_ready,         // Which warps can execute
    input wire [NUM_WARPS-1:0] warp_waiting_mem,   // Waiting for memory
    input wire [NUM_WARPS-1:0] warp_waiting_sync,  // Waiting at barrier
    input wire [NUM_WARPS-1:0] warp_completed,     // Warp finished execution
    
    // Priority hints (optional, higher = more priority)
    input wire [1:0] warp_priority [NUM_WARPS-1:0],
    
    // Selected warp output
    output reg [$clog2(NUM_WARPS)-1:0] selected_warp,
    output reg warp_valid,                          // A valid warp is selected
    
    // Issue control
    input wire issue_stall,            // Don't advance to next warp
    input wire warp_yield,             // Current warp yields execution
    
    // Statistics
    output reg [15:0] cycles_idle,
    output reg [15:0] warps_issued,
    output reg [15:0] stall_cycles
);
    localparam WARP_BITS = $clog2(NUM_WARPS);
    
    // Scheduling state
    reg [WARP_BITS-1:0] last_scheduled;
    reg [WARP_BITS-1:0] current_candidate;
    
    // Ready mask computation
    wire [NUM_WARPS-1:0] schedulable_mask;
    assign schedulable_mask = warp_active & warp_ready & 
                               ~warp_waiting_mem & ~warp_waiting_sync & 
                               ~warp_completed;
    
    // Check if any warp is schedulable
    wire any_schedulable = |schedulable_mask;
    
    // Priority-aware selection
    // Find highest priority among schedulable warps
    reg [1:0] highest_priority;
    reg [NUM_WARPS-1:0] priority_mask;
    
    integer i;
    always @(*) begin
        highest_priority = 0;
        for (i = 0; i < NUM_WARPS; i = i + 1) begin
            if (schedulable_mask[i] && warp_priority[i] > highest_priority) begin
                highest_priority = warp_priority[i];
            end
        end
        
        // Create mask of highest priority schedulable warps
        for (i = 0; i < NUM_WARPS; i = i + 1) begin
            priority_mask[i] = schedulable_mask[i] && (warp_priority[i] == highest_priority);
        end
    end
    
    // Round-robin among equal priority warps
    // Find next warp after last_scheduled that is in priority_mask
    reg [WARP_BITS-1:0] next_warp;
    reg found_next;
    
    always @(*) begin
        next_warp = last_scheduled;
        found_next = 0;
        
        // Search from last_scheduled+1 to end
        for (i = 0; i < NUM_WARPS; i = i + 1) begin
            if (!found_next) begin
                current_candidate = (last_scheduled + 1 + i) % NUM_WARPS;
                if (priority_mask[current_candidate]) begin
                    next_warp = current_candidate;
                    found_next = 1;
                end
            end
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            selected_warp <= 0;
            warp_valid <= 0;
            last_scheduled <= NUM_WARPS - 1;  // Start at max so first selection is 0
            cycles_idle <= 0;
            warps_issued <= 0;
            stall_cycles <= 0;
        end else begin
            if (!issue_stall || warp_yield) begin
                if (any_schedulable) begin
                    selected_warp <= next_warp;
                    warp_valid <= 1;
                    last_scheduled <= next_warp;
                    warps_issued <= warps_issued + 1;
                end else begin
                    warp_valid <= 0;
                    cycles_idle <= cycles_idle + 1;
                end
            end else begin
                stall_cycles <= stall_cycles + 1;
            end
        end
    end
endmodule

// WARP CONTEXT STORE
// > Stores register state for multiple warps
// > Enables fast context switching
module warp_context #(
    parameter NUM_WARPS = 4,
    parameter THREADS_PER_WARP = 8,
    parameter NUM_REGS = 8,
    parameter DATA_BITS = 8
) (
    input wire clk,
    input wire reset,
    
    // Access interface
    input wire [$clog2(NUM_WARPS)-1:0] warp_id,
    input wire [$clog2(THREADS_PER_WARP)-1:0] thread_id,
    input wire [$clog2(NUM_REGS)-1:0] reg_id,
    
    // Read port
    input wire read_en,
    output reg [DATA_BITS-1:0] read_data,
    
    // Write port
    input wire write_en,
    input wire [DATA_BITS-1:0] write_data,
    
    // Bulk operations
    input wire warp_clear,             // Clear all regs for warp_id
    
    // Program counter per warp
    input wire [$clog2(NUM_WARPS)-1:0] pc_warp_id,
    output reg [DATA_BITS-1:0] pc_out,
    input wire pc_write_en,
    input wire [DATA_BITS-1:0] pc_write_data
);
    localparam WARP_BITS = $clog2(NUM_WARPS);
    localparam THREAD_BITS = $clog2(THREADS_PER_WARP);
    localparam REG_BITS = $clog2(NUM_REGS);
    localparam TOTAL_REGS = NUM_WARPS * THREADS_PER_WARP * NUM_REGS;
    
    // Register file storage
    reg [DATA_BITS-1:0] registers [TOTAL_REGS-1:0];
    
    // PC storage (one per warp)
    reg [DATA_BITS-1:0] warp_pc [NUM_WARPS-1:0];
    
    // Address computation
    wire [$clog2(TOTAL_REGS)-1:0] reg_addr;
    assign reg_addr = (warp_id * THREADS_PER_WARP * NUM_REGS) + 
                      (thread_id * NUM_REGS) + reg_id;
    
    // Read logic
    always @(posedge clk) begin
        if (read_en) begin
            read_data <= registers[reg_addr];
        end
        pc_out <= warp_pc[pc_warp_id];
    end
    
    // Write logic
    integer i, j;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < TOTAL_REGS; i = i + 1) begin
                registers[i] <= 0;
            end
            for (i = 0; i < NUM_WARPS; i = i + 1) begin
                warp_pc[i] <= 0;
            end
        end else begin
            if (warp_clear) begin
                // Clear all registers for the specified warp
                for (j = 0; j < THREADS_PER_WARP * NUM_REGS; j = j + 1) begin
                    registers[warp_id * THREADS_PER_WARP * NUM_REGS + j] <= 0;
                end
                warp_pc[warp_id] <= 0;
            end else begin
                if (write_en) begin
                    registers[reg_addr] <= write_data;
                end
                if (pc_write_en) begin
                    warp_pc[pc_warp_id] <= pc_write_data;
                end
            end
        end
    end
endmodule
