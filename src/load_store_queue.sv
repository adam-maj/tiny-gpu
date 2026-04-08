/**
 * Load/Store Queue (LSQ)
 * Manages out-of-order memory operations for high performance
 * Production features:
 * - Store-to-load forwarding
 * - Memory dependency checking
 * - Out-of-order completion
 * - Memory ordering enforcement
 * - Store buffer
 */

module load_store_queue #(
    parameter QUEUE_SIZE = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic reset,
    
    // Dispatch interface
    input  logic                    dispatch_valid,
    input  logic                    dispatch_is_load,
    input  logic [ADDR_WIDTH-1:0]   dispatch_addr,
    input  logic [DATA_WIDTH-1:0]   dispatch_data,      // For stores
    input  logic [3:0]              dispatch_id,         // Instruction ID
    output logic                    dispatch_ready,
    
    // Execute interface
    output logic                    execute_valid,
    output logic                    execute_is_load,
    output logic [ADDR_WIDTH-1:0]   execute_addr,
    output logic [DATA_WIDTH-1:0]   execute_data,
    output logic [3:0]              execute_id,
    input  logic                    execute_ready,
    
    // Memory interface
    output logic                    mem_req,
    output logic                    mem_write,
    output logic [ADDR_WIDTH-1:0]   mem_addr,
    output logic [DATA_WIDTH-1:0]   mem_wdata,
    input  logic [DATA_WIDTH-1:0]   mem_rdata,
    input  logic                    mem_valid,
    
    // Completion interface
    output logic                    complete_valid,
    output logic [3:0]              complete_id,
    output logic [DATA_WIDTH-1:0]   complete_data,
    input  logic                    complete_ready,
    
    // Commit interface (for stores)
    input  logic                    commit_valid,
    input  logic [3:0]              commit_id,
    
    // Memory fence
    input  logic                    fence,
    output logic                    fence_complete,
    
    // Statistics
    output logic [31:0]             forwarded_loads,
    output logic [31:0]             stalled_cycles
);

    // LSQ entry
    typedef struct packed {
        logic                   valid;
        logic                   is_load;
        logic                   executed;
        logic                   completed;
        logic                   committed;          // For stores
        logic [ADDR_WIDTH-1:0]  addr;
        logic [DATA_WIDTH-1:0]  data;
        logic [3:0]             instr_id;
        logic [7:0]             age;                // For ordering
    } lsq_entry_t;
    
    lsq_entry_t queue [QUEUE_SIZE];
    logic [$clog2(QUEUE_SIZE)-1:0] head, tail, count;
    logic [7:0] global_age;
    
    // Store buffer for committed stores
    typedef struct packed {
        logic                   valid;
        logic [ADDR_WIDTH-1:0]  addr;
        logic [DATA_WIDTH-1:0]  data;
    } store_buffer_entry_t;
    
    store_buffer_entry_t store_buffer [QUEUE_SIZE/2];
    logic [$clog2(QUEUE_SIZE/2)-1:0] sb_head, sb_tail, sb_count;
    
    // Find oldest ready entry
    logic [$clog2(QUEUE_SIZE)-1:0] oldest_ready_idx;
    logic oldest_ready_found;
    logic [7:0] oldest_age;
    
    always_comb begin
        oldest_ready_found = 0;
        oldest_ready_idx = 0;
        oldest_age = 8'hFF;
        
        for (int i = 0; i < QUEUE_SIZE; i++) begin
            if (queue[i].valid && !queue[i].executed) begin
                // Check if ready to execute
                logic ready = 1;
                
                // For loads, check for address conflicts with older stores
                if (queue[i].is_load) begin
                    for (int j = 0; j < QUEUE_SIZE; j++) begin
                        if (queue[j].valid && !queue[j].is_load && 
                            queue[j].age < queue[i].age && 
                            !queue[j].executed &&
                            queue[j].addr == queue[i].addr) begin
                            ready = 0;
                            break;
                        end
                    end
                end
                
                if (ready && queue[i].age < oldest_age) begin
                    oldest_ready_found = 1;
                    oldest_ready_idx = i;
                    oldest_age = queue[i].age;
                end
            end
        end
    end
    
    // Store-to-load forwarding check
    logic forward_found;
    logic [$clog2(QUEUE_SIZE)-1:0] forward_idx;
    logic [DATA_WIDTH-1:0] forward_data;
    
    always_comb begin
        forward_found = 0;
        forward_idx = 0;
        forward_data = 0;
        
        if (oldest_ready_found && queue[oldest_ready_idx].is_load) begin
            logic [7:0] youngest_store_age = 0;
            
            // Find youngest older store with same address that has data
            for (int i = 0; i < QUEUE_SIZE; i++) begin
                if (queue[i].valid && !queue[i].is_load && 
                    queue[i].executed &&
                    queue[i].age < queue[oldest_ready_idx].age &&
                    queue[i].addr == queue[oldest_ready_idx].addr &&
                    queue[i].age > youngest_store_age) begin
                    forward_found = 1;
                    forward_idx = i;
                    forward_data = queue[i].data;
                    youngest_store_age = queue[i].age;
                end
            end
        end
    end
    
    // Control signals
    assign dispatch_ready = (count < QUEUE_SIZE - 1);
    assign execute_valid = oldest_ready_found;
    assign execute_is_load = queue[oldest_ready_idx].is_load;
    assign execute_addr = queue[oldest_ready_idx].addr;
    assign execute_data = queue[oldest_ready_idx].data;
    assign execute_id = queue[oldest_ready_idx].instr_id;
    
    // Fence completion check
    logic all_completed;
    always_comb begin
        all_completed = 1;
        for (int i = 0; i < QUEUE_SIZE; i++) begin
            if (queue[i].valid && !queue[i].completed) begin
                all_completed = 0;
                break;
            end
        end
    end
    assign fence_complete = fence && all_completed && (sb_count == 0);
    
    // Statistics
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            forwarded_loads <= 0;
            stalled_cycles <= 0;
        end else begin
            if (forward_found && execute_ready) begin
                forwarded_loads <= forwarded_loads + 1;
            end
            if (dispatch_valid && !dispatch_ready) begin
                stalled_cycles <= stalled_cycles + 1;
            end
        end
    end
    
    // Age counter
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            global_age <= 0;
        end else if (dispatch_valid && dispatch_ready) begin
            global_age <= global_age + 1;
        end
    end
    
    // Queue management
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            for (int i = 0; i < QUEUE_SIZE; i++) begin
                queue[i].valid <= 0;
            end
        end else begin
            // Dispatch new operations
            if (dispatch_valid && dispatch_ready) begin
                queue[tail].valid <= 1;
                queue[tail].is_load <= dispatch_is_load;
                queue[tail].executed <= 0;
                queue[tail].completed <= 0;
                queue[tail].committed <= 0;
                queue[tail].addr <= dispatch_addr;
                queue[tail].data <= dispatch_data;
                queue[tail].instr_id <= dispatch_id;
                queue[tail].age <= global_age;
                tail <= tail + 1;
                count <= count + 1;
            end
            
            // Execute operations
            if (execute_valid && execute_ready) begin
                if (forward_found) begin
                    // Store-to-load forwarding
                    queue[oldest_ready_idx].executed <= 1;
                    queue[oldest_ready_idx].completed <= 1;
                    queue[oldest_ready_idx].data <= forward_data;
                end else begin
                    queue[oldest_ready_idx].executed <= 1;
                end
            end
            
            // Handle memory responses
            if (mem_valid) begin
                // Find the entry waiting for this response
                for (int i = 0; i < QUEUE_SIZE; i++) begin
                    if (queue[i].valid && queue[i].executed && !queue[i].completed &&
                        queue[i].addr == mem_addr) begin
                        queue[i].completed <= 1;
                        if (queue[i].is_load) begin
                            queue[i].data <= mem_rdata;
                        end
                        break;
                    end
                end
            end
            
            // Commit stores
            if (commit_valid) begin
                for (int i = 0; i < QUEUE_SIZE; i++) begin
                    if (queue[i].valid && queue[i].instr_id == commit_id && !queue[i].is_load) begin
                        queue[i].committed <= 1;
                    end
                end
            end
            
            // Retire completed entries from head
            if (queue[head].valid && queue[head].completed && 
                (queue[head].is_load || queue[head].committed)) begin
                queue[head].valid <= 0;
                head <= head + 1;
                count <= count - 1;
            end
        end
    end
    
    // Store buffer management
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sb_head <= 0;
            sb_tail <= 0;
            sb_count <= 0;
            for (int i = 0; i < QUEUE_SIZE/2; i++) begin
                store_buffer[i].valid <= 0;
            end
        end else begin
            // Move committed stores to store buffer
            for (int i = 0; i < QUEUE_SIZE; i++) begin
                if (queue[i].valid && !queue[i].is_load && 
                    queue[i].committed && queue[i].completed &&
                    sb_count < QUEUE_SIZE/2) begin
                    store_buffer[sb_tail].valid <= 1;
                    store_buffer[sb_tail].addr <= queue[i].addr;
                    store_buffer[sb_tail].data <= queue[i].data;
                    sb_tail <= sb_tail + 1;
                    sb_count <= sb_count + 1;
                end
            end
            
            // Drain store buffer to memory
            if (store_buffer[sb_head].valid && !mem_req) begin
                store_buffer[sb_head].valid <= 0;
                sb_head <= sb_head + 1;
                sb_count <= sb_count - 1;
            end
        end
    end
    
    // Memory request generation
    always_comb begin
        mem_req = 0;
        mem_write = 0;
        mem_addr = 0;
        mem_wdata = 0;
        
        if (execute_valid && execute_ready && !forward_found) begin
            mem_req = 1;
            mem_write = !execute_is_load;
            mem_addr = execute_addr;
            mem_wdata = execute_data;
        end else if (store_buffer[sb_head].valid) begin
            mem_req = 1;
            mem_write = 1;
            mem_addr = store_buffer[sb_head].addr;
            mem_wdata = store_buffer[sb_head].data;
        end
    end
    
    // Completion output
    assign complete_valid = queue[head].valid && queue[head].completed && queue[head].is_load;
    assign complete_id = queue[head].instr_id;
    assign complete_data = queue[head].data;

endmodule
