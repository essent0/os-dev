#include "experiment.h"

#include "FreeRTOS.h"
#include "task.h"

static int hello_run( void )
{
    unsigned ticks;

    /* A non-zero tick means SysTick is reaching the scheduler. */
    vTaskDelay( pdMS_TO_TICKS( 20 ) );
    ticks = ( unsigned ) xTaskGetTickCount();

    rtosdev_printf( "version %s\n", tskKERNEL_VERSION_NUMBER );
    rtosdev_printf( "heap_free %u heap_min %u\n",
                    ( unsigned ) xPortGetFreeHeapSize(),
                    ( unsigned ) xPortGetMinimumEverFreeHeapSize() );
    rtosdev_printf( "tasks %u tick %u\n",
                    ( unsigned ) uxTaskGetNumberOfTasks(),
                    ticks );

    return ticks == 0u ? 1 : 0;
}

RTOSDEV_EXPERIMENT( hello, hello_run );
