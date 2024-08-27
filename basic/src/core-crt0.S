.section .text.head
.globl core_start
core_start:
        li sp, 0x40000400
        call core_start_zig
        j .
