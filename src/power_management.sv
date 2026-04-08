`default_nettype none
`timescale 1ns/1ns

/**
 * Power Management Unit
 * Enterprise-grade power/thermal management for GPU
 * Features:
 * - Dynamic Voltage and Frequency Scaling (DVFS)
 * - Multiple power domains (compute, memory, display)
 * - Thermal throttling with hysteresis
 * - Power gating for idle units
 * - Performance state transitions
 * - Power budget management
 */
module power_management #(
    parameter NUM_DOMAINS = 4,
    parameter NUM_PSTATES = 8,
    parameter THERMAL_BITS = 10
) (
    input wire clk,
    input wire reset,
    
    // External control
    input wire [2:0] power_cap_watts,     // Power cap level
    input wire force_low_power,
    input wire thermal_alert,
    
    // Thermal sensor inputs
    input wire [THERMAL_BITS-1:0] gpu_temp,
    input wire [THERMAL_BITS-1:0] mem_temp,
    input wire [THERMAL_BITS-1:0] vrm_temp,
    
    // Thermal thresholds
    input wire [THERMAL_BITS-1:0] temp_target,
    input wire [THERMAL_BITS-1:0] temp_throttle,
    input wire [THERMAL_BITS-1:0] temp_shutdown,
    
    // Performance state control
    input wire [2:0] requested_pstate,
    output reg [2:0] current_pstate,
    output reg pstate_transitioning,
    
    // Voltage regulator control
    output reg [7:0] vdd_core,            // Core voltage (0.5V to 1.3V)
    output reg [7:0] vdd_mem,             // Memory voltage
    output reg [7:0] vdd_io,              // I/O voltage
    
    // Clock control outputs
    output reg [3:0] core_clock_div,      // Clock divider for core
    output reg [3:0] mem_clock_div,       // Clock divider for memory
    output reg core_clock_gate,           // Clock gating enable
    output reg mem_clock_gate,
    
    // Power domain control
    output reg [NUM_DOMAINS-1:0] domain_power_gate,
    output reg [NUM_DOMAINS-1:0] domain_clock_gate,
    output reg [NUM_DOMAINS-1:0] domain_voltage_reduce,
    
    // Activity monitors (from GPU units)
    input wire [NUM_DOMAINS-1:0] domain_active,
    input wire [7:0] compute_utilization,
    input wire [7:0] memory_bandwidth_util,
    input wire [7:0] display_active,
    
    // Power monitoring
    output reg [15:0] power_consumption,   // Estimated power in mW
    output reg [15:0] power_budget_remain,
    output reg power_limit_reached,
    
    // Status outputs
    output reg thermal_throttling,
    output reg emergency_shutdown,
    output reg [2:0] thermal_zone,         // 0=cold, 7=critical
    output reg [7:0] fan_speed_req         // Fan speed request 0-255
);

    // P-State table (voltage, core_div, mem_div)
    // P0 = max performance, P7 = min power
    reg [7:0] pstate_vcore [NUM_PSTATES-1:0];
    reg [3:0] pstate_core_div [NUM_PSTATES-1:0];
    reg [3:0] pstate_mem_div [NUM_PSTATES-1:0];
    reg [15:0] pstate_power [NUM_PSTATES-1:0];
    
    // Initialize P-state table
    initial begin
        // P0: Full performance
        pstate_vcore[0] = 8'd200;    // 1.0V
        pstate_core_div[0] = 4'd1;
        pstate_mem_div[0] = 4'd1;
        pstate_power[0] = 16'd350;   // 350W
        
        // P1: High performance
        pstate_vcore[1] = 8'd190;
        pstate_core_div[1] = 4'd1;
        pstate_mem_div[1] = 4'd1;
        pstate_power[1] = 16'd280;
        
        // P2: Balanced
        pstate_vcore[2] = 8'd170;
        pstate_core_div[2] = 4'd2;
        pstate_mem_div[2] = 4'd1;
        pstate_power[2] = 16'd200;
        
        // P3: Efficient
        pstate_vcore[3] = 8'd150;
        pstate_core_div[3] = 4'd2;
        pstate_mem_div[3] = 4'd2;
        pstate_power[3] = 16'd150;
        
        // P4: Power save
        pstate_vcore[4] = 8'd130;
        pstate_core_div[4] = 4'd4;
        pstate_mem_div[4] = 4'd2;
        pstate_power[4] = 16'd100;
        
        // P5: Low power
        pstate_vcore[5] = 8'd110;
        pstate_core_div[5] = 4'd4;
        pstate_mem_div[5] = 4'd4;
        pstate_power[5] = 16'd60;
        
        // P6: Minimum
        pstate_vcore[6] = 8'd100;
        pstate_core_div[6] = 4'd8;
        pstate_mem_div[6] = 4'd4;
        pstate_power[6] = 16'd30;
        
        // P7: Idle
        pstate_vcore[7] = 8'd80;
        pstate_core_div[7] = 4'd8;
        pstate_mem_div[7] = 4'd8;
        pstate_power[7] = 16'd10;
    end
    
    // Idle detection counters
    reg [15:0] idle_counter [NUM_DOMAINS-1:0];
    localparam IDLE_THRESHOLD = 16'd1000;
    localparam POWER_GATE_THRESHOLD = 16'd5000;
    
    // Thermal hysteresis
    reg thermal_throttle_active;
    reg [THERMAL_BITS-1:0] throttle_hyst_low;
    reg [THERMAL_BITS-1:0] throttle_hyst_high;
    
    // P-state transition state machine
    localparam PS_IDLE = 2'd0;
    localparam PS_RAMP_DOWN = 2'd1;
    localparam PS_STABLE = 2'd2;
    localparam PS_RAMP_UP = 2'd3;
    
    reg [1:0] pstate_state;
    reg [2:0] target_pstate;
    reg [7:0] transition_counter;
    
    // Maximum temp calculation
    wire [THERMAL_BITS-1:0] max_temp;
    assign max_temp = (gpu_temp > mem_temp) ? 
                      ((gpu_temp > vrm_temp) ? gpu_temp : vrm_temp) :
                      ((mem_temp > vrm_temp) ? mem_temp : vrm_temp);
    
    // Thermal zone calculation
    always @(*) begin
        if (max_temp < temp_target - 30)
            thermal_zone = 3'd0;  // Cold
        else if (max_temp < temp_target - 10)
            thermal_zone = 3'd1;  // Cool
        else if (max_temp < temp_target)
            thermal_zone = 3'd2;  // Normal
        else if (max_temp < temp_throttle - 10)
            thermal_zone = 3'd3;  // Warm
        else if (max_temp < temp_throttle)
            thermal_zone = 3'd4;  // Hot
        else if (max_temp < temp_shutdown - 10)
            thermal_zone = 3'd5;  // Throttling
        else if (max_temp < temp_shutdown)
            thermal_zone = 3'd6;  // Critical
        else
            thermal_zone = 3'd7;  // Emergency
    end
    
    // Fan speed control (proportional to temperature)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fan_speed_req <= 8'd50;  // Default 20% fan
        end else begin
            if (max_temp < temp_target - 20)
                fan_speed_req <= 8'd50;
            else if (max_temp < temp_target)
                fan_speed_req <= 8'd100;
            else if (max_temp < temp_throttle)
                fan_speed_req <= 8'd180;
            else
                fan_speed_req <= 8'd255;  // Maximum
        end
    end
    
    // Idle detection and power gating
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_DOMAINS; i = i + 1) begin
                idle_counter[i] <= 0;
                domain_clock_gate[i] <= 0;
                domain_power_gate[i] <= 0;
            end
        end else begin
            for (i = 0; i < NUM_DOMAINS; i = i + 1) begin
                if (domain_active[i]) begin
                    idle_counter[i] <= 0;
                    domain_clock_gate[i] <= 0;
                    domain_power_gate[i] <= 0;
                end else begin
                    if (idle_counter[i] < 16'hFFFF)
                        idle_counter[i] <= idle_counter[i] + 1;
                    
                    // Clock gate after idle threshold
                    if (idle_counter[i] >= IDLE_THRESHOLD)
                        domain_clock_gate[i] <= 1;
                    
                    // Power gate after longer idle
                    if (idle_counter[i] >= POWER_GATE_THRESHOLD)
                        domain_power_gate[i] <= 1;
                end
            end
        end
    end
    
    // Thermal throttling with hysteresis
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            thermal_throttle_active <= 0;
            thermal_throttling <= 0;
            emergency_shutdown <= 0;
            throttle_hyst_low <= 0;
            throttle_hyst_high <= 0;
        end else begin
            throttle_hyst_low <= temp_throttle - 5;
            throttle_hyst_high <= temp_throttle;
            
            // Hysteresis for throttling
            if (!thermal_throttle_active && max_temp >= throttle_hyst_high) begin
                thermal_throttle_active <= 1;
                thermal_throttling <= 1;
            end else if (thermal_throttle_active && max_temp < throttle_hyst_low) begin
                thermal_throttle_active <= 0;
                thermal_throttling <= 0;
            end
            
            // Emergency shutdown check
            if (max_temp >= temp_shutdown || thermal_alert) begin
                emergency_shutdown <= 1;
            end
        end
    end
    
    // P-state transition management
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_pstate <= 3'd4;  // Start at power save
            target_pstate <= 3'd4;
            pstate_state <= PS_IDLE;
            pstate_transitioning <= 0;
            transition_counter <= 0;
            vdd_core <= pstate_vcore[4];
            core_clock_div <= pstate_core_div[4];
            mem_clock_div <= pstate_mem_div[4];
        end else begin
            // Determine target P-state
            if (emergency_shutdown) begin
                target_pstate <= 3'd7;
            end else if (force_low_power) begin
                target_pstate <= 3'd6;
            end else if (thermal_throttling) begin
                target_pstate <= (current_pstate < 3'd5) ? current_pstate + 1 : 3'd5;
            end else begin
                target_pstate <= requested_pstate;
            end
            
            // P-state transition state machine
            case (pstate_state)
                PS_IDLE: begin
                    if (current_pstate != target_pstate) begin
                        pstate_transitioning <= 1;
                        if (target_pstate > current_pstate) begin
                            // Going to lower performance = reduce voltage first
                            pstate_state <= PS_RAMP_DOWN;
                        end else begin
                            // Going to higher performance = increase voltage first
                            pstate_state <= PS_RAMP_UP;
                        end
                        transition_counter <= 0;
                    end else begin
                        pstate_transitioning <= 0;
                    end
                end
                
                PS_RAMP_DOWN: begin
                    transition_counter <= transition_counter + 1;
                    // Gradually reduce voltage
                    if (vdd_core > pstate_vcore[target_pstate]) begin
                        vdd_core <= vdd_core - 1;
                    end
                    if (transition_counter >= 100) begin
                        core_clock_div <= pstate_core_div[target_pstate];
                        mem_clock_div <= pstate_mem_div[target_pstate];
                        pstate_state <= PS_STABLE;
                    end
                end
                
                PS_RAMP_UP: begin
                    transition_counter <= transition_counter + 1;
                    // Increase voltage first
                    if (vdd_core < pstate_vcore[target_pstate]) begin
                        vdd_core <= vdd_core + 1;
                    end
                    if (transition_counter >= 100) begin
                        core_clock_div <= pstate_core_div[target_pstate];
                        mem_clock_div <= pstate_mem_div[target_pstate];
                        pstate_state <= PS_STABLE;
                    end
                end
                
                PS_STABLE: begin
                    current_pstate <= target_pstate;
                    pstate_state <= PS_IDLE;
                end
            endcase
        end
    end
    
    // Power consumption estimation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            power_consumption <= 0;
            power_budget_remain <= 16'd350;
            power_limit_reached <= 0;
        end else begin
            // Simplified power model: base + dynamic
            power_consumption <= pstate_power[current_pstate] * 
                                 (8'd50 + compute_utilization[7:1] + memory_bandwidth_util[7:2]) / 100;
            
            // Power budget (example: 350W TDP)
            if (power_consumption >= pstate_power[0])
                power_limit_reached <= 1;
            else
                power_limit_reached <= 0;
                
            power_budget_remain <= pstate_power[0] - power_consumption;
        end
    end
    
    // Clock gating outputs
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            core_clock_gate <= 0;
            mem_clock_gate <= 0;
            vdd_mem <= 8'd150;
            vdd_io <= 8'd100;
        end else begin
            core_clock_gate <= (compute_utilization < 8'd10);
            mem_clock_gate <= (memory_bandwidth_util < 8'd5);
            
            // Memory voltage follows core with offset
            vdd_mem <= vdd_core - 8'd30;
            vdd_io <= 8'd100;  // Fixed I/O voltage
        end
    end
    
    // Domain voltage reduction
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            domain_voltage_reduce <= 0;
        end else begin
            for (i = 0; i < NUM_DOMAINS; i = i + 1) begin
                domain_voltage_reduce[i] <= domain_clock_gate[i] && (current_pstate >= 3'd4);
            end
        end
    end

endmodule
