# Communication Protocols

## I2C Master Implementation

```c
#include "stm32f4xx.h"

// I2C1 on PB6 (SCL) and PB7 (SDA)
void I2C_Init(void) {
    // Enable clocks
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;

    // Configure GPIO pins (alternate function, open-drain)
    GPIOB->MODER |= (2 << GPIO_MODER_MODER6_Pos) | (2 << GPIO_MODER_MODER7_Pos);
    GPIOB->OTYPER |= GPIO_OTYPER_OT6 | GPIO_OTYPER_OT7;
    GPIOB->OSPEEDR |= (3 << GPIO_OSPEEDR_OSPEEDR6_Pos) | (3 << GPIO_OSPEEDR_OSPEEDR7_Pos);
    GPIOB->PUPDR |= (1 << GPIO_PUPDR_PUPDR6_Pos) | (1 << GPIO_PUPDR_PUPDR7_Pos);
    GPIOB->AFR[0] |= (4 << GPIO_AFRL_AFRL6_Pos) | (4 << GPIO_AFRL_AFRL7_Pos);

    // Reset I2C
    I2C1->CR1 |= I2C_CR1_SWRST;
    I2C1->CR1 &= ~I2C_CR1_SWRST;

    // Configure I2C timing for 100kHz (APB1 = 42MHz)
    I2C1->CR2 = 42;  // FREQ = 42MHz
    I2C1->CCR = 210;  // CCR = 42MHz / (2 * 100kHz) = 210
    I2C1->TRISE = 43; // TRISE = (1000ns / 23.8ns) + 1 = 43

    // Enable I2C
    I2C1->CR1 |= I2C_CR1_PE;
}

// I2C write with timeout
bool I2C_Write(uint8_t addr, uint8_t *data, uint16_t len) {
    uint32_t timeout = 10000;

    // Generate start condition
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB) && --timeout);
    if (timeout == 0) return false;

    // Send address
    I2C1->DR = (addr << 1);
    timeout = 10000;
    while (!(I2C1->SR1 & I2C_SR1_ADDR) && --timeout);
    if (timeout == 0) return false;

    // Clear ADDR flag
    (void)I2C1->SR1;
    (void)I2C1->SR2;

    // Send data
    for (uint16_t i = 0; i < len; i++) {
        I2C1->DR = data[i];
        timeout = 10000;
        while (!(I2C1->SR1 & I2C_SR1_TXE) && --timeout);
        if (timeout == 0) return false;
    }

    // Wait for BTF
    timeout = 10000;
    while (!(I2C1->SR1 & I2C_SR1_BTF) && --timeout);
    if (timeout == 0) return false;

    // Generate stop condition
    I2C1->CR1 |= I2C_CR1_STOP;

    return true;
}

// I2C read
bool I2C_Read(uint8_t addr, uint8_t *data, uint16_t len) {
    uint32_t timeout = 10000;

    // Generate start
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB) && --timeout);
    if (timeout == 0) return false;

    // Send address with read bit
    I2C1->DR = (addr << 1) | 1;
    timeout = 10000;
    while (!(I2C1->SR1 & I2C_SR1_ADDR) && --timeout);
    if (timeout == 0) return false;

    // Clear ADDR flag
    (void)I2C1->SR1;
    (void)I2C1->SR2;

    if (len == 1) {
        // Single byte read
        I2C1->CR1 &= ~I2C_CR1_ACK;
        I2C1->CR1 |= I2C_CR1_STOP;

        timeout = 10000;
        while (!(I2C1->SR1 & I2C_SR1_RXNE) && --timeout);
        if (timeout == 0) return false;

        data[0] = I2C1->DR;
    } else {
        // Multiple byte read
        I2C1->CR1 |= I2C_CR1_ACK;

        for (uint16_t i = 0; i < len; i++) {
            if (i == len - 1) {
                I2C1->CR1 &= ~I2C_CR1_ACK;
                I2C1->CR1 |= I2C_CR1_STOP;
            }

            timeout = 10000;
            while (!(I2C1->SR1 & I2C_SR1_RXNE) && --timeout);
            if (timeout == 0) return false;

            data[i] = I2C1->DR;
        }
    }

    return true;
}

// I2C register read (common pattern)
bool I2C_ReadRegister(uint8_t addr, uint8_t reg, uint8_t *data, uint16_t len) {
    if (!I2C_Write(addr, &reg, 1)) return false;
    return I2C_Read(addr, data, len);
}
```

## SPI Master Implementation

```c
// SPI1 on PA5 (SCK), PA6 (MISO), PA7 (MOSI)
void SPI_Init(void) {
    // Enable clocks
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // Configure GPIO pins
    GPIOA->MODER |= (2 << GPIO_MODER_MODER5_Pos) |
                    (2 << GPIO_MODER_MODER6_Pos) |
                    (2 << GPIO_MODER_MODER7_Pos);
    GPIOA->AFR[0] |= (5 << GPIO_AFRL_AFRL5_Pos) |
                     (5 << GPIO_AFRL_AFRL6_Pos) |
                     (5 << GPIO_AFRL_AFRL7_Pos);

    // Configure SPI: Master, 8-bit, MSB first, fPCLK/16 (~5MHz)
    SPI1->CR1 = SPI_CR1_MSTR |        // Master mode
                SPI_CR1_SSM |         // Software slave management
                SPI_CR1_SSI |         // Internal slave select
                (3 << SPI_CR1_BR_Pos) | // Baud rate fPCLK/16
                SPI_CR1_SPE;          // Enable SPI
}

uint8_t SPI_Transfer(uint8_t data) {
    // Wait for TX buffer empty
    while (!(SPI1->SR & SPI_SR_TXE));
    SPI1->DR = data;

    // Wait for RX buffer not empty
    while (!(SPI1->SR & SPI_SR_RXNE));
    return SPI1->DR;
}

void SPI_TransferBuffer(uint8_t *tx_data, uint8_t *rx_data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        rx_data[i] = SPI_Transfer(tx_data[i]);
    }
}

// SPI with DMA for high-speed transfers
void SPI_DMA_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

    // Configure TX DMA (DMA2 Stream 3 Channel 3)
    DMA2_Stream3->CR = 0;
    while (DMA2_Stream3->CR & DMA_SxCR_EN);

    DMA2_Stream3->PAR = (uint32_t)&(SPI1->DR);
    DMA2_Stream3->CR = (3 << DMA_SxCR_CHSEL_Pos) |  // Channel 3
                       (0 << DMA_SxCR_MSIZE_Pos) |  // 8-bit memory
                       (0 << DMA_SxCR_PSIZE_Pos) |  // 8-bit peripheral
                       DMA_SxCR_MINC |               // Memory increment
                       DMA_SxCR_DIR_0;               // Memory to peripheral

    // Configure RX DMA (DMA2 Stream 0 Channel 3)
    DMA2_Stream0->CR = 0;
    while (DMA2_Stream0->CR & DMA_SxCR_EN);

    DMA2_Stream0->PAR = (uint32_t)&(SPI1->DR);
    DMA2_Stream0->CR = (3 << DMA_SxCR_CHSEL_Pos) |
                       (0 << DMA_SxCR_MSIZE_Pos) |
                       (0 << DMA_SxCR_PSIZE_Pos) |
                       DMA_SxCR_MINC;

    // Enable SPI DMA requests
    SPI1->CR2 |= SPI_CR2_TXDMAEN | SPI_CR2_RXDMAEN;
}

bool SPI_DMA_Transfer(uint8_t *tx_data, uint8_t *rx_data, uint16_t len) {
    // Configure DMA streams
    DMA2_Stream3->M0AR = (uint32_t)tx_data;
    DMA2_Stream3->NDTR = len;
    DMA2_Stream0->M0AR = (uint32_t)rx_data;
    DMA2_Stream0->NDTR = len;

    // Enable DMA streams
    DMA2_Stream0->CR |= DMA_SxCR_EN;
    DMA2_Stream3->CR |= DMA_SxCR_EN;

    // Wait for transfer complete
    uint32_t timeout = 100000;
    while ((DMA2_Stream0->CR & DMA_SxCR_EN) && --timeout);
    while ((DMA2_Stream3->CR & DMA_SxCR_EN) && --timeout);

    return timeout > 0;
}
```

## UART with Interrupt and Circular Buffer

```c
#define UART_RX_BUFFER_SIZE 256

typedef struct {
    uint8_t buffer[UART_RX_BUFFER_SIZE];
    uint16_t head;
    uint16_t tail;
} UARTBuffer_t;

volatile UARTBuffer_t uart_rx_buffer = {0};

void UART_Init_IRQ(void) {
    // Enable clocks
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;

    // Configure GPIO
    GPIOA->MODER |= (2 << GPIO_MODER_MODER2_Pos) | (2 << GPIO_MODER_MODER3_Pos);
    GPIOA->AFR[0] |= (7 << GPIO_AFRL_AFRL2_Pos) | (7 << GPIO_AFRL_AFRL3_Pos);

    // Configure USART
    USART2->BRR = 0x2D9;  // 115200 baud
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE | USART_CR1_UE;

    // Enable NVIC
    NVIC_SetPriority(USART2_IRQn, 2);
    NVIC_EnableIRQ(USART2_IRQn);
}

void USART2_IRQHandler(void) {
    if (USART2->SR & USART_SR_RXNE) {
        uint8_t data = USART2->DR;

        uint16_t next_head = (uart_rx_buffer.head + 1) % UART_RX_BUFFER_SIZE;

        if (next_head != uart_rx_buffer.tail) {
            uart_rx_buffer.buffer[uart_rx_buffer.head] = data;
            uart_rx_buffer.head = next_head;
        }
        // Else: buffer overflow, discard data
    }

    if (USART2->SR & USART_SR_ORE) {
        // Clear overrun error
        (void)USART2->DR;
    }
}

uint16_t UART_Available(void) {
    return (uart_rx_buffer.head - uart_rx_buffer.tail + UART_RX_BUFFER_SIZE) % UART_RX_BUFFER_SIZE;
}

bool UART_ReadByte(uint8_t *data) {
    if (uart_rx_buffer.head == uart_rx_buffer.tail) {
        return false;  // Buffer empty
    }

    *data = uart_rx_buffer.buffer[uart_rx_buffer.tail];
    uart_rx_buffer.tail = (uart_rx_buffer.tail + 1) % UART_RX_BUFFER_SIZE;

    return true;
}

uint16_t UART_ReadBuffer(uint8_t *buffer, uint16_t max_len) {
    uint16_t count = 0;

    while (count < max_len && UART_ReadByte(&buffer[count])) {
        count++;
    }

    return count;
}
```

## CAN Bus Implementation

