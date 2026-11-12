#include "console.h"

#include "FreeRTOS.h"
#include "task.h"

void rtosdev_assert_failed( const char * file, unsigned long line )
{
    uart_init();
    console_write_raw( "RTOSDEV_ASSERT " );
    console_write_raw( file != NULL ? file : "?" );
    uart_putc( ':' );
    console_write_dec( line );
    uart_putc( '\n' );
    rtosdev_poweroff( 1 );
}

void vApplicationMallocFailedHook( void )
{
    uart_init();
    console_write_raw( "RTOSDEV_FAULT malloc\n" );
    rtosdev_poweroff( 1 );
}

void vApplicationStackOverflowHook( TaskHandle_t task, char * name )
{
    ( void ) task;
    uart_init();
    console_write_raw( "RTOSDEV_FAULT stack " );
    console_write_raw( name != NULL ? name : "?" );
    uart_putc( '\n' );
    rtosdev_poweroff( 1 );
}
