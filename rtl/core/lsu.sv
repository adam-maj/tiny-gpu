`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// LOAD STORE UNIT
//
// Handles asynchronous memory transactions.
//
// Supported Operations:
//   LDR
//   STR
//
// Future Evolution:
//   Instruction Cache
//   Data Cache
//   Memory Coalescing
//   Shared Memory
// ============================================================

module lsu (
    input  logic clk,
    input  logic reset,
    input  logic enable,

    //----------------------------------------------------------
    // Execution State
    //----------------------------------------------------------

    input  core_state_t core_state,

    //----------------------------------------------------------
    // Decode Controls
    //----------------------------------------------------------

    input  logic decoded_mem_read_enable,
    input  logic decoded_mem_write_enable,

    //----------------------------------------------------------
    // Register Inputs
    //----------------------------------------------------------

    input  logic [7:0] rs,
    input  logic [7:0] rt,

    //----------------------------------------------------------
    // Data Memory Interface
    //----------------------------------------------------------

    output logic       mem_read_valid,
    output logic [7:0] mem_read_address,
    input  logic       mem_read_ready,
    input  logic [7:0] mem_read_data,

    output logic       mem_write_valid,
    output logic [7:0] mem_write_address,
    output logic [7:0] mem_write_data,
    input  logic       mem_write_ready,

    //----------------------------------------------------------
    // LSU Outputs
    //----------------------------------------------------------

    output lsu_state_t lsu_state,
    output logic [7:0] lsu_out
);

    logic is_load;
    logic is_store;

    assign is_load  = decoded_mem_read_enable;
    assign is_store = decoded_mem_write_enable;

    always_ff @(posedge clk) begin

        if (reset) begin

            lsu_state <= LSU_IDLE;

            lsu_out <= '0;

            mem_read_valid   <= 1'b0;
            mem_read_address <= '0;

            mem_write_valid   <= 1'b0;
            mem_write_address <= '0;
            mem_write_data    <= '0;

        end
        else if (enable) begin

            case (lsu_state)

                //--------------------------------------------------
                // IDLE
                //--------------------------------------------------

                LSU_IDLE: begin

                    mem_read_valid  <= 1'b0;
                    mem_write_valid <= 1'b0;

                    if ((core_state == CORE_REQUEST) &&
                        (is_load || is_store)) begin

                        lsu_state <= LSU_REQUESTING;

                    end

                end

                //--------------------------------------------------
                // REQUESTING
                //--------------------------------------------------

                LSU_REQUESTING: begin

                    if (is_load) begin

                        mem_read_valid   <= 1'b1;
                        mem_read_address <= rs;

                    end

                    if (is_store) begin

                        mem_write_valid   <= 1'b1;
                        mem_write_address <= rs;
                        mem_write_data    <= rt;

                    end

                    lsu_state <= LSU_WAITING;

                end

                //--------------------------------------------------
                // WAITING
                //--------------------------------------------------

                LSU_WAITING: begin

                    if (is_load) begin

                        if (mem_read_ready) begin

                            mem_read_valid <= 1'b0;
                            lsu_out <= mem_read_data;

                            lsu_state <= LSU_DONE;

                        end

                    end
                    else if (is_store) begin

                        if (mem_write_ready) begin

                            mem_write_valid <= 1'b0;

                            lsu_state <= LSU_DONE;

                        end

                    end

                end

                //--------------------------------------------------
                // DONE
                //--------------------------------------------------

                LSU_DONE: begin

                    if (core_state == CORE_UPDATE) begin

                        lsu_state <= LSU_IDLE;

                    end

                end

                //--------------------------------------------------
                // RECOVERY
                //--------------------------------------------------

                default: begin

                    lsu_state <= LSU_IDLE;

                end

            endcase

        end

    end

endmodule

`default_nettype wire