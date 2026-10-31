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
__str0:
    .word 38
    .byte 0x65, 0x72, 0x72, 0x6F, 0x72, 0x3A, 0x20, 0x65, 0x6C, 0x20, 0x6B, 0x65
    .byte 0x72, 0x6E, 0x65, 0x6C, 0x20, 0x64, 0x65, 0x62, 0x65, 0x20, 0x74, 0x65
    .byte 0x6E, 0x65, 0x72, 0x20, 0x6C, 0x61, 0x64, 0x6F, 0x20, 0x69, 0x6D, 0x70
    .byte 0x61, 0x72
    .space 2   // alineacion a palabra
__str1:
    .word 10
    .byte 0x72, 0x65, 0x73, 0x75, 0x6C, 0x74, 0x61, 0x64, 0x6F, 0x3A
    .space 2   // alineacion a palabra
__str2:
    .word 10
    .byte 0x70, 0x72, 0x6F, 0x6D, 0x65, 0x64, 0x69, 0x6F, 0x20, 0x3D
    .space 2   // alineacion a palabra
__str3:
    .word 8
    .byte 0x6D, 0x61, 0x78, 0x69, 0x6D, 0x6F, 0x20, 0x3D
__str4:
    .word 0

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
    movi r11, #8864            | -          | -                      | -                  | -                ;  // 0x0030
    -                          | -          | -                      | -                  | -                ;  // 0x0040
    -                          | -          | -                      | -                  | -                ;  // 0x0050
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x0060
    -                          | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | halt             ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    // functio convolucionar
convolucionar:
    // marco de 100 bytes, guarda R15 en #96(r14)
    subi r14, r14, #100        | -          | -                      | -                  | -                ;  // 0x00A0
    -                          | -          | -                      | -                  | -                ;  // 0x00B0
    -                          | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | sw r15, #96(r14)       | -                  | -                ;  // 0x00D0
    -                          | -          | sw r6, #64(r14)        | -                  | -                ;  // 0x00E0
    -                          | -          | sw r7, #68(r14)        | -                  | -                ;  // 0x00F0
    -                          | -          | sw r8, #72(r14)        | -                  | -                ;  // 0x0100
    -                          | -          | sw r9, #52(r14)        | -                  | -                ;  // 0x0110
    -                          | -          | lw r10, #100(r14)      | -                  | -                ;  // 0x0120
    -                          | -          | -                      | -                  | -                ;  // 0x0130
    -                          | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | sw r10, #56(r14)       | -                  | -                ;  // 0x0150
    -                          | -          | lw r10, #104(r14)      | -                  | -                ;  // 0x0160
    -                          | -          | -                      | -                  | -                ;  // 0x0170
    -                          | -          | -                      | -                  | -                ;  // 0x0180
    -                          | -          | sw r10, #60(r14)       | -                  | -                ;  // 0x0190
    -                          | -          | lw r10, #108(r14)      | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | -                      | -                  | -                ;  // 0x01C0
    -                          | -          | sw r10, #40(r14)       | -                  | -                ;  // 0x01D0
    -                          | -          | lw r10, #112(r14)      | -                  | -                ;  // 0x01E0
    -                          | -          | -                      | -                  | -                ;  // 0x01F0
    -                          | -          | -                      | -                  | -                ;  // 0x0200
    -                          | -          | sw r10, #44(r14)       | -                  | -                ;  // 0x0210
    -                          | -          | lw r10, #116(r14)      | -                  | -                ;  // 0x0220
    -                          | -          | -                      | -                  | -                ;  // 0x0230
    -                          | -          | -                      | -                  | -                ;  // 0x0240
    -                          | -          | sw r10, #48(r14)       | -                  | -                ;  // 0x0250
__convolucionar_cuerpo:
    // Nova fuente: linea 7, columna 25
    -                          | -          | lw r10, #68(r14)       | -                  | -                ;  // 0x0260
    -                          | -          | -                      | -                  | -                ;  // 0x0270
    -                          | -          | -                      | -                  | -                ;  // 0x0280
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0290
    // Nova fuente: linea 7, columna 8
    -                          | -          | sw r10, #36(r14)       | -                  | -                ;  // 0x02A0
    // Nova fuente: linea 8, columna 26
    -                          | -          | lw r10, #72(r14)       | -                  | -                ;  // 0x02B0
    -                          | -          | -                      | -                  | -                ;  // 0x02C0
    -                          | -          | -                      | -                  | -                ;  // 0x02D0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x02E0
    // Nova fuente: linea 8, columna 8
    -                          | -          | sw r10, #32(r14)       | -                  | -                ;  // 0x02F0
    // Nova fuente: linea 9, columna 26
    -                          | -          | lw r10, #56(r14)       | -                  | -                ;  // 0x0300
    -                          | -          | -                      | -                  | -                ;  // 0x0310
    -                          | -          | -                      | -                  | -                ;  // 0x0320
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0330
    // Nova fuente: linea 9, columna 46
    movi r10, #2               | -          | -                      | -                  | -                ;  // 0x0340
    -                          | -          | -                      | -                  | -                ;  // 0x0350
    -                          | -          | -                      | -                  | -                ;  // 0x0360
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x0370
    // Nova fuente: linea 9, columna 26
    -                          | -          | lw r6, #76(r14)        | -                  | -                ;  // 0x0380
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x0390
    -                          | -          | -                      | -                  | -                ;  // 0x03A0
    -                          | -          | -                      | -                  | -                ;  // 0x03B0
    movi r11, #36448           | -          | -                      | -                  | -                ;  // 0x03C0
    -                          | -          | -                      | -                  | -                ;  // 0x03D0
    -                          | -          | -                      | -                  | -                ;  // 0x03E0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x03F0
    -                          | -          | -                      | -                  | -                ;  // 0x0400
    -                          | -          | sw r6, #84(r14)        | -                  | -                ;  // 0x0410
    // Nova fuente: linea 9, columna 8
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x0420
    -                          | -          | -                      | -                  | -                ;  // 0x0430
    -                          | -          | -                      | -                  | -                ;  // 0x0440
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x0450
    // Nova fuente: linea 10, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0460
    -                          | -          | -                      | -                  | -                ;  // 0x0470
    -                          | -          | -                      | -                  | -                ;  // 0x0480
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0490
    // Nova fuente: linea 10, columna 13
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x04A0
L0:
    // Nova fuente: linea 10, columna 30
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x04B0
    -                          | -          | lw r11, #36(r14)       | -                  | -                ;  // 0x04C0
    -                          | -          | -                      | -                  | -                ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x04F0
    -                          | -          | -                      | -                  | -                ;  // 0x0500
    -                          | -          | -                      | -                  | -                ;  // 0x0510
    -                          | -          | -                      | -                  | br.lt __c14_si   ;  // 0x0520
    -                          | -          | -                      | -                  | -                ;  // 0x0530
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0540
    -                          | -          | -                      | -                  | -                ;  // 0x0550
    -                          | -          | -                      | -                  | -                ;  // 0x0560
    -                          | -          | -                      | -                  | br.al __c14_fin  ;  // 0x0570
    -                          | -          | -                      | -                  | -                ;  // 0x0580
__c14_si:
    // Nova fuente: linea 10, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0590
    -                          | -          | -                      | -                  | -                ;  // 0x05A0
    -                          | -          | -                      | -                  | -                ;  // 0x05B0
__c14_fin:
    // Nova fuente: linea 10, columna 30
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x05C0
    // Nova fuente: linea 10, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x05D0
    -                          | -          | -                      | -                  | -                ;  // 0x05E0
    -                          | -          | -                      | -                  | -                ;  // 0x05F0
    -                          | -          | -                      | -                  | br.eq L2         ;  // 0x0600
    -                          | -          | -                      | -                  | -                ;  // 0x0610
    // Nova fuente: linea 11, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0620
    -                          | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | -                      | -                  | -                ;  // 0x0640
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0650
    // Nova fuente: linea 11, columna 13
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0660
L3:
    // Nova fuente: linea 11, columna 30
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x0670
    -                          | -          | lw r11, #32(r14)       | -                  | -                ;  // 0x0680
    -                          | -          | -                      | -                  | -                ;  // 0x0690
    -                          | -          | -                      | -                  | -                ;  // 0x06A0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x06B0
    -                          | -          | -                      | -                  | -                ;  // 0x06C0
    -                          | -          | -                      | -                  | -                ;  // 0x06D0
    -                          | -          | -                      | -                  | br.lt __c15_si   ;  // 0x06E0
    -                          | -          | -                      | -                  | -                ;  // 0x06F0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0700
    -                          | -          | -                      | -                  | -                ;  // 0x0710
    -                          | -          | -                      | -                  | -                ;  // 0x0720
    -                          | -          | -                      | -                  | br.al __c15_fin  ;  // 0x0730
    -                          | -          | -                      | -                  | -                ;  // 0x0740
__c15_si:
    // Nova fuente: linea 11, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0750
    -                          | -          | -                      | -                  | -                ;  // 0x0760
    -                          | -          | -                      | -                  | -                ;  // 0x0770
__c15_fin:
    // Nova fuente: linea 11, columna 30
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0780
    // Nova fuente: linea 11, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0790
    -                          | -          | -                      | -                  | -                ;  // 0x07A0
    -                          | -          | -                      | -                  | -                ;  // 0x07B0
    -                          | -          | -                      | -                  | br.eq L5         ;  // 0x07C0
    -                          | -          | -                      | -                  | -                ;  // 0x07D0
    // Nova fuente: linea 12, columna 25
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x07E0
    -                          | -          | -                      | -                  | -                ;  // 0x07F0
    -                          | -          | -                      | -                  | -                ;  // 0x0800
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0810
    // Nova fuente: linea 12, columna 8
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x0820
    // Nova fuente: linea 13, columna 28
    -                          | -          | lw r10, #28(r14)       | -                  | -                ;  // 0x0830
    -                          | -          | -                      | -                  | -                ;  // 0x0840
    -                          | -          | -                      | -                  | -                ;  // 0x0850
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x0860
    -                          | -          | -                      | -                  | -                ;  // 0x0870
    -                          | -          | -                      | -                  | -                ;  // 0x0880
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0890
    // Nova fuente: linea 13, columna 13
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x08A0
L6:
    // Nova fuente: linea 13, columna 36
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x08B0
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x08C0
    -                          | -          | -                      | -                  | -                ;  // 0x08D0
    -                          | -          | -                      | -                  | -                ;  // 0x08E0
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x08F0
    -                          | -          | -                      | -                  | -                ;  // 0x0900
    -                          | -          | -                      | -                  | -                ;  // 0x0910
    -                          | -          | -                      | -                  | br.ge __c16_si   ;  // 0x0920
    -                          | -          | -                      | -                  | -                ;  // 0x0930
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0940
    -                          | -          | -                      | -                  | -                ;  // 0x0950
    -                          | -          | -                      | -                  | -                ;  // 0x0960
    -                          | -          | -                      | -                  | br.al __c16_fin  ;  // 0x0970
    -                          | -          | -                      | -                  | -                ;  // 0x0980
__c16_si:
    // Nova fuente: linea 13, columna 36
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0990
    -                          | -          | -                      | -                  | -                ;  // 0x09A0
    -                          | -          | -                      | -                  | -                ;  // 0x09B0
__c16_fin:
    // Nova fuente: linea 13, columna 36
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x09C0
    // Nova fuente: linea 13, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x09D0
    -                          | -          | -                      | -                  | -                ;  // 0x09E0
    -                          | -          | -                      | -                  | -                ;  // 0x09F0
    -                          | -          | -                      | -                  | br.eq L8         ;  // 0x0A00
    -                          | -          | -                      | -                  | -                ;  // 0x0A10
    // Nova fuente: linea 14, columna 28
    -                          | -          | lw r10, #28(r14)       | -                  | -                ;  // 0x0A20
    -                          | -          | -                      | -                  | -                ;  // 0x0A30
    -                          | -          | -                      | -                  | -                ;  // 0x0A40
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x0A50
    -                          | -          | -                      | -                  | -                ;  // 0x0A60
    -                          | -          | -                      | -                  | -                ;  // 0x0A70
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0A80
    // Nova fuente: linea 14, columna 13
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0A90
L9:
    // Nova fuente: linea 14, columna 36
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0AA0
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x0AB0
    -                          | -          | -                      | -                  | -                ;  // 0x0AC0
    -                          | -          | -                      | -                  | -                ;  // 0x0AD0
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x0AE0
    -                          | -          | -                      | -                  | -                ;  // 0x0AF0
    -                          | -          | -                      | -                  | -                ;  // 0x0B00
    -                          | -          | -                      | -                  | br.ge __c17_si   ;  // 0x0B10
    -                          | -          | -                      | -                  | -                ;  // 0x0B20
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0B30
    -                          | -          | -                      | -                  | -                ;  // 0x0B40
    -                          | -          | -                      | -                  | -                ;  // 0x0B50
    -                          | -          | -                      | -                  | br.al __c17_fin  ;  // 0x0B60
    -                          | -          | -                      | -                  | -                ;  // 0x0B70
__c17_si:
    // Nova fuente: linea 14, columna 36
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0B80
    -                          | -          | -                      | -                  | -                ;  // 0x0B90
    -                          | -          | -                      | -                  | -                ;  // 0x0BA0
__c17_fin:
    // Nova fuente: linea 14, columna 36
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0BB0
    // Nova fuente: linea 14, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0BC0
    -                          | -          | -                      | -                  | -                ;  // 0x0BD0
    -                          | -          | -                      | -                  | -                ;  // 0x0BE0
    -                          | -          | -                      | -                  | br.eq L11        ;  // 0x0BF0
    -                          | -          | -                      | -                  | -                ;  // 0x0C00
    // Nova fuente: linea 15, columna 38
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x0C10
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x0C20
    -                          | -          | -                      | -                  | -                ;  // 0x0C30
    -                          | -          | -                      | -                  | -                ;  // 0x0C40
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0C50
    -                          | -          | -                      | -                  | -                ;  // 0x0C60
    -                          | -          | -                      | -                  | -                ;  // 0x0C70
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0C80
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0C90
    // Nova fuente: linea 15, columna 46
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0CA0
    -                          | -          | -                      | -                  | -                ;  // 0x0CB0
    -                          | -          | -                      | -                  | -                ;  // 0x0CC0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0CD0
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x0CE0
    // Nova fuente: linea 15, columna 56
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0CF0
    -                          | -          | -                      | -                  | -                ;  // 0x0D00
    -                          | -          | -                      | -                  | -                ;  // 0x0D10
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0D20
    // Nova fuente: linea 15, columna 49
    -                          | -          | lw r10, #36(r14)       | -                  | -                ;  // 0x0D30
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x0D40
    -                          | -          | -                      | -                  | -                ;  // 0x0D50
    -                          | -          | -                      | -                  | -                ;  // 0x0D60
    sub r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0D70
    -                          | -          | -                      | -                  | -                ;  // 0x0D80
    -                          | -          | -                      | -                  | -                ;  // 0x0D90
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x0DA0
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x0DB0
    // Nova fuente: linea 15, columna 23
    -                          | -          | -                      | -                  | -                ;  // 0x0DC0
    -                          | -          | -                      | -                  | -                ;  // 0x0DD0
    movi r11, #22320           | -          | -                      | -                  | -                ;  // 0x0DE0
    -                          | -          | -                      | -                  | -                ;  // 0x0DF0
    -                          | -          | -                      | -                  | -                ;  // 0x0E00
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x0E10
    -                          | -          | -                      | -                  | -                ;  // 0x0E20
    -                          | -          | sw r6, #76(r14)        | -                  | -                ;  // 0x0E30
    // Nova fuente: linea 15, columna 8
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x0E40
    -                          | -          | -                      | -                  | -                ;  // 0x0E50
    -                          | -          | -                      | -                  | -                ;  // 0x0E60
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0E70
    // Nova fuente: linea 16, columna 38
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x0E80
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0E90
    -                          | -          | -                      | -                  | -                ;  // 0x0EA0
    -                          | -          | -                      | -                  | -                ;  // 0x0EB0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0EC0
    -                          | -          | -                      | -                  | -                ;  // 0x0ED0
    -                          | -          | -                      | -                  | -                ;  // 0x0EE0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0EF0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0F00
    // Nova fuente: linea 16, columna 46
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0F10
    -                          | -          | -                      | -                  | -                ;  // 0x0F20
    -                          | -          | -                      | -                  | -                ;  // 0x0F30
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0F40
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x0F50
    // Nova fuente: linea 16, columna 57
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0F60
    -                          | -          | -                      | -                  | -                ;  // 0x0F70
    -                          | -          | -                      | -                  | -                ;  // 0x0F80
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x0F90
    // Nova fuente: linea 16, columna 49
    -                          | -          | lw r10, #32(r14)       | -                  | -                ;  // 0x0FA0
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x0FB0
    -                          | -          | -                      | -                  | -                ;  // 0x0FC0
    -                          | -          | -                      | -                  | -                ;  // 0x0FD0
    sub r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0FE0
    -                          | -          | -                      | -                  | -                ;  // 0x0FF0
    -                          | -          | -                      | -                  | -                ;  // 0x1000
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x1010
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x1020
    // Nova fuente: linea 16, columna 23
    -                          | -          | -                      | -                  | -                ;  // 0x1030
    -                          | -          | -                      | -                  | -                ;  // 0x1040
    movi r11, #22320           | -          | -                      | -                  | -                ;  // 0x1050
    -                          | -          | -                      | -                  | -                ;  // 0x1060
    -                          | -          | -                      | -                  | -                ;  // 0x1070
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x1080
    -                          | -          | -                      | -                  | -                ;  // 0x1090
    -                          | -          | sw r6, #76(r14)        | -                  | -                ;  // 0x10A0
    // Nova fuente: linea 16, columna 8
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x10B0
    -                          | -          | -                      | -                  | -                ;  // 0x10C0
    -                          | -          | -                      | -                  | -                ;  // 0x10D0
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x10E0
    // Nova fuente: linea 17, columna 17
    -                          | -          | lw r10, #68(r14)       | -                  | -                ;  // 0x10F0
    -                          | -          | -                      | -                  | -                ;  // 0x1100
    -                          | -          | -                      | -                  | -                ;  // 0x1110
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1120
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x1130
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1140
    -                          | -          | -                      | -                  | -                ;  // 0x1150
    -                          | -          | -                      | -                  | -                ;  // 0x1160
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1170
    -                          | -          | -                      | -                  | -                ;  // 0x1180
    -                          | -          | -                      | -                  | -                ;  // 0x1190
    -                          | -          | -                      | -                  | br.ltu __rango16_ok ;  // 0x11A0
    -                          | -          | -                      | -                  | -                ;  // 0x11B0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x11C0
    -                          | -          | -                      | -                  | -                ;  // 0x11D0
    -                          | -          | -                      | -                  | -                ;  // 0x11E0
    -                          | -          | -                      | -                  | halt             ;  // 0x11F0
    -                          | -          | -                      | -                  | -                ;  // 0x1200
__rango16_ok:
    // Nova fuente: linea 17, columna 21
    -                          | -          | lw r10, #72(r14)       | -                  | -                ;  // 0x1210
    -                          | -          | -                      | -                  | -                ;  // 0x1220
    -                          | -          | -                      | -                  | -                ;  // 0x1230
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1240
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x1250
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1260
    -                          | -          | -                      | -                  | -                ;  // 0x1270
    -                          | -          | -                      | -                  | -                ;  // 0x1280
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1290
    -                          | -          | -                      | -                  | -                ;  // 0x12A0
    -                          | -          | -                      | -                  | -                ;  // 0x12B0
    -                          | -          | -                      | -                  | br.ltu __rango17_ok ;  // 0x12C0
    -                          | -          | -                      | -                  | -                ;  // 0x12D0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x12E0
    -                          | -          | -                      | -                  | -                ;  // 0x12F0
    -                          | -          | -                      | -                  | -                ;  // 0x1300
    -                          | -          | -                      | -                  | halt             ;  // 0x1310
    -                          | -          | -                      | -                  | -                ;  // 0x1320
__rango17_ok:
    // Nova fuente: linea 17, columna 21
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x1330
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1340
    -                          | -          | -                      | -                  | -                ;  // 0x1350
    -                          | -          | -                      | -                  | -                ;  // 0x1360
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1370
    -                          | -          | -                      | -                  | -                ;  // 0x1380
    -                          | -          | -                      | -                  | -                ;  // 0x1390
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x13A0
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x13B0
    -                          | -          | -                      | -                  | -                ;  // 0x13C0
    -                          | -          | -                      | -                  | -                ;  // 0x13D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x13E0
    -                          | -          | -                      | -                  | -                ;  // 0x13F0
    -                          | -          | -                      | -                  | -                ;  // 0x1400
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1410
    // Nova fuente: linea 17, columna 10
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x1420
    -                          | -          | lw r11, #64(r14)       | -                  | -                ;  // 0x1430
    -                          | -          | -                      | -                  | -                ;  // 0x1440
    -                          | -          | -                      | -                  | -                ;  // 0x1450
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x1460
    -                          | -          | -                      | -                  | -                ;  // 0x1470
    -                          | -          | -                      | -                  | -                ;  // 0x1480
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x1490
    -                          | -          | -                      | -                  | -                ;  // 0x14A0
    -                          | -          | -                      | -                  | -                ;  // 0x14B0
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x14C0
    // Nova fuente: linea 17, columna 34
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x14D0
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x14E0
    -                          | -          | -                      | -                  | -                ;  // 0x14F0
    -                          | -          | -                      | -                  | -                ;  // 0x1500
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1510
    -                          | -          | -                      | -                  | -                ;  // 0x1520
    -                          | -          | -                      | -                  | -                ;  // 0x1530
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1540
    -                          | -          | lw r10, #56(r14)       | -                  | -                ;  // 0x1550
    -                          | -          | -                      | -                  | -                ;  // 0x1560
    -                          | -          | -                      | -                  | -                ;  // 0x1570
    -                          | -          | sw r10, #84(r14)       | -                  | -                ;  // 0x1580
    -                          | -          | lw r10, #76(r14)       | -                  | -                ;  // 0x1590
    -                          | -          | lw r11, #84(r14)       | -                  | -                ;  // 0x15A0
    -                          | -          | -                      | -                  | -                ;  // 0x15B0
    -                          | -          | -                      | -                  | -                ;  // 0x15C0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x15D0
    -                          | -          | -                      | -                  | -                ;  // 0x15E0
    -                          | -          | -                      | -                  | -                ;  // 0x15F0
    -                          | -          | -                      | -                  | br.ltu __rango18_ok ;  // 0x1600
    -                          | -          | -                      | -                  | -                ;  // 0x1610
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x1620
    -                          | -          | -                      | -                  | -                ;  // 0x1630
    -                          | -          | -                      | -                  | -                ;  // 0x1640
    -                          | -          | -                      | -                  | halt             ;  // 0x1650
    -                          | -          | -                      | -                  | -                ;  // 0x1660
