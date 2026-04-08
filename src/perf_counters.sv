`default_nettype none
`timescale 1ns/1ns

// PERFORMANCE COUNTERS
// > Comprehensive GPU profiling and monitoring
// > Hardware cycle counters for various events
// > Supports reading/resetting individual counters
module perf_counters #(
    parameter COUNTER_BITS = 32,       // Width of each counter
    parameter NUM_CORES = 2            // Number of GPU cores
) (
    input wire clk,
    input wire reset,
    
    // Global control
    input wire enable_counting,        // Master enable
    input wire reset_counters,         // Reset all counters
    
    // Event inputs - Core execution
    input wire [NUM_CORES-1:0] core_active,      // Core is executing
    input wire [NUM_CORES-1:0] instruction_issued,
    input wire [NUM_CORES-1:0] instruction_completed,
    input wire [NUM_CORES-1:0] branch_taken,
    input wire [NUM_CORES-1:0] branch_divergent,
    
    // Event inputs - Memory
    input wire [NUM_CORES-1:0] dcache_hit,
    input wire [NUM_CORES-1:0] dcache_miss,
    input wire [NUM_CORES-1:0] icache_hit,
    input wire [NUM_CORES-1:0] icache_miss,
    input wire [NUM_CORES-1:0] mem_read,
    input wire [NUM_CORES-1:0] mem_write,
    input wire [NUM_CORES-1:0] mem_stall,
    
    // Event inputs - Synchronization
    input wire [NUM_CORES-1:0] barrier_wait,
    input wire [NUM_CORES-1:0] atomic_op,
    input wire [NUM_CORES-1:0] warp_stall,
    
    // Counter read interface
    input wire [4:0] counter_select,   // Which counter to read
    output reg [COUNTER_BITS-1:0] counter_value,
    
    // Summary outputs (always available)
    output wire [COUNTER_BITS-1:0] total_cycles,
    output wire [COUNTER_BITS-1:0] total_instructions,
    output wire [COUNTER_BITS-1:0] total_mem_accesses,
    
    // Derived metrics (combinational)
    output wire [15:0] ipc_x100,           // Instructions per cycle * 100
    output wire [7:0] dcache_hit_rate,     // Hit rate percentage
    output wire [7:0] icache_hit_rate      // Hit rate percentage
);
    // Counter indices
    localparam CTR_CYCLES          = 5'd0;
    localparam CTR_ACTIVE_CYCLES   = 5'd1;
    localparam CTR_INST_ISSUED     = 5'd2;
    localparam CTR_INST_COMPLETED  = 5'd3;
    localparam CTR_BRANCHES        = 5'd4;
    localparam CTR_DIVERGENT       = 5'd5;
    localparam CTR_DCACHE_HIT      = 5'd6;
    localparam CTR_DCACHE_MISS     = 5'd7;
    localparam CTR_ICACHE_HIT      = 5'd8;
    localparam CTR_ICACHE_MISS     = 5'd9;
    localparam CTR_MEM_READ        = 5'd10;
    localparam CTR_MEM_WRITE       = 5'd11;
    localparam CTR_MEM_STALL       = 5'd12;
    localparam CTR_BARRIER_WAIT    = 5'd13;
    localparam CTR_ATOMIC_OPS      = 5'd14;
    localparam CTR_WARP_STALLS     = 5'd15;
    
    // Counter storage
    reg [COUNTER_BITS-1:0] cycles;
    reg [COUNTER_BITS-1:0] active_cycles;
    reg [COUNTER_BITS-1:0] inst_issued;
    reg [COUNTER_BITS-1:0] inst_completed;
    reg [COUNTER_BITS-1:0] branches;
    reg [COUNTER_BITS-1:0] divergent_branches;
    reg [COUNTER_BITS-1:0] dcache_hits;
    reg [COUNTER_BITS-1:0] dcache_misses;
    reg [COUNTER_BITS-1:0] icache_hits;
    reg [COUNTER_BITS-1:0] icache_misses;
    reg [COUNTER_BITS-1:0] mem_reads;
    reg [COUNTER_BITS-1:0] mem_writes;
    reg [COUNTER_BITS-1:0] mem_stalls;
    reg [COUNTER_BITS-1:0] barrier_waits;
    reg [COUNTER_BITS-1:0] atomic_ops_cnt;
    reg [COUNTER_BITS-1:0] warp_stalls;
    
    // Population count function (count set bits)
    function automatic [3:0] popcount;
        input [NUM_CORES-1:0] bits;
        integer i;
        begin
            popcount = 0;
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                popcount = popcount + bits[i];
            end
        end
    endfunction
    
    // Counter update logic
    always @(posedge clk) begin
        if (reset || reset_counters) begin
            cycles <= 0;
            active_cycles <= 0;
            inst_issued <= 0;
            inst_completed <= 0;
            branches <= 0;
            divergent_branches <= 0;
            dcache_hits <= 0;
            dcache_misses <= 0;
            icache_hits <= 0;
            icache_misses <= 0;
            mem_reads <= 0;
            mem_writes <= 0;
            mem_stalls <= 0;
            barrier_waits <= 0;
            atomic_ops_cnt <= 0;
            warp_stalls <= 0;
        end else if (enable_counting) begin
            // Always count cycles
            cycles <= cycles + 1;
            
            // Count active cycles (at least one core active)
            if (|core_active) begin
                active_cycles <= active_cycles + 1;
            end
            
            // Aggregate events from all cores
            inst_issued <= inst_issued + popcount(instruction_issued);
            inst_completed <= inst_completed + popcount(instruction_completed);
            branches <= branches + popcount(branch_taken);
            divergent_branches <= divergent_branches + popcount(branch_divergent);
            dcache_hits <= dcache_hits + popcount(dcache_hit);
            dcache_misses <= dcache_misses + popcount(dcache_miss);
            icache_hits <= icache_hits + popcount(icache_hit);
            icache_misses <= icache_misses + popcount(icache_miss);
            mem_reads <= mem_reads + popcount(mem_read);
            mem_writes <= mem_writes + popcount(mem_write);
            mem_stalls <= mem_stalls + popcount(mem_stall);
            barrier_waits <= barrier_waits + popcount(barrier_wait);
            atomic_ops_cnt <= atomic_ops_cnt + popcount(atomic_op);
            warp_stalls <= warp_stalls + popcount(warp_stall);
        end
    end
    
    // Counter read multiplexer
    always @(*) begin
        case (counter_select)
            CTR_CYCLES:          counter_value = cycles;
            CTR_ACTIVE_CYCLES:   counter_value = active_cycles;
            CTR_INST_ISSUED:     counter_value = inst_issued;
            CTR_INST_COMPLETED:  counter_value = inst_completed;
            CTR_BRANCHES:        counter_value = branches;
            CTR_DIVERGENT:       counter_value = divergent_branches;
            CTR_DCACHE_HIT:      counter_value = dcache_hits;
            CTR_DCACHE_MISS:     counter_value = dcache_misses;
            CTR_ICACHE_HIT:      counter_value = icache_hits;
            CTR_ICACHE_MISS:     counter_value = icache_misses;
            CTR_MEM_READ:        counter_value = mem_reads;
            CTR_MEM_WRITE:       counter_value = mem_writes;
            CTR_MEM_STALL:       counter_value = mem_stalls;
            CTR_BARRIER_WAIT:    counter_value = barrier_waits;
            CTR_ATOMIC_OPS:      counter_value = atomic_ops_cnt;
            CTR_WARP_STALLS:     counter_value = warp_stalls;
            default:             counter_value = 0;
        endcase
    end
    
    // Summary outputs
    assign total_cycles = cycles;
    assign total_instructions = inst_completed;
    assign total_mem_accesses = mem_reads + mem_writes;
    
    // Derived metrics (avoid division by zero)
    wire [COUNTER_BITS-1:0] safe_cycles = (cycles == 0) ? 1 : cycles;
    wire [COUNTER_BITS-1:0] dcache_total = dcache_hits + dcache_misses;
    wire [COUNTER_BITS-1:0] icache_total = icache_hits + icache_misses;
    wire [COUNTER_BITS-1:0] safe_dcache_total = (dcache_total == 0) ? 1 : dcache_total;
    wire [COUNTER_BITS-1:0] safe_icache_total = (icache_total == 0) ? 1 : icache_total;
    
    assign ipc_x100 = (inst_completed * 100) / safe_cycles;
    assign dcache_hit_rate = (dcache_hits * 100) / safe_dcache_total;
    assign icache_hit_rate = (icache_hits * 100) / safe_icache_total;
    
