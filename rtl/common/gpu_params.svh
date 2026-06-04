`ifndef GPU_PARAMS_SVH
`define GPU_PARAMS_SVH

// ============================================================
// Tiny GPU Next
// Architectural Parameters
// ============================================================
// This file contains all globally visible architectural configuration constants.
// NOTE:
// These parameters define the educational reference implementation.
// Avoid introducing excessive parameterization until architectural features have stabilized.
// ============================================================

// ------------------------------------------------------------
// Core Configuration
// ------------------------------------------------------------
parameter int NUM_CORES = 1;

// ------------------------------------------------------------
// Warp Configuration
// ------------------------------------------------------------
parameter int WARP_SIZE = 8;
parameter int NUM_WARPS = 4;

// ------------------------------------------------------------
// Register File Configuration
// ------------------------------------------------------------
parameter int REG_COUNT = 32;
parameter int REG_WIDTH = 32;

// ------------------------------------------------------------
// Addressing
// ------------------------------------------------------------
parameter int ADDR_WIDTH = 32;
parameter int DATA_WIDTH = 32;

// ------------------------------------------------------------
// Shared Memory
// ------------------------------------------------------------
parameter int SHMEM_SIZE_BYTES = 4096;

// ------------------------------------------------------------
// Cache Configuration
// (Reserved For Future Use)
// ------------------------------------------------------------
parameter int ICACHE_LINE_SIZE = 32;
parameter int DCACHE_LINE_SIZE = 32;

// ------------------------------------------------------------
// Performance Infrastructure
// ------------------------------------------------------------
parameter int PERF_COUNTER_WIDTH = 64;

`endif
