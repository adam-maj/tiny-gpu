`default_nettype none
`timescale 1ns/1ns

// GPU
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control register before the start signal is triggered
// > Has memory controllers to interface between external memory and its multiple cores
// > Configurable number of cores and thread capacity per core
module gpu #(
    parameter DATA_MEM_ADDR_BITS = 8,        // Number of bits in data memory address (256 rows)
    parameter DATA_MEM_DATA_BITS = 8,        // Number of bits in data memory value (8 bit data)
    parameter DATA_MEM_NUM_CHANNELS = 4,     // Number of concurrent channels for sending requests to data memory
    parameter PROGRAM_MEM_ADDR_BITS = 8,     // Number of bits in program memory address (256 rows)
    parameter PROGRAM_MEM_DATA_BITS = 16,    // Number of bits in program memory value (16 bit instruction)
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,  // Number of concurrent channels for sending requests to program memory
    parameter NUM_CORES = 2,                 // Number of cores to include in this GPU
    parameter THREADS_PER_BLOCK = 4,         // Number of threads to handle per block (determines the compute resources of each core)

    // Multi-layered cache: each core has a private L1 in front of a GPU-wide shared L2, which
    // itself sits in front of the external-memory controller/channels above.
    parameter L1_NUM_CHANNELS = 2,           // Concurrent outstanding misses each core's L1 can track
    parameter L1_NUM_SETS = 4,               // L1 sets (per core)
    parameter L1_WAYS = 2,                   // L1 associativity (per core)
    parameter L1_LINE_SIZE = 4,              // L1 words per line (per core)
    parameter L2_NUM_CHANNELS = DATA_MEM_NUM_CHANNELS, // Concurrent outstanding misses the shared L2 can track
    parameter L2_NUM_SETS = 8,               // L2 sets (shared)
    parameter L2_WAYS = 2,                   // L2 associativity (shared)
    parameter L2_LINE_SIZE = 4,              // L2 words per line (shared)

    // Shared memory: on-chip per-block scratchpad, local to each core
    parameter SHARED_MEM_ADDR_BITS = 6
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Device Control Register
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Program Memory
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0],
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0],

    // Data Memory
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0],
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready,

    // Cache profiling / observability
    output wire [31:0] l1_hit_count [NUM_CORES-1:0],
    output wire [31:0] l1_miss_count [NUM_CORES-1:0],
    output wire [31:0] l2_hit_count,
    output wire [31:0] l2_miss_count
);
    // Control
    wire [7:0] thread_count;

    // Compute Core State
    reg [NUM_CORES-1:0] core_start;
    reg [NUM_CORES-1:0] core_reset;
    reg [NUM_CORES-1:0] core_done;
    reg [7:0] core_block_id [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];

    // L1 (per-core) <> L2 (shared) Cache Channels
    localparam L1_TOTAL_CHANNELS = NUM_CORES * L1_NUM_CHANNELS;
    reg [L1_TOTAL_CHANNELS-1:0] l1_mem_read_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] l1_mem_read_address [L1_TOTAL_CHANNELS-1:0];
    reg [L1_TOTAL_CHANNELS-1:0] l1_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] l1_mem_read_data [L1_TOTAL_CHANNELS-1:0];
    reg [L1_TOTAL_CHANNELS-1:0] l1_mem_write_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] l1_mem_write_address [L1_TOTAL_CHANNELS-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] l1_mem_write_data [L1_TOTAL_CHANNELS-1:0];
    reg [L1_TOTAL_CHANNELS-1:0] l1_mem_write_ready;

    // L2 (shared) Cache <> Data Memory Controller Channels
    reg [L2_NUM_CHANNELS-1:0] l2_mem_read_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] l2_mem_read_address [L2_NUM_CHANNELS-1:0];
    reg [L2_NUM_CHANNELS-1:0] l2_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] l2_mem_read_data [L2_NUM_CHANNELS-1:0];
    reg [L2_NUM_CHANNELS-1:0] l2_mem_write_valid;
    reg [DATA_MEM_ADDR_BITS-1:0] l2_mem_write_address [L2_NUM_CHANNELS-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] l2_mem_write_data [L2_NUM_CHANNELS-1:0];
    reg [L2_NUM_CHANNELS-1:0] l2_mem_write_ready;

    // Fetcher <> Program Memory Controller Channels
    localparam NUM_FETCHERS = NUM_CORES;
    reg [NUM_FETCHERS-1:0] fetcher_read_valid;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    reg [NUM_FETCHERS-1:0] fetcher_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];
    
    // Device Control Register
    dcr dcr_instance (
        .clk(clk),
        .reset(reset),

        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // Shared L2 Cache - sits between every core's private L1 and the memory controller
    cache #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(L1_TOTAL_CHANNELS),
        .NUM_CHANNELS(L2_NUM_CHANNELS),
        .NUM_SETS(L2_NUM_SETS),
        .WAYS(L2_WAYS),
        .LINE_SIZE(L2_LINE_SIZE)
    ) l2_cache_instance (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(l1_mem_read_valid),
        .consumer_read_address(l1_mem_read_address),
        .consumer_read_ready(l1_mem_read_ready),
        .consumer_read_data(l1_mem_read_data),
        .consumer_write_valid(l1_mem_write_valid),
        .consumer_write_address(l1_mem_write_address),
        .consumer_write_data(l1_mem_write_data),
        .consumer_write_ready(l1_mem_write_ready),

        .mem_read_valid(l2_mem_read_valid),
        .mem_read_address(l2_mem_read_address),
        .mem_read_ready(l2_mem_read_ready),
        .mem_read_data(l2_mem_read_data),
        .mem_write_valid(l2_mem_write_valid),
        .mem_write_address(l2_mem_write_address),
        .mem_write_data(l2_mem_write_data),
        .mem_write_ready(l2_mem_write_ready),

        .hit_count(l2_hit_count),
        .miss_count(l2_miss_count)
    );

    // Data Memory Controller
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(L2_NUM_CHANNELS),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_memory_controller (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(l2_mem_read_valid),
        .consumer_read_address(l2_mem_read_address),
        .consumer_read_ready(l2_mem_read_ready),
        .consumer_read_data(l2_mem_read_data),
        .consumer_write_valid(l2_mem_write_valid),
        .consumer_write_address(l2_mem_write_address),
        .consumer_write_data(l2_mem_write_data),
        .consumer_write_ready(l2_mem_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address(data_mem_write_address),
        .mem_write_data(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );

    // Program Memory Controller
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_FETCHERS),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .WRITE_ENABLE(0)
    ) program_memory_controller (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address(fetcher_read_address),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data(fetcher_read_data),

        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
    );

    // Dispatcher
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatch_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset),
        .core_block_id(core_block_id),
        .core_thread_count(core_thread_count),
        .done(done)
    );

    // Compute Cores
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            // EDA: We create separate signals here to pass to cores because of a requirement
            // by the OpenLane EDA flow (uses Verilog 2005) that prevents slicing the top-level signals
            reg [THREADS_PER_BLOCK-1:0] core_lsu_read_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_lsu_read_address [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_read_ready;
            reg [DATA_MEM_DATA_BITS-1:0] core_lsu_read_data [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_write_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_lsu_write_address [THREADS_PER_BLOCK-1:0];
            reg [DATA_MEM_DATA_BITS-1:0] core_lsu_write_data [THREADS_PER_BLOCK-1:0];
            reg [THREADS_PER_BLOCK-1:0] core_lsu_write_ready;

            // L1 Cache <> L2 Cache channels for this core
            reg [L1_NUM_CHANNELS-1:0] core_l1_mem_read_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_l1_mem_read_address [L1_NUM_CHANNELS-1:0];
            reg [L1_NUM_CHANNELS-1:0] core_l1_mem_read_ready;
            reg [DATA_MEM_DATA_BITS-1:0] core_l1_mem_read_data [L1_NUM_CHANNELS-1:0];
            reg [L1_NUM_CHANNELS-1:0] core_l1_mem_write_valid;
            reg [DATA_MEM_ADDR_BITS-1:0] core_l1_mem_write_address [L1_NUM_CHANNELS-1:0];
            reg [DATA_MEM_DATA_BITS-1:0] core_l1_mem_write_data [L1_NUM_CHANNELS-1:0];
            reg [L1_NUM_CHANNELS-1:0] core_l1_mem_write_ready;

            wire [31:0] core_l1_hit_count;
            wire [31:0] core_l1_miss_count;

            // Pass through signals between this core's L1 cache and the shared L2 cache
            genvar k;
            for (k = 0; k < L1_NUM_CHANNELS; k = k + 1) begin
                localparam l1_channel_index = i * L1_NUM_CHANNELS + k;
                always @(posedge clk) begin
                    l1_mem_read_valid[l1_channel_index] <= core_l1_mem_read_valid[k];
                    l1_mem_read_address[l1_channel_index] <= core_l1_mem_read_address[k];

                    l1_mem_write_valid[l1_channel_index] <= core_l1_mem_write_valid[k];
                    l1_mem_write_address[l1_channel_index] <= core_l1_mem_write_address[k];
                    l1_mem_write_data[l1_channel_index] <= core_l1_mem_write_data[k];

                    core_l1_mem_read_ready[k] <= l1_mem_read_ready[l1_channel_index];
                    core_l1_mem_read_data[k] <= l1_mem_read_data[l1_channel_index];
                    core_l1_mem_write_ready[k] <= l1_mem_write_ready[l1_channel_index];
                end
            end

            assign l1_hit_count[i] = core_l1_hit_count;
            assign l1_miss_count[i] = core_l1_miss_count;

            // L1 Cache (private to this core) - flushed whenever this core is handed a new block
            cache #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS),
                .NUM_CONSUMERS(THREADS_PER_BLOCK),
                .NUM_CHANNELS(L1_NUM_CHANNELS),
                .NUM_SETS(L1_NUM_SETS),
                .WAYS(L1_WAYS),
                .LINE_SIZE(L1_LINE_SIZE)
            ) l1_cache_instance (
                .clk(clk),
                .reset(core_reset[i]),

                .consumer_read_valid(core_lsu_read_valid),
                .consumer_read_address(core_lsu_read_address),
                .consumer_read_ready(core_lsu_read_ready),
                .consumer_read_data(core_lsu_read_data),
                .consumer_write_valid(core_lsu_write_valid),
                .consumer_write_address(core_lsu_write_address),
                .consumer_write_data(core_lsu_write_data),
                .consumer_write_ready(core_lsu_write_ready),

                .mem_read_valid(core_l1_mem_read_valid),
                .mem_read_address(core_l1_mem_read_address),
                .mem_read_ready(core_l1_mem_read_ready),
                .mem_read_data(core_l1_mem_read_data),
                .mem_write_valid(core_l1_mem_write_valid),
                .mem_write_address(core_l1_mem_write_address),
                .mem_write_data(core_l1_mem_write_data),
                .mem_write_ready(core_l1_mem_write_ready),

                .hit_count(core_l1_hit_count),
                .miss_count(core_l1_miss_count)
            );

            // Compute Core
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .SHARED_MEM_ADDR_BITS(SHARED_MEM_ADDR_BITS),
            ) core_instance (
                .clk(clk),
                .reset(core_reset[i]),
                .start(core_start[i]),
                .done(core_done[i]),
                .block_id(core_block_id[i]),
                .thread_count(core_thread_count[i]),
                
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),

                .data_mem_read_valid(core_lsu_read_valid),
                .data_mem_read_address(core_lsu_read_address),
                .data_mem_read_ready(core_lsu_read_ready),
                .data_mem_read_data(core_lsu_read_data),
                .data_mem_write_valid(core_lsu_write_valid),
                .data_mem_write_address(core_lsu_write_address),
                .data_mem_write_data(core_lsu_write_data),
                .data_mem_write_ready(core_lsu_write_ready)
            );
        end
    endgenerate
endmodule
