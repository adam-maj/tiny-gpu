`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes an instruction into the control signals necessary to execute it
// > Each core has it's own decoder
module riscV_decoder (
    input wire clk,
    input wire reset,

    input reg [2:0] core_state,
    input reg [31:0] instruction,
    
    // Instruction Signals
    output reg [3:0] decoded_rd_address,
    output reg [3:0] decoded_rs_address, //rs == rs1 in RISC-V spec
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control Signals
    output reg decoded_reg_write_enable,           // Enable writing to a register
    output reg decoded_mem_read_enable,            // Enable reading from memory
    output reg decoded_mem_write_enable,           // Enable writing to memory
    output reg decoded_nzp_write_enable,           // Enable writing to NZP register
    output reg [1:0] decoded_reg_input_mux,        // Select input to register
    output reg [3:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output reg decoded_alu_output_mux,             // Select operation in ALU
    output reg [1:0]decoded_pc_mux,                     // Select source of next PC

    //added outputs for new control signals
    output logic [1:0] BYTE_SEL,
	output logic SIGN,
	output logic [2:0] IMM_SEL,
	output logic BRANCH,
	output logic [2:0] BR_TYPE,
	output logic JUMP, 
    //could combine into one signal 
    output logic SPLIT, 
    output logic JOINT, 
    output logic BAR
    //

    // Return (finished executing thread)
    // output reg decoded_ret
);

    wire [2:0] func3;
    assign func3 = instruction[14:12];

    localparam 
        AUIPC = 7'b0010111,
        JAL = 7'b1101111,
        JALR = 7'b1100111,
        LUI = 7'b0110111,
        BTYPE = 7'b1100011,
        LOAD = 7'b0000011,
        STORE = 7'b0100011,
        OP_IMM = 7'b0010011,
        OP = 7'b0110011,
        VORTEX = 7'b0001011;

    localparam TMC_OP = 3'b000, SPLIT_OP = 3'b010, JOIN_OP = 3'b011, BAR_OP = 3'b100, PRED_OP = 3'b101;

    always_ff @(posedge clk ) begin 
        if (reset) begin 
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            // decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;

            BYTE_SEL <= 2'b00;
            SIGN <= 1'b0;
            IMM_SEL <= 3'b000;
            BRANCH <= 1'b0;
            BR_TYPE <= 3'b000;
            JUMP <= 1'b0;

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
                // Set the control signals for each instruction
                case (instruction[6:0])
                    JAL: begin 
                        decoded_pc_mux <= 1; // Jump to immediate 
                        JUMP <= 1; // Set jump signal for JAL instruction
                        IMM_SEL <= 3'b010; // Set immediate type to J-type
                        decoded_reg_write_enable <= 1; // Write return address to rd
                        decoded_reg_input_mux <= 2'b00; // Input to register is PC+4
                    end
                    JALR: begin 
                        JUMP <= 1; // Set jump signal for JALR instruction
                        IMM_SEL <= 3'b000; // Set immediate type to I-type
                        decoded_pc_mux <= 2'b11; // Jump to rs + immediate
                        decoded_reg_write_enable <= 1; // Write return address to rd
                        decoded_reg_input_mux <= 2'b00; // Input to register is PC+4
                    end
                    LUI: begin 
                        IMM_SEL <= 3'b011; // Set immediate type to U-type
                        //decoded_pc_mux <= 0; // No change to PC
                        decoded_reg_write_enable <= 1; // Write to rd
                        decoded_reg_input_mux <= 2'b11; // Input to register is u-type immediate
                        decoded_alu_output_mux <= 1; // ALU outputs u-type immediate (lui-copy)
                    end
                    AUIPC: begin 
                        //decoded_pc_mux <= 0; // No change to PC
                        decoded_reg_write_enable <= 1; // Write to rd
                        decoded_reg_input_mux <= 2'b11; // Input to register is u-type immediate
                        decoded_alu_output_mux <= 0; // ALU outputs pc + u-type immediate
                    end

                    BTYPE: begin 
                        //decoded_pc_mux <= 1; // Jump to immediate if branch taken --> add smthing in if we're not doing pure masking for divergence
                        decoded_pc_mux <= 2'b10; // Conditional branch to immediate
                        IMM_SEL <= 3'b001; // Set immediate type to B-type
                        BRANCH <= 1; // Set branch signal for branch instructions
                        BR_TYPE <= func3; // Set branch type based on func3
                    end
                    LOAD: begin 
                        decoded_mem_read_enable <= 1; // Read from memory
                        decoded_reg_write_enable <= 1; // Write to register
                        decoded_reg_input_mux <= 2'b01; // Input to register is memory output
                        IMM_SEL <= 3'b000;  // I-Type
                        case(func3)					
							3'b000: begin // LB
								BYTE_SEL <= 2'b00;
								SIGN <= 1'b1;		
							end							
							3'b001: begin // LH
								BYTE_SEL <= 2'b01;
								SIGN <= 1'b1;
							end
							3'b010: begin // LW
								BYTE_SEL <= 2'b10;
								SIGN <= 1'b1;
							end
							3'b011: begin // LBU
								BYTE_SEL <= 2'b00;
								SIGN <= 1'b0;
							end
							3'b100: begin //LHU
								BYTE_SEL <= 2'b01;
								SIGN <= 1'b0;
							end
							default: begin // default = LW
								BYTE_SEL <= 2'b10;
								SIGN <= 1'b1;
							end
					    endcase
                    end
                    STORE: begin 
                        decoded_mem_write_enable <= 1; // Write to memory
                        IMM_SEL <= 3'b010; // Set immediate type to S-type
                        case(func3)
                            3'b000: begin // SB
                                BYTE_SEL <= 2'b00;
                            end                            
                            3'b001: begin // SH
                                BYTE_SEL <= 2'b01;
                            end                            
                            3'b010: begin // SW
                                BYTE_SEL <= 2'b10;
                            end
                            default: begin
                                BYTE_SEL <= 2'b10; // SW
                            end
					    endcase
                    end
                    OP_IMM: begin
                        decoded_reg_write_enable <= 1; // Write to register
                        decoded_reg_input_mux <= 2'b10; // Input to register is ALU output
                        decoded_alu_arithmetic_mux <= {1'b0, instruction[14:12]}; // Select arithmetic operation based on funct3
                        if (instruction[14:12] == 3'b001 || instruction[14:12] == 3'b101) begin 
                            decoded_alu_arithmetic_mux <= {instruction[30], func3}; // Select shift operation based on funct3 and funct7
                        end
                    end
                    OP: begin
                        decoded_reg_write_enable <= 1; // Write to register
                        decoded_reg_input_mux <= 2'b10; // Input to register is ALU output
                        decoded_alu_arithmetic_mux <= {instruction[30], instruction[14:12]}; // Select arithmetic operation based on funct3 and funct7
                    end
                    VORTEX: begin
                        case(func3)  
                            TMC_OP: begin
                                // No clue what we doing with this one 
                                decoded_nzp_write_enable <= 1; // Write to NZP register to set predicate based on TMC instruction
                            end
                            // WSPAWN_OP: begin
                            //     // don't handle here 
                            // end
                            SPLIT_OP: begin
                                // No control signals to set for split instruction in this implementation, but we could set some if needed
                                SPLIT <= 1; 
                                decoded_rs_address <= instruction[7:4]; // Use rs field to specify number of threads in new warp for split instruction
                                decoded_rd_address <= instruction[11:8]; // Use rd field to specify warp ID for new warp in split instruction
                            end
                            JOIN_OP: begin
                                // No control signals to set for joint instruction in this implementation, but we could set some if needed
                                JOINT <= 1;
                            end
                            BAR_OP: begin
                                // No control signals to set for barrier instruction in this implementation, but we could set some if needed
                                BAR <= 1;
                            end
                            PRED_OP: begin
                                // No control signals to set for predication instruction in this implementation, but we could set some if needed
                                decoded_nzp_write_enable <= 1; // Write to NZP register to set predicate for predication instruction
                            end
                            default: begin ; end 
                        endcase
                    end
                    default: begin 
                        // For unrecognized instructions, keep all control signals at default (mostly 0)
                    end
                endcase
            end
        end
    end
endmodule
