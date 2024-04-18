`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 16
) (
    input wire clk,
    input wire reset,

    // LSU Interface
    input wire [NUM_CONSUMERS-1:0] consumer_read_valid,
    input wire [ADDR_BITS-1:0] consumer_read_address[NUM_CONSUMERS-1:0],
    output wire [NUM_CONSUMERS-1:0] consumer_read_ready,
    output wire [DATA_BITS-1:0] consumer_read_data[NUM_CONSUMERS-1:0],

    input wire [NUM_CONSUMERS-1:0] consumer_write_valid,
    input wire [ADDR_BITS-1:0] consumer_write_address[NUM_CONSUMERS-1:0],
    input wire [DATA_BITS-1:0] consumer_write_data[NUM_CONSUMERS-1:0],
    output wire [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,

    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready
);
    // QUEUE
    reg [NUM_CONSUMERS-1:0] request_pending;

    // STATE
    localparam IDLE = 2'b00, WAITING = 2'b01;
    reg [1:0] state = IDLE;
    reg [$clog2(NUM_CONSUMERS)-1:0] current_lsu;

    // RESPONSES
    reg [NUM_CONSUMERS-1:0] response_valid;
    reg [DATA_BITS-1:0] response_data [NUM_CONSUMERS-1:0];

    // Keep queue and pending status up to date
    always @(*) begin
        request_pending = (consumer_read_valid | consumer_write_valid) & ~(consumer_read_ready | consumer_write_ready);
    end

    // Send requests to memory
    always @(posedge clk) begin
        if (reset) begin
            current_lsu <= 0;
            state <= IDLE;

            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
            response_valid <= 0;

            for (int i = 0; i < NUM_CONSUMERS; i++) begin
                response_data[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (request_pending[current_lsu]) begin 
                        state <= WAITING;
                    end else begin 
                        current_lsu <= (current_lsu == NUM_CONSUMERS-1) ? 0 : current_lsu + 1;
                    end
                end
                WAITING: begin
                    if (consumer_read_valid[current_lsu]) begin
                        // Execute pending read request
                        if (mem_read_ready) begin
                            response_valid[current_lsu] <= 1;
                            response_data[current_lsu] <= mem_read_data;
                        end else begin 
                            mem_read_valid <= 1;
                            mem_read_address <= consumer_read_address[current_lsu];
                        end
                    end else if (consumer_write_valid[current_lsu]) begin 
                        // Execute pending write request
                        if (mem_write_ready) begin 
                            response_valid[current_lsu] <= 1;
                        end else begin 
                            mem_write_valid <= 1;
                            mem_write_address <= consumer_write_address[current_lsu];
                            mem_write_data <= consumer_write_data[current_lsu];
                        end
                    end else begin 
                        // Completed response handshake with LSU
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // Communicate back with LSUs
    genvar i;
    generate
        for (i = 0; i < NUM_CONSUMERS; i++) begin
            assign consumer_read_ready[i] = response_valid[i] & consumer_read_valid[i];
            assign consumer_write_ready[i] = response_valid[i] & consumer_write_valid[i];
            assign consumer_read_data[i] = response_data[i];
        end
    endgenerate
endmodule
