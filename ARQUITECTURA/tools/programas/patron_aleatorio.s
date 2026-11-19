// =============================================================================
// patron_aleatorio.s - Acceso ALEATORIO dentro de la misma region del stride.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Tercero de los tres programas de patrones de la Iteracion 5.
//
// PATRON: 1024 lecturas en posiciones pseudoaleatorias dentro de la MISMA
// region de 32 KB que recorre patron_stride.s, alineadas a linea.
//
// POR QUE SE COMPARA CONTRA EL STRIDE Y NO CONTRA EL SECUENCIAL
//
// Los tres hacen 1024 lecturas, pero no tocan lo mismo:
//
//   secuencial  paso de 4 B   ->  toca  128 lineas (4 KB), ocho accesos por linea
//   stride      paso de 32 B  ->  toca 1024 lineas (32 KB), uno por linea
//   aleatorio   al azar       ->  toca ~647 lineas de esas mismas 1024
//
// El aleatorio y el stride recorren la misma region de 32 KB, asi que son
// directamente comparables: la unica diferencia entre ellos es el ORDEN. El
// stride visita 1024 lineas distintas y nunca repite, de modo que no puede
// acertar jamas. El aleatorio repite por casualidad, y esos reencuentros son
// los unicos aciertos que puede tener. Medir cuantos sobreviven es lo que dice
// cuanta localidad temporal accidental logra capturar la cache.
//
// El secuencial queda como referencia del mejor caso, con localidad espacial
// perfecta.
//
// QUE SE ESPERA
//
// A diferencia de los otros dos, aqui la tasa de aciertos NO es calculable a
// mano: depende de cuantas lineas repite el generador y de cuales siguen en la
// cache cuando vuelven a salir. Por el problema del cumpleanos, 1024 tiradas
// sobre 1024 lineas tocan unas 1024 x (1 - 1/e) = 647 distintas, asi que hay
// unas 377 repeticiones; cuantas de ellas acierten es justamente la medicion.
//
// Lo que si es oraculo es el DATO: la secuencia del generador es determinista,
// asi que el programa siempre lee las mismas posiciones y deja la misma suma.
//
// EL GENERADOR
//
// xorshift32, el de Marsaglia:   x ^= x << 13;  x ^= x >> 17;  x ^= x << 5
//
// Se escogio porque usa solo desplazamientos y XOR, que la ALU ya tiene, sin
// multiplicacion ni division. La semilla es 0x12345, que cabe en el campo
// inmediato de 19 bits con signo del ISA; cualquier valor sirve mientras no
// sea cero, porque el cero es punto fijo del generador.
//
// AVISO PARA EL ANALISIS
//
// El generador son seis operaciones encadenadas, y con la latencia de tres
// bundles del procesador eso son 18 bundles por iteracion que no tocan
// memoria. Entonces el IPC y la ocupacion de este programa hablan del costo
// del generador, no del patron de acceso. Para comparar los tres patrones hay
// que mirar la TASA DE ACIERTOS y el AMAT, que son por acceso y no por ciclo.
//
//     make correr PROG=patron_aleatorio.s MOSTRAR=0x100 PALABRAS=1
//
// Resultados esperados:
//   r3   accesos contados      1024
//   r2   estado final del generador (determinista)
//   r4   suma de lo leido      0   (la memoria arranca en cero)
//
// -----------------------------------------------------------------------------
// REGISTROS
//   r1  base de la region, 0x2000      r2  estado del generador
//   r3  contador de accesos            r4  acumulador
//   r5  direccion calculada            r7  palabra leida
//   r8  temporal del generador         r9  mascara 1023
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r1, #0x2000      | movi r2, #0x12345 ;
        movi r3, #0           | movi r4, #0 ;
        movi r9, #1023 ;
        - ;
        - ;

// -----------------------------------------------------------------------------
// Una iteracion: avanzar el generador, sacar un indice de linea, leer.
//
// Cada operacion depende de la anterior, asi que van separadas tres bundles.
// No hay forma de apretarlo sin desenrollar o segmentar a mano, y eso
// cambiaria lo que el programa mide.
// -----------------------------------------------------------------------------
lazo:
        slli r8, r2, #13 ;                                                      //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        xor  r2, r2, r8 ;                                                       //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        srli r8, r2, #17 ;                                                      //  6
        - ;                                                                     //  7
        - ;                                                                     //  8
        xor  r2, r2, r8 ;                                                       //  9
        - ;                                                                     // 10
        - ;                                                                     // 11
        slli r8, r2, #5 ;                                                       // 12
        - ;                                                                     // 13
        - ;                                                                     // 14
        xor  r2, r2, r8 ;                                                       // 15
        - ;                                                                     // 16
        - ;                                                                     // 17
        and  r8, r2, r9 ;                                                       // 18  indice 0..1023
        - ;                                                                     // 19
        - ;                                                                     // 20
        slli r8, r8, #5 ;                                                       // 21  x 32: alinea a linea
        - ;                                                                     // 22
        - ;                                                                     // 23
        add  r5, r1, r8 ;                                                       // 24  direccion
        - ;                                                                     // 25
        - ;                                                                     // 26
        - | - | lw r7, #0(r5) | add.s r3, #1 ;                                  // 27
        - ;                                                                     // 28
        - ;                                                                     // 29
        cmpi r3, #1024        | add r4, r4, r7 ;                                // 30
        - ;                                                                     // 31
        - ;                                                                     // 32
        - | - | - | - | br.ne lazo ;                                            // 33
        - ;                                                                     // 34 delay slot

fin:
        movi r6, #0x100 ;
        - ;
        - ;
        - | - | sw r4, #0(r6) ;

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt
