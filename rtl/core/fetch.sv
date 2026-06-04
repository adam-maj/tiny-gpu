`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// INSTRUCTION FETCH UNIT
//
// Responsible for retrieving instructions from program memory.
//
// Current Behavior:
//   CORE_FETCH
//       |
//       v
//   Issue Memory Request
//       |
//       v
//   Wait For Response
//       |
//       v
//   Deliver Instruction
//
// Future Evolution:
//   - Instruction Cache
//   - Prefetch Queue
//   - Branch Prediction
//   - Speculative Fetch
// ============================================================

module fetch #(
    parameter int PROGRAM_MEM_ADDR_BITS = 8,
    parameter int PROGRAM_MEM_DATA_BITS = 16
)(
    input  logic clk,
    input  logic reset,

    //----------------------------------------------------------
    // Core State
    //----------------------------------------------------------

    input  core_state_t core_state,

    //----------------------------------------------------------
    // Program Counter
    //----------------------------------------------------------

    input  logic [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,

    //----------------------------------------------------------
    // Program Memory Interface
    //----------------------------------------------------------

    output logic mem_read_valid,
    output logic [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,

    input  logic mem_read_ready,
    input  logic [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    //----------------------------------------------------------
    // Fetch Outputs
    //----------------------------------------------------------

    output fetcher_state_t fetcher_state,
    output logic [PROGRAM_MEM_DATA_BITS-1:0] instruction
);

    //----------------------------------------------------------
    // Fetch State Machine
    //----------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            fetcher_state    <= FETCHER_IDLE;

            mem_read_valid   <= 1'b0;
            mem_read_address <= '0;

            instruction      <= '0;

        end
        else begin

            case (fetcher_state)

                //----------------------------------------------
                // IDLE
                //----------------------------------------------

                FETCHER_IDLE: begin

                    mem_read_valid <= 1'b0;

                    if (core_state == CORE_FETCH) begin

                        mem_read_valid   <= 1'b1;
                        mem_read_address <= current_pc;

                        fetcher_state <= FETCHER_FETCHING;

                    end

                end

                //----------------------------------------------
                // FETCHING
                //----------------------------------------------

                FETCHER_FETCHING: begin

                    if (mem_read_ready) begin

                        instruction <= mem_read_data;

                        mem_read_valid <= 1'b0;

                        fetcher_state <= FETCHER_FETCHED;

                    end

                end

                //----------------------------------------------
                // FETCHED
                //----------------------------------------------

                FETCHER_FETCHED: begin

                    if (core_state == CORE_DECODE) begin

                        fetcher_state <= FETCHER_IDLE;

                    end

                end

                //----------------------------------------------
                // RECOVERY
                //----------------------------------------------

                default: begin

                    fetcher_state    <= FETCHER_IDLE;
                    mem_read_valid   <= 1'b0;
                    mem_read_address <= 0;

                end

            endcase

        end

    end

endmodule

`default_nettype wire