__rango18_ok:
    // Nova fuente: linea 17, columna 46
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x1670
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x1680
    -                          | -          | -                      | -                  | -                ;  // 0x1690
    -                          | -          | -                      | -                  | -                ;  // 0x16A0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x16B0
    -                          | -          | -                      | -                  | -                ;  // 0x16C0
    -                          | -          | -                      | -                  | -                ;  // 0x16D0
    -                          | -          | sw r10, #84(r14)       | -                  | -                ;  // 0x16E0
    -                          | -          | lw r10, #60(r14)       | -                  | -                ;  // 0x16F0
    -                          | -          | -                      | -                  | -                ;  // 0x1700
    -                          | -          | -                      | -                  | -                ;  // 0x1710
    -                          | -          | sw r10, #88(r14)       | -                  | -                ;  // 0x1720
    -                          | -          | lw r10, #84(r14)       | -                  | -                ;  // 0x1730
    -                          | -          | lw r11, #88(r14)       | -                  | -                ;  // 0x1740
    -                          | -          | -                      | -                  | -                ;  // 0x1750
    -                          | -          | -                      | -                  | -                ;  // 0x1760
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1770
    -                          | -          | -                      | -                  | -                ;  // 0x1780
    -                          | -          | -                      | -                  | -                ;  // 0x1790
    -                          | -          | -                      | -                  | br.ltu __rango19_ok ;  // 0x17A0
    -                          | -          | -                      | -                  | -                ;  // 0x17B0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x17C0
    -                          | -          | -                      | -                  | -                ;  // 0x17D0
    -                          | -          | -                      | -                  | -                ;  // 0x17E0
    -                          | -          | -                      | -                  | halt             ;  // 0x17F0
    -                          | -          | -                      | -                  | -                ;  // 0x1800
__rango19_ok:
    // Nova fuente: linea 17, columna 46
    -                          | -          | lw r10, #76(r14)       | -                  | -                ;  // 0x1810
    -                          | -          | lw r11, #88(r14)       | -                  | -                ;  // 0x1820
    -                          | -          | -                      | -                  | -                ;  // 0x1830
    -                          | -          | -                      | -                  | -                ;  // 0x1840
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1850
    -                          | -          | -                      | -                  | -                ;  // 0x1860
    -                          | -          | -                      | -                  | -                ;  // 0x1870
    -                          | -          | sw r10, #92(r14)       | -                  | -                ;  // 0x1880
    -                          | -          | lw r11, #84(r14)       | -                  | -                ;  // 0x1890
    -                          | -          | -                      | -                  | -                ;  // 0x18A0
    -                          | -          | -                      | -                  | -                ;  // 0x18B0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x18C0
    -                          | -          | -                      | -                  | -                ;  // 0x18D0
    -                          | -          | -                      | -                  | -                ;  // 0x18E0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x18F0
    // Nova fuente: linea 17, columna 27
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x1900
    -                          | -          | lw r11, #52(r14)       | -                  | -                ;  // 0x1910
    -                          | -          | -                      | -                  | -                ;  // 0x1920
    -                          | -          | -                      | -                  | -                ;  // 0x1930
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x1940
    -                          | -          | -                      | -                  | -                ;  // 0x1950
    -                          | -          | -                      | -                  | -                ;  // 0x1960
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x1970
    -                          | -          | -                      | -                  | -                ;  // 0x1980
    -                          | -          | -                      | -                  | -                ;  // 0x1990
    -                          | -          | sw r10, #84(r14)       | -                  | -                ;  // 0x19A0
    // Nova fuente: linea 17, columna 10
    -                          | -          | lw r10, #80(r14)       | -                  | -                ;  // 0x19B0
    -                          | -          | lw r11, #84(r14)       | -                  | -                ;  // 0x19C0
    -                          | -          | -                      | -                  | -                ;  // 0x19D0
    -                          | -          | -                      | -                  | -                ;  // 0x19E0
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x19F0
    -                          | -          | -                      | -                  | -                ;  // 0x1A00
    -                          | -          | -                      | -                  | -                ;  // 0x1A10
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1A20
    // Nova fuente: linea 17, columna 2
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x1A30
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1A40
    -                          | -          | -                      | -                  | -                ;  // 0x1A50
    -                          | -          | -                      | -                  | -                ;  // 0x1A60
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1A70
    -                          | -          | -                      | -                  | -                ;  // 0x1A80
    -                          | -          | -                      | -                  | -                ;  // 0x1A90
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x1AA0
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x1AB0
L10:
    // Nova fuente: linea 14, columna 55
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1AC0
    -                          | -          | -                      | -                  | -                ;  // 0x1AD0
    -                          | -          | -                      | -                  | -                ;  // 0x1AE0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1AF0
    // Nova fuente: linea 14, columna 49
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x1B00
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1B10
    -                          | -          | -                      | -                  | -                ;  // 0x1B20
    -                          | -          | -                      | -                  | -                ;  // 0x1B30
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1B40
    -                          | -          | -                      | -                  | -                ;  // 0x1B50
    -                          | -          | -                      | -                  | -                ;  // 0x1B60
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x1B70
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x1B80
    -                          | -          | -                      | -                  | br.al L9         ;  // 0x1B90
    -                          | -          | -                      | -                  | -                ;  // 0x1BA0
L11:
L7:
    // Nova fuente: linea 13, columna 55
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1BB0
    -                          | -          | -                      | -                  | -                ;  // 0x1BC0
    -                          | -          | -                      | -                  | -                ;  // 0x1BD0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1BE0
    // Nova fuente: linea 13, columna 49
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x1BF0
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1C00
    -                          | -          | -                      | -                  | -                ;  // 0x1C10
    -                          | -          | -                      | -                  | -                ;  // 0x1C20
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1C30
    -                          | -          | -                      | -                  | -                ;  // 0x1C40
    -                          | -          | -                      | -                  | -                ;  // 0x1C50
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x1C60
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x1C70
    -                          | -          | -                      | -                  | br.al L6         ;  // 0x1C80
    -                          | -          | -                      | -                  | -                ;  // 0x1C90
L8:
    // Nova fuente: linea 20, columna 9
    -                          | -          | lw r10, #44(r14)       | -                  | -                ;  // 0x1CA0
    -                          | -          | -                      | -                  | -                ;  // 0x1CB0
    -                          | -          | -                      | -                  | -                ;  // 0x1CC0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1CD0
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x1CE0
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1CF0
    -                          | -          | -                      | -                  | -                ;  // 0x1D00
    -                          | -          | -                      | -                  | -                ;  // 0x1D10
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1D20
    -                          | -          | -                      | -                  | -                ;  // 0x1D30
    -                          | -          | -                      | -                  | -                ;  // 0x1D40
    -                          | -          | -                      | -                  | br.ltu __rango20_ok ;  // 0x1D50
    -                          | -          | -                      | -                  | -                ;  // 0x1D60
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x1D70
    -                          | -          | -                      | -                  | -                ;  // 0x1D80
    -                          | -          | -                      | -                  | -                ;  // 0x1D90
    -                          | -          | -                      | -                  | halt             ;  // 0x1DA0
    -                          | -          | -                      | -                  | -                ;  // 0x1DB0
__rango20_ok:
    // Nova fuente: linea 20, columna 12
    -                          | -          | lw r10, #48(r14)       | -                  | -                ;  // 0x1DC0
    -                          | -          | -                      | -                  | -                ;  // 0x1DD0
    -                          | -          | -                      | -                  | -                ;  // 0x1DE0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1DF0
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x1E00
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1E10
    -                          | -          | -                      | -                  | -                ;  // 0x1E20
    -                          | -          | -                      | -                  | -                ;  // 0x1E30
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1E40
    -                          | -          | -                      | -                  | -                ;  // 0x1E50
    -                          | -          | -                      | -                  | -                ;  // 0x1E60
    -                          | -          | -                      | -                  | br.ltu __rango21_ok ;  // 0x1E70
    -                          | -          | -                      | -                  | -                ;  // 0x1E80
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x1E90
    -                          | -          | -                      | -                  | -                ;  // 0x1EA0
    -                          | -          | -                      | -                  | -                ;  // 0x1EB0
    -                          | -          | -                      | -                  | halt             ;  // 0x1EC0
    -                          | -          | -                      | -                  | -                ;  // 0x1ED0
__rango21_ok:
    // Nova fuente: linea 20, columna 12
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x1EE0
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x1EF0
    -                          | -          | -                      | -                  | -                ;  // 0x1F00
    -                          | -          | -                      | -                  | -                ;  // 0x1F10
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1F20
    -                          | -          | -                      | -                  | -                ;  // 0x1F30
    -                          | -          | -                      | -                  | -                ;  // 0x1F40
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x1F50
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x1F60
    -                          | -          | -                      | -                  | -                ;  // 0x1F70
    -                          | -          | -                      | -                  | -                ;  // 0x1F80
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x1F90
    -                          | -          | -                      | -                  | -                ;  // 0x1FA0
    -                          | -          | -                      | -                  | -                ;  // 0x1FB0
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x1FC0
    // Nova fuente: linea 20, columna 2
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x1FD0
    -                          | -          | lw r11, #40(r14)       | -                  | -                ;  // 0x1FE0
    -                          | -          | -                      | -                  | -                ;  // 0x1FF0
    -                          | -          | -                      | -                  | -                ;  // 0x2000
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2010
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x2020
    -                          | -          | -                      | -                  | -                ;  // 0x2030
    -                          | -          | -                      | -                  | -                ;  // 0x2040
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2050
L4:
    // Nova fuente: linea 11, columna 46
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x2060
    -                          | -          | -                      | -                  | -                ;  // 0x2070
    -                          | -          | -                      | -                  | -                ;  // 0x2080
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x2090
    // Nova fuente: linea 11, columna 41
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x20A0
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x20B0
    -                          | -          | -                      | -                  | -                ;  // 0x20C0
    -                          | -          | -                      | -                  | -                ;  // 0x20D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x20E0
    -                          | -          | -                      | -                  | -                ;  // 0x20F0
    -                          | -          | -                      | -                  | -                ;  // 0x2100
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x2110
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x2120
    -                          | -          | -                      | -                  | br.al L3         ;  // 0x2130
    -                          | -          | -                      | -                  | -                ;  // 0x2140
L5:
L1:
    // Nova fuente: linea 10, columna 45
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x2150
    -                          | -          | -                      | -                  | -                ;  // 0x2160
    -                          | -          | -                      | -                  | -                ;  // 0x2170
    -                          | -          | sw r10, #76(r14)       | -                  | -                ;  // 0x2180
    // Nova fuente: linea 10, columna 40
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x2190
    -                          | -          | lw r11, #76(r14)       | -                  | -                ;  // 0x21A0
    -                          | -          | -                      | -                  | -                ;  // 0x21B0
    -                          | -          | -                      | -                  | -                ;  // 0x21C0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x21D0
    -                          | -          | -                      | -                  | -                ;  // 0x21E0
    -                          | -          | -                      | -                  | -                ;  // 0x21F0
    -                          | -          | sw r10, #80(r14)       | -                  | -                ;  // 0x2200
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x2210
    -                          | -          | -                      | -                  | br.al L0         ;  // 0x2220
    -                          | -          | -                      | -                  | -                ;  // 0x2230
L2:
    // Nova fuente: linea 5, columna 9
    -                          | -          | lw r15, #96(r14)       | -                  | -                ;  // 0x2240
    addi r14, r14, #100        | -          | -                      | -                  | -                ;  // 0x2250
    -                          | -          | -                      | -                  | -                ;  // 0x2260
    -                          | -          | -                      | -                  | -                ;  // 0x2270
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x2280
    -                          | -          | -                      | -                  | -                ;  // 0x2290
    // functio principale
principale:
    // marco de 268 bytes, guarda R15 en #264(r14)
    subi r14, r14, #268        | -          | -                      | -                  | -                ;  // 0x22A0
    -                          | -          | -                      | -                  | -                ;  // 0x22B0
    -                          | -          | -                      | -                  | -                ;  // 0x22C0
    -                          | -          | sw r15, #264(r14)      | -                  | -                ;  // 0x22D0
