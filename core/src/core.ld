OUTPUT_FORMAT(elf32-littleriscv)
OUTPUT_ARCH(riscv)
ENTRY(core_start)

SECTIONS {
    . = 0x0;

    .text : {
        *(.text*)
    }

    . = 0x40000000;

    .data : {
        *(.rodata*)
        *(.data*)
        *(.sdata*)
        *(.sbss*)
        *(.bss*)
    }
}
