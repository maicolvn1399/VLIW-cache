// =============================================================================
// fibonacci.s - Los primeros 47 numeros de Fibonacci, guardados en memoria.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Calcula F(0) a F(46) y guarda cada uno como una palabra de 32 bits desde la
// direccion 0x100. F(46) es el mayor que cabe en 32 bits con signo.
//
//     make correr PROG=fibonacci.s MOSTRAR=0x100 PALABRAS=47
//
// Resultados esperados:
//
//   memoria 0x100 + 4k   F(k), de F(0) = 0 a F(46) = 1 836 311 903 (0x6D73E55F)
//   r1                   F(47) = 2 971 215 073 (0xB11924E1), cabe solo sin signo
//   r2                   F(48), que ya desborda 32 bits: 0x1E8D0A40
//   r3                   0, el contador
//   r4                   0x100 + 47 * 4 = 0x1BC, el puntero despues del ultimo
//
// -----------------------------------------------------------------------------
// COMO ESTA ORGANIZADO EL LAZO
// -----------------------------------------------------------------------------
// Cada vuelta usa cuatro slots del mismo bundle a la vez: ALU-0 calcula el
// siguiente numero, ALU-1 descuenta el contador, la LSU guarda el numero
// actual y la ALU corta avanza el puntero. Despues hay que esperar la latencia
// de 3 bundles antes de usar los resultados.
//
//   r1  F(k), el actual          r4  puntero a la memoria
//   r2  F(k+1), el siguiente     r5  F(k+2), recien calculado
//   r3  vueltas restantes
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r1, #0      | movi r2, #1 ;
        movi r3, #47     | movi r4, #0x100 ;
        - ;
        - ;

lazo:
        add r5, r1, r2   | subi r3, r3, #1 | sw r1, #0(r4) | add.s r4, #4 ;   //  0
        - ;                                                                  //  1
        - ;                                                                  //  2
// r5 y r3 ya estan listos. Los dos MOV leen el r2 anterior, porque todos los
// slots de un bundle leen el estado previo a ese bundle.
        cmpi r3, #0      | mov r1, r2      | -             | mov.s r2, r5 ;  //  3
        - ;                                                                  //  4
        - ;                                                                  //  5
        - | - | - | - | br.ne lazo ;                                         //  6
        - ;                                                                  //  7 delay slot

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt