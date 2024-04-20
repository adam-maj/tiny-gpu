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

    input reg [2:0] fetcher_state,

    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,
    input reg [1:0] lsu_state [THREADS_PER_WARP-1:0],
    input reg [7:0] next_pc [THREADS_PER_WARP-1:0],
    input wire [7:0] thread_count,

    output reg [2:0] core_state,
    output reg [7:0] warp_pc [THREADS_PER_WARP-1:0],
    output reg [THREAD_ID_BITS-1:0] current_warp_id,
    output wire done
);
    // TODO: Package
    localparam IDLE = 3'b000, // Waiting to start
        FETCH = 3'b001,       // Fetch instructions from program memory
        DECODE = 3'b010,      // Decode instructions into control signals
        REQUEST = 3'b011,     // Request data from registers or memory
        WAIT = 3'b100,        // Wait for response from memory if necessary
        EXECUTE = 3'b101,     // Execute ALU and PC calculations
        UPDATE = 3'b110;      // Update registers, NZP, and PC
    
    wire [7:0] NUM_WARPS = (thread_count + THREADS_PER_WARP - 1) / THREADS_PER_WARP;
    reg [MAX_WARPS_PER_CORE-1:0] warp_done;

    assign done = &(warp_done);

    always @(posedge clk) begin 
        if (reset) begin 
            current_warp_id <= 0;
            core_state <= IDLE;

            for (int i = 0; i < MAX_WARPS_PER_CORE; i++) begin
                warp_pc[i] <= 0;
                warp_done[i] <= 0;
            end
        end else begin 
            case (core_state)
                IDLE: begin 
                    if (start) begin 
                        core_state <= FETCH;
                    end
                end
                FETCH: begin 
                    if (warp_done[current_warp_id]) begin 
                        // If this warp is complete, move to the next warp
                        current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                    end else if (fetcher_state == 3'b010) begin 
                        // Move on once fetcher reaches FETCHED
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decode is synchronous so we move on after one cycle
                    core_state <= REQUEST;
                end
                REQUEST: begin 
                    // Request is synchronous so we move on after one cycle
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Wait for all LSUs to finish their request before continuing
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_WARP; i++) begin
                        // Make sure no lsu_state = WAITING
                        if (lsu_state[i] == 2'b01) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // Execute is synchronous so we move on after one cycle
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        warp_done[current_warp_id] <= 1;
                    end

                    // TODO: Branch divergence. For now assume all next_pc converge
                    warp_pc[current_warp_id] <= next_pc[0];

                    // Update is synchronous so we move on after one cycle
                    core_state <= FETCH;
                    // Update the warp id
                    current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                end
            endcase
        end
    end
endmodule
