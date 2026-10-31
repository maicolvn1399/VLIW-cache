// =====================================================
// Ensamblador VLIW para CERBERO, generado por novac
// Bundle de 128 bits, cinco slots:
//   <S0:ALU-0> | <S1:ALU-1> | <S2:LSU> | <S3:CRP> | <S4:BRU> ;
// Tres bundles de productor a consumidor; un delay slot
// despues de cada salto, que siempre se ejecuta.
// =====================================================

.data
    // 0x0000-0x1FFF variables globales (Nova no tiene globales mutables)
    .org 0x2000
    // Literales de cadena: una palabra de longitud y luego los bytes.

    .org 0x3000
__out_n:
    .word 0
__out_buf:
    .space 4092

.text
    .org 0x0000
    // Arranque: la pila empieza en 0xFFFC y se entra a principale
__inicio:
    movi r14, #65532           | -          | -                      | -                  | -                ;  // 0x0000
    -                          | -          | -                      | -                  | -                ;  // 0x0010
    -                          | -          | -                      | -                  | -                ;  // 0x0020
    -                          | -          | -                      | -                  | jal.al principale ;  // 0x0030
    -                          | -          | -                      | -                  | -                ;  // 0x0040
    -                          | -          | -                      | -                  | halt             ;  // 0x0050
    -                          | -          | -                      | -                  | -                ;  // 0x0060
    // functio sumar
sumar:
    // marco de 16 bytes
    subi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x00A0
    -                          | -          | sw r7, #0(r14)         | -                  | -                ;  // 0x00B0
__sumar_cuerpo:
    // Nova fuente: linea 5, columna 14
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | -                      | -                  | -                ;  // 0x00D0
    -                          | -          | -                      | -                  | -                ;  // 0x00E0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x00F0
    // Nova fuente: linea 5, columna 9
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0100
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0110
    -                          | -          | -                      | -                  | -                ;  // 0x0120
    -                          | -          | -                      | -                  | -                ;  // 0x0130
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | -                      | -                  | -                ;  // 0x0150
    -                          | -          | -                      | -                  | -                ;  // 0x0160
    -                          | -          | -                      | -                  | br.eq __c0_si    ;  // 0x0170
    -                          | -          | -                      | -                  | -                ;  // 0x0180
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0190
    -                          | -          | -                      | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | -                      | -                  | br.al __c0_fin   ;  // 0x01C0
    -                          | -          | -                      | -                  | -                ;  // 0x01D0
__c0_si:
    // Nova fuente: linea 5, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x01E0
    -                          | -          | -                      | -                  | -                ;  // 0x01F0
    -                          | -          | -                      | -                  | -                ;  // 0x0200
__c0_fin:
    // Nova fuente: linea 5, columna 9
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0210
    // Nova fuente: linea 5, columna 5
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0220
    -                          | -          | -                      | -                  | -                ;  // 0x0230
    -                          | -          | -                      | -                  | -                ;  // 0x0240
    -                          | -          | -                      | -                  | br.eq L0         ;  // 0x0250
    -                          | -          | -                      | -                  | -                ;  // 0x0260
    // Nova fuente: linea 6, columna 9
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x0270
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0280
    -                          | -          | -                      | -                  | -                ;  // 0x0290
    -                          | -          | -                      | -                  | -                ;  // 0x02A0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x02B0
    -                          | -          | -                      | -                  | -                ;  // 0x02C0
L0:
    // Nova fuente: linea 8, columna 21
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x02D0
    -                          | -          | -                      | -                  | -                ;  // 0x02E0
    -                          | -          | -                      | -                  | -                ;  // 0x02F0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0300
    // Nova fuente: linea 8, columna 17
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0310
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0320
    -                          | -          | -                      | -                  | -                ;  // 0x0330
    -                          | -          | -                      | -                  | -                ;  // 0x0340
    sub r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0350
    -                          | -          | -                      | -                  | -                ;  // 0x0360
    -                          | -          | -                      | -                  | -                ;  // 0x0370
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0380
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0390
    // Nova fuente: linea 8, columna 24
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x03A0
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x03B0
    -                          | -          | -                      | -                  | -                ;  // 0x03C0
    -                          | -          | -                      | -                  | -                ;  // 0x03D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x03E0
    -                          | -          | -                      | -                  | -                ;  // 0x03F0
    -                          | -          | -                      | -                  | -                ;  // 0x0400
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0410
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x0420
    // Nova fuente: linea 8, columna 11
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x0430
    -                          | -          | -                      | -                  | -                ;  // 0x0440
    -                          | -          | sw r7, #0(r14)         | -                  | -                ;  // 0x0450
    -                          | -          | -                      | -                  | br.al __sumar_cuerpo ;  // 0x0460
    -                          | -          | -                      | -                  | -                ;  // 0x0470
    // Nova fuente: linea 4, columna 9
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0480
    -                          | -          | -                      | -                  | -                ;  // 0x0490
    -                          | -          | -                      | -                  | -                ;  // 0x04A0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x04B0
    -                          | -          | -                      | -                  | -                ;  // 0x04C0
    // functio principale