__principale_cuerpo:
    // Nova fuente: linea 25, columna 41
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x22E0
    -                          | -          | -                      | -                  | -                ;  // 0x22F0
    -                          | -          | -                      | -                  | -                ;  // 0x2300
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2310
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x2320
    -                          | -          | -                      | -                  | -                ;  // 0x2330
    -                          | -          | -                      | -                  | -                ;  // 0x2340
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2350
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2360
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2370
    -                          | -          | -                      | -                  | -                ;  // 0x2380
    -                          | -          | -                      | -                  | -                ;  // 0x2390
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x23A0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x23B0
    -                          | -          | -                      | -                  | -                ;  // 0x23C0
    -                          | -          | -                      | -                  | -                ;  // 0x23D0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x23E0
    // Nova fuente: linea 25, columna 45
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x23F0
    -                          | -          | -                      | -                  | -                ;  // 0x2400
    -                          | -          | -                      | -                  | -                ;  // 0x2410
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2420
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x2430
    -                          | -          | -                      | -                  | -                ;  // 0x2440
    -                          | -          | -                      | -                  | -                ;  // 0x2450
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2460
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2470
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2480
    -                          | -          | -                      | -                  | -                ;  // 0x2490
    -                          | -          | -                      | -                  | -                ;  // 0x24A0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x24B0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x24C0
    -                          | -          | -                      | -                  | -                ;  // 0x24D0
    -                          | -          | -                      | -                  | -                ;  // 0x24E0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x24F0
    // Nova fuente: linea 25, columna 49
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2500
    -                          | -          | -                      | -                  | -                ;  // 0x2510
    -                          | -          | -                      | -                  | -                ;  // 0x2520
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2530
    movi r10, #2               | -          | -                      | -                  | -                ;  // 0x2540
    -                          | -          | -                      | -                  | -                ;  // 0x2550
    -                          | -          | -                      | -                  | -                ;  // 0x2560
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2570
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2580
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2590
    -                          | -          | -                      | -                  | -                ;  // 0x25A0
    -                          | -          | -                      | -                  | -                ;  // 0x25B0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x25C0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x25D0
    -                          | -          | -                      | -                  | -                ;  // 0x25E0
    -                          | -          | -                      | -                  | -                ;  // 0x25F0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2600
    // Nova fuente: linea 25, columna 53
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2610
    -                          | -          | -                      | -                  | -                ;  // 0x2620
    -                          | -          | -                      | -                  | -                ;  // 0x2630
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2640
    movi r10, #3               | -          | -                      | -                  | -                ;  // 0x2650
    -                          | -          | -                      | -                  | -                ;  // 0x2660
    -                          | -          | -                      | -                  | -                ;  // 0x2670
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2680
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2690
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x26A0
    -                          | -          | -                      | -                  | -                ;  // 0x26B0
    -                          | -          | -                      | -                  | -                ;  // 0x26C0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x26D0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x26E0
    -                          | -          | -                      | -                  | -                ;  // 0x26F0
    -                          | -          | -                      | -                  | -                ;  // 0x2700
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2710
    // Nova fuente: linea 25, columna 57
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2720
    -                          | -          | -                      | -                  | -                ;  // 0x2730
    -                          | -          | -                      | -                  | -                ;  // 0x2740
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2750
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x2760
    -                          | -          | -                      | -                  | -                ;  // 0x2770
    -                          | -          | -                      | -                  | -                ;  // 0x2780
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2790
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x27A0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x27B0
    -                          | -          | -                      | -                  | -                ;  // 0x27C0
    -                          | -          | -                      | -                  | -                ;  // 0x27D0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x27E0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x27F0
    -                          | -          | -                      | -                  | -                ;  // 0x2800
    -                          | -          | -                      | -                  | -                ;  // 0x2810
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2820
    // Nova fuente: linea 26, columna 3
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2830
    -                          | -          | -                      | -                  | -                ;  // 0x2840
    -                          | -          | -                      | -                  | -                ;  // 0x2850
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2860
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x2870
    -                          | -          | -                      | -                  | -                ;  // 0x2880
    -                          | -          | -                      | -                  | -                ;  // 0x2890
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x28A0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x28B0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x28C0
    -                          | -          | -                      | -                  | -                ;  // 0x28D0
    -                          | -          | -                      | -                  | -                ;  // 0x28E0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x28F0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2900
    -                          | -          | -                      | -                  | -                ;  // 0x2910
    -                          | -          | -                      | -                  | -                ;  // 0x2920
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2930
    // Nova fuente: linea 26, columna 7
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x2940
    -                          | -          | -                      | -                  | -                ;  // 0x2950
    -                          | -          | -                      | -                  | -                ;  // 0x2960
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2970
    movi r10, #6               | -          | -                      | -                  | -                ;  // 0x2980
    -                          | -          | -                      | -                  | -                ;  // 0x2990
    -                          | -          | -                      | -                  | -                ;  // 0x29A0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x29B0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x29C0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x29D0
    -                          | -          | -                      | -                  | -                ;  // 0x29E0
    -                          | -          | -                      | -                  | -                ;  // 0x29F0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2A00
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2A10
    -                          | -          | -                      | -                  | -                ;  // 0x2A20
    -                          | -          | -                      | -                  | -                ;  // 0x2A30
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2A40
    // Nova fuente: linea 26, columna 11
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x2A50
    -                          | -          | -                      | -                  | -                ;  // 0x2A60
    -                          | -          | -                      | -                  | -                ;  // 0x2A70
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2A80
    movi r10, #7               | -          | -                      | -                  | -                ;  // 0x2A90
    -                          | -          | -                      | -                  | -                ;  // 0x2AA0
    -                          | -          | -                      | -                  | -                ;  // 0x2AB0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2AC0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2AD0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2AE0
    -                          | -          | -                      | -                  | -                ;  // 0x2AF0
    -                          | -          | -                      | -                  | -                ;  // 0x2B00
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2B10
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2B20
    -                          | -          | -                      | -                  | -                ;  // 0x2B30
    -                          | -          | -                      | -                  | -                ;  // 0x2B40
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2B50
    // Nova fuente: linea 26, columna 15
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x2B60
    -                          | -          | -                      | -                  | -                ;  // 0x2B70
    -                          | -          | -                      | -                  | -                ;  // 0x2B80
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2B90
    movi r10, #8               | -          | -                      | -                  | -                ;  // 0x2BA0
    -                          | -          | -                      | -                  | -                ;  // 0x2BB0
    -                          | -          | -                      | -                  | -                ;  // 0x2BC0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2BD0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2BE0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2BF0
    -                          | -          | -                      | -                  | -                ;  // 0x2C00
    -                          | -          | -                      | -                  | -                ;  // 0x2C10
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2C20
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2C30
    -                          | -          | -                      | -                  | -                ;  // 0x2C40
    -                          | -          | -                      | -                  | -                ;  // 0x2C50
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2C60
    // Nova fuente: linea 26, columna 19
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2C70
    -                          | -          | -                      | -                  | -                ;  // 0x2C80
    -                          | -          | -                      | -                  | -                ;  // 0x2C90
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2CA0
    movi r10, #9               | -          | -                      | -                  | -                ;  // 0x2CB0
    -                          | -          | -                      | -                  | -                ;  // 0x2CC0
    -                          | -          | -                      | -                  | -                ;  // 0x2CD0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2CE0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2CF0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2D00
    -                          | -          | -                      | -                  | -                ;  // 0x2D10
    -                          | -          | -                      | -                  | -                ;  // 0x2D20
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2D30
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2D40
    -                          | -          | -                      | -                  | -                ;  // 0x2D50
    -                          | -          | -                      | -                  | -                ;  // 0x2D60
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2D70
    // Nova fuente: linea 27, columna 3
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2D80
    -                          | -          | -                      | -                  | -                ;  // 0x2D90
    -                          | -          | -                      | -                  | -                ;  // 0x2DA0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2DB0
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x2DC0
    -                          | -          | -                      | -                  | -                ;  // 0x2DD0
    -                          | -          | -                      | -                  | -                ;  // 0x2DE0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2DF0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2E00
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2E10
    -                          | -          | -                      | -                  | -                ;  // 0x2E20
    -                          | -          | -                      | -                  | -                ;  // 0x2E30
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2E40
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2E50
    -                          | -          | -                      | -                  | -                ;  // 0x2E60
    -                          | -          | -                      | -                  | -                ;  // 0x2E70
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2E80
    // Nova fuente: linea 27, columna 7
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x2E90
    -                          | -          | -                      | -                  | -                ;  // 0x2EA0
    -                          | -          | -                      | -                  | -                ;  // 0x2EB0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2EC0
    movi r10, #11              | -          | -                      | -                  | -                ;  // 0x2ED0
    -                          | -          | -                      | -                  | -                ;  // 0x2EE0
    -                          | -          | -                      | -                  | -                ;  // 0x2EF0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x2F00
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x2F10
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x2F20
    -                          | -          | -                      | -                  | -                ;  // 0x2F30
    -                          | -          | -                      | -                  | -                ;  // 0x2F40
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x2F50
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x2F60
    -                          | -          | -                      | -                  | -                ;  // 0x2F70
    -                          | -          | -                      | -                  | -                ;  // 0x2F80
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x2F90
    // Nova fuente: linea 27, columna 11
    movi r10, #90              | -          | -                      | -                  | -                ;  // 0x2FA0
    -                          | -          | -                      | -                  | -                ;  // 0x2FB0
    -                          | -          | -                      | -                  | -                ;  // 0x2FC0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x2FD0
    movi r10, #12              | -          | -                      | -                  | -                ;  // 0x2FE0
    -                          | -          | -                      | -                  | -                ;  // 0x2FF0
    -                          | -          | -                      | -                  | -                ;  // 0x3000
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3010
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3020
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3030
    -                          | -          | -                      | -                  | -                ;  // 0x3040
    -                          | -          | -                      | -                  | -                ;  // 0x3050
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3060
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3070
    -                          | -          | -                      | -                  | -                ;  // 0x3080
    -                          | -          | -                      | -                  | -                ;  // 0x3090
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x30A0
    // Nova fuente: linea 27, columna 15
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x30B0
    -                          | -          | -                      | -                  | -                ;  // 0x30C0
    -                          | -          | -                      | -                  | -                ;  // 0x30D0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x30E0
    movi r10, #13              | -          | -                      | -                  | -                ;  // 0x30F0
    -                          | -          | -                      | -                  | -                ;  // 0x3100
    -                          | -          | -                      | -                  | -                ;  // 0x3110
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3120
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3130
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3140
    -                          | -          | -                      | -                  | -                ;  // 0x3150
    -                          | -          | -                      | -                  | -                ;  // 0x3160
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3170
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3180
    -                          | -          | -                      | -                  | -                ;  // 0x3190
    -                          | -          | -                      | -                  | -                ;  // 0x31A0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x31B0
    // Nova fuente: linea 27, columna 19
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x31C0
    -                          | -          | -                      | -                  | -                ;  // 0x31D0
    -                          | -          | -                      | -                  | -                ;  // 0x31E0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x31F0
    movi r10, #14              | -          | -                      | -                  | -                ;  // 0x3200
    -                          | -          | -                      | -                  | -                ;  // 0x3210
    -                          | -          | -                      | -                  | -                ;  // 0x3220
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3230
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3240
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3250
    -                          | -          | -                      | -                  | -                ;  // 0x3260
    -                          | -          | -                      | -                  | -                ;  // 0x3270
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3280
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3290
    -                          | -          | -                      | -                  | -                ;  // 0x32A0
    -                          | -          | -                      | -                  | -                ;  // 0x32B0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x32C0
    // Nova fuente: linea 28, columna 3
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x32D0
    -                          | -          | -                      | -                  | -                ;  // 0x32E0
    -                          | -          | -                      | -                  | -                ;  // 0x32F0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3300
    movi r10, #15              | -          | -                      | -                  | -                ;  // 0x3310
    -                          | -          | -                      | -                  | -                ;  // 0x3320
    -                          | -          | -                      | -                  | -                ;  // 0x3330
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3340
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3350
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3360
    -                          | -          | -                      | -                  | -                ;  // 0x3370
    -                          | -          | -                      | -                  | -                ;  // 0x3380
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3390
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x33A0
    -                          | -          | -                      | -                  | -                ;  // 0x33B0
    -                          | -          | -                      | -                  | -                ;  // 0x33C0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x33D0
    // Nova fuente: linea 28, columna 7
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x33E0
    -                          | -          | -                      | -                  | -                ;  // 0x33F0
    -                          | -          | -                      | -                  | -                ;  // 0x3400
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3410
    movi r10, #16              | -          | -                      | -                  | -                ;  // 0x3420
    -                          | -          | -                      | -                  | -                ;  // 0x3430
    -                          | -          | -                      | -                  | -                ;  // 0x3440
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3450
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3460
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3470
    -                          | -          | -                      | -                  | -                ;  // 0x3480
    -                          | -          | -                      | -                  | -                ;  // 0x3490
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x34A0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x34B0
    -                          | -          | -                      | -                  | -                ;  // 0x34C0
    -                          | -          | -                      | -                  | -                ;  // 0x34D0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x34E0
    // Nova fuente: linea 28, columna 11
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x34F0
    -                          | -          | -                      | -                  | -                ;  // 0x3500
    -                          | -          | -                      | -                  | -                ;  // 0x3510
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3520
    movi r10, #17              | -          | -                      | -                  | -                ;  // 0x3530
    -                          | -          | -                      | -                  | -                ;  // 0x3540
    -                          | -          | -                      | -                  | -                ;  // 0x3550
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3560
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3570
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3580
    -                          | -          | -                      | -                  | -                ;  // 0x3590
    -                          | -          | -                      | -                  | -                ;  // 0x35A0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x35B0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x35C0
    -                          | -          | -                      | -                  | -                ;  // 0x35D0
    -                          | -          | -                      | -                  | -                ;  // 0x35E0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x35F0
    // Nova fuente: linea 28, columna 15
    movi r10, #50              | -          | -                      | -                  | -                ;  // 0x3600
    -                          | -          | -                      | -                  | -                ;  // 0x3610
    -                          | -          | -                      | -                  | -                ;  // 0x3620
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3630
    movi r10, #18              | -          | -                      | -                  | -                ;  // 0x3640
    -                          | -          | -                      | -                  | -                ;  // 0x3650
    -                          | -          | -                      | -                  | -                ;  // 0x3660
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3670
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3680
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3690
    -                          | -          | -                      | -                  | -                ;  // 0x36A0
    -                          | -          | -                      | -                  | -                ;  // 0x36B0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x36C0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x36D0
    -                          | -          | -                      | -                  | -                ;  // 0x36E0
    -                          | -          | -                      | -                  | -                ;  // 0x36F0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3700
    // Nova fuente: linea 28, columna 19
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3710
    -                          | -          | -                      | -                  | -                ;  // 0x3720
    -                          | -          | -                      | -                  | -                ;  // 0x3730
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3740
    movi r10, #19              | -          | -                      | -                  | -                ;  // 0x3750
    -                          | -          | -                      | -                  | -                ;  // 0x3760
    -                          | -          | -                      | -                  | -                ;  // 0x3770
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3780
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3790
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x37A0
    -                          | -          | -                      | -                  | -                ;  // 0x37B0
    -                          | -          | -                      | -                  | -                ;  // 0x37C0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x37D0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x37E0
    -                          | -          | -                      | -                  | -                ;  // 0x37F0
    -                          | -          | -                      | -                  | -                ;  // 0x3800
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3810
    // Nova fuente: linea 29, columna 3
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3820
    -                          | -          | -                      | -                  | -                ;  // 0x3830
    -                          | -          | -                      | -                  | -                ;  // 0x3840
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3850
    movi r10, #20              | -          | -                      | -                  | -                ;  // 0x3860
    -                          | -          | -                      | -                  | -                ;  // 0x3870
    -                          | -          | -                      | -                  | -                ;  // 0x3880
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3890
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x38A0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x38B0
    -                          | -          | -                      | -                  | -                ;  // 0x38C0
    -                          | -          | -                      | -                  | -                ;  // 0x38D0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x38E0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x38F0
    -                          | -          | -                      | -                  | -                ;  // 0x3900
    -                          | -          | -                      | -                  | -                ;  // 0x3910
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3920
    // Nova fuente: linea 29, columna 7
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3930
    -                          | -          | -                      | -                  | -                ;  // 0x3940
    -                          | -          | -                      | -                  | -                ;  // 0x3950
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3960
    movi r10, #21              | -          | -                      | -                  | -                ;  // 0x3970
    -                          | -          | -                      | -                  | -                ;  // 0x3980
    -                          | -          | -                      | -                  | -                ;  // 0x3990
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x39A0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x39B0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x39C0
    -                          | -          | -                      | -                  | -                ;  // 0x39D0
    -                          | -          | -                      | -                  | -                ;  // 0x39E0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x39F0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3A00
    -                          | -          | -                      | -                  | -                ;  // 0x3A10
    -                          | -          | -                      | -                  | -                ;  // 0x3A20
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3A30
    // Nova fuente: linea 29, columna 11
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3A40
    -                          | -          | -                      | -                  | -                ;  // 0x3A50
    -                          | -          | -                      | -                  | -                ;  // 0x3A60
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3A70
    movi r10, #22              | -          | -                      | -                  | -                ;  // 0x3A80
    -                          | -          | -                      | -                  | -                ;  // 0x3A90
    -                          | -          | -                      | -                  | -                ;  // 0x3AA0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3AB0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3AC0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3AD0
    -                          | -          | -                      | -                  | -                ;  // 0x3AE0
    -                          | -          | -                      | -                  | -                ;  // 0x3AF0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3B00
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3B10
    -                          | -          | -                      | -                  | -                ;  // 0x3B20
    -                          | -          | -                      | -                  | -                ;  // 0x3B30
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3B40
    // Nova fuente: linea 29, columna 15
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3B50
    -                          | -          | -                      | -                  | -                ;  // 0x3B60
    -                          | -          | -                      | -                  | -                ;  // 0x3B70
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3B80
    movi r10, #23              | -          | -                      | -                  | -                ;  // 0x3B90
    -                          | -          | -                      | -                  | -                ;  // 0x3BA0
    -                          | -          | -                      | -                  | -                ;  // 0x3BB0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3BC0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3BD0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3BE0
    -                          | -          | -                      | -                  | -                ;  // 0x3BF0
    -                          | -          | -                      | -                  | -                ;  // 0x3C00
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3C10
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3C20
    -                          | -          | -                      | -                  | -                ;  // 0x3C30
    -                          | -          | -                      | -                  | -                ;  // 0x3C40
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3C50
    // Nova fuente: linea 29, columna 19
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x3C60
    -                          | -          | -                      | -                  | -                ;  // 0x3C70
    -                          | -          | -                      | -                  | -                ;  // 0x3C80
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3C90
    movi r10, #24              | -          | -                      | -                  | -                ;  // 0x3CA0
    -                          | -          | -                      | -                  | -                ;  // 0x3CB0
    -                          | -          | -                      | -                  | -                ;  // 0x3CC0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3CD0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3CE0
    addi r11, r14, #156        | -          | -                      | -                  | -                ;  // 0x3CF0
    -                          | -          | -                      | -                  | -                ;  // 0x3D00
    -                          | -          | -                      | -                  | -                ;  // 0x3D10
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3D20
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3D30
    -                          | -          | -                      | -                  | -                ;  // 0x3D40
    -                          | -          | -                      | -                  | -                ;  // 0x3D50
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3D60
    // Nova fuente: linea 30, columna 36
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x3D70
    -                          | -          | -                      | -                  | -                ;  // 0x3D80
    -                          | -          | -                      | -                  | -                ;  // 0x3D90
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3DA0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x3DB0
    -                          | -          | -                      | -                  | -                ;  // 0x3DC0
    -                          | -          | -                      | -                  | -                ;  // 0x3DD0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3DE0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3DF0
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x3E00
    -                          | -          | -                      | -                  | -                ;  // 0x3E10
    -                          | -          | -                      | -                  | -                ;  // 0x3E20
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3E30
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x3E40
    -                          | -          | -                      | -                  | -                ;  // 0x3E50
    -                          | -          | -                      | -                  | -                ;  // 0x3E60
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3E70
    // Nova fuente: linea 30, columna 40
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x3E80
    -                          | -          | -                      | -                  | -                ;  // 0x3E90
    -                          | -          | -                      | -                  | -                ;  // 0x3EA0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3EB0
    // Nova fuente: linea 30, columna 39
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x3EC0
    -                          | -          | -                      | -                  | -                ;  // 0x3ED0
    -                          | -          | -                      | -                  | -                ;  // 0x3EE0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x3EF0
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x3F00
    -                          | -          | -                      | -                  | -                ;  // 0x3F10
    -                          | -          | -                      | -                  | -                ;  // 0x3F20
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x3F30
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x3F40
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x3F50
    -                          | -          | -                      | -                  | -                ;  // 0x3F60
    -                          | -          | -                      | -                  | -                ;  // 0x3F70
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x3F80
    -                          | -          | lw r10, #260(r14)      | -                  | -                ;  // 0x3F90
    -                          | -          | -                      | -                  | -                ;  // 0x3FA0
    -                          | -          | -                      | -                  | -                ;  // 0x3FB0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x3FC0
    // Nova fuente: linea 30, columna 43
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x3FD0
    -                          | -          | -                      | -                  | -                ;  // 0x3FE0
    -                          | -          | -                      | -                  | -                ;  // 0x3FF0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4000
    movi r10, #2               | -          | -                      | -                  | -                ;  // 0x4010
    -                          | -          | -                      | -                  | -                ;  // 0x4020
    -                          | -          | -                      | -                  | -                ;  // 0x4030
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x4040
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x4050
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x4060
    -                          | -          | -                      | -                  | -                ;  // 0x4070
    -                          | -          | -                      | -                  | -                ;  // 0x4080
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x4090
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x40A0
    -                          | -          | -                      | -                  | -                ;  // 0x40B0
    -                          | -          | -                      | -                  | -                ;  // 0x40C0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x40D0
    // Nova fuente: linea 31, columna 4
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x40E0
    -                          | -          | -                      | -                  | -                ;  // 0x40F0
    -                          | -          | -                      | -                  | -                ;  // 0x4100
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4110
    // Nova fuente: linea 31, columna 3
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x4120
    -                          | -          | -                      | -                  | -                ;  // 0x4130
    -                          | -          | -                      | -                  | -                ;  // 0x4140
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x4150
    movi r10, #3               | -          | -                      | -                  | -                ;  // 0x4160
    -                          | -          | -                      | -                  | -                ;  // 0x4170
    -                          | -          | -                      | -                  | -                ;  // 0x4180
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4190
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x41A0
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x41B0
    -                          | -          | -                      | -                  | -                ;  // 0x41C0
    -                          | -          | -                      | -                  | -                ;  // 0x41D0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x41E0
    -                          | -          | lw r10, #260(r14)      | -                  | -                ;  // 0x41F0
    -                          | -          | -                      | -                  | -                ;  // 0x4200
    -                          | -          | -                      | -                  | -                ;  // 0x4210
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x4220
    // Nova fuente: linea 31, columna 7
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x4230
    -                          | -          | -                      | -                  | -                ;  // 0x4240
    -                          | -          | -                      | -                  | -                ;  // 0x4250
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4260
    movi r10, #4               | -          | -                      | -                  | -                ;  // 0x4270
    -                          | -          | -                      | -                  | -                ;  // 0x4280
    -                          | -          | -                      | -                  | -                ;  // 0x4290
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x42A0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x42B0
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x42C0
    -                          | -          | -                      | -                  | -                ;  // 0x42D0
    -                          | -          | -                      | -                  | -                ;  // 0x42E0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x42F0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x4300
    -                          | -          | -                      | -                  | -                ;  // 0x4310
    -                          | -          | -                      | -                  | -                ;  // 0x4320
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x4330
    // Nova fuente: linea 31, columna 11
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x4340
    -                          | -          | -                      | -                  | -                ;  // 0x4350
    -                          | -          | -                      | -                  | -                ;  // 0x4360
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4370
    // Nova fuente: linea 31, columna 10
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x4380
    -                          | -          | -                      | -                  | -                ;  // 0x4390
    -                          | -          | -                      | -                  | -                ;  // 0x43A0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x43B0
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x43C0
    -                          | -          | -                      | -                  | -                ;  // 0x43D0
    -                          | -          | -                      | -                  | -                ;  // 0x43E0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x43F0
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x4400
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x4410
    -                          | -          | -                      | -                  | -                ;  // 0x4420
    -                          | -          | -                      | -                  | -                ;  // 0x4430
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x4440
    -                          | -          | lw r10, #260(r14)      | -                  | -                ;  // 0x4450
    -                          | -          | -                      | -                  | -                ;  // 0x4460
    -                          | -          | -                      | -                  | -                ;  // 0x4470
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x4480
    // Nova fuente: linea 32, columna 4
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x4490
    -                          | -          | -                      | -                  | -                ;  // 0x44A0
    -                          | -          | -                      | -                  | -                ;  // 0x44B0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x44C0
    movi r10, #6               | -          | -                      | -                  | -                ;  // 0x44D0
    -                          | -          | -                      | -                  | -                ;  // 0x44E0
    -                          | -          | -                      | -                  | -                ;  // 0x44F0
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x4500
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x4510
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x4520
    -                          | -          | -                      | -                  | -                ;  // 0x4530
    -                          | -          | -                      | -                  | -                ;  // 0x4540
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x4550
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x4560
    -                          | -          | -                      | -                  | -                ;  // 0x4570
    -                          | -          | -                      | -                  | -                ;  // 0x4580
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x4590
    // Nova fuente: linea 32, columna 8
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x45A0
    -                          | -          | -                      | -                  | -                ;  // 0x45B0
    -                          | -          | -                      | -                  | -                ;  // 0x45C0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x45D0
    // Nova fuente: linea 32, columna 7
    neg r10, r10               | -          | -                      | -                  | -                ;  // 0x45E0
    -                          | -          | -                      | -                  | -                ;  // 0x45F0
    -                          | -          | -                      | -                  | -                ;  // 0x4600
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x4610
    movi r10, #7               | -          | -                      | -                  | -                ;  // 0x4620
    -                          | -          | -                      | -                  | -                ;  // 0x4630
    -                          | -          | -                      | -                  | -                ;  // 0x4640
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4650
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x4660
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x4670
    -                          | -          | -                      | -                  | -                ;  // 0x4680
    -                          | -          | -                      | -                  | -                ;  // 0x4690
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x46A0
    -                          | -          | lw r10, #260(r14)      | -                  | -                ;  // 0x46B0
    -                          | -          | -                      | -                  | -                ;  // 0x46C0
    -                          | -          | -                      | -                  | -                ;  // 0x46D0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x46E0
    // Nova fuente: linea 32, columna 11
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x46F0
    -                          | -          | -                      | -                  | -                ;  // 0x4700
    -                          | -          | -                      | -                  | -                ;  // 0x4710
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4720
    movi r10, #8               | -          | -                      | -                  | -                ;  // 0x4730
    -                          | -          | -                      | -                  | -                ;  // 0x4740
    -                          | -          | -                      | -                  | -                ;  // 0x4750
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x4760
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x4770
    addi r11, r14, #120        | -          | -                      | -                  | -                ;  // 0x4780
    -                          | -          | -                      | -                  | -                ;  // 0x4790
    -                          | -          | -                      | -                  | -                ;  // 0x47A0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x47B0
    -                          | -          | lw r10, #256(r14)      | -                  | -                ;  // 0x47C0
    -                          | -          | -                      | -                  | -                ;  // 0x47D0
    -                          | -          | -                      | -                  | -                ;  // 0x47E0
    -                          | -          | sw r10, #0(r11)        | -                  | -                ;  // 0x47F0
    // Nova fuente: linea 34, columna 26
    movi r10, #3               | -          | -                      | -                  | -                ;  // 0x4800
    -                          | -          | -                      | -                  | -                ;  // 0x4810
    -                          | -          | -                      | -                  | -                ;  // 0x4820
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4830
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x4840
    // Nova fuente: linea 34, columna 10
    -                          | -          | -                      | -                  | -                ;  // 0x4850
    -                          | -          | -                      | -                  | -                ;  // 0x4860
    -                          | -          | -                      | -                  | jal.al m_matriz_7eb00c1a$es_impar ;  // 0x4870
    -                          | -          | -                      | -                  | -                ;  // 0x4880
    -                          | -          | sw r6, #256(r14)       | -                  | -                ;  // 0x4890
    // Nova fuente: linea 34, columna 6
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x48A0
    -                          | -          | -                      | -                  | -                ;  // 0x48B0
    -                          | -          | -                      | -                  | -                ;  // 0x48C0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x48D0
    -                          | -          | -                      | -                  | -                ;  // 0x48E0
    -                          | -          | -                      | -                  | -                ;  // 0x48F0
    -                          | -          | -                      | -                  | br.eq __n1_si    ;  // 0x4900
    -                          | -          | -                      | -                  | -                ;  // 0x4910
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x4920
    -                          | -          | -                      | -                  | -                ;  // 0x4930
    -                          | -          | -                      | -                  | -                ;  // 0x4940
    -                          | -          | -                      | -                  | br.al __n1_fin   ;  // 0x4950
    -                          | -          | -                      | -                  | -                ;  // 0x4960
__n1_si:
    // Nova fuente: linea 34, columna 6
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x4970
    -                          | -          | -                      | -                  | -                ;  // 0x4980
    -                          | -          | -                      | -                  | -                ;  // 0x4990
__n1_fin:
    // Nova fuente: linea 34, columna 6
    -                          | -          | sw r10, #260(r14)      | -                  | -                ;  // 0x49A0
    // Nova fuente: linea 34, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x49B0
    -                          | -          | -                      | -                  | -                ;  // 0x49C0
    -                          | -          | -                      | -                  | -                ;  // 0x49D0
    -                          | -          | -                      | -                  | br.eq L12        ;  // 0x49E0
    -                          | -          | -                      | -                  | -                ;  // 0x49F0
    // Nova fuente: linea 35, columna 6
    movi r10, #8192            | -          | -                      | -                  | -                ;  // 0x4A00
    -                          | -          | -                      | -                  | -                ;  // 0x4A10
    -                          | -          | -                      | -                  | -                ;  // 0x4A20
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4A30
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x4A40
    // Nova fuente: linea 35, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x4A50
    -                          | -          | -                      | -                  | -                ;  // 0x4A60
    movi r11, #40208           | -          | -                      | -                  | -                ;  // 0x4A70
    -                          | -          | -                      | -                  | -                ;  // 0x4A80
    -                          | -          | -                      | -                  | -                ;  // 0x4A90
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x4AA0
    -                          | -          | -                      | -                  | -                ;  // 0x4AB0
    movi r11, #42528           | -          | -                      | -                  | -                ;  // 0x4AC0
    -                          | -          | -                      | -                  | -                ;  // 0x4AD0
    -                          | -          | -                      | -                  | -                ;  // 0x4AE0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x4AF0
    -                          | -          | -                      | -                  | -                ;  // 0x4B00
    // Nova fuente: linea 36, columna 8
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x4B10
    -                          | -          | -                      | -                  | -                ;  // 0x4B20
    -                          | -          | -                      | -                  | -                ;  // 0x4B30
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4B40
    // Nova fuente: linea 36, columna 2
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x4B50
    -                          | -          | -                      | -                  | -                ;  // 0x4B60
    -                          | -          | -                      | -                  | -                ;  // 0x4B70
    -                          | -          | -                      | -                  | halt             ;  // 0x4B80
    -                          | -          | -                      | -                  | -                ;  // 0x4B90
L12:
    // Nova fuente: linea 38, columna 16
    addi r10, r14, #156        | -          | -                      | -                  | -                ;  // 0x4BA0
    -                          | -          | -                      | -                  | -                ;  // 0x4BB0
    -                          | -          | -                      | -                  | -                ;  // 0x4BC0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4BD0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x4BE0
    // Nova fuente: linea 38, columna 16
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x4BF0
    -                          | -          | -                      | -                  | -                ;  // 0x4C00
    -                          | -          | -                      | -                  | -                ;  // 0x4C10
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4C20
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x4C30
    // Nova fuente: linea 38, columna 16
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x4C40
    -                          | -          | -                      | -                  | -                ;  // 0x4C50
    -                          | -          | -                      | -                  | -                ;  // 0x4C60
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4C70
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x4C80
    // Nova fuente: linea 38, columna 24
    addi r10, r14, #120        | -          | -                      | -                  | -                ;  // 0x4C90
    -                          | -          | -                      | -                  | -                ;  // 0x4CA0
    -                          | -          | -                      | -                  | -                ;  // 0x4CB0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4CC0
    mov r9, r10                | -          | -                      | -                  | -                ;  // 0x4CD0
    // Nova fuente: linea 38, columna 24
    movi r10, #3               | -          | -                      | -                  | -                ;  // 0x4CE0
    -                          | -          | -                      | -                  | -                ;  // 0x4CF0
    -                          | -          | -                      | -                  | -                ;  // 0x4D00
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4D10
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x4D20
    // Nova fuente: linea 38, columna 24
    movi r10, #3               | -          | -                      | -                  | -                ;  // 0x4D30
    -                          | -          | -                      | -                  | -                ;  // 0x4D40
    -                          | -          | -                      | -                  | -                ;  // 0x4D50
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4D60
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x4D70
    // Nova fuente: linea 38, columna 32
    addi r10, r14, #20         | -          | -                      | -                  | -                ;  // 0x4D80
    -                          | -          | -                      | -                  | -                ;  // 0x4D90
    -                          | -          | -                      | -                  | -                ;  // 0x4DA0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4DB0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x4DC0
    // Nova fuente: linea 38, columna 32
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x4DD0
    -                          | -          | -                      | -                  | -                ;  // 0x4DE0
    -                          | -          | -                      | -                  | -                ;  // 0x4DF0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4E00
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x4E10
    // Nova fuente: linea 38, columna 32
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x4E20
    -                          | -          | -                      | -                  | -                ;  // 0x4E30
    -                          | -          | -                      | -                  | -                ;  // 0x4E40
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4E50
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x4E60
    // Nova fuente: linea 38, columna 2
    movi r11, #160             | -          | -                      | -                  | -                ;  // 0x4E70
    -                          | -          | -                      | -                  | -                ;  // 0x4E80
    -                          | -          | -                      | -                  | -                ;  // 0x4E90
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x4EA0
    -                          | -          | -                      | -                  | -                ;  // 0x4EB0
    // Nova fuente: linea 39, columna 6
    movi r10, #8236            | -          | -                      | -                  | -                ;  // 0x4EC0
    -                          | -          | -                      | -                  | -                ;  // 0x4ED0
    -                          | -          | -                      | -                  | -                ;  // 0x4EE0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x4EF0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x4F00
    // Nova fuente: linea 39, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x4F10
    -                          | -          | -                      | -                  | -                ;  // 0x4F20
    movi r11, #40208           | -          | -                      | -                  | -                ;  // 0x4F30
    -                          | -          | -                      | -                  | -                ;  // 0x4F40
    -                          | -          | -                      | -                  | -                ;  // 0x4F50
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x4F60
    -                          | -          | -                      | -                  | -                ;  // 0x4F70
    movi r11, #42528           | -          | -                      | -                  | -                ;  // 0x4F80
    -                          | -          | -                      | -                  | -                ;  // 0x4F90
    -                          | -          | -                      | -                  | -                ;  // 0x4FA0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x4FB0
    -                          | -          | -                      | -                  | -                ;  // 0x4FC0
    // Nova fuente: linea 40, columna 18
    addi r10, r14, #20         | -          | -                      | -                  | -                ;  // 0x4FD0
    -                          | -          | -                      | -                  | -                ;  // 0x4FE0
    -                          | -          | -                      | -                  | -                ;  // 0x4FF0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5000
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x5010
    // Nova fuente: linea 40, columna 18
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x5020
    -                          | -          | -                      | -                  | -                ;  // 0x5030
    -                          | -          | -                      | -                  | -                ;  // 0x5040
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5050
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x5060
    // Nova fuente: linea 40, columna 18
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x5070
    -                          | -          | -                      | -                  | -                ;  // 0x5080
    -                          | -          | -                      | -                  | -                ;  // 0x5090
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x50A0
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x50B0
    // Nova fuente: linea 40, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x50C0
    -                          | -          | -                      | -                  | -                ;  // 0x50D0
    -                          | -          | -                      | -                  | jal.al m_matriz_7eb00c1a$imprimir ;  // 0x50E0
    -                          | -          | -                      | -                  | -                ;  // 0x50F0
    // Nova fuente: linea 41, columna 6
    movi r10, #8252            | -          | -                      | -                  | -                ;  // 0x5100
    -                          | -          | -                      | -                  | -                ;  // 0x5110
    -                          | -          | -                      | -                  | -                ;  // 0x5120
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5130
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x5140
    // Nova fuente: linea 41, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x5150
    -                          | -          | -                      | -                  | -                ;  // 0x5160
    movi r11, #40208           | -          | -                      | -                  | -                ;  // 0x5170
    -                          | -          | -                      | -                  | -                ;  // 0x5180
    -                          | -          | -                      | -                  | -                ;  // 0x5190
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x51A0
    -                          | -          | -                      | -                  | -                ;  // 0x51B0
    // Nova fuente: linea 41, columna 41
    addi r10, r14, #20         | -          | -                      | -                  | -                ;  // 0x51C0
    -                          | -          | -                      | -                  | -                ;  // 0x51D0
    -                          | -          | -                      | -                  | -                ;  // 0x51E0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x51F0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x5200
    // Nova fuente: linea 41, columna 41
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x5210
    -                          | -          | -                      | -                  | -                ;  // 0x5220
    -                          | -          | -                      | -                  | -                ;  // 0x5230
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5240
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x5250
    // Nova fuente: linea 41, columna 41
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x5260
    -                          | -          | -                      | -                  | -                ;  // 0x5270
    -                          | -          | -                      | -                  | -                ;  // 0x5280
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5290
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x52A0
    // Nova fuente: linea 41, columna 20
    -                          | -          | -                      | -                  | -                ;  // 0x52B0
    -                          | -          | -                      | -                  | -                ;  // 0x52C0
    movi r11, #30368           | -          | -                      | -                  | -                ;  // 0x52D0
    -                          | -          | -                      | -                  | -                ;  // 0x52E0
    -                          | -          | -                      | -                  | -                ;  // 0x52F0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x5300
    -                          | -          | -                      | -                  | -                ;  // 0x5310
    -                          | -          | sw r6, #256(r14)       | -                  | -                ;  // 0x5320
    // Nova fuente: linea 41, columna 2
    movi r11, #38352           | -          | -                      | -                  | -                ;  // 0x5330
    -                          | -          | -                      | -                  | -                ;  // 0x5340
    -                          | -          | -                      | -                  | -                ;  // 0x5350
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x5360
    -                          | -          | -                      | -                  | -                ;  // 0x5370
    movi r11, #42528           | -          | -                      | -                  | -                ;  // 0x5380
    -                          | -          | -                      | -                  | -                ;  // 0x5390
    -                          | -          | -                      | -                  | -                ;  // 0x53A0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x53B0
    -                          | -          | -                      | -                  | -                ;  // 0x53C0
    // Nova fuente: linea 42, columna 6
    movi r10, #8268            | -          | -                      | -                  | -                ;  // 0x53D0
    -                          | -          | -                      | -                  | -                ;  // 0x53E0
    -                          | -          | -                      | -                  | -                ;  // 0x53F0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5400
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x5410
    // Nova fuente: linea 42, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x5420
    -                          | -          | -                      | -                  | -                ;  // 0x5430
    movi r11, #40208           | -          | -                      | -                  | -                ;  // 0x5440
    -                          | -          | -                      | -                  | -                ;  // 0x5450
    -                          | -          | -                      | -                  | -                ;  // 0x5460
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x5470
    -                          | -          | -                      | -                  | -                ;  // 0x5480
    // Nova fuente: linea 42, columna 37
    addi r10, r14, #20         | -          | -                      | -                  | -                ;  // 0x5490
    -                          | -          | -                      | -                  | -                ;  // 0x54A0
    -                          | -          | -                      | -                  | -                ;  // 0x54B0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x54C0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x54D0
    // Nova fuente: linea 42, columna 37
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x54E0
    -                          | -          | -                      | -                  | -                ;  // 0x54F0
    -                          | -          | -                      | -                  | -                ;  // 0x5500
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5510
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x5520
    // Nova fuente: linea 42, columna 37
    movi r10, #5               | -          | -                      | -                  | -                ;  // 0x5530
    -                          | -          | -                      | -                  | -                ;  // 0x5540
    -                          | -          | -                      | -                  | -                ;  // 0x5550
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x5560
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x5570
    // Nova fuente: linea 42, columna 18
    -                          | -          | -                      | -                  | -                ;  // 0x5580
    -                          | -          | -                      | -                  | -                ;  // 0x5590
    movi r11, #31264           | -          | -                      | -                  | -                ;  // 0x55A0
    -                          | -          | -                      | -                  | -                ;  // 0x55B0
    -                          | -          | -                      | -                  | -                ;  // 0x55C0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x55D0
    -                          | -          | -                      | -                  | -                ;  // 0x55E0
    -                          | -          | sw r6, #256(r14)       | -                  | -                ;  // 0x55F0
    // Nova fuente: linea 42, columna 2
    movi r11, #38352           | -          | -                      | -                  | -                ;  // 0x5600
    -                          | -          | -                      | -                  | -                ;  // 0x5610
    -                          | -          | -                      | -                  | -                ;  // 0x5620
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x5630
    -                          | -          | -                      | -                  | -                ;  // 0x5640
    movi r11, #42528           | -          | -                      | -                  | -                ;  // 0x5650
    -                          | -          | -                      | -                  | -                ;  // 0x5660
    -                          | -          | -                      | -                  | -                ;  // 0x5670
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x5680
    -                          | -          | -                      | -                  | -                ;  // 0x5690
    // Nova fuente: linea 43, columna 8
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x56A0
    -                          | -          | -                      | -                  | -                ;  // 0x56B0
    -                          | -          | -                      | -                  | -                ;  // 0x56C0
    -                          | -          | sw r10, #256(r14)      | -                  | -                ;  // 0x56D0
    // Nova fuente: linea 43, columna 2
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x56E0
    -                          | -          | -                      | -                  | -                ;  // 0x56F0
    -                          | -          | -                      | -                  | -                ;  // 0x5700
    -                          | -          | -                      | -                  | halt             ;  // 0x5710
    -                          | -          | -                      | -                  | -                ;  // 0x5720
    // functio m_matriz_7eb00c1a$limitar
m_matriz_7eb00c1a$limitar:
    // marco de 16 bytes
    subi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x5730
    -                          | -          | -                      | -                  | -                ;  // 0x5740
    -                          | -          | -                      | -                  | -                ;  // 0x5750
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x5760
    -                          | -          | sw r7, #4(r14)         | -                  | -                ;  // 0x5770
    -                          | -          | sw r8, #0(r14)         | -                  | -                ;  // 0x5780
__m_matriz_7eb00c1a$limitar_cuerpo:
    // Nova fuente: linea 3, columna 6
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x5790
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x57A0
    -                          | -          | -                      | -                  | -                ;  // 0x57B0
    -                          | -          | -                      | -                  | -                ;  // 0x57C0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x57D0
    -                          | -          | -                      | -                  | -                ;  // 0x57E0
    -                          | -          | -                      | -                  | -                ;  // 0x57F0
    -                          | -          | -                      | -                  | br.lt __c18_si   ;  // 0x5800
    -                          | -          | -                      | -                  | -                ;  // 0x5810
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5820
    -                          | -          | -                      | -                  | -                ;  // 0x5830
    -                          | -          | -                      | -                  | -                ;  // 0x5840
    -                          | -          | -                      | -                  | br.al __c18_fin  ;  // 0x5850
    -                          | -          | -                      | -                  | -                ;  // 0x5860
__c18_si:
    // Nova fuente: linea 3, columna 6
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x5870
    -                          | -          | -                      | -                  | -                ;  // 0x5880
    -                          | -          | -                      | -                  | -                ;  // 0x5890
__c18_fin:
    // Nova fuente: linea 3, columna 6
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x58A0
    // Nova fuente: linea 3, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x58B0
    -                          | -          | -                      | -                  | -                ;  // 0x58C0
    -                          | -          | -                      | -                  | -                ;  // 0x58D0
    -                          | -          | -                      | -                  | br.eq L13        ;  // 0x58E0
    -                          | -          | -                      | -                  | -                ;  // 0x58F0
    // Nova fuente: linea 4, columna 2
    -                          | -          | lw r6, #4(r14)         | -                  | -                ;  // 0x5900
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x5910
    -                          | -          | -                      | -                  | -                ;  // 0x5920
    -                          | -          | -                      | -                  | -                ;  // 0x5930
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x5940
    -                          | -          | -                      | -                  | -                ;  // 0x5950
    -                          | -          | -                      | -                  | br.al L14        ;  // 0x5960
    -                          | -          | -                      | -                  | -                ;  // 0x5970
L13:
    // Nova fuente: linea 5, columna 9
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x5980
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x5990
    -                          | -          | -                      | -                  | -                ;  // 0x59A0
    -                          | -          | -                      | -                  | -                ;  // 0x59B0
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x59C0
    -                          | -          | -                      | -                  | -                ;  // 0x59D0
    -                          | -          | -                      | -                  | -                ;  // 0x59E0
    -                          | -          | -                      | -                  | br.lt __c19_si   ;  // 0x59F0
    -                          | -          | -                      | -                  | -                ;  // 0x5A00
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5A10
    -                          | -          | -                      | -                  | -                ;  // 0x5A20
    -                          | -          | -                      | -                  | -                ;  // 0x5A30
    -                          | -          | -                      | -                  | br.al __c19_fin  ;  // 0x5A40
    -                          | -          | -                      | -                  | -                ;  // 0x5A50
__c19_si:
    // Nova fuente: linea 5, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x5A60
    -                          | -          | -                      | -                  | -                ;  // 0x5A70
    -                          | -          | -                      | -                  | -                ;  // 0x5A80
__c19_fin:
    // Nova fuente: linea 5, columna 9
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x5A90
    // Nova fuente: linea 5, columna 4
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x5AA0
    -                          | -          | -                      | -                  | -                ;  // 0x5AB0
    -                          | -          | -                      | -                  | -                ;  // 0x5AC0
    -                          | -          | -                      | -                  | br.eq L15        ;  // 0x5AD0
    -                          | -          | -                      | -                  | -                ;  // 0x5AE0
    // Nova fuente: linea 6, columna 2
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x5AF0
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x5B00
    -                          | -          | -                      | -                  | -                ;  // 0x5B10
    -                          | -          | -                      | -                  | -                ;  // 0x5B20
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x5B30
    -                          | -          | -                      | -                  | -                ;  // 0x5B40
    -                          | -          | -                      | -                  | br.al L16        ;  // 0x5B50
    -                          | -          | -                      | -                  | -                ;  // 0x5B60
L15:
    // Nova fuente: linea 8, columna 2
    -                          | -          | lw r6, #8(r14)         | -                  | -                ;  // 0x5B70
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x5B80
    -                          | -          | -                      | -                  | -                ;  // 0x5B90
    -                          | -          | -                      | -                  | -                ;  // 0x5BA0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x5BB0
    -                          | -          | -                      | -                  | -                ;  // 0x5BC0
L16:
L14:
    // Nova fuente: linea 2, columna 9
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x5BD0
    -                          | -          | -                      | -                  | -                ;  // 0x5BE0
    -                          | -          | -                      | -                  | -                ;  // 0x5BF0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x5C00
    -                          | -          | -                      | -                  | -                ;  // 0x5C10
    // functio m_matriz_7eb00c1a$imprimir
m_matriz_7eb00c1a$imprimir:
    // marco de 32 bytes, guarda R15 en #28(r14)
    subi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x5C20
    -                          | -          | -                      | -                  | -                ;  // 0x5C30
    -                          | -          | -                      | -                  | -                ;  // 0x5C40
    -                          | -          | sw r15, #28(r14)       | -                  | -                ;  // 0x5C50
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x5C60
    -                          | -          | sw r7, #12(r14)        | -                  | -                ;  // 0x5C70
    -                          | -          | sw r8, #16(r14)        | -                  | -                ;  // 0x5C80
__m_matriz_7eb00c1a$imprimir_cuerpo:
    // Nova fuente: linea 12, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5C90
    -                          | -          | -                      | -                  | -                ;  // 0x5CA0
    -                          | -          | -                      | -                  | -                ;  // 0x5CB0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x5CC0
    // Nova fuente: linea 12, columna 13
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x5CD0
L17:
    // Nova fuente: linea 12, columna 34
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x5CE0
    -                          | -          | -                      | -                  | -                ;  // 0x5CF0
    -                          | -          | -                      | -                  | -                ;  // 0x5D00
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x5D10
    // Nova fuente: linea 12, columna 30
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x5D20
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x5D30
    -                          | -          | -                      | -                  | -                ;  // 0x5D40
    -                          | -          | -                      | -                  | -                ;  // 0x5D50
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x5D60
    -                          | -          | -                      | -                  | -                ;  // 0x5D70
    -                          | -          | -                      | -                  | -                ;  // 0x5D80
    -                          | -          | -                      | -                  | br.lt __c20_si   ;  // 0x5D90
    -                          | -          | -                      | -                  | -                ;  // 0x5DA0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5DB0
    -                          | -          | -                      | -                  | -                ;  // 0x5DC0
    -                          | -          | -                      | -                  | -                ;  // 0x5DD0
    -                          | -          | -                      | -                  | br.al __c20_fin  ;  // 0x5DE0
    -                          | -          | -                      | -                  | -                ;  // 0x5DF0
__c20_si:
    // Nova fuente: linea 12, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x5E00
    -                          | -          | -                      | -                  | -                ;  // 0x5E10
    -                          | -          | -                      | -                  | -                ;  // 0x5E20
__c20_fin:
    // Nova fuente: linea 12, columna 30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x5E30
    // Nova fuente: linea 12, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x5E40
    -                          | -          | -                      | -                  | -                ;  // 0x5E50
    -                          | -          | -                      | -                  | -                ;  // 0x5E60
    -                          | -          | -                      | -                  | br.eq L19        ;  // 0x5E70
    -                          | -          | -                      | -                  | -                ;  // 0x5E80
    // Nova fuente: linea 13, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5E90
    -                          | -          | -                      | -                  | -                ;  // 0x5EA0
    -                          | -          | -                      | -                  | -                ;  // 0x5EB0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x5EC0
    // Nova fuente: linea 13, columna 13
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x5ED0
L20:
    // Nova fuente: linea 13, columna 34
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x5EE0
    -                          | -          | -                      | -                  | -                ;  // 0x5EF0
    -                          | -          | -                      | -                  | -                ;  // 0x5F00
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x5F10
    // Nova fuente: linea 13, columna 30
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x5F20
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x5F30
    -                          | -          | -                      | -                  | -                ;  // 0x5F40
    -                          | -          | -                      | -                  | -                ;  // 0x5F50
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x5F60
    -                          | -          | -                      | -                  | -                ;  // 0x5F70
    -                          | -          | -                      | -                  | -                ;  // 0x5F80
    -                          | -          | -                      | -                  | br.lt __c21_si   ;  // 0x5F90
    -                          | -          | -                      | -                  | -                ;  // 0x5FA0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x5FB0
    -                          | -          | -                      | -                  | -                ;  // 0x5FC0
    -                          | -          | -                      | -                  | -                ;  // 0x5FD0
    -                          | -          | -                      | -                  | br.al __c21_fin  ;  // 0x5FE0
    -                          | -          | -                      | -                  | -                ;  // 0x5FF0
__c21_si:
    // Nova fuente: linea 13, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x6000
    -                          | -          | -                      | -                  | -                ;  // 0x6010
    -                          | -          | -                      | -                  | -                ;  // 0x6020
