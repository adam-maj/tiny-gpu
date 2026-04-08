`default_nettype none
`timescale 1ns/1ns

/**
 * ECC Memory Controller
 * Error Correcting Code memory protection unit
 * Enterprise features for datacenter/HPC reliability:
 * - SECDED (Single Error Correct, Double Error Detect)
 * - Memory scrubbing
 * - Error logging and statistics
 * - Poison bit support for uncorrectable errors
 * - Address/data parity protection
 */
module ecc_controller #(
    parameter DATA_WIDTH = 64,
    parameter ECC_WIDTH = 8,    // 8 bits for SECDED on 64-bit data
    parameter ADDR_WIDTH = 32,
    parameter LOG_DEPTH = 16
) (
    input wire clk,
    input wire reset,
    
    // Configuration
    input wire ecc_enable,
    input wire scrub_enable,
    input wire poison_enable,
    input wire [15:0] scrub_interval,
    
    // Memory write interface (unprotected data in)
    input wire write_req,
    input wire [ADDR_WIDTH-1:0] write_addr,
    input wire [DATA_WIDTH-1:0] write_data,
    output reg write_ready,
    
    // Memory read interface (unprotected data out)
    input wire read_req,
    input wire [ADDR_WIDTH-1:0] read_addr,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg read_valid,
    output reg read_error_corrected,
    output reg read_error_uncorrectable,
    output reg read_poison,
    
    // Protected memory interface (to physical memory)
    output reg mem_write,
    output reg [ADDR_WIDTH-1:0] mem_write_addr,
    output reg [DATA_WIDTH+ECC_WIDTH:0] mem_write_data,  // +1 for poison bit
    
    output reg mem_read,
    output reg [ADDR_WIDTH-1:0] mem_read_addr,
    input wire [DATA_WIDTH+ECC_WIDTH:0] mem_read_data,
    input wire mem_read_valid,
    
    // Scrubber interface
    output reg scrub_active,
    output reg [ADDR_WIDTH-1:0] scrub_addr,
    
    // Error reporting
    output reg correctable_error,
    output reg uncorrectable_error,
    output reg [31:0] ce_count,           // Correctable error count
    output reg [31:0] ue_count,           // Uncorrectable error count
    output reg [ADDR_WIDTH-1:0] last_error_addr,
    output reg [7:0] last_syndrome,
    
    // Error log interface
    output reg [LOG_DEPTH-1:0] log_entries_valid,
    input wire [3:0] log_read_idx,
    output reg [ADDR_WIDTH-1:0] log_addr_out,
    output reg [7:0] log_syndrome_out,
    output reg log_correctable_out,
    output reg [31:0] log_timestamp_out,
    
    // Interrupt
    output reg ecc_interrupt,
    input wire interrupt_clear,
    
    // Statistics
    output reg [31:0] total_reads,
    output reg [31:0] total_writes,
    output reg [31:0] scrub_corrected
);

    // ECC syndrome calculation (Hamming code with SECDED)
    // For 64-bit data, we use 8 check bits (7 for Hamming + 1 overall parity)
    
    function [ECC_WIDTH-1:0] calc_syndrome;
        input [DATA_WIDTH-1:0] data;
        input [ECC_WIDTH-1:0] stored_ecc;
        reg [ECC_WIDTH-1:0] computed_ecc;
        reg [ECC_WIDTH-1:0] syndrome;
        integer i;
    begin
        // Calculate parity bits for Hamming(72,64)
        computed_ecc[0] = ^{data[0], data[1], data[3], data[4], data[6], data[8], 
                          data[10], data[11], data[13], data[15], data[17], data[19],
                          data[21], data[23], data[25], data[26], data[28], data[30],
                          data[32], data[34], data[36], data[38], data[40], data[42],
                          data[44], data[46], data[48], data[50], data[52], data[54],
                          data[56], data[58], data[60], data[62]};
        computed_ecc[1] = ^{data[0], data[2], data[3], data[5], data[6], data[9],
                          data[10], data[12], data[13], data[16], data[17], data[20],
                          data[21], data[24], data[25], data[27], data[28], data[31],
                          data[32], data[35], data[36], data[39], data[40], data[43],
                          data[44], data[47], data[48], data[51], data[52], data[55],
                          data[56], data[59], data[60], data[63]};
        computed_ecc[2] = ^{data[1], data[2], data[3], data[7], data[8], data[9],
                          data[10], data[14], data[15], data[16], data[17], data[22],
                          data[23], data[24], data[25], data[29], data[30], data[31],
                          data[32], data[37], data[38], data[39], data[40], data[45],
                          data[46], data[47], data[48], data[53], data[54], data[55],
                          data[56], data[61], data[62], data[63]};
        computed_ecc[3] = ^{data[4], data[5], data[6], data[7], data[8], data[9],
                          data[10], data[18], data[19], data[20], data[21], data[22],
                          data[23], data[24], data[25], data[33], data[34], data[35],
                          data[36], data[37], data[38], data[39], data[40], data[49],
                          data[50], data[51], data[52], data[53], data[54], data[55],
                          data[56]};
        computed_ecc[4] = ^{data[11], data[12], data[13], data[14], data[15], data[16],
                          data[17], data[18], data[19], data[20], data[21], data[22],
                          data[23], data[24], data[25], data[41], data[42], data[43],
                          data[44], data[45], data[46], data[47], data[48], data[49],
                          data[50], data[51], data[52], data[53], data[54], data[55],
                          data[56]};
        computed_ecc[5] = ^{data[26], data[27], data[28], data[29], data[30], data[31],
                          data[32], data[33], data[34], data[35], data[36], data[37],
                          data[38], data[39], data[40], data[41], data[42], data[43],
                          data[44], data[45], data[46], data[47], data[48], data[49],
                          data[50], data[51], data[52], data[53], data[54], data[55],
                          data[56]};
        computed_ecc[6] = ^{data[57], data[58], data[59], data[60], data[61], data[62],
                          data[63]};
        // Overall parity for SECDED
        computed_ecc[7] = ^{data, computed_ecc[6:0]};
        
        syndrome = stored_ecc ^ computed_ecc;
        calc_syndrome = syndrome;
    end
    endfunction
    
    function [ECC_WIDTH-1:0] generate_ecc;
        input [DATA_WIDTH-1:0] data;
        reg [ECC_WIDTH-1:0] ecc;
    begin
        ecc[0] = ^{data[0], data[1], data[3], data[4], data[6], data[8], 
                  data[10], data[11], data[13], data[15], data[17], data[19],
                  data[21], data[23], data[25], data[26], data[28], data[30],
                  data[32], data[34], data[36], data[38], data[40], data[42],
                  data[44], data[46], data[48], data[50], data[52], data[54],
                  data[56], data[58], data[60], data[62]};
        ecc[1] = ^{data[0], data[2], data[3], data[5], data[6], data[9],
                  data[10], data[12], data[13], data[16], data[17], data[20],
                  data[21], data[24], data[25], data[27], data[28], data[31],
                  data[32], data[35], data[36], data[39], data[40], data[43],
                  data[44], data[47], data[48], data[51], data[52], data[55],
                  data[56], data[59], data[60], data[63]};
        ecc[2] = ^{data[1], data[2], data[3], data[7], data[8], data[9],
                  data[10], data[14], data[15], data[16], data[17], data[22],
                  data[23], data[24], data[25], data[29], data[30], data[31],
                  data[32], data[37], data[38], data[39], data[40], data[45],
                  data[46], data[47], data[48], data[53], data[54], data[55],
                  data[56], data[61], data[62], data[63]};
        ecc[3] = ^{data[4], data[5], data[6], data[7], data[8], data[9],
                  data[10], data[18], data[19], data[20], data[21], data[22],
                  data[23], data[24], data[25], data[33], data[34], data[35],
                  data[36], data[37], data[38], data[39], data[40], data[49],
                  data[50], data[51], data[52], data[53], data[54], data[55],
                  data[56]};
        ecc[4] = ^{data[11], data[12], data[13], data[14], data[15], data[16],
                  data[17], data[18], data[19], data[20], data[21], data[22],
                  data[23], data[24], data[25], data[41], data[42], data[43],
                  data[44], data[45], data[46], data[47], data[48], data[49],
                  data[50], data[51], data[52], data[53], data[54], data[55],
                  data[56]};
        ecc[5] = ^{data[26], data[27], data[28], data[29], data[30], data[31],
                  data[32], data[33], data[34], data[35], data[36], data[37],
                  data[38], data[39], data[40], data[41], data[42], data[43],
                  data[44], data[45], data[46], data[47], data[48], data[49],
                  data[50], data[51], data[52], data[53], data[54], data[55],
                  data[56]};
        ecc[6] = ^{data[57], data[58], data[59], data[60], data[61], data[62],
                  data[63]};
        ecc[7] = ^{data, ecc[6:0]};
        generate_ecc = ecc;
    end
    endfunction
    
    // State machine
    localparam ST_IDLE = 3'd0;
    localparam ST_WRITE = 3'd1;
    localparam ST_READ = 3'd2;
    localparam ST_CHECK = 3'd3;
    localparam ST_CORRECT = 3'd4;
    localparam ST_SCRUB = 3'd5;
    localparam ST_LOG = 3'd6;
    
    reg [2:0] state;
    reg [2:0] next_state;
    
    // Internal registers
    reg [DATA_WIDTH-1:0] data_buffer;
    reg [ECC_WIDTH-1:0] ecc_buffer;
    reg poison_bit;
    reg [ECC_WIDTH-1:0] syndrome;
    reg [ADDR_WIDTH-1:0] pending_addr;
    reg is_scrub_read;
    
    // Scrubber
    reg [15:0] scrub_counter;
    reg [ADDR_WIDTH-1:0] scrub_position;
    localparam SCRUB_END_ADDR = 32'h00100000;  // 1MB example
    
    // Error log
    reg [ADDR_WIDTH-1:0] error_log_addr [LOG_DEPTH-1:0];
    reg [7:0] error_log_syndrome [LOG_DEPTH-1:0];
    reg error_log_correctable [LOG_DEPTH-1:0];
    reg [31:0] error_log_timestamp [LOG_DEPTH-1:0];
    reg [3:0] log_write_ptr;
    reg [31:0] timestamp;
    
    // Timestamp counter
    always @(posedge clk or posedge reset) begin
        if (reset)
            timestamp <= 0;
        else
            timestamp <= timestamp + 1;
    end
    
    // Log output mux
    always @(*) begin
        log_addr_out = error_log_addr[log_read_idx];
        log_syndrome_out = error_log_syndrome[log_read_idx];
        log_correctable_out = error_log_correctable[log_read_idx];
        log_timestamp_out = error_log_timestamp[log_read_idx];
    end
    
    // Main state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            write_ready <= 1;
            read_valid <= 0;
            read_error_corrected <= 0;
            read_error_uncorrectable <= 0;
            read_poison <= 0;
            mem_write <= 0;
            mem_read <= 0;
            scrub_active <= 0;
            correctable_error <= 0;
            uncorrectable_error <= 0;
            ce_count <= 0;
            ue_count <= 0;
            scrub_corrected <= 0;
            total_reads <= 0;
            total_writes <= 0;
            ecc_interrupt <= 0;
            scrub_counter <= 0;
            scrub_position <= 0;
            log_write_ptr <= 0;
            log_entries_valid <= 0;
            is_scrub_read <= 0;
        end else begin
            // Clear pulse signals
            correctable_error <= 0;
            uncorrectable_error <= 0;
            read_valid <= 0;
            
            if (interrupt_clear)
                ecc_interrupt <= 0;
            
            case (state)
                ST_IDLE: begin
                    write_ready <= 1;
                    
                    if (write_req && ecc_enable) begin
                        state <= ST_WRITE;
                        pending_addr <= write_addr;
                        data_buffer <= write_data;
                        write_ready <= 0;
                    end else if (read_req) begin
                        state <= ST_READ;
                        pending_addr <= read_addr;
                        write_ready <= 0;
                        is_scrub_read <= 0;
                    end else if (scrub_enable && scrub_counter >= scrub_interval) begin
                        state <= ST_SCRUB;
                        scrub_active <= 1;
                        is_scrub_read <= 1;
                    end
                    
                    // Increment scrub counter
                    if (scrub_enable)
                        scrub_counter <= scrub_counter + 1;
                end
                
                ST_WRITE: begin
                    // Generate ECC and write to memory
                    ecc_buffer <= generate_ecc(data_buffer);
                    mem_write <= 1;
                    mem_write_addr <= pending_addr;
                    mem_write_data <= {1'b0, generate_ecc(data_buffer), data_buffer};  // poison=0
                    total_writes <= total_writes + 1;
                    state <= ST_IDLE;
                end
                
                ST_READ: begin
                    mem_read <= 1;
                    mem_read_addr <= is_scrub_read ? scrub_position : pending_addr;
                    if (mem_read_valid) begin
                        mem_read <= 0;
                        data_buffer <= mem_read_data[DATA_WIDTH-1:0];
                        ecc_buffer <= mem_read_data[DATA_WIDTH+ECC_WIDTH-1:DATA_WIDTH];
                        poison_bit <= mem_read_data[DATA_WIDTH+ECC_WIDTH];
                        total_reads <= total_reads + 1;
                        state <= ST_CHECK;
                    end
                end
                
                ST_CHECK: begin
                    if (poison_bit && poison_enable) begin
                        // Poisoned data - propagate error
                        read_poison <= 1;
                        read_error_uncorrectable <= 1;
                        uncorrectable_error <= 1;
                        ue_count <= ue_count + 1;
                        ecc_interrupt <= 1;
                        state <= ST_IDLE;
                    end else if (ecc_enable) begin
                        syndrome <= calc_syndrome(data_buffer, ecc_buffer);
                        state <= ST_CORRECT;
                    end else begin
                        read_data <= data_buffer;
                        read_valid <= !is_scrub_read;
                        state <= ST_IDLE;
                    end
                end
                
                ST_CORRECT: begin
                    if (syndrome == 0) begin
                        // No error
                        read_data <= data_buffer;
                        read_valid <= !is_scrub_read;
                        state <= ST_IDLE;
                    end else if (syndrome[7] == 1) begin
                        // Correctable single-bit error (odd parity in syndrome)
                        // Error position encoded in lower 7 bits
                        read_error_corrected <= 1;
                        correctable_error <= 1;
                        ce_count <= ce_count + 1;
                        last_error_addr <= pending_addr;
                        last_syndrome <= syndrome;
                        
                        // Correct the bit (simplified - toggle bit at syndrome position)
                        if (syndrome[6:0] > 0 && syndrome[6:0] <= DATA_WIDTH) begin
                            data_buffer[syndrome[6:0]-1] <= ~data_buffer[syndrome[6:0]-1];
                        end
                        
                        read_data <= data_buffer;
                        read_valid <= !is_scrub_read;
                        
                        if (is_scrub_read)
                            scrub_corrected <= scrub_corrected + 1;
                        
                        state <= ST_LOG;
                    end else begin
                        // Uncorrectable double-bit error (even parity)
                        read_error_uncorrectable <= 1;
                        uncorrectable_error <= 1;
                        ue_count <= ue_count + 1;
                        last_error_addr <= pending_addr;
                        last_syndrome <= syndrome;
                        ecc_interrupt <= 1;
                        
                        // Return data anyway with error flag
                        read_data <= data_buffer;
                        read_valid <= !is_scrub_read;
                        
                        state <= ST_LOG;
                    end
                end
                
                ST_LOG: begin
                    // Log error to error log
                    error_log_addr[log_write_ptr] <= pending_addr;
                    error_log_syndrome[log_write_ptr] <= syndrome;
                    error_log_correctable[log_write_ptr] <= (syndrome[7] == 1);
                    error_log_timestamp[log_write_ptr] <= timestamp;
                    log_entries_valid[log_write_ptr] <= 1;
                    log_write_ptr <= log_write_ptr + 1;
                    
                    // If correctable error during scrub, write back corrected data
                    if (is_scrub_read && syndrome[7] == 1) begin
                        mem_write <= 1;
                        mem_write_addr <= scrub_position;
                        mem_write_data <= {1'b0, generate_ecc(data_buffer), data_buffer};
                    end
                    
                    state <= ST_IDLE;
                end
                
                ST_SCRUB: begin
                    scrub_addr <= scrub_position;
                    pending_addr <= scrub_position;
                    state <= ST_READ;
                    
                    // Advance scrub position
                    if (scrub_position >= SCRUB_END_ADDR) begin
                        scrub_position <= 0;
                    end else begin
                        scrub_position <= scrub_position + (DATA_WIDTH/8);
                    end
                    
                    scrub_counter <= 0;
                    scrub_active <= 0;
                end
            endcase
        end
    end

endmodule