principale:
    // marco de 8 bytes, guarda R15 en #4(r14)
    subi r14, r14, #8          | -          | -                      | -                  | -                ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    -                          | -          | -                      | -                  | -                ;  // 0x04F0
    -                          | -          | sw r15, #4(r14)        | -                  | -                ;  // 0x0500
__principale_cuerpo:
    // Nova fuente: linea 12, columna 18
    movi r10, #500             | -          | -                      | -                  | -                ;  // 0x0510
    -                          | -          | -                      | -                  | -                ;  // 0x0520
    -                          | -          | -                      | -                  | -                ;  // 0x0530
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0540
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0550
    // Nova fuente: linea 12, columna 23
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0560
    -                          | -          | -                      | -                  | -                ;  // 0x0570
    -                          | -          | -                      | -                  | -                ;  // 0x0580
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0590
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x05A0
    // Nova fuente: linea 12, columna 12
    -                          | -          | -                      | -                  | -                ;  // 0x05B0
    -                          | -          | -                      | -                  | -                ;  // 0x05C0
    -                          | -          | -                      | -                  | jal.al sumar     ;  // 0x05D0
    -                          | -          | -                      | -                  | -                ;  // 0x05E0
    -                          | -          | sw r6, #0(r14)         | -                  | -                ;  // 0x05F0
    // Nova fuente: linea 12, columna 5
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x0600
    -                          | -          | -                      | -                  | -                ;  // 0x0610
    // Nova fuente: linea 13, columna 11
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0620
    -                          | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | -                      | -                  | -                ;  // 0x0640
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0650
    // Nova fuente: linea 13, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0660
    -                          | -          | -                      | -                  | -                ;  // 0x0670
    -                          | -          | -                      | -                  | -                ;  // 0x0680
    -                          | -          | -                      | -                  | halt             ;  // 0x0690
    -                          | -          | -                      | -                  | -                ;  // 0x06A0
    // __scribe_int(R6 = valor): el ISA no define puertos de E/S, los resultados se dejan en memoria para las herramientas de CE 4301
__scribe_int:
    movi r10, #12288           | -          | -                      | -                  | -                ;  // 0x06B0
    -                          | -          | -                      | -                  | -                ;  // 0x06C0
    -                          | -          | -                      | -                  | -                ;  // 0x06D0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x06E0
    -                          | -          | -                      | -                  | -                ;  // 0x06F0
    -                          | -          | -                      | -                  | -                ;  // 0x0700
    slli r11, r11, #2          | -          | -                      | -                  | -                ;  // 0x0710
    -                          | -          | -                      | -                  | -                ;  // 0x0720
    -                          | -          | -                      | -                  | -                ;  // 0x0730
    addi r11, r11, #4          | -          | -                      | -                  | -                ;  // 0x0740
    -                          | -          | -                      | -                  | -                ;  // 0x0750
    -                          | -          | -                      | -                  | -                ;  // 0x0760
    add r11, r10, r11          | -          | -                      | -                  | -                ;  // 0x0770
    -                          | -          | -                      | -                  | -                ;  // 0x0780
    -                          | -          | -                      | -                  | -                ;  // 0x0790
    -                          | -          | sw r6, #0(r11)         | -                  | -                ;  // 0x07A0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x07B0
    -                          | -          | -                      | -                  | -                ;  // 0x07C0
    -                          | -          | -                      | -                  | -                ;  // 0x07D0
    addi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x07E0
    -                          | -          | -                      | -                  | -                ;  // 0x07F0
    -                          | -          | -                      | -                  | -                ;  // 0x0800
    -                          | -          | sw r11, #0(r10)        | -                  | -                ;  // 0x0810
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0820
    -                          | -          | -                      | -                  | -                ;  // 0x0830

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   sumar                        0x0070     IMEM bundle 7
//   __sumar_cuerpo               0x00C0     IMEM bundle 12
//   __c0_si                      0x01E0     IMEM bundle 30
//   __c0_fin                     0x0210     IMEM bundle 33
//   L0                           0x02D0     IMEM bundle 45
//   principale                   0x04D0     IMEM bundle 77
//   __principale_cuerpo          0x0510     IMEM bundle 81
//   __scribe_int                 0x06B0     IMEM bundle 107
//   9 etiquetas de codigo, 2 de datos

// fin del programa
