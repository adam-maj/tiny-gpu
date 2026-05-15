# Microcontroller Programming

## GPIO Configuration (STM32)

```c
#include "stm32f4xx.h"

// Configure GPIO pin as output
void GPIO_Init_Output(GPIO_TypeDef *port, uint32_t pin) {
    // Enable clock for GPIO port
    if (port == GPIOA) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    else if (port == GPIOB) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    else if (port == GPIOC) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;

    // Set mode to output (01)
    port->MODER &= ~(0x3 << (pin * 2));
    port->MODER |= (0x1 << (pin * 2));

    // Set output type to push-pull
    port->OTYPER &= ~(1 << pin);

    // Set speed to high
    port->OSPEEDR |= (0x3 << (pin * 2));

    // No pull-up/pull-down
    port->PUPDR &= ~(0x3 << (pin * 2));
}

// Configure GPIO pin as input with pull-up
void GPIO_Init_Input_PullUp(GPIO_TypeDef *port, uint32_t pin) {
    // Enable clock
    if (port == GPIOA) RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;

    // Set mode to input (00)
    port->MODER &= ~(0x3 << (pin * 2));

    // Set pull-up (01)
    port->PUPDR &= ~(0x3 << (pin * 2));
    port->PUPDR |= (0x1 << (pin * 2));
}

// Toggle GPIO pin
static inline void GPIO_Toggle(GPIO_TypeDef *port, uint32_t pin) {
    port->ODR ^= (1 << pin);
}

// Read GPIO pin
static inline bool GPIO_Read(GPIO_TypeDef *port, uint32_t pin) {
    return (port->IDR & (1 << pin)) != 0;
}

// Write GPIO pin (using BSRR for atomic operation)
static inline void GPIO_Write(GPIO_TypeDef *port, uint32_t pin, bool state) {
    if (state) {
        port->BSRR = (1 << pin);  // Set
    } else {
        port->BSRR = (1 << (pin + 16));  // Reset
    }
}
```

## Timer Configuration

```c
// Configure TIM2 for 1kHz interrupt (84MHz clock)
void Timer_Init_1kHz(void) {
    // Enable TIM2 clock
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // Configure prescaler and auto-reload
    // 84MHz / 84 = 1MHz, 1MHz / 1000 = 1kHz
    TIM2->PSC = 84 - 1;     // Prescaler
    TIM2->ARR = 1000 - 1;   // Auto-reload

    // Enable update interrupt
    TIM2->DIER |= TIM_DIER_UIE;

    // Enable TIM2 interrupt in NVIC
    NVIC_SetPriority(TIM2_IRQn, 2);
    NVIC_EnableIRQ(TIM2_IRQn);

    // Start timer
    TIM2->CR1 |= TIM_CR1_CEN;
}

// Timer interrupt handler
void TIM2_IRQHandler(void) {
    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;  // Clear flag

        // 1kHz tick
        SystemTick();
    }
}

// PWM configuration (50% duty cycle, 1kHz)
void PWM_Init(void) {
    RCC->APB1ENR |= RCC_APB1ENR_TIM3EN;

    // Configure timer for PWM
    TIM3->PSC = 84 - 1;     // 1MHz
    TIM3->ARR = 1000 - 1;   // 1kHz

    // PWM mode 1 on channel 1
    TIM3->CCMR1 |= (0x6 << TIM_CCMR1_OC1M_Pos);
    TIM3->CCMR1 |= TIM_CCMR1_OC1PE;

    // 50% duty cycle
    TIM3->CCR1 = 500;

    // Enable output
    TIM3->CCER |= TIM_CCER_CC1E;

    // Start timer
    TIM3->CR1 |= TIM_CR1_CEN;
}

// Set PWM duty cycle (0-1000)
void PWM_SetDutyCycle(uint16_t duty) {
    TIM3->CCR1 = duty;
}
```

## External Interrupt (EXTI)

