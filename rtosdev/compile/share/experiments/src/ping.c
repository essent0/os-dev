#include "experiment.h"

#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#define PING_N    4

static QueueHandle_t ping_q;
static SemaphoreHandle_t ping_done;
static int ping_got;

static void ping_rx( void * arg )
{
    ( void ) arg;

    while( ping_got < PING_N )
    {
        int value = 0;

        if( xQueueReceive( ping_q, &value, pdMS_TO_TICKS( 2000 ) ) != pdPASS )
        {
            break;
        }

        rtosdev_printf( "ping recv %d\n", value );
        ping_got++;
    }

    ( void ) xSemaphoreGive( ping_done );
    vTaskDelete( NULL );
}

static void ping_tx( void * arg )
{
    int i;

    ( void ) arg;

    for( i = 1; i <= PING_N; i++ )
    {
        ( void ) xQueueSend( ping_q, &i, portMAX_DELAY );
        rtosdev_printf( "ping send %d\n", i );
    }

    vTaskDelete( NULL );
}

static int ping_run( void )
{
    ping_got = 0;
    ping_q = xQueueCreate( PING_N, sizeof( int ) );
    ping_done = xSemaphoreCreateBinary();
    if( ( ping_q == NULL ) || ( ping_done == NULL ) )
    {
        return 1;
    }

    if( xTaskCreate( ping_rx, "ping-rx", 512, NULL, tskIDLE_PRIORITY + 3, NULL ) != pdPASS )
    {
        return 1;
    }

    if( xTaskCreate( ping_tx, "ping-tx", 512, NULL, tskIDLE_PRIORITY + 2, NULL ) != pdPASS )
    {
        return 1;
    }

    if( xSemaphoreTake( ping_done, pdMS_TO_TICKS( 5000 ) ) != pdPASS )
    {
        return 1;
    }

    /* Let the sender finish and the idle task reap deleted tasks. */
    vTaskDelay( pdMS_TO_TICKS( 10 ) );
    return ping_got == PING_N ? 0 : 1;
}

RTOSDEV_EXPERIMENT( ping, ping_run );
