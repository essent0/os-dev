/*
 * QEMU loads ELF segments at p_paddr. .data has no AT(), so its load
 * address is RAM and the startup code must not copy it out of flash.
 * Boot the ELF (freertos.elf), not a raw binary.
 */
ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    RAM (rw)   : ORIGIN = 0x20000000, LENGTH = 4M
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_Min_Stack_Size = 0x1000;

SECTIONS
{
    .isr_vector :
    {
        __vector_table = .;
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } > FLASH

    .text :
    {
        *(.text*)
        *(.rodata*)
        . = ALIGN(8);
    } > FLASH

    .experiments ALIGN(8) :
    {
        __rtosdev_exp_start = .;
        KEEP(*(rtosdev_experiments))
        __rtosdev_exp_end = .;
    } > FLASH

    .data :
    {
        . = ALIGN(8);
        _sdata = .;
        *(.data*)
        . = ALIGN(8);
        _edata = .;
    } > RAM

    .bss :
    {
        . = ALIGN(8);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(8);
        _ebss = .;
        PROVIDE(end = .);
        PROVIDE(_end = .);
    } > RAM

    __StackTop = _estack;
    __StackLimit = __StackTop - _Min_Stack_Size;
    ASSERT(__StackLimit >= _ebss, "RAM overflow: bss overlaps the main stack")

    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.comment)
        *(.note*)
    }
}
