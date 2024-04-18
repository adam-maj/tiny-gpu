`default_nettype none
`timescale 1ns/1ns

module fetcher #(
    parameter ADDRESS_BITS = 8,
    parameter DRAWER_BITS = 16
) (
    input wire clk,
    input wire reset,
    
    input wire fetch_enable,
    // input wire instruction_processed,
    input wire [ADDRESS_BITS-1:0] current_pc,

    output reg mem_read_valid,
    output reg [ADDRESS_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [DRAWER_BITS-1:0] mem_read_data,

    output instruction_ready,
    output [DRAWER_BITS-1:0] instruction
);
    localparam IDLE = 2'b00, FETCHING = 2'b01, DONE = 2'b10;
    reg [1:0] state = IDLE;
    reg [DRAWER_BITS-1:0] instruction_buffer;
    assign instruction_ready = (state == DONE);
    assign instruction = (state == DONE) ? instruction_buffer : 16'b0;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            mem_read_valid <= 0;
            instruction_buffer <= {DRAWER_BITS{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    if (fetch_enable) begin
                        mem_read_valid <= 1;
                        mem_read_address <= current_pc;
                        state <= FETCHING;
                    end
                end
                FETCHING: begin
                    if (mem_read_ready) begin
                        instruction_buffer <= mem_read_data;
                        mem_read_valid <= 0;
                        state <= DONE;
                    end
                end
                DONE: begin
                    // Wait for instruction to be processed
                    if (fetch_enable) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