__c21_fin:
    // Nova fuente: linea 13, columna 30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6030
    // Nova fuente: linea 13, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x6040
    -                          | -          | -                      | -                  | -                ;  // 0x6050
    -                          | -          | -                      | -                  | -                ;  // 0x6060
    -                          | -          | -                      | -                  | br.eq L22        ;  // 0x6070
    -                          | -          | -                      | -                  | -                ;  // 0x6080
    // Nova fuente: linea 14, columna 11
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x6090
    -                          | -          | -                      | -                  | -                ;  // 0x60A0
    -                          | -          | -                      | -                  | -                ;  // 0x60B0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x60C0
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x60D0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x60E0
    -                          | -          | -                      | -                  | -                ;  // 0x60F0
    -                          | -          | -                      | -                  | -                ;  // 0x6100
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x6110
    -                          | -          | -                      | -                  | -                ;  // 0x6120
    -                          | -          | -                      | -                  | -                ;  // 0x6130
    -                          | -          | -                      | -                  | br.ltu __rango22_ok ;  // 0x6140
    -                          | -          | -                      | -                  | -                ;  // 0x6150
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x6160
    -                          | -          | -                      | -                  | -                ;  // 0x6170
    -                          | -          | -                      | -                  | -                ;  // 0x6180
    -                          | -          | -                      | -                  | halt             ;  // 0x6190
    -                          | -          | -                      | -                  | -                ;  // 0x61A0
__rango22_ok:
    // Nova fuente: linea 14, columna 14
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x61B0
    -                          | -          | -                      | -                  | -                ;  // 0x61C0
    -                          | -          | -                      | -                  | -                ;  // 0x61D0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x61E0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x61F0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x6200
    -                          | -          | -                      | -                  | -                ;  // 0x6210
    -                          | -          | -                      | -                  | -                ;  // 0x6220
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x6230
    -                          | -          | -                      | -                  | -                ;  // 0x6240
    -                          | -          | -                      | -                  | -                ;  // 0x6250
    -                          | -          | -                      | -                  | br.ltu __rango23_ok ;  // 0x6260
    -                          | -          | -                      | -                  | -                ;  // 0x6270
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x6280
    -                          | -          | -                      | -                  | -                ;  // 0x6290
    -                          | -          | -                      | -                  | -                ;  // 0x62A0
    -                          | -          | -                      | -                  | halt             ;  // 0x62B0
    -                          | -          | -                      | -                  | -                ;  // 0x62C0
__rango23_ok:
    // Nova fuente: linea 14, columna 14
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x62D0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x62E0
    -                          | -          | -                      | -                  | -                ;  // 0x62F0
    -                          | -          | -                      | -                  | -                ;  // 0x6300
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x6310
    -                          | -          | -                      | -                  | -                ;  // 0x6320
    -                          | -          | -                      | -                  | -                ;  // 0x6330
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6340
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x6350
    -                          | -          | -                      | -                  | -                ;  // 0x6360
    -                          | -          | -                      | -                  | -                ;  // 0x6370
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x6380
    -                          | -          | -                      | -                  | -                ;  // 0x6390
    -                          | -          | -                      | -                  | -                ;  // 0x63A0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x63B0
    // Nova fuente: linea 14, columna 9
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x63C0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x63D0
    -                          | -          | -                      | -                  | -                ;  // 0x63E0
    -                          | -          | -                      | -                  | -                ;  // 0x63F0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x6400
    -                          | -          | -                      | -                  | -                ;  // 0x6410
    -                          | -          | -                      | -                  | -                ;  // 0x6420
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x6430
    -                          | -          | -                      | -                  | -                ;  // 0x6440
    -                          | -          | -                      | -                  | -                ;  // 0x6450
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6460
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x6470
    // Nova fuente: linea 14, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x6480
    -                          | -          | -                      | -                  | -                ;  // 0x6490
    movi r11, #38352           | -          | -                      | -                  | -                ;  // 0x64A0
    -                          | -          | -                      | -                  | -                ;  // 0x64B0
    -                          | -          | -                      | -                  | -                ;  // 0x64C0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x64D0
    -                          | -          | -                      | -                  | -                ;  // 0x64E0
L21:
    // Nova fuente: linea 13, columna 56
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x64F0
    -                          | -          | -                      | -                  | -                ;  // 0x6500
    -                          | -          | -                      | -                  | -                ;  // 0x6510
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x6520
    // Nova fuente: linea 13, columna 51
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x6530
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x6540
    -                          | -          | -                      | -                  | -                ;  // 0x6550
    -                          | -          | -                      | -                  | -                ;  // 0x6560
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x6570
    -                          | -          | -                      | -                  | -                ;  // 0x6580
    -                          | -          | -                      | -                  | -                ;  // 0x6590
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x65A0
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x65B0
    -                          | -          | -                      | -                  | br.al L20        ;  // 0x65C0
    -                          | -          | -                      | -                  | -                ;  // 0x65D0
L22:
    // Nova fuente: linea 16, columna 6
    movi r10, #8280            | -          | -                      | -                  | -                ;  // 0x65E0
    -                          | -          | -                      | -                  | -                ;  // 0x65F0
    -                          | -          | -                      | -                  | -                ;  // 0x6600
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x6610
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x6620
    // Nova fuente: linea 16, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x6630
    -                          | -          | -                      | -                  | -                ;  // 0x6640
    movi r11, #40208           | -          | -                      | -                  | -                ;  // 0x6650
    -                          | -          | -                      | -                  | -                ;  // 0x6660
    -                          | -          | -                      | -                  | -                ;  // 0x6670
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x6680
    -                          | -          | -                      | -                  | -                ;  // 0x6690
    movi r11, #42528           | -          | -                      | -                  | -                ;  // 0x66A0
    -                          | -          | -                      | -                  | -                ;  // 0x66B0
    -                          | -          | -                      | -                  | -                ;  // 0x66C0
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x66D0
    -                          | -          | -                      | -                  | -                ;  // 0x66E0
L18:
    // Nova fuente: linea 12, columna 53
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x66F0
    -                          | -          | -                      | -                  | -                ;  // 0x6700
    -                          | -          | -                      | -                  | -                ;  // 0x6710
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x6720
    // Nova fuente: linea 12, columna 48
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x6730
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x6740
    -                          | -          | -                      | -                  | -                ;  // 0x6750
    -                          | -          | -                      | -                  | -                ;  // 0x6760
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x6770
    -                          | -          | -                      | -                  | -                ;  // 0x6780
    -                          | -          | -                      | -                  | -                ;  // 0x6790
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x67A0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x67B0
    -                          | -          | -                      | -                  | br.al L17        ;  // 0x67C0
    -                          | -          | -                      | -                  | -                ;  // 0x67D0
L19:
    // Nova fuente: linea 11, columna 9
    -                          | -          | lw r15, #28(r14)       | -                  | -                ;  // 0x67E0
    addi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x67F0
    -                          | -          | -                      | -                  | -                ;  // 0x6800
    -                          | -          | -                      | -                  | -                ;  // 0x6810
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x6820
    -                          | -          | -                      | -                  | -                ;  // 0x6830
    // functio m_matriz_7eb00c1a$es_impar
m_matriz_7eb00c1a$es_impar:
    // marco de 20 bytes, guarda R15 en #16(r14)
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x6840
    -                          | -          | -                      | -                  | -                ;  // 0x6850
    -                          | -          | -                      | -                  | -                ;  // 0x6860
    -                          | -          | sw r15, #16(r14)       | -                  | -                ;  // 0x6870
    -                          | -          | sw r6, #0(r14)         | -                  | -                ;  // 0x6880
__m_matriz_7eb00c1a$es_impar_cuerpo:
    // Nova fuente: linea 20, columna 12
    movi r10, #2               | -          | -                      | -                  | -                ;  // 0x6890
    -                          | -          | -                      | -                  | -                ;  // 0x68A0
    -                          | -          | -                      | -                  | -                ;  // 0x68B0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x68C0
    // Nova fuente: linea 20, columna 8
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x68D0
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x68E0
    -                          | -          | -                      | -                  | -                ;  // 0x68F0
    -                          | -          | -                      | -                  | -                ;  // 0x6900
    movi r11, #36448           | -          | -                      | -                  | -                ;  // 0x6910
    -                          | -          | -                      | -                  | -                ;  // 0x6920
    -                          | -          | -                      | -                  | -                ;  // 0x6930
    -                          | -          | -                      | -                  | jalr.al r11      ;  // 0x6940
    -                          | -          | -                      | -                  | -                ;  // 0x6950
    -                          | -          | sw r7, #8(r14)         | -                  | -                ;  // 0x6960
    // Nova fuente: linea 20, columna 17
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x6970
    -                          | -          | -                      | -                  | -                ;  // 0x6980
    -                          | -          | -                      | -                  | -                ;  // 0x6990
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x69A0
    // Nova fuente: linea 20, columna 8
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x69B0
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x69C0
    -                          | -          | -                      | -                  | -                ;  // 0x69D0
    -                          | -          | -                      | -                  | -                ;  // 0x69E0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x69F0
    -                          | -          | -                      | -                  | -                ;  // 0x6A00
    -                          | -          | -                      | -                  | -                ;  // 0x6A10
    -                          | -          | -                      | -                  | br.eq __c22_si   ;  // 0x6A20
    -                          | -          | -                      | -                  | -                ;  // 0x6A30
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6A40
    -                          | -          | -                      | -                  | -                ;  // 0x6A50
    -                          | -          | -                      | -                  | -                ;  // 0x6A60
    -                          | -          | -                      | -                  | br.al __c22_fin  ;  // 0x6A70
    -                          | -          | -                      | -                  | -                ;  // 0x6A80
__c22_si:
    // Nova fuente: linea 20, columna 8
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x6A90
    -                          | -          | -                      | -                  | -                ;  // 0x6AA0
    -                          | -          | -                      | -                  | -                ;  // 0x6AB0
__c22_fin:
    // Nova fuente: linea 20, columna 8
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x6AC0
    // Nova fuente: linea 20, columna 2
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x6AD0
    -                          | -          | lw r15, #16(r14)       | -                  | -                ;  // 0x6AE0
    addi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x6AF0
    -                          | -          | -                      | -                  | -                ;  // 0x6B00
    -                          | -          | -                      | -                  | -                ;  // 0x6B10
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x6B20
    -                          | -          | -                      | -                  | -                ;  // 0x6B30
    // functio m_estadistica_d879e4e7$total
m_estadistica_d879e4e7$total:
    // marco de 32 bytes
    subi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x6B40
    -                          | -          | -                      | -                  | -                ;  // 0x6B50
    -                          | -          | -                      | -                  | -                ;  // 0x6B60
    -                          | -          | sw r6, #12(r14)        | -                  | -                ;  // 0x6B70
    -                          | -          | sw r7, #16(r14)        | -                  | -                ;  // 0x6B80
    -                          | -          | sw r8, #20(r14)        | -                  | -                ;  // 0x6B90
__m_estadistica_d879e4e7$total_cuerpo:
    // Nova fuente: linea 3, columna 25
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6BA0
    -                          | -          | -                      | -                  | -                ;  // 0x6BB0
    -                          | -          | -                      | -                  | -                ;  // 0x6BC0
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6BD0
    // Nova fuente: linea 3, columna 8
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x6BE0
    // Nova fuente: linea 4, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6BF0
    -                          | -          | -                      | -                  | -                ;  // 0x6C00
    -                          | -          | -                      | -                  | -                ;  // 0x6C10
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6C20
    // Nova fuente: linea 4, columna 13
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x6C30
L23:
    // Nova fuente: linea 4, columna 34
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x6C40
    -                          | -          | -                      | -                  | -                ;  // 0x6C50
    -                          | -          | -                      | -                  | -                ;  // 0x6C60
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6C70
    // Nova fuente: linea 4, columna 30
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x6C80
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x6C90
    -                          | -          | -                      | -                  | -                ;  // 0x6CA0
    -                          | -          | -                      | -                  | -                ;  // 0x6CB0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x6CC0
    -                          | -          | -                      | -                  | -                ;  // 0x6CD0
    -                          | -          | -                      | -                  | -                ;  // 0x6CE0
    -                          | -          | -                      | -                  | br.lt __c23_si   ;  // 0x6CF0
    -                          | -          | -                      | -                  | -                ;  // 0x6D00
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6D10
    -                          | -          | -                      | -                  | -                ;  // 0x6D20
    -                          | -          | -                      | -                  | -                ;  // 0x6D30
    -                          | -          | -                      | -                  | br.al __c23_fin  ;  // 0x6D40
    -                          | -          | -                      | -                  | -                ;  // 0x6D50
__c23_si:
    // Nova fuente: linea 4, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x6D60
    -                          | -          | -                      | -                  | -                ;  // 0x6D70
    -                          | -          | -                      | -                  | -                ;  // 0x6D80
__c23_fin:
    // Nova fuente: linea 4, columna 30
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x6D90
    // Nova fuente: linea 4, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x6DA0
    -                          | -          | -                      | -                  | -                ;  // 0x6DB0
    -                          | -          | -                      | -                  | -                ;  // 0x6DC0
    -                          | -          | -                      | -                  | br.eq L25        ;  // 0x6DD0
    -                          | -          | -                      | -                  | -                ;  // 0x6DE0
    // Nova fuente: linea 5, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6DF0
    -                          | -          | -                      | -                  | -                ;  // 0x6E00
    -                          | -          | -                      | -                  | -                ;  // 0x6E10
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6E20
    // Nova fuente: linea 5, columna 13
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x6E30
L26:
    // Nova fuente: linea 5, columna 34
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x6E40
    -                          | -          | -                      | -                  | -                ;  // 0x6E50
    -                          | -          | -                      | -                  | -                ;  // 0x6E60
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x6E70
    // Nova fuente: linea 5, columna 30
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x6E80
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x6E90
    -                          | -          | -                      | -                  | -                ;  // 0x6EA0
    -                          | -          | -                      | -                  | -                ;  // 0x6EB0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x6EC0
    -                          | -          | -                      | -                  | -                ;  // 0x6ED0
    -                          | -          | -                      | -                  | -                ;  // 0x6EE0
    -                          | -          | -                      | -                  | br.lt __c24_si   ;  // 0x6EF0
    -                          | -          | -                      | -                  | -                ;  // 0x6F00
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x6F10
    -                          | -          | -                      | -                  | -                ;  // 0x6F20
    -                          | -          | -                      | -                  | -                ;  // 0x6F30
    -                          | -          | -                      | -                  | br.al __c24_fin  ;  // 0x6F40
    -                          | -          | -                      | -                  | -                ;  // 0x6F50
__c24_si:
    // Nova fuente: linea 5, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x6F60
    -                          | -          | -                      | -                  | -                ;  // 0x6F70
    -                          | -          | -                      | -                  | -                ;  // 0x6F80
__c24_fin:
    // Nova fuente: linea 5, columna 30
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x6F90
    // Nova fuente: linea 5, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x6FA0
    -                          | -          | -                      | -                  | -                ;  // 0x6FB0
    -                          | -          | -                      | -                  | -                ;  // 0x6FC0
    -                          | -          | -                      | -                  | br.eq L28        ;  // 0x6FD0
    -                          | -          | -                      | -                  | -                ;  // 0x6FE0
    // Nova fuente: linea 6, columna 12
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x6FF0
    -                          | -          | -                      | -                  | -                ;  // 0x7000
    -                          | -          | -                      | -                  | -                ;  // 0x7010
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7020
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x7030
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x7040
    -                          | -          | -                      | -                  | -                ;  // 0x7050
    -                          | -          | -                      | -                  | -                ;  // 0x7060
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x7070
    -                          | -          | -                      | -                  | -                ;  // 0x7080
    -                          | -          | -                      | -                  | -                ;  // 0x7090
    -                          | -          | -                      | -                  | br.ltu __rango24_ok ;  // 0x70A0
    -                          | -          | -                      | -                  | -                ;  // 0x70B0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x70C0
    -                          | -          | -                      | -                  | -                ;  // 0x70D0
    -                          | -          | -                      | -                  | -                ;  // 0x70E0
    -                          | -          | -                      | -                  | halt             ;  // 0x70F0
    -                          | -          | -                      | -                  | -                ;  // 0x7100
__rango24_ok:
    // Nova fuente: linea 6, columna 15
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x7110
    -                          | -          | -                      | -                  | -                ;  // 0x7120
    -                          | -          | -                      | -                  | -                ;  // 0x7130
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7140
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x7150
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x7160
    -                          | -          | -                      | -                  | -                ;  // 0x7170
    -                          | -          | -                      | -                  | -                ;  // 0x7180
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x7190
    -                          | -          | -                      | -                  | -                ;  // 0x71A0
    -                          | -          | -                      | -                  | -                ;  // 0x71B0
    -                          | -          | -                      | -                  | br.ltu __rango25_ok ;  // 0x71C0
    -                          | -          | -                      | -                  | -                ;  // 0x71D0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x71E0
    -                          | -          | -                      | -                  | -                ;  // 0x71F0
    -                          | -          | -                      | -                  | -                ;  // 0x7200
    -                          | -          | -                      | -                  | halt             ;  // 0x7210
    -                          | -          | -                      | -                  | -                ;  // 0x7220
__rango25_ok:
    // Nova fuente: linea 6, columna 15
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x7230
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x7240
    -                          | -          | -                      | -                  | -                ;  // 0x7250
    -                          | -          | -                      | -                  | -                ;  // 0x7260
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x7270
    -                          | -          | -                      | -                  | -                ;  // 0x7280
    -                          | -          | -                      | -                  | -                ;  // 0x7290
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x72A0
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x72B0
    -                          | -          | -                      | -                  | -                ;  // 0x72C0
    -                          | -          | -                      | -                  | -                ;  // 0x72D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x72E0
    -                          | -          | -                      | -                  | -                ;  // 0x72F0
    -                          | -          | -                      | -                  | -                ;  // 0x7300
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7310
    // Nova fuente: linea 6, columna 10
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x7320
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x7330
    -                          | -          | -                      | -                  | -                ;  // 0x7340
    -                          | -          | -                      | -                  | -                ;  // 0x7350
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x7360
    -                          | -          | -                      | -                  | -                ;  // 0x7370
    -                          | -          | -                      | -                  | -                ;  // 0x7380
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x7390
    -                          | -          | -                      | -                  | -                ;  // 0x73A0
    -                          | -          | -                      | -                  | -                ;  // 0x73B0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x73C0
    // Nova fuente: linea 6, columna 2
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x73D0
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x73E0
    -                          | -          | -                      | -                  | -                ;  // 0x73F0
    -                          | -          | -                      | -                  | -                ;  // 0x7400
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x7410
    -                          | -          | -                      | -                  | -                ;  // 0x7420
    -                          | -          | -                      | -                  | -                ;  // 0x7430
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7440
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x7450
L27:
    // Nova fuente: linea 5, columna 56
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x7460
    -                          | -          | -                      | -                  | -                ;  // 0x7470
    -                          | -          | -                      | -                  | -                ;  // 0x7480
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7490
    // Nova fuente: linea 5, columna 51
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x74A0
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x74B0
    -                          | -          | -                      | -                  | -                ;  // 0x74C0
    -                          | -          | -                      | -                  | -                ;  // 0x74D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x74E0
    -                          | -          | -                      | -                  | -                ;  // 0x74F0
    -                          | -          | -                      | -                  | -                ;  // 0x7500
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x7510
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x7520
    -                          | -          | -                      | -                  | br.al L26        ;  // 0x7530
    -                          | -          | -                      | -                  | -                ;  // 0x7540
L28:
L24:
    // Nova fuente: linea 4, columna 53
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x7550
    -                          | -          | -                      | -                  | -                ;  // 0x7560
    -                          | -          | -                      | -                  | -                ;  // 0x7570
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7580
    // Nova fuente: linea 4, columna 48
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x7590
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x75A0
    -                          | -          | -                      | -                  | -                ;  // 0x75B0
    -                          | -          | -                      | -                  | -                ;  // 0x75C0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x75D0
    -                          | -          | -                      | -                  | -                ;  // 0x75E0
    -                          | -          | -                      | -                  | -                ;  // 0x75F0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x7600
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x7610
    -                          | -          | -                      | -                  | br.al L23        ;  // 0x7620
    -                          | -          | -                      | -                  | -                ;  // 0x7630
L25:
    // Nova fuente: linea 9, columna 2
    -                          | -          | lw r6, #8(r14)         | -                  | -                ;  // 0x7640
    addi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x7650
    -                          | -          | -                      | -                  | -                ;  // 0x7660
    -                          | -          | -                      | -                  | -                ;  // 0x7670
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x7680
    -                          | -          | -                      | -                  | -                ;  // 0x7690
    // functio m_estadistica_d879e4e7$promedio
m_estadistica_d879e4e7$promedio:
    // marco de 32 bytes, guarda R15 en #28(r14)
    subi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x76A0
    -                          | -          | -                      | -                  | -                ;  // 0x76B0
    -                          | -          | -                      | -                  | -                ;  // 0x76C0
    -                          | -          | sw r15, #28(r14)       | -                  | -                ;  // 0x76D0
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x76E0
    -                          | -          | sw r7, #8(r14)         | -                  | -                ;  // 0x76F0
    -                          | -          | sw r8, #12(r14)        | -                  | -                ;  // 0x7700
