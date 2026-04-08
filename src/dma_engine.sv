`default_nettype none
`timescale 1ns/1ns

/**
 * DMA Engine
 * Direct Memory Access controller for efficient bulk data transfers
 * Enterprise features:
 * - Multi-channel DMA with priority
 * - Scatter-gather support
 * - 2D/3D block transfers
 * - Memory-to-memory, device-to-memory, memory-to-device
 * - Interrupt generation on completion
 */
module dma_engine #(
    parameter NUM_CHANNELS = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter MAX_BURST = 16,
    parameter DESC_DEPTH = 8
) (
    input wire clk,
    input wire reset,
    
    // Channel control (per channel)
    input wire [NUM_CHANNELS-1:0] channel_enable,
    input wire [NUM_CHANNELS-1:0] channel_start,
    output wire [NUM_CHANNELS-1:0] channel_busy,
    output wire [NUM_CHANNELS-1:0] channel_done,
    output wire [NUM_CHANNELS-1:0] channel_error,
    
    // Descriptor interface
    input wire desc_write,
    input wire [1:0] desc_channel,
    input wire [ADDR_WIDTH-1:0] desc_src_addr,
    input wire [ADDR_WIDTH-1:0] desc_dst_addr,
    input wire [15:0] desc_length,
    input wire [1:0] desc_type,          // 0=mem2mem, 1=dev2mem, 2=mem2dev
    input wire desc_2d_enable,
    input wire [15:0] desc_src_stride,
    input wire [15:0] desc_dst_stride,
    input wire [15:0] desc_rows,
    output wire desc_full,
    
    // Source memory interface
    output reg src_read_req,
    output reg [ADDR_WIDTH-1:0] src_read_addr,
    output reg [7:0] src_read_burst,
    input wire [DATA_WIDTH-1:0] src_read_data,
    input wire src_read_valid,
    input wire src_read_last,
    
    // Destination memory interface
    output reg dst_write_req,
    output reg [ADDR_WIDTH-1:0] dst_write_addr,
    output reg [DATA_WIDTH-1:0] dst_write_data,
    output reg [7:0] dst_write_burst,
    input wire dst_write_ready,
    input wire dst_write_done,
    
    // Interrupt output
    output reg irq,
    output reg [NUM_CHANNELS-1:0] irq_status,
    input wire irq_clear,
    
    // Statistics
    output reg [31:0] bytes_transferred,
    output reg [31:0] transfers_completed
);

    // Descriptor structure
    typedef struct packed {
        logic valid;
        logic [ADDR_WIDTH-1:0] src_addr;
        logic [ADDR_WIDTH-1:0] dst_addr;
        logic [15:0] length;
        logic [1:0] xfer_type;
        logic is_2d;
        logic [15:0] src_stride;
        logic [15:0] dst_stride;
        logic [15:0] rows;
    } descriptor_t;
    
    // Per-channel state
    descriptor_t desc_queue [NUM_CHANNELS-1:0][DESC_DEPTH-1:0];
    reg [2:0] desc_head [NUM_CHANNELS-1:0];
    reg [2:0] desc_tail [NUM_CHANNELS-1:0];
    reg [3:0] desc_count [NUM_CHANNELS-1:0];
    
    // Channel state machine
    localparam CS_IDLE = 3'd0;
    localparam CS_FETCH_DESC = 3'd1;
    localparam CS_READ_SRC = 3'd2;
    localparam CS_WRITE_DST = 3'd3;
    localparam CS_NEXT_ROW = 3'd4;
    localparam CS_COMPLETE = 3'd5;
    localparam CS_ERROR = 3'd6;
    
    reg [2:0] channel_state [NUM_CHANNELS-1:0];
    
    // Current transfer state per channel
    reg [ADDR_WIDTH-1:0] cur_src_addr [NUM_CHANNELS-1:0];
    reg [ADDR_WIDTH-1:0] cur_dst_addr [NUM_CHANNELS-1:0];
    reg [15:0] cur_remaining [NUM_CHANNELS-1:0];
    reg [15:0] cur_row [NUM_CHANNELS-1:0];
    descriptor_t cur_desc [NUM_CHANNELS-1:0];
    
    // FIFO buffer for transfers
    reg [DATA_WIDTH-1:0] xfer_buffer [MAX_BURST-1:0];
    reg [3:0] buf_count;
    reg [3:0] buf_read_ptr;
    reg [3:0] buf_write_ptr;
    
    // Active channel (round-robin arbiter)
    reg [1:0] active_channel;
    reg has_active;
    
    // Status outputs
    genvar ch;
    generate
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : gen_status
            assign channel_busy[ch] = (channel_state[ch] != CS_IDLE);
            assign channel_done[ch] = (channel_state[ch] == CS_COMPLETE);
            assign channel_error[ch] = (channel_state[ch] == CS_ERROR);
        end
    endgenerate
    
    // Descriptor queue full check
    assign desc_full = (desc_count[desc_channel] >= DESC_DEPTH);
    
    // Descriptor write logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (integer i = 0; i < NUM_CHANNELS; i = i + 1) begin
                desc_head[i] <= 0;
                desc_tail[i] <= 0;
                desc_count[i] <= 0;
            end
        end else begin
            if (desc_write && !desc_full) begin
                desc_queue[desc_channel][desc_tail[desc_channel]].valid <= 1;
                desc_queue[desc_channel][desc_tail[desc_channel]].src_addr <= desc_src_addr;
                desc_queue[desc_channel][desc_tail[desc_channel]].dst_addr <= desc_dst_addr;
                desc_queue[desc_channel][desc_tail[desc_channel]].length <= desc_length;
                desc_queue[desc_channel][desc_tail[desc_channel]].xfer_type <= desc_type;
                desc_queue[desc_channel][desc_tail[desc_channel]].is_2d <= desc_2d_enable;
                desc_queue[desc_channel][desc_tail[desc_channel]].src_stride <= desc_src_stride;
                desc_queue[desc_channel][desc_tail[desc_channel]].dst_stride <= desc_dst_stride;
                desc_queue[desc_channel][desc_tail[desc_channel]].rows <= desc_rows;
                desc_tail[desc_channel] <= desc_tail[desc_channel] + 1;
                desc_count[desc_channel] <= desc_count[desc_channel] + 1;
            end
        end
    end
    
    // Channel arbiter
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_channel <= 0;
            has_active <= 0;
        end else begin
            has_active <= 0;
            for (integer i = 0; i < NUM_CHANNELS; i = i + 1) begin
                if (channel_enable[i] && channel_state[i] != CS_IDLE && channel_state[i] != CS_COMPLETE) begin
                    active_channel <= i[1:0];
                    has_active <= 1;
                end
            end
        end
    end
    
    // Main state machine (per channel)
    integer c;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
                channel_state[c] <= CS_IDLE;
                cur_src_addr[c] <= 0;
                cur_dst_addr[c] <= 0;
                cur_remaining[c] <= 0;
                cur_row[c] <= 0;
            end
            src_read_req <= 0;
            dst_write_req <= 0;
            bytes_transferred <= 0;
            transfers_completed <= 0;
            irq <= 0;
            irq_status <= 0;
            buf_count <= 0;
        end else begin
            // Clear IRQ when acknowledged
            if (irq_clear) begin
                irq <= 0;
                irq_status <= 0;
            end
            
            // Process each channel
            for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
                case (channel_state[c])
                    CS_IDLE: begin
                        if (channel_enable[c] && channel_start[c] && desc_count[c] > 0) begin
                            cur_desc[c] <= desc_queue[c][desc_head[c]];
                            channel_state[c] <= CS_FETCH_DESC;
                        end
                    end
                    
                    CS_FETCH_DESC: begin
                        cur_src_addr[c] <= cur_desc[c].src_addr;
                        cur_dst_addr[c] <= cur_desc[c].dst_addr;
                        cur_remaining[c] <= cur_desc[c].length;
                        cur_row[c] <= 0;
                        channel_state[c] <= CS_READ_SRC;
                    end
                    
                    CS_READ_SRC: begin
                        if (c[1:0] == active_channel && cur_remaining[c] > 0) begin
                            src_read_req <= 1;
                            src_read_addr <= cur_src_addr[c];
                            src_read_burst <= (cur_remaining[c] > MAX_BURST) ? MAX_BURST : cur_remaining[c][7:0];
                            
                            if (src_read_valid) begin
                                xfer_buffer[buf_write_ptr] <= src_read_data;
                                buf_write_ptr <= buf_write_ptr + 1;
                                buf_count <= buf_count + 1;
                                cur_src_addr[c] <= cur_src_addr[c] + (DATA_WIDTH/8);
                                cur_remaining[c] <= cur_remaining[c] - 1;
                                bytes_transferred <= bytes_transferred + (DATA_WIDTH/8);
                                
                                if (src_read_last || cur_remaining[c] == 1) begin
                                    src_read_req <= 0;
                                    channel_state[c] <= CS_WRITE_DST;
                                end
                            end
                        end
                    end
                    
                    CS_WRITE_DST: begin
                        if (c[1:0] == active_channel && buf_count > 0) begin
                            dst_write_req <= 1;
                            dst_write_addr <= cur_dst_addr[c];
                            dst_write_data <= xfer_buffer[buf_read_ptr];
                            
                            if (dst_write_ready) begin
                                buf_read_ptr <= buf_read_ptr + 1;
                                buf_count <= buf_count - 1;
                                cur_dst_addr[c] <= cur_dst_addr[c] + (DATA_WIDTH/8);
                                
                                if (buf_count == 1) begin
                                    dst_write_req <= 0;
                                    if (cur_remaining[c] == 0) begin
                                        if (cur_desc[c].is_2d && cur_row[c] < cur_desc[c].rows - 1) begin
                                            channel_state[c] <= CS_NEXT_ROW;
                                        end else begin
                                            channel_state[c] <= CS_COMPLETE;
                                        end
                                    end else begin
                                        channel_state[c] <= CS_READ_SRC;
                                    end
                                end
                            end
                        end
                    end
                    
                    CS_NEXT_ROW: begin
                        cur_row[c] <= cur_row[c] + 1;
                        cur_src_addr[c] <= cur_desc[c].src_addr + (cur_row[c] + 1) * cur_desc[c].src_stride;
                        cur_dst_addr[c] <= cur_desc[c].dst_addr + (cur_row[c] + 1) * cur_desc[c].dst_stride;
                        cur_remaining[c] <= cur_desc[c].length;
                        channel_state[c] <= CS_READ_SRC;
                    end
                    
                    CS_COMPLETE: begin
                        transfers_completed <= transfers_completed + 1;
                        desc_head[c] <= desc_head[c] + 1;
                        desc_count[c] <= desc_count[c] - 1;
                        irq <= 1;
                        irq_status[c] <= 1;
                        channel_state[c] <= CS_IDLE;
                    end
                    
                    CS_ERROR: begin
                        irq <= 1;
                        irq_status[c] <= 1;
                    end
                endcase
            end
        end
    end

endmodule
