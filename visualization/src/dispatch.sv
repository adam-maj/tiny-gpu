module dispatch (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    // Core States
    input [1:0] core_done,
    output reg [1:0] core_start,
    output reg [1:0] core_reset,
    output reg [15:0] core_block_id,        // 2 x 8-bit: {core1_id, core0_id}
    output reg [5:0] core_thread_count,     // 2 x 3-bit: {core1_count, core0_count}

    // Kernel Execution
    output reg done
);
    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + 3) / 4;

    // Keep track of how many blocks have been processed
    reg [7:0] blocks_dispatched; // How many blocks have been sent to cores?
    reg [7:0] blocks_done; // How many blocks have finished processing?
    reg start_execution; // EDA: Unimportant hack used because of EDA tooling

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched = 0;
            blocks_done = 0;
            start_execution <= 0;

            core_start <= 2'b0;
            core_reset <= 2'b11;
            core_block_id <= 16'b0;
            core_thread_count <= 6'b0;
        end else if (start) begin    
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin 
                start_execution <= 1;
                for (i = 0; i < 2; i = i + 1) begin
                    core_reset[i] <= 1;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin 
                done <= 1;
            end

            for (i = 0; i < 2; i = i + 1) begin
                if (core_reset[i]) begin 
                    core_reset[i] <= 0;

                    // If this core was just reset, check if there are more blocks to be dispatched
                    if (blocks_dispatched < total_blocks) begin 
                        core_start[i] <= 1;
                        core_block_id[i*8 +: 8] <= blocks_dispatched;
                        core_thread_count[i*3 +: 3] <= (blocks_dispatched == total_blocks - 1) 
                            ? thread_count - (blocks_dispatched * 4)
                            : 4;

                        blocks_dispatched = blocks_dispatched + 1;
                    end
                end
            end

            for (i = 0; i < 2; i = i + 1) begin
                if (core_start[i] && core_done[i]) begin
                    // If a core just finished executing it's current block, reset it
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    blocks_done = blocks_done + 1;
                end
            end
        end
    end
endmodule