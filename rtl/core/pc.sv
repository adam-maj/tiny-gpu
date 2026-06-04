`default_nettype none
`timescale 1ns/1ns

import gpu_pkg::*;

// ============================================================
// PROGRAM COUNTER
//
// Calculates the next PC for a thread.
//
// Current Assumptions:
// - No branch divergence
// - All threads within a block converge to same PC
//
// Future Evolution:
// - Branch divergence
// - Reconvergence support
// - Warp-level PC management
// ============================================================

module pc #(
    parameter int DATA_MEM_DATA_BITS    = 8,
    parameter int PROGRAM_MEM_ADDR_BITS = 8
)(
    input  logic clk,
    input  logic reset,

    // Thread Active
    input  logic enable,

    // Execution State
    input  core_state_t core_state,

    // Control Signals
    input  logic [2:0] decoded_nzp,
    input  logic [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    input  logic decoded_nzp_write_enable,
    input  logic decoded_pc_mux,

    // ALU Output
    input  logic [DATA_MEM_DATA_BITS-1:0] alu_out,

    // Current & Next PCs
    input  logic [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output logic [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);

    //----------------------------------------------------------
    // NZP Register
    //----------------------------------------------------------
    //
    // Bit[2] = Negative
    // Bit[1] = Zero
    // Bit[0] = Positive
    //
    //----------------------------------------------------------

    logic [2:0] nzp;

    always_ff @(posedge clk) begin

        if (reset) begin
            nzp     <= '0;
            next_pc <= '0;
        end
        else if (enable) begin

            //--------------------------------------------------
            // Program Counter Update
            //--------------------------------------------------

            if (core_state == CORE_EXECUTE) begin
                if (decoded_pc_mux) begin
                    // BRnzp
                    if ((nzp & decoded_nzp) != 3'b000) begin
                        // Branch Taken
                        next_pc <= PROGRAM_MEM_ADDR_BITS'(decoded_immediate);
                    end
                    else begin
                        // Branch Not Taken
                        next_pc <= current_pc + 1'b1;
                    end
                end
                else begin
                    // Sequential Execution
                    next_pc <= current_pc + 1'b1;
                end
            end

            //--------------------------------------------------
            // NZP Register Update
            //--------------------------------------------------

            if (core_state == CORE_UPDATE) begin
                if (decoded_nzp_write_enable) begin
                    nzp <= alu_out[2:0];
                end
            end
        end
    end
endmodule
`default_nettype wire

