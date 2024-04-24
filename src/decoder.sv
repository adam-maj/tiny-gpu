`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes an instruction into the control signals necessary to execute it
// > Each core has it's own decoder
module decoder (
    input wire clk,
    input wire reset,

    input reg [2:0] core_state,
    input reg [15:0] instruction,
    
    // Instruction Signals
    output reg [3:0] decoded_rd_address,
    output reg [3:0] decoded_rs_address,
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control Signals
    output reg decoded_reg_write_enable,           // Enable writing to a register
    output reg decoded_mem_read_enable,            // Enable reading from memory
    output reg decoded_mem_write_enable,           // Enable writing to memory
    output reg decoded_nzp_write_enable,           // Enable writing to NZP register
    output reg [1:0] decoded_reg_input_mux,        // Select input to register
    output reg [1:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output reg decoded_alu_output_mux,             // Select operation in ALU
    output reg decoded_pc_mux,                     // Select source of next PC

    // Return (finished executing thread)
    output reg decoded_ret
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

    always @(posedge clk) begin 
        if (reset) begin 
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;
            decoded_ret <= 0;
        end else begin 
            // Decode when core_state = DECODE
            if (core_state == 3'b010) begin 
                // Get instruction signals from instruction every time
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate <= instruction[7:0];
                decoded_nzp <= instruction[11:9];

                // Control signals reset on every decode and set conditionally by instruction
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_pc_mux <= 0;
                decoded_ret <= 0;

                // Set the control signals for each instruction
                case (instruction[15:12])
                    NOP: begin 
                        // no-op
                    end
                    BRnzp: begin 
                        decoded_pc_mux <= 1;
                    end
                    CMP: begin 
                        decoded_alu_output_mux <= 1;
                        decoded_nzp_write_enable <= 1;
                    end
                    ADD: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b00;
                    end
                    SUB: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b01;
                    end
                    MUL: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b10;
                    end
                    DIV: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b11;
                    end
                    LDR: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b01;
                        decoded_mem_read_enable <= 1;
                    end
                    STR: begin 
                        decoded_mem_write_enable <= 1;
                    end
                    CONST: begin 
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b10;
                    end
                    RET: begin 
                        decoded_ret <= 1;
                    end
                endcase
            end
        end
    end
endmodule
