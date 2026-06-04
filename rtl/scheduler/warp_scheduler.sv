module warp_scheduler #(
    parameter int NUM_WARPS = 4
)(
    input logic clk,
    input logic rst_n,

    input warp_context_t warp_contexts[NUM_WARPS],

    output logic valid,
    output logic [$clog2(NUM_WARPS)-1:0] warp_id
);

    import gpu_pkg::*;

    logic [$clog2(NUM_WARPS)-1:0] rr_ptr_q;
    logic [$clog2(NUM_WARPS)-1:0] rr_ptr_d;

    logic found;

    logic [$clog2(NUM_WARPS)-1:0] selected_warp;

    integer i;
    integer idx;

    //----------------------------------------------------------
    // Scheduler Search
    //----------------------------------------------------------

    always_comb begin

        found = 1'b0;

        selected_warp = rr_ptr_q;

        rr_ptr_d = rr_ptr_q;

        for (i = 0; i < NUM_WARPS; i++) begin

            idx = (rr_ptr_q + i) % NUM_WARPS;

            if (!found &&
                warp_schedulable(warp_contexts[idx])) begin

                selected_warp = idx;
                rr_ptr_d = idx + 1;
                found = 1'b1;

            end

        end

    end

    //----------------------------------------------------------
    // Output Logic
    //----------------------------------------------------------

    assign valid   = found;
    assign warp_id = selected_warp;

    //----------------------------------------------------------
    // Round Robin Pointer
    //----------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            rr_ptr_q <= '0;
        else
            rr_ptr_q <= rr_ptr_d;

    end

endmodule