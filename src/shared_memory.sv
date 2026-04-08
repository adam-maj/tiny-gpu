`default_nettype none
`timescale 1ns/1ns

// SHARED MEMORY
// > Fast on-chip memory shared between threads in a block
// > Multi-banked for parallel access
// > Supports concurrent reads from different banks
// > Bank conflicts cause serialization
module shared_memory #(
    parameter ADDR_BITS = 8,           // Address width
    parameter DATA_BITS = 8,           // Data width
    parameter NUM_BANKS = 4,           // Number of memory banks
    parameter BANK_SIZE = 64,          // Words per bank
    parameter NUM_PORTS = 4            // Number of access ports (threads)
) (
    input wire clk,
    input wire reset,
    
    // Multi-port interface
    input wire [NUM_PORTS-1:0] read_valid,
    input wire [ADDR_BITS-1:0] read_addr [NUM_PORTS-1:0],
    output reg [NUM_PORTS-1:0] read_ready,
    output reg [DATA_BITS-1:0] read_data [NUM_PORTS-1:0],
    
    input wire [NUM_PORTS-1:0] write_valid,
    input wire [ADDR_BITS-1:0] write_addr [NUM_PORTS-1:0],
    input wire [DATA_BITS-1:0] write_data [NUM_PORTS-1:0],
    output reg [NUM_PORTS-1:0] write_ready,
    
    // Bank conflict indicator
    output reg [NUM_PORTS-1:0] bank_conflict
);
    localparam BANK_BITS = $clog2(NUM_BANKS);
    localparam BANK_ADDR_BITS = $clog2(BANK_SIZE);
    
    // Memory banks
    reg [DATA_BITS-1:0] bank_mem [NUM_BANKS-1:0][BANK_SIZE-1:0];
    
    // Bank request tracking
    reg [NUM_PORTS-1:0] bank_read_request [NUM_BANKS-1:0];
    reg [NUM_PORTS-1:0] bank_write_request [NUM_BANKS-1:0];
    
    // Address decoding
    wire [BANK_BITS-1:0] read_bank [NUM_PORTS-1:0];
    wire [BANK_ADDR_BITS-1:0] read_bank_addr [NUM_PORTS-1:0];
    wire [BANK_BITS-1:0] write_bank [NUM_PORTS-1:0];
    wire [BANK_ADDR_BITS-1:0] write_bank_addr [NUM_PORTS-1:0];
    
    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1) begin : addr_decode
            assign read_bank[p] = read_addr[p][BANK_BITS-1:0];
            assign read_bank_addr[p] = read_addr[p][BANK_BITS +: BANK_ADDR_BITS];
            assign write_bank[p] = write_addr[p][BANK_BITS-1:0];
            assign write_bank_addr[p] = write_addr[p][BANK_BITS +: BANK_ADDR_BITS];
        end
    endgenerate
    
    integer i, j, b;
    
    // Bank conflict detection and request routing
    always @(*) begin
        // Initialize
        for (b = 0; b < NUM_BANKS; b = b + 1) begin
            bank_read_request[b] = 0;
            bank_write_request[b] = 0;
        end
        
        // Map requests to banks
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            if (read_valid[i]) begin
                bank_read_request[read_bank[i]][i] = 1;
            end
            if (write_valid[i]) begin
                bank_write_request[write_bank[i]][i] = 1;
            end
        end
        
        // Detect conflicts (more than one request to same bank)
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            bank_conflict[i] = 0;
            if (read_valid[i]) begin
                // Check if another port also wants this bank
                for (j = 0; j < NUM_PORTS; j = j + 1) begin
                    if (j != i && read_valid[j] && read_bank[j] == read_bank[i]) begin
                        // Lower port ID wins
                        if (j < i) bank_conflict[i] = 1;
                    end
                    if (write_valid[j] && write_bank[j] == read_bank[i]) begin
                        // Write takes priority
                        bank_conflict[i] = 1;
                    end
                end
            end
            if (write_valid[i]) begin
                for (j = 0; j < NUM_PORTS; j = j + 1) begin
                    if (j != i && write_valid[j] && write_bank[j] == write_bank[i]) begin
                        if (j < i) bank_conflict[i] = 1;
                    end
                end
            end
        end
    end
    
    // Memory operations
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                read_ready[i] <= 0;
                write_ready[i] <= 0;
                read_data[i] <= 0;
            end
            // Initialize memory to zero
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                for (i = 0; i < BANK_SIZE; i = i + 1) begin
                    bank_mem[b][i] <= 0;
                end
            end
        end else begin
            // Process requests (no conflict = immediate service)
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                read_ready[i] <= 0;
                write_ready[i] <= 0;
                
                // Write has priority
                if (write_valid[i] && !bank_conflict[i]) begin
                    bank_mem[write_bank[i]][write_bank_addr[i]] <= write_data[i];
                    write_ready[i] <= 1;
                end else if (read_valid[i] && !bank_conflict[i]) begin
                    read_data[i] <= bank_mem[read_bank[i]][read_bank_addr[i]];
                    read_ready[i] <= 1;
                end
            end
        end
    end
endmodule
