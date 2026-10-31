// =============================================================================
// contar_hasta_n.s - Un lazo que cuenta hasta N. El programa minimo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
//     make correr PROG=contar_hasta_n.s MOSTRAR=0x400 PALABRAS=2
//
// Cuenta de 1 a N guardando cada numero en memoria desde 0x400, y deja la
// suma 1 + 2 + ... + N en R6. Con N = 10 la suma es 55 y el ultimo numero
// guardado es 10.
//
// Es el ejemplo de referencia para escribir un programa de cero en este ISA.
// La guia completa, con los patrones de lazo, condicional y arreglo, esta en
// `docs/escribir_programas.md`.
//
// -----------------------------------------------------------------------------
// LO UNICO QUE HAY QUE RECORDAR PARA ESCRIBIRLO
// -----------------------------------------------------------------------------
// 1. Un bundle son cinco ranuras separadas por '|' y termina en ';'
//
//        S0 ALU | S1 ALU | S2 memoria | S3 cripto | S4 saltos ;
//
//    Las ranuras que no se usan van con '-'. Si solo se escribe una cosa, va
//    a S0, asi que una instruccion de memoria o un salto SIEMPRE necesitan
//    sus barras: `- | - | lw r1, #0(r2) ;`
//
// 2. Entre el bundle que produce un valor y el que lo lee tienen que pasar
//    TRES bundles. Eso vale tambien para las banderas: entre `cmpi` y el
//    `br` que las mira. El ensamblador avisa si falta alguno.
//
// 3. Despues de todo salto se ejecuta UN bundle mas, se tome o no: el delay
//    slot. Se deja vacio salvo que se sepa lo que se hace.
//
// Con eso se escribe cualquier lazo. El resto es aritmetica.
//
// -----------------------------------------------------------------------------
// EL ESQUELETO DE UN LAZO, QUE ES SIEMPRE EL MISMO
// -----------------------------------------------------------------------------
//        movi  contador, #N        preparar
//        ...
//   etiqueta:
//        ...el trabajo...
//        subi  contador, contador, #1
//        ...dos bundles...
//        cmpi  contador, #0
//        ...dos bundles...
//        - | - | - | - | br.ne etiqueta ;
//        - ;                        <- delay slot
// =============================================================================

.data
    .org 0x0400
resultados:
    .space 64                     // sitio para los N numeros

.text
    .org 0x0000

// -----------------------------------------------------------------------------
// Preparacion
// -----------------------------------------------------------------------------
//   r1  el numero actual, de 1 a N
//   r2  cuantas vueltas quedan
//   r3  donde se guarda el siguiente numero
//   r6  la suma acumulada

        movi r1, #1          | movi r2, #10 ;          // i = 1, quedan N = 10
        movi r3, #0x400      | movi r6, #0 ;           // puntero y suma
        - ;
        - ;

// -----------------------------------------------------------------------------
// El lazo
// -----------------------------------------------------------------------------
// Los dos bundles de trabajo usan cuatro ranuras entre los dos: las dos ALU
// para sumar y avanzar, la LSU para guardar y la ALU corta para el puntero.
// Lo que queda vacio son los bundles de latencia, que es lo que cuesta que el
// `cmpi` vea el `subi`.

lazo:
        add r6, r6, r1       | subi r2, r2, #1   | sw r1, #0(r3)   | add.s r3, #4 ;
        addi r1, r1, #1 ;
        - ;
        - ;
        cmpi r2, #0 ;
        - ;
        - ;
        - | - | - | - | br.ne lazo ;
        - ;                                              // delay slot

// -----------------------------------------------------------------------------
// Fin
// -----------------------------------------------------------------------------
// La suma queda en r6 y tambien en memoria, justo despues de los N numeros.

        - | - | sw r6, #0x440(r0) ;
        - ;
        - ;
        - | - | - | - | halt ;
        - ;
