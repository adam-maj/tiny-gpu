`default_nettype none
`timescale 1ns/1ns

// MEMORY COALESCING UNIT
// > Combines adjacent memory requests from multiple threads into fewer, larger requests
// > Reduces memory bandwidth usage when threads access sequential or aligned addresses
// > Sits between LSUs and the memory controller
//
// Coalescing Strategy:
// 1. Collect all pending read/write requests from threads
// 2. Sort requests by address (simplified: detect contiguous blocks)
// 3. Combine requests that access the same cache line or adjacent addresses
// 4. Issue combined requests to memory
// 5. Distribute results back to individual threads
//
// This implementation coalesces requests to the same address (common in GPU patterns)
// and adjacent addresses within a configurable alignment boundary.
module coalescer #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter NUM_THREADS = 4,
    parameter COALESCE_ALIGNMENT = 4  // Combine accesses within 4-byte aligned blocks
) (
    input wire clk,
    input wire reset,

    // Thread Interface (from LSUs)
    input [NUM_THREADS-1:0] thread_read_valid,
    input [ADDR_BITS-1:0] thread_read_address [NUM_THREADS-1:0],
    output reg [NUM_THREADS-1:0] thread_read_ready,
    output reg [DATA_BITS-1:0] thread_read_data [NUM_THREADS-1:0],
    
    input [NUM_THREADS-1:0] thread_write_valid,
    input [ADDR_BITS-1:0] thread_write_address [NUM_THREADS-1:0],
    input [DATA_BITS-1:0] thread_write_data [NUM_THREADS-1:0],
    output reg [NUM_THREADS-1:0] thread_write_ready,

    // Memory Interface (to controller)
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input mem_read_ready,
    input [DATA_BITS-1:0] mem_read_data,
    
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input mem_write_ready,
    
    // Statistics (for monitoring)
    output reg [$clog2(NUM_THREADS)+1:0] coalesced_count  // How many requests were coalesced
);

    // State machine
    localparam S_IDLE          = 3'b000,
               S_COLLECT       = 3'b001,
               S_COALESCE      = 3'b010,
               S_READ_REQUEST  = 3'b011,
               S_READ_WAIT     = 3'b100,
               S_WRITE_REQUEST = 3'b101,
               S_WRITE_WAIT    = 3'b110,
               S_DISTRIBUTE    = 3'b111;

    reg [2:0] state;

    // Pending request tracking
    reg [NUM_THREADS-1:0] pending_read_mask;
    reg [NUM_THREADS-1:0] pending_write_mask;
    reg [ADDR_BITS-1:0] pending_addresses [NUM_THREADS-1:0];
    reg [DATA_BITS-1:0] pending_data [NUM_THREADS-1:0];

    // Coalescing results
    reg [NUM_THREADS-1:0] coalesced_mask;  // Which threads are served by current request
    reg [ADDR_BITS-1:0] coalesced_base_addr;
    reg [DATA_BITS-1:0] coalesced_result;

    // Thread iterator
    reg [$clog2(NUM_THREADS):0] current_thread;
    reg [$clog2(NUM_THREADS):0] next_unserved;

    // Address alignment helper (get base address of alignment block)
    function [ADDR_BITS-1:0] align_address;
        input [ADDR_BITS-1:0] addr;
        begin
            // Mask off lower bits based on alignment
            align_address = addr & ~(COALESCE_ALIGNMENT - 1);
        end
    endfunction

    // Find first set bit in mask
    function automatic [$clog2(NUM_THREADS):0] find_first_set;
        input [NUM_THREADS-1:0] mask;
        integer j;
        reg found;
        begin
            find_first_set = NUM_THREADS;  // Default: none found
            found = 0;
            for (j = 0; j < NUM_THREADS; j = j + 1) begin
                if (mask[j] && !found) begin
                    find_first_set = j;
                    found = 1;
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            pending_read_mask <= 0;
            pending_write_mask <= 0;
            coalesced_mask <= 0;
            coalesced_count <= 0;
            current_thread <= 0;
            
            thread_read_ready <= 0;
            thread_read_data <= '{default: 0};
            thread_write_ready <= 0;
            
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
            
            for (int i = 0; i < NUM_THREADS; i++) begin
                pending_addresses[i] <= 0;
                pending_data[i] <= 0;
            end
        end else begin
            // Default: deassert ready signals after one cycle
            thread_read_ready <= 0;
            thread_write_ready <= 0;

            case (state)
                S_IDLE: begin
                    // Collect new requests
                    pending_read_mask <= thread_read_valid;
                    pending_write_mask <= thread_write_valid;
                    coalesced_count <= 0;
                    
                    // Capture addresses and data
                    for (int i = 0; i < NUM_THREADS; i++) begin
                        if (thread_read_valid[i]) begin
                            pending_addresses[i] <= thread_read_address[i];
                        end
                        if (thread_write_valid[i]) begin
                            pending_addresses[i] <= thread_write_address[i];
                            pending_data[i] <= thread_write_data[i];
                        end
                    end
                    
                    // Move to coalescing if any requests pending
                    if (|thread_read_valid || |thread_write_valid) begin
                        state <= S_COALESCE;
                    end
                end

                S_COALESCE: begin
                    // Find first pending request
                    if (|pending_read_mask) begin
                        // Handle reads
                        current_thread <= find_first_set(pending_read_mask);
                        coalesced_base_addr <= align_address(pending_addresses[find_first_set(pending_read_mask)]);
                        
                        // Find all threads accessing same aligned block
                        coalesced_mask <= 0;
                        for (int i = 0; i < NUM_THREADS; i++) begin
                            if (pending_read_mask[i] && 
                                align_address(pending_addresses[i]) == align_address(pending_addresses[find_first_set(pending_read_mask)])) begin
                                coalesced_mask[i] <= 1;
                            end
                        end
                        
                        state <= S_READ_REQUEST;
                    end else if (|pending_write_mask) begin
                        // Handle writes
                        current_thread <= find_first_set(pending_write_mask);
                        coalesced_base_addr <= pending_addresses[find_first_set(pending_write_mask)];
                        
                        // For writes, only coalesce exact same address (to avoid data conflicts)
                        coalesced_mask <= 0;
                        for (int i = 0; i < NUM_THREADS; i++) begin
                            if (pending_write_mask[i] && 
                                pending_addresses[i] == pending_addresses[find_first_set(pending_write_mask)]) begin
                                coalesced_mask[i] <= 1;
                            end
                        end
                        
                        state <= S_WRITE_REQUEST;
                    end else begin
                        // All requests handled
                        state <= S_IDLE;
                    end
                end

                S_READ_REQUEST: begin
                    // Issue single read for all coalesced threads
                    mem_read_valid <= 1;
                    mem_read_address <= pending_addresses[current_thread];
                    state <= S_READ_WAIT;
                    
                    // Count coalesced requests
                    coalesced_count <= 0;
                    for (int i = 0; i < NUM_THREADS; i++) begin
                        if (coalesced_mask[i]) begin
                            coalesced_count <= coalesced_count + 1;
                        end
                    end
                end

                S_READ_WAIT: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        coalesced_result <= mem_read_data;
                        state <= S_DISTRIBUTE;
                    end
                end

                S_WRITE_REQUEST: begin
                    // Issue write (use first thread's data for same-address writes)
                    mem_write_valid <= 1;
                    mem_write_address <= pending_addresses[current_thread];
                    mem_write_data <= pending_data[current_thread];
                    state <= S_WRITE_WAIT;
                end

                S_WRITE_WAIT: begin
                    if (mem_write_ready) begin
                        mem_write_valid <= 0;
                        
                        // Mark all coalesced threads as complete
                        for (int i = 0; i < NUM_THREADS; i++) begin
                            if (coalesced_mask[i]) begin
                                thread_write_ready[i] <= 1;
                            end
                        end
                        
                        // Remove served threads from pending mask
                        pending_write_mask <= pending_write_mask & ~coalesced_mask;
                        
                        // Check for more pending requests
                        state <= S_COALESCE;
                    end
                end

                S_DISTRIBUTE: begin
                    // Distribute read result to all coalesced threads
                    for (int i = 0; i < NUM_THREADS; i++) begin
                        if (coalesced_mask[i]) begin
                            thread_read_ready[i] <= 1;
                            thread_read_data[i] <= coalesced_result;
                        end
                    end
                    
                    // Remove served threads from pending mask
                    pending_read_mask <= pending_read_mask & ~coalesced_mask;
                    
                    // Check for more pending requests
                    state <= S_COALESCE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
