`default_nettype none
`timescale 1ns/1ns

// BLOCK DISPATCH
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores
module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    // Core States
    input reg [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel Execution
    output reg done
);
    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Keep track of how many blocks have been processed
    reg [7:0] blocks_dispatched; // How many blocks have been sent to cores?
    reg [7:0] blocks_done; // How many blocks have finished processing?
    reg start_execution; // EDA: Unimportant hack used because of EDA tooling

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched = 0;
            blocks_done = 0;
            start_execution <= 0;

            for (int i = 0; i < NUM_CORES; i++) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;
                core_block_id[i] <= 0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (start) begin    
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin 
                start_execution <= 1;
                for (int i = 0; i < NUM_CORES; i++) begin
                    core_reset[i] <= 1;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin 
                done <= 1;
            end

            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_reset[i]) begin 
                    core_reset[i] <= 0;

                    // If this core was just reset, check if there are more blocks to be dispatched
                    if (blocks_dispatched < total_blocks) begin 
                        core_start[i] <= 1;
                        core_block_id[i] <= blocks_dispatched;
                        core_thread_count[i] <= (blocks_dispatched == total_blocks - 1) 
                            ? thread_count - (blocks_dispatched * THREADS_PER_BLOCK)
                            : THREADS_PER_BLOCK;

                        blocks_dispatched = blocks_dispatched + 1;
                    end
                end
            end

            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_start[i] && core_done[i]) begin
                    // If a core just finished executing it's current block, reset it
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    blocks_done = blocks_done + 1;
                end
            end
        end
    end
endmodule