`default_nettype none
`timescale 1ns/1ns

// ============================================================
// MEMORY CONTROLLER
//
// Arbitrates memory access between multiple consumers
// and a limited number of memory channels.
//
// Current Support:
// - Read Requests
// - Write Requests
// - Multi-Channel Arbitration
//
// Future Evolution:
// - Round-Robin Arbitration
// - QoS Scheduling
// - Memory Coalescing
// - Cache Integration
// ============================================================

module controller #(
    parameter int ADDR_BITS      = 8,
    parameter int DATA_BITS      = 16,
    parameter int NUM_CONSUMERS  = 4,
    parameter int NUM_CHANNELS   = 1,
    parameter int WRITE_ENABLE   = 1
)(
    input  logic clk,
    input  logic reset,

    //----------------------------------------------------------
    // Consumer Interface
    //----------------------------------------------------------

    input  logic [NUM_CONSUMERS-1:0]
                 consumer_read_valid,

    input  logic [ADDR_BITS-1:0]
                 consumer_read_address
                 [NUM_CONSUMERS-1:0],

    output logic [NUM_CONSUMERS-1:0]
                 consumer_read_ready,

    output logic [DATA_BITS-1:0]
                 consumer_read_data
                 [NUM_CONSUMERS-1:0],

    input  logic [NUM_CONSUMERS-1:0]
                 consumer_write_valid,

    input  logic [ADDR_BITS-1:0]
                 consumer_write_address
                 [NUM_CONSUMERS-1:0],

    input  logic [DATA_BITS-1:0]
                 consumer_write_data
                 [NUM_CONSUMERS-1:0],

    output logic [NUM_CONSUMERS-1:0]
                 consumer_write_ready,

    //----------------------------------------------------------
    // Memory Interface
    //----------------------------------------------------------

    output logic [NUM_CHANNELS-1:0]
                 mem_read_valid,

    output logic [ADDR_BITS-1:0]
                 mem_read_address
                 [NUM_CHANNELS-1:0],

    input  logic [NUM_CHANNELS-1:0]
                 mem_read_ready,

    input  logic [DATA_BITS-1:0]
                 mem_read_data
                 [NUM_CHANNELS-1:0],

    output logic [NUM_CHANNELS-1:0]
                 mem_write_valid,

    output logic [ADDR_BITS-1:0]
                 mem_write_address
                 [NUM_CHANNELS-1:0],

    output logic [DATA_BITS-1:0]
                 mem_write_data
                 [NUM_CHANNELS-1:0],

    input  logic [NUM_CHANNELS-1:0]
                 mem_write_ready
);

    typedef enum logic [2:0] {
        CTRL_IDLE,
        CTRL_READ_WAIT,
        CTRL_WRITE_WAIT,
        CTRL_READ_RELAY,
        CTRL_WRITE_RELAY
    } controller_state_t;

    controller_state_t controller_state [NUM_CHANNELS-1:0];
    logic [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0];
    logic [NUM_CONSUMERS-1:0] consumer_busy;

    integer i;
    integer j;

    //----------------------------------------------------------
    // Controller
    //----------------------------------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            consumer_busy       <= '0;
            consumer_read_ready <= '0;
            consumer_write_ready<= '0;

            for (i = 0; i < NUM_CONSUMERS; i++) begin
                consumer_read_data[i] <= '0;
            end

            for (i = 0; i < NUM_CHANNELS; i++) begin

                mem_read_valid[i]  <= 1'b0;
                mem_write_valid[i] <= 1'b0;

                mem_read_address[i]  <= '0;
                mem_write_address[i] <= '0;
                mem_write_data[i]    <= '0;

                current_consumer[i] <= '0;
                controller_state[i] <= CTRL_IDLE;
            end

        end
        else begin

            for (i = 0; i < NUM_CHANNELS; i++) begin

                case (controller_state[i])

                    //--------------------------------------------------
                    // IDLE
                    //--------------------------------------------------

                    CTRL_IDLE: begin

                        for (j = 0; j < NUM_CONSUMERS; j++) begin

                            if (consumer_read_valid[j] &&
                                !consumer_busy[j]) begin
                                consumer_busy[j] <= 1'b1;
                                current_consumer[i] <= $clog2(NUM_CONSUMERS)'(j);
                                mem_read_valid[i] <= 1'b1;
                                mem_read_address[i] <= consumer_read_address[j];
                                controller_state[i] <= CTRL_READ_WAIT;
                                break;
                            end

                            if ((WRITE_ENABLE != 0) && consumer_write_valid[j] &&!consumer_busy[j]) begin
                                consumer_busy[j] <= 1'b1;
                                current_consumer[i] <= $clog2(NUM_CONSUMERS)'(j);
                                mem_write_valid[i] <= 1'b1;
                                mem_write_address[i] <= consumer_write_address[j];
                                mem_write_data[i] <= consumer_write_data[j];
                                controller_state[i] <= CTRL_WRITE_WAIT;
                                break;
                            end
                        end
                    end

                    //--------------------------------------------------
                    // READ WAIT
                    //--------------------------------------------------

                    CTRL_READ_WAIT: begin

                        if (mem_read_ready[i]) begin
                            mem_read_valid[i] <= 1'b0;
                            consumer_read_ready[current_consumer[i]] <= 1'b1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
                            controller_state[i]<= CTRL_READ_RELAY;
                        end
                    end

                    //--------------------------------------------------
                    // WRITE WAIT
                    //--------------------------------------------------

                    CTRL_WRITE_WAIT: begin

                        if (mem_write_ready[i]) begin

                            mem_write_valid[i] <= 1'b0;
                            consumer_write_ready[current_consumer[i]] <= 1'b1;
                            controller_state[i] <= CTRL_WRITE_RELAY;
                        end
                    end

                    //--------------------------------------------------
                    // READ RELAY
                    //--------------------------------------------------

                    CTRL_READ_RELAY: begin

                        if (!consumer_read_valid[current_consumer[i]]) begin
                            consumer_busy[current_consumer[i]] <= 1'b0;
                            consumer_read_ready[current_consumer[i]] <= 1'b0;
                            controller_state[i]<= CTRL_IDLE;
                        end
                    end

                    //--------------------------------------------------
                    // WRITE RELAY
                    //--------------------------------------------------

                    CTRL_WRITE_RELAY: begin

                        if (!consumer_write_valid[current_consumer[i]]) begin

                            consumer_busy[current_consumer[i]] <= 1'b0;
                            consumer_write_ready[current_consumer[i]] <= 1'b0;
                            controller_state[i]<= CTRL_IDLE;
                        end
                    end

                    default: begin
                        controller_state[i] <= CTRL_IDLE;
                    end

                endcase
            end
        end
    end

endmodule

`default_nettype wire