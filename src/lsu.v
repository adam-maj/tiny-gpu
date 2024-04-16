`default_nettype none
`timescale 1ns/1ns

module lsu (
    input wire clk,
    input wire reset,

    decoded_instruction_if.consumer decoded_instruction,
    memory_if.consumer memory_control

    input wire [3:0] rs,
    input wire [3:0] rt,

    output wire [1:0] lsu_state,
    output wire [7:0] lsu_out,
);
    localparam IDLE = 0, WAITING = 1;
    reg read_state = IDLE;
    reg write_state = IDLE;

    always @(*) begin
        if (read_state == WAITING || write_state == WAITING) begin
            lsu_state = WAITING;
        end else begin
            lsu_state = IDLE;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            read_state <= IDLE;
        end else begin
            case (read_state)
                IDLE: begin
                    if (decoded_instruction.mem_read_enable) begin
                        memory_control.mem_read_valid <= 1;
                        memory_control.mem_read_address <= rs;
                        read_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (memory_control.mem_read_ready) begin
                        memory_control.mem_read_valid <= 0;
                        lsu_out = memory_control.mem_read_data;
                        read_state <= IDLE;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            write_state <= IDLE;
        end else begin
            case (write_state)
                IDLE: begin
                    if (decoded_instruction.mem_write_enable) begin
                        memory_control.mem_write_valid <= 1;
                        memory_control.mem_write_address <= rs;
                        memory_control.mem_write_data <= rt;
                        write_state <= WAITING;
                    end
                end
                WAITING: begin
                    if (memory_control.mem_write_ready) begin
                        memory_control.mem_write_valid <= 0;
                        write_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule