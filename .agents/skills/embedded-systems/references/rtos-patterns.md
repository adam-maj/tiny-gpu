# RTOS Patterns

## Task Creation and Management

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"

// Task priorities (0 = lowest, configMAX_PRIORITIES-1 = highest)
#define PRIORITY_SENSOR     (tskIDLE_PRIORITY + 2)
#define PRIORITY_PROCESSING (tskIDLE_PRIORITY + 1)
#define PRIORITY_COMM       (tskIDLE_PRIORITY + 3)

// Stack sizes (in words, not bytes)
#define STACK_SIZE_SENSOR   (256)
#define STACK_SIZE_PROCESS  (512)

void vSensorTask(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xFrequency = pdMS_TO_TICKS(100);  // 100ms period

    for (;;) {
        // Read sensor data
        uint16_t sensor_value = ADC_Read();

        // Send to processing queue
        xQueueSend(xProcessQueue, &sensor_value, pdMS_TO_TICKS(10));

        // Wait for next cycle (precise timing)
        vTaskDelayUntil(&xLastWakeTime, xFrequency);
    }
}

void vProcessingTask(void *pvParameters) {
    uint16_t received_data;

    for (;;) {
        // Block until data available
        if (xQueueReceive(xProcessQueue, &received_data, portMAX_DELAY) == pdPASS) {
            // Process data
            uint16_t result = ProcessSensorData(received_data);

            // Signal completion
            xSemaphoreGive(xProcessDoneSemaphore);
        }
    }
}

// Task creation in main()
void CreateTasks(void) {
    xTaskCreate(vSensorTask, "Sensor", STACK_SIZE_SENSOR, NULL,
                PRIORITY_SENSOR, &xSensorTaskHandle);
    xTaskCreate(vProcessingTask, "Process", STACK_SIZE_PROCESS, NULL,
                PRIORITY_PROCESSING, &xProcessTaskHandle);
}
```

## Queue Communication

```c
// Queue creation and usage
QueueHandle_t xDataQueue;
QueueHandle_t xCommandQueue;

void InitQueues(void) {
    // Create queue for 10 uint32_t items
    xDataQueue = xQueueCreate(10, sizeof(uint32_t));

    // Create queue for command structures
    xCommandQueue = xQueueCreate(5, sizeof(Command_t));

    if (xDataQueue == NULL || xCommandQueue == NULL) {
        // Handle error - insufficient heap
        Error_Handler();
    }
}

// Producer task
void vProducerTask(void *pvParameters) {
    uint32_t data = 0;

    for (;;) {
        data++;

        // Non-blocking send (timeout = 0)
        if (xQueueSend(xDataQueue, &data, 0) != pdPASS) {
            // Queue full - handle overflow
            DiscardOldData();
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// Consumer task
void vConsumerTask(void *pvParameters) {
    uint32_t received;

    for (;;) {
        // Block indefinitely until data available
        if (xQueueReceive(xDataQueue, &received, portMAX_DELAY) == pdPASS) {
            ProcessData(received);
        }
    }
}
```

## Mutex and Critical Sections

```c
SemaphoreHandle_t xI2CMutex;
SemaphoreHandle_t xUARTMutex;

void InitMutexes(void) {
    xI2CMutex = xSemaphoreCreateMutex();
    xUARTMutex = xSemaphoreCreateMutex();

    if (xI2CMutex == NULL || xUARTMutex == NULL) {
        Error_Handler();
    }
}

// Safe shared resource access
bool I2C_Write(uint8_t addr, uint8_t *data, size_t len) {
    // Take mutex with timeout
    if (xSemaphoreTake(xI2CMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        // Critical section - exclusive I2C access
        bool result = HAL_I2C_Write(addr, data, len);

        // Always release mutex
        xSemaphoreGive(xI2CMutex);

        return result;
    }

    return false;  // Timeout
}

// Very short critical section (disables interrupts)
void UpdateSharedCounter(void) {
    taskENTER_CRITICAL();
    g_shared_counter++;
    taskEXIT_CRITICAL();
}
```

## Binary Semaphores (Signaling)

```c
SemaphoreHandle_t xDataReadySemaphore;

// Interrupt signals task
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;

    // Signal from ISR
    xSemaphoreGiveFromISR(xDataReadySemaphore, &xHigherPriorityTaskWoken);

    // Yield if higher priority task woken
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

// Task waits for interrupt
void vADCTask(void *pvParameters) {
    for (;;) {
        // Wait for ADC completion (from ISR)
        if (xSemaphoreTake(xDataReadySemaphore, portMAX_DELAY) == pdTRUE) {
            uint16_t adc_value = HAL_ADC_GetValue(&hadc1);
            ProcessADCValue(adc_value);
        }
    }
}
```

## Software Timers

```c
TimerHandle_t xWatchdogTimer;
TimerHandle_t xBlinkTimer;

void vWatchdogCallback(TimerHandle_t xTimer) {
    // Periodic watchdog check
    if (!SystemHealthCheck()) {
        SystemReset();
    }
}

void vBlinkCallback(TimerHandle_t xTimer) {
    HAL_GPIO_TogglePin(LED_GPIO_Port, LED_Pin);
}

void InitTimers(void) {
    // One-shot timer
    xWatchdogTimer = xTimerCreate("Watchdog", pdMS_TO_TICKS(5000),
                                   pdTRUE, 0, vWatchdogCallback);

    // Auto-reload timer
    xBlinkTimer = xTimerCreate("Blink", pdMS_TO_TICKS(500),
                               pdTRUE, 0, vBlinkCallback);

    // Start timers
    xTimerStart(xWatchdogTimer, 0);
    xTimerStart(xBlinkTimer, 0);
}
```

## Event Groups

```c
EventGroupHandle_t xSystemEvents;

#define EVENT_SENSOR_READY   (1 << 0)
#define EVENT_COMM_READY     (1 << 1)
#define EVENT_CALIBRATED     (1 << 2)
#define EVENT_ALL_READY      (EVENT_SENSOR_READY | EVENT_COMM_READY | EVENT_CALIBRATED)

void vInitTask(void *pvParameters) {
    // Initialize subsystems
    InitSensor();
    xEventGroupSetBits(xSystemEvents, EVENT_SENSOR_READY);

    InitComm();
    xEventGroupSetBits(xSystemEvents, EVENT_COMM_READY);

    Calibrate();
    xEventGroupSetBits(xSystemEvents, EVENT_CALIBRATED);

    vTaskDelete(NULL);  // Delete init task
}

void vMainTask(void *pvParameters) {
    // Wait for all subsystems ready
    xEventGroupWaitBits(xSystemEvents, EVENT_ALL_READY, pdFALSE, pdTRUE, portMAX_DELAY);

    // System fully initialized
    for (;;) {
        RunMainLoop();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

## Memory Management

```c
// FreeRTOSConfig.h settings
#define configTOTAL_HEAP_SIZE           ((size_t)(20 * 1024))  // 20KB heap
#define configMINIMAL_STACK_SIZE        ((uint16_t)128)
#define configUSE_MALLOC_FAILED_HOOK    1

// Heap usage monitoring
void PrintHeapStats(void) {
    size_t free_heap = xPortGetFreeHeapSize();
    size_t min_ever_free = xPortGetMinimumEverFreeHeapSize();

    printf("Heap Free: %u bytes\n", free_heap);
    printf("Min Ever Free: %u bytes\n", min_ever_free);
}

// Stack overflow hook (enable in FreeRTOSConfig.h)
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    printf("STACK OVERFLOW: %s\n", pcTaskName);
    Error_Handler();
}

// Malloc failed hook
void vApplicationMallocFailedHook(void) {
    printf("MALLOC FAILED\n");
    Error_Handler();
}
```

## Task Notifications (Lightweight Alternative)

```c
TaskHandle_t xWorkerTaskHandle;

// ISR notifies task (faster than semaphore)
void EXTI_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;

    // Send notification with value
    xTaskNotifyFromISR(xWorkerTaskHandle, 0x01, eSetBits, &xHigherPriorityTaskWoken);

    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

// Task waits for notification
void vWorkerTask(void *pvParameters) {
    uint32_t ulNotificationValue;

    for (;;) {
        // Wait for notification (replaces semaphore)
        if (xTaskNotifyWait(0x00, 0xFFFFFFFF, &ulNotificationValue, portMAX_DELAY) == pdTRUE) {
            // Handle event based on notification value
            HandleEvent(ulNotificationValue);
        }
    }
}
```

## Best Practices

- Use `vTaskDelayUntil()` for periodic tasks (prevents drift)
- Keep ISRs short - defer work to tasks via queues/semaphores
- Size stacks appropriately (monitor with `uxTaskGetStackHighWaterMark()`)
- Use task notifications instead of semaphores when possible (lower overhead)
- Protect shared resources with mutexes, not critical sections (unless very short)
- Configure watchdog for production builds
- Monitor heap usage to prevent fragmentation
- Use priority inheritance mutexes to avoid priority inversion