endmodule

// SIMPLE PROFILER
// > Lightweight profiling interface
// > Start/stop timing for code regions
module profiler #(
    parameter NUM_REGIONS = 4,
    parameter COUNTER_BITS = 32
) (
    input wire clk,
    input wire reset,
    
    // Region control (one-hot encoding)
    input wire [NUM_REGIONS-1:0] region_start,
    input wire [NUM_REGIONS-1:0] region_stop,
    
    // Region times output
    output reg [COUNTER_BITS-1:0] region_cycles [NUM_REGIONS-1:0],
    output reg [15:0] region_invocations [NUM_REGIONS-1:0],
    
    // Status
    output wire [NUM_REGIONS-1:0] regions_active
);
    reg [NUM_REGIONS-1:0] active;
    reg [COUNTER_BITS-1:0] start_cycle [NUM_REGIONS-1:0];
    reg [COUNTER_BITS-1:0] global_cycle;
    
    assign regions_active = active;
    
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            active <= 0;
            global_cycle <= 0;
            for (i = 0; i < NUM_REGIONS; i = i + 1) begin
                region_cycles[i] <= 0;
                region_invocations[i] <= 0;
                start_cycle[i] <= 0;
            end
        end else begin
            global_cycle <= global_cycle + 1;
            
            for (i = 0; i < NUM_REGIONS; i = i + 1) begin
                if (region_start[i] && !active[i]) begin
                    active[i] <= 1;
                    start_cycle[i] <= global_cycle;
                end
                
                if (region_stop[i] && active[i]) begin
                    active[i] <= 0;
                    region_cycles[i] <= region_cycles[i] + (global_cycle - start_cycle[i]);
                    region_invocations[i] <= region_invocations[i] + 1;
                end
            end
        end
    end
endmodule
