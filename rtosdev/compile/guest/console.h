#ifndef RTOSDEV_CONSOLE_H
#define RTOSDEV_CONSOLE_H

#include <stddef.h>
#include <stdint.h>

void uart_init( void );
void uart_putc( char c );
int uart_getc_nonblock( void );

void console_init( void );
void console_write_raw( const char * s );
void console_write_hex( uint32_t value );
void console_write_dec( unsigned long value );
void rtosdev_printf( const char * fmt, ... );

void rtosdev_poweroff( int status );
int rtosdev_print_tasks( void );

#endif
