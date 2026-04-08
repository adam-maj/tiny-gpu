`default_nettype none
`timescale 1ns/1ns

// FRAMEBUFFER
// > Simple dual-port framebuffer for graphics output
// > Write port: receives pixels from rasterizer
// > Read port: outputs pixels for display
// > Supports configurable resolution and color depth
module framebuffer #(
    parameter WIDTH = 64,         // Framebuffer width
    parameter HEIGHT = 64,        // Framebuffer height
    parameter COLOR_BITS = 8,     // Bits per pixel
    parameter ADDR_BITS = 12      // Address bits (must cover WIDTH*HEIGHT)
) (
    input wire clk,
    input wire reset,

    // Write Port (from rasterizer)
    input wire write_enable,
    input wire [$clog2(WIDTH)-1:0] write_x,
    input wire [$clog2(HEIGHT)-1:0] write_y,
    input wire [COLOR_BITS-1:0] write_data,
    output reg write_ack,

    // Read Port (for display output)
    input wire read_enable,
    input wire [$clog2(WIDTH)-1:0] read_x,
    input wire [$clog2(HEIGHT)-1:0] read_y,
    output reg [COLOR_BITS-1:0] read_data,
    output reg read_valid,

    // Clear control
    input wire clear_enable,
    input wire [COLOR_BITS-1:0] clear_color,
    output reg clear_done,

    // Status
    output wire [ADDR_BITS-1:0] total_pixels
);
    // Calculate total pixels
    assign total_pixels = WIDTH * HEIGHT;

    // Framebuffer memory
    reg [COLOR_BITS-1:0] fb_mem [0:WIDTH*HEIGHT-1];

    // Address calculation
    wire [ADDR_BITS-1:0] write_addr = write_y * WIDTH + write_x;
    wire [ADDR_BITS-1:0] read_addr = read_y * WIDTH + read_x;

    // Clear state machine
    reg clearing;
    reg [ADDR_BITS-1:0] clear_addr;

    always @(posedge clk) begin
        if (reset) begin
            write_ack <= 0;
            read_data <= 0;
            read_valid <= 0;
            clear_done <= 0;
            clearing <= 0;
            clear_addr <= 0;
        end else begin
            // Default: deassert acknowledgments
            write_ack <= 0;
            read_valid <= 0;
            clear_done <= 0;

            // Clear operation (takes multiple cycles)
            if (clear_enable && !clearing) begin
                clearing <= 1;
                clear_addr <= 0;
            end

            if (clearing) begin
                fb_mem[clear_addr] <= clear_color;
                if (clear_addr >= WIDTH * HEIGHT - 1) begin
                    clearing <= 0;
                    clear_done <= 1;
                end else begin
                    clear_addr <= clear_addr + 1;
                end
            end
            // Normal write operation
            else if (write_enable) begin
                if (write_addr < WIDTH * HEIGHT) begin
                    fb_mem[write_addr] <= write_data;
                end
                write_ack <= 1;
            end

            // Read operation (concurrent with write)
            if (read_enable) begin
                if (read_addr < WIDTH * HEIGHT) begin
                    read_data <= fb_mem[read_addr];
                end else begin
                    read_data <= 0;
                end
                read_valid <= 1;
            end
        end
    end

endmodule
