`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION CACHE
// > Simple direct-mapped cache for program memory (read-only)
// > Sits between Fetcher and program memory controller
// > Stores recently fetched instructions to reduce program memory traffic
// > Read-only cache - no write support needed for instruction memory
module icache #(
    parameter CACHE_LINES = 32,          // Number of cache lines
    parameter ADDR_BITS = 8,             // Address bits (256 program memory rows)
    parameter DATA_BITS = 16,            // Instruction width (16-bit instructions)
    parameter INDEX_BITS = 5,            // log2(CACHE_LINES)
    parameter TAG_BITS = 3               // ADDR_BITS - INDEX_BITS
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Interface from Fetcher
    input wire read_request,
    input wire [ADDR_BITS-1:0] address,

    // Interface to Fetcher
    output reg read_ready,
    output reg [DATA_BITS-1:0] read_data,
    output reg cache_hit_out,            // For performance monitoring

    // Interface to Program Memory Controller
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data
);
    // State machine states
    localparam IDLE = 2'b00;
    localparam MEM_READ_WAIT = 2'b01;
    localparam RETURNING = 2'b10;

    // Cache storage
    reg [DATA_BITS-1:0] cache_data [CACHE_LINES-1:0];
    reg [TAG_BITS-1:0] cache_tags [CACHE_LINES-1:0];
    reg cache_valid [CACHE_LINES-1:0];

    // Extract index and tag from address
    wire [INDEX_BITS-1:0] index = address[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] tag = address[ADDR_BITS-1:INDEX_BITS];

    // Cache hit detection
    wire cache_hit = cache_valid[index] && (cache_tags[index] == tag);

    // State register
    reg [1:0] cache_state;

    // Saved address for memory fetch
    reg [ADDR_BITS-1:0] saved_address;
    reg [INDEX_BITS-1:0] saved_index;
    reg [TAG_BITS-1:0] saved_tag;

    // Loop variable
    integer i;

    // Performance counters (optional - can be removed for synthesis)
    reg [15:0] hit_count;
    reg [15:0] miss_count;

    always @(posedge clk) begin
        if (reset) begin
            cache_state <= IDLE;
            read_ready <= 0;
            read_data <= 0;
            cache_hit_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            saved_address <= 0;
            saved_index <= 0;
            saved_tag <= 0;
            hit_count <= 0;
            miss_count <= 0;

            // Initialize cache as invalid
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                cache_valid[i] <= 0;
                cache_tags[i] <= 0;
                cache_data[i] <= 0;
            end
        end else if (enable) begin
            case (cache_state)
                IDLE: begin
                    read_ready <= 0;
                    cache_hit_out <= 0;

                    if (read_request) begin
                        if (cache_hit) begin
                            // Cache hit - return instruction immediately
                            read_data <= cache_data[index];
                            read_ready <= 1;
                            cache_hit_out <= 1;
                            hit_count <= hit_count + 1;
                        end else begin
                            // Cache miss - request from program memory
                            saved_address <= address;
                            saved_index <= index;
                            saved_tag <= tag;
                            mem_read_valid <= 1;
                            mem_read_address <= address;
                            miss_count <= miss_count + 1;
                            cache_state <= MEM_READ_WAIT;
                        end
                    end
                end

                MEM_READ_WAIT: begin
                    if (mem_read_ready) begin
                        // Store instruction in cache
                        cache_data[saved_index] <= mem_read_data;
                        cache_tags[saved_index] <= saved_tag;
                        cache_valid[saved_index] <= 1;

                        // Return instruction to fetcher
                        read_data <= mem_read_data;
                        read_ready <= 1;
                        mem_read_valid <= 0;
                        cache_state <= IDLE;
                    end
                end

                default: begin
                    cache_state <= IDLE;
                end
            endcase
        end
    end
endmodule