__m_estadistica_d879e4e7$promedio_cuerpo:
    // Nova fuente: linea 12, columna 27
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x7710
    -                          | -          | -                      | -                  | -                ;  // 0x7720
    -                          | -          | -                      | -                  | -                ;  // 0x7730
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x7740
    // Nova fuente: linea 12, columna 42
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x7750
    -                          | -          | -                      | -                  | -                ;  // 0x7760
    -                          | -          | -                      | -                  | -                ;  // 0x7770
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x7780
    // Nova fuente: linea 12, columna 27
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x7790
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x77A0
    -                          | -          | -                      | -                  | -                ;  // 0x77B0
    -                          | -          | -                      | -                  | -                ;  // 0x77C0
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x77D0
    -                          | -          | -                      | -                  | -                ;  // 0x77E0
    -                          | -          | -                      | -                  | -                ;  // 0x77F0
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7800
    // Nova fuente: linea 12, columna 8
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x7810
    // Nova fuente: linea 13, columna 14
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x7820
    -                          | -          | -                      | -                  | -                ;  // 0x7830
    -                          | -          | -                      | -                  | -                ;  // 0x7840
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x7850
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x7860
    // Nova fuente: linea 13, columna 14
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x7870
    -                          | -          | -                      | -                  | -                ;  // 0x7880
    -                          | -          | -                      | -                  | -                ;  // 0x7890
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x78A0
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x78B0
    // Nova fuente: linea 13, columna 14
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x78C0
    -                          | -          | -                      | -                  | -                ;  // 0x78D0
    -                          | -          | -                      | -                  | -                ;  // 0x78E0
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x78F0
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x7900
    // Nova fuente: linea 13, columna 8
    -                          | -          | -                      | -                  | -                ;  // 0x7910
    -                          | -          | -                      | -                  | -                ;  // 0x7920
    -                          | -          | -                      | -                  | jal.al m_estadistica_d879e4e7$total ;  // 0x7930
    -                          | -          | -                      | -                  | -                ;  // 0x7940
    -                          | -          | sw r6, #16(r14)        | -                  | -                ;  // 0x7950
    -                          | -          | lw r7, #0(r14)         | -                  | -                ;  // 0x7960
    -                          | -          | -                      | -                  | -                ;  // 0x7970
    -                          | -          | -                      | -                  | -                ;  // 0x7980
    -                          | -          | -                      | -                  | jal.al __nova_div32 ;  // 0x7990
    -                          | -          | -                      | -                  | -                ;  // 0x79A0
    -                          | -          | sw r6, #20(r14)        | -                  | -                ;  // 0x79B0
    // Nova fuente: linea 13, columna 2
    -                          | -          | lw r15, #28(r14)       | -                  | -                ;  // 0x79C0
    addi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x79D0
    -                          | -          | -                      | -                  | -                ;  // 0x79E0
    -                          | -          | -                      | -                  | -                ;  // 0x79F0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x7A00
    -                          | -          | -                      | -                  | -                ;  // 0x7A10
    // functio m_estadistica_d879e4e7$maximo
m_estadistica_d879e4e7$maximo:
    // marco de 40 bytes
    subi r14, r14, #40         | -          | -                      | -                  | -                ;  // 0x7A20
    -                          | -          | -                      | -                  | -                ;  // 0x7A30
    -                          | -          | -                      | -                  | -                ;  // 0x7A40
    -                          | -          | sw r6, #12(r14)        | -                  | -                ;  // 0x7A50
    -                          | -          | sw r7, #16(r14)        | -                  | -                ;  // 0x7A60
    -                          | -          | sw r8, #20(r14)        | -                  | -                ;  // 0x7A70
__m_estadistica_d879e4e7$maximo_cuerpo:
    // Nova fuente: linea 16, columna 28
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x7A80
    -                          | -          | -                      | -                  | -                ;  // 0x7A90
    -                          | -          | -                      | -                  | -                ;  // 0x7AA0
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7AB0
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x7AC0
    -                          | -          | -                      | -                  | -                ;  // 0x7AD0
    -                          | -          | -                      | -                  | -                ;  // 0x7AE0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x7AF0
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x7B00
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x7B10
    -                          | -          | -                      | -                  | -                ;  // 0x7B20
    -                          | -          | -                      | -                  | -                ;  // 0x7B30
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x7B40
    -                          | -          | -                      | -                  | -                ;  // 0x7B50
    -                          | -          | -                      | -                  | -                ;  // 0x7B60
    -                          | -          | -                      | -                  | br.ltu __rango26_ok ;  // 0x7B70
    -                          | -          | -                      | -                  | -                ;  // 0x7B80
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x7B90
    -                          | -          | -                      | -                  | -                ;  // 0x7BA0
    -                          | -          | -                      | -                  | -                ;  // 0x7BB0
    -                          | -          | -                      | -                  | halt             ;  // 0x7BC0
    -                          | -          | -                      | -                  | -                ;  // 0x7BD0
__rango26_ok:
    // Nova fuente: linea 16, columna 31
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x7BE0
    -                          | -          | -                      | -                  | -                ;  // 0x7BF0
    -                          | -          | -                      | -                  | -                ;  // 0x7C00
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x7C10
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x7C20
    -                          | -          | -                      | -                  | -                ;  // 0x7C30
    -                          | -          | -                      | -                  | -                ;  // 0x7C40
    -                          | -          | sw r10, #32(r14)       | -                  | -                ;  // 0x7C50
    -                          | -          | lw r10, #28(r14)       | -                  | -                ;  // 0x7C60
    -                          | -          | lw r11, #32(r14)       | -                  | -                ;  // 0x7C70
    -                          | -          | -                      | -                  | -                ;  // 0x7C80
    -                          | -          | -                      | -                  | -                ;  // 0x7C90
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x7CA0
    -                          | -          | -                      | -                  | -                ;  // 0x7CB0
    -                          | -          | -                      | -                  | -                ;  // 0x7CC0
    -                          | -          | -                      | -                  | br.ltu __rango27_ok ;  // 0x7CD0
    -                          | -          | -                      | -                  | -                ;  // 0x7CE0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x7CF0
    -                          | -          | -                      | -                  | -                ;  // 0x7D00
    -                          | -          | -                      | -                  | -                ;  // 0x7D10
    -                          | -          | -                      | -                  | halt             ;  // 0x7D20
    -                          | -          | -                      | -                  | -                ;  // 0x7D30
__rango27_ok:
    // Nova fuente: linea 16, columna 31
    -                          | -          | lw r10, #24(r14)       | -                  | -                ;  // 0x7D40
    -                          | -          | lw r11, #32(r14)       | -                  | -                ;  // 0x7D50
    -                          | -          | -                      | -                  | -                ;  // 0x7D60
    -                          | -          | -                      | -                  | -                ;  // 0x7D70
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x7D80
    -                          | -          | -                      | -                  | -                ;  // 0x7D90
    -                          | -          | -                      | -                  | -                ;  // 0x7DA0
    -                          | -          | sw r10, #36(r14)       | -                  | -                ;  // 0x7DB0
    -                          | -          | lw r11, #28(r14)       | -                  | -                ;  // 0x7DC0
    -                          | -          | -                      | -                  | -                ;  // 0x7DD0
    -                          | -          | -                      | -                  | -                ;  // 0x7DE0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x7DF0
    -                          | -          | -                      | -                  | -                ;  // 0x7E00
    -                          | -          | -                      | -                  | -                ;  // 0x7E10
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7E20
    // Nova fuente: linea 16, columna 26
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x7E30
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x7E40
    -                          | -          | -                      | -                  | -                ;  // 0x7E50
    -                          | -          | -                      | -                  | -                ;  // 0x7E60
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x7E70
    -                          | -          | -                      | -                  | -                ;  // 0x7E80
    -                          | -          | -                      | -                  | -                ;  // 0x7E90
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x7EA0
    -                          | -          | -                      | -                  | -                ;  // 0x7EB0
    -                          | -          | -                      | -                  | -                ;  // 0x7EC0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x7ED0
    // Nova fuente: linea 16, columna 8
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x7EE0
    // Nova fuente: linea 17, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x7EF0
    -                          | -          | -                      | -                  | -                ;  // 0x7F00
    -                          | -          | -                      | -                  | -                ;  // 0x7F10
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7F20
    // Nova fuente: linea 17, columna 13
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x7F30
L29:
    // Nova fuente: linea 17, columna 34
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x7F40
    -                          | -          | -                      | -                  | -                ;  // 0x7F50
    -                          | -          | -                      | -                  | -                ;  // 0x7F60
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x7F70
    // Nova fuente: linea 17, columna 30
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x7F80
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x7F90
    -                          | -          | -                      | -                  | -                ;  // 0x7FA0
    -                          | -          | -                      | -                  | -                ;  // 0x7FB0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x7FC0
    -                          | -          | -                      | -                  | -                ;  // 0x7FD0
    -                          | -          | -                      | -                  | -                ;  // 0x7FE0
    -                          | -          | -                      | -                  | br.lt __c25_si   ;  // 0x7FF0
    -                          | -          | -                      | -                  | -                ;  // 0x8000
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x8010
    -                          | -          | -                      | -                  | -                ;  // 0x8020
    -                          | -          | -                      | -                  | -                ;  // 0x8030
    -                          | -          | -                      | -                  | br.al __c25_fin  ;  // 0x8040
    -                          | -          | -                      | -                  | -                ;  // 0x8050
__c25_si:
    // Nova fuente: linea 17, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x8060
    -                          | -          | -                      | -                  | -                ;  // 0x8070
    -                          | -          | -                      | -                  | -                ;  // 0x8080
__c25_fin:
    // Nova fuente: linea 17, columna 30
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8090
    // Nova fuente: linea 17, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x80A0
    -                          | -          | -                      | -                  | -                ;  // 0x80B0
    -                          | -          | -                      | -                  | -                ;  // 0x80C0
    -                          | -          | -                      | -                  | br.eq L31        ;  // 0x80D0
    -                          | -          | -                      | -                  | -                ;  // 0x80E0
    // Nova fuente: linea 18, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x80F0
    -                          | -          | -                      | -                  | -                ;  // 0x8100
    -                          | -          | -                      | -                  | -                ;  // 0x8110
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8120
    // Nova fuente: linea 18, columna 13
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x8130
L32:
    // Nova fuente: linea 18, columna 34
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x8140
    -                          | -          | -                      | -                  | -                ;  // 0x8150
    -                          | -          | -                      | -                  | -                ;  // 0x8160
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8170
    // Nova fuente: linea 18, columna 30
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x8180
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8190
    -                          | -          | -                      | -                  | -                ;  // 0x81A0
    -                          | -          | -                      | -                  | -                ;  // 0x81B0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x81C0
    -                          | -          | -                      | -                  | -                ;  // 0x81D0
    -                          | -          | -                      | -                  | -                ;  // 0x81E0
    -                          | -          | -                      | -                  | br.lt __c26_si   ;  // 0x81F0
    -                          | -          | -                      | -                  | -                ;  // 0x8200
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x8210
    -                          | -          | -                      | -                  | -                ;  // 0x8220
    -                          | -          | -                      | -                  | -                ;  // 0x8230
    -                          | -          | -                      | -                  | br.al __c26_fin  ;  // 0x8240
    -                          | -          | -                      | -                  | -                ;  // 0x8250
__c26_si:
    // Nova fuente: linea 18, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x8260
    -                          | -          | -                      | -                  | -                ;  // 0x8270
    -                          | -          | -                      | -                  | -                ;  // 0x8280
__c26_fin:
    // Nova fuente: linea 18, columna 30
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8290
    // Nova fuente: linea 18, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x82A0
    -                          | -          | -                      | -                  | -                ;  // 0x82B0
    -                          | -          | -                      | -                  | -                ;  // 0x82C0
    -                          | -          | -                      | -                  | br.eq L34        ;  // 0x82D0
    -                          | -          | -                      | -                  | -                ;  // 0x82E0
    // Nova fuente: linea 19, columna 8
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x82F0
    -                          | -          | -                      | -                  | -                ;  // 0x8300
    -                          | -          | -                      | -                  | -                ;  // 0x8310
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8320
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x8330
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8340
    -                          | -          | -                      | -                  | -                ;  // 0x8350
    -                          | -          | -                      | -                  | -                ;  // 0x8360
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x8370
    -                          | -          | -                      | -                  | -                ;  // 0x8380
    -                          | -          | -                      | -                  | -                ;  // 0x8390
    -                          | -          | -                      | -                  | br.ltu __rango28_ok ;  // 0x83A0
    -                          | -          | -                      | -                  | -                ;  // 0x83B0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x83C0
    -                          | -          | -                      | -                  | -                ;  // 0x83D0
    -                          | -          | -                      | -                  | -                ;  // 0x83E0
    -                          | -          | -                      | -                  | halt             ;  // 0x83F0
    -                          | -          | -                      | -                  | -                ;  // 0x8400
__rango28_ok:
    // Nova fuente: linea 19, columna 11
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x8410
    -                          | -          | -                      | -                  | -                ;  // 0x8420
    -                          | -          | -                      | -                  | -                ;  // 0x8430
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8440
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x8450
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8460
    -                          | -          | -                      | -                  | -                ;  // 0x8470
    -                          | -          | -                      | -                  | -                ;  // 0x8480
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x8490
    -                          | -          | -                      | -                  | -                ;  // 0x84A0
    -                          | -          | -                      | -                  | -                ;  // 0x84B0
    -                          | -          | -                      | -                  | br.ltu __rango29_ok ;  // 0x84C0
    -                          | -          | -                      | -                  | -                ;  // 0x84D0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x84E0
    -                          | -          | -                      | -                  | -                ;  // 0x84F0
    -                          | -          | -                      | -                  | -                ;  // 0x8500
    -                          | -          | -                      | -                  | halt             ;  // 0x8510
    -                          | -          | -                      | -                  | -                ;  // 0x8520
__rango29_ok:
    // Nova fuente: linea 19, columna 11
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x8530
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8540
    -                          | -          | -                      | -                  | -                ;  // 0x8550
    -                          | -          | -                      | -                  | -                ;  // 0x8560
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x8570
    -                          | -          | -                      | -                  | -                ;  // 0x8580
    -                          | -          | -                      | -                  | -                ;  // 0x8590
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x85A0
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x85B0
    -                          | -          | -                      | -                  | -                ;  // 0x85C0
    -                          | -          | -                      | -                  | -                ;  // 0x85D0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x85E0
    -                          | -          | -                      | -                  | -                ;  // 0x85F0
    -                          | -          | -                      | -                  | -                ;  // 0x8600
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8610
    // Nova fuente: linea 19, columna 6
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x8620
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x8630
    -                          | -          | -                      | -                  | -                ;  // 0x8640
    -                          | -          | -                      | -                  | -                ;  // 0x8650
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x8660
    -                          | -          | -                      | -                  | -                ;  // 0x8670
    -                          | -          | -                      | -                  | -                ;  // 0x8680
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x8690
    -                          | -          | -                      | -                  | -                ;  // 0x86A0
    -                          | -          | -                      | -                  | -                ;  // 0x86B0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x86C0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x86D0
    -                          | -          | -                      | -                  | -                ;  // 0x86E0
    -                          | -          | -                      | -                  | -                ;  // 0x86F0
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x8700
    -                          | -          | -                      | -                  | -                ;  // 0x8710
    -                          | -          | -                      | -                  | -                ;  // 0x8720
    -                          | -          | -                      | -                  | br.lt __c27_si   ;  // 0x8730
    -                          | -          | -                      | -                  | -                ;  // 0x8740
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x8750
    -                          | -          | -                      | -                  | -                ;  // 0x8760
    -                          | -          | -                      | -                  | -                ;  // 0x8770
    -                          | -          | -                      | -                  | br.al __c27_fin  ;  // 0x8780
    -                          | -          | -                      | -                  | -                ;  // 0x8790
__c27_si:
    // Nova fuente: linea 19, columna 6
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x87A0
    -                          | -          | -                      | -                  | -                ;  // 0x87B0
    -                          | -          | -                      | -                  | -                ;  // 0x87C0
__c27_fin:
    // Nova fuente: linea 19, columna 6
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x87D0
    // Nova fuente: linea 19, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x87E0
    -                          | -          | -                      | -                  | -                ;  // 0x87F0
    -                          | -          | -                      | -                  | -                ;  // 0x8800
    -                          | -          | -                      | -                  | br.eq L35        ;  // 0x8810
    -                          | -          | -                      | -                  | -                ;  // 0x8820
    // Nova fuente: linea 20, columna 12
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x8830
    -                          | -          | -                      | -                  | -                ;  // 0x8840
    -                          | -          | -                      | -                  | -                ;  // 0x8850
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8860
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x8870
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8880
    -                          | -          | -                      | -                  | -                ;  // 0x8890
    -                          | -          | -                      | -                  | -                ;  // 0x88A0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x88B0
    -                          | -          | -                      | -                  | -                ;  // 0x88C0
    -                          | -          | -                      | -                  | -                ;  // 0x88D0
    -                          | -          | -                      | -                  | br.ltu __rango30_ok ;  // 0x88E0
    -                          | -          | -                      | -                  | -                ;  // 0x88F0
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x8900
    -                          | -          | -                      | -                  | -                ;  // 0x8910
    -                          | -          | -                      | -                  | -                ;  // 0x8920
    -                          | -          | -                      | -                  | halt             ;  // 0x8930
    -                          | -          | -                      | -                  | -                ;  // 0x8940
__rango30_ok:
    // Nova fuente: linea 20, columna 15
    -                          | -          | lw r10, #20(r14)       | -                  | -                ;  // 0x8950
    -                          | -          | -                      | -                  | -                ;  // 0x8960
    -                          | -          | -                      | -                  | -                ;  // 0x8970
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8980
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x8990
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x89A0
    -                          | -          | -                      | -                  | -                ;  // 0x89B0
    -                          | -          | -                      | -                  | -                ;  // 0x89C0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x89D0
    -                          | -          | -                      | -                  | -                ;  // 0x89E0
    -                          | -          | -                      | -                  | -                ;  // 0x89F0
    -                          | -          | -                      | -                  | br.ltu __rango31_ok ;  // 0x8A00
    -                          | -          | -                      | -                  | -                ;  // 0x8A10
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x8A20
    -                          | -          | -                      | -                  | -                ;  // 0x8A30
    -                          | -          | -                      | -                  | -                ;  // 0x8A40
    -                          | -          | -                      | -                  | halt             ;  // 0x8A50
    -                          | -          | -                      | -                  | -                ;  // 0x8A60
__rango31_ok:
    // Nova fuente: linea 20, columna 15
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x8A70
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8A80
    -                          | -          | -                      | -                  | -                ;  // 0x8A90
    -                          | -          | -                      | -                  | -                ;  // 0x8AA0
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x8AB0
    -                          | -          | -                      | -                  | -                ;  // 0x8AC0
    -                          | -          | -                      | -                  | -                ;  // 0x8AD0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8AE0
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x8AF0
    -                          | -          | -                      | -                  | -                ;  // 0x8B00
    -                          | -          | -                      | -                  | -                ;  // 0x8B10
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x8B20
    -                          | -          | -                      | -                  | -                ;  // 0x8B30
    -                          | -          | -                      | -                  | -                ;  // 0x8B40
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8B50
    // Nova fuente: linea 20, columna 10
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x8B60
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x8B70
    -                          | -          | -                      | -                  | -                ;  // 0x8B80
    -                          | -          | -                      | -                  | -                ;  // 0x8B90
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x8BA0
    -                          | -          | -                      | -                  | -                ;  // 0x8BB0
    -                          | -          | -                      | -                  | -                ;  // 0x8BC0
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x8BD0
    -                          | -          | -                      | -                  | -                ;  // 0x8BE0
    -                          | -          | -                      | -                  | -                ;  // 0x8BF0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8C00
    // Nova fuente: linea 20, columna 2
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x8C10
L35:
L33:
    // Nova fuente: linea 18, columna 56
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x8C20
    -                          | -          | -                      | -                  | -                ;  // 0x8C30
    -                          | -          | -                      | -                  | -                ;  // 0x8C40
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8C50
    // Nova fuente: linea 18, columna 51
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x8C60
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8C70
    -                          | -          | -                      | -                  | -                ;  // 0x8C80
    -                          | -          | -                      | -                  | -                ;  // 0x8C90
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x8CA0
    -                          | -          | -                      | -                  | -                ;  // 0x8CB0
    -                          | -          | -                      | -                  | -                ;  // 0x8CC0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8CD0
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x8CE0
    -                          | -          | -                      | -                  | br.al L32        ;  // 0x8CF0
    -                          | -          | -                      | -                  | -                ;  // 0x8D00
L34:
L30:
    // Nova fuente: linea 17, columna 53
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x8D10
    -                          | -          | -                      | -                  | -                ;  // 0x8D20
    -                          | -          | -                      | -                  | -                ;  // 0x8D30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x8D40
    // Nova fuente: linea 17, columna 48
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x8D50
    -                          | -          | lw r11, #24(r14)       | -                  | -                ;  // 0x8D60
    -                          | -          | -                      | -                  | -                ;  // 0x8D70
    -                          | -          | -                      | -                  | -                ;  // 0x8D80
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x8D90
    -                          | -          | -                      | -                  | -                ;  // 0x8DA0
    -                          | -          | -                      | -                  | -                ;  // 0x8DB0
    -                          | -          | sw r10, #28(r14)       | -                  | -                ;  // 0x8DC0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x8DD0
    -                          | -          | -                      | -                  | br.al L29        ;  // 0x8DE0
    -                          | -          | -                      | -                  | -                ;  // 0x8DF0
L31:
    // Nova fuente: linea 24, columna 2
    -                          | -          | lw r6, #8(r14)         | -                  | -                ;  // 0x8E00
    addi r14, r14, #40         | -          | -                      | -                  | -                ;  // 0x8E10
    -                          | -          | -                      | -                  | -                ;  // 0x8E20
    -                          | -          | -                      | -                  | -                ;  // 0x8E30
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x8E40
    -                          | -          | -                      | -                  | -                ;  // 0x8E50
    // __nova_div32(R6 = a, R7 = b) -> R6 = a/b, R7 = a%b, con signo
__nova_div32:
    cmpi r7, #0                | -          | -                      | -                  | -                ;  // 0x8E60
    -                          | -          | -                      | -                  | -                ;  // 0x8E70
    -                          | -          | -                      | -                  | -                ;  // 0x8E80
    -                          | -          | -                      | -                  | br.ne __dv_ok    ;  // 0x8E90
    -                          | -          | -                      | -                  | -                ;  // 0x8EA0
    movi r6, #136              | -          | -                      | -                  | -                ;  // 0x8EB0
    -                          | -          | -                      | -                  | -                ;  // 0x8EC0
    -                          | -          | -                      | -                  | -                ;  // 0x8ED0
    -                          | -          | -                      | -                  | halt             ;  // 0x8EE0
    -                          | -          | -                      | -                  | -                ;  // 0x8EF0
