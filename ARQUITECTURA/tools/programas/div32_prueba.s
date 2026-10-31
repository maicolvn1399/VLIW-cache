// =============================================================================
// div32_prueba.s - Llama a __div32 con seis pares y guarda los resultados.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// La subrutina de division no se puede probar leyendola: son 32 vueltas de un
// lazo con una cadena de dependencias de siete pasos, y un error de
// calendarizacion da un resultado equivocado sin que nada avise. Asi que se
// prueba ejecutandola, con los seis casos que cubren lo que puede salir mal:
//
//   caso           dividendo    divisor   cociente    residuo
//   -------------  -----------  --------  ----------  ----------
//   normal         0x000003E8   0x0007    0x0000008E  0x00000006
//   divisor 1      0xFFFFFFFF   0x0001    0xFFFFFFFF  0x00000000
//   dividendo < d  0x00000007   0x03E8    0x00000000  0x00000007
//   bit 31 puesto  0x80000000   0x0003    0x2AAAAAAA  0x00000002
//   division por 0 0x00000064   0x0000    0xFFFFFFFF  0x00000064
//   dividendo 0    0x00000000   0x0005    0x00000000  0x00000000
//
// Los valores esperados se calcularon fuera del simulador. tb_div.sv los tiene
// escritos y compara contra la memoria.
//
// El caso del bit 31 es el que importa mas: un algoritmo de restas desplazadas
// que tratara el dividendo como numero con signo daria otra cosa, y es el error
// clasico de esta rutina. El de divisor 1 con dividendo en todos unos recorre
// las 32 vueltas poniendo un bit de cociente en cada una.
// =============================================================================

        .data
        .org 0x0000

// Seis pares de dividendo y divisor, consecutivos
pares:
        .word 1000,       7
        .word 0xFFFFFFFF, 1
        .word 7,          1000
        .word 0x80000000, 3
        .word 100,        0
        .word 0,          5

// Doce palabras de resultado, un cociente y un residuo por caso
        .org 0x0040
resultados:
        .space 48

// =============================================================================

        .text
        .org 0x0000

inicio:
// --- caso 0: 1000 / 7 --------------------------------------------------------
        - | - | lw r6, #0(r0)  ;
        - | - | lw r7, #4(r0)  ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;                                   // delay slot
        - | - | sw r6, #64(r0) ;              // aqui aterriza el retorno
        - | - | sw r7, #68(r0) ;

// --- caso 1: 0xFFFFFFFF / 1 --------------------------------------------------
        - | - | lw r6, #8(r0)  ;
        - | - | lw r7, #12(r0) ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;
        - | - | sw r6, #72(r0) ;
        - | - | sw r7, #76(r0) ;

// --- caso 2: 7 / 1000 --------------------------------------------------------
        - | - | lw r6, #16(r0) ;
        - | - | lw r7, #20(r0) ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;
        - | - | sw r6, #80(r0) ;
        - | - | sw r7, #84(r0) ;

// --- caso 3: 0x80000000 / 3 --------------------------------------------------
        - | - | lw r6, #24(r0) ;
        - | - | lw r7, #28(r0) ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;
        - | - | sw r6, #88(r0) ;
        - | - | sw r7, #92(r0) ;

// --- caso 4: 100 / 0 ---------------------------------------------------------
        - | - | lw r6, #32(r0) ;
        - | - | lw r7, #36(r0) ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;
        - | - | sw r6, #96(r0) ;
        - | - | sw r7, #100(r0) ;

// --- caso 5: 0 / 5 -----------------------------------------------------------
        - | - | lw r6, #40(r0) ;
        - | - | lw r7, #44(r0) ;
        - ;
        - ;
        - | - | - | - | jal.al __div32 ;
        - ;
        - | - | sw r6, #104(r0) ;
        - | - | sw r7, #108(r0) ;

// --- fin ---------------------------------------------------------------------
        - ;
        - ;
        - | - | - | - | halt ;
        - ;                                   // delay slot del halt

// =============================================================================
// La rutina, tal como se entrega junto con el ISA
// =============================================================================

        .include "div32.s"
