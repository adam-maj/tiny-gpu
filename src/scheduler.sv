`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Manages the entire control flow of a single compute core processing 1 block
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into control signals & read register operands
//    (decoding is combinational, so this also covers what used to be a separate
//    REQUEST cycle - see decoder.sv / registers.sv)
// 3. WAIT - Only entered for LDR/STR: wait for all async memory requests to resolve.
//    Every other instruction skips straight to EXECUTE, since there's nothing to wait on.
// 4. EXECUTE - Execute computations on retrieved data from registers / memory
// 5. UPDATE - Update register values (including NZP register) and program counter
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.
//
// OPTIMIZATION (basic branch divergence): there's still a single fetch/decode
// pipeline per core (one instruction executed per round), but each thread now owns
// its own PC (see pc.sv) instead of assuming they all agree on the next one. Each
// round, this scheduler:
//   1. Picks `current_pc` = the lowest PC among all threads that haven't RET'd yet.
//   2. Latches `active_mask` = which threads' own PC equals `current_pc` - this is
//      latched ONCE per round (alongside current_pc) and held stable all the way
//      through DECODE/WAIT/EXECUTE/UPDATE. This matters: each active thread's own
//      pc.sv advances its PC during EXECUTE, so if we recomputed the mask live from
//      thread_pc afterwards it would (incorrectly) go to all-zero before UPDATE ever
//      got to write results back - latching avoids that.
//   3. Fetches + decodes the single instruction at that PC (unchanged mechanism);
//      only the threads in `active_mask` execute it (see the `enable` ports on
//      alu/lsu/pc/registers in core.sv) - everyone else just sits this round out.
//   4. Each active thread's PC (and, for BRnzp, direction) is computed
//      independently in its own pc.sv, so threads that take different branches
//      simply end up with different PCs and get scheduled separately from here on
//      - until their PCs match again, at which point they naturally reconverge and
//      go back to executing together.
//   5. RET retires threads individually (`retired` mask); the block is done once
//      every thread that was actually enabled for this block has retired.
//
// OPTIMIZATION (control-flow): folding DECODE+REQUEST (via a combinational decoder)
// and skipping WAIT whenever neither decoded_mem_read_enable nor
// decoded_mem_write_enable is set removes 2 cycles/instruction for
// arithmetic/branch/const instructions and 1 cycle/instruction for memory
// instructions, with no change in observable behavior.
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,

    // Memory Access State
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Per-thread state (see pc.sv / core.sv)
    input reg [7:0] thread_pc [THREADS_PER_BLOCK-1:0],       // Each thread's own current PC
    input reg [THREADS_PER_BLOCK-1:0] thread_enable_mask,    // Which threads exist in this block (i < thread_count)
    output reg [THREADS_PER_BLOCK-1:0] active_mask,          // Which threads execute the instruction fetched THIS round
                                                              // (latched once per round - see above)

    // Current PC being fetched this round (= lowest PC among threads still running)
    output reg [7:0] current_pc,

    // Execution State
    output reg [2:0] core_state,
    output reg done
);
    localparam IDLE = 3'b000,   // Waiting to start
        FETCH = 3'b001,         // Fetch instructions from program memory
        DECODE = 3'b010,        // Decode instruction & read register operands
        WAIT = 3'b011,          // Wait for response from memory (LDR/STR only)
        EXECUTE = 3'b100,       // Execute ALU and PC calculations
        UPDATE = 3'b101,        // Update registers, NZP, and PC
        DONE = 3'b110;          // Done executing this block

    // Which threads have already hit RET and are no longer running
    reg [THREADS_PER_BLOCK-1:0] retired;

    // If we're retiring threads this exact cycle (RET resolving in UPDATE), exclude
    // them from "still running" immediately rather than waiting a cycle for `retired`
    // to actually update.
    wire [THREADS_PER_BLOCK-1:0] retiring_now = (core_state == UPDATE && decoded_ret) ? active_mask : {THREADS_PER_BLOCK{1'b0}};
    wire [THREADS_PER_BLOCK-1:0] still_running = thread_enable_mask & ~(retired | retiring_now);

    // Combinationally track the lowest PC among all still-running threads, and which
    // threads would be active if we picked that PC as the next round's target. Both
    // are LATCHED into current_pc/active_mask (below) exactly once per round - see
    // the module header comment for why this can't just be read live throughout the
    // round.
    reg [7:0] lowest_pc;
    reg [THREADS_PER_BLOCK-1:0] next_active_mask;
    integer t;
    always @(*) begin
        lowest_pc = 8'hFF;
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin
            if (still_running[t] && thread_pc[t] < lowest_pc) begin
                lowest_pc = thread_pc[t];
            end
        end
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin
            next_active_mask[t] = still_running[t] && (thread_pc[t] == lowest_pc);
        end
    end

    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0;
            active_mask <= 0;
            core_state <= IDLE;
            done <= 0;
            retired <= 0;
        end else begin 
            case (core_state)
                IDLE: begin
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    if (start) begin 
                        // Start by fetching the next instruction for this block based on PC
                        current_pc <= lowest_pc;
                        active_mask <= next_active_mask;
                        core_state <= FETCH;
                    end
                end
                FETCH: begin 
                    // Move on once fetcher_state = FETCHED
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decoding & register-operand reads are both combinational/synchronous-in-one-cycle
                    // (see decoder.sv, registers.sv). Only LDR/STR need to actually wait on memory.
                    if (decoded_mem_read_enable || decoded_mem_write_enable) begin 
                        core_state <= WAIT;
                    end else begin 
                        core_state <= EXECUTE;
                    end
                end
                WAIT: begin
                    // Wait for all ACTIVE threads' LSUs to finish their request before continuing
                    reg any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        // Make sure no active thread's lsu_state = REQUESTING or WAITING
                        if (active_mask[i] && (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10)) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    // If no LSU is waiting for a response, move onto the next stage
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // Execute is synchronous so we move on after one cycle. Each active thread's
                    // own pc.sv advances its PC this same edge - active_mask itself stays put
                    // (latched) so UPDATE still knows exactly who just ran this instruction.
                    core_state <= UPDATE;
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        retired <= retired | active_mask;
                    end

                    if (still_running == {THREADS_PER_BLOCK{1'b0}}) begin 
                        // Every thread that was actually running has now retired - this block is done
                        done <= 1;
                        core_state <= DONE;
                    end else begin 
                        // Pick the next round's target PC (and matching active threads) among
                        // whichever threads are still running - naturally re-converges once
                        // diverged threads catch back up to each other.
                        current_pc <= lowest_pc;
                        active_mask <= next_active_mask;

                        // Update is synchronous so we move on after one cycle
                        core_state <= FETCH;
                    end
                end
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule
