// =============================================================================
// cobertura.s - Ejercita el 100% del conjunto de instrucciones de CERBERO-1.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// El enunciado pide que el ensamblador se pruebe sobre todo el conjunto. Este
// programa usa los 63 mnemonicos una vez por lo menos, y se comprueba con
//
//     cerbero_asm.py programas/cobertura.s --cobertura
//
// que no reporte ninguno sin usar. No calcula nada util: su trabajo es que cada
// formato de instruccion pase por el codificador y por las validaciones.
//
// Si el programa se emite sin errores, entonces el ensamblador acepta todos los
// formatos; si ademas --cobertura sale en cero, ninguno quedo sin probar. Las
// dos mitades juntas son lo que pide el enunciado.
//
// Aparte, el programa respeta las reglas del ISA, asi que no debe producir
// ninguna advertencia de latencia ni de salto en delay slot. Que salga limpio
// es parte de la prueba: un ensamblador que no revisara nada tambien saldria
// limpio, pero este programa fue escrito a proposito para quedar al borde de
// varias reglas sin violarlas.
// =============================================================================

        .data
        .org 0x0000

valores:
        .word 0x11223344, 0x55667788
        .word -1
bytes_sueltos:
        .byte 0x7F, 1, 0
hueco:
        .space 16

// -----------------------------------------------------------------------------

        .text
        .org 0x0000

inicio:
// --- Slot ALU, forma de tres registros ---------------------------------------
        add  r1, r2, r3  | sub  r4, r5, r6  ;
        mul  r7, r8, r9  | and  r10, r11, r12 ;
        or   r1, r2, r3  | xor  r4, r5, r6  ;
        sll  r7, r8, r9  | srl  r10, r11, r12 ;
        sra  r1, r2, r3  | rol  r4, r5, r6  ;
        ror  r7, r8, r9  ;
        - ;                      // separacion: r4 lo escribio `rol` dos bundles atras

// --- Slot ALU, formas de dos registros ---------------------------------------
        mov  r1, r2      | not  r3, r4      ;
        neg  r5, r6      ;

// --- Comparaciones: solo existen en S0 ---------------------------------------
        cmp  r7, r8      ;
        test r9, r10     ;
        cmpi r11, #100   ;
        testi r12, #0x0F ;

// --- Slot ALU, formas con inmediato ------------------------------------------
        addi r1, r2, #1      | subi r3, r4, #-1     ;
        andi r5, r6, #0xFF   | ori  r7, r8, #256    ;
        xori r9, r10, #-4    | slli r11, r12, #3    ;
        srli r1, r2, #31     | srai r3, r4, #1      ;
        roli r5, r6, #13     ;

// --- Slot ALU, formas de tipo U ----------------------------------------------
        movi r7, #262143     | movh r8, #0xFFFF     ;
        movi r9, #-262144    ;
        setcc r10, lt        | setcc r11, auth      ;
        mfpsw r12            ;

// --- Slot LSU: los cinco tamanos de carga ------------------------------------
        - | - | lw   r1, #0(r13)   ;
        - | - | lh   r2, #2(r13)   ;
        - | - | lhu  r3, #4(r13)   ;
        - | - | lb   r4, #1(r13)   ;
        - | - | lbu  r5, #3(r13)   ;

// --- Slot LSU: almacenamientos y postincremento ------------------------------
        - | - | sw   r6, #0(r13)   ;
        - | - | sh   r7, #2(r13)   ;
        - | - | sb   r8, #1(r13)   ;
        - | - | lw.inc r9, #4(r14) ;
        - | - | - ;
        - | - | - ;
        - | - | sw.inc r10, #4(r14) ;

// --- Slot S3: ALU corta, forma de registro y forma de inmediato --------------
        - | - | - | add.s r1, r2   ;
        - | - | - | sub.s r3, #5   ;
        - | - | - | and.s r4, r5   ;
        - | - | - | or.s  r6, #31  ;
        - | - | - | xor.s r7, r8   ;
        - | - | - | mov.s r9, #0   ;
        - | - | - | not.s r10      ;
        - | - | - | neg.s r11      ;

// --- Slot S3: boveda ---------------------------------------------------------
        .org 0x7000
        .secure

region_segura:
        - | - | - | authw #0, r1   ;
        - | - | - | authw #1, r2   ;
        - | - | - | authw #2, r3   ;
        - | - | - | authw #3, r4   ;
        - | - | - | login          ;
        - | - | - | - ;
        - | - | - | - ;
        - | - | - | ksetw k0, #0, r5 ;
        - | - | - | ksetw k1, #1, r6 ;
        - | - | - | ksetw k2, #2, r7 ;
        - | - | - | ksetw k3, #3, r8 ;

// --- Slot S3: las dos rondas -------------------------------------------------
        - | - | - | f4e p0, k0, #0 ;
        - | - | - | - ;
        - | - | - | - ;
        - | - | - | f4d p7, k3, #3 ;
        - | - | - | - ;
        - | - | - | - ;

// --- Slot S3: el resto del control de la boveda ------------------------------
        - | - | - | pwset          ;
        - | - | - | kclr k2        ;
        - | - | - | logout         ;
        .endsecure

// --- Slot BRU: saltos relativos y condicionales ------------------------------
        .org 0x0400

saltos:
        - | - | - | - | br.al adelante ;
        - | - | - | - ;                      // delay slot
        - | - | - | - ;

adelante:
        - | - | - | - | br.eq atras ;
        - | - | - | - ;
        - | - | - | - | br.ne adelante ;
        - | - | - | - ;
        - | - | - | - | br.lt adelante ;
        - | - | - | - ;
        - | - | - | - | br.ge adelante ;
        - | - | - | - ;
        - | - | - | - | br.ltu adelante ;
        - | - | - | - ;
        - | - | - | - | br.geu adelante ;
        - | - | - | - ;
        - | - | - | - | br.auth adelante ;
        - | - | - | - ;

// --- Slot BRU: llamada, retorno indirecto y detencion ------------------------
        - | - | - | - | jal.al rutina ;
        - | - | - | - ;
        - | - | - | - | jalr.al r13 ;
        - | - | - | - ;
        - | - | - | - | jr.auth r14 ;
        - | - | - | - ;

atras:
        - | - | - | - | halt ;
        - | - | - | - ;                      // delay slot de halt

rutina:
        - | - | - | - | jr.al r15 ;
        - | - | - | - ;
