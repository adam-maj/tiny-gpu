# Memory Optimization

## Code Size Optimization

```c
// Compiler flags for size optimization:
// -Os               : Optimize for size
// -ffunction-sections -fdata-sections : Separate functions/data
// -Wl,--gc-sections : Remove unused sections

// Use const for read-only data (stored in flash, not RAM)
const uint8_t lookup_table[256] = {
    0x00, 0x01, 0x02, /* ... */
};

// Use static to limit scope and enable optimization
static void InternalFunction(void) {
    // Only used in this file
}

// Inline small functions
static inline uint16_t Min(uint16_t a, uint16_t b) {
    return (a < b) ? a : b;
}

// Use appropriate data types
uint8_t small_value;      // Not int
bool is_ready;            // Not int
uint16_t medium_value;    // Not uint32_t if 16 bits enough

// Bit-fields for packed structures
typedef struct {
    uint8_t status : 3;      // 0-7
    uint8_t mode : 2;        // 0-3
    uint8_t error : 1;       // 0-1
    uint8_t ready : 1;       // 0-1
    uint8_t reserved : 1;
} __attribute__((packed)) StatusReg_t;

// Avoid unnecessary includes
// Only include what you need
```

## RAM Optimization

```c
// Share buffers when possible
#define BUFFER_SIZE 256
static uint8_t shared_buffer[BUFFER_SIZE];

void ProcessA(void) {
    // Use shared_buffer
    memset(shared_buffer, 0, BUFFER_SIZE);
    // Process...
}

void ProcessB(void) {
    // Reuse same buffer (not called simultaneously with ProcessA)
    memset(shared_buffer, 0, BUFFER_SIZE);
    // Process...
}

// Use unions for overlapping data
typedef union {
    uint8_t bytes[4];
    uint32_t word;
    float value;
} DataUnion_t;

// Stack vs heap allocation
void BadExample(void) {
    uint8_t *buffer = malloc(1024);  // Heap allocation, fragmentation risk
    // Use buffer...
    free(buffer);
}

void GoodExample(void) {
    uint8_t buffer[1024];  // Stack allocation (if stack permits)
    // Use buffer...
}  // Automatically freed

// Static allocation for predictable behavior
#define MAX_MESSAGES 10
typedef struct {
    CANMessage_t messages[MAX_MESSAGES];
    uint8_t count;
} MessageQueue_t;

static MessageQueue_t message_queue;  // Fixed size, no malloc

// Memory pools for dynamic allocation
#define POOL_SIZE 10
typedef struct {
    uint8_t buffer[64];
    bool in_use;
} MemBlock_t;

static MemBlock_t mem_pool[POOL_SIZE];

MemBlock_t* AllocBlock(void) {
    for (int i = 0; i < POOL_SIZE; i++) {
        if (!mem_pool[i].in_use) {
            mem_pool[i].in_use = true;
            return &mem_pool[i];
        }
    }
    return NULL;  // Pool exhausted
}

void FreeBlock(MemBlock_t *block) {
    if (block >= mem_pool && block < mem_pool + POOL_SIZE) {
        block->in_use = false;
    }
}
```

## Flash Memory Management

```c
// Store constants in flash with PROGMEM (AVR example)
// Or use const in ARM (automatically placed in flash)

// Large lookup tables
const uint16_t sine_table[360] = {
    0, 17, 34, 52, 69, 87, /* ... */
};

// String constants in flash
const char error_msg[] = "Error: Invalid parameter";

// Access flash data directly (ARM)
void UseFlashData(void) {
    uint16_t value = sine_table[90];  // Read from flash
    printf("%s\n", error_msg);        // String from flash
}

// Flash wear leveling for EEPROM emulation
#define FLASH_PAGE_SIZE 2048
#define FLASH_START_ADDR 0x0807F000

typedef struct {
    uint16_t id;
    uint16_t data;
    uint32_t checksum;
} FlashRecord_t;

bool Flash_WriteRecord(uint16_t id, uint16_t data) {
    // Find next available slot
    uint32_t addr = FLASH_START_ADDR;

    while (addr < FLASH_START_ADDR + FLASH_PAGE_SIZE) {
        FlashRecord_t *record = (FlashRecord_t*)addr;

        if (record->id == 0xFFFF) {
            // Empty slot found
            FlashRecord_t new_record = {
                .id = id,
                .data = data,
                .checksum = id + data
            };

            HAL_FLASH_Unlock();
            HAL_FLASH_Program(FLASH_TYPEPROGRAM_WORD, addr, *(uint32_t*)&new_record);
            HAL_FLASH_Lock();

            return true;
        }

        addr += sizeof(FlashRecord_t);
    }

    // Page full - erase and write
    HAL_FLASH_Unlock();
    FLASH_EraseInitTypeDef erase = {
        .TypeErase = FLASH_TYPEERASE_PAGES,
        .PageAddress = FLASH_START_ADDR,
        .NbPages = 1
    };
    uint32_t error;
    HAL_FLASHEx_Erase(&erase, &error);
    HAL_FLASH_Lock();

    return Flash_WriteRecord(id, data);
}
```

