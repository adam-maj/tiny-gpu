`default_nettype none
`timescale 1ns/1ns

module decoder (
    input wire clk,
    input wire reset,
    input wire [15:0] instruction,
    
    // Values
    output wire [3:0] decoded_rd_address,
    output wire [3:0] decoded_rs_address,
    output wire [3:0] decoded_rt_address,
    output wire [2:0] decoded_nzp,
    output wire [7:0] decoded_immediate,
    
    // Signals
    output wire decoded_reg_write_enable,           // Enable writing to a register
    output wire decoded_mem_read_enable,            // Enable reading from memory
    output wire decoded_mem_write_enable,           // Enable writing to memory
    output wire decoded_nzp_write_enable,           // Enable writing to NZP register
    output wire [1:0] decoded_reg_input_mux,        // Select input to register
    output wire [1:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output wire decoded_alu_output_mux,             // Select operation in ALU
    
    output wire decoded_pc_mux,                     // Select source of next PC

    // Done
    output wire decoded_done
);
    localparam NOP = 4'b0000,
        BRnzp = 4'b0001,
        CMP = 4'b0010,
        ADD = 4'b0011,
        SUB = 4'b0100,
        MUL = 4'b0101,
        DIV = 4'b0110,
        LDR = 4'b0111,
        STR = 4'b1000,
        CONST = 4'b1001,
        RET = 4'b1111;

    assign decoded_reg_write_enable = reset 
        ? 0
        : ((instruction[15:12] == ADD) 
            || (instruction[15:12] == SUB) 
            || (instruction[15:12] == MUL) 
            || (instruction[15:12] == DIV) 
            || (instruction[15:12] == CONST));
    assign decoded_mem_read_enable = reset 
        ? 0
        : (instruction[15:12] == LDR);
    assign decoded_mem_write_enable = reset 
        ? 0 
        : (instruction[15:12] == STR);
    assign decoded_nzp_write_enable = reset 
        ? 0 
        : (instruction[15:12] == CMP);
    assign decoded_reg_input_mux = reset 
        ? 0 
        : ((instruction[15:12] == CONST) ? 2'b10 : 2'b00);
    assign decoded_alu_arithmetic_mux = reset 
        ? 0 
        : ((instruction[15:12] == ADD) ? 2'b00 : 
            (instruction[15:12] == SUB) ? 2'b01 : 
            (instruction[15:12] == MUL) ? 2'b10 : 
            (instruction[15:12] == DIV) ? 2'b11 : 0);
    assign decoded_alu_output_mux = reset 
        ? 0 
        : (instruction[15:12] == CMP);
    assign decoded_pc_mux = reset 
        ? 0 
        : (instruction[15:12] == BRnzp);
    assign decoded_done = reset 
        ? 0 
        : (instruction[15:12] == RET);

    assign decoded_rd_address = instruction[11:8];
    assign decoded_rs_address = instruction[7:4];
    assign decoded_rt_address = instruction[3:0];
    assign decoded_immediate = instruction[7:0];
    assign decoded_nzp = instruction[11:9];

endmodule