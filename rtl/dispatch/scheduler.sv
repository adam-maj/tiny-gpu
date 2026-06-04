`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// CORE SCHEDULER
//
// Controls execution flow for a compute core.
//
// Pipeline:
//
//   FETCH
//     |
//   DECODE
//     |
//   REQUEST
//     |
//   WAIT
//     |
//   EXECUTE
//     |
//   UPDATE
//
// Future Evolution:
// - Instruction Cache
// - Pipeline Stages
// - Branch Divergence
// - Warp Scheduling
// - Scoreboarding
// ============================================================

module scheduler #(
    parameter int THREADS_PER_BLOCK = 4,
    parameter int PC_WIDTH          = 8
)(
    input  logic clk,
    input  logic reset,
    input  logic start,

    //----------------------------------------------------------
    // Decode Outputs
    //----------------------------------------------------------

    input  logic decoded_mem_read_enable,
    input  logic decoded_mem_write_enable,
    input  logic decoded_ret,

    //----------------------------------------------------------
    // Fetch State
    //----------------------------------------------------------

    input  fetcher_state_t fetcher_state,

    //----------------------------------------------------------
    // LSU State
    //----------------------------------------------------------

    input  lsu_state_t lsu_state [THREADS_PER_BLOCK-1:0],

    //----------------------------------------------------------
    // Program Counter
    //----------------------------------------------------------

    output logic [PC_WIDTH-1:0] current_pc,
    input  logic [PC_WIDTH-1:0] next_pc [THREADS_PER_BLOCK-1:0],

    //----------------------------------------------------------
    // Core State
    //----------------------------------------------------------

    output core_state_t core_state,
    output logic done
);

    logic any_lsu_waiting;

    integer i;

    //----------------------------------------------------------
    // LSU Completion Detection
    //----------------------------------------------------------

    always_comb begin

        any_lsu_waiting = 1'b0;

        for (i = 0; i < THREADS_PER_BLOCK; i++) begin

            if ((lsu_state[i] == LSU_REQUESTING) ||
                (lsu_state[i] == LSU_WAITING)) begin

                any_lsu_waiting = 1'b1;

            end

        end

    end

    //----------------------------------------------------------
    // Scheduler FSM
    //----------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            current_pc <= '0;
            core_state <= CORE_IDLE;
            done       <= 1'b0;

        end
        else begin

            case (core_state)

                //----------------------------------------------
                // IDLE
                //----------------------------------------------

                CORE_IDLE: begin

                    done <= 1'b0;

                    if (start) begin
                        current_pc <= RESET_PC[PC_WIDTH-1:0];
                        core_state <= CORE_FETCH;
                    end

                end

                //----------------------------------------------
                // FETCH
                //----------------------------------------------

                CORE_FETCH: begin

                    if (fetcher_state == FETCHER_FETCHED) begin
                        core_state <= CORE_DECODE;
                    end

                end

                //----------------------------------------------
                // DECODE
                //----------------------------------------------

                CORE_DECODE: begin

                    core_state <= CORE_REQUEST;

                end

                //----------------------------------------------
                // REQUEST
                //----------------------------------------------

                CORE_REQUEST: begin

                    if (decoded_mem_read_enable ||
                        decoded_mem_write_enable) begin

                        core_state <= CORE_WAIT;

                    end
                    else begin

                        core_state <= CORE_EXECUTE;

                    end

                end

                //----------------------------------------------
                // WAIT
                //----------------------------------------------

                CORE_WAIT: begin

                    if (!any_lsu_waiting) begin
                        core_state <= CORE_EXECUTE;
                    end

                end

                //----------------------------------------------
                // EXECUTE
                //----------------------------------------------

                CORE_EXECUTE: begin

                    core_state <= CORE_UPDATE;

                end

                //----------------------------------------------
                // UPDATE
                //----------------------------------------------

                CORE_UPDATE: begin

                    if (decoded_ret) begin

                        done <= 1'b1;
                        core_state <= CORE_DONE;

                    end
                    else begin

                        // Branch divergence not yet supported.
                        // Assume all thread PCs converge.

                        current_pc <= next_pc[0];
                        core_state <= CORE_FETCH;

                    end

                end

                //----------------------------------------------
                // DONE
                //----------------------------------------------

                CORE_DONE: begin

                    if (!start) begin
                        core_state <= CORE_IDLE;
                    end

                end

                //----------------------------------------------
                // RECOVERY
                //----------------------------------------------

                default: begin

                    current_pc <= '0;
                    core_state <= CORE_IDLE;
                    done       <= 1'b0;

                end

            endcase

        end

    end

endmodule

`default_nettype wire