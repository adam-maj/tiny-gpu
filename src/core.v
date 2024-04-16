`default_nettype none
`timescale 1ns/1ns

module core #(
    parameter BLOCK_ID,
    parameter WARP_SIZE = 4,
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    input wire [7:0] block_dim,
    input wire [7:0] thread_count,

    memory_if.consumer data_memory_control
    memory_if.consumer program_memory_control
);
    localparam IDLE = 2'b00, FETCHING = 2'b01, PROCESSING = 2'10, DONE = 2'b11; 
    reg [1:0] state = IDLE;

    wire [15:0] instruction;
    wire instruction_ready = 0;

    wire [7:0] rs[WARP_SIZE-1:0];
    wire [7:0] rt[WARP_SIZE-1:0];
    wire [7:0] rd[WARP_SIZE-1:0];
    wire [7:0] alu_out[WARP_SIZE-1:0];
    wire lsu_state[WARP_SIZE-1:0];
    wire [7:0] lsu_out[WARP_SIZE-1:0];
    wire [7:0] next_pc[WARP_SIZE-1:0];

    genvar i;
    generate
        for (i = 0; i < WARP_SIZE; i = i + 1) begin : threads
            registers #(
                .BLOCK_ID(BLOCK_ID),
                .THREAD_ID(i)
            ) register_instance (
                .clk(clk),
                .reset(reset),
                .decoded_instruction(decoded_instruction)
                .block_dim(),
                .rd(rd[i]),
                .rs(rs[i]),
                .rt(rt[i])
            );

            alu alu_instance (
                .clk(clk),
                .reset(reset),
                .decoded_instruction(decoded_instruction)
                .rs(rs[i]),
                .rt(rt[i]),
                .alu_out(alu_out[i])
            );

            lsu lsu_instance (
                .clk(clk),
                .reset(reset),
                .decoded_instruction(decoded_instruction),
                .memory_control(data_memory_control),
                .rs(rs[i]),
                .rt(rt[i]),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            pc pc_instance (
                .clk(clk),
                .reset(reset),
                .decoded_instruction(decoded_instruction),
                .nzp_input_data(alu_out[2:0]),
                .pc(warp_pc[current_warp_id]),
                .next_pc(next_pc[i])
            );

            case (decoded_instruction.reg_input_mux)
                2'b00: rd[i] = alu_out[i];
                2'b01: rd[i] = lsu_out[i];
                2'b10: rd[i] = decoded_instruction.immediate;
                default: rd[i] = alu_out[i];
            endcase
        end
    endgenerate

    fetcher fetcher_instance (
        .clk(clk),
        .reset(reset),
        .fetch_enable(state == FETCHING),
        .pc(warp_pc[current_warp_id]),
        .memory_control(program_memory_control),
        .instruction_ready(instruction_ready),
        .instruction(instruction)
    )

    decoded_instruction_if decoded_instruction;
    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
        .instruction(instruction),
        .decoded_instruction(decoded_instruction)
    );

    localparam warp_count = (thread_count + WARP_SIZE - 1) / WARP_SIZE;
    reg [7:0] warp_pc [0:warp_count-1];
    reg warp_done [0:warp_count-1];
    reg [7:0] current_warp_id = 0;

    always @(posedge clk) begin
        if (reset) begin 
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin 
                    if (start) begin 
                        state <= FETCHING;

                        for (int i = 0; i < NUM_WARPS; i++) begin
                            warp_pc[i] <= i * WARP_SIZE;
                            warp_done[i] <= 0;
                        end
                    end
                end
                FETCHING: begin 
                    if (&warp_done) begin
                        core_state <= DONE;
                    end else begin 
                        if (!warp_done[current_warp_id]) begin
                            if (instruction_ready) begin
                                state <= PROCESSING;
                            end
                        end else begin 
                            current_warp_id <= (current_warp_id + 1) % NUM_WARPS;
                        end
                    end
                end
                PROCESSING: begin 
                    // TODO: Is decoding going to happen before this? I think it is!
                    if (decoded_instruction.done == 1) begin
                        warp_done[current_warp_id] <= 1;
                    end else begin
                        // If LSU isn't waiting, update PC and state
                        // otherwise, wait for the LSU to finish its work
                        if (lsu_state != 1) begin 
                            // Check if all next_pc values are the same
                            reg next_pc_divergent = 0;
                            for (int j = 0; j < warp_count - 1; j++) begin
                                if (next_pc[j] != next_pc[j+1]) begin
                                    next_pc_divergent = 1;
                                    break;
                                end
                            end
                            
                            if (!next_pc_divergent) begin
                                // IMPORTANT: UDPATE PC
                                warp_pc[current_warp_id] <= next_pc[0];
                                // build something to fetch the instructions from global memory or cache
                            end else begin
                                // TODO: Branch divergence
                            end

                            // IMPORTANT: UPDATE STATE
                            state <= FETCHING;
                        end
                    end
                end
                DONE: ;
            endcase
        end
    end
endmodule

