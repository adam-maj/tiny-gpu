# Power Optimization

## Sleep Mode Strategy

```c
#include "stm32f4xx.h"

typedef enum {
    POWER_MODE_RUN,
    POWER_MODE_SLEEP,
    POWER_MODE_STOP,
    POWER_MODE_STANDBY
} PowerMode_t;

// Power mode with peripheral activity tracking
typedef struct {
    uint32_t run_time_ms;
    uint32_t sleep_time_ms;
    uint32_t stop_time_ms;
    uint32_t active_peripherals;
} PowerProfile_t;

// Enter appropriate sleep mode based on wakeup time
void EnterLowPower(uint32_t sleep_duration_ms) {
    if (sleep_duration_ms < 10) {
        // Very short sleep - just WFI
        __WFI();
    } else if (sleep_duration_ms < 1000) {
        // Short sleep - sleep mode (fast wakeup)
        EnterSleepMode();
    } else {
        // Long sleep - stop mode (lower power)
        EnterStopMode(sleep_duration_ms);
    }
}

void EnterSleepMode(void) {
    // Disable SysTick interrupt to prevent wakeup
    SysTick->CTRL &= ~SysTick_CTRL_TICKINT_Msk;

    // Enter sleep mode
    __WFI();

    // Re-enable SysTick
    SysTick->CTRL |= SysTick_CTRL_TICKINT_Msk;
}

void EnterStopMode(uint32_t sleep_ms) {
    // Configure RTC wakeup if needed
    if (sleep_ms > 0) {
        RTC_SetWakeup(sleep_ms);
    }

    // Disable peripherals before stop
    DisableUnusedPeripherals();

    // Enter stop mode with regulator in low-power mode
    PWR->CR |= PWR_CR_LPDS;
    PWR->CR &= ~PWR_CR_PDDS;
    SCB->SCR |= SCB_SCR_SLEEPDEEP_Msk;

    __WFI();

    // Restore system clock after wakeup
    SystemClock_Config();

    // Re-enable peripherals
    RestorePeripherals();
}
```

## Dynamic Clock Scaling

```c
typedef enum {
    CLOCK_SPEED_LOW = 0,     // 48MHz
    CLOCK_SPEED_MEDIUM,      // 84MHz
    CLOCK_SPEED_HIGH         // 168MHz
} ClockSpeed_t;

void SetSystemClock(ClockSpeed_t speed) {
    switch (speed) {
        case CLOCK_SPEED_LOW:
            // 48MHz - lowest power for low-performance tasks
            ConfigurePLL(8, 96, 2, 2);  // VCO=96MHz, SYSCLK=48MHz
            SystemCoreClock = 48000000;
            break;

        case CLOCK_SPEED_MEDIUM:
            // 84MHz - medium power
            ConfigurePLL(8, 168, 2, 2);
            SystemCoreClock = 84000000;
            break;

        case CLOCK_SPEED_HIGH:
            // 168MHz - full performance
            ConfigurePLL(8, 336, 2, 2);
            SystemCoreClock = 168000000;
            break;
    }

    // Update peripheral clocks
    UpdatePeripheralClocks();
}

// Automatic clock scaling based on workload
void AdaptiveClock(void) {
    static uint32_t idle_ticks = 0;
    static uint32_t total_ticks = 0;

    total_ticks++;

    if (IsIdle()) {
        idle_ticks++;
    }

    // Check every second
    if (total_ticks >= 1000) {
        uint32_t load_percent = 100 - (idle_ticks * 100 / total_ticks);

        if (load_percent > 80) {
            SetSystemClock(CLOCK_SPEED_HIGH);
        } else if (load_percent > 40) {
            SetSystemClock(CLOCK_SPEED_MEDIUM);
        } else {
            SetSystemClock(CLOCK_SPEED_LOW);
        }

        idle_ticks = 0;
        total_ticks = 0;
    }
}
```

## Peripheral Power Management

