`default_nettype none
`timescale 1ns/1ns

// PIPELINED FETCHER
// > Supports instruction prefetching for pipelined execution
// > Can fetch next instruction while current instruction executes
// > Maintains prefetch buffer for reduced fetch latency
module pipelined_fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PREFETCH_BUFFER_SIZE = 2  // Number of instructions to prefetch
) (
    input wire clk,
    input wire reset,

    // Core State
    input [2:0] core_state,

    // Current PC and prefetch control
    input [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input [PROGRAM_MEM_ADDR_BITS-1:0] prefetch_pc,
    input prefetch_enable,
    input pipeline_stall,  // Flush prefetch buffer on stall

    // Memory Interface
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input mem_read_ready,
    input [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Outputs
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction,
    output reg prefetch_hit  // 1 if current_pc was prefetched
);
    localparam IDLE = 3'b000,
               REQUESTING = 3'b001,
               FETCHED = 3'b010,
               PREFETCHING = 3'b011;

    // Prefetch buffer
    reg [PROGRAM_MEM_DATA_BITS-1:0] prefetch_buffer [PREFETCH_BUFFER_SIZE-1:0];
    reg [PROGRAM_MEM_ADDR_BITS-1:0] prefetch_addr [PREFETCH_BUFFER_SIZE-1:0];
    reg [PREFETCH_BUFFER_SIZE-1:0] prefetch_valid_mask;

    // Prefetch management
    reg prefetch_in_progress;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] prefetch_request_addr;
    reg [$clog2(PREFETCH_BUFFER_SIZE):0] prefetch_write_ptr;

    // Check if current_pc is in prefetch buffer
    function automatic [PREFETCH_BUFFER_SIZE-1:0] check_prefetch_hit;
        input [PROGRAM_MEM_ADDR_BITS-1:0] pc;
        integer j;
        begin
            check_prefetch_hit = 0;
            for (j = 0; j < PREFETCH_BUFFER_SIZE; j = j + 1) begin
                if (prefetch_valid_mask[j] && prefetch_addr[j] == pc) begin
                    check_prefetch_hit[j] = 1;
                end
            end
        end
    endfunction

    // Get instruction from prefetch buffer
    function automatic [PROGRAM_MEM_DATA_BITS-1:0] get_prefetched;
        input [PROGRAM_MEM_ADDR_BITS-1:0] pc;
        integer j;
        begin
            get_prefetched = 0;
            for (j = 0; j < PREFETCH_BUFFER_SIZE; j = j + 1) begin
                if (prefetch_valid_mask[j] && prefetch_addr[j] == pc) begin
                    get_prefetched = prefetch_buffer[j];
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            instruction <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            prefetch_hit <= 0;
            prefetch_valid_mask <= 0;
            prefetch_in_progress <= 0;
            prefetch_write_ptr <= 0;

            for (int i = 0; i < PREFETCH_BUFFER_SIZE; i++) begin
                prefetch_buffer[i] <= 0;
                prefetch_addr[i] <= 0;
            end
        end else begin
            // Handle pipeline stall - flush prefetch buffer
            if (pipeline_stall) begin
                prefetch_valid_mask <= 0;
                prefetch_in_progress <= 0;
                prefetch_write_ptr <= 0;
            end

            case (fetcher_state)
                IDLE: begin
                    prefetch_hit <= 0;
                    
                    // Only start fetching when core_state = FETCH
                    if (core_state == 3'b001) begin
                        // Check prefetch buffer first
                        if (|check_prefetch_hit(current_pc)) begin
                            // Prefetch hit! Use cached instruction
                            instruction <= get_prefetched(current_pc);
                            prefetch_hit <= 1;
                            
                            // Invalidate used entry
                            for (int i = 0; i < PREFETCH_BUFFER_SIZE; i++) begin
                                if (prefetch_valid_mask[i] && prefetch_addr[i] == current_pc) begin
                                    prefetch_valid_mask[i] <= 0;
                                end
                            end
                            
                            // Skip directly to FETCHED
                            fetcher_state <= FETCHED;
                        end else begin
                            // Cache miss - need to fetch from memory
                            fetcher_state <= REQUESTING;
                        end
                    end
                end

                REQUESTING: begin
                    mem_read_valid <= 1;
                    mem_read_address <= current_pc;

                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        instruction <= mem_read_data;
                        fetcher_state <= FETCHED;
                    end
                end

                FETCHED: begin
                    // Start prefetch if enabled and buffer has space
                    if (prefetch_enable && !prefetch_in_progress && 
                        prefetch_write_ptr < PREFETCH_BUFFER_SIZE) begin
                        prefetch_request_addr <= prefetch_pc;
                        prefetch_in_progress <= 1;
                        fetcher_state <= PREFETCHING;
                    end
                    // Wait for core to move to DECODE state, then reset
                    else if (core_state == 3'b010) begin
                        fetcher_state <= IDLE;
                    end
                end

                PREFETCHING: begin
                    mem_read_valid <= 1;
                    mem_read_address <= prefetch_request_addr;

                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        
                        // Store in prefetch buffer
                        prefetch_buffer[prefetch_write_ptr] <= mem_read_data;
                        prefetch_addr[prefetch_write_ptr] <= prefetch_request_addr;
                        prefetch_valid_mask[prefetch_write_ptr] <= 1;
                        prefetch_write_ptr <= prefetch_write_ptr + 1;
                        
                        prefetch_in_progress <= 0;
                        fetcher_state <= IDLE;
                    end
                end

                default: begin
                    fetcher_state <= IDLE;
                end
            endcase
        end
    end

endmodule
