# Getting started

The scheduler is in `FreeRTOS-Kernel/tasks.c`. The Cortex-M3 port in `FreeRTOS-Kernel/portable/GCC/ARM_CM3/` is what actually swaps stacks. This image is one core (`configNUMBER_OF_CORES` is unset, so it is 1).

`compile/guest/main.c` creates the tasks, then calls `vTaskStartScheduler()`. That call does not return.

## Who runs next

`tasks.c` keeps one ready list per priority, `pxReadyTasksLists`. `pxCurrentTCB` is the running task.

`vTaskSwitchContext()` is the single-core switch. It is the `#if ( configNUMBER_OF_CORES == 1 )` definition. The function below it takes a core id and is the SMP build. After the stack-overflow check it calls `taskSELECT_HIGHEST_PRIORITY_TASK()`, which writes the next task into `pxCurrentTCB`.

This image sets `configUSE_PORT_OPTIMISED_TASK_SELECTION` to 1, so that macro is the second definition in `tasks.c`, not the generic loop. It asks the port for the highest set bit in `uxTopReadyPriority`, then takes the next task on that priority's list. Tasks at the same priority rotate. The bit scan is `portGET_HIGHEST_PRIORITY()` in `portable/GCC/ARM_CM3/portmacro.h` (`clz` on the ready bitmap).

`xTaskIncrementTick()` runs once per tick. It advances `xTickCount`, wakes delayed tasks whose time has come, and returns true when a higher-priority task is ready or the current task's time slice is over.

`vTaskStartScheduler()` creates the idle task and the timer task, sets `xSchedulerRunning`, and calls `xPortStartScheduler()`.

## How the CPU gets there

`portable/GCC/ARM_CM3/port.c`:

1. `xPortStartScheduler()` checks that SVCall and PendSV point at `vPortSVCHandler` and `xPortPendSVHandler`, starts SysTick (`vPortSetupTimerInterrupt()`), and calls `prvPortStartFirstTask()`.
2. `prvPortStartFirstTask()` enables interrupts and executes `svc 0`.
3. `vPortSVCHandler()` loads `pxCurrentTCB` and returns into the first task. That is the only start-up switch. Later switches do not go through SVCall.
4. `xPortSysTickHandler()` calls `xTaskIncrementTick()`. If a switch is required, it pends PendSV.
5. `xPortPendSVHandler()` saves r4–r11 on the task stack, calls `vTaskSwitchContext()`, then restores the task `pxCurrentTCB` now points at.

PendSV and SysTick sit at the lowest priority. A task switch requested from a syscall pends the same PendSV, so the decision stays in `vTaskSwitchContext()` and the register save stays in the port.

## Read in this order

1. `compile/guest/main.c` — `vTaskStartScheduler()`
2. `FreeRTOS-Kernel/tasks.c` — `vTaskStartScheduler()`, then `vTaskSwitchContext()`, then `xTaskIncrementTick()`
3. `FreeRTOS-Kernel/portable/GCC/ARM_CM3/port.c` — `xPortPendSVHandler()` and `xPortSysTickHandler()`
4. `FreeRTOS-Kernel/portable/GCC/ARM_CM3/portmacro.h` — `portGET_HIGHEST_PRIORITY()`
