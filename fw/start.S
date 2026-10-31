# Reset entry: set the stack pointer, run main(), report its return value.
    .section .text.start
    .global _start
_start:
    li   sp, 0x00010000        # top of the 64 KiB RAM
    call main
    li   t0, 0x10000004        # OUT_EXIT
    sw   a0, 0(t0)
1:  j    1b
