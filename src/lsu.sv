`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT
// > Handles asynchronous memory load and store operations and waits for response
// > Each thread in each core has it's own LSU
// > LDR, STR instructions are executed here
//
// OPTIMIZATION (branch divergence readiness): with divergence, a thread's `enable`
// can go low for several rounds while other threads run a different PC, then come
// back high once this thread's PC is picked again. We can no longer rely on
// reaching core_state == UPDATE to clean up a finished (DONE) request, because a
// masked-out thread never sees UPDATE while it's inactive. Instead, we proactively
// reset lsu_state back to IDLE as soon as this thread is enabled again during
// FETCH - FETCH always takes >= 1 cycle before DECODE, so this is guaranteed to
// land cleanly before the next request needs to start.
module lsu (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some LSUs will be inactive

    // State
    input reg [2:0] core_state,

    // Memory Control Sgiansl
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,

    // Registers
    input reg [7:0] rs,
    input reg [7:0] rt,

    // Data Memory
    output reg mem_read_valid,
    output reg [7:0] mem_read_address,
    input reg mem_read_ready,
    input reg [7:0] mem_read_data,
    output reg mem_write_valid,
    output reg [7:0] mem_write_address,
    output reg [7:0] mem_write_data,
    input reg mem_write_ready,

    // LSU Outputs
    output reg [1:0] lsu_state,
    output reg [7:0] lsu_out
);
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
        end else if (enable) begin
            // Make sure we start every new instruction from a clean slate, even if this
            // thread was masked out (inactive) for a while and never got to see UPDATE
            // to reset a previous DONE state on its own.
            if (core_state == 3'b001) begin // FETCH
                lsu_state <= IDLE;
            end else begin
                // If memory read enable is triggered (LDR instruction)
                if (decoded_mem_read_enable) begin 
                    case (lsu_state)
                        IDLE: begin
                            // Only read when core_state = DECODE (decoding is combinational,
                            // so decoded_mem_read_enable is already valid for this instruction)
                            if (core_state == 3'b010) begin 
                                lsu_state <= REQUESTING;
                            end
                        end
                        REQUESTING: begin 
                            mem_read_valid <= 1;
                            mem_read_address <= rs;
                            lsu_state <= WAITING;
                        end
                        WAITING: begin
                            if (mem_read_ready == 1) begin
                                mem_read_valid <= 0;
                                lsu_out <= mem_read_data;
                                lsu_state <= DONE;
                            end
                        end
                        DONE: begin 
                            // no-op; reset back to IDLE happens above at the next FETCH
                        end
                    endcase
                end

                // If memory write enable is triggered (STR instruction)
                if (decoded_mem_write_enable) begin 
                    case (lsu_state)
                        IDLE: begin
                            // Only read when core_state = DECODE (decoding is combinational,
                            // so decoded_mem_write_enable is already valid for this instruction)
                            if (core_state == 3'b010) begin 
                                lsu_state <= REQUESTING;
                            end
                        end
                        REQUESTING: begin 
                            mem_write_valid <= 1;
                            mem_write_address <= rs;
                            mem_write_data <= rt;
                            lsu_state <= WAITING;
                        end
                        WAITING: begin
                            if (mem_write_ready) begin
                                mem_write_valid <= 0;
                                lsu_state <= DONE;
                            end
                        end
                        DONE: begin 
                            // no-op; reset back to IDLE happens above at the next FETCH
                        end
                    endcase
                end
            end
        end
    end
endmodule
