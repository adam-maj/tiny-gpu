`default_nettype none
`timescale 1ns/1ns

// DATA CACHE
// > Write-back cache for data memory accesses
// > Direct-mapped cache with configurable size
// > Reduces memory latency for repeated accesses
module dcache #(
    parameter ADDR_BITS = 8,           // Address width
    parameter DATA_BITS = 8,           // Data width
    parameter CACHE_SIZE = 16,         // Number of cache lines
    parameter LINE_SIZE = 1            // Words per cache line
) (
    input wire clk,
    input wire reset,
    
    // CPU interface
    input wire cpu_read_valid,
    input wire [ADDR_BITS-1:0] cpu_read_addr,
    output reg cpu_read_ready,
    output reg [DATA_BITS-1:0] cpu_read_data,
    
    input wire cpu_write_valid,
    input wire [ADDR_BITS-1:0] cpu_write_addr,
    input wire [DATA_BITS-1:0] cpu_write_data,
    output reg cpu_write_ready,
    
    // Memory interface
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_addr,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,
    
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_addr,
    output reg [DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready,
    
    // Status
    output wire busy,
    output reg [15:0] hits,
    output reg [15:0] misses
);
    localparam INDEX_BITS = $clog2(CACHE_SIZE);
    localparam TAG_BITS = ADDR_BITS - INDEX_BITS;
    
    // Cache storage
    reg [DATA_BITS-1:0] cache_data [CACHE_SIZE-1:0];
    reg [TAG_BITS-1:0] cache_tag [CACHE_SIZE-1:0];
    reg cache_valid [CACHE_SIZE-1:0];
    reg cache_dirty [CACHE_SIZE-1:0];
    
    // State machine
    localparam S_IDLE = 3'd0;
    localparam S_READ_HIT = 3'd1;
    localparam S_WRITE_HIT = 3'd2;
    localparam S_WRITEBACK = 3'd3;
    localparam S_FILL = 3'd4;
    localparam S_WRITE_FILL = 3'd5;
    
    reg [2:0] state;
    reg [ADDR_BITS-1:0] pending_addr;
    reg [DATA_BITS-1:0] pending_data;
    reg pending_is_write;
    
    // Address decoding
    wire [INDEX_BITS-1:0] cpu_index = cpu_read_valid ? cpu_read_addr[INDEX_BITS-1:0] : cpu_write_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] cpu_tag = cpu_read_valid ? cpu_read_addr[ADDR_BITS-1:INDEX_BITS] : cpu_write_addr[ADDR_BITS-1:INDEX_BITS];
    wire [INDEX_BITS-1:0] pending_index = pending_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] pending_tag = pending_addr[ADDR_BITS-1:INDEX_BITS];
    
    // Hit detection
    wire tag_match = cache_valid[cpu_index] && (cache_tag[cpu_index] == cpu_tag);
    wire read_hit = cpu_read_valid && tag_match;
    wire write_hit = cpu_write_valid && tag_match;
    
    assign busy = (state != S_IDLE);
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            cpu_read_ready <= 0;
            cpu_write_ready <= 0;
            mem_read_valid <= 0;
            mem_write_valid <= 0;
            hits <= 0;
            misses <= 0;
            pending_addr <= 0;
            pending_data <= 0;
            pending_is_write <= 0;
            
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                cache_valid[i] <= 0;
                cache_dirty[i] <= 0;
                cache_tag[i] <= 0;
                cache_data[i] <= 0;
            end
        end else begin
            // Default outputs
            cpu_read_ready <= 0;
            cpu_write_ready <= 0;
            
            case (state)
                S_IDLE: begin
                    if (cpu_read_valid) begin
                        if (read_hit) begin
                            // Cache hit - return data immediately
                            cpu_read_data <= cache_data[cpu_index];
                            cpu_read_ready <= 1;
                            hits <= hits + 1;
                        end else begin
                            // Cache miss
                            misses <= misses + 1;
                            pending_addr <= cpu_read_addr;
                            pending_is_write <= 0;
                            
                            if (cache_valid[cpu_index] && cache_dirty[cpu_index]) begin
                                // Need to write back dirty line first
                                mem_write_valid <= 1;
                                mem_write_addr <= {cache_tag[cpu_index], cpu_index};
                                mem_write_data <= cache_data[cpu_index];
                                state <= S_WRITEBACK;
                            end else begin
                                // Clean miss - fetch from memory
                                mem_read_valid <= 1;
                                mem_read_addr <= cpu_read_addr;
                                state <= S_FILL;
                            end
                        end
                    end else if (cpu_write_valid) begin
                        if (write_hit) begin
                            // Write hit - update cache
                            cache_data[cpu_index] <= cpu_write_data;
                            cache_dirty[cpu_index] <= 1;
                            cpu_write_ready <= 1;
                            hits <= hits + 1;
                        end else begin
                            // Write miss - allocate line
                            misses <= misses + 1;
                            pending_addr <= cpu_write_addr;
                            pending_data <= cpu_write_data;
                            pending_is_write <= 1;
                            
                            if (cache_valid[cpu_index] && cache_dirty[cpu_index]) begin
                                // Write back dirty line
                                mem_write_valid <= 1;
                                mem_write_addr <= {cache_tag[cpu_index], cpu_index};
                                mem_write_data <= cache_data[cpu_index];
                                state <= S_WRITEBACK;
                            end else begin
                                // Write-allocate: fetch line then write
                                mem_read_valid <= 1;
                                mem_read_addr <= cpu_write_addr;
                                state <= S_WRITE_FILL;
                            end
                        end
                    end
                end
                
                S_WRITEBACK: begin
                    if (mem_write_ready) begin
                        mem_write_valid <= 0;
                        cache_dirty[pending_index] <= 0;
                        
                        // Now fetch the new line
                        mem_read_valid <= 1;
                        mem_read_addr <= pending_addr;
                        state <= pending_is_write ? S_WRITE_FILL : S_FILL;
                    end
                end
                
                S_FILL: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        
                        // Update cache
                        cache_data[pending_index] <= mem_read_data;
                        cache_tag[pending_index] <= pending_tag;
                        cache_valid[pending_index] <= 1;
                        cache_dirty[pending_index] <= 0;
                        
                        // Return data to CPU
                        cpu_read_data <= mem_read_data;
                        cpu_read_ready <= 1;
                        state <= S_IDLE;
                    end
                end
                
                S_WRITE_FILL: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        
                        // Update cache with write data (write-allocate)
                        cache_data[pending_index] <= pending_data;
                        cache_tag[pending_index] <= pending_tag;
                        cache_valid[pending_index] <= 1;
                        cache_dirty[pending_index] <= 1;
                        
                        cpu_write_ready <= 1;
                        state <= S_IDLE;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
