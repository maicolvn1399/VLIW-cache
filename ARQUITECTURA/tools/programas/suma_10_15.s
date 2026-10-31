// Suma 10 + 15 y deja el resultado en R3.
// Cada consumidor espera tres bundles desde el productor, como requiere el ISA.

        .data
        .org 0x0000
        .word 0, 0, 0, 0, 0, 0, 0, 0
        .word 0, 0, 0, 0, 0, 0, 0, 0

        .text
        .org 0x0000

inicio:
        movi r1, #10 | - | - ;
        movi r2, #15 | - | - ;
        - ;
        - ;
        add r3, r1, r2 | - | - ;
        - | - | - | - | halt ;
        - ;                                   // delay slot del halt
