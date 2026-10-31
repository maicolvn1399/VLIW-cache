// =============================================================================
// suma_simple.s - La version sin paralelismo, para comparar.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Suma los cuadrados de las 64 palabras que hay en 0x100 y deja el resultado
// en 0x200. La respuesta es 89440.
//
// Una operacion por bundle, que es la forma natural de escribirlo y es lo que
// emite un generador de codigo sin planificacion. La cadena
//
//     lw r5,#0(r4)  ->  mul r5,r5,r5  ->  add r6,r6,r5
//
// cuesta seis bundles de pura latencia, con las cinco ranuras libres mientras
// espera. El procesador no esta ocioso por culpa del hardware: el programa no
// le esta dando trabajo independiente que hacer.
//
//     make correr PROG=suma_simple.s MOSTRAR=0x200 PALABRAS=1
//
// Su pareja es suma_vliw.s, que calcula lo mismo desenrollando el lazo.
// `make vliw` corre las dos y compara ciclos.
// =============================================================================

.data
    .org 0x0100
// 64 palabras: 1, 2, 3 ... 64. La suma de sus cuadrados es 89440.
datos:
    .word 1,  2,  3,  4,  5,  6,  7,  8
    .word 9,  10, 11, 12, 13, 14, 15, 16
    .word 17, 18, 19, 20, 21, 22, 23, 24
    .word 25, 26, 27, 28, 29, 30, 31, 32
    .word 33, 34, 35, 36, 37, 38, 39, 40
    .word 41, 42, 43, 44, 45, 46, 47, 48
    .word 49, 50, 51, 52, 53, 54, 55, 56
    .word 57, 58, 59, 60, 61, 62, 63, 64

    .org 0x0200
resultado:
    .word 0

.text
    .org 0x0000

        movi r4, #0x100 ;             // puntero al vector
        movi r3, #64 ;                // cuantos quedan
        movi r6, #0 ;                 // acumulador
        - ;

lazo:
        - | - | lw r5, #0(r4) ;
        - ;
        - ;
        mul r5, r5, r5 ;
        - ;
        - ;
        add r6, r6, r5 ;
        addi r4, r4, #4 ;
        subi r3, r3, #1 ;
        - ;
        - ;
        cmpi r3, #0 ;
        - ;
        - ;
        - | - | - | - | br.ne lazo ;
        - ;

        - | - | sw r6, #0x200(r0) ;
        - ;
        - ;
        - | - | - | - | halt ;
        - ;
