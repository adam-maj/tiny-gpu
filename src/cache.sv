`default_nettype none
`timescale 1ns/1ns

// GENERIC SET-ASSOCIATIVE CACHE
// > Sits between NUM_CONSUMERS upstream requesters (LSUs for an L1, or per-core L1s for a shared L2)
//   and NUM_CHANNELS parallel downstream ports to the next memory level (another cache, or the
//   external memory controller).
// > Write-through, no-write-allocate: stores are always forwarded downstream, and also update the
//   line in place if it's already cached (write-update-on-hit). This avoids needing a dirty/write-back
//   protocol or cross-cache invalidation broadcast to stay correct.
// > Each of the NUM_CHANNELS internal "ways in" can independently track a miss (non-blocking cache
//   with NUM_CHANNELS outstanding misses), so a miss on one set doesn't stall hits/misses on others.
// > To avoid two channels racing on the same set (e.g. both filling into the same line, corrupting
//   LRU/way state), a set is locked from admission until the channel handling it fully resolves.
module cache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter NUM_CONSUMERS = 4,   // Number of upstream requesters (LSUs, or lower-level caches)
    parameter NUM_CHANNELS = 2,    // Number of concurrent in-flight requests this cache can track
    parameter NUM_SETS = 8,        // Number of cache sets (must be a power of 2, >= 2)
    parameter WAYS = 2,            // Associativity: lines per set (>= 1)
    parameter LINE_SIZE = 4        // Words per cache line (must be a power of 2, >= 2)
) (
    input wire clk,
    input wire reset,

    // Consumer Interface (LSUs, or lower-level caches)
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory-side Interface (next cache level, or the memory controller) - NUM_CHANNELS wide
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_write_ready,

    // Stats - useful for profiling kernels & for tests to assert on cache behavior
    output reg [31:0] hit_count,
    output reg [31:0] miss_count
);
    localparam OFFSET_BITS = $clog2(LINE_SIZE);
    localparam INDEX_BITS = $clog2(NUM_SETS);
    localparam TAG_BITS = ADDR_BITS - OFFSET_BITS - INDEX_BITS;
    localparam NUM_LINES = NUM_SETS * WAYS;

    localparam WAY_BITS = (WAYS <= 1) ? 1 : $clog2(WAYS);
    localparam CONSUMER_BITS = (NUM_CONSUMERS <= 1) ? 1 : $clog2(NUM_CONSUMERS);

    localparam IDLE = 3'd0,
        FILL_WAIT = 3'd1,
        FILL_NEXT = 3'd2,
        WRITE_WAIT = 3'd3,
        RELAY_READ = 3'd4,
        RELAY_WRITE = 3'd5;

    // Per-channel pipeline state
    reg [2:0] channel_state [NUM_CHANNELS-1:0];
    reg [CONSUMER_BITS-1:0] channel_consumer [NUM_CHANNELS-1:0];
    reg [ADDR_BITS-1:0] channel_address [NUM_CHANNELS-1:0];
    reg [DATA_BITS-1:0] channel_wdata [NUM_CHANNELS-1:0];
    reg [WAY_BITS-1:0] channel_way [NUM_CHANNELS-1:0];
    reg [INDEX_BITS-1:0] channel_set [NUM_CHANNELS-1:0];
    reg [OFFSET_BITS-1:0] channel_fill_offset [NUM_CHANNELS-1:0];
    reg [ADDR_BITS-1:0] channel_line_base [NUM_CHANNELS-1:0];

    // Which channel (if any) is currently serving each consumer - prevents double pick-up
    reg [NUM_CONSUMERS-1:0] consumer_being_served;
    // Which sets currently have an in-flight transaction against them (any channel)
    reg [NUM_SETS-1:0] set_busy;

    // Cache storage, flattened: line index = set * WAYS + way
    reg valid [NUM_LINES-1:0];
    reg [TAG_BITS-1:0] tags [NUM_LINES-1:0];
    reg [7:0] age [NUM_LINES-1:0]; // pseudo-LRU: higher = older/less-recently-used
    reg [DATA_BITS-1:0] line_data [(NUM_LINES*LINE_SIZE)-1:0];

    always @(posedge clk) begin
        if (reset) begin
            hit_count <= 0;
            miss_count <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_being_served = 0;
            set_busy = 0;

            for (int c = 0; c < NUM_CHANNELS; c = c + 1) begin
                channel_state[c] <= IDLE;
            end

            for (int l = 0; l < NUM_LINES; l = l + 1) begin
                valid[l] <= 1'b0;
                age[l] <= 8'b0;
            end
        end else begin
            integer hits_this_cycle;
            integer misses_this_cycle;
            hits_this_cycle = 0;
            misses_this_cycle = 0;

            for (int c = 0; c < NUM_CHANNELS; c = c + 1) begin
                case (channel_state[c])
                    IDLE: begin
                        // Scan consumers for a pending request not already claimed by another channel
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if ((consumer_read_valid[j] || consumer_write_valid[j]) && !consumer_being_served[j]) begin
                                reg [ADDR_BITS-1:0] req_addr;
                                reg [TAG_BITS-1:0] req_tag;
                                reg [INDEX_BITS-1:0] req_set;
                                reg is_write;
                                reg found_hit;
                                reg [WAY_BITS-1:0] found_way;
                                reg [WAY_BITS-1:0] victim_way;
                                reg [7:0] oldest_age;

                                is_write = consumer_write_valid[j];
                                req_addr = is_write ? consumer_write_address[j] : consumer_read_address[j];
                                req_tag = req_addr[ADDR_BITS-1:OFFSET_BITS+INDEX_BITS];
                                req_set = req_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];

                                // Don't admit a new request against a set another channel is still resolving
                                if (!set_busy[req_set]) begin
                                    found_hit = 1'b0;
                                    found_way = 0;
                                    victim_way = 0;
                                    oldest_age = 0;
                                    for (int w = 0; w < WAYS; w = w + 1) begin
                                        if (valid[req_set*WAYS + w] && tags[req_set*WAYS + w] == req_tag) begin
                                            found_hit = 1'b1;
                                            found_way = w[WAY_BITS-1:0];
                                        end
                                        if (age[req_set*WAYS + w] >= oldest_age) begin
                                            oldest_age = age[req_set*WAYS + w];
                                            victim_way = w[WAY_BITS-1:0];
                                        end
                                    end

                                    consumer_being_served[j] = 1;
                                    set_busy[req_set] = 1;
                                    channel_consumer[c] <= j[CONSUMER_BITS-1:0];
                                    channel_address[c] <= req_addr;
                                    channel_set[c] <= req_set;

                                    if (is_write) begin
                                        // Write-through: always forward the store downstream
                                        channel_wdata[c] <= consumer_write_data[j];
                                        mem_write_valid[c] <= 1;
                                        mem_write_address[c] <= req_addr;
                                        mem_write_data[c] <= consumer_write_data[j];
                                        channel_state[c] <= WRITE_WAIT;

                                        if (found_hit) begin
                                            // Write-update-on-hit: keep the cached copy fresh
                                            line_data[(req_set*WAYS + found_way)*LINE_SIZE + req_addr[OFFSET_BITS-1:0]] <= consumer_write_data[j];
                                            for (int w2 = 0; w2 < WAYS; w2 = w2 + 1) begin
                                                age[req_set*WAYS + w2] <= (w2 == found_way) ? 8'b0 :
                                                    ((age[req_set*WAYS + w2] == 8'hFF) ? 8'hFF : age[req_set*WAYS + w2] + 1'b1);
                                            end
                                        end
                                    end else if (found_hit) begin
                                        hits_this_cycle = hits_this_cycle + 1;
                                        consumer_read_ready[j] <= 1;
                                        consumer_read_data[j] <= line_data[(req_set*WAYS + found_way)*LINE_SIZE + req_addr[OFFSET_BITS-1:0]];
                                        channel_state[c] <= RELAY_READ;

                                        for (int w2 = 0; w2 < WAYS; w2 = w2 + 1) begin
                                            age[req_set*WAYS + w2] <= (w2 == found_way) ? 8'b0 :
                                                ((age[req_set*WAYS + w2] == 8'hFF) ? 8'hFF : age[req_set*WAYS + w2] + 1'b1);
                                        end
                                    end else begin
                                        // Read miss: kick off a line fill starting at the line-aligned base address
                                        misses_this_cycle = misses_this_cycle + 1;
                                        channel_way[c] <= victim_way;
                                        channel_fill_offset[c] <= 0;
                                        channel_line_base[c] <= {req_tag, req_set, {OFFSET_BITS{1'b0}}};
                                        mem_read_valid[c] <= 1;
                                        mem_read_address[c] <= {req_tag, req_set, {OFFSET_BITS{1'b0}}};
                                        channel_state[c] <= FILL_WAIT;
                                    end

                                    // Only stop scanning once we've actually admitted a request -
                                    // a request whose set is busy is left pending and we keep
                                    // looking for another consumer this channel can serve instead.
                                    break;
                                end
                            end
                        end
                    end
                    FILL_WAIT: begin
                        if (mem_read_ready[c]) begin
                            reg [INDEX_BITS-1:0] set_i;
                            reg [WAY_BITS-1:0] way_i;
                            reg [OFFSET_BITS-1:0] off_i;
                            reg [OFFSET_BITS-1:0] want_off;
                            set_i = channel_set[c];
                            way_i = channel_way[c];
                            off_i = channel_fill_offset[c];
                            want_off = channel_address[c][OFFSET_BITS-1:0];

                            line_data[(set_i*WAYS + way_i)*LINE_SIZE + off_i] <= mem_read_data[c];

                            if (off_i == want_off) begin
                                consumer_read_data[channel_consumer[c]] <= mem_read_data[c];
                            end

                            // Always drop valid after consuming a response - never overlap it with
                            // presenting a new address, otherwise the memory below (which responds
                            // fresh every cycle it sees valid asserted) can answer the next word's
                            // request using this cycle's still-old address before it updates.
                            mem_read_valid[c] <= 0;

                            if (off_i == LINE_SIZE - 1) begin
                                // Line fully fetched - commit tag/valid and hand back the wanted word
                                tags[set_i*WAYS + way_i] <= channel_address[c][ADDR_BITS-1:OFFSET_BITS+INDEX_BITS];
                                valid[set_i*WAYS + way_i] <= 1'b1;
                                for (int w2 = 0; w2 < WAYS; w2 = w2 + 1) begin
                                    age[set_i*WAYS + w2] <= (w2 == way_i) ? 8'b0 :
                                        ((age[set_i*WAYS + w2] == 8'hFF) ? 8'hFF : age[set_i*WAYS + w2] + 1'b1);
                                end
                                consumer_read_ready[channel_consumer[c]] <= 1;
                                channel_state[c] <= RELAY_READ;
                            end else begin
                                channel_fill_offset[c] <= off_i + 1'b1;
                                channel_state[c] <= FILL_NEXT;
                            end
                        end
                    end
                    FILL_NEXT: begin
                        // Wait for the downstream ready to actually clear before presenting the next
                        // word's address - with a registered hop in between (e.g. L1 talking to L2
                        // through gpu.sv's pass-through), a fixed one-cycle wait isn't long enough
                        // for our valid-drop to be observed downstream, so a stale ready can still be
                        // in flight back to us. Waiting for ready==0 makes this robust to any latency.
                        if (!mem_read_ready[c]) begin
                            mem_read_valid[c] <= 1;
                            mem_read_address[c] <= channel_line_base[c] + channel_fill_offset[c];
                            channel_state[c] <= FILL_WAIT;
                        end
                    end
                    WRITE_WAIT: begin
                        if (mem_write_ready[c]) begin
                            mem_write_valid[c] <= 0;
                            consumer_write_ready[channel_consumer[c]] <= 1;
                            channel_state[c] <= RELAY_WRITE;
                        end
                    end
                    RELAY_READ: begin
                        if (!consumer_read_valid[channel_consumer[c]]) begin
                            consumer_read_ready[channel_consumer[c]] <= 0;
                            consumer_being_served[channel_consumer[c]] = 0;
                            set_busy[channel_set[c]] = 0;
                            channel_state[c] <= IDLE;
                        end
                    end
                    RELAY_WRITE: begin
                        if (!consumer_write_valid[channel_consumer[c]]) begin
                            consumer_write_ready[channel_consumer[c]] <= 0;
                            consumer_being_served[channel_consumer[c]] = 0;
                            set_busy[channel_set[c]] = 0;
                            channel_state[c] <= IDLE;
                        end
                    end
                endcase
            end

            hit_count <= hit_count + hits_this_cycle;
            miss_count <= miss_count + misses_this_cycle;
        end
    end
endmodule
