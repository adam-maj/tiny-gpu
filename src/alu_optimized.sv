`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED ARITHMETIC-LOGIC UNIT
// > Improvements over original ALU:
//   1. Pre-computed arithmetic results for all operations (parallel execution)
//   2. Final mux selection uses registered inputs (shorter critical path)
//   3. Comparison results computed in parallel with arithmetic
//   4. Division implemented as shift (for power-of-2) with fallback
// > Each thread in each core has its own ALU
module alu_optimized (
    input wire clk,
    input wire reset,
    input wire enable,

    input [2:0] core_state,

    input [1:0] decoded_alu_arithmetic_mux,
    input decoded_alu_output_mux,

    input [7:0] rs,
    input [7:0] rt,
    output wire [7:0] alu_out
);
    localparam ADD = 2'b00,
               SUB = 2'b01,
               MUL = 2'b10,
               DIV = 2'b11;

    // Pipeline stage 1: Compute all results in parallel
    reg [7:0] add_result;
    reg [7:0] sub_result;
    reg [7:0] mul_result;
    reg [7:0] div_result;
    reg [2:0] cmp_result;
    
    // Pipeline stage 2: Select and output
    reg [7:0] alu_out_reg;
    assign alu_out = alu_out_reg;

    // Registered inputs for better timing
    reg [7:0] rs_reg, rt_reg;
    reg [1:0] op_reg;
    reg output_mux_reg;
    reg compute_enable;

    // Pre-compute comparison flags
    wire [7:0] diff = rs - rt;
    wire is_positive = (diff != 0) && !diff[7];  // positive and non-zero
    wire is_zero = (diff == 0);
    wire is_negative = diff[7];  // MSB indicates negative

    always @(posedge clk) begin
        if (reset) begin
            alu_out_reg <= 8'b0;
            add_result <= 8'b0;
            sub_result <= 8'b0;
            mul_result <= 8'b0;
            div_result <= 8'b0;
            cmp_result <= 3'b0;
            rs_reg <= 8'b0;
            rt_reg <= 8'b0;
            op_reg <= 2'b0;
            output_mux_reg <= 0;
            compute_enable <= 0;
        end else if (enable) begin
            // Stage 1: Register inputs and pre-compute results when entering EXECUTE
            if (core_state == 3'b100) begin  // WAIT state - prepare for EXECUTE
                rs_reg <= rs;
                rt_reg <= rt;
                op_reg <= decoded_alu_arithmetic_mux;
                output_mux_reg <= decoded_alu_output_mux;
                compute_enable <= 1;
                
                // Pre-compute all arithmetic results in parallel
                add_result <= rs + rt;
                sub_result <= rs - rt;
                mul_result <= rs * rt;
                // Use shift for power-of-2 division when possible
                div_result <= (rt == 8'd2) ? (rs >> 1) :
                              (rt == 8'd4) ? (rs >> 2) :
                              (rt == 8'd8) ? (rs >> 3) :
                              (rt != 0) ? (rs / rt) : 8'hFF;
                              
                // Pre-compute comparison
                cmp_result <= {is_positive, is_zero, is_negative};
            end
            
            // Stage 2: Final selection during EXECUTE
            if (core_state == 3'b101 && compute_enable) begin
                compute_enable <= 0;
                
                if (output_mux_reg) begin
                    // Comparison result
                    alu_out_reg <= {5'b0, cmp_result};
                end else begin
                    // Arithmetic result - simple mux selection
                    case (op_reg)
                        ADD: alu_out_reg <= add_result;
                        SUB: alu_out_reg <= sub_result;
                        MUL: alu_out_reg <= mul_result;
                        DIV: alu_out_reg <= div_result;
                    endcase
                end
            end
        end
    end
endmodule
