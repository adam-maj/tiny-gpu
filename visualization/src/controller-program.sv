module controllerProg (
    input wire clk,
    input wire reset,

    // Consumer Interface (2 consumers)
    input wire [1:0] consumer_read_valid,
    input wire [15:0] consumer_read_address, // 2 x 8-bit: {addr1, addr0}
    output reg [1:0] consumer_read_ready,
    output reg [31:0] consumer_read_data,    // 2 x 16-bit: {data1, data0}

    // Program Memory Interface (1 channel, read-only)
    output reg mem_read_valid,
    output reg [7:0] mem_read_address,
    input wire mem_read_ready,
    input wire [15:0] mem_read_data
);
    localparam IDLE = 2'b00,
        READ_WAITING  = 2'b01,
        READ_RELAYING = 2'b10;

    reg [1:0] controller_state;
    reg current_consumer;
    reg [1:0] serving_consumer;

    integer j;

    always @(posedge clk) begin
        if (reset) begin
            mem_read_valid <= 1'b0;
            mem_read_address <= 8'b0;

            consumer_read_ready <= 2'b0;
            consumer_read_data <= 32'b0;

            controller_state <= IDLE;
            current_consumer <= 1'b0;
            serving_consumer = 2'b0;
        end else begin
            case (controller_state)
                IDLE: begin
                    // Cycle through consumers looking for a pending request
                    for (j = 0; j < 2; j = j + 1) begin
                        if (consumer_read_valid[j] && !serving_consumer[j]) begin
                            serving_consumer[j] = 1'b1;
                            current_consumer <= j[0];

                            mem_read_valid <= 1'b1;
                            mem_read_address <= consumer_read_address[j*8 +: 8];
                            controller_state <= READ_WAITING;

                            // Stop scanning
                            j = 2;
                        end
                    end
                end

                READ_WAITING: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 1'b0;
                        consumer_read_ready[current_consumer] <= 1'b1;
                        consumer_read_data[current_consumer*16 +: 16] <= mem_read_data;
                        controller_state <= READ_RELAYING;
                    end
                end

                READ_RELAYING: begin
                    // Wait until consumer acknowledges it received response, then reset
                    if (!consumer_read_valid[current_consumer]) begin
                        serving_consumer[current_consumer] = 1'b0;
                        consumer_read_ready[current_consumer] <= 1'b0;
                        controller_state <= IDLE;
                    end
                end

                default: begin
                    controller_state <= IDLE;
                end
            endcase
        end
    end
endmodule
