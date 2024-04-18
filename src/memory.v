`default_nettype none
`timescale 1ns/1ns

module memory #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16
) (
    input wire clk,
    input wire reset,

    input wire mem_read_valid,
    input wire [ADDR_BITS-1:0] mem_read_address,
    output reg mem_read_ready,
    output reg [DATA_BITS-1:0] mem_read_data,

    input wire mem_write_valid,
    input wire [ADDR_BITS-1:0] mem_write_address,
    input wire [DATA_BITS-1:0] mem_write_data,
    output reg mem_write_ready
);
    localparam MEMORY_SIZE = 2 ** ADDR_BITS;
    reg [DATA_BITS-1:0] memory[0:MEMORY_SIZE-1];

    localparam LATENCY = 3;
    localparam IDLE = 2'b00, WAITING = 2'b10, READY = 2'b11;

    reg [1:0] read_state_reg = IDLE;
    reg [1:0] read_latency_reg = 0;
    reg [ADDR_BITS-1:0] mem_read_address_reg;

    reg [1:0] write_state_reg = IDLE;
    reg [1:0] write_latency_reg = 0;
    reg [ADDR_BITS-1:0] mem_write_address_reg;
    reg [DATA_BITS-1:0] mem_write_data_reg;

    always @(posedge clk) begin
        if (reset) begin
            mem_read_ready <= 0;
            mem_write_ready <= 0;
            read_state_reg <= 0;
            write_state_reg <= 0;
            read_latency_reg <= 0;
            write_latency_reg <= 0;

            for (int i = 0; i < MEMORY_SIZE; i = i + 1) begin
                memory[i] = {DATA_BITS{1'b0}};
            end
        end else begin
            case (read_state_reg)
                IDLE: begin
                    if (mem_read_valid) begin
                        mem_read_address_reg <= mem_read_address;
                        read_state_reg <= WAITING;
                    end
                end
                WAITING: begin
                    if (read_latency_reg < LATENCY) begin
                        read_latency_reg <= read_latency_reg + 1;
                    end else begin
                        mem_read_data <= memory[mem_read_address_reg];
                        mem_read_ready <= 1;
                        read_state_reg <= READY;
                    end
                end
                READY: begin
                    if (!mem_read_valid) begin
                        mem_read_ready <= 0;
                        read_latency_reg <= 0;
                        read_state_reg <= IDLE;
                    end
                end
            endcase

            case (write_state_reg)
                IDLE: begin
                    if (mem_write_valid) begin
                        mem_write_address_reg <= mem_write_address;
                        mem_write_data_reg <= mem_write_data;
                        write_state_reg <= WAITING;
                    end
                end
                WAITING: begin
                    if (write_latency_reg < LATENCY) begin
                        write_latency_reg <= write_latency_reg + 1;
                    end else begin
                        memory[mem_write_address_reg] <= mem_write_data_reg;
                        mem_write_ready <= 1;
                        write_state_reg <= READY;
                    end
                end
                READY: begin
                    if (!mem_write_valid) begin 
                        mem_write_ready <= 0;
                        write_latency_reg <= 0;
                        write_state_reg <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
