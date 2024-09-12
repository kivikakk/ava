OUTPUT_FORMAT(elf32-littleriscv)
OUTPUT_ARCH(riscv)
ENTRY(core_start)

MEMORY {
    dmem (RW) : ORIGIN = 0x40000000, LENGTH = 128K
    imem (RX) : ORIGIN = 0x80000000, LENGTH = 1M
}

SECTIONS {
    .text 0x80000000 : {
        *(.text*)

        . = ALIGN(4);
        text_right = .;
    } > imem

    .data 0x40000000 : AT(text_right) {
        data_left = .;

        *(.rodata*)
        *(.data*)
        *(.sdata*)
        *(.sbss*)

        . = ALIGN(4);
        data_right = .;
    } > dmem

    .bss : {
        *(.bss*)

        /* Ensure at least 10kb for the stack. */
        /* TODO: detect stack overrun. */
        . = 0x4001d800;
        sp_left = .;

        . = 0x40020000;
        sp_right = .;
    } > dmem

}
