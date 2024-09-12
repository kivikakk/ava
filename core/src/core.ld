OUTPUT_FORMAT(elf32-littleriscv)
OUTPUT_ARCH(riscv)
ENTRY(core_start)

SECTIONS {
    . = 0x40000000;

    .data : {
        *(.rodata*)
        *(.data*)
        *(.sdata*)
        *(.sbss*)
    }

    . = ALIGN(4);

    .bss : {
        *(.bss*)

        /* Ensure at least 10kb for the stack. */
        /* TODO: detect stack overrun. */
        . = 0x4001d800;
        sp_left = .;

        . = 0x40020000;
        sp_right = .;
    }

    . = 0x80000000;

    .text : {
        *(.text*)
    }

}
