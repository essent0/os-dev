#include "console.h"

#include "semihost.h"

#include "FreeRTOS.h"
#include "semphr.h"
#include "task.h"

#include <stdarg.h>
#include <stdio.h>

/* CMSDK APB UART0 on MPS2 AN385. TXFULL is STATE bit 0, RXFULL is bit 1. */
#define UART_BASE    0x40004000u
#define UART_REG( off )    ( *( volatile uint32_t * ) ( UART_BASE + ( off ) ) )

static SemaphoreHandle_t console_lock;
static volatile int poweroff_started;

void uart_init( void )
{
    UART_REG( 0x10 ) = 16; /* baud divider, must be >= 16 */
    UART_REG( 0x08 ) = 0x3; /* TX and RX enable */
}

static void uart_putc_raw( char c )
{
    uint32_t spins = 0;

    while( ( UART_REG( 0x04 ) & 1u ) != 0 )
    {
        if( ++spins > 1000000u )
        {
            break;
        }
    }

    UART_REG( 0x00 ) = ( uint8_t ) c;
}

void uart_putc( char c )
{
    if( c == '\n' )
    {
        uart_putc_raw( '\r' );
    }

    uart_putc_raw( c );
}

int uart_getc_nonblock( void )
{
    if( ( UART_REG( 0x04 ) & 2u ) == 0 )
    {
        return -1;
    }

    return ( int ) ( UART_REG( 0x00 ) & 0xffu );
}

void console_init( void )
{
    uart_init();
    if( console_lock == NULL )
    {
        console_lock = xSemaphoreCreateMutex();
    }
}

void console_write_raw( const char * s )
{
    if( s == NULL )
    {
        return;
    }

    while( *s != '\0' )
    {
        uart_putc( *s );
        s++;
    }
}

void console_write_hex( uint32_t value )
{
    int shift;

    for( shift = 28; shift >= 0; shift -= 4 )
    {
        uint32_t nibble = ( value >> shift ) & 0xfu;
        uart_putc( ( char ) ( nibble < 10 ? ( '0' + nibble ) : ( 'a' + nibble - 10 ) ) );
    }
}

void console_write_dec( unsigned long value )
{
    char buf[ 12 ];
    int i = 0;

    if( value == 0 )
    {
        uart_putc( '0' );
        return;
    }

    while( ( value > 0 ) && ( i < ( int ) sizeof( buf ) ) )
    {
        buf[ i++ ] = ( char ) ( '0' + ( value % 10u ) );
        value /= 10u;
    }

    while( i > 0 )
    {
        uart_putc( buf[ --i ] );
    }
}

void rtosdev_printf( const char * fmt, ... )
{
    char buf[ 256 ];
    va_list ap;
    int locked = 0;

    va_start( ap, fmt );
    ( void ) vsnprintf( buf, sizeof( buf ), fmt, ap );
    va_end( ap );
    buf[ sizeof( buf ) - 1 ] = '\0';

    if( ( console_lock != NULL ) &&
        ( xTaskGetSchedulerState() == taskSCHEDULER_RUNNING ) &&
        ( xPortIsInsideInterrupt() == pdFALSE ) )
    {
        ( void ) xSemaphoreTake( console_lock, portMAX_DELAY );
        locked = 1;
    }

    console_write_raw( buf );

    if( locked != 0 )
    {
        ( void ) xSemaphoreGive( console_lock );
    }
}

void rtosdev_poweroff( int status )
{
    if( poweroff_started != 0 )
    {
        for( ;; )
        {
        }
    }

    poweroff_started = 1;
    uart_init();
    console_write_raw( "RTOSDEV_POWEROFF\n" );
    semihost_exit( status );

    /* SYSRESETREQ. QEMU is started with -no-reboot, so a reset exits. */
    *( volatile uint32_t * ) 0xE000ED0C = 0x05FA0004u;
    for( ;; )
    {
    }
}
