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
    // functio factorial
factorial:
    // marco de 20 bytes
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x00A0
__factorial_cuerpo:
    // Nova fuente: linea 2, columna 33
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x00B0
    -                          | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | -                      | -                  | -                ;  // 0x00D0
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x00E0
    // Nova fuente: linea 2, columna 11
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x00F0
    // Nova fuente: linea 3, columna 25
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0100
    -                          | -          | -                      | -                  | -                ;  // 0x0110
    -                          | -          | -                      | -                  | -                ;  // 0x0120
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0130
    // Nova fuente: linea 3, columna 11
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0140
    // Nova fuente: linea 5, columna 13
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0150
    -                          | -          | -                      | -                  | -                ;  // 0x0160
    -                          | -          | -                      | -                  | -                ;  // 0x0170
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0180
    // Nova fuente: linea 5, columna 9
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0190
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | -                      | -                  | -                ;  // 0x01C0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x01D0
    -                          | -          | -                      | -                  | -                ;  // 0x01E0
    -                          | -          | -                      | -                  | -                ;  // 0x01F0
    -                          | -          | -                      | -                  | br.lt __c0_si    ;  // 0x0200
    -                          | -          | -                      | -                  | -                ;  // 0x0210
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0220
    -                          | -          | -                      | -                  | -                ;  // 0x0230
    -                          | -          | -                      | -                  | -                ;  // 0x0240
    -                          | -          | -                      | -                  | br.al __c0_fin   ;  // 0x0250
    -                          | -          | -                      | -                  | -                ;  // 0x0260
__c0_si:
    // Nova fuente: linea 5, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0270
    -                          | -          | -                      | -                  | -                ;  // 0x0280
    -                          | -          | -                      | -                  | -                ;  // 0x0290
__c0_fin:
    // Nova fuente: linea 5, columna 9
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x02A0
    // Nova fuente: linea 5, columna 5
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x02B0
    -                          | -          | -                      | -                  | -                ;  // 0x02C0
    -                          | -          | -                      | -                  | -                ;  // 0x02D0
    -                          | -          | -                      | -                  | br.eq L0         ;  // 0x02E0
    -                          | -          | -                      | -                  | -                ;  // 0x02F0
    // Nova fuente: linea 6, columna 15
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0300
    -                          | -          | -                      | -                  | -                ;  // 0x0310
    -                          | -          | -                      | -                  | -                ;  // 0x0320
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0330
    // Nova fuente: linea 6, columna 9
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0340
    addi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x0350
    -                          | -          | -                      | -                  | -                ;  // 0x0360
    -                          | -          | -                      | -                  | -                ;  // 0x0370
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0380
    -                          | -          | -                      | -                  | -                ;  // 0x0390
L0:
L1:
    // Nova fuente: linea 9, columna 10
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x03A0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x03B0
    -                          | -          | -                      | -                  | -                ;  // 0x03C0
    -                          | -          | -                      | -                  | -                ;  // 0x03D0
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x03E0
    -                          | -          | -                      | -                  | -                ;  // 0x03F0
    -                          | -          | -                      | -                  | -                ;  // 0x0400
    -                          | -          | -                      | -                  | br.ge __c1_si    ;  // 0x0410
    -                          | -          | -                      | -                  | -                ;  // 0x0420
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0430
    -                          | -          | -                      | -                  | -                ;  // 0x0440
    -                          | -          | -                      | -                  | -                ;  // 0x0450
    -                          | -          | -                      | -                  | br.al __c1_fin   ;  // 0x0460
    -                          | -          | -                      | -                  | -                ;  // 0x0470
__c1_si:
    // Nova fuente: linea 9, columna 10
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0480
    -                          | -          | -                      | -                  | -                ;  // 0x0490
    -                          | -          | -                      | -                  | -                ;  // 0x04A0
__c1_fin:
    // Nova fuente: linea 9, columna 10
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x04B0
    // Nova fuente: linea 9, columna 5
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x04C0
    -                          | -          | -                      | -                  | -                ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    -                          | -          | -                      | -                  | br.eq L2         ;  // 0x04F0
    -                          | -          | -                      | -                  | -                ;  // 0x0500
    // Nova fuente: linea 10, columna 21
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0510
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x0520
    -                          | -          | -                      | -                  | -                ;  // 0x0530
    -                          | -          | -                      | -                  | -                ;  // 0x0540
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0550
    -                          | -          | -                      | -                  | -                ;  // 0x0560
    -                          | -          | -                      | -                  | -                ;  // 0x0570
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0580
    // Nova fuente: linea 10, columna 9
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0590
    // Nova fuente: linea 11, columna 17
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x05A0
    -                          | -          | -                      | -                  | -                ;  // 0x05B0
    -                          | -          | -                      | -                  | -                ;  // 0x05C0
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x05D0
    // Nova fuente: linea 11, columna 13
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x05E0
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x05F0
    -                          | -          | -                      | -                  | -                ;  // 0x0600
    -                          | -          | -                      | -                  | -                ;  // 0x0610
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0620
    -                          | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | -                      | -                  | -                ;  // 0x0640
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x0650
    // Nova fuente: linea 11, columna 9
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0660
    -                          | -          | -                      | -                  | br.al L1         ;  // 0x0670
    -                          | -          | -                      | -                  | -                ;  // 0x0680
L2:
    // Nova fuente: linea 14, columna 5
    -                          | -          | lw r6, #4(r14)         | -                  | -                ;  // 0x0690
    addi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x06A0
    -                          | -          | -                      | -                  | -                ;  // 0x06B0
    -                          | -          | -                      | -                  | -                ;  // 0x06C0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x06D0
    -                          | -          | -                      | -                  | -                ;  // 0x06E0
    // functio principale
principale:
    // marco de 16 bytes, guarda R15 en #12(r14)
    subi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x06F0
    -                          | -          | -                      | -                  | -                ;  // 0x0700
    -                          | -          | -                      | -                  | -                ;  // 0x0710
    -                          | -          | sw r15, #12(r14)       | -                  | -                ;  // 0x0720
__principale_cuerpo:
    // Nova fuente: linea 18, columna 25
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x0730
    -                          | -          | -                      | -                  | -                ;  // 0x0740
    -                          | -          | -                      | -                  | -                ;  // 0x0750
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0760
    // Nova fuente: linea 18, columna 11
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0770
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0780
    // Nova fuente: linea 19, columna 33
    -                          | -          | -                      | -                  | -                ;  // 0x0790
    -                          | -          | -                      | -                  | -                ;  // 0x07A0
    -                          | -          | -                      | -                  | jal.al factorial ;  // 0x07B0
    -                          | -          | -                      | -                  | -                ;  // 0x07C0
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x07D0
    // Nova fuente: linea 19, columna 11
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x07E0
    -                          | -          | -                      | -                  | -                ;  // 0x07F0
    -                          | -          | -                      | -                  | -                ;  // 0x0800
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0810
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0820
    // Nova fuente: linea 20, columna 5
    -                          | -          | -                      | -                  | -                ;  // 0x0830
    -                          | -          | -                      | -                  | -                ;  // 0x0840
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x0850
    -                          | -          | -                      | -                  | -                ;  // 0x0860
    // Nova fuente: linea 21, columna 5
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x0870
    -                          | -          | -                      | -                  | -                ;  // 0x0880
    -                          | -          | -                      | -                  | -                ;  // 0x0890
    -                          | -          | -                      | -                  | halt             ;  // 0x08A0
    -                          | -          | -                      | -                  | -                ;  // 0x08B0
    // __scribe_int(R6 = valor): el ISA no define puertos de E/S, los resultados se dejan en memoria para las herramientas de CE 4301
__scribe_int:
    movi r10, #12288           | -          | -                      | -                  | -                ;  // 0x08C0
    -                          | -          | -                      | -                  | -                ;  // 0x08D0
    -                          | -          | -                      | -                  | -                ;  // 0x08E0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x08F0
    -                          | -          | -                      | -                  | -                ;  // 0x0900
    -                          | -          | -                      | -                  | -                ;  // 0x0910
    slli r11, r11, #2          | -          | -                      | -                  | -                ;  // 0x0920
    -                          | -          | -                      | -                  | -                ;  // 0x0930
    -                          | -          | -                      | -                  | -                ;  // 0x0940
    addi r11, r11, #4          | -          | -                      | -                  | -                ;  // 0x0950
    -                          | -          | -                      | -                  | -                ;  // 0x0960
    -                          | -          | -                      | -                  | -                ;  // 0x0970
    add r11, r10, r11          | -          | -                      | -                  | -                ;  // 0x0980
    -                          | -          | -                      | -                  | -                ;  // 0x0990
    -                          | -          | -                      | -                  | -                ;  // 0x09A0
    -                          | -          | sw r6, #0(r11)         | -                  | -                ;  // 0x09B0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x09C0
    -                          | -          | -                      | -                  | -                ;  // 0x09D0
    -                          | -          | -                      | -                  | -                ;  // 0x09E0
    addi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x09F0
    -                          | -          | -                      | -                  | -                ;  // 0x0A00
    -                          | -          | -                      | -                  | -                ;  // 0x0A10
    -                          | -          | sw r11, #0(r10)        | -                  | -                ;  // 0x0A20
    -                          | -          | -                      | -                  | -                ;  // 0x0A30
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0A40
    -                          | -          | -                      | -                  | -                ;  // 0x0A50

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   factorial                    0x0070     IMEM bundle 7
//   __factorial_cuerpo           0x00B0     IMEM bundle 11
//   __c0_si                      0x0270     IMEM bundle 39
//   __c0_fin                     0x02A0     IMEM bundle 42
//   L0                           0x03A0     IMEM bundle 58
//   L1                           0x03A0     IMEM bundle 58
//   __c1_si                      0x0480     IMEM bundle 72
//   __c1_fin                     0x04B0     IMEM bundle 75
//   L2                           0x0690     IMEM bundle 105
//   principale                   0x06F0     IMEM bundle 111
//   __principale_cuerpo          0x0730     IMEM bundle 115
//   __scribe_int                 0x08C0     IMEM bundle 140
//   13 etiquetas de codigo, 2 de datos

// fin del programa
