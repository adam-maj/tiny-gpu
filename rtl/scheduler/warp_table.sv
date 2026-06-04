`default_nettype none

module warp_table #(
    parameter int NUM_WARPS = 4
)(
    input logic clk,
    input logic rst_n,

    // --------------------------------------------------------
    // Allocation Interface
    // --------------------------------------------------------

    input logic alloc_valid,
    input logic [$clog2(NUM_WARPS)-1:0] alloc_warp_id,
    input logic [31:0] alloc_pc,

    // --------------------------------------------------------
    // Update Interface
    // --------------------------------------------------------

    input logic update_valid,
    input logic [$clog2(NUM_WARPS)-1:0] update_warp_id,

    input logic update_pc_en,
    input logic [31:0] update_pc,

    input logic update_mask_en,
    input thread_mask_t update_mask,

    input logic update_state_en,
    input warp_state_t update_state,

    // --------------------------------------------------------
    // Context Outputs
    // --------------------------------------------------------

    output warp_context_t warp_contexts [NUM_WARPS]
);

    import gpu_pkg::*;

    genvar i;

    generate
        for (i = 0; i < NUM_WARPS; i++) begin : gen_warp_contexts

            warp_context #(
                .WARP_ID(i)
            ) u_warp_context (
                .clk             (clk),
                .rst_n           (rst_n),
                .alloc_valid     ( alloc_valid && (alloc_warp_id == i)),
                .alloc_pc        (alloc_pc),
                .update_pc_en    (update_valid && (update_warp_id == i) && update_pc_en),
                .update_pc       (update_pc),
                .update_mask_en  ( update_valid && (update_warp_id == i) && update_mask_en),
                .update_mask     (update_mask),
                .update_state_en (update_valid && (update_warp_id == i) && update_state_en),
                .update_state    (update_state),
                .warp_context_o  (warp_contexts[i]));

        end
    endgenerate

endmodule

`default_nettype wire