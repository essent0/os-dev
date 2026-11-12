#include "semihost.h"

#include <stdint.h>

/* ARM semihosting. QEMU handles the bkpt when started with
 * -semihosting-config enable=on,target=native. */
#define SEMI_SYS_GET_CMDLINE      0x15u
#define SEMI_SYS_EXIT_EXTENDED    0x20u
#define ADP_Stopped_ApplicationExit 0x20026u

static uint32_t semihost( uint32_t op, uint32_t arg )
{
    register uint32_t r0 asm( "r0" ) = op;
    register uint32_t r1 asm( "r1" ) = arg;

    __asm volatile ( "bkpt 0xAB" : "+r" ( r0 ) : "r" ( r1 ) : "memory" );
    return r0;
}

int semihost_cmdline( char * buf, size_t len )
{
    uint32_t block[ 2 ];

    if( ( buf == 0 ) || ( len < 2 ) )
    {
        return -1;
    }

    buf[ 0 ] = '\0';
    block[ 0 ] = ( uint32_t ) buf;
    block[ 1 ] = ( uint32_t ) len;
    if( semihost( SEMI_SYS_GET_CMDLINE, ( uint32_t ) block ) != 0 )
    {
        buf[ 0 ] = '\0';
        return -1;
    }

    buf[ len - 1 ] = '\0';
    return 0;
}

void semihost_exit( int status )
{
    uint32_t args[ 2 ];

    args[ 0 ] = ADP_Stopped_ApplicationExit;
    args[ 1 ] = ( uint32_t ) status;
    ( void ) semihost( SEMI_SYS_EXIT_EXTENDED, ( uint32_t ) args );

    /* Older M-profile stubs take the reason in r1 directly and ignore status. */
    ( void ) semihost( 0x18u, status == 0 ? ADP_Stopped_ApplicationExit : 0x20023u );
}
