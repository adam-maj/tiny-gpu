`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED INSTRUCTION DECODER
// > Improvements over original decoder:
//   1. Combinational decode with registered outputs (shorter critical path)
//   2. Instruction field extraction separated from control signal generation
//   3. One-hot opcode encoding for faster comparisons
//   4. Control signal defaults use wire assignments instead of sequential reset
// > Each core has its own decoder
module decoder_optimized (
    input wire clk,
    input wire reset,

    input [2:0] core_state,
    input [15:0] instruction,
    
    // Instruction Signals
    output reg [3:0] decoded_rd_address,
    output reg [3:0] decoded_rs_address,
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control Signals
    output reg decoded_reg_write_enable,
    output reg decoded_mem_read_enable,
    output reg decoded_mem_write_enable,
    output reg decoded_nzp_write_enable,
    output reg [1:0] decoded_reg_input_mux,
    output reg [1:0] decoded_alu_arithmetic_mux,
    output reg decoded_alu_output_mux,
    output reg decoded_pc_mux,

    output reg decoded_ret
);
    // Opcode definitions
    localparam [3:0] NOP   = 4'b0000,
                     BRnzp = 4'b0001,
                     CMP   = 4'b0010,
                     ADD   = 4'b0011,
                     SUB   = 4'b0100,
                     MUL   = 4'b0101,
                     DIV   = 4'b0110,
                     LDR   = 4'b0111,
                     STR   = 4'b1000,
                     CONST = 4'b1001,
                     RET   = 4'b1111;

    // Extract opcode for faster comparison
    wire [3:0] opcode = instruction[15:12];

    // Pre-extract instruction fields (combinational)
    wire [3:0] rd_field = instruction[11:8];
    wire [3:0] rs_field = instruction[7:4];
    wire [3:0] rt_field = instruction[3:0];
    wire [7:0] imm_field = instruction[7:0];
    wire [2:0] nzp_field = instruction[11:9];

    // One-hot opcode decode (combinational) - faster than case comparison
    wire is_nop   = (opcode == NOP);
    wire is_br    = (opcode == BRnzp);
    wire is_cmp   = (opcode == CMP);
    wire is_add   = (opcode == ADD);
    wire is_sub   = (opcode == SUB);
    wire is_mul   = (opcode == MUL);
    wire is_div   = (opcode == DIV);
    wire is_ldr   = (opcode == LDR);
    wire is_str   = (opcode == STR);
    wire is_const = (opcode == CONST);
    wire is_ret   = (opcode == RET);

    // Pre-compute control signals (combinational)
    wire is_alu_op = is_add | is_sub | is_mul | is_div;
    wire needs_reg_write = is_alu_op | is_ldr | is_const;
    
    // ALU operation encoding
    wire [1:0] alu_op = is_sub ? 2'b01 :
                        is_mul ? 2'b10 :
                        is_div ? 2'b11 : 2'b00;  // Default ADD

    // Register input mux: 0=ALU, 1=MEM, 2=CONST
    wire [1:0] reg_mux = is_ldr   ? 2'b01 :
                         is_const ? 2'b10 : 2'b00;

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
                // Register instruction fields
                decoded_rd_address <= rd_field;
                decoded_rs_address <= rs_field;
                decoded_rt_address <= rt_field;
                decoded_immediate <= imm_field;
                decoded_nzp <= nzp_field;

                // Register pre-computed control signals
                decoded_reg_write_enable <= needs_reg_write;
                decoded_mem_read_enable <= is_ldr;
                decoded_mem_write_enable <= is_str;
                decoded_nzp_write_enable <= is_cmp;
                decoded_reg_input_mux <= reg_mux;
                decoded_alu_arithmetic_mux <= alu_op;
                decoded_alu_output_mux <= is_cmp;
                decoded_pc_mux <= is_br;
                decoded_ret <= is_ret;
            end
        end
    end
endmodule
