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
    // functio principale
principale:
    // marco de 20 bytes, guarda R15 en #16(r14)
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    -                          | -          | sw r15, #16(r14)       | -                  | -                ;  // 0x00A0
__principale_cuerpo:
    // Nova fuente: linea 4, columna 25
    movi r10, #240             | -          | -                      | -                  | -                ;  // 0x00B0
    -                          | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | -                      | -                  | -                ;  // 0x00D0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x00E0
    // Nova fuente: linea 4, columna 11
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x00F0
    // Nova fuente: linea 5, columna 26
    movi r10, #256             | -          | -                      | -                  | -                ;  // 0x0100
    -                          | -          | -                      | -                  | -                ;  // 0x0110
    -                          | -          | -                      | -                  | -                ;  // 0x0120
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0130
    // Nova fuente: linea 5, columna 25
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | -                      | -                  | -                ;  // 0x0150
    -                          | -          | -                      | -                  | -                ;  // 0x0160
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0170
    // Nova fuente: linea 5, columna 11
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0180
    // Nova fuente: linea 6, columna 17
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x0190
    -                          | -          | -                      | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x01C0
    // Nova fuente: linea 6, columna 12
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x01D0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x01E0
    -                          | -          | -                      | -                  | -                ;  // 0x01F0
    -                          | -          | -                      | -                  | -                ;  // 0x0200
    sll r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0210
    -                          | -          | -                      | -                  | -                ;  // 0x0220
    -                          | -          | -                      | -                  | -                ;  // 0x0230
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0240
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0250
    // Nova fuente: linea 6, columna 5
    -                          | -          | -                      | -                  | -                ;  // 0x0260
    -                          | -          | -                      | -                  | -                ;  // 0x0270
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x0280
    -                          | -          | -                      | -                  | -                ;  // 0x0290
    // Nova fuente: linea 7, columna 17
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x02A0
    -                          | -          | -                      | -                  | -                ;  // 0x02B0
    -                          | -          | -                      | -                  | -                ;  // 0x02C0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x02D0
    // Nova fuente: linea 7, columna 12
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x02E0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x02F0
    -                          | -          | -                      | -                  | -                ;  // 0x0300
    -                          | -          | -                      | -                  | -                ;  // 0x0310
    sra r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0320
    -                          | -          | -                      | -                  | -                ;  // 0x0330
    -                          | -          | -                      | -                  | -                ;  // 0x0340
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0350
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0360
    // Nova fuente: linea 7, columna 5
    -                          | -          | -                      | -                  | -                ;  // 0x0370
    -                          | -          | -                      | -                  | -                ;  // 0x0380
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x0390
    -                          | -          | -                      | -                  | -                ;  // 0x03A0
    // Nova fuente: linea 8, columna 17
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x03B0
    -                          | -          | -                      | -                  | -                ;  // 0x03C0
    -                          | -          | -                      | -                  | -                ;  // 0x03D0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x03E0
    // Nova fuente: linea 8, columna 12
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x03F0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0400
    -                          | -          | -                      | -                  | -                ;  // 0x0410
    -                          | -          | -                      | -                  | -                ;  // 0x0420
    sra r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0430
    -                          | -          | -                      | -                  | -                ;  // 0x0440
    -                          | -          | -                      | -                  | -                ;  // 0x0450
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0460
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0470
    // Nova fuente: linea 8, columna 5
    -                          | -          | -                      | -                  | -                ;  // 0x0480
    -                          | -          | -                      | -                  | -                ;  // 0x0490
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x04A0
    -                          | -          | -                      | -                  | -                ;  // 0x04B0
    // Nova fuente: linea 9, columna 18
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x04C0
    -                          | -          | -                      | -                  | -                ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x04F0
    // Nova fuente: linea 9, columna 12
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x0500
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0510
    -                          | -          | -                      | -                  | -                ;  // 0x0520
    -                          | -          | -                      | -                  | -                ;  // 0x0530
    srl r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0540
    -                          | -          | -                      | -                  | -                ;  // 0x0550
    -                          | -          | -                      | -                  | -                ;  // 0x0560
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0570
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0580
    // Nova fuente: linea 9, columna 5
    -                          | -          | -                      | -                  | -                ;  // 0x0590
    -                          | -          | -                      | -                  | -                ;  // 0x05A0
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x05B0
    -                          | -          | -                      | -                  | -                ;  // 0x05C0
    // Nova fuente: linea 10, columna 11
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x05D0
    -                          | -          | -                      | -                  | -                ;  // 0x05E0
    -                          | -          | -                      | -                  | -                ;  // 0x05F0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0600
    // Nova fuente: linea 10, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0610
    -                          | -          | -                      | -                  | -                ;  // 0x0620
    -                          | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | -                      | -                  | halt             ;  // 0x0640
    -                          | -          | -                      | -                  | -                ;  // 0x0650
    // __scribe_int(R6 = valor): el ISA no define puertos de E/S, los resultados se dejan en memoria para las herramientas de CE 4301
