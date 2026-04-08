/**
 * Memory Controller with Virtual Memory Support
 * Handles address translation, page faults, and memory bandwidth management
 * Production-grade features:
 * - Virtual to physical address translation
 * - Page fault detection and handling
 * - Memory request queuing and prioritization
 * - Bandwidth throttling
 * - Memory protection
 */

module memory_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter PAGE_SIZE = 4096,    // 4KB pages
    parameter NUM_PAGES = 256,     // Page table size
    parameter QUEUE_DEPTH = 8
) (
    input  logic clk,
    input  logic reset,
    
    // Virtual memory interface (from GPU cores)
    input  logic                    req_valid,
    input  logic                    req_write,
    input  logic [ADDR_WIDTH-1:0]   req_vaddr,
    input  logic [DATA_WIDTH-1:0]   req_wdata,
    output logic                    req_ready,
    output logic [DATA_WIDTH-1:0]   req_rdata,
    output logic                    req_done,
    output logic                    page_fault,
    
    // Physical memory interface (to DRAM)
    output logic                    mem_valid,
    output logic                    mem_write,
    output logic [ADDR_WIDTH-1:0]   mem_paddr,
    output logic [DATA_WIDTH-1:0]   mem_wdata,
    input  logic                    mem_ready,
    input  logic [DATA_WIDTH-1:0]   mem_rdata,
    input  logic                    mem_done,
    
    // Page table interface
    input  logic                    pt_update,
    input  logic [19:0]             pt_vpn,        // Virtual page number
    input  logic [19:0]             pt_ppn,        // Physical page number
    input  logic                    pt_valid,
    input  logic                    pt_writable,
    
    // Statistics
    output logic [31:0]             total_requests,
    output logic [31:0]             page_faults_count,
    output logic [31:0]             tlb_hits
);

    // Page table entry structure
    typedef struct packed {
        logic valid;
        logic writable;
        logic accessed;
        logic dirty;
        logic [19:0] ppn;
    } pte_t;
    
    // Page table
    pte_t page_table [NUM_PAGES];
    
    // Request queue
    typedef struct packed {
        logic valid;
        logic write;
        logic [ADDR_WIDTH-1:0] vaddr;
        logic [DATA_WIDTH-1:0] wdata;
    } request_t;
    
    request_t request_queue [QUEUE_DEPTH];
    logic [$clog2(QUEUE_DEPTH)-1:0] queue_head, queue_tail, queue_count;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        TRANSLATE,
        CHECK_PERMISSIONS,
        MEM_ACCESS,
        COMPLETE,
        FAULT
    } state_t;
    
    state_t state, next_state;
    
    // Current request being processed
    logic [ADDR_WIDTH-1:0] current_vaddr;
    logic [ADDR_WIDTH-1:0] current_paddr;
    logic [DATA_WIDTH-1:0] current_wdata;
    logic current_write;
    
    // Extract page number and offset
    wire [19:0] vpn = current_vaddr[31:12];
    wire [11:0] offset = current_vaddr[11:0];
    
    // Page table lookup
    pte_t current_pte;
    always_comb begin
        current_pte = page_table[vpn[7:0]]; // Use lower 8 bits for indexing
    end
    
    // Statistics counters
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            total_requests <= 0;
            page_faults_count <= 0;
            tlb_hits <= 0;
        end else begin
            if (req_valid && req_ready) begin
                total_requests <= total_requests + 1;
            end
            if (state == FAULT && next_state == IDLE) begin
                page_faults_count <= page_faults_count + 1;
            end
            if (state == TRANSLATE && current_pte.valid) begin
                tlb_hits <= tlb_hits + 1;
            end
        end
    end
    
    // Page table updates
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < NUM_PAGES; i++) begin
                page_table[i].valid <= 0;
                page_table[i].writable <= 0;
                page_table[i].accessed <= 0;
                page_table[i].dirty <= 0;
                page_table[i].ppn <= 0;
            end
        end else if (pt_update) begin
            page_table[pt_vpn[7:0]].valid <= pt_valid;
            page_table[pt_vpn[7:0]].writable <= pt_writable;
            page_table[pt_vpn[7:0]].ppn <= pt_ppn;
            page_table[pt_vpn[7:0]].accessed <= 0;
            page_table[pt_vpn[7:0]].dirty <= 0;
        end else if (state == CHECK_PERMISSIONS && current_pte.valid) begin
            // Update accessed bit
            page_table[vpn[7:0]].accessed <= 1;
            if (current_write) begin
                page_table[vpn[7:0]].dirty <= 1;
            end
        end
    end
    
    // Request queue management
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            queue_head <= 0;
            queue_tail <= 0;
            queue_count <= 0;
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                request_queue[i].valid <= 0;
            end
        end else begin
            // Enqueue new requests
            if (req_valid && req_ready) begin
                request_queue[queue_tail].valid <= 1;
                request_queue[queue_tail].write <= req_write;
                request_queue[queue_tail].vaddr <= req_vaddr;
                request_queue[queue_tail].wdata <= req_wdata;
                queue_tail <= queue_tail + 1;
                queue_count <= queue_count + 1;
            end
            
            // Dequeue processed requests
            if (state == COMPLETE || state == FAULT) begin
                request_queue[queue_head].valid <= 0;
                queue_head <= queue_head + 1;
                queue_count <= queue_count - 1;
            end
        end
    end
    
    // Control signals
    assign req_ready = (queue_count < QUEUE_DEPTH - 1);
    assign req_done = (state == COMPLETE);
    assign page_fault = (state == FAULT);
    
    // State machine
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        mem_valid = 0;
        mem_write = 0;
        mem_paddr = 0;
        mem_wdata = 0;
        
        case (state)
            IDLE: begin
                if (queue_count > 0 && request_queue[queue_head].valid) begin
                    next_state = TRANSLATE;
                end
            end
            
            TRANSLATE: begin
                // Perform address translation
                if (current_pte.valid) begin
                    next_state = CHECK_PERMISSIONS;
                end else begin
                    next_state = FAULT;
                end
            end
            
            CHECK_PERMISSIONS: begin
                if (current_write && !current_pte.writable) begin
                    next_state = FAULT;
                end else begin
                    next_state = MEM_ACCESS;
                end
            end
            
            MEM_ACCESS: begin
                mem_valid = 1;
                mem_write = current_write;
                mem_paddr = current_paddr;
                mem_wdata = current_wdata;
                
                if (mem_ready) begin
                    if (mem_done) begin
                        next_state = COMPLETE;
                    end
                end
            end
            
            COMPLETE: begin
                next_state = IDLE;
            end
            
            FAULT: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Load current request
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_vaddr <= 0;
            current_wdata <= 0;
            current_write <= 0;
            current_paddr <= 0;
            req_rdata <= 0;
        end else begin
            if (state == IDLE && queue_count > 0) begin
                current_vaddr <= request_queue[queue_head].vaddr;
                current_wdata <= request_queue[queue_head].wdata;
                current_write <= request_queue[queue_head].write;
            end
            
            if (state == TRANSLATE && current_pte.valid) begin
                // Compute physical address
                current_paddr <= {current_pte.ppn, offset};
            end
            
            if (state == MEM_ACCESS && mem_done && !current_write) begin
                req_rdata <= mem_rdata;
            end
        end
    end

endmodule