```c
// Smart peripheral enabling/disabling
typedef struct {
    uint32_t last_used_ms;
    bool is_enabled;
    uint32_t timeout_ms;
} PeripheralPower_t;

PeripheralPower_t i2c_power = {0, false, 1000};
PeripheralPower_t uart_power = {0, false, 5000};

void EnablePeripheral_I2C(void) {
    if (!i2c_power.is_enabled) {
        RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;
        i2c_power.is_enabled = true;
    }
    i2c_power.last_used_ms = HAL_GetTick();
}

void DisableUnusedPeripherals(void) {
    uint32_t current_time = HAL_GetTick();

    // Auto-disable I2C if not used recently
    if (i2c_power.is_enabled) {
        if ((current_time - i2c_power.last_used_ms) > i2c_power.timeout_ms) {
            RCC->APB1ENR &= ~RCC_APB1ENR_I2C1EN;
            i2c_power.is_enabled = false;
        }
    }

    // Auto-disable UART
    if (uart_power.is_enabled) {
        if ((current_time - uart_power.last_used_ms) > uart_power.timeout_ms) {
            RCC->APB1ENR &= ~RCC_APB1ENR_USART2EN;
            uart_power.is_enabled = false;
        }
    }
}

// Disable all non-essential peripherals
void MinimizePower(void) {
    // Disable unused GPIO clocks
    RCC->AHB1ENR &= ~(RCC_AHB1ENR_GPIODEN | RCC_AHB1ENR_GPIOEEN);

    // Disable unused timers
    RCC->APB1ENR &= ~(RCC_APB1ENR_TIM3EN | RCC_APB1ENR_TIM4EN);

    // Disable USB if not used
    RCC->AHB2ENR &= ~RCC_AHB2ENR_OTGFSEN;

    // Disable DMA if not needed
    RCC->AHB1ENR &= ~(RCC_AHB1ENR_DMA1EN | RCC_AHB1ENR_DMA2EN);
}
```

## GPIO Power Optimization

```c
// Configure unused pins to minimize leakage
void ConfigureUnusedPins(void) {
    // All unused pins: analog mode (lowest power)
    GPIOD->MODER = 0xFFFFFFFF;  // All pins analog
    GPIOE->MODER = 0xFFFFFFFF;
    GPIOF->MODER = 0xFFFFFFFF;

    // Alternatively: output low
    // GPIOD->MODER = 0x55555555;  // All output
    // GPIOD->ODR = 0x0000;        // All low
}

// Configure GPIO for minimum power in sleep
void PrepareGPIOForSleep(void) {
    // Save current GPIO state
    uint32_t gpioa_moder = GPIOA->MODER;

    // Set all to analog mode (except wakeup pins)
    GPIOA->MODER = 0xFFFFFFFF;
    GPIOB->MODER = 0xFFFFFFFF;
    GPIOC->MODER = 0xFFFFFFFF;

    // Keep PA0 as input for wakeup
    GPIOA->MODER &= ~(0x3 << 0);

    // Enter sleep...
    EnterStopMode(0);

    // Restore GPIO configuration
    GPIOA->MODER = gpioa_moder;
}
```

## ADC Power Optimization

```c
// ADC with automatic power-down
void ADC_LowPower_Init(void) {
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;

    // Enable auto power-down mode
    ADC1->CR1 &= ~ADC_CR1_RES;  // 12-bit resolution

    // Discontinuous mode
    ADC1->CR1 |= ADC_CR1_DISCEN;

    // Power on only when needed
    ADC1->CR2 &= ~ADC_CR2_ADON;
}

uint16_t ADC_ReadLowPower(uint8_t channel) {
    // Power on ADC
    ADC1->CR2 |= ADC_CR2_ADON;

    // Wait for ADC ready (few microseconds)
    for (volatile int i = 0; i < 100; i++);

    // Configure channel
    ADC1->SQR3 = channel;

    // Start conversion
    ADC1->CR2 |= ADC_CR2_SWSTART;

    // Wait for completion
    while (!(ADC1->SR & ADC_SR_EOC));

    uint16_t result = ADC1->DR;

    // Power down ADC
    ADC1->CR2 &= ~ADC_CR2_ADON;

    return result;
}
```

## Battery Monitoring

```c
// Battery voltage monitoring with low-power ADC
#define VREFINT_CAL_ADDR  ((uint16_t*)0x1FFF7A2A)
#define VREFINT_CAL_VREF  3300  // mV

uint16_t GetBatteryVoltage_mV(void) {
    // Read internal reference voltage
    uint16_t vrefint_data = ADC_ReadLowPower(17);  // Internal VREF channel

    // Calculate actual VDDA
    uint32_t vdda = 3300 * (*VREFINT_CAL_ADDR) / vrefint_data;

    // Read battery voltage divider (e.g., on ADC channel 0)
    uint16_t battery_raw = ADC_ReadLowPower(0);

    // Assuming 2:1 voltage divider
    uint32_t battery_mv = (vdda * battery_raw / 4096) * 2;

    return battery_mv;
}

// Battery state estimation
typedef enum {
    BATTERY_FULL,
    BATTERY_GOOD,
    BATTERY_LOW,
    BATTERY_CRITICAL
} BatteryState_t;

BatteryState_t GetBatteryState(void) {
    uint16_t voltage = GetBatteryVoltage_mV();

    if (voltage > 3700) return BATTERY_FULL;
    else if (voltage > 3400) return BATTERY_GOOD;
    else if (voltage > 3200) return BATTERY_LOW;
    else return BATTERY_CRITICAL;
}

// Adaptive behavior based on battery
void AdaptToBattery(void) {
    BatteryState_t state = GetBatteryState();

    switch (state) {
        case BATTERY_FULL:
        case BATTERY_GOOD:
            // Normal operation
            SetSystemClock(CLOCK_SPEED_HIGH);
            SetSamplingRate(100);  // 100Hz
            break;

        case BATTERY_LOW:
            // Reduce performance
            SetSystemClock(CLOCK_SPEED_MEDIUM);
            SetSamplingRate(10);  // 10Hz
            break;

        case BATTERY_CRITICAL:
            // Minimum power mode
            SetSystemClock(CLOCK_SPEED_LOW);
            SetSamplingRate(1);  // 1Hz
            DisableNonEssentialFeatures();
            break;
    }
}
```

## RTC Wakeup

```c
// Configure RTC for periodic wakeup
void RTC_Init_Wakeup(void) {
    // Enable PWR clock
    RCC->APB1ENR |= RCC_APB1ENR_PWREN;

    // Enable access to RTC domain
    PWR->CR |= PWR_CR_DBP;

    // Enable LSI
    RCC->CSR |= RCC_CSR_LSION;
    while (!(RCC->CSR & RCC_CSR_LSIRDY));

    // Select LSI as RTC clock
    RCC->BDCR |= RCC_BDCR_RTCSEL_1;
    RCC->BDCR |= RCC_BDCR_RTCEN;

    // Disable RTC write protection
    RTC->WPR = 0xCA;
    RTC->WPR = 0x53;

    // Configure wakeup timer
    RTC->CR &= ~RTC_CR_WUTE;
    while (!(RTC->ISR & RTC_ISR_WUTWF));

    // Set wakeup auto-reload (1Hz with 37kHz LSI)
    RTC->WUTR = 37000 - 1;

    // Enable wakeup timer and interrupt
    RTC->CR |= RTC_CR_WUTIE | RTC_CR_WUTE;

    // Enable RTC wakeup interrupt in EXTI
    EXTI->IMR |= EXTI_IMR_MR22;
    EXTI->RTSR |= EXTI_RTSR_TR22;

    // Enable NVIC
    NVIC_EnableIRQ(RTC_WKUP_IRQn);
}

void RTC_WKUP_IRQHandler(void) {
    if (RTC->ISR & RTC_ISR_WUTF) {
        RTC->ISR &= ~RTC_ISR_WUTF;  // Clear flag
        EXTI->PR = EXTI_PR_PR22;     // Clear EXTI flag

        // Periodic wakeup action
        PeriodicTask();
    }
}
```

## Power Measurement

```c
// Estimate power consumption
typedef struct {
    uint32_t cpu_active_ms;
    uint32_t cpu_sleep_ms;
    uint32_t peripherals;  // Bitmap of active peripherals
    ClockSpeed_t clock_speed;
} PowerStats_t;

float EstimatePower_mA(PowerStats_t *stats) {
    float power = 0.0f;

    // CPU power based on clock speed and activity
    switch (stats->clock_speed) {
        case CLOCK_SPEED_HIGH:
            power += 30.0f;  // 30mA at 168MHz
            break;
        case CLOCK_SPEED_MEDIUM:
            power += 20.0f;  // 20mA at 84MHz
            break;
        case CLOCK_SPEED_LOW:
            power += 12.0f;  // 12mA at 48MHz
            break;
    }

    // Sleep mode power
    float sleep_ratio = (float)stats->cpu_sleep_ms / (stats->cpu_active_ms + stats->cpu_sleep_ms);
    power = power * (1.0f - sleep_ratio) + 0.5f * sleep_ratio;  // 0.5mA in sleep

    // Peripheral power
    if (stats->peripherals & PERIPH_UART) power += 1.0f;
    if (stats->peripherals & PERIPH_I2C) power += 0.5f;
    if (stats->peripherals & PERIPH_SPI) power += 1.5f;
    if (stats->peripherals & PERIPH_ADC) power += 2.0f;

    return power;
}
```

## Best Practices

- Use stop mode for sleeps > 1 second
- Configure unused pins as analog or output-low
- Disable peripheral clocks when not in use
- Use RTC wakeup instead of systick in low-power modes
- Reduce clock speed during low-activity periods
- Use DMA to reduce CPU wakeups
- Batch operations to minimize wakeup frequency
- Monitor battery and adapt behavior
- Profile actual power consumption with current meter
