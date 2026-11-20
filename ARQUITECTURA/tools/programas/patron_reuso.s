// =============================================================================
// patron_reuso.s - Dos pasadas sobre un arreglo que cabe en L2 y no en L1.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Cuarto programa de patrones de la Iteracion 5.
//
// PATRON: dos pasadas identicas de 256 lecturas con paso de 32 bytes sobre
// 8 KB desde 0x2000. Cada lectura toca la palabra 0 de una linea distinta.
//
// POR QUE ESTE TAMANO
//
// Los otros tres patrones no distinguen a la L2: el secuencial y el stride
// tocan cada linea una sola vez, asi que todo fallo de L1 es de arranque y
// tambien falla en L2. Para que la L2 sirva hace falta REUSO a una distancia
// que la L1 no alcance a cubrir:
//
//   8 KB = 256 lineas = el doble de la L1 (4 KB) y la mitad de la L2 (16 KB)
//
// QUE SE ESPERA, CALCULADO A MANO
//
// L1 (64 conjuntos x 2 vias): las 256 lineas caen 4 por conjunto. Con LRU
// sobre un recorrido ciclico de 4 lineas en 2 vias, cuando la pasada vuelve a
// una linea ya la expulsaron las dos siguientes de su conjunto. Ninguna
// lectura acierta:
//
//   fallos de lectura de L1   = 512   (256 por pasada)
//   aciertos de lectura de L1 = 0
//
// L2 (128 conjuntos x 4 vias): las 256 lineas caen 2 por conjunto y caben
// todas. La primera pasada las trae de memoria y la segunda las encuentra:
//
//   fallos de lectura de L2   = 256   (primera pasada, de arranque)
//   aciertos de lectura de L2 = 256   (segunda pasada)
//   invalidaciones hacia atras = 0    (la L2 no expulsa nada)
//
// Las invalidaciones no se fuerzan: para que aparezcan hace falta un arreglo
// de mas de 16 KB. Aqui se mide que con reuso dentro de la L2 son cero.
//
//     make correr PROG=patron_reuso.s MOSTRAR=0x100 PALABRAS=1
//
// Resultados esperados:
//   r3   lineas de la ultima pasada  256
//   r5   pasadas                     2
//   r1   puntero final               0x00004000   (0x2000 + 256 x 32)
//   r4   suma de lo leido            0            (la memoria arranca en cero)
//
// -----------------------------------------------------------------------------
// REGISTROS
//   r1  puntero         r3  contador de lineas     r5  contador de pasadas
//   r4  acumulador      r7  palabra leida
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r4, #0 | movi r5, #0 ;

// -----------------------------------------------------------------------------
// Una pasada: 256 lineas con paso de 32 bytes
// -----------------------------------------------------------------------------
pasada:
        movi r1, #0x2000 | movi r3, #0 ;                                        //  0
        - ;                                                                     //  1
        - ;                                                                     //  2

lazo:
        addi r1, r1, #32 | - | lw r7, #0(r1) | add.s r3, #1 ;                  //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        cmpi r3, #256    | add r4, r4, r7 ;                                     //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        - | - | - | - | br.ne lazo ;                                            //  6
        - ;                                                                     //  7 delay slot

// -----------------------------------------------------------------------------
// Fin de una pasada: se repite una vez
// -----------------------------------------------------------------------------
        - | - | - | add.s r5, #1 ;                                             //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        cmpi r5, #2 ;                                                           //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        - | - | - | - | br.ne pasada ;                                          //  6
        - ;                                                                     //  7 delay slot

fin:
        movi r6, #0x100 ;
        - ;
        - ;
        - | - | sw r4, #0(r6) ;

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt
