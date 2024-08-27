.section .text.head
.globl core_start
core_start:
        li sp, 0x40001000  // Must correspond with avasoc's DMEM_BYTES.
        j core_start_zig
