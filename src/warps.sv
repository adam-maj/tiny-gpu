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

    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,

    input wire [1:0] lsu_state [THREAD_ID_BITS-1:0],
    input wire [7:0] thread_count,
    input wire [7:0] next_pc[0:THREAD_ID_BITS-1],
    output reg [1:0] state,
    output reg [7:0] warp_pc[0:THREAD_ID_BITS-1],
    output reg [THREAD_ID_BITS-1:0] current_warp_id,
    output wire done
);
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'b10, WAITING = 2'b11;
    
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
                    // TODO: Add a done state
                    if (warp_done[current_warp_id]) begin
                        current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                    end else begin 
                        if (instruction_ready) begin 
                            state <= PROCESSING;
                        end
                    end
                end
                PROCESSING: begin
                    if (decoded_done) begin
                        warp_done[current_warp_id] <= 1;
                        state <= FETCHING;
                    end else begin
                        // if (decoded_mem_read_enable || decoded_mem_write_enable) begin 
                        //     state <= WAITING;
                        // end else begin
                            // TODO: BRANCH DIVERGENCE
                        warp_pc[current_warp_id] <= next_pc[0];
                        current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                        
                        state <= FETCHING;
                        // end
                    end
                end
                WAITING: begin 
                    if (lsu_state[current_warp_id] == 2'b00) begin 
                        warp_pc[current_warp_id] <= next_pc[0];
                        current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                            
                        state <= FETCHING;
                    end
                end
            endcase
        end
    end
endmodule