## Stack Optimization

```c
// Monitor stack usage (FreeRTOS)
void CheckStackUsage(void) {
    UBaseType_t high_water = uxTaskGetStackHighWaterMark(NULL);
    printf("Stack remaining: %u words\n", high_water);
}

// Reduce local variable size
void BadFunction(void) {
    uint8_t large_buffer[2048];  // Large stack usage
    // ...
}

void GoodFunction(void) {
    static uint8_t large_buffer[2048];  // In BSS, not stack
    // ...
}

// Limit recursion depth
#define MAX_RECURSION_DEPTH 5

int RecursiveFunction(int n, int depth) {
    if (depth > MAX_RECURSION_DEPTH) {
        return -1;  // Prevent stack overflow
    }

    if (n <= 1) return n;
    return RecursiveFunction(n - 1, depth + 1) + RecursiveFunction(n - 2, depth + 1);
}

// Use iteration instead of recursion
int IterativeFunction(int n) {
    if (n <= 1) return n;

    int prev2 = 0, prev1 = 1;
    for (int i = 2; i <= n; i++) {
        int current = prev1 + prev2;
        prev2 = prev1;
        prev1 = current;
    }

    return prev1;
}
```

## Data Structure Optimization

```c
// Packed structures to save RAM
typedef struct {
    uint32_t timestamp;
    uint16_t value;
    uint8_t status;
    uint8_t checksum;
} __attribute__((packed)) DataRecord_t;  // 8 bytes instead of 12

// Ring buffer for efficient FIFO
typedef struct {
    uint8_t buffer[256];
    uint8_t head;
    uint8_t tail;  // Wraps at 256, no modulo needed
} RingBuffer_t;

void RingBuffer_Put(RingBuffer_t *rb, uint8_t data) {
    rb->buffer[rb->head++] = data;  // Auto-wraps due to uint8_t
}

uint8_t RingBuffer_Get(RingBuffer_t *rb) {
    return rb->buffer[rb->tail++];  // Auto-wraps
}

// Bit manipulation for flags
typedef struct {
    uint32_t flags;  // 32 boolean flags in 4 bytes
} SystemFlags_t;

#define FLAG_READY      (1 << 0)
#define FLAG_ERROR      (1 << 1)
#define FLAG_CALIBRATED (1 << 2)

void SetFlag(SystemFlags_t *sf, uint32_t flag) {
    sf->flags |= flag;
}

void ClearFlag(SystemFlags_t *sf, uint32_t flag) {
    sf->flags &= ~flag;
}

bool CheckFlag(SystemFlags_t *sf, uint32_t flag) {
    return (sf->flags & flag) != 0;
}

// Compact state machines
typedef enum {
    STATE_IDLE = 0,
    STATE_INIT,
    STATE_ACTIVE,
    STATE_ERROR
} State_t;

typedef struct {
    State_t state : 3;  // Only 3 bits needed for 4 states
    uint8_t retry_count : 5;
} StateMachine_t;
```

## Memory Monitoring

