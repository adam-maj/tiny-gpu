`default_nettype none
`timescale 1ns/1ns

// SHARED MEMORY (per-block scratchpad)
// > A single on-chip memory local to one core, directly addressable by every thread in the block
//   the core is currently processing - unlike global memory, it never round-trips through the
//   cache hierarchy or external memory controller, so it's much lower latency for threads to
//   exchange data with each other.
// > Contents are not preserved across blocks: the core resets this module (along with the rest of
//   its state) whenever it's handed a new block, matching real GPUs where shared memory contents
//   are undefined at the start of a block.
// > Supports THREADS_PER_BLOCK simultaneous read ports and THREADS_PER_BLOCK simultaneous write
//   ports (one pair per thread) since all threads in a block run on the same core and may need to
//   access shared memory in the same cycle. If two threads write the same address in the same
//   cycle, the highest-indexed thread's write wins (real hardware also leaves this undefined).
module shared_memory #(
    parameter DATA_BITS = 8,
    parameter ADDR_BITS = 6,           // Shared memory is intentionally small (2**ADDR_BITS words)
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,

    input reg [THREADS_PER_BLOCK-1:0] read_valid,
    input reg [ADDR_BITS-1:0] read_address [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0] read_ready,
    output reg [DATA_BITS-1:0] read_data [THREADS_PER_BLOCK-1:0],

    input reg [THREADS_PER_BLOCK-1:0] write_valid,
    input reg [ADDR_BITS-1:0] write_address [THREADS_PER_BLOCK-1:0],
    input reg [DATA_BITS-1:0] write_data [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0] write_ready
);
    reg [DATA_BITS-1:0] mem [(2**ADDR_BITS)-1:0];

    always @(posedge clk) begin
        if (reset) begin
            read_ready <= 0;
            read_data <= 0;
            write_ready <= 0;
        end else begin
            for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                if (read_valid[i]) begin
                    read_data[i] <= mem[read_address[i]];
                    read_ready[i] <= 1;
                end else begin
                    read_ready[i] <= 0;
                end

                if (write_valid[i]) begin
                    mem[write_address[i]] <= write_data[i];
                    write_ready[i] <= 1;
                end else begin
                    write_ready[i] <= 0;
                end
            end
        end
    end
endmodule
