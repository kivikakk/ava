ENTRY(core_start)
OUTPUT_FORMAT(elf32-littleriscv)

SECTIONS {
    . = 0x0;

    .text : {
        *(.text*)
    }
}
