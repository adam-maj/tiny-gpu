// Clock and Reset Controller - PLL and Clock Domain Management
// Enterprise-grade multi-domain clock generation with DVFS support
// Compatible with: ASIC/FPGA clock infrastructure
// IEEE 1800-2012 SystemVerilog

module clock_reset_controller #(
    parameter NUM_CLOCK_DOMAINS = 8,
    parameter NUM_PLLS = 4,
    parameter REF_CLK_FREQ = 100_000_000,  // 100 MHz reference
    parameter MAX_CORE_FREQ = 2_000_000_000, // 2 GHz max
    parameter MAX_MEM_FREQ = 1_000_000_000   // 1 GHz max
) (
    // Reference Clock and External Reset
    input  logic                    ref_clk,
    input  logic                    ext_rst_n,
    
    // Generated Clocks
    output logic                    core_clk,         // GPU core clock
    output logic                    shader_clk,       // Shader engine clock
    output logic                    memory_clk,       // Memory controller clock
    output logic                    display_clk,      // Display/pixel clock
    output logic                    pcie_clk,         // PCIe interface clock
    output logic                    aux_clk,          // Auxiliary/slow clock
    
    // Clock Enables
    output logic                    core_clk_en,
    output logic                    shader_clk_en,
    output logic                    memory_clk_en,
    output logic                    display_clk_en,
    
    // Reset Outputs (synchronized to each domain)
    output logic                    core_rst_n,
    output logic                    shader_rst_n,
    output logic                    memory_rst_n,
    output logic                    display_rst_n,
    output logic                    pcie_rst_n,
    output logic                    aux_rst_n,
    
    // Global Reset
    output logic                    global_rst_n,
    
    // PLL Configuration
    input  logic [7:0]              pll_mult [NUM_PLLS],
    input  logic [7:0]              pll_div [NUM_PLLS],
    input  logic [3:0]              pll_post_div [NUM_PLLS],
    input  logic [NUM_PLLS-1:0]     pll_enable,
    output logic [NUM_PLLS-1:0]     pll_locked,
    
    // DVFS Control
    input  logic [2:0]              dvfs_state,       // P-state
    input  logic                    dvfs_transition_req,
    output logic                    dvfs_transition_done,
    output logic                    dvfs_transition_busy,
    
    // Clock Gating Control
    input  logic                    cg_core_request,
    input  logic                    cg_shader_request,
    input  logic                    cg_memory_request,
    input  logic                    cg_display_request,
    
    // Power Gating Interface
    output logic [NUM_CLOCK_DOMAINS-1:0] power_gate_ack,
    input  logic [NUM_CLOCK_DOMAINS-1:0] power_gate_req,
    
    // Watchdog Timer
    input  logic                    wdt_enable,
    input  logic [31:0]             wdt_timeout,
    output logic                    wdt_expired,
    input  logic                    wdt_kick,
    
    // Debug/Status
    output logic [31:0]             core_freq_hz,
    output logic [31:0]             memory_freq_hz,
    output logic [NUM_PLLS-1:0]     pll_status,
    output logic                    clock_stable
);

    // DVFS P-state frequency table (in MHz)
    localparam logic [15:0] PSTATE_CORE_FREQ [8] = '{
        16'd300,   // P7 - Idle
        16'd600,   // P6 - Light load
        16'd900,   // P5 
        16'd1200,  // P4 - Balanced
        16'd1500,  // P3
        16'd1800,  // P2 - Performance
        16'd2000,  // P1 - High performance
        16'd2100   // P0 - Boost
    };
    
    localparam logic [15:0] PSTATE_MEM_FREQ [8] = '{
        16'd200,   // P7
        16'd400,   // P6
        16'd600,   // P5
        16'd800,   // P4
        16'd900,   // P3
        16'd950,   // P2
        16'd1000,  // P1
        16'd1050   // P0
    };
    
    // PLL state machine
    typedef enum logic [2:0] {
        PLL_OFF,
        PLL_POWERUP,
        PLL_LOCK_WAIT,
        PLL_LOCKED,
        PLL_FREQ_CHANGE,
        PLL_ERROR
    } pll_state_t;
    
    pll_state_t pll_fsm [NUM_PLLS];
    
    // Lock detection counters
    logic [15:0] lock_counter [NUM_PLLS];
    localparam LOCK_CYCLES = 16'd1000;
    
    // Internal clocks from PLLs
    logic pll_clk_out [NUM_PLLS];
    
    // Reset synchronizers
    logic [2:0] rst_sync_core;
    logic [2:0] rst_sync_shader;
    logic [2:0] rst_sync_memory;
    logic [2:0] rst_sync_display;
    logic [2:0] rst_sync_pcie;
    logic [2:0] rst_sync_aux;
    
    // Clock dividers
    logic [7:0] core_div_counter;
    logic [7:0] shader_div_counter;
    logic [7:0] memory_div_counter;
    logic [7:0] display_div_counter;
    
    // DVFS transition state machine
    typedef enum logic [2:0] {
        DVFS_IDLE,
        DVFS_GATE_CLOCKS,
        DVFS_CHANGE_FREQ,
        DVFS_WAIT_LOCK,
        DVFS_UNGATE_CLOCKS,
        DVFS_COMPLETE
    } dvfs_state_t;
    
    dvfs_state_t dvfs_fsm;
    logic [2:0] target_pstate;
    
    // Watchdog counter
    logic [31:0] wdt_counter;
    
    // Glitch-free clock multiplexer (for simulation - real design uses dedicated cells)
    logic core_clk_mux;
    logic memory_clk_mux;
    
    // PLL model (simplified behavioral)
    generate
        for (genvar i = 0; i < NUM_PLLS; i++) begin : gen_plls
            always_ff @(posedge ref_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    pll_fsm[i] <= PLL_OFF;
                    pll_locked[i] <= 1'b0;
                    lock_counter[i] <= 16'd0;
                    pll_clk_out[i] <= 1'b0;
                end else begin
                    case (pll_fsm[i])
                        PLL_OFF: begin
                            pll_locked[i] <= 1'b0;
                            if (pll_enable[i]) begin
                                pll_fsm[i] <= PLL_POWERUP;
                            end
                        end
                        
                        PLL_POWERUP: begin
                            lock_counter[i] <= 16'd0;
                            pll_fsm[i] <= PLL_LOCK_WAIT;
                        end
                        
                        PLL_LOCK_WAIT: begin
                            lock_counter[i] <= lock_counter[i] + 1'b1;
                            if (lock_counter[i] >= LOCK_CYCLES) begin
                                pll_fsm[i] <= PLL_LOCKED;
                                pll_locked[i] <= 1'b1;
                            end
                        end
                        
                        PLL_LOCKED: begin
                            pll_locked[i] <= 1'b1;
                            if (!pll_enable[i]) begin
                                pll_fsm[i] <= PLL_OFF;
                            end
                        end
                        
                        PLL_FREQ_CHANGE: begin
                            pll_locked[i] <= 1'b0;
                            lock_counter[i] <= 16'd0;
                            pll_fsm[i] <= PLL_LOCK_WAIT;
                        end
                        
                        PLL_ERROR: begin
                            pll_locked[i] <= 1'b0;
                        end
                        
                        default: pll_fsm[i] <= PLL_OFF;
                    endcase
                end
            end
            
            // Simple clock divider for PLL output (behavioral model)
            always_ff @(posedge ref_clk or negedge ext_rst_n) begin
                if (!ext_rst_n) begin
                    pll_clk_out[i] <= 1'b0;
                end else if (pll_locked[i]) begin
                    pll_clk_out[i] <= ~pll_clk_out[i];
                end
            end
        end
    endgenerate
    
    // Clock assignment (simplified - real design uses clock muxes)
    assign core_clk = pll_clk_out[0];
    assign shader_clk = pll_clk_out[0];  // Same as core or separate
    assign memory_clk = pll_clk_out[1];
    assign display_clk = pll_clk_out[2];
    assign pcie_clk = ref_clk;           // PCIe uses reference
    assign aux_clk = ref_clk;            // Aux uses reference divided
    
    // Clock enable logic with hysteresis
    always_ff @(posedge ref_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            core_clk_en <= 1'b1;
            shader_clk_en <= 1'b1;
            memory_clk_en <= 1'b1;
            display_clk_en <= 1'b1;
        end else begin
            core_clk_en <= !cg_core_request && !power_gate_req[0];
            shader_clk_en <= !cg_shader_request && !power_gate_req[1];
            memory_clk_en <= !cg_memory_request && !power_gate_req[2];
            display_clk_en <= !cg_display_request && !power_gate_req[3];
        end
    end
    
    // Reset synchronizers
    always_ff @(posedge core_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_core <= 3'b000;
        end else begin
            rst_sync_core <= {rst_sync_core[1:0], 1'b1};
        end
    end
    assign core_rst_n = rst_sync_core[2] && pll_locked[0];
    
    always_ff @(posedge shader_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_shader <= 3'b000;
        end else begin
            rst_sync_shader <= {rst_sync_shader[1:0], 1'b1};
        end
    end
    assign shader_rst_n = rst_sync_shader[2] && pll_locked[0];
    
    always_ff @(posedge memory_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_memory <= 3'b000;
        end else begin
            rst_sync_memory <= {rst_sync_memory[1:0], 1'b1};
        end
    end
    assign memory_rst_n = rst_sync_memory[2] && pll_locked[1];
    
    always_ff @(posedge display_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_display <= 3'b000;
        end else begin
            rst_sync_display <= {rst_sync_display[1:0], 1'b1};
        end
    end
    assign display_rst_n = rst_sync_display[2] && pll_locked[2];
    
    always_ff @(posedge pcie_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_pcie <= 3'b000;
        end else begin
            rst_sync_pcie <= {rst_sync_pcie[1:0], 1'b1};
        end
    end
    assign pcie_rst_n = rst_sync_pcie[2];
    
    always_ff @(posedge aux_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_aux <= 3'b000;
        end else begin
            rst_sync_aux <= {rst_sync_aux[1:0], 1'b1};
        end
    end
    assign aux_rst_n = rst_sync_aux[2];
    
    // Global reset
    assign global_rst_n = ext_rst_n && &pll_locked[1:0];
    
    // DVFS state machine
    always_ff @(posedge ref_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            dvfs_fsm <= DVFS_IDLE;
            dvfs_transition_done <= 1'b0;
            dvfs_transition_busy <= 1'b0;
            target_pstate <= 3'd4;  // Default to P4
        end else begin
            case (dvfs_fsm)
                DVFS_IDLE: begin
                    dvfs_transition_done <= 1'b0;
                    dvfs_transition_busy <= 1'b0;
                    
                    if (dvfs_transition_req && dvfs_state != target_pstate) begin
                        target_pstate <= dvfs_state;
                        dvfs_transition_busy <= 1'b1;
                        dvfs_fsm <= DVFS_GATE_CLOCKS;
                    end
                end
                
                DVFS_GATE_CLOCKS: begin
                    // Wait for clock gating to take effect
                    dvfs_fsm <= DVFS_CHANGE_FREQ;
                end
                
                DVFS_CHANGE_FREQ: begin
                    // Update PLL multipliers (would trigger PLL relock)
                    dvfs_fsm <= DVFS_WAIT_LOCK;
                end
                
                DVFS_WAIT_LOCK: begin
                    if (&pll_locked[1:0]) begin
                        dvfs_fsm <= DVFS_UNGATE_CLOCKS;
                    end
                end
                
                DVFS_UNGATE_CLOCKS: begin
                    dvfs_fsm <= DVFS_COMPLETE;
                end
                
                DVFS_COMPLETE: begin
                    dvfs_transition_done <= 1'b1;
                    dvfs_transition_busy <= 1'b0;
                    dvfs_fsm <= DVFS_IDLE;
                end
                
                default: dvfs_fsm <= DVFS_IDLE;
            endcase
        end
    end
    
    // Frequency calculation (for status reporting)
    always_comb begin
        core_freq_hz = (REF_CLK_FREQ * pll_mult[0]) / (pll_div[0] * pll_post_div[0]);
        memory_freq_hz = (REF_CLK_FREQ * pll_mult[1]) / (pll_div[1] * pll_post_div[1]);
    end
    
    // Clock stability indicator
    assign clock_stable = &pll_locked && !dvfs_transition_busy;
    assign pll_status = pll_locked;
    
    // Power gate acknowledgment
    always_ff @(posedge ref_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            power_gate_ack <= '0;
        end else begin
            for (int i = 0; i < NUM_CLOCK_DOMAINS; i++) begin
                power_gate_ack[i] <= power_gate_req[i];
            end
        end
    end
    
    // Watchdog timer
    always_ff @(posedge aux_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            wdt_counter <= 32'd0;
            wdt_expired <= 1'b0;
        end else if (wdt_enable) begin
            if (wdt_kick) begin
                wdt_counter <= 32'd0;
                wdt_expired <= 1'b0;
            end else if (wdt_counter >= wdt_timeout) begin
                wdt_expired <= 1'b1;
            end else begin
                wdt_counter <= wdt_counter + 1'b1;
            end
        end else begin
            wdt_counter <= 32'd0;
            wdt_expired <= 1'b0;
        end
    end

endmodule
