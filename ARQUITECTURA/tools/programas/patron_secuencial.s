// =============================================================================
// patron_secuencial.s - Acceso SECUENCIAL: palabra por palabra.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Primero de los tres programas de patrones de acceso que pide la Iteracion 5
// (seccion 7.1.5: "benchmarks de distintos patrones de acceso a memoria:
// secuencial, aleatorio, stride").
//
// Los tres recorren el MISMO conjunto de trabajo, 1024 palabras de 4 KB en
// 0x2000, y hacen el MISMO numero de accesos, 1024 lecturas. Lo unico que
// cambia entre ellos es el orden en que tocan las palabras, asi que cualquier
// diferencia en tasa de aciertos, AMAT o ciclos es atribuible al patron y a
// nada mas. Esa es la razon de fijar el conjunto y la cuenta.
//
// PATRON: lee las 1024 palabras en orden, de la 0 a la 1023, avanzando 4 bytes.
//
// QUE SE ESPERA, CALCULADO A MANO
//
// Una linea son 32 bytes, 8 palabras. Recorriendo palabra por palabra, la
// primera de cada linea falla y las siete siguientes aciertan, porque el fallo
// trajo la linea entera. Son 1024 / 8 = 128 lineas:
//
//   fallos de lectura   = 128    uno por linea, todos de arranque
//   aciertos de lectura = 896    1024 - 128
//   tasa de aciertos    = 87.50 %
//
// Es el mejor caso de la jerarquia: maxima localidad espacial. Cada fallo paga
// la linea completa y despues se amortiza entre ocho accesos. El 87.5 % no es
// una medicion, es 7/8 exacto, y por eso sirve de oraculo.
//
//     make correr PROG=patron_secuencial.s MOSTRAR=0x100 PALABRAS=1
//
// Resultados esperados:
//   r4   suma de las 1024 palabras leidas    0  (la memoria arranca en cero)
//   r3   palabras contadas                   1024
//   r1   puntero final                       0x00003000
//   memoria 0x100                            r4
//
// -----------------------------------------------------------------------------
// REGISTROS
//   r1  puntero         r3  contador de palabras
//   r4  acumulador      r7  palabra leida
//
// Los numeros a la derecha cuentan bundles desde la etiqueta. Un valor
// producido en el bundle n se lee desde el n+3.
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r1, #0x2000 | movi r3, #0 ;
        movi r4, #0 ;
        - ;
        - ;

// -----------------------------------------------------------------------------
// Recorrido secuencial: paso de 4 bytes, una palabra por acceso.
//
// Ocho bundles por palabra, que es lo que imponen las latencias: el contador
// se lee tres bundles despues de incrementarlo, la bandera tres despues del
// cmpi, y el dato cargado tres despues del lw.
// -----------------------------------------------------------------------------
lazo:
        addi r1, r1, #4  | - | lw r7, #0(r1) | add.s r3, #1 ;                  //  0
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
