module warp_context #(
    parameter int WARP_ID = 0
)(
    input  logic clk,
    input  logic rst_n,

    // Context Allocation
    input  logic alloc_valid,
    input  logic [31:0] alloc_pc,

    // Context Update
    input  logic update_pc_en,
    input  logic [31:0] update_pc,

    input  logic update_mask_en,
    input  logic [WARP_SIZE-1:0] update_mask,

    input  logic update_state_en,
    input  warp_state_t update_state,

    // Context Read
    output warp_context_t warp_context_o
);

    import gpu_pkg::*;

    warp_context_t ctx_q;
    warp_context_t ctx_d;

    // --------------------------------------------------------
    // Next-State Logic
    // --------------------------------------------------------

    always_comb begin

        ctx_d = ctx_q;

        //---------------------------------------------
        // Warp Allocation
        //---------------------------------------------

        if (alloc_valid) begin

            ctx_d.valid       = 1'b1;
            ctx_d.pc          = alloc_pc;
            ctx_d.active_mask = '1;
            ctx_d.state       = WARP_READY;

        end

        //---------------------------------------------
        // Program Counter Update
        //---------------------------------------------

        if (update_pc_en)
            ctx_d.pc = update_pc;

        //---------------------------------------------
        // Active Mask Update
        //---------------------------------------------

        if (update_mask_en)
            ctx_d.active_mask = update_mask;

        //---------------------------------------------
        // State Update
        //---------------------------------------------

        if (update_state_en)
            ctx_d.state = update_state;

    end

    // --------------------------------------------------------
    // Sequential Logic
    // --------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            ctx_q.valid       <= 1'b0;
            ctx_q.pc          <= '0;
            ctx_q.active_mask <= '0;
            ctx_q.state       <= WARP_DONE;

        end
        else begin

            ctx_q <= ctx_d;

        end

    end
    assign warp_context_o = ctx_q;

endmodule