```c
// CAN on PB8 (RX) and PB9 (TX)
void CAN_Init(void) {
    // Enable clocks
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    RCC->APB1ENR |= RCC_APB1ENR_CAN1EN;

    // Configure GPIO
    GPIOB->MODER |= (2 << GPIO_MODER_MODER8_Pos) | (2 << GPIO_MODER_MODER9_Pos);
    GPIOB->AFR[1] |= (9 << GPIO_AFRH_AFRH0_Pos) | (9 << GPIO_AFRH_AFRH1_Pos);

    // Enter initialization mode
    CAN1->MCR |= CAN_MCR_INRQ;
    while (!(CAN1->MSR & CAN_MSR_INAK));

    // Configure timing: 500kbps (APB1 = 42MHz)
    // BRP=6, TS1=13, TS2=2 -> 42MHz/(6*(1+13+2)) = 437.5kbps
    CAN1->BTR = (1 << CAN_BTR_SJW_Pos) |   // SJW = 2
                (13 << CAN_BTR_TS1_Pos) |  // TS1 = 14
                (1 << CAN_BTR_TS2_Pos) |   // TS2 = 2
                (5 << CAN_BTR_BRP_Pos);    // BRP = 6

    // Configure filters (accept all)
    CAN1->FMR |= CAN_FMR_FINIT;
    CAN1->FA1R &= ~CAN_FA1R_FACT0;
    CAN1->FM1R &= ~CAN_FM1R_FBM0;   // Mask mode
    CAN1->FS1R |= CAN_FS1R_FSC0;    // 32-bit scale
    CAN1->sFilterRegister[0].FR1 = 0;
    CAN1->sFilterRegister[0].FR2 = 0;
    CAN1->FA1R |= CAN_FA1R_FACT0;
    CAN1->FMR &= ~CAN_FMR_FINIT;

    // Leave initialization mode
    CAN1->MCR &= ~CAN_MCR_INRQ;
    while (CAN1->MSR & CAN_MSR_INAK);

    // Enable FIFO interrupts
    CAN1->IER |= CAN_IER_FMPIE0;
    NVIC_EnableIRQ(CAN1_RX0_IRQn);
}

bool CAN_Transmit(uint32_t id, uint8_t *data, uint8_t len) {
    // Find empty mailbox
    if (!(CAN1->TSR & CAN_TSR_TME0)) return false;

    // Set identifier
    CAN1->sTxMailBox[0].TIR = (id << CAN_TI0R_STID_Pos);

    // Set data length
    CAN1->sTxMailBox[0].TDTR = len;

    // Set data
    CAN1->sTxMailBox[0].TDLR = ((uint32_t)data[3] << 24) |
                               ((uint32_t)data[2] << 16) |
                               ((uint32_t)data[1] << 8) |
                               ((uint32_t)data[0]);
    CAN1->sTxMailBox[0].TDHR = ((uint32_t)data[7] << 24) |
                               ((uint32_t)data[6] << 16) |
                               ((uint32_t)data[5] << 8) |
                               ((uint32_t)data[4]);

    // Request transmission
    CAN1->sTxMailBox[0].TIR |= CAN_TI0R_TXRQ;

    return true;
}

typedef struct {
    uint32_t id;
    uint8_t data[8];
    uint8_t len;
} CANMessage_t;

bool CAN_Receive(CANMessage_t *msg) {
    if (!(CAN1->RF0R & CAN_RF0R_FMP0)) {
        return false;  // No message
    }

    // Read identifier
    msg->id = (CAN1->sFIFOMailBox[0].RIR >> CAN_RI0R_STID_Pos) & 0x7FF;

    // Read data length
    msg->len = CAN1->sFIFOMailBox[0].RDTR & CAN_RDT0R_DLC;

    // Read data
    uint32_t low = CAN1->sFIFOMailBox[0].RDLR;
    uint32_t high = CAN1->sFIFOMailBox[0].RDHR;

    msg->data[0] = (low >> 0) & 0xFF;
    msg->data[1] = (low >> 8) & 0xFF;
    msg->data[2] = (low >> 16) & 0xFF;
    msg->data[3] = (low >> 24) & 0xFF;
    msg->data[4] = (high >> 0) & 0xFF;
    msg->data[5] = (high >> 8) & 0xFF;
    msg->data[6] = (high >> 16) & 0xFF;
    msg->data[7] = (high >> 24) & 0xFF;

    // Release FIFO
    CAN1->RF0R |= CAN_RF0R_RFOM0;

    return true;
}
```

## Best Practices

- Always use timeouts to prevent infinite loops
- Implement error handling and recovery
- Use DMA for high-speed transfers
- Use interrupts to avoid polling
- Protect shared buffers with critical sections
- Validate received data (CRC, checksums)
- Implement protocol state machines properly
- Configure GPIO alternate functions correctly
- Calculate baud rates/timings accurately
