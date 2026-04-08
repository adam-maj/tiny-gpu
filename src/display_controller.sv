// Display Controller - Video Output and Scanout Engine
// Enterprise-grade display controller with multi-monitor support
// Compatible with: DisplayPort 1.4, HDMI 2.1, VGA timing
// IEEE 1800-2012 SystemVerilog

module display_controller #(
    parameter NUM_DISPLAYS = 4,
    parameter MAX_H_RES = 3840,
    parameter MAX_V_RES = 2160,
    parameter PIXEL_DEPTH = 30,         // 10-bit per channel
    parameter FRAMEBUFFER_WIDTH = 128,
    parameter NUM_PLANES = 4            // Overlay planes
) (
    input  logic                    clk,              // System clock
    input  logic                    pixel_clk,        // Pixel clock (variable)
    input  logic                    rst_n,
    
    // Framebuffer Read Interface
    output logic                    fb_read_valid,
    output logic [31:0]             fb_read_addr,
    input  logic [FRAMEBUFFER_WIDTH-1:0] fb_read_data,
    input  logic                    fb_read_ready,
    
    // Display Output Interface (active display selected)
    output logic                    display_valid,
    output logic [PIXEL_DEPTH-1:0]  display_pixel,
    output logic                    display_hsync,
    output logic                    display_vsync,
    output logic                    display_data_enable,
    output logic                    display_blank,
    
    // Multi-Display Selection
    input  logic [1:0]              active_display,
    
    // Timing Configuration (per display)
    input  logic [12:0]             h_active [NUM_DISPLAYS],
    input  logic [7:0]              h_front_porch [NUM_DISPLAYS],
    input  logic [7:0]              h_sync_width [NUM_DISPLAYS],
    input  logic [8:0]              h_back_porch [NUM_DISPLAYS],
    input  logic [11:0]             v_active [NUM_DISPLAYS],
    input  logic [5:0]              v_front_porch [NUM_DISPLAYS],
    input  logic [5:0]              v_sync_width [NUM_DISPLAYS],
    input  logic [6:0]              v_back_porch [NUM_DISPLAYS],
    input  logic                    hsync_polarity [NUM_DISPLAYS],
    input  logic                    vsync_polarity [NUM_DISPLAYS],
    
    // Framebuffer Configuration
    input  logic [31:0]             fb_base_addr [NUM_DISPLAYS],
    input  logic [15:0]             fb_stride [NUM_DISPLAYS],     // Bytes per row
    input  logic [3:0]              fb_format [NUM_DISPLAYS],     // Pixel format
    
    // Overlay Plane Configuration
    input  logic [NUM_PLANES-1:0]   plane_enable,
    input  logic [31:0]             plane_base [NUM_PLANES],
    input  logic [12:0]             plane_x [NUM_PLANES],
    input  logic [11:0]             plane_y [NUM_PLANES],
    input  logic [12:0]             plane_width [NUM_PLANES],
    input  logic [11:0]             plane_height [NUM_PLANES],
    input  logic [7:0]              plane_alpha [NUM_PLANES],
    
    // Cursor Configuration
    input  logic                    cursor_enable,
    input  logic [31:0]             cursor_base,
    input  logic [12:0]             cursor_x,
    input  logic [11:0]             cursor_y,
    input  logic [5:0]              cursor_width,
    input  logic [5:0]              cursor_height,
    input  logic [31:0]             cursor_color,
    
    // Color Management
    input  logic                    gamma_enable,
    input  logic [9:0]              gamma_lut_r [256],
    input  logic [9:0]              gamma_lut_g [256],
    input  logic [9:0]              gamma_lut_b [256],
    
    // Status
    output logic [NUM_DISPLAYS-1:0] display_connected,
    output logic                    vblank_interrupt,
    output logic [31:0]             frame_count,
    output logic [15:0]             current_line,
    output logic [15:0]             current_pixel
);

    // Pixel formats
    localparam FMT_ARGB8888 = 4'd0;
    localparam FMT_XRGB8888 = 4'd1;
    localparam FMT_RGB888 = 4'd2;
    localparam FMT_RGB565 = 4'd3;
    localparam FMT_ARGB2101010 = 4'd4;
    localparam FMT_XRGB2101010 = 4'd5;
    localparam FMT_YUV422 = 4'd6;
    localparam FMT_YUV420 = 4'd7;
    
    // Timing counters
    logic [12:0] h_counter;
    logic [11:0] v_counter;
    
    // Total timing values (computed)
    wire [12:0] h_total = h_active[active_display] + h_front_porch[active_display] + 
                          h_sync_width[active_display] + h_back_porch[active_display];
    wire [11:0] v_total = v_active[active_display] + v_front_porch[active_display] + 
                          v_sync_width[active_display] + v_back_porch[active_display];
    
    // Active region detection
    wire h_active_region = (h_counter >= (h_sync_width[active_display] + h_back_porch[active_display])) &&
                           (h_counter < (h_sync_width[active_display] + h_back_porch[active_display] + h_active[active_display]));
    wire v_active_region = (v_counter >= (v_sync_width[active_display] + v_back_porch[active_display])) &&
                           (v_counter < (v_sync_width[active_display] + v_back_porch[active_display] + v_active[active_display]));
    wire active_region = h_active_region && v_active_region;
    
    // Current pixel position in active region
    wire [12:0] pixel_x = h_counter - h_sync_width[active_display] - h_back_porch[active_display];
    wire [11:0] pixel_y = v_counter - v_sync_width[active_display] - v_back_porch[active_display];
    
    // Sync generation
    wire h_sync = (h_counter < h_sync_width[active_display]) ^ hsync_polarity[active_display];
    wire v_sync = (v_counter < v_sync_width[active_display]) ^ vsync_polarity[active_display];
    
    // Prefetch FIFO
    localparam FIFO_DEPTH = 64;
    logic [PIXEL_DEPTH-1:0] pixel_fifo [FIFO_DEPTH];
    logic [$clog2(FIFO_DEPTH)-1:0] fifo_write_ptr;
    logic [$clog2(FIFO_DEPTH)-1:0] fifo_read_ptr;
    logic [$clog2(FIFO_DEPTH):0] fifo_count;
    
    wire fifo_empty = (fifo_count == 0);
    wire fifo_full = (fifo_count >= FIFO_DEPTH - 4);
    
    // Fetch state machine
    typedef enum logic [2:0] {
        FETCH_IDLE,
        FETCH_REQUEST,
        FETCH_WAIT,
        FETCH_STORE,
        FETCH_NEXT_LINE
    } fetch_state_t;
    
    fetch_state_t fetch_state;
    
    logic [12:0] fetch_x;
    logic [11:0] fetch_y;
    logic [31:0] current_fb_addr;
    
    // Overlay compositing
    logic [PIXEL_DEPTH-1:0] base_pixel;
    logic [PIXEL_DEPTH-1:0] overlay_pixel [NUM_PLANES];
    logic [PIXEL_DEPTH-1:0] composited_pixel;
    logic [PIXEL_DEPTH-1:0] cursor_pixel;
    logic [PIXEL_DEPTH-1:0] gamma_corrected_pixel;
    
    // VBlank detection
    wire vblank = (v_counter >= (v_sync_width[active_display] + v_back_porch[active_display] + v_active[active_display]));
    logic vblank_prev;
    
    // Horizontal and vertical counter logic
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_counter <= 13'd0;
            v_counter <= 12'd0;
            frame_count <= 32'd0;
            vblank_prev <= 1'b0;
            vblank_interrupt <= 1'b0;
        end else begin
            vblank_prev <= vblank;
            vblank_interrupt <= (vblank && !vblank_prev);
            
            if (h_counter >= h_total - 1) begin
                h_counter <= 13'd0;
                
                if (v_counter >= v_total - 1) begin
                    v_counter <= 12'd0;
                    frame_count <= frame_count + 1'b1;
                end else begin
                    v_counter <= v_counter + 1'b1;
                end
            end else begin
                h_counter <= h_counter + 1'b1;
            end
        end
    end
    
    // Framebuffer fetch logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_state <= FETCH_IDLE;
            fb_read_valid <= 1'b0;
            fetch_x <= 13'd0;
            fetch_y <= 12'd0;
            fifo_write_ptr <= '0;
            fifo_count <= '0;
        end else begin
            case (fetch_state)
                FETCH_IDLE: begin
                    if (!fifo_full && active_region) begin
                        fetch_state <= FETCH_REQUEST;
                    end
                end
                
                FETCH_REQUEST: begin
                    fb_read_valid <= 1'b1;
                    current_fb_addr <= fb_base_addr[active_display] + 
                                      (fetch_y * fb_stride[active_display]) + 
                                      (fetch_x << 2);  // 4 bytes per pixel
                    fb_read_addr <= current_fb_addr;
                    fetch_state <= FETCH_WAIT;
                end
                
                FETCH_WAIT: begin
                    if (fb_read_ready) begin
                        fb_read_valid <= 1'b0;
                        fetch_state <= FETCH_STORE;
                    end
                end
                
                FETCH_STORE: begin
                    // Convert format and store in FIFO
                    // Supports 4 pixels per 128-bit read for ARGB8888
                    for (int i = 0; i < 4 && fetch_x + i < h_active[active_display]; i++) begin
                        logic [31:0] pixel32;
                        pixel32 = fb_read_data[i*32 +: 32];
                        
                        case (fb_format[active_display])
                            FMT_ARGB8888, FMT_XRGB8888: begin
                                pixel_fifo[fifo_write_ptr + i] <= {
                                    pixel32[17:10],  // R (8 bits -> 10 bits scaled)
                                    2'b00,
                                    pixel32[9:2],    // G
                                    2'b00,
                                    pixel32[1:0],    // B
                                    pixel32[25:18],
                                    2'b00
                                };
                            end
                            
                            FMT_ARGB2101010, FMT_XRGB2101010: begin
                                pixel_fifo[fifo_write_ptr + i] <= pixel32[29:0];
                            end
                            
                            default: begin
                                pixel_fifo[fifo_write_ptr + i] <= pixel32[29:0];
                            end
                        endcase
                    end
                    
                    fifo_write_ptr <= fifo_write_ptr + 4;
                    fifo_count <= fifo_count + 4;
                    fetch_x <= fetch_x + 4;
                    
                    if (fetch_x + 4 >= h_active[active_display]) begin
                        fetch_state <= FETCH_NEXT_LINE;
                    end else if (fifo_full) begin
                        fetch_state <= FETCH_IDLE;
                    end else begin
                        fetch_state <= FETCH_REQUEST;
                    end
                end
                
                FETCH_NEXT_LINE: begin
                    fetch_x <= 13'd0;
                    fetch_y <= (fetch_y >= v_active[active_display] - 1) ? 12'd0 : fetch_y + 1'b1;
                    fetch_state <= FETCH_IDLE;
                end
                
                default: fetch_state <= FETCH_IDLE;
            endcase
        end
    end
    
    // Pixel output and FIFO read
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_read_ptr <= '0;
            display_valid <= 1'b0;
            display_hsync <= 1'b0;
            display_vsync <= 1'b0;
            display_data_enable <= 1'b0;
            display_blank <= 1'b1;
            display_pixel <= '0;
            current_line <= 16'd0;
            current_pixel <= 16'd0;
        end else begin
            display_hsync <= h_sync;
            display_vsync <= v_sync;
            display_data_enable <= active_region;
            display_blank <= !active_region;
            display_valid <= active_region;
            current_line <= {4'd0, pixel_y};
            current_pixel <= {3'd0, pixel_x};
            
            if (active_region && !fifo_empty) begin
                base_pixel <= pixel_fifo[fifo_read_ptr];
                fifo_read_ptr <= fifo_read_ptr + 1'b1;
                
                // Overlay compositing
                composited_pixel <= base_pixel;
                
                // Cursor overlay
                if (cursor_enable && 
                    pixel_x >= cursor_x && pixel_x < cursor_x + cursor_width &&
                    pixel_y >= cursor_y && pixel_y < cursor_y + cursor_height) begin
                    composited_pixel <= cursor_color[29:0];
                end
                
                // Gamma correction
                if (gamma_enable) begin
                    gamma_corrected_pixel[29:20] <= gamma_lut_r[composited_pixel[29:22]];
                    gamma_corrected_pixel[19:10] <= gamma_lut_g[composited_pixel[19:12]];
                    gamma_corrected_pixel[9:0] <= gamma_lut_b[composited_pixel[9:2]];
                    display_pixel <= gamma_corrected_pixel;
                end else begin
                    display_pixel <= composited_pixel;
                end
            end else begin
                display_pixel <= '0;  // Black during blanking
            end
        end
    end
    
    // Display connection detection (simplified - would use HPD in real design)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_connected <= '0;
        end else begin
            // Assume all displays connected for simulation
            display_connected <= {NUM_DISPLAYS{1'b1}};
        end
    end

endmodule
