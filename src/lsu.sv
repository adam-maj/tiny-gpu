`default_nettype none
`timescale 1ns/1ns

module lsu (
    input wire clk,
    input wire reset,

    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    
    output reg mem_read_valid,
    output reg [7:0] mem_read_address,
    input reg mem_read_ready,
    input reg [7:0] mem_read_data,

    output reg mem_write_valid,
    output reg [7:0] mem_write_address,
    output reg [7:0] mem_write_data,
    input reg mem_write_ready,

    input wire [7:0] rs,
    input wire [7:0] rt,

    output wire [1:0] lsu_state,
    output wire [7:0] lsu_out
);
    localparam IDLE = 2'b00, WAITING = 2'b01, STORING = 2'b10;
    reg [7:0] lsu_out_reg = 0;
    reg [1:0] read_state = IDLE;
    reg [1:0] write_state = IDLE;

    assign lsu_out = lsu_out_reg;
    assign lsu_state = (read_state == STORING) 
        ? STORING
        : (read_state == WAITING || write_state == WAITING) 
        ? WAITING 
        : IDLE;

    always @(posedge clk) begin
        if (reset) begin
            read_state <= IDLE;
            write_state <= IDLE;
        end else begin
            case (read_state)
                IDLE: begin
                    if (decoded_mem_read_enable) begin
                        mem_read_valid <= 1;
                        mem_read_address <= rs;
                        read_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (mem_read_ready == 1) begin
                        mem_read_valid <= 0;
                        lsu_out_reg <= mem_read_data;
                        // TODO: Need to go to a state to be read first...
                        read_state <= STORING;
                    end
                end
                STORING: begin 
                    read_state <= IDLE;
                end
            endcase

            case (write_state)
                IDLE: begin
                    if (decoded_mem_write_enable) begin
                        mem_write_valid <= 1;
                        mem_write_address <= rs;
                        mem_write_data <= rt;
                        write_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (mem_write_ready) begin
                        mem_write_valid <= 0;
                        write_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
