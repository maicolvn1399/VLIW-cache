// =============================================================================
// feistel.s - Cifrado Feistel4 de un bloque, con sesion de boveda.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es el programa del enunciado y, a la vez, la prueba de que el ensamblador
// produce binarios que el procesador ejecuta: tb_asm.sv carga el .hex que sale
// de aqui y comprueba el resultado contra los valores calculados fuera del
// simulador.
//
//   claro            L=DEADBEEF  R=CAFEBABE
//   cifrado          L=677DE658  R=47BBFB52
//
// -----------------------------------------------------------------------------
// ESTRUCTURA
// -----------------------------------------------------------------------------
// El programa principal vive en el codigo de usuario y la rutina de cifrado en
// la region segura, porque la boveda cierra la sesion en cuanto el PC sale de
// [SEC_BASE, SEC_LIMIT]. Eso obliga a que AUTHW, LOGIN, KSETW y las rondas esten
// todas dentro.
//
// La llamada es con JALR y no con JAL porque el salto relativo alcanza 512
// bundles y de 0x00A0 a 0x7000 hay 1781. El ensamblador lo rechaza si se intenta
// con JAL, que es justamente la validacion de "desplazamiento fuera de rango".
//
// Al retornar, el PC abandona la region y la boveda cierra la sesion sola, sin
// que el programa ejecute LOGOUT. Es el cierre automatico del ISA 8.3, y
// tb_asm.sv lo comprueba: al final AUTH tiene que estar apagado aunque el
// cifrado haya salido bien.
//
// -----------------------------------------------------------------------------
// SEPARACION ENTRE PRODUCTOR Y CONSUMIDOR
// -----------------------------------------------------------------------------
// Los bundles vacios no son relleno decorativo: el ISA exige tres bundles entre
// un productor y su consumidor, y se cuentan en bundles EJECUTADOS. El
// ensamblador avisa si falta alguno, y este programa no debe producir ninguna
// advertencia.
// =============================================================================

        .data
        .org 0x0000

// Credencial: las cuatro palabras de ROT_SECRET, de la menos significativa a la
// mas significativa, que es el orden en que las toma AUTHW
credencial:
        .word 0x76543210
        .word 0xFEDCBA98
        .word 0x89ABCDEF
        .word 0x01234567

// Llave de 128 bits, una palabra por ronda
llave:
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444

// Bloque de 64 bits a cifrar: mitad L y mitad R
bloque:
        .word 0xDEADBEEF
        .word 0xCAFEBABE

        .org 0x0040
resultado:
        .word 0
        .word 0

// =============================================================================

        .text
        .org 0x0000

inicio:
// La direccion de la rutina segura no cabe en un salto relativo, asi que va a
// un registro. 0x7000 cabe de sobra en el inmediato de 19 bits con signo.
        movi r12, #0x7000 | - | lw r1, #0(r0)   ;
        - | - | lw r2,  #4(r0)   ;
        - | - | lw r3,  #8(r0)   ;
        - | - | lw r4,  #12(r0)  ;
        - | - | lw r5,  #16(r0)  ;
        - | - | lw r6,  #20(r0)  ;
        - | - | lw r7,  #24(r0)  ;
        - | - | lw r8,  #28(r0)  ;
// El bloque va al par P5, que son R10 y R11: la mitad L en el par y la R en el
// impar, como fija el ISA
        - | - | lw r10, #32(r0)  ;
        - | - | lw r11, #36(r0)  ;

// Llamada a la rutina segura. El enlace queda en R15 y apunta dos bundles
// adelante, porque el siguiente ya es el delay slot y se ejecuta.
        - | - | - | - | jalr.al r12 ;
        - ;                                  // delay slot del jalr

// Aqui aterriza el retorno: PC del jalr mas 32
        - | - | sw r10, #64(r0)  ;
        - | - | sw r11, #68(r0)  ;
        - | - | - | - | halt ;
        - ;                                  // delay slot del halt

// =============================================================================
// Rutina de cifrado. Toda dentro de la region segura.
// =============================================================================

        .org 0x7000
        .secure

cifrar:
// Paso 1 del protocolo: las cuatro palabras de la credencial al desafio
        - | - | - | authw #0, r1 ;
        - | - | - | authw #1, r2 ;
        - | - | - | authw #2, r3 ;
        - | - | - | authw #3, r4 ;

// Paso 2: autenticar
        - | - | - | login ;
        - ;
        - ;

// Paso 4: instalar la llave en la ranura 0. Requiere AUTH, que quedo listo tres
// bundles despues del login.
        - | - | - | ksetw k0, #0, r5 ;
        - | - | - | ksetw k0, #1, r6 ;
        - | - | - | ksetw k0, #2, r7 ;
        - | - | - | ksetw k0, #3, r8 ;
        - ;
        - ;

// Paso 5: cuatro rondas. Cada una lee y reescribe el par, asi que van separadas
// por los tres bundles de la latencia.
        - | - | - | f4e p5, k0, #0 ;
        - ;
        - ;
        - | - | - | f4e p5, k0, #1 ;
        - ;
        - ;
        - | - | - | f4e p5, k0, #2 ;
        - ;
        - ;
        - | - | - | f4e p5, k0, #3 ;
        - ;
        - ;

// Retorno. No hace falta LOGOUT: al salir de la region la boveda cierra la
// sesion por su cuenta.
        - | - | - | - | jr.al r15 ;
        - ;                                  // delay slot del jr

        .endsecure
