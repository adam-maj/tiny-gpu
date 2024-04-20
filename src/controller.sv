`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4,
    parameter WRITE_ENABLE = 1
) (
    input wire clk,
    input wire reset,

    // LSU Interface
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address[NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data[NUM_CONSUMERS-1:0],

    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address[NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data[NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data,

    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input reg mem_write_ready
);
    // STATE - TODO: Can switch to different states for read/write waiting
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;
    reg [2:0] controller_state = IDLE;
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer;

    // TODO: read/write should be separate channels, and should handle multi-channel
    always @(posedge clk) begin
        if (reset) begin
            current_consumer <= 0;
            controller_state <= IDLE;

            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;
        end else begin
            case (controller_state)
                IDLE: begin
                    if (consumer_read_valid[current_consumer]) begin 
                        // Send a read request
                        mem_read_valid <= 1;
                        mem_read_address <= consumer_read_address[current_consumer];
                        controller_state <= READ_WAITING;
                    end else if (consumer_write_valid[current_consumer]) begin 
                        // Send a write request
                        mem_write_valid <= 1;
                        mem_write_address <= consumer_write_address[current_consumer];
                        mem_write_data <= consumer_write_data[current_consumer];
                        controller_state <= WRITE_WAITING;
                    end else begin
                        // Cycle through consumers looking for a pending request
                        current_consumer <= (current_consumer + 1) % NUM_CONSUMERS;
                    end
                end
                READ_WAITING: begin
                    // Wait for response from memory for pending read request
                    if (mem_read_ready) begin 
                        mem_read_valid <= 0;
                        consumer_read_ready[current_consumer] <= 1;
                        consumer_read_data[current_consumer] <= mem_read_data;
                        controller_state <= READ_RELAYING;
                    end
                end
                WRITE_WAITING: begin 
                    // Wait for response from memory for pending write request
                    if (mem_write_ready) begin 
                        mem_write_valid <= 0;
                        consumer_write_ready[current_consumer] <= 1;
                        controller_state <= WRITE_RELAYING;
                    end
                end
                // Wait until consumer acknowledges it received data, then reset
                READ_RELAYING: begin
                    if (!consumer_read_valid[current_consumer]) begin 
                        consumer_read_ready[current_consumer] <= 0;
                        controller_state <= IDLE;
                    end
                end
                WRITE_RELAYING: begin 
                    if (!consumer_write_valid[current_consumer]) begin 
                        consumer_write_ready[current_consumer] <= 0;
                        controller_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
