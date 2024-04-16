`default_nettype none
`timescale 1ns/1ns

module gpu #(
    parameter CORES = 4
) (
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    input wire dcr_write_enable,
    input wire [7:0] dcr_data,

    memory_if.consumer data_memory_control
    memory_if.consumer program_memory_control
);
    reg [7:0] device_conrol_register;
    wire [7:0] thread_count;
    wire [7:0] block_dim;
    wire core_done [0:CORES-1];

    assign thread_count = device_conrol_register[7:0];
    assign block_dim = (thread_count + CORES - 1) / CORES;
    
    always @(posedge clk) begin
        if (reset) begin
            device_conrol_register <= 8'b0;
        end else begin
            if (dcr_write_enable) begin 
                device_conrol_register <= dcr_data;
            end
        end
    end

    genvar i;
    generate
        for (i = 0; i < CORES; i = i + 1) begin : cores
            localparam block_thread_count = (i == CORES - 1) 
                ? (thread_count - (BLOCK_DIM * i)) 
                : BLOCK_DIM;

            core #(
                .BLOCK_ID(i)
            ) core_instance (
                .clk(clk),
                .reset(reset),
                .start(start),
                .block_dim(block_dim),
                .thread_count(block_thread_count)
                .data_memory_control(data_memory_control),
                .program_memory_control(program_memory_control)
                .done(core_done[i])
            )
        end
    endgenerate

    assign done = &(core_done);
endmodule