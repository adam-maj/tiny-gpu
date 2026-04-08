`default_nettype none
`timescale 1ns/1ns

// ATOMIC OPERATIONS UNIT
// > Provides atomic read-modify-write operations
// > Ensures memory consistency for concurrent access
// > Supports: ADD, MIN, MAX, AND, OR, XOR, SWAP, CAS
module atomic_unit #(
    parameter ADDR_BITS = 8,           // Address width
    parameter DATA_BITS = 8            // Data width
) (
    input wire clk,
    input wire reset,
    
    // Request interface
    input wire request_valid,
    input wire [2:0] operation,        // Atomic operation type
    input wire [ADDR_BITS-1:0] address,
    input wire [DATA_BITS-1:0] operand,        // Value to combine
    input wire [DATA_BITS-1:0] compare_value,  // For CAS
    output reg request_ready,
    output reg [DATA_BITS-1:0] result,         // Old value (before atomic)
    
    // Memory interface (exclusive access)
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_addr,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,
    
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_addr,
    output reg [DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready,
    
    // Lock status
    output wire busy,
    output wire [ADDR_BITS-1:0] locked_addr
);
    // Operation codes
    localparam OP_ADD  = 3'd0;
    localparam OP_MIN  = 3'd1;
    localparam OP_MAX  = 3'd2;
    localparam OP_AND  = 3'd3;
    localparam OP_OR   = 3'd4;
    localparam OP_XOR  = 3'd5;
    localparam OP_SWAP = 3'd6;
    localparam OP_CAS  = 3'd7;
    
    // State machine
    localparam S_IDLE = 2'd0;
    localparam S_READ = 2'd1;
    localparam S_COMPUTE = 2'd2;
    localparam S_WRITE = 2'd3;
    
    reg [1:0] state;
    reg [2:0] pending_op;
    reg [ADDR_BITS-1:0] pending_addr;
    reg [DATA_BITS-1:0] pending_operand;
    reg [DATA_BITS-1:0] pending_compare;
    reg [DATA_BITS-1:0] read_value;
    reg [DATA_BITS-1:0] new_value;
    
    assign busy = (state != S_IDLE);
    assign locked_addr = pending_addr;
    
    // Compute new value based on operation
    always @(*) begin
        case (pending_op)
            OP_ADD:  new_value = read_value + pending_operand;
            OP_MIN:  new_value = (read_value < pending_operand) ? read_value : pending_operand;
            OP_MAX:  new_value = (read_value > pending_operand) ? read_value : pending_operand;
            OP_AND:  new_value = read_value & pending_operand;
            OP_OR:   new_value = read_value | pending_operand;
            OP_XOR:  new_value = read_value ^ pending_operand;
            OP_SWAP: new_value = pending_operand;
            OP_CAS:  new_value = (read_value == pending_compare) ? pending_operand : read_value;
            default: new_value = read_value;
        endcase
    end
    
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            request_ready <= 0;
            result <= 0;
            mem_read_valid <= 0;
            mem_write_valid <= 0;
            pending_op <= 0;
            pending_addr <= 0;
            pending_operand <= 0;
            pending_compare <= 0;
            read_value <= 0;
        end else begin
            request_ready <= 0;
            
            case (state)
                S_IDLE: begin
                    if (request_valid) begin
                        pending_op <= operation;
                        pending_addr <= address;
                        pending_operand <= operand;
                        pending_compare <= compare_value;
                        
                        // Start read
                        mem_read_valid <= 1;
                        mem_read_addr <= address;
                        state <= S_READ;
                    end
                end
                
                S_READ: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        read_value <= mem_read_data;
                        state <= S_COMPUTE;
                    end
                end
                
                S_COMPUTE: begin
                    // new_value is computed combinationally
                    // Start write
                    mem_write_valid <= 1;
                    mem_write_addr <= pending_addr;
                    mem_write_data <= new_value;
                    state <= S_WRITE;
                end
                
                S_WRITE: begin
                    if (mem_write_ready) begin
                        mem_write_valid <= 0;
                        result <= read_value;  // Return old value
                        request_ready <= 1;
                        state <= S_IDLE;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
