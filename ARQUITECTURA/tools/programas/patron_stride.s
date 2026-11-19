// =============================================================================
// patron_stride.s - Acceso con PASO de una linea: 32 bytes.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Segundo de los tres programas de patrones de la Iteracion 5.
//
// PATRON: 1024 lecturas con paso de 32 bytes, que es exactamente el tamano de
// una linea. Toca la palabra 0 de 1024 lineas consecutivas, una sola vez cada
// una, cubriendo 32 KB desde 0x2000.
//
// POR QUE ESTE PASO Y NO OTRO
//
// El paso igual al tamano de linea es el que anula por completo la localidad
// espacial: cada acceso cae en una linea distinta, asi que traer la linea no
// sirve para nada mas. Es el complemento exacto de patron_secuencial.s, que
// hace el mismo numero de accesos y aprovecha las ocho palabras de cada linea.
//
// QUE SE ESPERA, CALCULADO A MANO
//
//   fallos de lectura   = 1024   una linea nueva por acceso, una sola pasada
//   aciertos de lectura = 0      no hay nada que reusar
//   tasa de aciertos    = 0.00 %
//
// El cero es exacto y por eso sirve de oraculo: con 1024 lineas distintas
// tocadas una sola vez, ninguna cache de ningun tamano puede acertar. Y como
// 1024 lineas son 32 KB, el conjunto tampoco cabe en la L2 de 16 KB, asi que
// los 1024 fallos llegan hasta memoria principal.
//
// Este programa es el peor caso de la jerarquia y el que mas presion pone
// sobre el bus de memoria: sirve para medir la utilizacion del ancho de banda
// que pide la seccion 5.3 del enunciado.
//
//     make correr PROG=patron_stride.s MOSTRAR=0x100 PALABRAS=1
//
// Resultados esperados:
//   r3   lineas contadas         1024
//   r1   puntero final           0x0000A000   (0x2000 + 1024 x 32)
//   r4   suma de lo leido        0            (la memoria arranca en cero)
//
// -----------------------------------------------------------------------------
// REGISTROS
//   r1  puntero         r3  contador
//   r4  acumulador      r7  palabra leida
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r1, #0x2000 | movi r3, #0 ;
        movi r4, #0 ;
        - ;
        - ;

// -----------------------------------------------------------------------------
// Paso de 32 bytes: una linea por acceso, sin reuso posible.
// -----------------------------------------------------------------------------
lazo:
        addi r1, r1, #32 | - | lw r7, #0(r1) | add.s r3, #1 ;                  //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        cmpi r3, #1024   | add r4, r4, r7 ;                                     //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        - | - | - | - | br.ne lazo ;                                            //  6
        - ;                                                                     //  7 delay slot

fin:
        movi r6, #0x100 ;
        - ;
        - ;
        - | - | sw r4, #0(r6) ;

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt
