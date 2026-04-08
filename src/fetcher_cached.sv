`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER WITH CACHE
// > Retrieves the instruction at the current PC from program memory via instruction cache
// > Each core has its own fetcher with integrated instruction cache
// > Cache improves performance when executing loops (same instructions fetched multiple times)
module fetcher_cached #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter CACHE_LINES = 32,
    parameter INDEX_BITS = 5,
    parameter TAG_BITS = 3
) (
    input wire clk,
    input wire reset,

    // Execution State
    input [2:0] core_state,
    input [7:0] current_pc,

    // Program Memory (to memory controller)
    output wire mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input mem_read_ready,
    input [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction,

    // Cache statistics (optional)
    output wire cache_hit
);
    localparam IDLE = 3'b000,
        FETCHING = 3'b001,
        FETCHED = 3'b010;

    // Internal signals for cache interface
    reg cache_read_request;
    wire cache_read_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] cache_read_data;
    wire cache_hit_signal;

    // Instantiate instruction cache
    icache #(
        .CACHE_LINES(CACHE_LINES),
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .INDEX_BITS(INDEX_BITS),
        .TAG_BITS(TAG_BITS)
    ) icache_inst (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),

        // Fetcher interface
        .read_request(cache_read_request),
        .address(current_pc),
        .read_ready(cache_read_ready),
        .read_data(cache_read_data),
        .cache_hit_out(cache_hit_signal),

        // Memory controller interface
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );

    assign cache_hit = cache_hit_signal;

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            cache_read_request <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    // Start fetching when core_state = FETCH
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        cache_read_request <= 1;
                    end
                end
                FETCHING: begin
                    // Wait for response from cache (hit or miss)
                    if (cache_read_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= cache_read_data;
                        cache_read_request <= 0;
                    end
                end
                FETCHED: begin
                    // Reset when core_state = DECODE
                    if (core_state == 3'b010) begin
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
