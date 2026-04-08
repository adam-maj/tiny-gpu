// Command Processor - GPU Front-End Command Queue and Dispatch
// Enterprise-grade command buffer with ring buffer architecture
// Compatible with: NVIDIA Push Buffer, AMD PM4, Intel ExecList
// IEEE 1800-2012 SystemVerilog

module command_processor #(
    parameter RING_BUFFER_DEPTH = 1024,
    parameter CMD_WIDTH = 128,
    parameter NUM_QUEUES = 4,
    parameter DOORBELL_WIDTH = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Host Interface (PCIe/AXI)
    input  logic                    host_write_valid,
    input  logic [31:0]             host_write_addr,
    input  logic [CMD_WIDTH-1:0]    host_write_data,
    output logic                    host_write_ready,
    
    // Doorbell Interface
    input  logic                    doorbell_valid,
    input  logic [1:0]              doorbell_queue_id,
    input  logic [DOORBELL_WIDTH-1:0] doorbell_value,
    
    // Command Output to Execution Units
    output logic                    cmd_valid,
    output logic [7:0]              cmd_opcode,
    output logic [23:0]             cmd_length,
    output logic [63:0]             cmd_address,
    output logic [31:0]             cmd_data,
    input  logic                    cmd_ready,
    
    // Dispatch Interfaces
    output logic                    dispatch_3d_valid,
    output logic [31:0]             dispatch_3d_x,
    output logic [31:0]             dispatch_3d_y,
    output logic [31:0]             dispatch_3d_z,
    input  logic                    dispatch_3d_ready,
    
    output logic                    dispatch_compute_valid,
    output logic [31:0]             dispatch_workgroups,
    output logic [31:0]             dispatch_local_size,
    input  logic                    dispatch_compute_ready,
    
    // DMA Interface
    output logic                    dma_request_valid,
    output logic [63:0]             dma_src_addr,
    output logic [63:0]             dma_dst_addr,
    output logic [31:0]             dma_length,
    output logic [1:0]              dma_direction,
    input  logic                    dma_request_ready,
    
    // Status and Interrupts
    output logic [NUM_QUEUES-1:0]   queue_empty,
    output logic [NUM_QUEUES-1:0]   queue_error,
    output logic                    interrupt_pending,
    output logic [7:0]              interrupt_vector
);

    // Command opcodes (similar to AMD PM4 / NVIDIA methods)
    localparam OP_NOP           = 8'h00;
    localparam OP_DRAW          = 8'h01;
    localparam OP_DRAW_INDEXED  = 8'h02;
    localparam OP_DISPATCH      = 8'h03;
    localparam OP_DMA_COPY      = 8'h04;
    localparam OP_SET_REGISTER  = 8'h05;
    localparam OP_WAIT_EVENT    = 8'h06;
    localparam OP_SIGNAL_EVENT  = 8'h07;
    localparam OP_FENCE         = 8'h08;
    localparam OP_TIMESTAMP     = 8'h09;
    localparam OP_INDIRECT_DRAW = 8'h0A;
    localparam OP_INDIRECT_DISPATCH = 8'h0B;
    localparam OP_LOAD_SHADER   = 8'h0C;
    localparam OP_BIND_RESOURCE = 8'h0D;
    localparam OP_CONTEXT_SWITCH = 8'h0E;
    
    // Ring buffer pointers per queue
    logic [$clog2(RING_BUFFER_DEPTH)-1:0] write_ptr [NUM_QUEUES];
    logic [$clog2(RING_BUFFER_DEPTH)-1:0] read_ptr [NUM_QUEUES];
    logic [$clog2(RING_BUFFER_DEPTH)-1:0] fence_ptr [NUM_QUEUES];
    
    // Command buffer memory
    logic [CMD_WIDTH-1:0] cmd_buffer [NUM_QUEUES][RING_BUFFER_DEPTH];
    
    // Queue state machines
    typedef enum logic [2:0] {
        Q_IDLE,
        Q_FETCH_CMD,
        Q_DECODE,
        Q_EXECUTE,
        Q_WAIT_COMPLETION,
        Q_ERROR
    } queue_state_t;
    
    queue_state_t queue_state [NUM_QUEUES];
    
    // Current command being processed
    logic [CMD_WIDTH-1:0] current_cmd;
    logic [1:0] active_queue;
    logic [7:0] current_opcode;
    
    // Command parsing
    wire [7:0] cmd_op = current_cmd[7:0];
    wire [23:0] cmd_len = current_cmd[31:8];
    wire [63:0] cmd_addr = current_cmd[95:32];
    wire [31:0] cmd_payload = current_cmd[127:96];
    
    // Priority arbiter for queue selection
    logic [1:0] next_queue;
    logic [NUM_QUEUES-1:0] queue_has_work;  // Packed array for reduction OR
    
    always_comb begin
        for (int i = 0; i < NUM_QUEUES; i++) begin
            queue_has_work[i] = (write_ptr[i] != read_ptr[i]) && (queue_state[i] == Q_IDLE);
        end
        
        // Round-robin with priority (queue 0 highest)
        next_queue = 2'b00;
        for (int i = NUM_QUEUES-1; i >= 0; i--) begin
            if (queue_has_work[i]) next_queue = i[1:0];
        end
    end
    
    // Main state machine
    typedef enum logic [3:0] {
        CP_IDLE,
        CP_SELECT_QUEUE,
        CP_FETCH,
        CP_DECODE,
        CP_EXEC_DRAW,
        CP_EXEC_DISPATCH,
        CP_EXEC_DMA,
        CP_EXEC_REGISTER,
        CP_EXEC_FENCE,
        CP_WAIT_COMPLETE,
        CP_UPDATE_PTR,
        CP_ERROR
    } cp_state_t;
    
    cp_state_t cp_state;
    
    // Fence tracking
    logic [31:0] fence_value [NUM_QUEUES];
    logic [31:0] completed_fence [NUM_QUEUES];
    
    // Event synchronization
    logic [31:0] event_signals;
    logic [31:0] event_waits;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cp_state <= CP_IDLE;
            active_queue <= 2'b00;
            current_cmd <= '0;
            current_opcode <= 8'h00;
            cmd_valid <= 1'b0;
            dispatch_3d_valid <= 1'b0;
            dispatch_compute_valid <= 1'b0;
            dma_request_valid <= 1'b0;
            interrupt_pending <= 1'b0;
            interrupt_vector <= 8'h00;
            event_signals <= 32'h0;
            event_waits <= 32'h0;
            
            for (int i = 0; i < NUM_QUEUES; i++) begin
                write_ptr[i] <= '0;
                read_ptr[i] <= '0;
                fence_ptr[i] <= '0;
                queue_state[i] <= Q_IDLE;
                fence_value[i] <= 32'h0;
                completed_fence[i] <= 32'h0;
                queue_empty[i] <= 1'b1;
                queue_error[i] <= 1'b0;
            end
        end else begin
            // Handle host writes to command buffer
            if (host_write_valid && host_write_ready) begin
                logic [1:0] q_id;
                q_id = host_write_addr[31:30];
                cmd_buffer[q_id][write_ptr[q_id]] <= host_write_data;
            end
            
            // Handle doorbell updates
            if (doorbell_valid) begin
                write_ptr[doorbell_queue_id] <= doorbell_value[$clog2(RING_BUFFER_DEPTH)-1:0];
                queue_empty[doorbell_queue_id] <= 1'b0;
            end
            
            // Command processor state machine
            case (cp_state)
                CP_IDLE: begin
                    cmd_valid <= 1'b0;
                    dispatch_3d_valid <= 1'b0;
                    dispatch_compute_valid <= 1'b0;
                    dma_request_valid <= 1'b0;
                    
                    // Check if any queue has work
                    if (|queue_has_work) begin
                        cp_state <= CP_SELECT_QUEUE;
                    end
                end
                
                CP_SELECT_QUEUE: begin
                    active_queue <= next_queue;
                    queue_state[next_queue] <= Q_FETCH_CMD;
                    cp_state <= CP_FETCH;
                end
                
                CP_FETCH: begin
                    current_cmd <= cmd_buffer[active_queue][read_ptr[active_queue]];
                    queue_state[active_queue] <= Q_DECODE;
                    cp_state <= CP_DECODE;
                end
                
                CP_DECODE: begin
                    current_opcode <= cmd_op;
                    
                    case (cmd_op)
                        OP_NOP: begin
                            cp_state <= CP_UPDATE_PTR;
                        end
                        
                        OP_DRAW, OP_DRAW_INDEXED: begin
                            dispatch_3d_valid <= 1'b1;
                            dispatch_3d_x <= cmd_payload;
                            dispatch_3d_y <= 32'd1;
                            dispatch_3d_z <= 32'd1;
                            cp_state <= CP_EXEC_DRAW;
                        end
                        
                        OP_DISPATCH: begin
                            dispatch_compute_valid <= 1'b1;
                            dispatch_workgroups <= cmd_payload;
                            dispatch_local_size <= cmd_addr[31:0];
                            cp_state <= CP_EXEC_DISPATCH;
                        end
                        
                        OP_DMA_COPY: begin
                            dma_request_valid <= 1'b1;
                            dma_src_addr <= cmd_addr;
                            dma_dst_addr <= {cmd_payload, cmd_len, 8'h0};
                            dma_length <= cmd_len;
                            dma_direction <= 2'b00;
                            cp_state <= CP_EXEC_DMA;
                        end
                        
                        OP_SET_REGISTER: begin
                            cmd_valid <= 1'b1;
                            cmd_opcode <= cmd_op;
                            cmd_address <= cmd_addr;
                            cmd_data <= cmd_payload;
                            cmd_length <= cmd_len;
                            cp_state <= CP_EXEC_REGISTER;
                        end
                        
                        OP_FENCE: begin
                            fence_value[active_queue] <= cmd_payload;
                            fence_ptr[active_queue] <= read_ptr[active_queue];
                            cp_state <= CP_EXEC_FENCE;
                        end
                        
                        OP_WAIT_EVENT: begin
                            event_waits <= cmd_payload;
                            if (|(event_signals & cmd_payload)) begin
                                cp_state <= CP_UPDATE_PTR;
                            end
                            // else stay waiting
                        end
                        
                        OP_SIGNAL_EVENT: begin
                            event_signals <= event_signals | cmd_payload;
                            interrupt_pending <= 1'b1;
                            interrupt_vector <= cmd_op;
                            cp_state <= CP_UPDATE_PTR;
                        end
                        
                        default: begin
                            queue_error[active_queue] <= 1'b1;
                            queue_state[active_queue] <= Q_ERROR;
                            cp_state <= CP_ERROR;
                        end
                    endcase
                end
                
                CP_EXEC_DRAW: begin
                    if (dispatch_3d_ready) begin
                        dispatch_3d_valid <= 1'b0;
                        cp_state <= CP_UPDATE_PTR;
                    end
                end
                
                CP_EXEC_DISPATCH: begin
                    if (dispatch_compute_ready) begin
                        dispatch_compute_valid <= 1'b0;
                        cp_state <= CP_UPDATE_PTR;
                    end
                end
                
                CP_EXEC_DMA: begin
                    if (dma_request_ready) begin
                        dma_request_valid <= 1'b0;
                        cp_state <= CP_UPDATE_PTR;
                    end
                end
                
                CP_EXEC_REGISTER: begin
                    if (cmd_ready) begin
                        cmd_valid <= 1'b0;
                        cp_state <= CP_UPDATE_PTR;
                    end
                end
                
                CP_EXEC_FENCE: begin
                    completed_fence[active_queue] <= fence_value[active_queue];
                    cp_state <= CP_UPDATE_PTR;
                end
                
                CP_UPDATE_PTR: begin
                    read_ptr[active_queue] <= read_ptr[active_queue] + 1'b1;
                    queue_state[active_queue] <= Q_IDLE;
                    
                    if (read_ptr[active_queue] + 1'b1 == write_ptr[active_queue]) begin
                        queue_empty[active_queue] <= 1'b1;
                    end
                    
                    cp_state <= CP_IDLE;
                end
                
                CP_ERROR: begin
                    interrupt_pending <= 1'b1;
                    interrupt_vector <= 8'hFF;
                    // Stay in error until reset
                end
                
                default: cp_state <= CP_IDLE;
            endcase
        end
    end
    
    // Host write ready when not processing
    assign host_write_ready = (cp_state == CP_IDLE);

endmodule
