`default_nettype none
`timescale 1ns/1ns

/**
 * Debug Controller
 * Enterprise hardware debug infrastructure
 * Features:
 * - JTAG-style scan chain
 * - Hardware breakpoints
 * - Watchpoints on registers/memory
 * - Trace buffer for execution history
 * - Performance counter access
 * - Register file inspection
 */
module debug_controller #(
    parameter NUM_BREAKPOINTS = 8,
    parameter NUM_WATCHPOINTS = 4,
    parameter TRACE_DEPTH = 256,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input wire clk,
    input wire reset,
    
    // Debug enable
    input wire debug_enable,
    input wire debug_halt_req,
    output reg debug_halted,
    output reg debug_running,
    
    // JTAG-style interface
    input wire tck,           // Test clock
    input wire tms,           // Test mode select
    input wire tdi,           // Test data in
    output reg tdo,           // Test data out
    output reg tdo_enable,
    
    // Breakpoint configuration
    input wire bp_write,
    input wire [2:0] bp_idx,
    input wire [ADDR_WIDTH-1:0] bp_addr,
    input wire bp_enable_in,
    input wire [3:0] bp_type,             // 0=exec, 1=read, 2=write, 3=rw
    
    // Watchpoint configuration
    input wire wp_write,
    input wire [1:0] wp_idx,
    input wire [ADDR_WIDTH-1:0] wp_addr,
    input wire [DATA_WIDTH-1:0] wp_mask,
    input wire [DATA_WIDTH-1:0] wp_value,
    input wire wp_enable_in,
    
    // CPU state monitoring
    input wire [ADDR_WIDTH-1:0] pc_value,
    input wire [ADDR_WIDTH-1:0] mem_addr,
    input wire [DATA_WIDTH-1:0] mem_data,
    input wire mem_read,
    input wire mem_write,
    input wire [31:0] instruction,
    input wire instruction_valid,
    
    // Debug events
    output reg breakpoint_hit,
    output reg watchpoint_hit,
    output reg [2:0] hit_bp_idx,
    output reg [1:0] hit_wp_idx,
    
    // Single step control
    input wire single_step,
    output reg step_complete,
    
    // Register access interface
    input wire reg_read_req,
    input wire reg_write_req,
    input wire [4:0] reg_addr,
    input wire [DATA_WIDTH-1:0] reg_write_data,
    output reg [DATA_WIDTH-1:0] reg_read_data,
    output reg reg_access_done,
    
    // Memory access interface (for debug reads/writes)
    input wire dbg_mem_read_req,
    input wire dbg_mem_write_req,
    input wire [ADDR_WIDTH-1:0] dbg_mem_addr,
    input wire [DATA_WIDTH-1:0] dbg_mem_write_data,
    output reg [DATA_WIDTH-1:0] dbg_mem_read_data,
    output reg dbg_mem_done,
    
    // Trace buffer interface
    input wire trace_enable,
    input wire trace_read_req,
    input wire [7:0] trace_read_idx,
    output reg [ADDR_WIDTH-1:0] trace_pc_out,
    output reg [31:0] trace_instr_out,
    output reg [31:0] trace_timestamp_out,
    output reg [7:0] trace_count,
    
    // Performance counter access
    input wire perf_read_req,
    input wire [3:0] perf_counter_sel,
    output reg [63:0] perf_counter_value,
    
    // Status
    output reg [7:0] debug_status,
    output reg [15:0] debug_cause
);

    // JTAG TAP states
    localparam TAP_RESET = 4'd0;
    localparam TAP_IDLE = 4'd1;
    localparam TAP_DR_SELECT = 4'd2;
    localparam TAP_DR_CAPTURE = 4'd3;
    localparam TAP_DR_SHIFT = 4'd4;
    localparam TAP_DR_EXIT1 = 4'd5;
    localparam TAP_DR_PAUSE = 4'd6;
    localparam TAP_DR_EXIT2 = 4'd7;
    localparam TAP_DR_UPDATE = 4'd8;
    localparam TAP_IR_SELECT = 4'd9;
    localparam TAP_IR_CAPTURE = 4'd10;
    localparam TAP_IR_SHIFT = 4'd11;
    localparam TAP_IR_EXIT1 = 4'd12;
    localparam TAP_IR_PAUSE = 4'd13;
    localparam TAP_IR_EXIT2 = 4'd14;
    localparam TAP_IR_UPDATE = 4'd15;
    
    reg [3:0] tap_state;
    reg [3:0] instruction_reg;
    reg [63:0] data_reg;
    reg [5:0] shift_count;
    
    // JTAG instructions
    localparam JTAG_IDCODE = 4'h0;
    localparam JTAG_BYPASS = 4'h1;
    localparam JTAG_READ_REG = 4'h2;
    localparam JTAG_WRITE_REG = 4'h3;
    localparam JTAG_READ_MEM = 4'h4;
    localparam JTAG_WRITE_MEM = 4'h5;
    localparam JTAG_HALT = 4'h6;
    localparam JTAG_RESUME = 4'h7;
    localparam JTAG_STEP = 4'h8;
    
    // Device ID
    localparam DEVICE_ID = 32'h4C4B4700;  // "LKG\0"
    
    // Breakpoint storage
    reg [ADDR_WIDTH-1:0] bp_addresses [NUM_BREAKPOINTS-1:0];
    reg bp_enabled [NUM_BREAKPOINTS-1:0];
    reg [3:0] bp_types [NUM_BREAKPOINTS-1:0];
    
    // Watchpoint storage
    reg [ADDR_WIDTH-1:0] wp_addresses [NUM_WATCHPOINTS-1:0];
    reg [DATA_WIDTH-1:0] wp_masks [NUM_WATCHPOINTS-1:0];
    reg [DATA_WIDTH-1:0] wp_values [NUM_WATCHPOINTS-1:0];
    reg wp_enabled [NUM_WATCHPOINTS-1:0];
    
    // Trace buffer
    reg [ADDR_WIDTH-1:0] trace_pc [TRACE_DEPTH-1:0];
    reg [31:0] trace_instr [TRACE_DEPTH-1:0];
    reg [31:0] trace_time [TRACE_DEPTH-1:0];
    reg [7:0] trace_head;
    reg [7:0] trace_tail;
    reg trace_wrapped;
    
    // Timestamp counter
    reg [31:0] timestamp;
    
    // Debug state machine
    localparam DBG_RUNNING = 2'd0;
    localparam DBG_HALTED = 2'd1;
    localparam DBG_STEPPING = 2'd2;
    
    reg [1:0] debug_state;
    reg step_pending;
    
    // Internal performance counters
    reg [63:0] perf_cycles;
    reg [63:0] perf_instructions;
    reg [63:0] perf_mem_reads;
    reg [63:0] perf_mem_writes;
    reg [63:0] perf_breakpoint_hits;
    reg [63:0] perf_watchpoint_hits;
    
    // Initialize
    integer k;
    initial begin
        for (k = 0; k < NUM_BREAKPOINTS; k = k + 1) begin
            bp_addresses[k] = 0;
            bp_enabled[k] = 0;
            bp_types[k] = 0;
        end
        for (k = 0; k < NUM_WATCHPOINTS; k = k + 1) begin
            wp_addresses[k] = 0;
            wp_masks[k] = 0;
            wp_values[k] = 0;
            wp_enabled[k] = 0;
        end
    end
    
    // Timestamp
    always @(posedge clk or posedge reset) begin
        if (reset)
            timestamp <= 0;
        else
            timestamp <= timestamp + 1;
    end
    
    // Performance counters
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            perf_cycles <= 0;
            perf_instructions <= 0;
            perf_mem_reads <= 0;
            perf_mem_writes <= 0;
            perf_breakpoint_hits <= 0;
            perf_watchpoint_hits <= 0;
        end else begin
            perf_cycles <= perf_cycles + 1;
            
            if (instruction_valid && debug_state == DBG_RUNNING)
                perf_instructions <= perf_instructions + 1;
            
            if (mem_read && debug_state == DBG_RUNNING)
                perf_mem_reads <= perf_mem_reads + 1;
                
            if (mem_write && debug_state == DBG_RUNNING)
                perf_mem_writes <= perf_mem_writes + 1;
                
            if (breakpoint_hit)
                perf_breakpoint_hits <= perf_breakpoint_hits + 1;
                
            if (watchpoint_hit)
                perf_watchpoint_hits <= perf_watchpoint_hits + 1;
        end
    end
    
    // Breakpoint configuration
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < NUM_BREAKPOINTS; k = k + 1) begin
                bp_addresses[k] <= 0;
                bp_enabled[k] <= 0;
                bp_types[k] <= 0;
            end
        end else if (bp_write) begin
            bp_addresses[bp_idx] <= bp_addr;
            bp_enabled[bp_idx] <= bp_enable_in;
            bp_types[bp_idx] <= bp_type;
        end
    end
    
    // Watchpoint configuration
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < NUM_WATCHPOINTS; k = k + 1) begin
                wp_addresses[k] <= 0;
                wp_masks[k] <= 0;
                wp_values[k] <= 0;
                wp_enabled[k] <= 0;
            end
        end else if (wp_write) begin
            wp_addresses[wp_idx] <= wp_addr;
            wp_masks[wp_idx] <= wp_mask;
            wp_values[wp_idx] <= wp_value;
            wp_enabled[wp_idx] <= wp_enable_in;
        end
    end
    
    // Breakpoint checking
    integer bp;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            breakpoint_hit <= 0;
            hit_bp_idx <= 0;
        end else begin
            breakpoint_hit <= 0;
            
            if (debug_enable && debug_state == DBG_RUNNING && instruction_valid) begin
                for (bp = 0; bp < NUM_BREAKPOINTS; bp = bp + 1) begin
                    if (bp_enabled[bp]) begin
                        case (bp_types[bp])
                            4'd0: begin  // Execution breakpoint
                                if (pc_value == bp_addresses[bp]) begin
                                    breakpoint_hit <= 1;
                                    hit_bp_idx <= bp[2:0];
                                end
                            end
                            4'd1: begin  // Read breakpoint
                                if (mem_read && mem_addr == bp_addresses[bp]) begin
                                    breakpoint_hit <= 1;
                                    hit_bp_idx <= bp[2:0];
                                end
                            end
                            4'd2: begin  // Write breakpoint
                                if (mem_write && mem_addr == bp_addresses[bp]) begin
                                    breakpoint_hit <= 1;
                                    hit_bp_idx <= bp[2:0];
                                end
                            end
                            4'd3: begin  // Read/Write breakpoint
                                if ((mem_read || mem_write) && mem_addr == bp_addresses[bp]) begin
                                    breakpoint_hit <= 1;
                                    hit_bp_idx <= bp[2:0];
                                end
                            end
                        endcase
                    end
                end
            end
        end
    end
    
    // Watchpoint checking
    integer wp;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            watchpoint_hit <= 0;
            hit_wp_idx <= 0;
        end else begin
            watchpoint_hit <= 0;
            
            if (debug_enable && debug_state == DBG_RUNNING && mem_write) begin
                for (wp = 0; wp < NUM_WATCHPOINTS; wp = wp + 1) begin
                    if (wp_enabled[wp] && mem_addr == wp_addresses[wp]) begin
                        if ((mem_data & wp_masks[wp]) == (wp_values[wp] & wp_masks[wp])) begin
                            watchpoint_hit <= 1;
                            hit_wp_idx <= wp[1:0];
                        end
                    end
                end
            end
        end
    end
    
    // Trace buffer management
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            trace_head <= 0;
            trace_tail <= 0;
            trace_count <= 0;
            trace_wrapped <= 0;
        end else if (trace_enable && instruction_valid && debug_state == DBG_RUNNING) begin
            trace_pc[trace_head] <= pc_value;
            trace_instr[trace_head] <= instruction;
            trace_time[trace_head] <= timestamp;
            
            trace_head <= trace_head + 1;
            
            if (trace_head == TRACE_DEPTH - 1) begin
                trace_wrapped <= 1;
            end
            
            if (trace_count < TRACE_DEPTH)
                trace_count <= trace_count + 1;
        end
    end
    
    // Trace read
    always @(posedge clk) begin
        if (trace_read_req) begin
            trace_pc_out <= trace_pc[trace_read_idx];
            trace_instr_out <= trace_instr[trace_read_idx];
            trace_timestamp_out <= trace_time[trace_read_idx];
        end
    end
    
    // Performance counter read
    always @(posedge clk) begin
        if (perf_read_req) begin
            case (perf_counter_sel)
                4'd0: perf_counter_value <= perf_cycles;
                4'd1: perf_counter_value <= perf_instructions;
                4'd2: perf_counter_value <= perf_mem_reads;
                4'd3: perf_counter_value <= perf_mem_writes;
                4'd4: perf_counter_value <= perf_breakpoint_hits;
                4'd5: perf_counter_value <= perf_watchpoint_hits;
                default: perf_counter_value <= 0;
            endcase
        end
    end
    
    // Debug state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debug_state <= DBG_RUNNING;
            debug_halted <= 0;
            debug_running <= 1;
            step_pending <= 0;
            step_complete <= 0;
            debug_status <= 0;
            debug_cause <= 0;
        end else begin
            step_complete <= 0;
            
            case (debug_state)
                DBG_RUNNING: begin
                    debug_halted <= 0;
                    debug_running <= 1;
                    
                    if (debug_halt_req) begin
                        debug_state <= DBG_HALTED;
                        debug_cause <= 16'h0001;  // Manual halt
                    end else if (breakpoint_hit) begin
                        debug_state <= DBG_HALTED;
                        debug_cause <= 16'h0002;  // Breakpoint
                    end else if (watchpoint_hit) begin
                        debug_state <= DBG_HALTED;
                        debug_cause <= 16'h0003;  // Watchpoint
                    end
                end
                
                DBG_HALTED: begin
                    debug_halted <= 1;
                    debug_running <= 0;
                    
                    if (single_step) begin
                        debug_state <= DBG_STEPPING;
                        step_pending <= 1;
                    end else if (!debug_halt_req && !breakpoint_hit && !watchpoint_hit) begin
                        debug_state <= DBG_RUNNING;
                        debug_cause <= 0;
                    end
                end
                
                DBG_STEPPING: begin
                    debug_halted <= 0;
                    debug_running <= 1;
                    
                    if (step_pending && instruction_valid) begin
                        step_pending <= 0;
                        step_complete <= 1;
                        debug_state <= DBG_HALTED;
                        debug_cause <= 16'h0004;  // Single step
                    end
                end
            endcase
            
            // Update status register
            debug_status <= {4'b0, debug_state, debug_halted, debug_running};
        end
    end
    
    // JTAG TAP state machine
    always @(posedge tck or posedge reset) begin
        if (reset) begin
            tap_state <= TAP_RESET;
            instruction_reg <= JTAG_IDCODE;
            data_reg <= 0;
            shift_count <= 0;
            tdo <= 0;
            tdo_enable <= 0;
        end else begin
            case (tap_state)
                TAP_RESET: begin
                    instruction_reg <= JTAG_IDCODE;
                    if (!tms) tap_state <= TAP_IDLE;
                end
                
                TAP_IDLE: begin
                    if (tms) tap_state <= TAP_DR_SELECT;
                end
                
                TAP_DR_SELECT: begin
                    if (tms) tap_state <= TAP_IR_SELECT;
                    else tap_state <= TAP_DR_CAPTURE;
                end
                
                TAP_DR_CAPTURE: begin
                    // Capture data based on instruction
                    case (instruction_reg)
                        JTAG_IDCODE: data_reg <= {32'b0, DEVICE_ID};
                        JTAG_BYPASS: data_reg <= 0;
                        default: data_reg <= 0;
                    endcase
                    shift_count <= 0;
                    if (tms) tap_state <= TAP_DR_EXIT1;
                    else tap_state <= TAP_DR_SHIFT;
                end
                
                TAP_DR_SHIFT: begin
                    tdo <= data_reg[0];
                    tdo_enable <= 1;
                    data_reg <= {tdi, data_reg[63:1]};
                    shift_count <= shift_count + 1;
                    if (tms) tap_state <= TAP_DR_EXIT1;
                end
                
                TAP_DR_EXIT1: begin
                    tdo_enable <= 0;
                    if (tms) tap_state <= TAP_DR_UPDATE;
                    else tap_state <= TAP_DR_PAUSE;
                end
                
                TAP_DR_PAUSE: begin
                    if (tms) tap_state <= TAP_DR_EXIT2;
                end
                
                TAP_DR_EXIT2: begin
                    if (tms) tap_state <= TAP_DR_UPDATE;
                    else tap_state <= TAP_DR_SHIFT;
                end
                
                TAP_DR_UPDATE: begin
                    // Update outputs based on instruction
                    if (tms) tap_state <= TAP_DR_SELECT;
                    else tap_state <= TAP_IDLE;
                end
                
                TAP_IR_SELECT: begin
                    if (tms) tap_state <= TAP_RESET;
                    else tap_state <= TAP_IR_CAPTURE;
                end
                
                TAP_IR_CAPTURE: begin
                    data_reg <= {60'b0, instruction_reg};
                    shift_count <= 0;
                    if (tms) tap_state <= TAP_IR_EXIT1;
                    else tap_state <= TAP_IR_SHIFT;
                end
                
                TAP_IR_SHIFT: begin
                    tdo <= data_reg[0];
                    tdo_enable <= 1;
                    data_reg <= {tdi, data_reg[63:1]};
                    shift_count <= shift_count + 1;
                    if (tms) tap_state <= TAP_IR_EXIT1;
                end
                
                TAP_IR_EXIT1: begin
                    tdo_enable <= 0;
                    if (tms) tap_state <= TAP_IR_UPDATE;
                    else tap_state <= TAP_IR_PAUSE;
                end
                
                TAP_IR_PAUSE: begin
                    if (tms) tap_state <= TAP_IR_EXIT2;
                end
                
                TAP_IR_EXIT2: begin
                    if (tms) tap_state <= TAP_IR_UPDATE;
                    else tap_state <= TAP_IR_SHIFT;
                end
                
                TAP_IR_UPDATE: begin
                    instruction_reg <= data_reg[3:0];
                    if (tms) tap_state <= TAP_DR_SELECT;
                    else tap_state <= TAP_IDLE;
                end
            endcase
        end
    end
    
    // Register access handling
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_read_data <= 0;
            reg_access_done <= 0;
        end else begin
            reg_access_done <= 0;
            
            if (reg_read_req && debug_halted) begin
                // Would connect to actual register file
                reg_read_data <= 32'hDEADBEEF;  // Placeholder
                reg_access_done <= 1;
            end else if (reg_write_req && debug_halted) begin
                // Would connect to actual register file
                reg_access_done <= 1;
            end
        end
    end
    
    // Debug memory access handling
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dbg_mem_read_data <= 0;
            dbg_mem_done <= 0;
        end else begin
            dbg_mem_done <= 0;
            
            if (dbg_mem_read_req && debug_halted) begin
                // Would connect to memory interface
                dbg_mem_read_data <= 32'hCAFEBABE;  // Placeholder
                dbg_mem_done <= 1;
            end else if (dbg_mem_write_req && debug_halted) begin
                // Would connect to memory interface
                dbg_mem_done <= 1;
            end
        end
    end

endmodule
