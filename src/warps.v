`default_nettype none
`timescale 1ns/1ns

module warps #(
    parameter WARP_SIZE = 4,
    parameter MAX_WARPS = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire instruction_ready,
    input wire decoded_done,
    input wire [WARP_SIZE-1:0] lsu_state,
    input wire [7:0] thread_count,
    input wire [7:0] next_pc[WARP_SIZE-1:0],
    output reg [7:0] current_warp_id,
    output wire done
);
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'b10, DONE = 2'b11;
    reg [1:0] state = IDLE;
    
    wire [7:0] NUM_WARPS = (thread_count + WARP_SIZE - 1) / WARP_SIZE;
    reg [7:0] warp_pc [0:MAX_WARPS-1];
    reg [0:MAX_WARPS-1] warp_done;

    assign done = &(warp_done);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            current_warp_id <= 0; 

            for (int i = 0; i < MAX_WARPS; i++) begin
                warp_pc[i] <= 0;
                warp_done[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= FETCHING;

                        if (NUM_WARPS <= MAX_WARPS) begin 
                            for (int i = 0; i < NUM_WARPS; i++) begin
                                warp_pc[i] <= i * WARP_SIZE;
                                warp_done[i] <= 0;
                            end
                        end else begin
                            $display("ERROR: NUM_WARPS exceeds MAX_WARPS");
                        end
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
