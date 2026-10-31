// =============================================================================
// estadisticas.s - Suma, maximo, minimo, negativos y promedio de un arreglo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Recorre ocho palabras con signo y deja en memoria seis resultados:
//
//   arreglo   15, -3, 42, 7, -20, 8, 100, 6
//
//   0x40  suma       155   0x0000009B
//   0x44  maximo     100   0x00000064
//   0x48  minimo     -20   0xFFFFFFEC
//   0x4C  negativos    2   0x00000002
//   0x50  promedio    19   0x00000013   (155 / 8 con __div32)
//   0x54  residuo      3   0x00000003
//
// -----------------------------------------------------------------------------
// QUE EJERCITA
// -----------------------------------------------------------------------------
// - lw.inc para recorrer el arreglo sin gastar una ALU en el puntero
// - el maximo y el minimo se actualizan sin saltos, multiplicando la
//   diferencia por un 0 o un 1. Para el maximo ese bit sale de cmp y setcc;
//   para el minimo, del signo de x - min, que no toca las banderas
// - setcc y cmpi en el mismo bundle: setcc lee las banderas previas al bundle,
//   asi que la comparacion del contador puede emitirse ahi mismo
// - un lazo con br.ne y su delay slot aprovechado con dos sumas
// - una llamada a __div32 con jal y el retorno a dos bundles del salto
//
// -----------------------------------------------------------------------------
// REGISTROS
// -----------------------------------------------------------------------------
//   r1  elemento actual             r8   suma
//   r2  x - max, luego por bandera  r9   maximo
//   r3  x - min, luego por bandera  r10  minimo
//   r4  bandera x >= max            r11  cantidad de negativos
//   r5  bandera x <  min            r12  vueltas restantes
//   r6  bit de signo de x           r13  puntero al arreglo
//                                   r14  base de los resultados
//
// R0 no es cero cableado en este ISA, asi que ninguna direccion se arma sobre
// r0: las dos bases se cargan con movi.
//
// El signo de x - min vale como "x < min" mientras la resta no desborde, y con
// valores que caben en el inmediato de 19 bits no puede desbordar.
// =============================================================================

        .data
        .org 0x0000

arreglo:
        .word 15, -3, 42, 7
        .word -20, 8, 100, 6

        .org 0x0040
resultados:
        .space 24

// =============================================================================

        .text
        .org 0x0000

inicio:
// El maximo arranca en el inmediato mas chico y el minimo en el mas grande,
// asi el primer elemento reemplaza a los dos
        movi r8, #0          | movi r11, #0       ;
        movi r9, #-262144    | movi r10, #262143  ;
        movi r12, #8         | movi r13, #0       ;
        movi r14, #0x40      ;
        - ;

// Cada vuelta dura 14 bundles. Los numeros de la derecha cuentan desde lazo y
// la latencia es de 3: un valor producido en el bundle n se lee desde el n+3.
lazo:
        -                | subi r12, r12, #1 | lw.inc r1, #4(r13) ;   //  0
        - ;                                                           //  1
        - ;                                                           //  2
        cmp r1, r9       | add r8, r8, r1    ;                        //  3 banderas: x vs max
        srli r6, r1, #31 | sub r3, r1, r10   ;                        //  4
        -                | sub r2, r1, r9    ;                        //  5
        cmpi r12, #0     | setcc r4, ge      ;                        //  6 setcc lee las del cmp
        srli r5, r3, #31 | add r11, r11, r6  ;                        //  7 x < min, sin banderas
        - ;                                                           //  8
        - ;                                                           //  9
        mul r2, r2, r4   | mul r3, r3, r5    ;                        // 10
        - ;                                                           // 11
        - | - | - | - | br.ne lazo ;                                  // 12
        add r9, r9, r2   | add r10, r10, r3  ;                        // 13 delay slot

// Promedio: suma / 8. __div32 es sin signo, y la suma de este arreglo es
// positiva. Destruye r1 a r5 y preserva r8 a r14.
        mov r6, r8       | movi r7, #8 ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;                                         // delay slot del jal

// Aqui aterriza el retorno: PC del jal mas 32
        - | - | sw r8,  #0(r14)  ;
        - | - | sw r9,  #4(r14)  ;
        - | - | sw r10, #8(r14)  ;
        - | - | sw r11, #12(r14) ;
        - | - | sw r6,  #16(r14) ;
        - | - | sw r7,  #20(r14) ;
        - | - | - | - | halt ;
        - ;                                         // delay slot del halt

        .include "div32.s"
