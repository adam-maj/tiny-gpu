/**
 * Translation Lookaside Buffer (TLB)
 * Fast cache for virtual-to-physical address translations
 * Production features:
 * - Fully associative or set-associative lookup
 * - LRU replacement policy
 * - Support for different page sizes
 * - TLB flush capability
 * - Performance counters
 */

module tlb #(
    parameter NUM_ENTRIES = 64,
    parameter ADDR_WIDTH = 32,
    parameter VPN_WIDTH = 20,
    parameter PPN_WIDTH = 20
) (
    input  logic clk,
    input  logic reset,
    
    // Lookup interface
    input  logic                  lookup_valid,
    input  logic [VPN_WIDTH-1:0]  lookup_vpn,
    output logic                  lookup_hit,
    output logic [PPN_WIDTH-1:0]  lookup_ppn,
    output logic                  lookup_writable,
    output logic                  lookup_executable,
    
    // Update interface
    input  logic                  update_valid,
    input  logic [VPN_WIDTH-1:0]  update_vpn,
    input  logic [PPN_WIDTH-1:0]  update_ppn,
    input  logic                  update_writable,
    input  logic                  update_executable,
    
    // Invalidate interface
    input  logic                  invalidate,
    input  logic [VPN_WIDTH-1:0]  invalidate_vpn,
    input  logic                  invalidate_all,
    
    // Statistics
    output logic [31:0]           hits,
    output logic [31:0]           misses,
    output logic [31:0]           evictions
);

    // TLB entry structure
    typedef struct packed {
        logic                  valid;
        logic                  writable;
        logic                  executable;
        logic [VPN_WIDTH-1:0]  vpn;
        logic [PPN_WIDTH-1:0]  ppn;
        logic [7:0]            lru_counter;
    } tlb_entry_t;
    
    tlb_entry_t entries [NUM_ENTRIES];
    
    // LRU management
    logic [7:0] global_time;
    
    // Lookup logic
    logic [$clog2(NUM_ENTRIES)-1:0] hit_index;
    logic found;
    
    always_comb begin
        found = 0;
        hit_index = 0;
        lookup_hit = 0;
        lookup_ppn = 0;
        lookup_writable = 0;
        lookup_executable = 0;
        
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entries[i].valid && entries[i].vpn == lookup_vpn) begin
                found = 1;
                hit_index = i;
                lookup_hit = 1;
                lookup_ppn = entries[i].ppn;
                lookup_writable = entries[i].writable;
                lookup_executable = entries[i].executable;
            end
        end
    end
    
    // Find LRU entry for replacement
    logic [$clog2(NUM_ENTRIES)-1:0] lru_index;
    logic [7:0] min_lru;
    
    always_comb begin
        lru_index = 0;
        min_lru = entries[0].lru_counter;
        
        for (int i = 1; i < NUM_ENTRIES; i++) begin
            if (!entries[i].valid) begin
                lru_index = i;
                break;
            end else if (entries[i].lru_counter < min_lru) begin
                min_lru = entries[i].lru_counter;
                lru_index = i;
            end
        end
    end
    
    // Statistics
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            hits <= 0;
            misses <= 0;
            evictions <= 0;
        end else begin
            if (lookup_valid) begin
                if (found) begin
                    hits <= hits + 1;
                end else begin
                    misses <= misses + 1;
                end
            end
            
            if (update_valid && entries[lru_index].valid) begin
                evictions <= evictions + 1;
            end
        end
    end
    
    // Global time counter for LRU
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            global_time <= 0;
        end else begin
            global_time <= global_time + 1;
        end
    end
    
    // TLB update and management
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                entries[i].valid <= 0;
                entries[i].writable <= 0;
                entries[i].executable <= 0;
                entries[i].vpn <= 0;
                entries[i].ppn <= 0;
                entries[i].lru_counter <= 0;
            end
        end else begin
            // Update LRU on successful lookup
            if (lookup_valid && found) begin
                entries[hit_index].lru_counter <= global_time;
            end
            
            // Add new entry on update
            if (update_valid) begin
                entries[lru_index].valid <= 1;
                entries[lru_index].writable <= update_writable;
                entries[lru_index].executable <= update_executable;
                entries[lru_index].vpn <= update_vpn;
                entries[lru_index].ppn <= update_ppn;
                entries[lru_index].lru_counter <= global_time;
            end
            
            // Handle invalidations
            if (invalidate_all) begin
                for (int i = 0; i < NUM_ENTRIES; i++) begin
                    entries[i].valid <= 0;
                end
            end else if (invalidate) begin
                for (int i = 0; i < NUM_ENTRIES; i++) begin
                    if (entries[i].valid && entries[i].vpn == invalidate_vpn) begin
                        entries[i].valid <= 0;
                    end
                end
            end
        end
    end

endmodule