__scribe_int:
    movi r10, #12288           | -          | -                      | -                  | -                ;  // 0x0660
    -                          | -          | -                      | -                  | -                ;  // 0x0670
    -                          | -          | -                      | -                  | -                ;  // 0x0680
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x0690
    -                          | -          | -                      | -                  | -                ;  // 0x06A0
    -                          | -          | -                      | -                  | -                ;  // 0x06B0
    slli r11, r11, #2          | -          | -                      | -                  | -                ;  // 0x06C0
    -                          | -          | -                      | -                  | -                ;  // 0x06D0
    -                          | -          | -                      | -                  | -                ;  // 0x06E0
    addi r11, r11, #4          | -          | -                      | -                  | -                ;  // 0x06F0
    -                          | -          | -                      | -                  | -                ;  // 0x0700
    -                          | -          | -                      | -                  | -                ;  // 0x0710
    add r11, r10, r11          | -          | -                      | -                  | -                ;  // 0x0720
    -                          | -          | -                      | -                  | -                ;  // 0x0730
    -                          | -          | -                      | -                  | -                ;  // 0x0740
    -                          | -          | sw r6, #0(r11)         | -                  | -                ;  // 0x0750
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x0760
    -                          | -          | -                      | -                  | -                ;  // 0x0770
    -                          | -          | -                      | -                  | -                ;  // 0x0780
    addi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x0790
    -                          | -          | -                      | -                  | -                ;  // 0x07A0
    -                          | -          | -                      | -                  | -                ;  // 0x07B0
    -                          | -          | sw r11, #0(r10)        | -                  | -                ;  // 0x07C0
    -                          | -          | -                      | -                  | -                ;  // 0x07D0
    -                          | -          | -                      | -                  | -                ;  // 0x07E0
    -                          | -          | -                      | -                  | -                ;  // 0x07F0
    -                          | -          | -                      | -                  | -                ;  // 0x0800
    -                          | -          | -                      | -                  | -                ;  // 0x0810
    -                          | -          | -                      | -                  | -                ;  // 0x0820
    -                          | -          | -                      | -                  | -                ;  // 0x0830
    -                          | -          | -                      | -                  | -                ;  // 0x0840
    -                          | -          | -                      | -                  | -                ;  // 0x0850
    -                          | -          | -                      | -                  | -                ;  // 0x0860
    -                          | -          | -                      | -                  | -                ;  // 0x0870
    -                          | -          | -                      | -                  | -                ;  // 0x0880
    -                          | -          | -                      | -                  | -                ;  // 0x0890
    -                          | -          | -                      | -                  | -                ;  // 0x08A0
    -                          | -          | -                      | -                  | -                ;  // 0x08B0
    -                          | -          | -                      | -                  | -                ;  // 0x08C0
    -                          | -          | -                      | -                  | -                ;  // 0x08D0
    -                          | -          | -                      | -                  | -                ;  // 0x08E0
    -                          | -          | -                      | -                  | -                ;  // 0x08F0
    -                          | -          | -                      | -                  | -                ;  // 0x0900
    -                          | -          | -                      | -                  | -                ;  // 0x0910
    -                          | -          | -                      | -                  | -                ;  // 0x0920
    -                          | -          | -                      | -                  | -                ;  // 0x0930
    -                          | -          | -                      | -                  | -                ;  // 0x0940
    -                          | -          | -                      | -                  | -                ;  // 0x0950
    -                          | -          | -                      | -                  | -                ;  // 0x0960
    -                          | -          | -                      | -                  | -                ;  // 0x0970
    -                          | -          | -                      | -                  | -                ;  // 0x0980
    -                          | -          | -                      | -                  | -                ;  // 0x0990
    -                          | -          | -                      | -                  | -                ;  // 0x09A0
    -                          | -          | -                      | -                  | -                ;  // 0x09B0
    -                          | -          | -                      | -                  | -                ;  // 0x09C0
    -                          | -          | -                      | -                  | -                ;  // 0x09D0
    -                          | -          | -                      | -                  | -                ;  // 0x09E0
    -                          | -          | -                      | -                  | -                ;  // 0x09F0
    -                          | -          | -                      | -                  | -                ;  // 0x0A00
    -                          | -          | -                      | -                  | -                ;  // 0x0A10
    -                          | -          | -                      | -                  | -                ;  // 0x0A20
    -                          | -          | -                      | -                  | -                ;  // 0x0A30
    -                          | -          | -                      | -                  | -                ;  // 0x0A40
    -                          | -          | -                      | -                  | -                ;  // 0x0A50
    -                          | -          | -                      | -                  | -                ;  // 0x0A60
    -                          | -          | -                      | -                  | -                ;  // 0x0A70
    -                          | -          | -                      | -                  | -                ;  // 0x0A80
    -                          | -          | -                      | -                  | -                ;  // 0x0A90
    -                          | -          | -                      | -                  | -                ;  // 0x0AA0
    -                          | -          | -                      | -                  | -                ;  // 0x0AB0
    -                          | -          | -                      | -                  | -                ;  // 0x0AC0
    -                          | -          | -                      | -                  | -                ;  // 0x0AD0
    -                          | -          | -                      | -                  | -                ;  // 0x0AE0
    -                          | -          | -                      | -                  | -                ;  // 0x0AF0
    -                          | -          | -                      | -                  | -                ;  // 0x0B00
    -                          | -          | -                      | -                  | -                ;  // 0x0B10
    -                          | -          | -                      | -                  | -                ;  // 0x0B20
    -                          | -          | -                      | -                  | -                ;  // 0x0B30
    -                          | -          | -                      | -                  | -                ;  // 0x0B40
    -                          | -          | -                      | -                  | -                ;  // 0x0B50
    -                          | -          | -                      | -                  | -                ;  // 0x0B60
    -                          | -          | -                      | -                  | -                ;  // 0x0B70
    -                          | -          | -                      | -                  | -                ;  // 0x0B80
    -                          | -          | -                      | -                  | -                ;  // 0x0B90
    -                          | -          | -                      | -                  | -                ;  // 0x0BA0
    -                          | -          | -                      | -                  | -                ;  // 0x0BB0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0BC0
    -                          | -          | -                      | -                  | -                ;  // 0x0BD0

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   principale                   0x0070     IMEM bundle 7
//   __principale_cuerpo          0x00B0     IMEM bundle 11
//   __scribe_int                 0x0660     IMEM bundle 102
//   4 etiquetas de codigo, 2 de datos

// fin del programa
