// =============================================================================
// suma_vliw.s - El mismo calculo, desenrollado por cuatro.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Suma los cuadrados de las 64 palabras que hay en 0x100 y deja el resultado
// en 0x200, igual que suma_simple.s. La respuesta es la misma: 89440.
//
// -----------------------------------------------------------------------------
// QUE CAMBIA Y POR QUE IMPORTA
// -----------------------------------------------------------------------------
// En suma_simple.s cada vuelta del lazo depende de si misma de principio a
// fin: la carga alimenta al producto y el producto a la suma, y entre cada par
// hay que esperar los tres bundles de latencia del ISA. El bundle queda casi
// vacio no porque falten ranuras sino porque no hay nada independiente que
// meter en ellas.
//
// Aqui el lazo procesa CUATRO elementos por vuelta y lleva cuatro acumuladores
// parciales, de modo que ni los productos ni las sumas dependen entre si. Esa
// es toda la idea: el trabajo independiente de un lazo son sus otras vueltas,
// y desenrollarlo es ponerlas a la vista del planificador.
//
// Los cuatro acumuladores se juntan al final. La suma es asociativa, asi que
// el resultado es identico.
//
// -----------------------------------------------------------------------------
// SIGUE ESCRITO UNA OPERACION POR LINEA
// -----------------------------------------------------------------------------
// Desenrollar es una decision del programador; planificar es mecanico. Este
// archivo no tiene un solo bundle empacado a mano: quien los junta es
//
//     python3 tools/empacar.py tools/programas/suma_vliw.s -o <salida>
//
// que respeta la latencia, los puertos de escritura y el orden de la memoria.
// El makefile lo hace solo con `make vliw`.
//
// -----------------------------------------------------------------------------
// HASTA DONDE SE PUEDE LLEGAR
// -----------------------------------------------------------------------------
// El techo lo pone la LSU, que es una sola: dos accesos a memoria no caben en
// el mismo bundle. Con una carga por elemento, el limite de este lazo es un
// elemento por bundle. Las dos ALU y la ALU corta quedan disponibles para los
// productos y las sumas, que es justamente lo que el desenrollado les da.
//
//     make correr PROG=suma_vliw.s MOSTRAR=0x200 PALABRAS=1
// =============================================================================

.data
    .org 0x0100
// Las mismas 64 palabras que suma_simple.s
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

        movi r4, #0x100 ;             // puntero
        movi r3, #16 ;                // 16 vueltas de 4 elementos
        movi r6, #0 ;                 // acumulador 0
        movi r7, #0 ;                 // acumulador 1
        movi r8, #0 ;                 // acumulador 2
        movi r9, #0 ;                 // acumulador 3
        - ;
        - ;

lazo:
        - | - | lw r10, #0(r4) ;
        - | - | lw r11, #4(r4) ;
        - | - | lw r12, #8(r4) ;
        - | - | lw r13, #12(r4) ;
        addi r4, r4, #16 ;
        subi r3, r3, #1 ;
        mul r10, r10, r10 ;
        mul r11, r11, r11 ;
        mul r12, r12, r12 ;
        mul r13, r13, r13 ;
        add r6, r6, r10 ;
        add r7, r7, r11 ;
        add r8, r8, r12 ;
        add r9, r9, r13 ;
        cmpi r3, #0 ;
        - | - | - | - | br.ne lazo ;
        - ;

// Juntar los cuatro acumuladores parciales
        add r6, r6, r7 ;
        add r8, r8, r9 ;
        - ;
        - ;
        add r6, r6, r8 ;
        - ;
        - ;
        - | - | sw r6, #0x200(r0) ;
        - ;
        - ;
        - | - | - | - | halt ;
        - ;
