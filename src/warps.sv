`default_nettype none
`timescale 1ns/1ns

module warps #(
    parameter MAX_WARPS_PER_CORE = 2,
    parameter THREADS_PER_WARP = 2,
    parameter THREAD_ID_BITS = $clog2(THREADS_PER_WARP)
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire instruction_ready,
    input wire decoded_done,
    input wire [THREAD_ID_BITS-1:0] lsu_state,
    input wire [7:0] thread_count,
    input wire [7:0] next_pc[0:THREAD_ID_BITS-1],
    output reg [1:0] state,
    output reg [7:0] warp_pc[0:THREAD_ID_BITS-1],
    output reg [THREAD_ID_BITS-1:0] current_warp_id,
    output wire done
);
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'b10, DONE = 2'b11;
    
    wire [7:0] NUM_WARPS = (thread_count + THREADS_PER_WARP - 1) / THREADS_PER_WARP;
    reg [MAX_WARPS_PER_CORE-1:0] warp_done;

    assign done = &(warp_done);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            current_warp_id <= 0; 

            for (int i = 0; i < MAX_WARPS_PER_CORE; i++) begin
                warp_pc[i] <= 0;
                warp_done[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= FETCHING;
                    end
                end
                FETCHING: begin
                    if (&warp_done) begin
                        state <= DONE;
                    end else begin
                        if (warp_done[current_warp_id]) begin
                            current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                        end else begin 
                            if (instruction_ready) begin 
                                state <= PROCESSING;
                            end
                        end
                    end
                end
                PROCESSING: begin
                    if (decoded_done) begin
                        warp_done[current_warp_id] <= 1;
                        state <= FETCHING;
                    end else begin
                        // TODO: fix
                        if (!lsu_state[0]) begin
                            // TODO: BRANCH DIVERGENCE
                            warp_pc[current_warp_id] <= next_pc[0];
                            current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                            
                            state <= FETCHING;
                        end
                    end
                end
                DONE: begin
                    // no-op
                end
            endcase
        end
    end
endmodule
