.section .text.head

.globl core_start
core_start:
        la sp, sp_right
        j core_start_zig
