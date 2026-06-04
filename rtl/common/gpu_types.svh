`ifndef GPU_TYPES_SVH
`define GPU_TYPES_SVH

`include "gpu_params.svh"

// ============================================================
// Tiny GPU Next
// Common Architecture Types
// ============================================================
// ------------------------------------------------------------
// Warp State
// ------------------------------------------------------------
// READY   : Eligible for scheduling
// RUNNING : Currently executing
// STALLED : Waiting on memory/resource
// DONE    : Completed execution
// ------------------------------------------------------------
typedef enum logic [1:0] {
    WARP_READY   = 2'b00,
    WARP_RUNNING = 2'b01,
    WARP_STALLED = 2'b10,
    WARP_DONE    = 2'b11
} warp_state_t;

// ------------------------------------------------------------
// Thread Mask
// ------------------------------------------------------------
// One bit per thread lane.
// Example:
// WARP_SIZE = 8
// 11111111 -> all active
// 00001111 -> lower half active
// ------------------------------------------------------------
typedef logic [WARP_SIZE-1:0] thread_mask_t;

// ------------------------------------------------------------
// Warp Context
// ------------------------------------------------------------
// Architectural state associated with a warp.
// Future revisions may extend this structure with:
// - reconvergence information
// - scoreboarding state
// - performance statistics
// ------------------------------------------------------------
typedef struct packed {
    logic             valid;
    logic [31:0]      pc;
    thread_mask_t     active_mask;
    warp_state_t      state;
} warp_context_t;

`endif
