module pc (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some PCs will be inactive

    // State
    input [2:0] core_state,

    // Control Signals
    input [2:0] decoded_nzp,
    input [7:0] decoded_immediate,
    input decoded_nzp_write_enable,
    input decoded_pc_mux, 

    // ALU Output - used for alu_out[2:0] to compare with NZP register
    input [7:0] alu_out,

    // Current & Next PCs
    input [7:0] current_pc,
    output reg [7:0] next_pc
);
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
            next_pc <= 0;
        end else if (enable) begin
            // Update PC when core_state = EXECUTE
            if (core_state == 3'b101) begin 
                if (decoded_pc_mux == 1) begin 
                    if (((nzp & decoded_nzp) != 3'b0)) begin 
                        // On BRnzp instruction, branch to immediate if NZP case matches previous CMP
                        next_pc <= decoded_immediate;
                    end else begin 
                        // Otherwise, just update to PC + 1 (next line)
                        next_pc <= current_pc + 1;
                    end
                end else begin 
                    // By default update to PC + 1 (next line)
                    next_pc <= current_pc + 1;
                end
            end   

            // Store NZP when core_state = UPDATE   
            if (core_state == 3'b110) begin 
                // Write to NZP register on CMP instruction
                if (decoded_nzp_write_enable) begin
                    nzp[2] <= alu_out[2];
                    nzp[1] <= alu_out[1];
                    nzp[0] <= alu_out[0];
                end
            end      
        end
    end

endmodule
