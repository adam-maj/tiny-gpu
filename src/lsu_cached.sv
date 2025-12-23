`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT WITH CACHE
// > Handles asynchronous memory load and store operations through cache
// > Each thread in each core has its own LSU with cache
// > LDR, STR instructions are executed here
module lsu_cached (
    input wire clk,
    input wire reset,
    input wire enable,

    // State
    input reg [2:0] core_state,

    // Memory Control Signals
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,

    // Registers
    input reg [7:0] rs,
    input reg [7:0] rt,

    // Data Memory (through controller)
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

    // Cache signals
    reg cache_read_request;
    reg cache_write_request;
    reg [7:0] cache_address;
    reg [7:0] cache_write_data;
    wire cache_read_ready;
    wire cache_write_ready;
    wire [7:0] cache_read_data;

    // Instantiate cache
    cache #(
        .CACHE_LINES(64),
        .ADDR_BITS(8),
        .DATA_BITS(8),
        .INDEX_BITS(6),
        .TAG_BITS(2)
    ) cache_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        
        // LSU interface
        .read_request(cache_read_request),
        .write_request(cache_write_request),
        .address(cache_address),
        .write_data(cache_write_data),
        .read_ready(cache_read_ready),
        .write_ready(cache_write_ready),
        .read_data(cache_read_data),
        
        // Memory controller interface
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data),
        .mem_write_valid(mem_write_valid),
        .mem_write_address(mem_write_address),
        .mem_write_data(mem_write_data),
        .mem_write_ready(mem_write_ready)
    );

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= 0;
            cache_read_request <= 0;
            cache_write_request <= 0;
            cache_address <= 0;
            cache_write_data <= 0;
        end else if (enable) begin
            // Handle memory read (LDR instruction)
            if (decoded_mem_read_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011) begin  // REQUEST state
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        cache_read_request <= 1;
                        cache_address <= rs;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        if (cache_read_ready) begin
                            cache_read_request <= 0;
                            lsu_out <= cache_read_data;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        if (core_state == 3'b110) begin  // UPDATE state
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            // Handle memory write (STR instruction)
            if (decoded_mem_write_enable) begin
                case (lsu_state)
                    IDLE: begin
                        if (core_state == 3'b011) begin  // REQUEST state
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        cache_write_request <= 1;
                        cache_address <= rs;
                        cache_write_data <= rt;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        if (cache_write_ready) begin
                            cache_write_request <= 0;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        if (core_state == 3'b110) begin  // UPDATE state
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule