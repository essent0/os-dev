#include "console.h"

#include <stdint.h>

extern uint32_t _sbss;
extern uint32_t _ebss;
extern uint32_t _estack;
extern uint32_t __vector_table;

void Reset_Handler( void );
void Default_Handler( void );
void HardFault_Handler( void );
void HardFault_C( uint32_t * stacked );

void vPortSVCHandler( void );
void xPortPendSVHandler( void );
void xPortSysTickHandler( void );

extern int main( void );

/* 16 system exceptions + 48 IRQs. 64 entries, 256-byte aligned for VTOR. */
__attribute__( ( section( ".isr_vector" ), used, aligned( 256 ) ) )
static const uintptr_t isr_vector[ 64 ] =
{
    ( uintptr_t ) &_estack,
    ( uintptr_t ) Reset_Handler,
    ( uintptr_t ) Default_Handler,      /* NMI */
    ( uintptr_t ) HardFault_Handler,
    ( uintptr_t ) Default_Handler,      /* MemManage */
    ( uintptr_t ) Default_Handler,      /* BusFault */
    ( uintptr_t ) Default_Handler,      /* UsageFault */
    0, 0, 0, 0,                         /* reserved */
    ( uintptr_t ) vPortSVCHandler,      /* SVCall, vector 11 */
    ( uintptr_t ) Default_Handler,      /* DebugMon */
    0,                                  /* reserved */
    ( uintptr_t ) xPortPendSVHandler,   /* PendSV, vector 14 */
    ( uintptr_t ) xPortSysTickHandler,
    [ 16 ... 63 ] = ( uintptr_t ) Default_Handler
};

void Reset_Handler( void )
{
    uint32_t * bss;

    for( bss = &_sbss; bss < &_ebss; bss++ )
    {
        *bss = 0;
    }

    /* The port checks VTOR for SVC and PendSV. Point it at this table. */
    *( volatile uint32_t * ) 0xE000ED08 = ( uint32_t ) &__vector_table;

    ( void ) main();
    for( ;; )
    {
    }
}

void Default_Handler( void )
{
    uint32_t ipsr;

    __asm volatile ( "mrs %0, ipsr" : "=r" ( ipsr ) );
    uart_init();
    console_write_raw( "RTOSDEV_FAULT exception " );
    console_write_hex( ipsr );
    uart_putc( '\n' );
    rtosdev_poweroff( 1 );
}

void HardFault_C( uint32_t * stacked )
{
    uart_init();
    console_write_raw( "RTOSDEV_FAULT hardfault pc=" );
    console_write_hex( stacked[ 6 ] );
    console_write_raw( " lr=" );
    console_write_hex( stacked[ 5 ] );
    uart_putc( '\n' );
    rtosdev_poweroff( 1 );
}

__attribute__( ( naked ) ) void HardFault_Handler( void )
{
    __asm volatile (
        "tst lr, #4        \n"
        "ite eq            \n"
        "mrseq r0, msp     \n"
        "mrsne r0, psp     \n"
        "b HardFault_C     \n"
        );
}