```c
// Configure PA0 as external interrupt (rising edge)
void EXTI_Init_PA0(void) {
    // Enable GPIOA and SYSCFG clocks
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;

    // Configure PA0 as input
    GPIOA->MODER &= ~GPIO_MODER_MODER0;

    // Connect EXTI0 to PA0
    SYSCFG->EXTICR[0] &= ~SYSCFG_EXTICR1_EXTI0;
    SYSCFG->EXTICR[0] |= SYSCFG_EXTICR1_EXTI0_PA;

    // Configure EXTI0
    EXTI->IMR |= EXTI_IMR_MR0;      // Unmask interrupt
    EXTI->RTSR |= EXTI_RTSR_TR0;    // Rising edge trigger

    // Enable EXTI0 interrupt in NVIC
    NVIC_SetPriority(EXTI0_IRQn, 3);
    NVIC_EnableIRQ(EXTI0_IRQn);
}

// EXTI0 interrupt handler
void EXTI0_IRQHandler(void) {
    if (EXTI->PR & EXTI_PR_PR0) {
        EXTI->PR = EXTI_PR_PR0;  // Clear pending flag

        // Handle button press
        Button_Pressed();
    }
}
```

## ADC Configuration

```c
// Configure ADC1 for single conversion
void ADC_Init(void) {
    // Enable ADC1 clock
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;

    // Configure ADC
    ADC1->CR2 = 0;
    ADC1->CR1 = 0;

    // 12-bit resolution
    ADC1->CR1 &= ~ADC_CR1_RES;

    // Single conversion mode
    ADC1->CR2 &= ~ADC_CR2_CONT;

    // Right alignment
    ADC1->CR2 &= ~ADC_CR2_ALIGN;

    // Regular sequence length = 1
    ADC1->SQR1 = 0;

    // Power on ADC
    ADC1->CR2 |= ADC_CR2_ADON;
}

// Read ADC channel
uint16_t ADC_Read(uint8_t channel) {
    // Set channel in regular sequence
    ADC1->SQR3 = channel;

    // Start conversion
    ADC1->CR2 |= ADC_CR2_SWSTART;

    // Wait for conversion complete
    while (!(ADC1->SR & ADC_SR_EOC));

    // Return result
    return ADC1->DR;
}

// ADC with DMA (continuous conversion)
void ADC_Init_DMA(void) {
    // Enable DMA2 clock
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

    // Configure DMA2 Stream 0 Channel 0 for ADC1
    DMA2_Stream0->CR = 0;
    while (DMA2_Stream0->CR & DMA_SxCR_EN);  // Wait for disable

    DMA2_Stream0->PAR = (uint32_t)&(ADC1->DR);
    DMA2_Stream0->M0AR = (uint32_t)adc_buffer;
    DMA2_Stream0->NDTR = ADC_BUFFER_SIZE;

    DMA2_Stream0->CR = (0 << DMA_SxCR_CHSEL_Pos) |  // Channel 0
                       (1 << DMA_SxCR_MSIZE_Pos) |  // 16-bit memory
                       (1 << DMA_SxCR_PSIZE_Pos) |  // 16-bit peripheral
                       DMA_SxCR_MINC |               // Memory increment
                       DMA_SxCR_CIRC |               // Circular mode
                       DMA_SxCR_EN;                  // Enable

    // Enable ADC DMA mode
    ADC1->CR2 |= ADC_CR2_DMA | ADC_CR2_DDS;

    // Enable continuous conversion
    ADC1->CR2 |= ADC_CR2_CONT;

    // Start conversion
    ADC1->CR2 |= ADC_CR2_SWSTART;
}
```

## UART Communication

```c
// Configure USART2 (115200 baud, 8N1)
void UART_Init(void) {
    // Enable USART2 and GPIOA clocks
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;

    // Configure PA2 (TX) and PA3 (RX) as alternate function
    GPIOA->MODER |= (2 << GPIO_MODER_MODER2_Pos) | (2 << GPIO_MODER_MODER3_Pos);
    GPIOA->AFR[0] |= (7 << GPIO_AFRL_AFRL2_Pos) | (7 << GPIO_AFRL_AFRL3_Pos);

    // Configure USART2
    // 84MHz / 115200 = 729 = 0x2D9
    USART2->BRR = 0x2D9;

    // Enable TX, RX, and USART
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
}

// Send byte
void UART_SendByte(uint8_t data) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = data;
}

// Receive byte
uint8_t UART_ReceiveByte(void) {
    while (!(USART2->SR & USART_SR_RXNE));
    return USART2->DR;
}

// Send string
void UART_SendString(const char *str) {
    while (*str) {
        UART_SendByte(*str++);
    }
}
```

