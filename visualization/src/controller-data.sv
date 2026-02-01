module controllerData (
    input wire clk,
    input wire reset,

    // Consumer Interface (8 consumers: Fetchers / LSUs)
    input [7:0] consumer_read_valid,
    input [63:0] consumer_read_address,   // 8 x 8-bit addresses
    output reg [7:0] consumer_read_ready,
    output reg [63:0] consumer_read_data,     // 8 x 8-bit data
    input [7:0] consumer_write_valid,
    input [63:0] consumer_write_address,  // 8 x 8-bit addresses
    input [63:0] consumer_write_data,     // 8 x 8-bit data
    output reg [7:0] consumer_write_ready,

    // Memory Interface (4 channels: Data / Program)
    output reg [3:0] mem_read_valid,
    output reg [31:0] mem_read_address,       // 4 x 8-bit addresses
    input [3:0] mem_read_ready,
    input [31:0] mem_read_data,           // 4 x 8-bit data
    output reg [3:0] mem_write_valid,
    output reg [31:0] mem_write_address,      // 4 x 8-bit addresses
    output reg [31:0] mem_write_data,         // 4 x 8-bit data
    input [3:0] mem_write_ready
);
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Keep track of state for each channel and which jobs each channel is handling
    reg [11:0] controller_state;              // 4 x 3-bit states
    reg [11:0] current_consumer;              // 4 x 3-bit consumer IDs
    reg [7:0] channel_serving_consumer;       // Which consumers are being served

    integer i;
    integer j;

    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= 4'b0;
            mem_read_address <= 32'b0;

            mem_write_valid <= 4'b0;
            mem_write_address <= 32'b0;
            mem_write_data <= 32'b0;

            consumer_read_ready <= 8'b0;
            consumer_read_data <= 64'b0;
            consumer_write_ready <= 8'b0;

            current_consumer <= 12'b0;
            controller_state <= 12'b0;

            channel_serving_consumer = 8'b0;
        end else begin 
            // For each channel, we handle processing concurrently
            for (i = 0; i < 4; i = i + 1) begin 
                case (controller_state[i*3 +: 3])
                    IDLE: begin
                        // While this channel is idle, cycle through consumers looking for one with a pending request
                        for (j = 0; j < 8; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] = 1;
                                current_consumer[i*3 +: 3] <= j[2:0];

                                mem_read_valid[i] <= 1;
                                mem_read_address[i*8 +: 8] <= consumer_read_address[j*8 +: 8];
                                controller_state[i*3 +: 3] <= READ_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                j = 8;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] = 1;
                                current_consumer[i*3 +: 3] <= j[2:0];

                                mem_write_valid[i] <= 1;
                                mem_write_address[i*8 +: 8] <= consumer_write_address[j*8 +: 8];
                                mem_write_data[i*8 +: 8] <= consumer_write_data[j*8 +: 8];
                                controller_state[i*3 +: 3] <= WRITE_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                j = 8;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i*3 +: 3]] <= 1;
                            consumer_read_data[current_consumer[i*3 +: 3]*8 +: 8] <= mem_read_data[i*8 +: 8];
                            controller_state[i*3 +: 3] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait for response from memory for pending write request
                        if (mem_write_ready[i]) begin 
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i*3 +: 3]] <= 1;
                            controller_state[i*3 +: 3] <= WRITE_RELAYING;
                        end
                    end
                    // Wait until consumer acknowledges it received response, then reset
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i*3 +: 3]]) begin 
                            channel_serving_consumer[current_consumer[i*3 +: 3]] = 0;
                            consumer_read_ready[current_consumer[i*3 +: 3]] <= 0;
                            controller_state[i*3 +: 3] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i*3 +: 3]]) begin 
                            channel_serving_consumer[current_consumer[i*3 +: 3]] = 0;
                            consumer_write_ready[current_consumer[i*3 +: 3]] <= 0;
                            controller_state[i*3 +: 3] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
