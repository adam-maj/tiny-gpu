`default_nettype none
`timescale 1ns/1ns

// BARRIER SYNCHRONIZATION UNIT
// > Provides thread synchronization within a block
// > All threads must reach barrier before any can proceed
// > Supports multiple named barriers
module barrier #(
    parameter NUM_THREADS = 4,         // Number of threads in block
    parameter NUM_BARRIERS = 2         // Number of independent barriers
) (
    input wire clk,
    input wire reset,
    
    // Barrier interface (one per thread)
    input wire [NUM_THREADS-1:0] barrier_request,      // Thread requests barrier
    input wire [$clog2(NUM_BARRIERS)-1:0] barrier_id [NUM_THREADS-1:0],  // Which barrier
    output reg [NUM_THREADS-1:0] barrier_release,      // Thread can proceed
    
    // Thread mask (which threads are active)
    input wire [NUM_THREADS-1:0] active_threads,
    
    // Status
    output wire [NUM_BARRIERS-1:0] barrier_active,     // Barrier has waiting threads
    output wire [NUM_BARRIERS-1:0] barrier_complete    // All active threads reached
);
    // Barrier state per barrier ID
    reg [NUM_THREADS-1:0] threads_waiting [NUM_BARRIERS-1:0];
    reg [NUM_BARRIERS-1:0] barrier_triggered;
    
    // Count active threads
    integer count;
    reg [$clog2(NUM_THREADS)+1:0] active_count;
    always @(*) begin
        active_count = 0;
        for (count = 0; count < NUM_THREADS; count = count + 1) begin
            if (active_threads[count]) active_count = active_count + 1;
        end
    end
    
    // Check barrier completion
    genvar b;
    generate
        for (b = 0; b < NUM_BARRIERS; b = b + 1) begin : barrier_check
            wire [$clog2(NUM_THREADS)+1:0] waiting_count;
            reg [$clog2(NUM_THREADS)+1:0] wait_cnt;
            integer w;
            
            always @(*) begin
                wait_cnt = 0;
                for (w = 0; w < NUM_THREADS; w = w + 1) begin
                    if (threads_waiting[b][w]) wait_cnt = wait_cnt + 1;
                end
            end
            
            assign waiting_count = wait_cnt;
            assign barrier_active[b] = (waiting_count > 0);
            assign barrier_complete[b] = (waiting_count == active_count) && (active_count > 0);
        end
    endgenerate
    
    integer i, j;
    
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_BARRIERS; i = i + 1) begin
                threads_waiting[i] <= 0;
                barrier_triggered[i] <= 0;
            end
            barrier_release <= 0;
        end else begin
            barrier_release <= 0;
            
            // Process barrier requests
            for (i = 0; i < NUM_THREADS; i = i + 1) begin
                if (barrier_request[i] && active_threads[i]) begin
                    threads_waiting[barrier_id[i]][i] <= 1;
                end
            end
            
            // Check for barrier completion and release
            for (j = 0; j < NUM_BARRIERS; j = j + 1) begin
                if (barrier_complete[j] && !barrier_triggered[j]) begin
                    // All threads reached - release them
                    barrier_release <= barrier_release | threads_waiting[j];
                    threads_waiting[j] <= 0;
                    barrier_triggered[j] <= 1;
                end
                
                // Reset trigger when barrier becomes inactive
                if (!barrier_active[j]) begin
                    barrier_triggered[j] <= 0;
                end
            end
        end
    end
endmodule
