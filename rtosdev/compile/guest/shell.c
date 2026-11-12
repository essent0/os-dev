#include "experiment.h"

#include "FreeRTOS.h"
#include "task.h"

#include <string.h>

int rtosdev_print_tasks( void )
{
    UBaseType_t count;
    UBaseType_t i;
    TaskStatus_t * status;

    count = uxTaskGetNumberOfTasks();
    status = pvPortMalloc( ( count + 2u ) * sizeof( *status ) );
    if( status == NULL )
    {
        rtosdev_printf( "task list: out of memory\n" );
        return -1;
    }

    count = uxTaskGetSystemState( status, count + 2u, NULL );
    for( i = 0; i < count; i++ )
    {
        rtosdev_printf( "task %s pri=%u state=%u watermark=%u\n",
                        status[ i ].pcTaskName,
                        ( unsigned ) status[ i ].uxCurrentPriority,
                        ( unsigned ) status[ i ].eCurrentState,
                        ( unsigned ) status[ i ].usStackHighWaterMark );
    }

    vPortFree( status );
    return ( int ) count;
}

static void cmd_run( const char * name )
{
    const rtosdev_experiment_t * exp;
    int status;

    if( ( name == NULL ) || ( name[ 0 ] == '\0' ) )
    {
        rtosdev_printf( "usage: run NAME\n" );
        return;
    }

    exp = rtosdev_find_experiment( name );
    rtosdev_printf( "RTOSDEV_BEGIN %s\n", name );
    if( exp == NULL )
    {
        rtosdev_printf( "unknown experiment %s\n", name );
        status = 1;
    }
    else
    {
        status = exp->fn();
    }

    rtosdev_printf( "RTOSDEV_END %s status=%d\n", name, status );
}

static void dispatch( char * line )
{
    char * cmd;
    char * arg;

    cmd = line;
    while( ( *cmd == ' ' ) || ( *cmd == '\t' ) )
    {
        cmd++;
    }

    if( *cmd == '\0' )
    {
        return;
    }

    arg = cmd;
    while( ( *arg != '\0' ) && ( *arg != ' ' ) && ( *arg != '\t' ) )
    {
        arg++;
    }

    if( *arg != '\0' )
    {
        *arg = '\0';
        arg++;
        while( ( *arg == ' ' ) || ( *arg == '\t' ) )
        {
            arg++;
        }
    }

    if( ( strcmp( cmd, "help" ) == 0 ) || ( strcmp( cmd, "?" ) == 0 ) )
    {
        rtosdev_printf( "help        this list\n" );
        rtosdev_printf( "version     kernel version\n" );
        rtosdev_printf( "tasks       task name, priority, state, stack watermark\n" );
        rtosdev_printf( "heap        free and minimum free heap\n" );
        rtosdev_printf( "uptime      tick count\n" );
        rtosdev_printf( "experiments compiled-in experiment names\n" );
        rtosdev_printf( "run NAME    run one experiment, stay in the shell\n" );
        rtosdev_printf( "poweroff    shut QEMU down\n" );
    }
    else if( strcmp( cmd, "version" ) == 0 )
    {
        rtosdev_printf( "%s ARM_CM3 mps2-an385\n", tskKERNEL_VERSION_NUMBER );
    }
    else if( ( strcmp( cmd, "tasks" ) == 0 ) || ( strcmp( cmd, "ps" ) == 0 ) )
    {
        ( void ) rtosdev_print_tasks();
    }
    else if( strcmp( cmd, "heap" ) == 0 )
    {
        rtosdev_printf( "heap_free %u heap_min %u\n",
                        ( unsigned ) xPortGetFreeHeapSize(),
                        ( unsigned ) xPortGetMinimumEverFreeHeapSize() );
    }
    else if( strcmp( cmd, "uptime" ) == 0 )
    {
        TickType_t ticks = xTaskGetTickCount();
        rtosdev_printf( "tick %u ms %u\n",
                        ( unsigned ) ticks,
                        ( unsigned ) ( ticks * portTICK_PERIOD_MS ) );
    }
    else if( strcmp( cmd, "experiments" ) == 0 )
    {
        rtosdev_list_experiments();
    }
    else if( strcmp( cmd, "run" ) == 0 )
    {
        cmd_run( arg );
    }
    else if( ( strcmp( cmd, "poweroff" ) == 0 ) || ( strcmp( cmd, "exit" ) == 0 ) )
    {
        rtosdev_poweroff( 0 );
    }
    else
    {
        rtosdev_printf( "unknown command %s\n", cmd );
    }
}

static void read_line( char * buf, size_t len )
{
    size_t n = 0;

    for( ;; )
    {
        int c = uart_getc_nonblock();

        if( c < 0 )
        {
            vTaskDelay( 1 );
            continue;
        }

        if( ( c == '\r' ) || ( c == '\n' ) )
        {
            break;
        }

        if( ( n + 1 ) < len )
        {
            buf[ n++ ] = ( char ) c;
        }
    }

    buf[ n ] = '\0';
}

void shell_task( void * arg )
{
    char line[ 96 ];

    ( void ) arg;
    rtosdev_printf( "RTOSDEV_SHELL\n" );
    rtosdev_printf( "commands: help version tasks heap uptime experiments run poweroff\n" );

    for( ;; )
    {
        rtosdev_printf( "rtosdev> " );
        read_line( line, sizeof( line ) );
        dispatch( line );
    }
}
