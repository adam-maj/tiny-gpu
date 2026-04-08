`default_nettype none
`timescale 1ns/1ns

// CACHE
// > Simple direct-mapped cache for data memory
// > Sits between LSU and memory controller
// > Stores recently accessed data to reduce global memory traffic
module cache #(
    parameter CACHE_LINES = 64,
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter INDEX_BITS = 6,  // log2(CACHE_LINES)
    parameter TAG_BITS = 2     // ADDR_BITS - INDEX_BITS
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Interface from LSU
    input wire read_request,
    input wire write_request,
    input wire [ADDR_BITS-1:0] address,
    input wire [DATA_BITS-1:0] write_data,

    // Interface to LSU
    output reg read_ready,
    output reg write_ready,
    output reg [DATA_BITS-1:0] read_data,

    // Interface to Memory Controller
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready
);
    // State machine states
    localparam IDLE = 2'b00;
    localparam MEM_READ_WAIT = 2'b01;
    localparam MEM_WRITE_WAIT = 2'b10;

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

    // Loop variable
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            cache_state <= IDLE;
            read_ready <= 0;
            write_ready <= 0;
            read_data <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

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
                    write_ready <= 0;

                    if (read_request) begin
                        if (cache_hit) begin
                            // Cache hit - return data immediately
                            read_data <= cache_data[index];
                            read_ready <= 1;
                        end else begin
                            // Cache miss - request from memory
                            mem_read_valid <= 1;
                            mem_read_address <= address;
                            cache_state <= MEM_READ_WAIT;
                        end
                    end else if (write_request) begin
                        // Write-through: update cache and write to memory
                        cache_data[index] <= write_data;
                        cache_tags[index] <= tag;
                        cache_valid[index] <= 1;

                        mem_write_valid <= 1;
                        mem_write_address <= address;
                        mem_write_data <= write_data;
                        cache_state <= MEM_WRITE_WAIT;
                    end
                end

                MEM_READ_WAIT: begin
                    if (mem_read_ready) begin
                        // Store data in cache
                        cache_data[index] <= mem_read_data;
                        cache_tags[index] <= tag;
                        cache_valid[index] <= 1;

                        // Return data to LSU
                        read_data <= mem_read_data;
                        read_ready <= 1;
                        mem_read_valid <= 0;
                        cache_state <= IDLE;
                    end
                end

                MEM_WRITE_WAIT: begin
                    if (mem_write_ready) begin
                        write_ready <= 1;
                        mem_write_valid <= 0;
                        cache_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
