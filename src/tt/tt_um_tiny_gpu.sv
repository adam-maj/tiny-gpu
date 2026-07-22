`default_nettype none
`timescale 1ns/1ns

// TINY TAPEOUT 7 ADAPTER
// > Wraps a minimal tiny-gpu configuration (1 core, 4 threads/block, 1 data
//   channel, 1 program channel) behind the standard Tiny Tapeout top-level
//   interface: 8 dedicated inputs (ui_in), 8 dedicated outputs (uo_out), and
//   8 bidirectional pins (uio_*) - 24 usable I/Os total, active-low reset.
//
// > tiny-gpu's native interfaces (16-bit-wide program memory reads, 8-bit
//   data memory reads/writes, one port per thread) need far more than 24
//   pins, so this adapter time-multiplexes everything: program memory, data
//   memory, the device control register, kernel start/done, and result
//   readback are all driven over a byte-serial command protocol carried by
//   ui_in/uo_out, with a 4-wire ready/valid handshake on 4 of the 8 uio pins.
//   Program and data memory themselves are just small internal register
//   arrays here (loaded entirely over the serial link before START is sent)
//   - a real chip would still need *some* memory of this size on-die since
//   there's no way to expose tiny-gpu's wide async memory ports through only
//   24 pins at useful bandwidth.
//
// > This is silicon-flow scaffolding validated only in simulation (cocotb
//   smoke test - see test/test_tt_adapter.py) - no OpenLane hardening run is
//   included in this repo. See docs/tiny_tapeout.md for the full pinout and
//   protocol reference.
module tt_um_tiny_gpu (
    input  wire [7:0] ui_in,    // Dedicated inputs - command/payload byte from host
    output wire [7:0] uo_out,   // Dedicated outputs - response/status byte to host
    input  wire [7:0] uio_in,   // IOs: input path
    output wire [7:0] uio_out,  // IOs: output path
    output wire [7:0] uio_oe,   // IOs: enable path (1 = uio drives out, 0 = uio is input)
    input  wire       ena,      // Always 1 when powered - unused (see TT docs)
    input  wire       clk,
    input  wire       rst_n     // Active-low reset
);
    wire reset = !rst_n;

    // ---------------------------------------------------------------------
    // Byte-serial host protocol
    // ---------------------------------------------------------------------
    // Handshake pins (see docs/tiny_tapeout.md for the full pinout table):
    //   uio[0] = device_ready (out) - device can accept a command/payload byte
    //   uio[1] = host_valid   (in)  - host is presenting a byte on ui_in
    //   uio[2] = device_valid (out) - device is presenting a response on uo_out
    //   uio[3] = host_ready   (in)  - host has consumed the response byte
    //   uio[7:4] = unused (driven low, high-Z as inputs)
    wire host_valid = uio_in[1];
    wire host_ready = uio_in[3];
    reg device_ready;
    reg device_valid;

    assign uio_oe  = 8'b0000_0101;                    // bits 0,2 are outputs; rest inputs
    assign uio_out = {4'b0, 1'b0, device_valid, 1'b0, device_ready};
    assign uo_out  = resp_byte;

    // Command opcodes (first byte of every transaction, sent when device_ready=1)
    localparam CMD_LOAD_PROGRAM = 8'h01; // + addr, data_hi, data_lo (3 bytes)  -> program_mem[addr] = {data_hi,data_lo}
    localparam CMD_LOAD_DATA    = 8'h02; // + addr, data (2 bytes)             -> data_mem[addr] = data
    localparam CMD_SET_THREADS  = 8'h03; // + count (1 byte)                  -> device control register (thread_count)
    localparam CMD_START        = 8'h04; // (no payload)                      -> launch the kernel
    localparam CMD_READ_DATA    = 8'h05; // + addr (1 byte)                   -> responds with data_mem[addr]
    localparam CMD_READ_STATUS  = 8'h06; // (no payload)                      -> responds with {7'b0, done}

    localparam S_IDLE    = 2'b00,
        S_COLLECT = 2'b01, // gathering a command's payload bytes
        S_ACTION  = 2'b10, // payload fully collected - perform the write/read this cycle
        S_RESPOND = 2'b11; // holding a response byte on uo_out for the host to collect

    reg [1:0] state;
    reg [7:0] cmd;
    reg [1:0] bytes_needed;
    reg [1:0] byte_idx;
    reg [7:0] payload [2:0]; // up to 3 payload bytes (CMD_LOAD_PROGRAM: addr, data_hi, data_lo)
    reg [7:0] resp_byte;

    // ---------------------------------------------------------------------
    // Internal program & data memory (loaded entirely via CMD_LOAD_PROGRAM /
    // CMD_LOAD_DATA before CMD_START is issued)
    // ---------------------------------------------------------------------
    reg [15:0] program_mem [255:0];
    reg [7:0] data_mem [255:0];

    // ---------------------------------------------------------------------
    // GPU core (minimal config) + its memory-side glue
    // ---------------------------------------------------------------------
    reg gpu_start;
    wire gpu_done;
    reg dcr_write_enable;
    reg [7:0] dcr_data;

    wire prog_read_valid;
    wire [7:0] prog_read_addr [0:0];
    wire [15:0] prog_read_data [0:0];

    wire data_read_valid [0:0];
    wire [7:0] data_read_addr [0:0];
    wire [7:0] data_read_data [0:0];
    wire data_write_valid [0:0];
    wire [7:0] data_write_addr [0:0];
    wire [7:0] data_write_data [0:0];

    // Program memory: single-cycle combinational "async" memory (read-only from the
    // core's point of view - always ready the same cycle it's asked, since it's just
    // an on-die register array)
    assign prog_read_data[0] = program_mem[prog_read_addr[0]];

    // Data memory: same idea, but also handles writes (STR instructions)
    assign data_read_data[0] = data_mem[data_read_addr[0]];
    always @(posedge clk) begin
        if (!reset && data_write_valid[0]) begin
            data_mem[data_write_addr[0]] <= data_write_data[0];
        end
    end

    gpu #(
        .DATA_MEM_ADDR_BITS(8),
        .DATA_MEM_DATA_BITS(8),
        .DATA_MEM_NUM_CHANNELS(1),
        .PROGRAM_MEM_ADDR_BITS(8),
        .PROGRAM_MEM_DATA_BITS(16),
        .PROGRAM_MEM_NUM_CHANNELS(1),
        .NUM_CORES(1),
        .THREADS_PER_BLOCK(4)
    ) gpu_instance (
        .clk(clk),
        .reset(reset),
        .start(gpu_start),
        .done(gpu_done),

        .device_control_write_enable(dcr_write_enable),
        .device_control_data(dcr_data),

        .program_mem_read_valid(prog_read_valid),
        .program_mem_read_address(prog_read_addr),
        .program_mem_read_ready(prog_read_valid), // instant same-cycle response
        .program_mem_read_data(prog_read_data),

        .data_mem_read_valid(data_read_valid),
        .data_mem_read_address(data_read_addr),
        .data_mem_read_ready(data_read_valid),    // instant same-cycle response
        .data_mem_read_data(data_read_data),
        .data_mem_write_valid(data_write_valid),
        .data_mem_write_address(data_write_addr),
        .data_mem_write_data(data_write_data),
        .data_mem_write_ready(data_write_valid)   // instant same-cycle response
    );

    // ---------------------------------------------------------------------
    // Host protocol FSM
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            cmd <= 0;
            bytes_needed <= 0;
            byte_idx <= 0;
            resp_byte <= 0;
            device_ready <= 0;
            device_valid <= 0;
            gpu_start <= 0;
            dcr_write_enable <= 0;
            dcr_data <= 0;
        end else begin
            dcr_write_enable <= 0; // single-cycle pulse unless re-asserted below

            case (state)
                S_IDLE: begin
                    device_ready <= 1;
                    device_valid <= 0;
                    if (host_valid) begin
                        cmd <= ui_in;
                        byte_idx <= 0;
                        case (ui_in)
                            CMD_LOAD_PROGRAM: begin bytes_needed <= 2'd3; state <= S_COLLECT; end
                            CMD_LOAD_DATA:    begin bytes_needed <= 2'd2; state <= S_COLLECT; end
                            CMD_SET_THREADS:  begin bytes_needed <= 2'd1; state <= S_COLLECT; end
                            CMD_READ_DATA:    begin bytes_needed <= 2'd1; state <= S_COLLECT; end
                            CMD_START: begin
                                gpu_start <= 1; // level signal - stays high for the whole kernel run
                            end
                            CMD_READ_STATUS: begin
                                resp_byte <= {7'b0, gpu_done};
                                state <= S_RESPOND;
                                device_ready <= 0;
                            end
                            default: begin end // unknown opcode - ignore, stay idle
                        endcase
                    end
                end
                S_COLLECT: begin
                    if (host_valid) begin
                        payload[byte_idx] <= ui_in;
                        if (byte_idx + 2'd1 == bytes_needed) begin
                            state <= S_ACTION;
                            device_ready <= 0;
                        end else begin
                            byte_idx <= byte_idx + 2'd1;
                        end
                    end
                end
                S_ACTION: begin
                    // All payload bytes are now settled in `payload[]` (including the very
                    // last one, captured last cycle) - perform the command's effect.
                    case (cmd)
                        CMD_LOAD_PROGRAM: begin
                            program_mem[payload[0]] <= {payload[1], payload[2]};
                            state <= S_IDLE;
                        end
                        CMD_LOAD_DATA: begin
                            data_mem[payload[0]] <= payload[1];
                            state <= S_IDLE;
                        end
                        CMD_SET_THREADS: begin
                            dcr_data <= payload[0];
                            dcr_write_enable <= 1;
                            state <= S_IDLE;
                        end
                        CMD_READ_DATA: begin
                            resp_byte <= data_mem[payload[0]];
                            state <= S_RESPOND;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                S_RESPOND: begin
                    device_valid <= 1;
                    if (host_ready) begin
                        device_valid <= 0;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