```c
// Linker script symbols
extern uint32_t _estack;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;
extern uint32_t _heap_start;
extern uint32_t _heap_end;

// Calculate memory usage
void PrintMemoryUsage(void) {
    uint32_t data_size = (uint32_t)&_edata - (uint32_t)&_sdata;
    uint32_t bss_size = (uint32_t)&_ebss - (uint32_t)&_sbss;
    uint32_t heap_size = (uint32_t)&_heap_end - (uint32_t)&_heap_start;

    printf("Data: %u bytes\n", data_size);
    printf("BSS: %u bytes\n", bss_size);
    printf("Heap: %u bytes\n", heap_size);
    printf("Total RAM: %u bytes\n", data_size + bss_size + heap_size);
}

// Stack painting for usage analysis
void PaintStack(void) {
    extern uint32_t _estack;
    uint32_t stack_top = (uint32_t)&_estack;
    uint32_t current_sp;

    __asm volatile("MOV %0, SP" : "=r"(current_sp));

    for (uint32_t addr = current_sp; addr < stack_top; addr += 4) {
        *(uint32_t*)addr = 0xDEADBEEF;
    }
}

uint32_t GetStackUsage(void) {
    extern uint32_t _estack;
    uint32_t stack_top = (uint32_t)&_estack;
    uint32_t addr = stack_top - 1024;  // Assume 1KB stack

    while (addr < stack_top) {
        if (*(uint32_t*)addr != 0xDEADBEEF) {
            break;
        }
        addr += 4;
    }

    return stack_top - addr;
}
```

## Compile-Time Memory Analysis

```c
// Use static_assert to enforce limits
_Static_assert(sizeof(DataRecord_t) <= 16, "DataRecord too large");
_Static_assert(sizeof(StatusReg_t) == 1, "StatusReg not packed");

// Compile-time size calculations
#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

const uint8_t config_data[] = {1, 2, 3, 4, 5};
#define CONFIG_SIZE ARRAY_SIZE(config_data)  // Known at compile time

// Check array bounds at compile time
void SetConfig(uint8_t index, uint8_t value) {
    _Static_assert(CONFIG_SIZE < 256, "Config index must fit in uint8_t");

    if (index < CONFIG_SIZE) {
        // Safe access
    }
}
```

## Optimization Techniques Summary

```c
// 1. Use smallest appropriate data types
uint8_t  counter;        // Not int
bool     flag;           // Not int

// 2. Pack structures
typedef struct {
    uint16_t id;
    uint8_t status;
    uint8_t checksum;
} __attribute__((packed)) Header_t;

// 3. Use const for read-only data (goes to flash)
const uint8_t lookup[256] = { /* ... */ };

// 4. Share buffers
static uint8_t work_buffer[512];

// 5. Use memory pools instead of malloc
static Block_t pool[10];

// 6. Limit stack usage
static uint8_t large_array[1024];  // Not on stack

// 7. Use bit-fields for flags
typedef struct {
    uint8_t ready : 1;
    uint8_t error : 1;
    uint8_t mode : 3;
} Flags_t;

// 8. Enable compiler optimizations
// -Os -ffunction-sections -fdata-sections -Wl,--gc-sections

// 9. Monitor usage
printf("Free heap: %u\n", xPortGetFreeHeapSize());
printf("Stack high water: %u\n", uxTaskGetStackHighWaterMark(NULL));

// 10. Profile and measure
// Use .map file to identify large symbols
// Use size tool: arm-none-eabi-size firmware.elf
```

## Linker Script Customization

```ld
/* Custom linker script sections */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 512K
    RAM (rwx)   : ORIGIN = 0x20000000, LENGTH = 128K
}

SECTIONS
{
    .text : {
        *(.isr_vector)
        *(.text*)
        *(.rodata*)
    } > FLASH

    .data : {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > RAM AT > FLASH

    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > RAM

    /* Reserve space for heap */
    .heap : {
        _heap_start = .;
        . = . + 10K;
        _heap_end = .;
    } > RAM
}
```

## Best Practices

- Use const for all read-only data
- Prefer static allocation over dynamic
- Pack structures with `__attribute__((packed))`
- Use smallest data types possible
- Share buffers when tasks don't overlap
- Monitor heap and stack usage regularly
- Enable link-time optimization (-flto)
- Remove unused code with -ffunction-sections
- Profile with .map file and size tool
- Test with minimal memory configuration
