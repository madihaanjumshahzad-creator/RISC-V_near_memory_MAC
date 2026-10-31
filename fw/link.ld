MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0xC000 }
SECTIONS {
    .text : { *(.text.start) *(.text*) } > RAM
    .rodata : { *(.rodata*) *(.srodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss : { *(.bss*) *(.sbss*) *(COMMON) } > RAM
}