## System Clock Configuration

```c
// Configure system clock to 168MHz (STM32F4)
void SystemClock_Config(void) {
    // Enable HSE
    RCC->CR |= RCC_CR_HSEON;
    while (!(RCC->CR & RCC_CR_HSERDY));

    // Configure flash latency (5 wait states for 168MHz)
    FLASH->ACR = FLASH_ACR_PRFTEN | FLASH_ACR_ICEN | FLASH_ACR_DCEN | FLASH_ACR_LATENCY_5WS;

    // Configure PLL: HSE=8MHz, VCO=336MHz, SYSCLK=168MHz
    // PLL_VCO = (HSE / PLLM) * PLLN = (8 / 8) * 336 = 336MHz
    // SYSCLK = PLL_VCO / PLLP = 336 / 2 = 168MHz
    RCC->PLLCFGR = (8 << RCC_PLLCFGR_PLLM_Pos) |
                   (336 << RCC_PLLCFGR_PLLN_Pos) |
                   (0 << RCC_PLLCFGR_PLLP_Pos) |  // PLLP = 2
                   RCC_PLLCFGR_PLLSRC_HSE |
                   (7 << RCC_PLLCFGR_PLLQ_Pos);

    // Enable PLL
    RCC->CR |= RCC_CR_PLLON;
    while (!(RCC->CR & RCC_CR_PLLRDY));

    // Configure AHB, APB1, APB2 prescalers
    RCC->CFGR = RCC_CFGR_HPRE_DIV1 |   // AHB = 168MHz
                RCC_CFGR_PPRE1_DIV4 |  // APB1 = 42MHz
                RCC_CFGR_PPRE2_DIV2;   // APB2 = 84MHz

    // Switch to PLL
    RCC->CFGR |= RCC_CFGR_SW_PLL;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL);

    // Update SystemCoreClock variable
    SystemCoreClock = 168000000;
}
```

## Watchdog Timer

```c
// Configure independent watchdog (IWDG)
void Watchdog_Init(void) {
    // Enable write access to IWDG registers
    IWDG->KR = 0x5555;

    // Set prescaler to 64 (40kHz / 64 = 625Hz)
    IWDG->PR = IWDG_PR_PR_2;

    // Set reload value (625Hz / 625 = 1s timeout)
    IWDG->RLR = 625;

    // Reload counter
    IWDG->KR = 0xAAAA;

    // Start watchdog
    IWDG->KR = 0xCCCC;
}

// Reset watchdog
void Watchdog_Refresh(void) {
    IWDG->KR = 0xAAAA;
}
```

## Low-Power Modes

```c
// Enter sleep mode (CPU stopped, peripherals running)
void Enter_Sleep(void) {
    __WFI();  // Wait for interrupt
}

// Enter stop mode (all clocks stopped except LSI/LSE)
void Enter_Stop(void) {
    // Clear wakeup flags
    PWR->CR |= PWR_CR_CWUF;

    // Set SLEEPDEEP bit
    SCB->SCR |= SCB_SCR_SLEEPDEEP_Msk;

    // Enter stop mode
    PWR->CR &= ~PWR_CR_PDDS;
    PWR->CR |= PWR_CR_LPDS;

    __WFI();

    // Reconfigure clocks after wakeup
    SystemClock_Config();
}

// Enter standby mode (lowest power, RAM lost)
void Enter_Standby(void) {
    // Enable wakeup pin
    PWR->CSR |= PWR_CSR_EWUP;

    // Clear wakeup flags
    PWR->CR |= PWR_CR_CWUF;

    // Set SLEEPDEEP bit
    SCB->SCR |= SCB_SCR_SLEEPDEEP_Msk;

    // Enter standby mode
    PWR->CR |= PWR_CR_PDDS;

    __WFI();
}
```

## Best Practices

- Always use `volatile` for hardware register access
- Use bit-banding for atomic single-bit operations
- Clear interrupt flags in ISRs to prevent re-entry
- Configure clock tree before enabling peripherals
- Use BSRR register for atomic GPIO writes
- Enable interrupts with appropriate priorities
- Add timeout checks for polling operations
- Protect RMW operations with critical sections if needed