__dv_ok:
    subi r14, r14, #8          | -          | -                      | -                  | -                ;  // 0x8F00
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x8F10
    -                          | -          | -                      | -                  | -                ;  // 0x8F20
    -                          | -          | -                      | -                  | -                ;  // 0x8F30
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x8F40
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x8F50
    cmpi r6, #0                | -          | -                      | -                  | -                ;  // 0x8F60
    -                          | -          | -                      | -                  | -                ;  // 0x8F70
    -                          | -          | -                      | -                  | -                ;  // 0x8F80
    -                          | -          | -                      | -                  | br.ge __dv_a_pos ;  // 0x8F90
    -                          | -          | -                      | -                  | -                ;  // 0x8FA0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x8FB0
    -                          | -          | -                      | -                  | -                ;  // 0x8FC0
    -                          | -          | -                      | -                  | -                ;  // 0x8FD0
    sub r6, r10, r6            | -          | -                      | -                  | -                ;  // 0x8FE0
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x8FF0
    -                          | -          | -                      | -                  | -                ;  // 0x9000
    -                          | -          | -                      | -                  | -                ;  // 0x9010
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x9020
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x9030
__dv_a_pos:
    cmpi r7, #0                | -          | -                      | -                  | -                ;  // 0x9040
    -                          | -          | -                      | -                  | -                ;  // 0x9050
    -                          | -          | -                      | -                  | -                ;  // 0x9060
    -                          | -          | -                      | -                  | br.ge __dv_b_pos ;  // 0x9070
    -                          | -          | -                      | -                  | -                ;  // 0x9080
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x9090
    -                          | -          | -                      | -                  | -                ;  // 0x90A0
    -                          | -          | -                      | -                  | -                ;  // 0x90B0
    sub r7, r10, r7            | -          | -                      | -                  | -                ;  // 0x90C0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x90D0
    -                          | -          | -                      | -                  | -                ;  // 0x90E0
    -                          | -          | -                      | -                  | -                ;  // 0x90F0
    xori r10, r10, #1          | -          | -                      | -                  | -                ;  // 0x9100
    -                          | -          | -                      | -                  | -                ;  // 0x9110
    -                          | -          | -                      | -                  | -                ;  // 0x9120
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x9130
__dv_b_pos:
    movi r8, #0                | -          | -                      | -                  | -                ;  // 0x9140
    movi r9, #0                | -          | -                      | -                  | -                ;  // 0x9150
    movi r10, #31              | -          | -                      | -                  | -                ;  // 0x9160
    -                          | -          | -                      | -                  | -                ;  // 0x9170
    -                          | -          | -                      | -                  | -                ;  // 0x9180
__dv_bucle:
    srl r11, r6, r10           | -          | -                      | -                  | -                ;  // 0x9190
    -                          | -          | -                      | -                  | -                ;  // 0x91A0
    -                          | -          | -                      | -                  | -                ;  // 0x91B0
    andi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x91C0
    slli r9, r9, #1            | -          | -                      | -                  | -                ;  // 0x91D0
    -                          | -          | -                      | -                  | -                ;  // 0x91E0
    -                          | -          | -                      | -                  | -                ;  // 0x91F0
    or r9, r9, r11             | -          | -                      | -                  | -                ;  // 0x9200
    -                          | -          | -                      | -                  | -                ;  // 0x9210
    -                          | -          | -                      | -                  | -                ;  // 0x9220
    cmp r9, r7                 | -          | -                      | -                  | -                ;  // 0x9230
    -                          | -          | -                      | -                  | -                ;  // 0x9240
    -                          | -          | -                      | -                  | -                ;  // 0x9250
    -                          | -          | -                      | -                  | br.ltu __dv_sigue ;  // 0x9260
    -                          | -          | -                      | -                  | -                ;  // 0x9270
    sub r9, r9, r7             | -          | -                      | -                  | -                ;  // 0x9280
    movi r11, #1               | -          | -                      | -                  | -                ;  // 0x9290
    -                          | -          | -                      | -                  | -                ;  // 0x92A0
    -                          | -          | -                      | -                  | -                ;  // 0x92B0
    sll r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x92C0
    -                          | -          | -                      | -                  | -                ;  // 0x92D0
    -                          | -          | -                      | -                  | -                ;  // 0x92E0
    or r8, r8, r11             | -          | -                      | -                  | -                ;  // 0x92F0
    -                          | -          | -                      | -                  | -                ;  // 0x9300
    -                          | -          | -                      | -                  | -                ;  // 0x9310
__dv_sigue:
    subi r10, r10, #1          | -          | -                      | -                  | -                ;  // 0x9320
    -                          | -          | -                      | -                  | -                ;  // 0x9330
    -                          | -          | -                      | -                  | -                ;  // 0x9340
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x9350
    -                          | -          | -                      | -                  | -                ;  // 0x9360
    -                          | -          | -                      | -                  | -                ;  // 0x9370
    -                          | -          | -                      | -                  | br.ge __dv_bucle ;  // 0x9380
    -                          | -          | -                      | -                  | -                ;  // 0x9390
    mov r6, r8                 | -          | -                      | -                  | -                ;  // 0x93A0
    mov r7, r9                 | -          | -                      | -                  | -                ;  // 0x93B0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x93C0
    -                          | -          | -                      | -                  | -                ;  // 0x93D0
    -                          | -          | -                      | -                  | -                ;  // 0x93E0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x93F0
    -                          | -          | -                      | -                  | -                ;  // 0x9400
    -                          | -          | -                      | -                  | -                ;  // 0x9410
    -                          | -          | -                      | -                  | br.eq __dv_c_pos ;  // 0x9420
    -                          | -          | -                      | -                  | -                ;  // 0x9430
    movi r11, #0               | -          | -                      | -                  | -                ;  // 0x9440
    -                          | -          | -                      | -                  | -                ;  // 0x9450
    -                          | -          | -                      | -                  | -                ;  // 0x9460
    sub r6, r11, r6            | -          | -                      | -                  | -                ;  // 0x9470
    -                          | -          | -                      | -                  | -                ;  // 0x9480
    -                          | -          | -                      | -                  | -                ;  // 0x9490
__dv_c_pos:
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x94A0
    -                          | -          | -                      | -                  | -                ;  // 0x94B0
    -                          | -          | -                      | -                  | -                ;  // 0x94C0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x94D0
    -                          | -          | -                      | -                  | -                ;  // 0x94E0
    -                          | -          | -                      | -                  | -                ;  // 0x94F0
    -                          | -          | -                      | -                  | br.eq __dv_r_pos ;  // 0x9500
    -                          | -          | -                      | -                  | -                ;  // 0x9510
    movi r11, #0               | -          | -                      | -                  | -                ;  // 0x9520
    -                          | -          | -                      | -                  | -                ;  // 0x9530
    -                          | -          | -                      | -                  | -                ;  // 0x9540
    sub r7, r11, r7            | -          | -                      | -                  | -                ;  // 0x9550
    -                          | -          | -                      | -                  | -                ;  // 0x9560
    -                          | -          | -                      | -                  | -                ;  // 0x9570
__dv_r_pos:
    addi r14, r14, #8          | -          | -                      | -                  | -                ;  // 0x9580
    -                          | -          | -                      | -                  | -                ;  // 0x9590
    -                          | -          | -                      | -                  | -                ;  // 0x95A0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x95B0
    -                          | -          | -                      | -                  | -                ;  // 0x95C0
    // __scribe_int(R6 = valor): el ISA no define puertos de E/S, los resultados se dejan en memoria para las herramientas de CE 4301
__scribe_int:
    movi r10, #12288           | -          | -                      | -                  | -                ;  // 0x95D0
    -                          | -          | -                      | -                  | -                ;  // 0x95E0
    -                          | -          | -                      | -                  | -                ;  // 0x95F0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x9600
    -                          | -          | -                      | -                  | -                ;  // 0x9610
    -                          | -          | -                      | -                  | -                ;  // 0x9620
    slli r11, r11, #2          | -          | -                      | -                  | -                ;  // 0x9630
    -                          | -          | -                      | -                  | -                ;  // 0x9640
    -                          | -          | -                      | -                  | -                ;  // 0x9650
    addi r11, r11, #4          | -          | -                      | -                  | -                ;  // 0x9660
    -                          | -          | -                      | -                  | -                ;  // 0x9670
    -                          | -          | -                      | -                  | -                ;  // 0x9680
    add r11, r10, r11          | -          | -                      | -                  | -                ;  // 0x9690
    -                          | -          | -                      | -                  | -                ;  // 0x96A0
    -                          | -          | -                      | -                  | -                ;  // 0x96B0
    -                          | -          | sw r6, #0(r11)         | -                  | -                ;  // 0x96C0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x96D0
    -                          | -          | -                      | -                  | -                ;  // 0x96E0
    -                          | -          | -                      | -                  | -                ;  // 0x96F0
    addi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x9700
    -                          | -          | -                      | -                  | -                ;  // 0x9710
    -                          | -          | -                      | -                  | -                ;  // 0x9720
    -                          | -          | sw r11, #0(r10)        | -                  | -                ;  // 0x9730
    -                          | -          | -                      | -                  | -                ;  // 0x9740
    -                          | -          | -                      | -                  | -                ;  // 0x9750
    -                          | -          | -                      | -                  | -                ;  // 0x9760
    -                          | -          | -                      | -                  | -                ;  // 0x9770
    -                          | -          | -                      | -                  | -                ;  // 0x9780
    -                          | -          | -                      | -                  | -                ;  // 0x9790
    -                          | -          | -                      | -                  | -                ;  // 0x97A0
    -                          | -          | -                      | -                  | -                ;  // 0x97B0
    -                          | -          | -                      | -                  | -                ;  // 0x97C0
    -                          | -          | -                      | -                  | -                ;  // 0x97D0
    -                          | -          | -                      | -                  | -                ;  // 0x97E0
    -                          | -          | -                      | -                  | -                ;  // 0x97F0
    -                          | -          | -                      | -                  | -                ;  // 0x9800
    -                          | -          | -                      | -                  | -                ;  // 0x9810
    -                          | -          | -                      | -                  | -                ;  // 0x9820
    -                          | -          | -                      | -                  | -                ;  // 0x9830
    -                          | -          | -                      | -                  | -                ;  // 0x9840
    -                          | -          | -                      | -                  | -                ;  // 0x9850
    -                          | -          | -                      | -                  | -                ;  // 0x9860
    -                          | -          | -                      | -                  | -                ;  // 0x9870
    -                          | -          | -                      | -                  | -                ;  // 0x9880
    -                          | -          | -                      | -                  | -                ;  // 0x9890
    -                          | -          | -                      | -                  | -                ;  // 0x98A0
    -                          | -          | -                      | -                  | -                ;  // 0x98B0
    -                          | -          | -                      | -                  | -                ;  // 0x98C0
    -                          | -          | -                      | -                  | -                ;  // 0x98D0
    -                          | -          | -                      | -                  | -                ;  // 0x98E0
    -                          | -          | -                      | -                  | -                ;  // 0x98F0
    -                          | -          | -                      | -                  | -                ;  // 0x9900
    -                          | -          | -                      | -                  | -                ;  // 0x9910
    -                          | -          | -                      | -                  | -                ;  // 0x9920
    -                          | -          | -                      | -                  | -                ;  // 0x9930
    -                          | -          | -                      | -                  | -                ;  // 0x9940
    -                          | -          | -                      | -                  | -                ;  // 0x9950
    -                          | -          | -                      | -                  | -                ;  // 0x9960
    -                          | -          | -                      | -                  | -                ;  // 0x9970
    -                          | -          | -                      | -                  | -                ;  // 0x9980
    -                          | -          | -                      | -                  | -                ;  // 0x9990
    -                          | -          | -                      | -                  | -                ;  // 0x99A0
    -                          | -          | -                      | -                  | -                ;  // 0x99B0
    -                          | -          | -                      | -                  | -                ;  // 0x99C0
    -                          | -          | -                      | -                  | -                ;  // 0x99D0
    -                          | -          | -                      | -                  | -                ;  // 0x99E0
    -                          | -          | -                      | -                  | -                ;  // 0x99F0
    -                          | -          | -                      | -                  | -                ;  // 0x9A00
    -                          | -          | -                      | -                  | -                ;  // 0x9A10
    -                          | -          | -                      | -                  | -                ;  // 0x9A20
    -                          | -          | -                      | -                  | -                ;  // 0x9A30
    -                          | -          | -                      | -                  | -                ;  // 0x9A40
    -                          | -          | -                      | -                  | -                ;  // 0x9A50
    -                          | -          | -                      | -                  | -                ;  // 0x9A60
    -                          | -          | -                      | -                  | -                ;  // 0x9A70
    -                          | -          | -                      | -                  | -                ;  // 0x9A80
    -                          | -          | -                      | -                  | -                ;  // 0x9A90
    -                          | -          | -                      | -                  | -                ;  // 0x9AA0
    -                          | -          | -                      | -                  | -                ;  // 0x9AB0
    -                          | -          | -                      | -                  | -                ;  // 0x9AC0
    -                          | -          | -                      | -                  | -                ;  // 0x9AD0
    -                          | -          | -                      | -                  | -                ;  // 0x9AE0
    -                          | -          | -                      | -                  | -                ;  // 0x9AF0
    -                          | -          | -                      | -                  | -                ;  // 0x9B00
    -                          | -          | -                      | -                  | -                ;  // 0x9B10
    -                          | -          | -                      | -                  | -                ;  // 0x9B20
    -                          | -          | -                      | -                  | -                ;  // 0x9B30
    -                          | -          | -                      | -                  | -                ;  // 0x9B40
    -                          | -          | -                      | -                  | -                ;  // 0x9B50
    -                          | -          | -                      | -                  | -                ;  // 0x9B60
    -                          | -          | -                      | -                  | -                ;  // 0x9B70
    -                          | -          | -                      | -                  | -                ;  // 0x9B80
    -                          | -          | -                      | -                  | -                ;  // 0x9B90
    -                          | -          | -                      | -                  | -                ;  // 0x9BA0
    -                          | -          | -                      | -                  | -                ;  // 0x9BB0
    -                          | -          | -                      | -                  | -                ;  // 0x9BC0
    -                          | -          | -                      | -                  | -                ;  // 0x9BD0
    -                          | -          | -                      | -                  | -                ;  // 0x9BE0
    -                          | -          | -                      | -                  | -                ;  // 0x9BF0
    -                          | -          | -                      | -                  | -                ;  // 0x9C00
    -                          | -          | -                      | -                  | -                ;  // 0x9C10
    -                          | -          | -                      | -                  | -                ;  // 0x9C20
    -                          | -          | -                      | -                  | -                ;  // 0x9C30
    -                          | -          | -                      | -                  | -                ;  // 0x9C40
    -                          | -          | -                      | -                  | -                ;  // 0x9C50
    -                          | -          | -                      | -                  | -                ;  // 0x9C60
    -                          | -          | -                      | -                  | -                ;  // 0x9C70
    -                          | -          | -                      | -                  | -                ;  // 0x9C80
    -                          | -          | -                      | -                  | -                ;  // 0x9C90
    -                          | -          | -                      | -                  | -                ;  // 0x9CA0
    -                          | -          | -                      | -                  | -                ;  // 0x9CB0
    -                          | -          | -                      | -                  | -                ;  // 0x9CC0
    -                          | -          | -                      | -                  | -                ;  // 0x9CD0
    -                          | -          | -                      | -                  | -                ;  // 0x9CE0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x9CF0
    -                          | -          | -                      | -                  | -                ;  // 0x9D00
    // __scribe_txt(R6 = direccion): escribe la longitud y las palabras
__scribe_txt:
    subi r14, r14, #4          | -          | -                      | -                  | -                ;  // 0x9D10
    -                          | -          | -                      | -                  | -                ;  // 0x9D20
    -                          | -          | -                      | -                  | -                ;  // 0x9D30
    -                          | -          | sw r15, #0(r14)        | -                  | -                ;  // 0x9D40
    -                          | -          | lw r7, #0(r6)          | -                  | -                ;  // 0x9D50
    mov r9, r6                 | -          | -                      | -                  | -                ;  // 0x9D60
    -                          | -          | -                      | -                  | -                ;  // 0x9D70
    mov r6, r7                 | -          | -                      | -                  | -                ;  // 0x9D80
    -                          | -          | -                      | -                  | -                ;  // 0x9D90
    -                          | -          | -                      | -                  | -                ;  // 0x9DA0
    -                          | -          | -                      | -                  | -                ;  // 0x9DB0
    -                          | -          | -                      | -                  | -                ;  // 0x9DC0
    -                          | -          | -                      | -                  | -                ;  // 0x9DD0
    -                          | -          | -                      | -                  | -                ;  // 0x9DE0
    -                          | -          | -                      | -                  | -                ;  // 0x9DF0
    -                          | -          | -                      | -                  | -                ;  // 0x9E00
    -                          | -          | -                      | -                  | -                ;  // 0x9E10
    -                          | -          | -                      | -                  | -                ;  // 0x9E20
    -                          | -          | -                      | -                  | -                ;  // 0x9E30
    -                          | -          | -                      | -                  | -                ;  // 0x9E40
    -                          | -          | -                      | -                  | -                ;  // 0x9E50
    -                          | -          | -                      | -                  | -                ;  // 0x9E60
    -                          | -          | -                      | -                  | -                ;  // 0x9E70
    -                          | -          | -                      | -                  | -                ;  // 0x9E80
    -                          | -          | -                      | -                  | -                ;  // 0x9E90
    -                          | -          | -                      | -                  | -                ;  // 0x9EA0
    -                          | -          | -                      | -                  | -                ;  // 0x9EB0
    -                          | -          | -                      | -                  | -                ;  // 0x9EC0
    -                          | -          | -                      | -                  | -                ;  // 0x9ED0
    -                          | -          | -                      | -                  | -                ;  // 0x9EE0
    -                          | -          | -                      | -                  | -                ;  // 0x9EF0
    -                          | -          | -                      | -                  | -                ;  // 0x9F00
    -                          | -          | -                      | -                  | -                ;  // 0x9F10
    -                          | -          | -                      | -                  | -                ;  // 0x9F20
    -                          | -          | -                      | -                  | -                ;  // 0x9F30
    -                          | -          | -                      | -                  | -                ;  // 0x9F40
    -                          | -          | -                      | -                  | -                ;  // 0x9F50
    -                          | -          | -                      | -                  | -                ;  // 0x9F60
    -                          | -          | -                      | -                  | -                ;  // 0x9F70
    -                          | -          | -                      | -                  | -                ;  // 0x9F80
    -                          | -          | -                      | -                  | -                ;  // 0x9F90
    -                          | -          | -                      | -                  | -                ;  // 0x9FA0
    -                          | -          | -                      | -                  | -                ;  // 0x9FB0
    -                          | -          | -                      | -                  | -                ;  // 0x9FC0
    -                          | -          | -                      | -                  | -                ;  // 0x9FD0
    -                          | -          | -                      | -                  | -                ;  // 0x9FE0
    -                          | -          | -                      | -                  | -                ;  // 0x9FF0
    -                          | -          | -                      | -                  | -                ;  // 0xA000
    -                          | -          | -                      | -                  | -                ;  // 0xA010
    -                          | -          | -                      | -                  | -                ;  // 0xA020
    -                          | -          | -                      | -                  | -                ;  // 0xA030
    -                          | -          | -                      | -                  | -                ;  // 0xA040
    -                          | -          | -                      | -                  | -                ;  // 0xA050
    -                          | -          | -                      | -                  | -                ;  // 0xA060
    -                          | -          | -                      | -                  | -                ;  // 0xA070
    -                          | -          | -                      | -                  | -                ;  // 0xA080
    -                          | -          | -                      | -                  | -                ;  // 0xA090
    -                          | -          | -                      | -                  | -                ;  // 0xA0A0
    -                          | -          | -                      | -                  | -                ;  // 0xA0B0
    -                          | -          | -                      | -                  | -                ;  // 0xA0C0
    -                          | -          | -                      | -                  | -                ;  // 0xA0D0
    -                          | -          | -                      | -                  | -                ;  // 0xA0E0
    -                          | -          | -                      | -                  | -                ;  // 0xA0F0
    -                          | -          | -                      | -                  | -                ;  // 0xA100
    -                          | -          | -                      | -                  | -                ;  // 0xA110
    -                          | -          | -                      | -                  | -                ;  // 0xA120
    -                          | -          | -                      | -                  | -                ;  // 0xA130
    -                          | -          | -                      | -                  | -                ;  // 0xA140
    -                          | -          | -                      | -                  | -                ;  // 0xA150
    -                          | -          | -                      | -                  | -                ;  // 0xA160
    -                          | -          | -                      | -                  | -                ;  // 0xA170
    -                          | -          | -                      | -                  | -                ;  // 0xA180
    -                          | -          | -                      | -                  | -                ;  // 0xA190
    -                          | -          | -                      | -                  | -                ;  // 0xA1A0
    -                          | -          | -                      | -                  | -                ;  // 0xA1B0
    -                          | -          | -                      | -                  | -                ;  // 0xA1C0
    -                          | -          | -                      | -                  | -                ;  // 0xA1D0
    -                          | -          | -                      | -                  | -                ;  // 0xA1E0
    -                          | -          | -                      | -                  | -                ;  // 0xA1F0
    -                          | -          | -                      | -                  | -                ;  // 0xA200
    -                          | -          | -                      | -                  | -                ;  // 0xA210
    -                          | -          | -                      | -                  | -                ;  // 0xA220
    -                          | -          | -                      | -                  | -                ;  // 0xA230
    -                          | -          | -                      | -                  | -                ;  // 0xA240
    -                          | -          | -                      | -                  | -                ;  // 0xA250
    -                          | -          | -                      | -                  | -                ;  // 0xA260
    -                          | -          | -                      | -                  | -                ;  // 0xA270
    -                          | -          | -                      | -                  | -                ;  // 0xA280
    -                          | -          | -                      | -                  | -                ;  // 0xA290
    -                          | -          | -                      | -                  | -                ;  // 0xA2A0
    -                          | -          | -                      | -                  | -                ;  // 0xA2B0
    -                          | -          | -                      | -                  | -                ;  // 0xA2C0
    -                          | -          | -                      | -                  | -                ;  // 0xA2D0
    -                          | -          | -                      | -                  | -                ;  // 0xA2E0
    -                          | -          | -                      | -                  | -                ;  // 0xA2F0
    -                          | -          | -                      | -                  | -                ;  // 0xA300
    -                          | -          | -                      | -                  | -                ;  // 0xA310
    -                          | -          | -                      | -                  | -                ;  // 0xA320
    -                          | -          | -                      | -                  | -                ;  // 0xA330
    -                          | -          | -                      | -                  | -                ;  // 0xA340
    -                          | -          | -                      | -                  | -                ;  // 0xA350
    -                          | -          | -                      | -                  | -                ;  // 0xA360
    -                          | -          | -                      | -                  | -                ;  // 0xA370
    -                          | -          | -                      | -                  | -                ;  // 0xA380
    -                          | -          | -                      | -                  | -                ;  // 0xA390
    -                          | -          | -                      | -                  | -                ;  // 0xA3A0
    -                          | -          | -                      | -                  | -                ;  // 0xA3B0
    -                          | -          | -                      | -                  | -                ;  // 0xA3C0
    -                          | -          | -                      | -                  | -                ;  // 0xA3D0
    -                          | -          | -                      | -                  | -                ;  // 0xA3E0
    -                          | -          | -                      | -                  | -                ;  // 0xA3F0
    -                          | -          | -                      | -                  | -                ;  // 0xA400
    -                          | -          | -                      | -                  | -                ;  // 0xA410
    -                          | -          | -                      | -                  | -                ;  // 0xA420
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0xA430
    -                          | -          | -                      | -                  | -                ;  // 0xA440
    addi r9, r9, #4            | -          | -                      | -                  | -                ;  // 0xA450
    addi r8, r7, #3            | -          | -                      | -                  | -                ;  // 0xA460
    -                          | -          | -                      | -                  | -                ;  // 0xA470
    -                          | -          | -                      | -                  | -                ;  // 0xA480
    srli r8, r8, #2            | -          | -                      | -                  | -                ;  // 0xA490
    -                          | -          | -                      | -                  | -                ;  // 0xA4A0
    -                          | -          | -                      | -                  | -                ;  // 0xA4B0
