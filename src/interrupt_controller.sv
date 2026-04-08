// Interrupt Controller - GPU Interrupt Management
// Enterprise-grade interrupt aggregation and routing
// Compatible with: MSI/MSI-X, ARM GIC, x86 APIC patterns
// IEEE 1800-2012 SystemVerilog

module interrupt_controller #(
    parameter NUM_SOURCES = 64,
    parameter NUM_VECTORS = 32,
    parameter NUM_PRIORITY_LEVELS = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Interrupt Sources
    input  logic [NUM_SOURCES-1:0]  interrupt_sources,
    
    // Interrupt Acknowledge from CPU/Host
    input  logic                    interrupt_ack,
    input  logic [5:0]              interrupt_ack_id,
    
    // Interrupt Output (to PCIe MSI-X or internal CPU)
    output logic                    interrupt_pending,
    output logic [5:0]              interrupt_vector,
    output logic [3:0]              interrupt_priority,
    
    // Per-Source Enable
    input  logic [NUM_SOURCES-1:0]  interrupt_enable,
    
    // Per-Source Priority
    input  logic [3:0]              interrupt_priority_cfg [NUM_SOURCES],
    
    // Source to Vector Mapping
    input  logic [5:0]              interrupt_vector_map [NUM_SOURCES],
    
    // Edge vs Level Trigger Configuration
    input  logic [NUM_SOURCES-1:0]  interrupt_edge_trigger,
    
    // Interrupt Coalescing Configuration
    input  logic                    coalesce_enable,
    input  logic [15:0]             coalesce_timeout,
    input  logic [7:0]              coalesce_count_threshold,
    
    // Register Interface
    input  logic                    reg_write,
    input  logic [7:0]              reg_addr,
    input  logic [31:0]             reg_wdata,
    output logic [31:0]             reg_rdata,
    
    // Status Registers
    output logic [NUM_SOURCES-1:0]  interrupt_status,
    output logic [NUM_SOURCES-1:0]  interrupt_pending_status,
    output logic [31:0]             interrupt_count [NUM_VECTORS],
    
    // Debug
    output logic [NUM_SOURCES-1:0]  interrupt_raw,
    output logic [5:0]              last_serviced_vector,
    output logic [31:0]             total_interrupts
);

    // Internal signals
    logic [NUM_SOURCES-1:0] interrupt_sources_d;
    logic [NUM_SOURCES-1:0] interrupt_edge_detect;
    logic [NUM_SOURCES-1:0] interrupt_active;
    logic [NUM_SOURCES-1:0] interrupt_masked;
    
    // Priority arbitration
    logic [5:0] highest_priority_source;
    logic [3:0] highest_priority;
    logic any_pending;
    
    // Coalescing state
    logic [15:0] coalesce_timer;
    logic [7:0] coalesce_counter;
    logic coalesce_fire;
    
    // Per-vector pending and in-service bits
    logic [NUM_VECTORS-1:0] vector_pending;
    logic [NUM_VECTORS-1:0] vector_in_service;
    
    // Edge detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_sources_d <= '0;
        end else begin
            interrupt_sources_d <= interrupt_sources;
        end
    end
    
    always_comb begin
        for (int i = 0; i < NUM_SOURCES; i++) begin
            // Rising edge detection for edge-triggered
            interrupt_edge_detect[i] = interrupt_edge_trigger[i] ? 
                                       (interrupt_sources[i] & ~interrupt_sources_d[i]) :
                                       interrupt_sources[i];
        end
    end
    
    // Apply mask and determine active interrupts
    assign interrupt_masked = interrupt_edge_detect & interrupt_enable;
    assign interrupt_raw = interrupt_sources;
    
    // Latch edge-triggered interrupts
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_status <= '0;
        end else begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                if (interrupt_masked[i]) begin
                    interrupt_status[i] <= 1'b1;
                end else if (interrupt_ack && interrupt_vector_map[i] == interrupt_ack_id) begin
                    // Clear on acknowledge
                    if (interrupt_edge_trigger[i]) begin
                        interrupt_status[i] <= 1'b0;
                    end
                end
            end
        end
    end
    
    // Priority arbiter - find highest priority pending interrupt
    always_comb begin
        highest_priority_source = 6'd0;
        highest_priority = 4'd0;
        any_pending = 1'b0;
        
        for (int i = 0; i < NUM_SOURCES; i++) begin
            if (interrupt_status[i] && interrupt_enable[i]) begin
                if (!any_pending || interrupt_priority_cfg[i] > highest_priority) begin
                    highest_priority = interrupt_priority_cfg[i];
                    highest_priority_source = i[5:0];
                    any_pending = 1'b1;
                end
            end
        end
    end
    
    // Interrupt coalescing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coalesce_timer <= 16'd0;
            coalesce_counter <= 8'd0;
            coalesce_fire <= 1'b0;
        end else if (coalesce_enable) begin
            if (any_pending) begin
                coalesce_counter <= coalesce_counter + 1'b1;
                coalesce_timer <= coalesce_timer + 1'b1;
            end
            
            // Fire if threshold reached or timeout
            if (coalesce_counter >= coalesce_count_threshold || 
                coalesce_timer >= coalesce_timeout) begin
                coalesce_fire <= 1'b1;
                coalesce_timer <= 16'd0;
                coalesce_counter <= 8'd0;
            end else begin
                coalesce_fire <= 1'b0;
            end
            
            // Reset on acknowledge
            if (interrupt_ack) begin
                coalesce_fire <= 1'b0;
            end
        end else begin
            coalesce_fire <= any_pending;
            coalesce_timer <= 16'd0;
            coalesce_counter <= 8'd0;
        end
    end
    
    // Output generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interrupt_pending <= 1'b0;
            interrupt_vector <= 6'd0;
            interrupt_priority <= 4'd0;
            last_serviced_vector <= 6'd0;
            total_interrupts <= 32'd0;
        end else begin
            if (coalesce_enable) begin
                interrupt_pending <= coalesce_fire;
            end else begin
                interrupt_pending <= any_pending;
            end
            
            if (any_pending) begin
                interrupt_vector <= interrupt_vector_map[highest_priority_source];
                interrupt_priority <= highest_priority;
            end
            
            if (interrupt_ack) begin
                last_serviced_vector <= interrupt_ack_id;
                total_interrupts <= total_interrupts + 1'b1;
            end
        end
    end
    
    // Per-vector interrupt counting
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_VECTORS; i++) begin
                interrupt_count[i] <= 32'd0;
            end
        end else begin
            if (interrupt_ack && interrupt_ack_id < NUM_VECTORS) begin
                interrupt_count[interrupt_ack_id] <= interrupt_count[interrupt_ack_id] + 1'b1;
            end
        end
    end
    
    // Pending status
    assign interrupt_pending_status = interrupt_status & interrupt_enable;
    
    // Register interface
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rdata <= 32'd0;
        end else begin
            case (reg_addr)
                8'h00: reg_rdata <= interrupt_status[31:0];
                8'h04: reg_rdata <= interrupt_status[63:32];
                8'h08: reg_rdata <= interrupt_enable[31:0];
                8'h0C: reg_rdata <= interrupt_enable[63:32];
                8'h10: reg_rdata <= interrupt_pending_status[31:0];
                8'h14: reg_rdata <= interrupt_pending_status[63:32];
                8'h18: reg_rdata <= {26'd0, interrupt_vector};
                8'h1C: reg_rdata <= {28'd0, interrupt_priority};
                8'h20: reg_rdata <= total_interrupts;
                8'h24: reg_rdata <= {26'd0, last_serviced_vector};
                8'h28: reg_rdata <= {16'd0, coalesce_timeout};
                8'h2C: reg_rdata <= {24'd0, coalesce_count_threshold};
                default: reg_rdata <= 32'd0;
            endcase
        end
    end
    
    // Register writes handled externally via interrupt_enable, etc.

endmodule
