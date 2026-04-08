`default_nettype none
`timescale 1ns/1ns

// TINY TAPEOUT 7 ADAPTER
// > Wrapper to interface tiny-gpu with Tiny Tapeout 7 pinout
// > Tiny Tapeout provides: 8 input pins, 8 output pins, 8 bidirectional I/O pins
// > This adapter provides a serial interface for programming and data access
//
// Pin Usage:
//   ui_in[7:0]  - Input: Command/Data input
//   uo_out[7:0] - Output: Status/Data output  
//   uio[7:0]    - Bidirectional: Extended data bus
//
// Protocol:
//   The GPU is controlled via a simple command protocol:
//   - Write to program memory
//   - Write to data memory
//   - Read from data memory
//   - Set thread count
//   - Start/Stop execution
//   - Read status
//
module tt_um_tiny_gpu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when design is selected
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Internal reset (active high)
    wire reset = !rst_n;

    // ========================================================================
    // Command Protocol Definition
    // ========================================================================
    // Commands are 4 bits in ui_in[7:4]
    localparam CMD_NOP           = 4'h0;  // No operation
    localparam CMD_SET_ADDR_LOW  = 4'h1;  // Set address low byte (data in ui_in[7:0] next cycle)
    localparam CMD_SET_ADDR_HIGH = 4'h2;  // Set address high byte
    localparam CMD_WRITE_PROG    = 4'h3;  // Write to program memory (16-bit, 2 cycles)
    localparam CMD_WRITE_DATA    = 4'h4;  // Write to data memory (8-bit)
    localparam CMD_READ_DATA     = 4'h5;  // Read from data memory
    localparam CMD_SET_THREADS   = 4'h6;  // Set thread count
    localparam CMD_START         = 4'h7;  // Start GPU execution
    localparam CMD_STOP          = 4'h8;  // Stop/Reset GPU
    localparam CMD_STATUS        = 4'h9;  // Read GPU status

    // ========================================================================
    // State Machine
    // ========================================================================
    localparam STATE_IDLE           = 4'h0;
    localparam STATE_SET_ADDR_LOW   = 4'h1;
    localparam STATE_SET_ADDR_HIGH  = 4'h2;
    localparam STATE_WRITE_PROG_H   = 4'h3;
    localparam STATE_WRITE_PROG_L   = 4'h4;
    localparam STATE_WRITE_DATA     = 4'h5;
    localparam STATE_READ_DATA      = 4'h6;
    localparam STATE_SET_THREADS    = 4'h7;
    localparam STATE_RUNNING        = 4'h8;

    reg [3:0] state;
    reg [7:0] addr_low;
    reg [7:0] addr_high;
    reg [15:0] write_addr;
    reg [7:0] prog_high_byte;

    // ========================================================================
    // Internal Memory (Small on-chip memory for Tiny Tapeout)
    // ========================================================================
    // Program memory: 64 x 16-bit instructions (reduced for area)
    // Data memory: 64 x 8-bit values (reduced for area)
    localparam PROG_MEM_SIZE = 64;
    localparam DATA_MEM_SIZE = 64;
    localparam PROG_ADDR_BITS = 6;
    localparam DATA_ADDR_BITS = 6;

    reg [15:0] program_memory [PROG_MEM_SIZE-1:0];
    reg [7:0] data_memory [DATA_MEM_SIZE-1:0];

    // GPU Control Signals
    reg gpu_start;
    reg gpu_reset;
    reg [7:0] thread_count;
    wire gpu_done;

    // Memory interface signals
    reg prog_mem_read_ready;
    reg [15:0] prog_mem_read_data;
    reg data_mem_read_ready;
    reg [7:0] data_mem_read_data;
    reg data_mem_write_ready;

    // Simplified GPU core signals
    wire prog_mem_read_valid;
    wire [PROG_ADDR_BITS-1:0] prog_mem_read_address;
    wire data_mem_read_valid;
    wire [DATA_ADDR_BITS-1:0] data_mem_read_address;
    wire data_mem_write_valid;
    wire [DATA_ADDR_BITS-1:0] data_mem_write_address;
    wire [7:0] data_mem_write_data;

    // ========================================================================
    // Output Data Register
    // ========================================================================
    reg [7:0] output_data;
    reg [7:0] status_reg;

    // Status bits
    // [0] - GPU running
    // [1] - GPU done
    // [2] - Ready for command
    // [7:3] - Reserved
    always @(*) begin
        status_reg = 8'b0;
        status_reg[0] = (state == STATE_RUNNING);
        status_reg[1] = gpu_done;
        status_reg[2] = (state == STATE_IDLE);
    end

    // ========================================================================
    // Command Processing State Machine
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            addr_low <= 8'b0;
            addr_high <= 8'b0;
            write_addr <= 16'b0;
            prog_high_byte <= 8'b0;
            gpu_start <= 0;
            gpu_reset <= 1;
            thread_count <= 8'd4;  // Default 4 threads
            output_data <= 8'b0;
        end else if (ena) begin
            // Default - deassert start after one cycle
            gpu_start <= 0;
            gpu_reset <= 0;

            case (state)
                STATE_IDLE: begin
                    case (ui_in[7:4])
                        CMD_SET_ADDR_LOW: begin
                            state <= STATE_SET_ADDR_LOW;
                        end
                        CMD_SET_ADDR_HIGH: begin
                            state <= STATE_SET_ADDR_HIGH;
                        end
                        CMD_WRITE_PROG: begin
                            state <= STATE_WRITE_PROG_H;
                        end
                        CMD_WRITE_DATA: begin
                            state <= STATE_WRITE_DATA;
                        end
                        CMD_READ_DATA: begin
                            state <= STATE_READ_DATA;
                        end
                        CMD_SET_THREADS: begin
                            state <= STATE_SET_THREADS;
                        end
                        CMD_START: begin
                            gpu_reset <= 0;
                            gpu_start <= 1;
                            state <= STATE_RUNNING;
                        end
                        CMD_STOP: begin
                            gpu_reset <= 1;
                            state <= STATE_IDLE;
                        end
                        CMD_STATUS: begin
                            output_data <= status_reg;
                        end
                        default: begin
                            // NOP or unknown command
                        end
                    endcase
                end

                STATE_SET_ADDR_LOW: begin
                    addr_low <= ui_in;
                    write_addr[7:0] <= ui_in;
                    state <= STATE_IDLE;
                end

                STATE_SET_ADDR_HIGH: begin
                    addr_high <= ui_in;
                    write_addr[15:8] <= ui_in;
                    state <= STATE_IDLE;
                end

                STATE_WRITE_PROG_H: begin
                    prog_high_byte <= ui_in;
                    state <= STATE_WRITE_PROG_L;
                end

                STATE_WRITE_PROG_L: begin
                    // Write 16-bit instruction to program memory
                    if (write_addr[PROG_ADDR_BITS-1:0] < PROG_MEM_SIZE) begin
                        program_memory[write_addr[PROG_ADDR_BITS-1:0]] <= {prog_high_byte, ui_in};
                    end
                    write_addr <= write_addr + 1;
                    state <= STATE_IDLE;
                end

                STATE_WRITE_DATA: begin
                    // Write 8-bit data to data memory
                    if (write_addr[DATA_ADDR_BITS-1:0] < DATA_MEM_SIZE) begin
                        data_memory[write_addr[DATA_ADDR_BITS-1:0]] <= ui_in;
                    end
                    write_addr <= write_addr + 1;
                    state <= STATE_IDLE;
                end

                STATE_READ_DATA: begin
                    // Read 8-bit data from data memory
                    if (write_addr[DATA_ADDR_BITS-1:0] < DATA_MEM_SIZE) begin
                        output_data <= data_memory[write_addr[DATA_ADDR_BITS-1:0]];
                    end
                    write_addr <= write_addr + 1;
                    state <= STATE_IDLE;
                end

                STATE_SET_THREADS: begin
                    thread_count <= ui_in;
                    state <= STATE_IDLE;
                end

                STATE_RUNNING: begin
                    if (gpu_done) begin
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

    // ========================================================================
    // Memory Interface Handling
    // ========================================================================
    // Program memory read (single cycle for on-chip memory)
    always @(posedge clk) begin
        if (reset) begin
            prog_mem_read_ready <= 0;
            prog_mem_read_data <= 16'b0;
        end else begin
            prog_mem_read_ready <= prog_mem_read_valid;
            if (prog_mem_read_valid) begin
                prog_mem_read_data <= program_memory[prog_mem_read_address];
            end
        end
    end

    // Data memory read/write (single cycle for on-chip memory)
    always @(posedge clk) begin
        if (reset) begin
            data_mem_read_ready <= 0;
            data_mem_read_data <= 8'b0;
            data_mem_write_ready <= 0;
        end else begin
            data_mem_read_ready <= data_mem_read_valid;
            data_mem_write_ready <= data_mem_write_valid;

            if (data_mem_read_valid) begin
                data_mem_read_data <= data_memory[data_mem_read_address];
            end

            if (data_mem_write_valid) begin
                data_memory[data_mem_write_address] <= data_mem_write_data;
            end
        end
    end

    // ========================================================================
    // GPU Core Instance (Minimal Configuration)
    // ========================================================================
    // Note: This is a simplified single-core, single-thread configuration
    // suitable for Tiny Tapeout's area constraints

    // For now, we instantiate a minimal scheduler to demonstrate the concept
    // A full GPU would require more area than available in standard TT tiles

    // Simplified done signal for demonstration
    reg [7:0] execution_counter;
    assign gpu_done = (execution_counter == 0) && !gpu_start;

    always @(posedge clk) begin
        if (reset || gpu_reset) begin
            execution_counter <= 0;
        end else if (gpu_start) begin
            execution_counter <= thread_count;
        end else if (execution_counter > 0) begin
            execution_counter <= execution_counter - 1;
        end
    end

    // Stub connections for memory interface (GPU core would connect here)
    assign prog_mem_read_valid = 0;
    assign prog_mem_read_address = 0;
    assign data_mem_read_valid = 0;
    assign data_mem_read_address = 0;
    assign data_mem_write_valid = 0;
    assign data_mem_write_address = 0;
    assign data_mem_write_data = 0;

    // ========================================================================
    // Output Assignments
    // ========================================================================
    assign uo_out = output_data;

    // Bidirectional pins configured as outputs for extended status
    assign uio_out = {4'b0, state};
    assign uio_oe = 8'hFF;  // All outputs for now

endmodule
