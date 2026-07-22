`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION CACHE
// > Sits between each core's fetcher and the shared program memory controller
// > Direct-mapped cache: PC address bits split into { tag | index }
// > On a HIT, the instruction is returned combinationally straight from the cache
//   line - faster than a full memory-controller round trip, and the shared program
//   memory controller/channel is never touched at all.
// > On a MISS, the request is wired straight through to the memory controller
//   (zero added latency vs not having a cache) while the response is snooped and
//   stored for next time.
// > This directly targets loop-heavy kernels (e.g. matmul's inner dot-product loop)
//   where the same handful of instructions are re-fetched every iteration - see
//   test/test_icache.py for a hit/miss-rate regression test.
module icache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter CACHE_LINES = 16 // Must be a power of 2
) (
    input wire clk,
    input wire reset,

    // Fetcher-facing interface (upstream) - behaves exactly like a single-channel
    // memory controller from the fetcher's point of view, just faster on a hit
    input wire consumer_read_valid,
    input wire [ADDR_BITS-1:0] consumer_read_address,
    output wire consumer_read_ready,
    output wire [DATA_BITS-1:0] consumer_read_data,

    // Program-memory-controller-facing interface (downstream) - only driven on a miss
    output wire mem_read_valid,
    output wire [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,

    // Stats - pulse high for exactly 1 cycle per resolved request, exposed for the
    // live dashboard & tests (see test/test_icache.py)
    output reg hit,
    output reg miss
);
    localparam INDEX_BITS = $clog2(CACHE_LINES);
    localparam TAG_BITS = ADDR_BITS - INDEX_BITS;

    reg [DATA_BITS-1:0] lines [CACHE_LINES-1:0];
    reg [TAG_BITS-1:0] tags [CACHE_LINES-1:0];
    reg line_valid [CACHE_LINES-1:0];

    wire [INDEX_BITS-1:0] req_index = consumer_read_address[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] req_tag = consumer_read_address[ADDR_BITS-1:INDEX_BITS];

    // Combinational hit/miss classification of whatever address is currently pending
    wire cache_hit = consumer_read_valid && line_valid[req_index] && (tags[req_index] == req_tag);
    wire cache_miss = consumer_read_valid && !cache_hit;

    // HIT: respond immediately from the cache line, no controller round trip.
    // MISS: transparently forward to the memory controller (pure wire pass-through,
    // so a miss costs exactly what it would without a cache at all) and snoop the
    // eventual response below to fill the line for next time.
    assign mem_read_valid = cache_miss;
    assign mem_read_address = consumer_read_address;
    assign consumer_read_ready = cache_hit || mem_read_ready;
    assign consumer_read_data = cache_hit ? lines[req_index] : mem_read_data;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            hit <= 0;
            miss <= 0;
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                line_valid[i] <= 0;
            end
        end else begin
            // Stat pulses reflect the request being resolved this exact cycle
            hit <= cache_hit;
            miss <= cache_miss && mem_read_ready;

            if (cache_miss && mem_read_ready) begin
                line_valid[req_index] <= 1;
                tags[req_index] <= req_tag;
                lines[req_index] <= mem_read_data;
            end
        end
    end
endmodule
