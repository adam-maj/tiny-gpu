`default_nettype none
`timescale 1ns/1ns

// SHARED MEMORY LOAD-STORE UNIT
// > Handles LDS/STS access to the core-local shared memory scratchpad
// > Mirrors the timing/state machine of lsu.sv so the scheduler can gate on it the same way,
//   even though shared memory itself has no external bandwidth constraint to throttle
// > Each thread in each core has it's own shared LSU
module shared_lsu #(
    parameter ADDR_BITS = 6
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,

    input reg decoded_shared_mem_read_enable,
    input reg decoded_shared_mem_write_enable,

    input reg [7:0] rs,
    input reg [7:0] rt,

    // Shared Memory
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [7:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [7:0] mem_write_data,
    input reg mem_write_ready,

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
            if (decoded_shared_mem_read_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011) begin
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
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            if (decoded_shared_mem_write_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011) begin
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
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
