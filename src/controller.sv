`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
// > Receives memory requests from all cores
// > Throttles requests based on limited external memory bandwidth
// > Waits for responses from external memory and distributes them back to cores
// > OPTIMIZATION (memory coalescing): When multiple consumers issue a read to the
//   *same* address in the same cycle (a very common pattern - e.g. every thread in
//   a block loading a shared scalar, or all threads in matmul's inner loop reading
//   the same row of matrix A), they're folded into a single external-memory
//   transaction instead of being served one-by-one on separate channels/cycles.
//   The single response is then broadcast back to every consumer that asked for it.
//   This directly reduces contention for the (limited) memory channels and the
//   total number of external memory transactions - see test/test_coalescing.py.
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4, // The number of consumers accessing memory through this controller
    parameter NUM_CHANNELS = 1,  // The number of concurrent channels available to send requests to global memory
    parameter WRITE_ENABLE = 1   // Whether this memory controller can write to memory (program memory is read-only)
) (
    input wire clk,
    input wire reset,

    // Consumer Interface (Fetchers / LSUs)
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface (Data / Program)
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_write_ready
);
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Keep track of state for each channel and which jobs each channel is handling
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    // Which consumers is each channel currently serving? A single in-flight transaction
    // may serve >1 consumer at once when their reads have been coalesced together.
    reg [NUM_CONSUMERS-1:0] channel_consumer_mask [NUM_CHANNELS-1:0];
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer; // Which consumers are already claimed by some channel?

    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            controller_state <= 0;
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                channel_consumer_mask[i] = 0;
            end

            channel_serving_consumer = 0;
        end else begin 
            // For each channel, we handle processing concurrently
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // While this channel is idle, cycle through consumers looking for one with a pending request
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin 
                                // OPTIMIZATION: memory coalescing - fold every other pending read
                                // to this exact same address into this one transaction, so they all
                                // get served by a single external memory access instead of queuing
                                // up one-by-one across cycles/channels.
                                reg [NUM_CONSUMERS-1:0] coalesced_mask;
                                coalesced_mask = 0;
                                for (int k = 0; k < NUM_CONSUMERS; k = k + 1) begin
                                    if (consumer_read_valid[k] && !channel_serving_consumer[k] &&
                                        consumer_read_address[k] == consumer_read_address[j]) begin
                                        coalesced_mask[k] = 1;
                                    end
                                end

                                channel_serving_consumer = channel_serving_consumer | coalesced_mask;
                                channel_consumer_mask[i] <= coalesced_mask;

                                mem_read_valid[i] <= 1;
                                mem_read_address[i] <= consumer_read_address[j];
                                controller_state[i] <= READ_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                break;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] = 1;
                                channel_consumer_mask[i] <= 1 << j;

                                mem_write_valid[i] <= 1;
                                mem_write_address[i] <= consumer_write_address[j];
                                mem_write_data[i] <= consumer_write_data[j];
                                controller_state[i] <= WRITE_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;

                            // Broadcast the single response to every consumer coalesced onto this transaction
                            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                                if (channel_consumer_mask[i][j]) begin
                                    consumer_read_ready[j] <= 1;
                                    consumer_read_data[j] <= mem_read_data[i];
                                end
                            end

                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait for response from memory for pending write request
                        if (mem_write_ready[i]) begin 
                            mem_write_valid[i] <= 0;
                            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                                if (channel_consumer_mask[i][j]) begin
                                    consumer_write_ready[j] <= 1;
                                end
                            end
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    // Wait until every coalesced consumer acknowledges it received the response, then reset
                    READ_RELAYING: begin
                        reg all_acked;
                        all_acked = 1'b1;
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if (channel_consumer_mask[i][j] && consumer_read_valid[j]) begin
                                all_acked = 1'b0;
                            end
                        end
                        if (all_acked) begin 
                            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                                if (channel_consumer_mask[i][j]) begin
                                    channel_serving_consumer[j] = 0;
                                    consumer_read_ready[j] <= 0;
                                end
                            end
                            channel_consumer_mask[i] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        reg all_acked;
                        all_acked = 1'b1;
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if (channel_consumer_mask[i][j] && consumer_write_valid[j]) begin
                                all_acked = 1'b0;
                            end
                        end
                        if (all_acked) begin 
                            for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                                if (channel_consumer_mask[i][j]) begin
                                    channel_serving_consumer[j] = 0;
                                    consumer_write_ready[j] <= 0;
                                end
                            end
                            channel_consumer_mask[i] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
