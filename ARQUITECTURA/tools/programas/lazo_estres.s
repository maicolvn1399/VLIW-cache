// =============================================================================
// lazo_estres.s - Un lazo de 100 000 vueltas que ocupa los cinco slots.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Pensado para tener el procesador trabajando cerca de un millon de ciclos con
// todas sus unidades en uso: en un mismo bundle trabajan las dos ALU, la LSU,
// la ALU corta y la BRU. Al final, cada registro tiene un valor que se puede
// calcular a mano, asi que cualquier error de latencia, de escritura o de
// salto se nota en el resultado.
//
//     make correr PROG=lazo_estres.s MOSTRAR=0x200 PALABRAS=2
//
// Con N = 100 000 vueltas, los resultados esperados son:
//
//   r1   N                                     100000      0x000186A0
//   r2   suma de 0 a N-1, modulo 2^32          704982704   0x2A052EB0
//   r3   XOR de 0 a N-1 (da 0 porque N es      0           0x00000000
//        multiplo de 4)
//   r6   0, el contador
//   r7   N, contado por la ALU corta           100000      0x000186A0
//   r8   N-1, el ultimo valor leido            99999       0x0001869F
//   r9   suma de lo leido de memoria, igual    704982704   0x2A052EB0
//        a r2
//   r10  r2 AND r3 al final                    0           0x00000000
//   r11  OR de 1 a N                           131071      0x0001FFFF
//   r12  XOR de los valores de r7, 1 a N       100000      0x000186A0
//   memoria 0x200   N-1                        99999       0x0001869F
//   memoria 0x204   XOR de 0 a N-1             0           0x00000000
//
// Termina en 900 018 ciclos (9 bundles por vuelta).
//
// -----------------------------------------------------------------------------
// REGISTROS
// -----------------------------------------------------------------------------
//   r1   i, de 0 a N-1                   r7   vueltas, contadas por la ALU corta
//   r2   suma de i                       r8   i, leido de vuelta de memoria
//   r3   XOR de i                        r9   suma de lo leido de memoria
//   r4   0x200, direccion de trabajo     r10  r2 AND r3
//   r6   vueltas restantes               r11  OR de i+1
//                                        r12  XOR de r7, por la ALU corta
//
// Cada vuelta dura 9 bundles. Los numeros de la derecha cuentan desde lazo; un
// valor producido en el bundle n se puede leer desde el n+3.
// =============================================================================

        .text
        .org 0x0000

inicio:
        movi r1, #0      | movi r2, #0 ;
        movi r3, #0      | movi r4, #0x200 ;
        movi r6, #100000 | movi r7, #0 ;
        movi r9, #0      | movi r11, #0 ;
        movi r12, #0 ;
        - ;
        - ;

lazo:
// Cuatro slots: suma, XOR, guardar i en memoria y contar la vuelta
        add r2, r2, r1   | xor r3, r3, r1  | sw r1, #0(r4)  | add.s r7, #1 ;        //  0
// Avanzar i, descontar y leer de vuelta lo que se acaba de guardar
        addi r1, r1, #1  | subi r6, r6, #1 | lw r8, #0(r4) ;                         //  1
        - ;                                                                          //  2
        - ;                                                                          //  3
        cmpi r6, #0      | add r9, r9, r8 ;                                          //  4
        - ;                                                                          //  5
        - ;                                                                          //  6
// Los cinco slots ocupados en el mismo bundle, incluido el salto
        and r10, r2, r3  | or r11, r11, r1 | sw r3, #4(r4)  | xor.s r12, r7 | br.ne lazo ;  //  7
        - ;                                                                          //  8 delay slot

        - | - | - | - | halt ;
        - ;                                         // delay slot del halt