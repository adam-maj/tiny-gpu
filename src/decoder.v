`default_nettype none
`timescale 1ns/1ns

interface decoded_instruction_if;
    // Values
    wire [3:0] rd_address;
    wire [3:0] rs_address;
    wire [3:0] rt_address;
    wire [2:0] nzp;
    wire [7:0] immediate;
    
    // Signals
    wire reg_write_enable;           // Enable writing to a register
    wire mem_read_enable;            // Enable reading from memory
    wire mem_write_enable;           // Enable writing to memory
    wire nzp_write_enable;           // Enable writing to NZP register
    wire [1:0] reg_input_mux;        // Select input to register
    wire [1:0] alu_arithmetic_mux;   // Select arithmetic operation
    wire alu_output_mux;             // Select operation in ALU
    wire pc_mux;                     // Select source of next PC

    // Done
    wire done;

    modport decoder (
        output rd_address,
        output rs_address,
        output rt_address,
        output nzp,
        output immediate,
        output reg_write_enable,
        output mem_read_enable,
        output mem_write_enable,
        output nzp_write_enable,
        output reg_input_mux,
        output alu_arithmetic_mux,
        output alu_output_mux,
        output pc_mux,
        output done
    );

    modport consumer (
        input rd_address,
        input rs_address,
        input rt_address,
        input nzp,
        input immediate,
        input reg_write_enable,
        input mem_read_enable,
        input mem_write_enable,
        input nzp_write_enable,
        input reg_input_mux,
        input alu_arithmetic_mux,
        input alu_output_mux,
        input pc_mux,
        input done
    );
endinterface

module decoder (
    input wire clk,
    input wire reset,
    input wire [15:0] instruction,
    decoded_instruction_if.decoder decoded_instruction
);

    assign decoded_instruction.rd_address = instruction[11:8];
    assign decoded_instruction.rs_address = instruction[7:4];
    assign decoded_instruction.rt_address = instruction[3:0];
    assign decoded_instruction.immediate = instruction[7:0];
    assign decoded_instruction.nzp = instruction[11:9];

    // Control signals logic placeholder
    always @(posedge clk) begin
        // Reset all control signals on reset
        if (reset) begin
            decoded_instruction.reg_write_enable = 0;
            decoded_instruction.mem_read_enable = 0;
            decoded_instruction.mem_write_enable = 0;
            decoded_instruction.nzp_write_enable = 0;
            decoded_instruction.reg_input_mux = 0;
            decoded_instruction.alu_op_mux = 0;
            decoded_instruction.alu_mux = 0;
            decoded_instruction.pc_mux = 0;
            decoded_instruction.done = 0;
        end else begin
            // TODO: Mem read and write can't reset to 0 every cycle
            decoded_instruction.reg_write_enable = 0;
            decoded_instruction.mem_read_enable = 0;
            decoded_instruction.mem_write_enable = 0;
            decoded_instruction.nzp_write_enable = 0;
            decoded_instruction.pc_mux = 0;

            case (instruction[15:12])
                // NOP
                4'b0000: ;
                // BRnzp
                4'b0001: begin
                    decoded_instruction.pc_mux = 1;
                end
                // CMP
                4'b0010: begin
                    decoded_instruction.alu_mux = 1;
                    decoded_instruction.nzp_write_enable = 1;
                end
                // ADD
                4'b0011: begin
                    decoded_instruction.alu_arithmetic_mux = 2'b00;
                    decoded_instruction.alu_mux = 0;
                    decoded_instruction.reg_input_mux = 2'b00;
                    decoded_instruction.reg_write_enable = 1;
                end
                // SUB
                4'b0100: begin
                    decoded_instruction.alu_arithmetic_mux = 2'b01;
                    decoded_instruction.alu_mux = 0;
                    decoded_instruction.reg_input_mux = 2'b00;
                    decoded_instruction.reg_write_enable = 1;
                end
                // MUL
                4'b0101: begin
                    decoded_instruction.alu_arithmetic_mux = 2'b10;
                    decoded_instruction.alu_mux = 0;
                    decoded_instruction.reg_input_mux = 2'b00;
                    decoded_instruction.reg_write_enable = 1;
                end
                // DIV
                4'b0110: begin
                    decoded_instruction.alu_arithmetic_mux = 2'b11;
                    decoded_instruction.alu_mux = 0;
                    decoded_instruction.reg_input_mux = 2'b00;
                    decoded_instruction.reg_write_enable = 1;
                end
                // LDR
                4'b0111: begin
                    decoded_instruction.mem_read_enable = 1;
                end
                // STR
                4'b1000: begin
                    decoded_instruction.mem_write_enable = 1;
                end
                // CONST
                4'b1001: begin
                    decoded_instruction.reg_input_mux = 2'b10;
                    decoded_instruction.reg_write_enable = 1;
                end
                // RET
                4'b1111: begin
                    decoded_instruction.done = 1;
                end
            endcase
        end
    end

endmodule