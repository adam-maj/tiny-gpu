`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
// > Arbitrates many requesters onto a smaller number of external memory channels.
// > Used twice in this design:
//   - once for data memory (serving all LSUs)
//   - once for program memory (serving all fetchers)
// > Beginner mental model:
//   many internal clients may want memory at the same time, but the outside world has only a
//   few ports. This controller is the traffic cop that assigns channels and relays responses.
// 新手导读：
// 1. 这个模块是“仲裁器 + 转发器”：左边连很多消费者，右边连较少的 memory channel。
// 2. 端口里像 `signal [NUM_CONSUMERS-1:0]` 这样的写法表示向量；像 `signal [NUM_CONSUMERS-1:0]` 后面再跟数组下标，则是数组端口。
// 3. `current_consumer[i]` 记录“第 i 个外部通道当前在服务哪个内部客户端”。
// 4. `channel_serving_consumer` 是一个位图，防止两个 channel 同时抢到同一个请求。
// 5. 读懂这个模块的关键不是每一行赋值，而是先抓住每个 channel 都有自己的小状态机。
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4, // The number of consumers accessing memory through this controller
    parameter NUM_CHANNELS = 1,  // The number of concurrent channels available to send requests to global memory
    parameter WRITE_ENABLE = 1   // Whether this memory controller can write to memory (program memory is read-only)
) (
    input wire clk,
    input wire reset,

    // Consumer-facing handshake ports (fetchers or LSUs, depending on instantiation).
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // External memory-facing channels.
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_write_ready
);
    // Per-channel FSM states.
    // 每个外部 memory channel 都会在这些状态之间独立切换。
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Each channel behaves like a tiny independent worker.
    // `controller_state [NUM_CHANNELS-1:0]` 表示“每个通道各自保存一个状态值”。
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0];

    // Bookkeeping bitmask: a 1 means some channel already claimed that consumer's pending request.
    // This prevents two channels from accidentally servicing the same client in parallel.
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer;

    always @(posedge clk) begin
        if (reset) begin 
            // Reset clears both sides of the handshake and returns every channel to IDLE.
            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            current_consumer <= 0;
            controller_state <= 0;

            channel_serving_consumer = 0;
        end else begin 
            // Process every external channel in parallel.
            // 这里的 for 循环是在 RTL 中“复制相似逻辑到每个通道”，不是软件串行跑很多次的意思。
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // Greedily scan consumers to find one pending request this idle channel can adopt.
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin 
                                // Claim this consumer so no other channel grabs it.
                                // 这里用阻塞赋值 `=` 改位图，是想在本拍后续逻辑里立刻看到“已被占用”的效果。
                                channel_serving_consumer[j] = 1;
                                current_consumer[i] <= j;

                                // Forward the read request out to memory on this channel.
                                mem_read_valid[i] <= 1;
                                mem_read_address[i] <= consumer_read_address[j];
                                controller_state[i] <= READ_WAITING;

                                // One channel handles at most one consumer at a time.
                                break;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin 
                                // Same idea for writes.
                                channel_serving_consumer[j] = 1;
                                current_consumer[i] <= j;

                                mem_write_valid[i] <= 1;
                                mem_write_address[i] <= consumer_write_address[j];
                                mem_write_data[i] <= consumer_write_data[j];
                                controller_state[i] <= WRITE_WAITING;

                                // Stop scanning once this channel has adopted one request.
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Keep waiting until external memory accepts/completes the read.
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;

                            // Relay the returned data back to the original consumer.
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait until external memory acknowledges the write.
                        if (mem_write_ready[i]) begin 
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 1;
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    // Keep ready asserted until the original consumer drops its valid signal.
                    // That "valid goes low" acts like an acknowledgement in this simple protocol.
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i]]) begin 
                            // 当消费者自己把 valid 拉低，说明这次读响应已经被它消费完了。
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i]]) begin 
                            // Release the claimed consumer so some future request can be serviced.
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
