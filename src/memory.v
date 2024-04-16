`default_nettype none
`timescale 1ns/1ns

interface memory_if;
    reg mem_read_valid,
    reg [7:0] mem_read_address,
    wire mem_read_ready,
    wire [15:0] mem_read_data,

    reg mem_write_valid,
    reg [7:0] mem_write_address,
    reg [15:0] mem_write_data,
    wire mem_write_ready

    modport memory (
        input mem_read_valid,
        input mem_read_address,
        output mem_read_ready,
        output mem_read_data,

        input mem_write_valid,
        input mem_write_address,
        input mem_write_data,
        output mem_write_ready
    );

    modport consumer (
        output mem_read_valid,
        output mem_read_address,
        input mem_read_ready,
        input mem_read_data,

        output mem_write_valid,
        output mem_write_address,
        output mem_write_data,
        input mem_write_ready
    )
endinterface

module memory (
    input wire clk,
    input wire reset,

    memory_if.memory memory_control
);
    localparam MEMORY_SIZE = 256;
    localparam DRAWER_SIZE = 16;
    reg [15:0] memory[0:MEMORY_SIZE-1];

    localparam LATENCY = 3;
    localparam IDLE = 2'b00, WAITING = 2'b10, READY = 2'b11;

    reg [1:0] read_state = IDLE;
    reg [1:0] read_latency = 0;
    reg [7:0] mem_read_address;

    reg [1:0] write_state = IDLE;
    reg [1:0] write_latency = 0;
    reg [7:0] mem_write_address;
    reg [15:0] mem_write_data;

    always @(posedge clk) begin
        if (reset) begin
            memory_control.mem_read_ready <= 0;
            memory_control.mem_write_ready <= 0;
            read_state <= 0;
            write_state <= 0;
            
            read_latency <= 0;
            write_latency <= 0;
        end else begin
            case (read_state)
                IDLE: begin
                    if (memory_control.mem_read_valid) begin
                        mem_read_address <= memory_control.mem_read_address;
                        read_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (read_latency < LATENCY) begin
                        read_latency <= read_latency + 1;
                    end else begin
                        memory_control.mem_read_data <= memory[mem_read_address];
                        memory_control.mem_read_ready <= 1;
                        read_state <= READY;
                    end
                end
                READY: begin
                    if (!memory_control.mem_read_valid) begin
                        memory_control.mem_read_ready <= 0;
                        read_latency <= 0;
                        read_state <= IDLE;
                    end
                end
            endcase

            case (write_state)
                IDLE: begin
                    if (memory_control.mem_write_valid) begin
                        mem_write_address <= memory_control.mem_write_address;
                        mem_write_data <= memory_control.mem_write_data;
                        write_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (write_latency < LATENCY) begin
                        write_latency <= write_latency + 1;
                    end else begin
                        memory[mem_write_address] <= mem_write_data;
                        memory_control.mem_write_ready <= 1;
                        write_state <= READY;
                    end
                end
                READY: begin
                    if (!mem_write_valid) begin 
                        memory_control.mem_write_ready <= 0;
                        write_latency <= 0;
                        write_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule