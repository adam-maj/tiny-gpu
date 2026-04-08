`default_nettype none
`timescale 1ns/1ns

// SIMPLE RASTERIZER
// > Basic hardware rasterization unit for simple 2D graphics
// > Supports:
//   - Point drawing
//   - Line drawing (Bresenham's algorithm)
//   - Filled rectangle drawing
//   - Basic triangle rasterization (bounding box + edge test)
// > Outputs pixel coordinates and color to framebuffer
//
// Command format:
//   cmd[2:0] - Operation: 000=NOP, 001=POINT, 010=LINE, 011=RECT, 100=TRIANGLE
//   x0,y0    - First vertex
//   x1,y1    - Second vertex (for line/rect/triangle)
//   x2,y2    - Third vertex (for triangle)
//   color    - 8-bit color value (RRRGGGBB)
module rasterizer #(
    parameter COORD_BITS = 8,  // 256x256 max resolution
    parameter COLOR_BITS = 8   // 8-bit color
) (
    input wire clk,
    input wire reset,

    // Command Interface
    input wire cmd_valid,
    input wire [2:0] cmd_op,
    input wire [COORD_BITS-1:0] x0, y0,
    input wire [COORD_BITS-1:0] x1, y1,
    input wire [COORD_BITS-1:0] x2, y2,
    input wire [COLOR_BITS-1:0] color,
    output reg cmd_ready,

    // Pixel Output Interface
    output reg pixel_valid,
    output reg [COORD_BITS-1:0] pixel_x,
    output reg [COORD_BITS-1:0] pixel_y,
    output reg [COLOR_BITS-1:0] pixel_color,
    input wire pixel_ack,

    // Status
    output reg busy,
    output reg done
);
    // Operations
    localparam OP_NOP      = 3'b000,
               OP_POINT    = 3'b001,
               OP_LINE     = 3'b010,
               OP_RECT     = 3'b011,
               OP_TRIANGLE = 3'b100;

    // State machine
    localparam S_IDLE       = 3'b000,
               S_POINT      = 3'b001,
               S_LINE_INIT  = 3'b010,
               S_LINE_DRAW  = 3'b011,
               S_RECT_INIT  = 3'b100,
               S_RECT_DRAW  = 3'b101,
               S_TRI_INIT   = 3'b110,
               S_TRI_DRAW   = 3'b111;

    reg [2:0] state;

    // Saved command parameters
    reg [COORD_BITS-1:0] saved_x0, saved_y0;
    reg [COORD_BITS-1:0] saved_x1, saved_y1;
    reg [COORD_BITS-1:0] saved_x2, saved_y2;
    reg [COLOR_BITS-1:0] saved_color;

    // Line drawing state (Bresenham)
    reg signed [COORD_BITS:0] line_x, line_y;
    reg signed [COORD_BITS:0] line_dx, line_dy;
    reg signed [COORD_BITS+1:0] line_err;
    reg line_sx, line_sy;  // Step directions (+1 or -1)
    reg signed [COORD_BITS:0] line_e2;

    // Rectangle/Triangle drawing state
    reg [COORD_BITS-1:0] cur_x, cur_y;
    reg [COORD_BITS-1:0] min_x, min_y, max_x, max_y;

    // Helper: absolute value
    function [COORD_BITS-1:0] abs_diff;
        input [COORD_BITS-1:0] a, b;
        begin
            abs_diff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    // Helper: min/max
    function [COORD_BITS-1:0] min3;
        input [COORD_BITS-1:0] a, b, c;
        begin
            min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
        end
    endfunction

    function [COORD_BITS-1:0] max3;
        input [COORD_BITS-1:0] a, b, c;
        begin
            max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
        end
    endfunction

    // Edge function for triangle rasterization
    // Returns positive if point is on left side of edge
    function signed [COORD_BITS*2+1:0] edge_func;
        input signed [COORD_BITS:0] ax, ay;  // Edge start
        input signed [COORD_BITS:0] bx, by;  // Edge end
        input signed [COORD_BITS:0] px, py;  // Test point
        begin
            edge_func = (px - ax) * (by - ay) - (py - ay) * (bx - ax);
        end
    endfunction

    // Signed versions of triangle vertices for edge function
    wire signed [COORD_BITS:0] sx0 = {1'b0, saved_x0};
    wire signed [COORD_BITS:0] sy0 = {1'b0, saved_y0};
    wire signed [COORD_BITS:0] sx1 = {1'b0, saved_x1};
    wire signed [COORD_BITS:0] sy1 = {1'b0, saved_y1};
    wire signed [COORD_BITS:0] sx2 = {1'b0, saved_x2};
    wire signed [COORD_BITS:0] sy2 = {1'b0, saved_y2};
    wire signed [COORD_BITS:0] spx = {1'b0, cur_x};
    wire signed [COORD_BITS:0] spy = {1'b0, cur_y};

    // Pre-compute edge functions for current pixel
    wire signed [COORD_BITS*2+1:0] e0 = edge_func(sx0, sy0, sx1, sy1, spx, spy);
    wire signed [COORD_BITS*2+1:0] e1 = edge_func(sx1, sy1, sx2, sy2, spx, spy);
    wire signed [COORD_BITS*2+1:0] e2_val = edge_func(sx2, sy2, sx0, sy0, spx, spy);
    wire inside_triangle = (e0 >= 0) && (e1 >= 0) && (e2_val >= 0);

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            cmd_ready <= 1;
            pixel_valid <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            pixel_color <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            // Default: deassert done after one cycle
            done <= 0;

            // Handle pixel acknowledgment
            if (pixel_valid && pixel_ack) begin
                pixel_valid <= 0;
            end

            case (state)
                S_IDLE: begin
                    cmd_ready <= 1;
                    busy <= 0;

                    if (cmd_valid) begin
                        cmd_ready <= 0;
                        busy <= 1;

                        // Save parameters
                        saved_x0 <= x0;
                        saved_y0 <= y0;
                        saved_x1 <= x1;
                        saved_y1 <= y1;
                        saved_x2 <= x2;
                        saved_y2 <= y2;
                        saved_color <= color;

                        case (cmd_op)
                            OP_POINT: state <= S_POINT;
                            OP_LINE: state <= S_LINE_INIT;
                            OP_RECT: state <= S_RECT_INIT;
                            OP_TRIANGLE: state <= S_TRI_INIT;
                            default: begin
                                done <= 1;
                                state <= S_IDLE;
                            end
                        endcase
                    end
                end

                S_POINT: begin
                    if (!pixel_valid) begin
                        pixel_valid <= 1;
                        pixel_x <= saved_x0;
                        pixel_y <= saved_y0;
                        pixel_color <= saved_color;
                        done <= 1;
                        state <= S_IDLE;
                    end
                end

                S_LINE_INIT: begin
                    // Initialize Bresenham's line algorithm
                    line_x <= {1'b0, saved_x0};
                    line_y <= {1'b0, saved_y0};
                    line_dx <= abs_diff(saved_x1, saved_x0);
                    line_dy <= abs_diff(saved_y1, saved_y0);
                    line_sx <= (saved_x0 < saved_x1);
                    line_sy <= (saved_y0 < saved_y1);
                    
                    // Initial error
                    if (abs_diff(saved_x1, saved_x0) > abs_diff(saved_y1, saved_y0)) begin
                        line_err <= abs_diff(saved_x1, saved_x0) - abs_diff(saved_y1, saved_y0);
                    end else begin
                        line_err <= abs_diff(saved_y1, saved_y0) - abs_diff(saved_x1, saved_x0);
                    end

                    state <= S_LINE_DRAW;
                end

                S_LINE_DRAW: begin
                    if (!pixel_valid) begin
                        // Output current pixel
                        pixel_valid <= 1;
                        pixel_x <= line_x[COORD_BITS-1:0];
                        pixel_y <= line_y[COORD_BITS-1:0];
                        pixel_color <= saved_color;

                        // Check if reached end
                        if (line_x[COORD_BITS-1:0] == saved_x1 && 
                            line_y[COORD_BITS-1:0] == saved_y1) begin
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            // Bresenham step
                            line_e2 <= line_err * 2;
                            
                            if (line_err * 2 >= -$signed({1'b0, line_dy})) begin
                                line_err <= line_err - line_dy;
                                line_x <= line_sx ? (line_x + 1) : (line_x - 1);
                            end
                            if (line_err * 2 <= $signed({1'b0, line_dx})) begin
                                line_err <= line_err + line_dx;
                                line_y <= line_sy ? (line_y + 1) : (line_y - 1);
                            end
                        end
                    end
                end

                S_RECT_INIT: begin
                    // Set up rectangle bounds
                    min_x <= (saved_x0 < saved_x1) ? saved_x0 : saved_x1;
                    min_y <= (saved_y0 < saved_y1) ? saved_y0 : saved_y1;
                    max_x <= (saved_x0 > saved_x1) ? saved_x0 : saved_x1;
                    max_y <= (saved_y0 > saved_y1) ? saved_y0 : saved_y1;
                    cur_x <= (saved_x0 < saved_x1) ? saved_x0 : saved_x1;
                    cur_y <= (saved_y0 < saved_y1) ? saved_y0 : saved_y1;
                    state <= S_RECT_DRAW;
                end

                S_RECT_DRAW: begin
                    if (!pixel_valid) begin
                        pixel_valid <= 1;
                        pixel_x <= cur_x;
                        pixel_y <= cur_y;
                        pixel_color <= saved_color;

                        // Advance to next pixel
                        if (cur_x >= max_x) begin
                            if (cur_y >= max_y) begin
                                done <= 1;
                                state <= S_IDLE;
                            end else begin
                                cur_x <= min_x;
                                cur_y <= cur_y + 1;
                            end
                        end else begin
                            cur_x <= cur_x + 1;
                        end
                    end
                end

                S_TRI_INIT: begin
                    // Compute bounding box of triangle
                    min_x <= min3(saved_x0, saved_x1, saved_x2);
                    min_y <= min3(saved_y0, saved_y1, saved_y2);
                    max_x <= max3(saved_x0, saved_x1, saved_x2);
                    max_y <= max3(saved_y0, saved_y1, saved_y2);
                    cur_x <= min3(saved_x0, saved_x1, saved_x2);
                    cur_y <= min3(saved_y0, saved_y1, saved_y2);
                    state <= S_TRI_DRAW;
                end

                S_TRI_DRAW: begin
                    if (!pixel_valid) begin
                        // Check if current pixel is inside triangle
                        if (inside_triangle) begin
                            pixel_valid <= 1;
                            pixel_x <= cur_x;
                            pixel_y <= cur_y;
                            pixel_color <= saved_color;
                        end

                        // Advance to next pixel in bounding box
                        if (cur_x >= max_x) begin
                            if (cur_y >= max_y) begin
                                done <= 1;
                                state <= S_IDLE;
                            end else begin
                                cur_x <= min_x;
                                cur_y <= cur_y + 1;
                            end
                        end else begin
                            cur_x <= cur_x + 1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
