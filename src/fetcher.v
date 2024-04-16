`default_nettype none
`timescale 1ns/1ns

module fetcher (
    input wire clk,
    input wire reset,
    
    input wire fetch_enable,
    input wire [7:0] pc,

    memory_if.consumer memory_control,

    output instruction_ready,
    output [15:0] instruction,
)
    localparam IDLE = 2'b00, FETCHING = 2'b01, DONE = 2'b10;
    reg [1:0] fetcher_state = IDLE;
    reg [15:0] instruction_buffer;
    assign instruction_ready = (fetcher_state == DONE);
    assign instruction = (fetcher_state == DONE) ? instruction_buffer : 16'b0;

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            memory_control.mem_read_valid <= 0;
            instruction_buffer <= 16'b0;
        end else begin
            case (fetcher_state)
                IDLE: begin
                    if (fetch_enable) begin
                        memory_control.mem_read_valid <= 1;
                        memory_control.mem_read_address <= pc;
                        fetcher_state <= FETCHING;
                    end
                end
                FETCHING: begin
                    if (memory_control.mem_read_ready) begin
                        instruction_buffer <= memory_control.mem_read_data;
                        memory_control.mem_read_valid <= 0;
                        fetcher_state <= DONE;
                    end
                end
                DONE: begin
                    // Wait for instruction to be consumed
                    if (!fetch_enable) begin
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule