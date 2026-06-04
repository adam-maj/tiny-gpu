`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// BLOCK DISPATCH
//
// Responsibilities:
// - Split kernel into blocks
// - Dispatch blocks to available cores
// - Allocate warp contexts
// - Track kernel completion
//
// Future Evolution:
// - Occupancy Management
// - Dynamic Warp Scheduling
// - Multi-Kernel Support
// - Work Stealing
// ============================================================

module block_dispatch #(
    parameter int NUM_CORES         = 2,
    parameter int THREADS_PER_BLOCK = 4,
    parameter int NUM_WARPS         = 4
)(
    input  logic clk,
    input  logic reset,
    input  logic start,

    //----------------------------------------------------------
    // Kernel Metadata
    //----------------------------------------------------------

    input  logic [7:0] thread_count,

    //----------------------------------------------------------
    // Core Interface
    //----------------------------------------------------------

    input  logic [NUM_CORES-1:0] core_done,

    output logic [NUM_CORES-1:0] core_start,
    output logic [NUM_CORES-1:0] core_reset,

    output logic [7:0] core_block_id [NUM_CORES-1:0],

    output logic [$clog2(THREADS_PER_BLOCK+1)-1:0]
                 core_thread_count [NUM_CORES-1:0],

    //----------------------------------------------------------
    // Warp Allocation Interface
    //----------------------------------------------------------

    output logic alloc_valid,
    output logic [$clog2(NUM_WARPS)-1:0] alloc_warp_id,
    output logic [31:0] alloc_pc,

    //----------------------------------------------------------
    // Completion
    //----------------------------------------------------------

    output logic done
);

    //----------------------------------------------------------
    // Internal State
    //----------------------------------------------------------

    logic [7:0] total_blocks;

    logic [7:0] blocks_dispatched;
    logic [7:0] blocks_completed;

    logic start_execution;

    logic [$clog2(NUM_WARPS)-1:0] next_warp_id;

    logic [31:0] thread_count_ext;
    logic [31:0] total_blocks_calc;

    integer i;

    //----------------------------------------------------------
    // Block Calculation
    //----------------------------------------------------------

    assign thread_count_ext = 32'(thread_count);

    assign total_blocks_calc =
        (thread_count_ext + THREADS_PER_BLOCK - 1)
        / THREADS_PER_BLOCK;

    assign total_blocks = 8'(total_blocks_calc);

    //----------------------------------------------------------
    // Dispatcher
    //----------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            done <= 1'b0;

            blocks_dispatched <= '0;
            blocks_completed  <= '0;

            start_execution <= 1'b0;

            alloc_valid   <= 1'b0;
            alloc_warp_id <= '0;
            alloc_pc      <= '0;

            next_warp_id <= '0;

            for (i = 0; i < NUM_CORES; i++) begin

                core_start[i] <= 1'b0;
                core_reset[i] <= 1'b1;

                core_block_id[i] <= '0;

                core_thread_count[i]
                    <= $clog2(THREADS_PER_BLOCK+1)'(
                        THREADS_PER_BLOCK
                    );

            end

        end
        else begin

            alloc_valid <= 1'b0;

            //--------------------------------------------------
            // Waiting For Launch
            //--------------------------------------------------

            if (!start) begin

                done <= 1'b0;
                start_execution <= 1'b0;

            end

            //--------------------------------------------------
            // Active Kernel
            //--------------------------------------------------

            else begin

                //----------------------------------------------
                // First Launch
                //----------------------------------------------

                if (!start_execution) begin

                    start_execution <= 1'b1;

                    blocks_dispatched <= '0;
                    blocks_completed  <= '0;

                    next_warp_id <= '0;

                    for (i = 0; i < NUM_CORES; i++) begin

                        core_start[i] <= 1'b0;
                        core_reset[i] <= 1'b1;

                    end

                end

                //----------------------------------------------
                // Kernel Complete
                //----------------------------------------------

                if ((total_blocks != 0) &&
                    (blocks_completed >= total_blocks)) begin

                    done <= 1'b1;

                end

                //----------------------------------------------
                // Dispatch Work
                //----------------------------------------------

                for (i = 0; i < NUM_CORES; i++) begin

                    if (core_reset[i]) begin

                        core_reset[i] <= 1'b0;

                        if (blocks_dispatched < total_blocks) begin

                            core_start[i] <= 1'b1;

                            core_block_id[i]
                                <= blocks_dispatched;

                            //----------------------------------
                            // Last Partial Block
                            //----------------------------------

                            if (blocks_dispatched ==
                                (total_blocks - 1)) begin

                                core_thread_count[i]
                                    <= $clog2(THREADS_PER_BLOCK+1)'(
                                           thread_count_ext -
                                           (blocks_dispatched *
                                            THREADS_PER_BLOCK)
                                       );

                            end

                            //----------------------------------
                            // Full Block
                            //----------------------------------

                            else begin

                                core_thread_count[i]
                                    <= $clog2(THREADS_PER_BLOCK+1)'(
                                           THREADS_PER_BLOCK
                                       );

                            end

                            //----------------------------------
                            // Warp Allocation
                            //----------------------------------

                            alloc_valid   <= 1'b1;
                            alloc_warp_id <= next_warp_id;
                            alloc_pc      <= RESET_PC;

                            next_warp_id <= next_warp_id + 1'b1;

                            //----------------------------------
                            // Accounting
                            //----------------------------------

                            blocks_dispatched
                                <= blocks_dispatched + 1'b1;

                        end

                    end

                end

                //----------------------------------------------
                // Completion Tracking
                //----------------------------------------------

                for (i = 0; i < NUM_CORES; i++) begin

                    if (core_start[i] &&
                        core_done[i]) begin

                        core_start[i] <= 1'b0;
                        core_reset[i] <= 1'b1;

                        blocks_completed
                            <= blocks_completed + 1'b1;

                    end

                end

            end

        end

    end

endmodule

`default_nettype wire