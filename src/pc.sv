`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// > Calculates & owns the next PC for this thread
// > Each thread in each core has it's own PC register and it's own NZP flags -
//   this is what makes branch divergence possible (see scheduler.sv): when a
//   BRnzp branches differently across threads (because each thread's `nzp` was
//   set independently by its own CMP), their PCs simply diverge from here on.
// > The NZP register value is set by the CMP instruction (based on >/=/< comparison) to 
//   initiate the BRnzp instruction for branching
//
// OPTIMIZATION (branch divergence): `current_pc` used to be a single core-wide
// register fed in from the scheduler, hard-coding the (incorrect) assumption that
// every thread always agrees on the next PC. Now each thread owns its own PC here;
// the scheduler (see scheduler.sv) picks the lowest PC among still-running threads
// each round, fetches+decodes exactly one instruction for it, and only the threads
// whose own PC matches get to execute it (everyone else just waits their turn).
// Threads that took different branches keep making progress independently and
// naturally reconverge once their PCs line up again.
module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable, // High only for threads whose own PC matches the instruction being executed this round

    // State
    input reg [2:0] core_state,

    // Control Signals
    input reg [2:0] decoded_nzp,
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    input reg decoded_nzp_write_enable,
    input reg decoded_pc_mux, 

    // ALU Output - used for alu_out[2:0] to compare with NZP register
    input reg [DATA_MEM_DATA_BITS-1:0] alu_out,

    // This thread's own program counter (persists across rounds where this thread isn't active)
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc
);
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
            current_pc <= 0;
        end else if (enable) begin
            // Update this thread's own PC when core_state = EXECUTE
            if (core_state == 3'b100) begin 
                if (decoded_pc_mux == 1) begin 
                    if (((nzp & decoded_nzp) != 3'b0)) begin 
                        // On BRnzp instruction, branch to immediate if NZP case matches previous CMP
                        current_pc <= decoded_immediate;
                    end else begin 
                        // Otherwise, just update to PC + 1 (next line)
                        current_pc <= current_pc + 1;
                    end
                end else begin 
                    // By default update to PC + 1 (next line)
                    current_pc <= current_pc + 1;
                end
            end   

            // Store NZP when core_state = UPDATE   
            if (core_state == 3'b101) begin 
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
