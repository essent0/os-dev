#include "experiment.h"
#include "semihost.h"

#include "FreeRTOS.h"
#include "task.h"

#include <string.h>

extern const rtosdev_experiment_t __rtosdev_exp_start[];
extern const rtosdev_experiment_t __rtosdev_exp_end[];

static char cmdline[ 256 ];
static char exp_spec[ 160 ];

const rtosdev_experiment_t * rtosdev_find_experiment( const char * name )
{
    const rtosdev_experiment_t * exp;

    if( name == NULL )
    {
        return NULL;
    }

    for( exp = __rtosdev_exp_start; exp < __rtosdev_exp_end; exp++ )
    {
        if( ( exp->name != NULL ) && ( strcmp( exp->name, name ) == 0 ) )
        {
            return exp;
        }
    }

    return NULL;
}

void rtosdev_list_experiments( void )
{
    const rtosdev_experiment_t * exp;

    for( exp = __rtosdev_exp_start; exp < __rtosdev_exp_end; exp++ )
    {
        if( exp->name != NULL )
        {
            rtosdev_printf( "experiment %s\n", exp->name );
        }
    }
}

static const char * arg_value( const char * cmd, const char * key )
{
    size_t key_len = strlen( key );
    const char * p = cmd;

    while( ( p = strstr( p, key ) ) != NULL )
    {
        if( ( p == cmd ) || ( p[ -1 ] == ' ' ) )
        {
            return p + key_len;
        }

        p += key_len;
    }

    return NULL;
}

static int arg_is( const char * cmd, const char * key, char expect )
{
    const char * v = arg_value( cmd, key );

    return ( v != NULL ) && ( v[ 0 ] == expect ) &&
           ( ( v[ 1 ] == '\0' ) || ( v[ 1 ] == ' ' ) );
}

static void copy_token( char * dst, size_t dst_len, const char * src )
{
    size_t i = 0;

    while( ( src[ i ] != '\0' ) && ( src[ i ] != ' ' ) && ( ( i + 1 ) < dst_len ) )
    {
        dst[ i ] = src[ i ];
        i++;
    }

    dst[ i ] = '\0';
}

static int name_ok( const char * name )
{
    const char * p;

    if( ( name == NULL ) || ( name[ 0 ] == '\0' ) )
    {
        return 0;
    }

    for( p = name; *p != '\0'; p++ )
    {
        char c = *p;
        int alnum = ( ( c >= 'a' ) && ( c <= 'z' ) ) ||
                    ( ( c >= 'A' ) && ( c <= 'Z' ) ) ||
                    ( ( c >= '0' ) && ( c <= '9' ) );
        if( !alnum && ( c != '_' ) && ( c != '-' ) )
        {
            return 0;
        }
    }

    return 1;
}

static void experiment_task( void * arg )
{
    char * spec = arg;
    int failed = 0;

    while( ( spec != NULL ) && ( *spec != '\0' ) )
    {
        char * sep = strpbrk( spec, ",+" );
        const rtosdev_experiment_t * exp;
        int status = 1;

        if( sep != NULL )
        {
            *sep = '\0';
        }

        if( spec[ 0 ] != '\0' )
        {
            rtosdev_printf( "RTOSDEV_BEGIN %s\n", spec );
            exp = rtosdev_find_experiment( spec );
            if( exp == NULL )
            {
                rtosdev_printf( "unknown experiment %s\n", spec );
            }
            else
            {
                status = exp->fn();
            }

            rtosdev_printf( "RTOSDEV_END %s status=%d\n", spec, status );
            if( status != 0 )
            {
                failed = 1;
            }
        }

        if( sep == NULL )
        {
            break;
        }

        spec = sep + 1;
    }

    rtosdev_poweroff( failed ? 1 : 0 );
}

static void heartbeat_task( void * arg )
{
    ( void ) arg;

    for( ;; )
    {
        rtosdev_printf( "RTOSDEV_TICK %u\n", ( unsigned ) xTaskGetTickCount() );
        vTaskDelay( pdMS_TO_TICKS( 1000 ) );
    }
}

static void start_experiments( const char * spec )
{
    if( !name_ok( spec ) && ( strpbrk( spec, ",+" ) == NULL ) )
    {
        rtosdev_printf( "RTOSDEV_BEGIN %s\n", spec );
        rtosdev_printf( "bad experiment name\n" );
        rtosdev_printf( "RTOSDEV_END %s status=1\n", spec );
        rtosdev_poweroff( 1 );
    }

    ( void ) strncpy( exp_spec, spec, sizeof( exp_spec ) - 1 );
    exp_spec[ sizeof( exp_spec ) - 1 ] = '\0';
    ( void ) xTaskCreate( experiment_task, "exp", 1024, exp_spec, tskIDLE_PRIORITY + 2, NULL );
}

int main( void )
{
    int shell = 0;
    int run = 0;
    const char * exp;

    console_init();
    rtosdev_printf( "RTOSDEV_BOOT kernel=%s port=ARM_CM3 machine=mps2-an385\n",
                    tskKERNEL_VERSION_NUMBER );

    cmdline[ 0 ] = '\0';
    if( semihost_cmdline( cmdline, sizeof( cmdline ) ) != 0 )
    {
        cmdline[ 0 ] = '\0';
    }

    rtosdev_printf( "RTOSDEV_CMDLINE %s\n", cmdline[ 0 ] != '\0' ? cmdline : "(none)" );

    shell = arg_is( cmdline, "rtosdev.shell=", '1' );
    run = arg_is( cmdline, "rtosdev.run=", '1' );
    exp = arg_value( cmdline, "rtosdev.exp=" );

    if( shell != 0 )
    {
        void shell_task( void * arg );
        ( void ) xTaskCreate( shell_task, "shell", 1024, NULL, tskIDLE_PRIORITY + 2, NULL );
    }
    else if( run != 0 )
    {
        ( void ) xTaskCreate( heartbeat_task, "tick", 512, NULL, tskIDLE_PRIORITY + 1, NULL );
    }
    else
    {
        char spec[ 160 ];

        if( exp == NULL )
        {
            exp = "hello";
        }

        copy_token( spec, sizeof( spec ), exp );
        start_experiments( spec );
    }

    vTaskStartScheduler();
    console_write_raw( "RTOSDEV_FAULT scheduler returned\n" );
    rtosdev_poweroff( 1 );
    return 0;
}