__txt_bucle:
    cmpi r8, #0                | -          | -                      | -                  | -                ;  // 0xA4C0
    -                          | -          | -                      | -                  | -                ;  // 0xA4D0
    -                          | -          | -                      | -                  | -                ;  // 0xA4E0
    -                          | -          | -                      | -                  | br.eq __txt_fin  ;  // 0xA4F0
    -                          | -          | -                      | -                  | -                ;  // 0xA500
    -                          | -          | lw r6, #0(r9)          | -                  | -                ;  // 0xA510
    -                          | -          | -                      | -                  | -                ;  // 0xA520
    -                          | -          | -                      | -                  | -                ;  // 0xA530
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0xA540
    -                          | -          | -                      | -                  | -                ;  // 0xA550
    addi r9, r9, #4            | -          | -                      | -                  | -                ;  // 0xA560
    subi r8, r8, #1            | -          | -                      | -                  | -                ;  // 0xA570
    -                          | -          | -                      | -                  | -                ;  // 0xA580
    -                          | -          | -                      | -                  | -                ;  // 0xA590
    -                          | -          | -                      | -                  | br.al __txt_bucle ;  // 0xA5A0
    -                          | -          | -                      | -                  | -                ;  // 0xA5B0
__txt_fin:
    -                          | -          | lw r15, #0(r14)        | -                  | -                ;  // 0xA5C0
    addi r14, r14, #4          | -          | -                      | -                  | -                ;  // 0xA5D0
    -                          | -          | -                      | -                  | -                ;  // 0xA5E0
    -                          | -          | -                      | -                  | -                ;  // 0xA5F0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0xA600
    -                          | -          | -                      | -                  | -                ;  // 0xA610
    // __dic_fin(): marca el fin de linea de 'dic' con 0x0A
__dic_fin:
    movi r6, #10               | -          | -                      | -                  | -                ;  // 0xA620
    -                          | -          | -                      | -                  | -                ;  // 0xA630
    -                          | -          | -                      | -                  | -                ;  // 0xA640
    -                          | -          | -                      | -                  | -                ;  // 0xA650
    -                          | -          | -                      | -                  | -                ;  // 0xA660
    -                          | -          | -                      | -                  | -                ;  // 0xA670
    -                          | -          | -                      | -                  | -                ;  // 0xA680
    -                          | -          | -                      | -                  | -                ;  // 0xA690
    -                          | -          | -                      | -                  | -                ;  // 0xA6A0
    -                          | -          | -                      | -                  | -                ;  // 0xA6B0
    -                          | -          | -                      | -                  | -                ;  // 0xA6C0
    -                          | -          | -                      | -                  | -                ;  // 0xA6D0
    -                          | -          | -                      | -                  | -                ;  // 0xA6E0
    -                          | -          | -                      | -                  | -                ;  // 0xA6F0
    -                          | -          | -                      | -                  | -                ;  // 0xA700
    -                          | -          | -                      | -                  | -                ;  // 0xA710
    -                          | -          | -                      | -                  | -                ;  // 0xA720
    -                          | -          | -                      | -                  | -                ;  // 0xA730
    -                          | -          | -                      | -                  | -                ;  // 0xA740
    -                          | -          | -                      | -                  | -                ;  // 0xA750
    -                          | -          | -                      | -                  | -                ;  // 0xA760
    -                          | -          | -                      | -                  | -                ;  // 0xA770
    -                          | -          | -                      | -                  | -                ;  // 0xA780
    -                          | -          | -                      | -                  | -                ;  // 0xA790
    -                          | -          | -                      | -                  | -                ;  // 0xA7A0
    -                          | -          | -                      | -                  | -                ;  // 0xA7B0
    -                          | -          | -                      | -                  | -                ;  // 0xA7C0
    -                          | -          | -                      | -                  | -                ;  // 0xA7D0
    -                          | -          | -                      | -                  | -                ;  // 0xA7E0
    -                          | -          | -                      | -                  | -                ;  // 0xA7F0
    -                          | -          | -                      | -                  | -                ;  // 0xA800
    -                          | -          | -                      | -                  | -                ;  // 0xA810
    -                          | -          | -                      | -                  | -                ;  // 0xA820
    -                          | -          | -                      | -                  | -                ;  // 0xA830
    -                          | -          | -                      | -                  | -                ;  // 0xA840
    -                          | -          | -                      | -                  | -                ;  // 0xA850
    -                          | -          | -                      | -                  | -                ;  // 0xA860
    -                          | -          | -                      | -                  | -                ;  // 0xA870
    -                          | -          | -                      | -                  | -                ;  // 0xA880
    -                          | -          | -                      | -                  | -                ;  // 0xA890
    -                          | -          | -                      | -                  | -                ;  // 0xA8A0
    -                          | -          | -                      | -                  | -                ;  // 0xA8B0
    -                          | -          | -                      | -                  | -                ;  // 0xA8C0
    -                          | -          | -                      | -                  | -                ;  // 0xA8D0
    -                          | -          | -                      | -                  | -                ;  // 0xA8E0
    -                          | -          | -                      | -                  | -                ;  // 0xA8F0
    -                          | -          | -                      | -                  | -                ;  // 0xA900
    -                          | -          | -                      | -                  | -                ;  // 0xA910
    -                          | -          | -                      | -                  | -                ;  // 0xA920
    -                          | -          | -                      | -                  | -                ;  // 0xA930
    -                          | -          | -                      | -                  | -                ;  // 0xA940
    -                          | -          | -                      | -                  | -                ;  // 0xA950
    -                          | -          | -                      | -                  | -                ;  // 0xA960
    -                          | -          | -                      | -                  | -                ;  // 0xA970
    -                          | -          | -                      | -                  | -                ;  // 0xA980
    -                          | -          | -                      | -                  | -                ;  // 0xA990
    -                          | -          | -                      | -                  | -                ;  // 0xA9A0
    -                          | -          | -                      | -                  | -                ;  // 0xA9B0
    -                          | -          | -                      | -                  | -                ;  // 0xA9C0
    -                          | -          | -                      | -                  | -                ;  // 0xA9D0
    -                          | -          | -                      | -                  | -                ;  // 0xA9E0
    -                          | -          | -                      | -                  | -                ;  // 0xA9F0
    -                          | -          | -                      | -                  | -                ;  // 0xAA00
    -                          | -          | -                      | -                  | -                ;  // 0xAA10
    -                          | -          | -                      | -                  | -                ;  // 0xAA20
    -                          | -          | -                      | -                  | -                ;  // 0xAA30
    -                          | -          | -                      | -                  | -                ;  // 0xAA40
    -                          | -          | -                      | -                  | -                ;  // 0xAA50
    -                          | -          | -                      | -                  | -                ;  // 0xAA60
    -                          | -          | -                      | -                  | -                ;  // 0xAA70
    -                          | -          | -                      | -                  | -                ;  // 0xAA80
    -                          | -          | -                      | -                  | -                ;  // 0xAA90
    -                          | -          | -                      | -                  | -                ;  // 0xAAA0
    -                          | -          | -                      | -                  | -                ;  // 0xAAB0
    -                          | -          | -                      | -                  | -                ;  // 0xAAC0
    -                          | -          | -                      | -                  | -                ;  // 0xAAD0
    -                          | -          | -                      | -                  | -                ;  // 0xAAE0
    -                          | -          | -                      | -                  | -                ;  // 0xAAF0
    -                          | -          | -                      | -                  | -                ;  // 0xAB00
    -                          | -          | -                      | -                  | -                ;  // 0xAB10
    -                          | -          | -                      | -                  | -                ;  // 0xAB20
    -                          | -          | -                      | -                  | -                ;  // 0xAB30
    -                          | -          | -                      | -                  | -                ;  // 0xAB40
    -                          | -          | -                      | -                  | -                ;  // 0xAB50
    -                          | -          | -                      | -                  | -                ;  // 0xAB60
    -                          | -          | -                      | -                  | -                ;  // 0xAB70
    -                          | -          | -                      | -                  | -                ;  // 0xAB80
    -                          | -          | -                      | -                  | -                ;  // 0xAB90
    -                          | -          | -                      | -                  | -                ;  // 0xABA0
    -                          | -          | -                      | -                  | -                ;  // 0xABB0
    -                          | -          | -                      | -                  | -                ;  // 0xABC0
    -                          | -          | -                      | -                  | -                ;  // 0xABD0
    -                          | -          | -                      | -                  | -                ;  // 0xABE0
    -                          | -          | -                      | -                  | -                ;  // 0xABF0
    -                          | -          | -                      | -                  | -                ;  // 0xAC00
    -                          | -          | -                      | -                  | -                ;  // 0xAC10
    -                          | -          | -                      | -                  | -                ;  // 0xAC20
    -                          | -          | -                      | -                  | -                ;  // 0xAC30
    -                          | -          | -                      | -                  | -                ;  // 0xAC40
    -                          | -          | -                      | -                  | -                ;  // 0xAC50
    -                          | -          | -                      | -                  | -                ;  // 0xAC60
    -                          | -          | -                      | -                  | -                ;  // 0xAC70
    -                          | -          | -                      | -                  | -                ;  // 0xAC80
    -                          | -          | -                      | -                  | -                ;  // 0xAC90
    -                          | -          | -                      | -                  | -                ;  // 0xACA0
    -                          | -          | -                      | -                  | -                ;  // 0xACB0
    -                          | -          | -                      | -                  | -                ;  // 0xACC0
    -                          | -          | -                      | -                  | -                ;  // 0xACD0
    -                          | -          | -                      | -                  | -                ;  // 0xACE0
    -                          | -          | -                      | -                  | -                ;  // 0xACF0
    -                          | -          | -                      | -                  | -                ;  // 0xAD00
    -                          | -          | -                      | -                  | -                ;  // 0xAD10
    -                          | -          | -                      | -                  | -                ;  // 0xAD20
    -                          | -          | -                      | -                  | -                ;  // 0xAD30
    -                          | -          | -                      | -                  | -                ;  // 0xAD40
    -                          | -          | -                      | -                  | -                ;  // 0xAD50
    -                          | -          | -                      | -                  | -                ;  // 0xAD60
    -                          | -          | -                      | -                  | -                ;  // 0xAD70
    -                          | -          | -                      | -                  | -                ;  // 0xAD80
    -                          | -          | -                      | -                  | -                ;  // 0xAD90
    -                          | -          | -                      | -                  | -                ;  // 0xADA0
    -                          | -          | -                      | -                  | -                ;  // 0xADB0
    -                          | -          | -                      | -                  | -                ;  // 0xADC0
    -                          | -          | -                      | -                  | -                ;  // 0xADD0
    -                          | -          | -                      | -                  | -                ;  // 0xADE0
    -                          | -          | -                      | -                  | -                ;  // 0xADF0
    -                          | -          | -                      | -                  | -                ;  // 0xAE00
    -                          | -          | -                      | -                  | -                ;  // 0xAE10
    -                          | -          | -                      | -                  | -                ;  // 0xAE20
    -                          | -          | -                      | -                  | -                ;  // 0xAE30
    -                          | -          | -                      | -                  | -                ;  // 0xAE40
    -                          | -          | -                      | -                  | -                ;  // 0xAE50
    -                          | -          | -                      | -                  | -                ;  // 0xAE60
    -                          | -          | -                      | -                  | -                ;  // 0xAE70
    -                          | -          | -                      | -                  | -                ;  // 0xAE80
    -                          | -          | -                      | -                  | -                ;  // 0xAE90
    -                          | -          | -                      | -                  | -                ;  // 0xAEA0
    -                          | -          | -                      | -                  | -                ;  // 0xAEB0
    -                          | -          | -                      | -                  | -                ;  // 0xAEC0
    -                          | -          | -                      | -                  | br.al __scribe_int ;  // 0xAED0
    -                          | -          | -                      | -                  | -                ;  // 0xAEE0

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __str0                       0x2000     DMEM (datos)
//   __str1                       0x202C     DMEM (datos)
//   __str2                       0x203C     DMEM (datos)
//   __str3                       0x204C     DMEM (datos)
//   __str4                       0x2058     DMEM (datos)
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   convolucionar                0x00A0     IMEM bundle 10
//   __convolucionar_cuerpo       0x0260     IMEM bundle 38
//   L0                           0x04B0     IMEM bundle 75
//   __c14_si                     0x0590     IMEM bundle 89
//   __c14_fin                    0x05C0     IMEM bundle 92
//   L3                           0x0670     IMEM bundle 103
//   __c15_si                     0x0750     IMEM bundle 117
//   __c15_fin                    0x0780     IMEM bundle 120
//   L6                           0x08B0     IMEM bundle 139
//   __c16_si                     0x0990     IMEM bundle 153
//   __c16_fin                    0x09C0     IMEM bundle 156
//   L9                           0x0AA0     IMEM bundle 170
//   __c17_si                     0x0B80     IMEM bundle 184
//   __c17_fin                    0x0BB0     IMEM bundle 187
//   __rango16_ok                 0x1210     IMEM bundle 289
//   __rango17_ok                 0x1330     IMEM bundle 307
//   __rango18_ok                 0x1670     IMEM bundle 359
//   __rango19_ok                 0x1810     IMEM bundle 385
//   L10                          0x1AC0     IMEM bundle 428
//   L11                          0x1BB0     IMEM bundle 443
//   L7                           0x1BB0     IMEM bundle 443
//   L8                           0x1CA0     IMEM bundle 458
//   __rango20_ok                 0x1DC0     IMEM bundle 476
//   __rango21_ok                 0x1EE0     IMEM bundle 494
//   L4                           0x2060     IMEM bundle 518
//   L5                           0x2150     IMEM bundle 533
//   L1                           0x2150     IMEM bundle 533
//   L2                           0x2240     IMEM bundle 548
//   principale                   0x22A0     IMEM bundle 554
//   __principale_cuerpo          0x22E0     IMEM bundle 558
//   __n1_si                      0x4970     IMEM bundle 1175
//   __n1_fin                     0x49A0     IMEM bundle 1178
//   L12                          0x4BA0     IMEM bundle 1210
//   m_matriz_7eb00c1a$limitar    0x5730     IMEM bundle 1395
//   __m_matriz_7eb00c1a$limitar_cuerpo 0x5790     IMEM bundle 1401
//   __c18_si                     0x5870     IMEM bundle 1415
//   __c18_fin                    0x58A0     IMEM bundle 1418
//   L13                          0x5980     IMEM bundle 1432
//   __c19_si                     0x5A60     IMEM bundle 1446
//   __c19_fin                    0x5A90     IMEM bundle 1449
//   L15                          0x5B70     IMEM bundle 1463
//   L16                          0x5BD0     IMEM bundle 1469
//   L14                          0x5BD0     IMEM bundle 1469
//   m_matriz_7eb00c1a$imprimir   0x5C20     IMEM bundle 1474
//   __m_matriz_7eb00c1a$imprimir_cuerpo 0x5C90     IMEM bundle 1481
//   L17                          0x5CE0     IMEM bundle 1486
//   __c20_si                     0x5E00     IMEM bundle 1504
//   __c20_fin                    0x5E30     IMEM bundle 1507
//   L20                          0x5EE0     IMEM bundle 1518
//   __c21_si                     0x6000     IMEM bundle 1536
//   __c21_fin                    0x6030     IMEM bundle 1539
//   __rango22_ok                 0x61B0     IMEM bundle 1563
//   __rango23_ok                 0x62D0     IMEM bundle 1581
//   L21                          0x64F0     IMEM bundle 1615
//   L22                          0x65E0     IMEM bundle 1630
//   L18                          0x66F0     IMEM bundle 1647
//   L19                          0x67E0     IMEM bundle 1662
//   m_matriz_7eb00c1a$es_impar   0x6840     IMEM bundle 1668
//   __m_matriz_7eb00c1a$es_impar_cuerpo 0x6890     IMEM bundle 1673
//   __c22_si                     0x6A90     IMEM bundle 1705
//   __c22_fin                    0x6AC0     IMEM bundle 1708
//   m_estadistica_d879e4e7$total 0x6B40     IMEM bundle 1716
//   __m_estadistica_d879e4e7$total_cuerpo 0x6BA0     IMEM bundle 1722
//   L23                          0x6C40     IMEM bundle 1732
//   __c23_si                     0x6D60     IMEM bundle 1750
//   __c23_fin                    0x6D90     IMEM bundle 1753
//   L26                          0x6E40     IMEM bundle 1764
//   __c24_si                     0x6F60     IMEM bundle 1782
//   __c24_fin                    0x6F90     IMEM bundle 1785
//   __rango24_ok                 0x7110     IMEM bundle 1809
//   __rango25_ok                 0x7230     IMEM bundle 1827
//   L27                          0x7460     IMEM bundle 1862
//   L28                          0x7550     IMEM bundle 1877
//   L24                          0x7550     IMEM bundle 1877
//   L25                          0x7640     IMEM bundle 1892
//   m_estadistica_d879e4e7$promedio 0x76A0     IMEM bundle 1898
//   __m_estadistica_d879e4e7$promedio_cuerpo 0x7710     IMEM bundle 1905
//   m_estadistica_d879e4e7$maximo 0x7A20     IMEM bundle 1954
//   __m_estadistica_d879e4e7$maximo_cuerpo 0x7A80     IMEM bundle 1960
//   __rango26_ok                 0x7BE0     IMEM bundle 1982
//   __rango27_ok                 0x7D40     IMEM bundle 2004
//   L29                          0x7F40     IMEM bundle 2036
//   __c25_si                     0x8060     IMEM bundle 2054
//   __c25_fin                    0x8090     IMEM bundle 2057
//   L32                          0x8140     IMEM bundle 2068
//   __c26_si                     0x8260     IMEM bundle 2086
//   __c26_fin                    0x8290     IMEM bundle 2089
//   __rango28_ok                 0x8410     IMEM bundle 2113
//   __rango29_ok                 0x8530     IMEM bundle 2131
//   __c27_si                     0x87A0     IMEM bundle 2170
//   __c27_fin                    0x87D0     IMEM bundle 2173
//   __rango30_ok                 0x8950     IMEM bundle 2197
//   __rango31_ok                 0x8A70     IMEM bundle 2215
//   L35                          0x8C20     IMEM bundle 2242
//   L33                          0x8C20     IMEM bundle 2242
//   L34                          0x8D10     IMEM bundle 2257
//   L30                          0x8D10     IMEM bundle 2257
//   L31                          0x8E00     IMEM bundle 2272
//   __nova_div32                 0x8E60     IMEM bundle 2278
//   __dv_ok                      0x8F00     IMEM bundle 2288
//   __dv_a_pos                   0x9040     IMEM bundle 2308
//   __dv_b_pos                   0x9140     IMEM bundle 2324
//   __dv_bucle                   0x9190     IMEM bundle 2329
//   __dv_sigue                   0x9320     IMEM bundle 2354
//   __dv_c_pos                   0x94A0     IMEM bundle 2378
//   __dv_r_pos                   0x9580     IMEM bundle 2392
//   __scribe_int                 0x95D0     IMEM bundle 2397
//   __scribe_txt                 0x9D10     IMEM bundle 2513
//   __txt_bucle                  0xA4C0     IMEM bundle 2636
//   __txt_fin                    0xA5C0     IMEM bundle 2652
//   __dic_fin                    0xA620     IMEM bundle 2658
//   112 etiquetas de codigo, 7 de datos

// fin del programa
