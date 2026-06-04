`timescale 1ns/1ns

package gpu_pkg;

`include "gpu_params.svh"
`include "gpu_types.svh"

// ============================================================
// Tiny GPU Next
// GPU Package
//
// Central repository for:
// - Architectural enums
// - Shared constants
// - Utility functions
//
// NOTE:
// ISA definitions are intentionally NOT centralized yet.
// Current decoder still follows Adam Maj Tiny-GPU ISA.
// ============================================================

// ------------------------------------------------------------
// Core State Machine
// ------------------------------------------------------------

typedef enum logic [2:0] {

    CORE_IDLE    = 3'd0,
    CORE_FETCH   = 3'd1,
    CORE_DECODE  = 3'd2,
    CORE_REQUEST = 3'd3,
    CORE_WAIT    = 3'd4,
    CORE_EXECUTE = 3'd5,
    CORE_UPDATE  = 3'd6,
    CORE_DONE    = 3'd7

} core_state_t;

// ------------------------------------------------------------
// Fetch State Machine
// ------------------------------------------------------------

typedef enum logic [1:0] {

    FETCHER_IDLE,
    FETCHER_FETCHING,
    FETCHER_FETCHED

} fetcher_state_t;

// ------------------------------------------------------------
// LSU State Machine
// ------------------------------------------------------------

typedef enum logic [1:0] {

    LSU_IDLE,
    LSU_REQUESTING,
    LSU_WAITING,
    LSU_DONE

} lsu_state_t;

// ------------------------------------------------------------
// Scheduler Constants
// ------------------------------------------------------------

localparam logic [31:0] INVALID_WARP_ID =
    32'hFFFF_FFFF;

// ------------------------------------------------------------
// Memory Constants
// ------------------------------------------------------------

localparam logic [ADDR_WIDTH-1:0] RESET_PC = '0;

// ------------------------------------------------------------
// Utility Functions
// ------------------------------------------------------------

function automatic logic warp_active (
    input warp_context_t warp
);
begin
    warp_active =
        warp.valid &&
        (warp.state != WARP_DONE);
end
endfunction

function automatic logic warp_schedulable (
    input warp_context_t warp
);
begin
    warp_schedulable =
        warp.valid &&
        (warp.state == WARP_READY);
end
endfunction

endpackage
