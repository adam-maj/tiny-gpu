`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from global data memory
// > Each core has it's own fetcher
//
// OPTIMIZATION (basic pipelining): once this round's instruction has been
// captured (FETCHED), the single memory port this fetcher owns sits
// completely idle for the rest of the round (WAIT/EXECUTE/UPDATE) under the
// old design - it does nothing until core_state cycles back around to FETCH.
// Instead, we immediately use that idle window to speculatively prefetch
// PC+1 (the common case: straight-line code / not-taken branch) into a
// one-deep buffer. When the next round actually starts:
//   - if the scheduler's chosen PC matches the buffered guess, the
//     instruction is already sitting there and FETCH collapses to 1 cycle
//     (no memory round trip at all - not even an icache hit's latency).
//   - if it doesn't match (branch taken, divergence picked a different PC,
//     loop back-edge, etc.), the stale guess is discarded and we fall back
//     to an ordinary fetch - identical latency to the non-pipelined design,
//     so a misprediction never costs *more* than before.
// Both the committed fetch and the speculative prefetch share this one
// memory port; they're mutually exclusive in time (see PREFETCHING state),
// so the icache/controller below only ever sees one outstanding request at
// a time, same as pre-pipelining.
//
// CORRECTNESS NOTE (block-boundary draining): the program memory controller
// (controller.sv) and icache (icache.sv) have no notion of a "request ID" -
// a consumer's most recent completed transaction is just "whatever
// mem_read_ready/mem_read_data currently show". If this fetcher abandoned an
// in-flight request outright on reset (e.g. a prefetch still waiting on a
// cache-miss round trip when the block it belongs to finishes and the core
// resets for the next block), the *next* block's very first fetch could
// start before that stale response arrives - and would then be handed the
// old, unrelated data as if it were the answer to its own request. To avoid
// this, reset does NOT rip out a request that's actually in flight
// (mem_read_valid=1); it lets it drain (via DRAINING below) and only lets
// the fetcher go properly idle once the response has actually arrived and
// been discarded, so a new block's requests can never be issued while a
// stale one is still outstanding underneath them.
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    
    // Execution State
    input reg [2:0] core_state,
    input reg [7:0] current_pc,

    // Program Memory
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction,

    // Stats - pulses high for exactly 1 cycle whenever a round's instruction was
    // served instantly from the prefetch buffer instead of a fresh memory fetch.
    // Exposed for the live dashboard.
    output reg prefetch_hit
);
    localparam IDLE = 3'b000, 
        FETCHING = 3'b001, 
        FETCHED = 3'b010,
        PREFETCHING = 3'b011,
        DRAINING = 3'b100; // see module header comment - absorbing an abandoned in-flight request

    // One-deep speculative prefetch buffer
    reg prefetch_valid;                              // Buffer holds a completed, unconsumed prefetch
    reg [PROGRAM_MEM_ADDR_BITS-1:0] prefetch_target;  // Address that request was/is for
    reg [PROGRAM_MEM_DATA_BITS-1:0] prefetch_instruction;

    always @(posedge clk) begin
        if (reset) begin
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
            prefetch_valid <= 0;
            prefetch_target <= 0;
            prefetch_instruction <= 0;
            prefetch_hit <= 0;

            if (mem_read_valid) begin
                // A request is genuinely in flight (either a real fetch or a
                // speculative prefetch) - don't abandon it, let it drain first
                // (see module header comment). mem_read_valid/mem_read_address
                // are deliberately left untouched so the outstanding request
                // stays exactly as the icache/controller already saw it.
                fetcher_state <= DRAINING;
            end else begin
                fetcher_state <= IDLE;
                mem_read_valid <= 0;
                mem_read_address <= 0;
            end
        end else begin
            prefetch_hit <= 0;

            case (fetcher_state)
                DRAINING: begin
                    // Absorb (and discard) the response to whatever was in flight when
                    // reset happened, before this fetcher is allowed to issue anything
                    // new - see module header comment for why this matters.
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        fetcher_state <= IDLE;
                    end
                end
                IDLE: begin
                    // Start fetching when core_state = FETCH
                    if (core_state == 3'b001) begin
                        if (prefetch_valid && prefetch_target == current_pc) begin
                            // Speculative guess paid off - deliver instantly, no memory access
                            instruction <= prefetch_instruction;
                            prefetch_valid <= 0;
                            prefetch_hit <= 1;
                            fetcher_state <= FETCHED;
                        end else begin
                            // No usable prefetch (first fetch of the block, or the buffered
                            // guess was for the wrong address) - fetch for real
                            prefetch_valid <= 0;
                            mem_read_valid <= 1;
                            mem_read_address <= current_pc;
                            fetcher_state <= FETCHING;
                        end
                    end
                end
                FETCHING: begin
                    // Wait for response from program memory
                    if (mem_read_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= mem_read_data; // Store the instruction when received
                        mem_read_valid <= 0;
                    end
                end
                FETCHED: begin
                    // This round's instruction has been captured (the scheduler already saw
                    // FETCHED this same edge and is moving on to DECODE) - the memory port is
                    // now free, so immediately kick off a speculative fetch of PC+1 to use up
                    // the idle WAIT/EXECUTE/UPDATE window instead of waiting for next round's
                    // FETCH to start one from scratch.
                    prefetch_target <= current_pc + 1;
                    mem_read_valid <= 1;
                    mem_read_address <= current_pc + 1;
                    fetcher_state <= PREFETCHING;
                end
                PREFETCHING: begin
                    if (mem_read_ready) begin
                        mem_read_valid <= 0;
                        if (core_state == 3'b001 && current_pc == prefetch_target) begin
                            // The next round is already waiting on exactly this address -
                            // hand it straight over instead of bouncing through IDLE first
                            instruction <= mem_read_data;
                            prefetch_hit <= 1;
                            fetcher_state <= FETCHED;
                        end else begin
                            // Buffer it for whenever (if ever) the scheduler asks for this PC
                            prefetch_instruction <= mem_read_data;
                            prefetch_valid <= 1;
                            fetcher_state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule
