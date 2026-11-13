// =============================================================================
// recorrido_cache.s - Recorre un arreglo de 4 KB con paso de una linea.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// POR QUE EXISTE ESTE PROGRAMA
//
// El barrido de configuraciones (tools/barrido_cache.sh) salio completamente
// plano con los ocho programas del Proyecto I: la misma tasa de aciertos de
// 512 B a 16 KB, un rango de 32 veces. La causa no es que la cache no sirva,
// es que esos programas tocan dos o tres lineas distintas cada uno, asi que
// TODOS sus fallos son de arranque (compulsory): la primera vez que se toca
// una linea se falla por fuerza, y no hay geometria que lo evite. Sin un
// programa cuyo conjunto de trabajo no quepa, el barrido no puede medir nada.
//
// Este programa es ese caso. Recorre 128 lineas consecutivas en ciclo, con
// paso de 32 bytes para tocar una linea por acceso, y repite el recorrido
// cuatro veces. El patron ciclico es el peor caso de LRU: si el conjunto de
// trabajo no cabe, cuando se vuelve a la primera linea ya fue expulsada, y la
// tasa de aciertos se cae a cero en vez de degradarse poco a poco.
//
// QUE SE ESPERA, CALCULADO A MANO
//
// Conjunto de trabajo: 128 lineas x 32 B = 4096 B, el tamano exacto que pide
// el enunciado para L1-D. Capacidad en lineas de cada configuracion:
//
//     512 B ->  16 lineas      4 KB -> 128 lineas
//       1 KB ->  32 lineas      8 KB -> 256 lineas
//       2 KB ->  64 lineas     16 KB -> 512 lineas
//
// Con 128 o mas lineas de capacidad el recorrido cabe: la pasada 1 falla las
// 128 veces (arranque) y las pasadas 2, 3 y 4 aciertan siempre, o sea 384
// aciertos de 512 lecturas. Con menos de 128 lineas de capacidad el recorrido
// se atropella y las 512 lecturas fallan.
//
// Sumando la pasada de escritura (128 almacenamientos, que con
// no-write-allocate fallan los 128 en cualquier geometria, porque un
// almacenamiento que falla no trae la linea) y los 2 del guardado final:
//
//     cabe        384 aciertos de 642 accesos  ->  59.81 %
//     no cabe       0 aciertos de 642 accesos  ->   0.00 %
//
// El salto esta entre 2 KB y 4 KB, justo en la geometria que exige el
// enunciado. Eso no es casualidad: el conjunto de trabajo se escogio de 4 KB
// para que el barrido mida el punto de diseno y no un tamano cualquiera.
//
// La pasada de escritura no esta de adorno: deja un valor conocido en cada
// linea, para que la suma de las lecturas se pueda comprobar a mano, y ademas
// pone a trabajar el write buffer y el camino RAW (la primera lectura de cada
// linea llega cuando el almacenamiento de esa misma linea puede estar todavia
// en el buffer).
//
//     make correr PROG=recorrido_cache.s MOSTRAR=0x100 PALABRAS=2
//
// Resultados esperados:
//
//   r1   puntero al final                    0x00003000
//   r2   pasadas restantes                   0
//   r3   lineas contadas en la ultima pasada  128
//   r4   suma de las cuatro pasadas           32512      0x00007F00
//        = 4 x (0 + 1 + ... + 127) = 4 x 8128
//   r8   ultimo valor escrito + 1             128
//   memoria 0x100   r4                        32512      0x00007F00
//   memoria 0x104   r8                        128        0x00000080
//
// -----------------------------------------------------------------------------
// REGISTROS
// -----------------------------------------------------------------------------
//   r1   puntero que recorre el arreglo    r5   base del arreglo, 0x2000
//   r2   pasadas de lectura que faltan     r7   palabra leida
//   r3   lineas contadas en esta pasada     r8   valor a escribir, 0 a 127
//   r4   acumulador de lo leido
//
// Los numeros de la derecha cuentan bundles desde la etiqueta del lazo. Un
// valor producido en el bundle n se puede leer desde el n+3, igual que en el
// resto de los programas del proyecto.
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r5, #0x2000 | movi r2, #4 ;
        movi r1, #0x2000 | movi r4, #0 ;
        movi r3, #0      | movi r8, #0 ;
        - ;
        - ;

// -----------------------------------------------------------------------------
// Pasada de escritura: deja i en la primera palabra de la linea i.
//
// El contador de lineas va por la ALU corta (S3) porque las dos ALU anchas
// estan ocupadas avanzando el puntero y el valor, y la LSU esta en el
// almacenamiento: cuatro de las cinco ranuras trabajando en el mismo bundle.
// Cuenta hacia arriba y se compara contra 128, en vez de descontar hasta cero,
// porque add.s suma y no resta.
// -----------------------------------------------------------------------------
escribir:
        addi r1, r1, #32 | addi r8, r8, #1 | sw r8, #0(r1) | add.s r3, #1 ;     //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        cmpi r3, #128 ;                                                         //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        - | - | - | - | br.ne escribir ;                                        //  6
        - ;                                                                     //  7 delay slot

// Volver el puntero y el contador al inicio para la primera pasada de lectura
        movi r1, #0x2000 | movi r3, #0 ;
        - ;
        - ;

// -----------------------------------------------------------------------------
// Pasada de lectura: suma la primera palabra de cada linea.
//
// Son 8 bundles por linea y no se puede apretar mas sin desenrollar: el
// contador se lee tres bundles despues de incrementarlo, la bandera tres
// bundles despues del cmpi, y el dato cargado tres bundles despues del lw.
// -----------------------------------------------------------------------------
leer:
        addi r1, r1, #32 | - | lw r7, #0(r1) | add.s r3, #1 ;                   //  0
        - ;                                                                     //  1
        - ;                                                                     //  2
        cmpi r3, #128    | add r4, r4, r7 ;                                     //  3
        - ;                                                                     //  4
        - ;                                                                     //  5
        - | - | - | - | br.ne leer ;                                            //  6
        - ;                                                                     //  7 delay slot

// -----------------------------------------------------------------------------
// Fin de una pasada: descontar y, si faltan, volver a recorrer desde la base.
// -----------------------------------------------------------------------------
siguiente:
        movi r1, #0x2000 | subi r2, r2, #1 ;                                    //  0
        movi r3, #0 ;                                                           //  1
        - ;                                                                     //  2
        - ;                                                                     //  3
        cmpi r2, #0 ;                                                           //  4
        - ;                                                                     //  5
        - ;                                                                     //  6
        - | - | - | - | br.ne leer ;                                            //  7
        - ;                                                                     //  8 delay slot

// -----------------------------------------------------------------------------
// Guardar el resultado donde se pueda ver con MOSTRAR
// -----------------------------------------------------------------------------
fin:
        movi r6, #0x100 ;
        - ;
        - ;
        - | - | sw r4, #0(r6) ;
        - | - | sw r8, #4(r6) ;

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt
