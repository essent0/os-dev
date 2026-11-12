# FreeRTOS helpers for the mps2-an385 image.
# pxCurrentTCB is only valid after vTaskStartScheduler has switched to a task.

define rtos-current
  if pxCurrentTCB == 0
    printf "scheduler has not started\n"
  else
    printf "task %s  priority %lu\n", pxCurrentTCB->pcTaskName, (unsigned long)pxCurrentTCB->uxPriority
  end
end
document rtos-current
Print the task in pxCurrentTCB. Continue into the scheduler first.
end

define rtos-faults
  break HardFault_Handler
  break rtosdev_assert_failed
  break vApplicationStackOverflowHook
  break vApplicationMallocFailedHook
end
document rtos-faults
Stop on a fault, a configASSERT, a stack overflow, or a failed allocation.
end
