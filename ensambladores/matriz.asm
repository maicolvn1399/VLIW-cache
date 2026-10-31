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
    .word 0

    .org 0x3000
__out_n:
    .word 0
__out_buf:
    .space 4092

.text
    .org 0x0000
    // Modulo de biblioteca: no tiene principale, no lleva arranque
    // functio limitar
limitar:
    // marco de 16 bytes
    subi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0000
    -                          | -          | -                      | -                  | -                ;  // 0x0010
    -                          | -          | -                      | -                  | -                ;  // 0x0020
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x0030
    -                          | -          | sw r7, #4(r14)         | -                  | -                ;  // 0x0040
    -                          | -          | sw r8, #0(r14)         | -                  | -                ;  // 0x0050
__limitar_cuerpo:
    // Nova fuente: linea 3, columna 6
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0060
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x00A0
    -                          | -          | -                      | -                  | -                ;  // 0x00B0
    -                          | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | -                      | -                  | br.lt __c0_si    ;  // 0x00D0
    -                          | -          | -                      | -                  | -                ;  // 0x00E0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x00F0
    -                          | -          | -                      | -                  | -                ;  // 0x0100
    -                          | -          | -                      | -                  | -                ;  // 0x0110
    -                          | -          | -                      | -                  | br.al __c0_fin   ;  // 0x0120
    -                          | -          | -                      | -                  | -                ;  // 0x0130
__c0_si:
    // Nova fuente: linea 3, columna 6
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | -                      | -                  | -                ;  // 0x0150
    -                          | -          | -                      | -                  | -                ;  // 0x0160
__c0_fin:
    // Nova fuente: linea 3, columna 6
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0170
    // Nova fuente: linea 3, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0180
    -                          | -          | -                      | -                  | -                ;  // 0x0190
    -                          | -          | -                      | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | br.eq L0         ;  // 0x01B0
    -                          | -          | -                      | -                  | -                ;  // 0x01C0
    // Nova fuente: linea 4, columna 2
    -                          | -          | lw r6, #4(r14)         | -                  | -                ;  // 0x01D0
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x01E0
    -                          | -          | -                      | -                  | -                ;  // 0x01F0
    -                          | -          | -                      | -                  | -                ;  // 0x0200
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0210
    -                          | -          | -                      | -                  | -                ;  // 0x0220
    -                          | -          | -                      | -                  | br.al L1         ;  // 0x0230
    -                          | -          | -                      | -                  | -                ;  // 0x0240
L0:
    // Nova fuente: linea 5, columna 9
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0250
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x0260
    -                          | -          | -                      | -                  | -                ;  // 0x0270
    -                          | -          | -                      | -                  | -                ;  // 0x0280
    cmp r11, r10               | -          | -                      | -                  | -                ;  // 0x0290
    -                          | -          | -                      | -                  | -                ;  // 0x02A0
    -                          | -          | -                      | -                  | -                ;  // 0x02B0
    -                          | -          | -                      | -                  | br.lt __c1_si    ;  // 0x02C0
    -                          | -          | -                      | -                  | -                ;  // 0x02D0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x02E0
    -                          | -          | -                      | -                  | -                ;  // 0x02F0
    -                          | -          | -                      | -                  | -                ;  // 0x0300
    -                          | -          | -                      | -                  | br.al __c1_fin   ;  // 0x0310
    -                          | -          | -                      | -                  | -                ;  // 0x0320
__c1_si:
    // Nova fuente: linea 5, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0330
    -                          | -          | -                      | -                  | -                ;  // 0x0340
    -                          | -          | -                      | -                  | -                ;  // 0x0350
__c1_fin:
    // Nova fuente: linea 5, columna 9
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0360
    // Nova fuente: linea 5, columna 4
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0370
    -                          | -          | -                      | -                  | -                ;  // 0x0380
    -                          | -          | -                      | -                  | -                ;  // 0x0390
    -                          | -          | -                      | -                  | br.eq L2         ;  // 0x03A0
    -                          | -          | -                      | -                  | -                ;  // 0x03B0
    // Nova fuente: linea 6, columna 2
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x03C0
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x03D0
    -                          | -          | -                      | -                  | -                ;  // 0x03E0
    -                          | -          | -                      | -                  | -                ;  // 0x03F0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0400
    -                          | -          | -                      | -                  | -                ;  // 0x0410
    -                          | -          | -                      | -                  | br.al L3         ;  // 0x0420
    -                          | -          | -                      | -                  | -                ;  // 0x0430
L2:
    // Nova fuente: linea 8, columna 2
    -                          | -          | lw r6, #8(r14)         | -                  | -                ;  // 0x0440
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0450
    -                          | -          | -                      | -                  | -                ;  // 0x0460
    -                          | -          | -                      | -                  | -                ;  // 0x0470
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0480
    -                          | -          | -                      | -                  | -                ;  // 0x0490
L3:
L1:
    // Nova fuente: linea 2, columna 9
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x04A0
    -                          | -          | -                      | -                  | -                ;  // 0x04B0
    -                          | -          | -                      | -                  | -                ;  // 0x04C0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    // functio imprimir
imprimir:
    // marco de 32 bytes, guarda R15 en #28(r14)
    subi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x04F0
    -                          | -          | -                      | -                  | -                ;  // 0x0500
    -                          | -          | -                      | -                  | -                ;  // 0x0510
    -                          | -          | sw r15, #28(r14)       | -                  | -                ;  // 0x0520
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x0530
    -                          | -          | sw r7, #12(r14)        | -                  | -                ;  // 0x0540
    -                          | -          | sw r8, #16(r14)        | -                  | -                ;  // 0x0550
__imprimir_cuerpo:
    // Nova fuente: linea 12, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0560
    -                          | -          | -                      | -                  | -                ;  // 0x0570
    -                          | -          | -                      | -                  | -                ;  // 0x0580
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0590
    // Nova fuente: linea 12, columna 13
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x05A0
L4:
    // Nova fuente: linea 12, columna 34
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x05B0
    -                          | -          | -                      | -                  | -                ;  // 0x05C0
    -                          | -          | -                      | -                  | -                ;  // 0x05D0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x05E0
    // Nova fuente: linea 12, columna 30
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x05F0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0600
    -                          | -          | -                      | -                  | -                ;  // 0x0610
    -                          | -          | -                      | -                  | -                ;  // 0x0620
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | -                      | -                  | -                ;  // 0x0640
    -                          | -          | -                      | -                  | -                ;  // 0x0650
    -                          | -          | -                      | -                  | br.lt __c2_si    ;  // 0x0660
    -                          | -          | -                      | -                  | -                ;  // 0x0670
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0680
    -                          | -          | -                      | -                  | -                ;  // 0x0690
    -                          | -          | -                      | -                  | -                ;  // 0x06A0
    -                          | -          | -                      | -                  | br.al __c2_fin   ;  // 0x06B0
    -                          | -          | -                      | -                  | -                ;  // 0x06C0
__c2_si:
    // Nova fuente: linea 12, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x06D0
    -                          | -          | -                      | -                  | -                ;  // 0x06E0
    -                          | -          | -                      | -                  | -                ;  // 0x06F0
__c2_fin:
    // Nova fuente: linea 12, columna 30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0700
    // Nova fuente: linea 12, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0710
    -                          | -          | -                      | -                  | -                ;  // 0x0720
    -                          | -          | -                      | -                  | -                ;  // 0x0730
    -                          | -          | -                      | -                  | br.eq L6         ;  // 0x0740
    -                          | -          | -                      | -                  | -                ;  // 0x0750
    // Nova fuente: linea 13, columna 27
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0760
    -                          | -          | -                      | -                  | -                ;  // 0x0770
    -                          | -          | -                      | -                  | -                ;  // 0x0780
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0790
    // Nova fuente: linea 13, columna 13
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x07A0
L7:
    // Nova fuente: linea 13, columna 34
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x07B0
    -                          | -          | -                      | -                  | -                ;  // 0x07C0
    -                          | -          | -                      | -                  | -                ;  // 0x07D0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x07E0
    // Nova fuente: linea 13, columna 30
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x07F0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0800
    -                          | -          | -                      | -                  | -                ;  // 0x0810
    -                          | -          | -                      | -                  | -                ;  // 0x0820
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x0830
    -                          | -          | -                      | -                  | -                ;  // 0x0840
    -                          | -          | -                      | -                  | -                ;  // 0x0850
    -                          | -          | -                      | -                  | br.lt __c3_si    ;  // 0x0860
    -                          | -          | -                      | -                  | -                ;  // 0x0870
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0880
    -                          | -          | -                      | -                  | -                ;  // 0x0890
    -                          | -          | -                      | -                  | -                ;  // 0x08A0
    -                          | -          | -                      | -                  | br.al __c3_fin   ;  // 0x08B0
    -                          | -          | -                      | -                  | -                ;  // 0x08C0
__c3_si:
    // Nova fuente: linea 13, columna 30
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x08D0
    -                          | -          | -                      | -                  | -                ;  // 0x08E0
    -                          | -          | -                      | -                  | -                ;  // 0x08F0
__c3_fin:
    // Nova fuente: linea 13, columna 30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0900
    // Nova fuente: linea 13, columna 2
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0910
    -                          | -          | -                      | -                  | -                ;  // 0x0920
    -                          | -          | -                      | -                  | -                ;  // 0x0930
    -                          | -          | -                      | -                  | br.eq L9         ;  // 0x0940
    -                          | -          | -                      | -                  | -                ;  // 0x0950
    // Nova fuente: linea 14, columna 11
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x0960
    -                          | -          | -                      | -                  | -                ;  // 0x0970
    -                          | -          | -                      | -                  | -                ;  // 0x0980
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0990
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x09A0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x09B0
    -                          | -          | -                      | -                  | -                ;  // 0x09C0
    -                          | -          | -                      | -                  | -                ;  // 0x09D0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x09E0
    -                          | -          | -                      | -                  | -                ;  // 0x09F0
    -                          | -          | -                      | -                  | -                ;  // 0x0A00
    -                          | -          | -                      | -                  | br.ltu __rango0_ok ;  // 0x0A10
    -                          | -          | -                      | -                  | -                ;  // 0x0A20
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x0A30
    -                          | -          | -                      | -                  | -                ;  // 0x0A40
    -                          | -          | -                      | -                  | -                ;  // 0x0A50
    -                          | -          | -                      | -                  | halt             ;  // 0x0A60
    -                          | -          | -                      | -                  | -                ;  // 0x0A70
__rango0_ok:
    // Nova fuente: linea 14, columna 14
    -                          | -          | lw r10, #16(r14)       | -                  | -                ;  // 0x0A80
    -                          | -          | -                      | -                  | -                ;  // 0x0A90
    -                          | -          | -                      | -                  | -                ;  // 0x0AA0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0AB0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x0AC0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0AD0
    -                          | -          | -                      | -                  | -                ;  // 0x0AE0
    -                          | -          | -                      | -                  | -                ;  // 0x0AF0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x0B00
    -                          | -          | -                      | -                  | -                ;  // 0x0B10
    -                          | -          | -                      | -                  | -                ;  // 0x0B20
    -                          | -          | -                      | -                  | br.ltu __rango1_ok ;  // 0x0B30
    -                          | -          | -                      | -                  | -                ;  // 0x0B40
    movi r6, #134              | -          | -                      | -                  | -                ;  // 0x0B50
    -                          | -          | -                      | -                  | -                ;  // 0x0B60
    -                          | -          | -                      | -                  | -                ;  // 0x0B70
    -                          | -          | -                      | -                  | halt             ;  // 0x0B80
    -                          | -          | -                      | -                  | -                ;  // 0x0B90
__rango1_ok:
    // Nova fuente: linea 14, columna 14
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0BA0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0BB0
    -                          | -          | -                      | -                  | -                ;  // 0x0BC0
    -                          | -          | -                      | -                  | -                ;  // 0x0BD0
    mul r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0BE0
    -                          | -          | -                      | -                  | -                ;  // 0x0BF0
    -                          | -          | -                      | -                  | -                ;  // 0x0C00
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0C10
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x0C20
    -                          | -          | -                      | -                  | -                ;  // 0x0C30
    -                          | -          | -                      | -                  | -                ;  // 0x0C40
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0C50
    -                          | -          | -                      | -                  | -                ;  // 0x0C60
    -                          | -          | -                      | -                  | -                ;  // 0x0C70
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0C80
    // Nova fuente: linea 14, columna 9
    slli r10, r10, #2          | -          | -                      | -                  | -                ;  // 0x0C90
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0CA0
    -                          | -          | -                      | -                  | -                ;  // 0x0CB0
    -                          | -          | -                      | -                  | -                ;  // 0x0CC0
    add r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x0CD0
    -                          | -          | -                      | -                  | -                ;  // 0x0CE0
    -                          | -          | -                      | -                  | -                ;  // 0x0CF0
    -                          | -          | lw r10, #0(r11)        | -                  | -                ;  // 0x0D00
    -                          | -          | -                      | -                  | -                ;  // 0x0D10
    -                          | -          | -                      | -                  | -                ;  // 0x0D20
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0D30
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0D40
    // Nova fuente: linea 14, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x0D50
    -                          | -          | -                      | -                  | -                ;  // 0x0D60
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x0D70
    -                          | -          | -                      | -                  | -                ;  // 0x0D80
L8:
    // Nova fuente: linea 13, columna 56
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0D90
    -                          | -          | -                      | -                  | -                ;  // 0x0DA0
    -                          | -          | -                      | -                  | -                ;  // 0x0DB0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0DC0
    // Nova fuente: linea 13, columna 51
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x0DD0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0DE0
    -                          | -          | -                      | -                  | -                ;  // 0x0DF0
    -                          | -          | -                      | -                  | -                ;  // 0x0E00
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0E10
    -                          | -          | -                      | -                  | -                ;  // 0x0E20
    -                          | -          | -                      | -                  | -                ;  // 0x0E30
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0E40
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0E50
    -                          | -          | -                      | -                  | br.al L7         ;  // 0x0E60
    -                          | -          | -                      | -                  | -                ;  // 0x0E70
L9:
    // Nova fuente: linea 16, columna 6
    movi r10, #8192            | -          | -                      | -                  | -                ;  // 0x0E80
    -                          | -          | -                      | -                  | -                ;  // 0x0E90
    -                          | -          | -                      | -                  | -                ;  // 0x0EA0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0EB0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0EC0
    // Nova fuente: linea 16, columna 2
    -                          | -          | -                      | -                  | -                ;  // 0x0ED0
    -                          | -          | -                      | -                  | -                ;  // 0x0EE0
    -                          | -          | -                      | -                  | jal.al __scribe_txt ;  // 0x0EF0
    -                          | -          | -                      | -                  | -                ;  // 0x0F00
    -                          | -          | -                      | -                  | jal.al __dic_fin ;  // 0x0F10
    -                          | -          | -                      | -                  | -                ;  // 0x0F20
L5:
    // Nova fuente: linea 12, columna 53
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0F30
    -                          | -          | -                      | -                  | -                ;  // 0x0F40
    -                          | -          | -                      | -                  | -                ;  // 0x0F50
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x0F60
    // Nova fuente: linea 12, columna 48
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0F70
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x0F80
    -                          | -          | -                      | -                  | -                ;  // 0x0F90
    -                          | -          | -                      | -                  | -                ;  // 0x0FA0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0FB0
    -                          | -          | -                      | -                  | -                ;  // 0x0FC0
    -                          | -          | -                      | -                  | -                ;  // 0x0FD0
    -                          | -          | sw r10, #24(r14)       | -                  | -                ;  // 0x0FE0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0FF0
    -                          | -          | -                      | -                  | br.al L4         ;  // 0x1000
    -                          | -          | -                      | -                  | -                ;  // 0x1010
L6:
    // Nova fuente: linea 11, columna 9
    -                          | -          | lw r15, #28(r14)       | -                  | -                ;  // 0x1020
    addi r14, r14, #32         | -          | -                      | -                  | -                ;  // 0x1030
    -                          | -          | -                      | -                  | -                ;  // 0x1040
    -                          | -          | -                      | -                  | -                ;  // 0x1050
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x1060
    -                          | -          | -                      | -                  | -                ;  // 0x1070
    // functio es_impar
es_impar:
    // marco de 20 bytes, guarda R15 en #16(r14)
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x1080
    -                          | -          | -                      | -                  | -                ;  // 0x1090
    -                          | -          | -                      | -                  | -                ;  // 0x10A0
    -                          | -          | sw r15, #16(r14)       | -                  | -                ;  // 0x10B0
    -                          | -          | sw r6, #0(r14)         | -                  | -                ;  // 0x10C0
__es_impar_cuerpo:
    // Nova fuente: linea 20, columna 12
    movi r10, #2               | -          | -                      | -                  | -                ;  // 0x10D0
    -                          | -          | -                      | -                  | -                ;  // 0x10E0
    -                          | -          | -                      | -                  | -                ;  // 0x10F0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x1100
    // Nova fuente: linea 20, columna 8
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x1110
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x1120
    -                          | -          | -                      | -                  | -                ;  // 0x1130
    -                          | -          | -                      | -                  | -                ;  // 0x1140
    -                          | -          | -                      | -                  | jal.al __nova_div32 ;  // 0x1150
    -                          | -          | -                      | -                  | -                ;  // 0x1160
    -                          | -          | sw r7, #8(r14)         | -                  | -                ;  // 0x1170
    // Nova fuente: linea 20, columna 17
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1180
    -                          | -          | -                      | -                  | -                ;  // 0x1190
    -                          | -          | -                      | -                  | -                ;  // 0x11A0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x11B0
    // Nova fuente: linea 20, columna 8
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x11C0
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x11D0
    -                          | -          | -                      | -                  | -                ;  // 0x11E0
    -                          | -          | -                      | -                  | -                ;  // 0x11F0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1200
    -                          | -          | -                      | -                  | -                ;  // 0x1210
    -                          | -          | -                      | -                  | -                ;  // 0x1220
    -                          | -          | -                      | -                  | br.eq __c4_si    ;  // 0x1230
    -                          | -          | -                      | -                  | -                ;  // 0x1240
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x1250
    -                          | -          | -                      | -                  | -                ;  // 0x1260
    -                          | -          | -                      | -                  | -                ;  // 0x1270
    -                          | -          | -                      | -                  | br.al __c4_fin   ;  // 0x1280
    -                          | -          | -                      | -                  | -                ;  // 0x1290
__c4_si:
    // Nova fuente: linea 20, columna 8
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x12A0
    -                          | -          | -                      | -                  | -                ;  // 0x12B0
    -                          | -          | -                      | -                  | -                ;  // 0x12C0
__c4_fin:
    // Nova fuente: linea 20, columna 8
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x12D0
    // Nova fuente: linea 20, columna 2
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x12E0
    -                          | -          | lw r15, #16(r14)       | -                  | -                ;  // 0x12F0
    addi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x1300
    -                          | -          | -                      | -                  | -                ;  // 0x1310
    -                          | -          | -                      | -                  | -                ;  // 0x1320
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x1330
    -                          | -          | -                      | -                  | -                ;  // 0x1340
    // __nova_div32(R6 = a, R7 = b) -> R6 = a/b, R7 = a%b, con signo
__nova_div32:
    cmpi r7, #0                | -          | -                      | -                  | -                ;  // 0x1350
    -                          | -          | -                      | -                  | -                ;  // 0x1360
    -                          | -          | -                      | -                  | -                ;  // 0x1370
    -                          | -          | -                      | -                  | br.ne __dv_ok    ;  // 0x1380
    -                          | -          | -                      | -                  | -                ;  // 0x1390
    movi r6, #136              | -          | -                      | -                  | -                ;  // 0x13A0
    -                          | -          | -                      | -                  | -                ;  // 0x13B0
    -                          | -          | -                      | -                  | -                ;  // 0x13C0
    -                          | -          | -                      | -                  | halt             ;  // 0x13D0
    -                          | -          | -                      | -                  | -                ;  // 0x13E0
__dv_ok:
    subi r14, r14, #8          | -          | -                      | -                  | -                ;  // 0x13F0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x1400
    -                          | -          | -                      | -                  | -                ;  // 0x1410
    -                          | -          | -                      | -                  | -                ;  // 0x1420
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x1430
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x1440
    cmpi r6, #0                | -          | -                      | -                  | -                ;  // 0x1450
    -                          | -          | -                      | -                  | -                ;  // 0x1460
    -                          | -          | -                      | -                  | -                ;  // 0x1470
    -                          | -          | -                      | -                  | br.ge __dv_a_pos ;  // 0x1480
    -                          | -          | -                      | -                  | -                ;  // 0x1490
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x14A0
    -                          | -          | -                      | -                  | -                ;  // 0x14B0
    -                          | -          | -                      | -                  | -                ;  // 0x14C0
    sub r6, r10, r6            | -          | -                      | -                  | -                ;  // 0x14D0
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x14E0
    -                          | -          | -                      | -                  | -                ;  // 0x14F0
    -                          | -          | -                      | -                  | -                ;  // 0x1500
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x1510
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x1520
__dv_a_pos:
    cmpi r7, #0                | -          | -                      | -                  | -                ;  // 0x1530
    -                          | -          | -                      | -                  | -                ;  // 0x1540
    -                          | -          | -                      | -                  | -                ;  // 0x1550
    -                          | -          | -                      | -                  | br.ge __dv_b_pos ;  // 0x1560
    -                          | -          | -                      | -                  | -                ;  // 0x1570
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x1580
    -                          | -          | -                      | -                  | -                ;  // 0x1590
    -                          | -          | -                      | -                  | -                ;  // 0x15A0
    sub r7, r10, r7            | -          | -                      | -                  | -                ;  // 0x15B0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x15C0
    -                          | -          | -                      | -                  | -                ;  // 0x15D0
    -                          | -          | -                      | -                  | -                ;  // 0x15E0
    xori r10, r10, #1          | -          | -                      | -                  | -                ;  // 0x15F0
    -                          | -          | -                      | -                  | -                ;  // 0x1600
    -                          | -          | -                      | -                  | -                ;  // 0x1610
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x1620
__dv_b_pos:
    movi r8, #0                | -          | -                      | -                  | -                ;  // 0x1630
    movi r9, #0                | -          | -                      | -                  | -                ;  // 0x1640
    movi r10, #31              | -          | -                      | -                  | -                ;  // 0x1650
    -                          | -          | -                      | -                  | -                ;  // 0x1660
    -                          | -          | -                      | -                  | -                ;  // 0x1670
__dv_bucle:
    srl r11, r6, r10           | -          | -                      | -                  | -                ;  // 0x1680
    -                          | -          | -                      | -                  | -                ;  // 0x1690
    -                          | -          | -                      | -                  | -                ;  // 0x16A0
    andi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x16B0
    slli r9, r9, #1            | -          | -                      | -                  | -                ;  // 0x16C0
    -                          | -          | -                      | -                  | -                ;  // 0x16D0
    -                          | -          | -                      | -                  | -                ;  // 0x16E0
    or r9, r9, r11             | -          | -                      | -                  | -                ;  // 0x16F0
    -                          | -          | -                      | -                  | -                ;  // 0x1700
    -                          | -          | -                      | -                  | -                ;  // 0x1710
    cmp r9, r7                 | -          | -                      | -                  | -                ;  // 0x1720
    -                          | -          | -                      | -                  | -                ;  // 0x1730
    -                          | -          | -                      | -                  | -                ;  // 0x1740
    -                          | -          | -                      | -                  | br.ltu __dv_sigue ;  // 0x1750
    -                          | -          | -                      | -                  | -                ;  // 0x1760
    sub r9, r9, r7             | -          | -                      | -                  | -                ;  // 0x1770
    movi r11, #1               | -          | -                      | -                  | -                ;  // 0x1780
    -                          | -          | -                      | -                  | -                ;  // 0x1790
    -                          | -          | -                      | -                  | -                ;  // 0x17A0
    sll r11, r11, r10          | -          | -                      | -                  | -                ;  // 0x17B0
    -                          | -          | -                      | -                  | -                ;  // 0x17C0
    -                          | -          | -                      | -                  | -                ;  // 0x17D0
    or r8, r8, r11             | -          | -                      | -                  | -                ;  // 0x17E0
    -                          | -          | -                      | -                  | -                ;  // 0x17F0
    -                          | -          | -                      | -                  | -                ;  // 0x1800
__dv_sigue:
    subi r10, r10, #1          | -          | -                      | -                  | -                ;  // 0x1810
    -                          | -          | -                      | -                  | -                ;  // 0x1820
    -                          | -          | -                      | -                  | -                ;  // 0x1830
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x1840
    -                          | -          | -                      | -                  | -                ;  // 0x1850
    -                          | -          | -                      | -                  | -                ;  // 0x1860
    -                          | -          | -                      | -                  | br.ge __dv_bucle ;  // 0x1870
    -                          | -          | -                      | -                  | -                ;  // 0x1880
    mov r6, r8                 | -          | -                      | -                  | -                ;  // 0x1890
    mov r7, r9                 | -          | -                      | -                  | -                ;  // 0x18A0
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x18B0
    -                          | -          | -                      | -                  | -                ;  // 0x18C0
    -                          | -          | -                      | -                  | -                ;  // 0x18D0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x18E0
    -                          | -          | -                      | -                  | -                ;  // 0x18F0
    -                          | -          | -                      | -                  | -                ;  // 0x1900
    -                          | -          | -                      | -                  | br.eq __dv_c_pos ;  // 0x1910
    -                          | -          | -                      | -                  | -                ;  // 0x1920
    movi r11, #0               | -          | -                      | -                  | -                ;  // 0x1930
    -                          | -          | -                      | -                  | -                ;  // 0x1940
    -                          | -          | -                      | -                  | -                ;  // 0x1950
    sub r6, r11, r6            | -          | -                      | -                  | -                ;  // 0x1960
    -                          | -          | -                      | -                  | -                ;  // 0x1970
    -                          | -          | -                      | -                  | -                ;  // 0x1980
__dv_c_pos:
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x1990
    -                          | -          | -                      | -                  | -                ;  // 0x19A0
    -                          | -          | -                      | -                  | -                ;  // 0x19B0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x19C0
    -                          | -          | -                      | -                  | -                ;  // 0x19D0
    -                          | -          | -                      | -                  | -                ;  // 0x19E0
    -                          | -          | -                      | -                  | br.eq __dv_r_pos ;  // 0x19F0
    -                          | -          | -                      | -                  | -                ;  // 0x1A00
    movi r11, #0               | -          | -                      | -                  | -                ;  // 0x1A10
    -                          | -          | -                      | -                  | -                ;  // 0x1A20
    -                          | -          | -                      | -                  | -                ;  // 0x1A30
    sub r7, r11, r7            | -          | -                      | -                  | -                ;  // 0x1A40
    -                          | -          | -                      | -                  | -                ;  // 0x1A50
    -                          | -          | -                      | -                  | -                ;  // 0x1A60
__dv_r_pos:
    addi r14, r14, #8          | -          | -                      | -                  | -                ;  // 0x1A70
    -                          | -          | -                      | -                  | -                ;  // 0x1A80
    -                          | -          | -                      | -                  | -                ;  // 0x1A90
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x1AA0
    -                          | -          | -                      | -                  | -                ;  // 0x1AB0
    // __scribe_int(R6 = valor): el ISA no define puertos de E/S, los resultados se dejan en memoria para las herramientas de CE 4301
__scribe_int:
    movi r10, #12288           | -          | -                      | -                  | -                ;  // 0x1AC0
    -                          | -          | -                      | -                  | -                ;  // 0x1AD0
    -                          | -          | -                      | -                  | -                ;  // 0x1AE0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x1AF0
    -                          | -          | -                      | -                  | -                ;  // 0x1B00
    -                          | -          | -                      | -                  | -                ;  // 0x1B10
    slli r11, r11, #2          | -          | -                      | -                  | -                ;  // 0x1B20
    -                          | -          | -                      | -                  | -                ;  // 0x1B30
    -                          | -          | -                      | -                  | -                ;  // 0x1B40
    addi r11, r11, #4          | -          | -                      | -                  | -                ;  // 0x1B50
    -                          | -          | -                      | -                  | -                ;  // 0x1B60
    -                          | -          | -                      | -                  | -                ;  // 0x1B70
    add r11, r10, r11          | -          | -                      | -                  | -                ;  // 0x1B80
    -                          | -          | -                      | -                  | -                ;  // 0x1B90
    -                          | -          | -                      | -                  | -                ;  // 0x1BA0
    -                          | -          | sw r6, #0(r11)         | -                  | -                ;  // 0x1BB0
    -                          | -          | lw r11, #0(r10)        | -                  | -                ;  // 0x1BC0
    -                          | -          | -                      | -                  | -                ;  // 0x1BD0
    -                          | -          | -                      | -                  | -                ;  // 0x1BE0
    addi r11, r11, #1          | -          | -                      | -                  | -                ;  // 0x1BF0
    -                          | -          | -                      | -                  | -                ;  // 0x1C00
    -                          | -          | -                      | -                  | -                ;  // 0x1C10
    -                          | -          | sw r11, #0(r10)        | -                  | -                ;  // 0x1C20
    -                          | -          | -                      | -                  | -                ;  // 0x1C30
    -                          | -          | -                      | -                  | -                ;  // 0x1C40
    -                          | -          | -                      | -                  | -                ;  // 0x1C50
    -                          | -          | -                      | -                  | -                ;  // 0x1C60
    -                          | -          | -                      | -                  | -                ;  // 0x1C70
    -                          | -          | -                      | -                  | -                ;  // 0x1C80
    -                          | -          | -                      | -                  | -                ;  // 0x1C90
    -                          | -          | -                      | -                  | -                ;  // 0x1CA0
    -                          | -          | -                      | -                  | -                ;  // 0x1CB0
    -                          | -          | -                      | -                  | -                ;  // 0x1CC0
    -                          | -          | -                      | -                  | -                ;  // 0x1CD0
    -                          | -          | -                      | -                  | -                ;  // 0x1CE0
    -                          | -          | -                      | -                  | -                ;  // 0x1CF0
    -                          | -          | -                      | -                  | -                ;  // 0x1D00
    -                          | -          | -                      | -                  | -                ;  // 0x1D10
    -                          | -          | -                      | -                  | -                ;  // 0x1D20
    -                          | -          | -                      | -                  | -                ;  // 0x1D30
    -                          | -          | -                      | -                  | -                ;  // 0x1D40
    -                          | -          | -                      | -                  | -                ;  // 0x1D50
    -                          | -          | -                      | -                  | -                ;  // 0x1D60
    -                          | -          | -                      | -                  | -                ;  // 0x1D70
    -                          | -          | -                      | -                  | -                ;  // 0x1D80
    -                          | -          | -                      | -                  | -                ;  // 0x1D90
    -                          | -          | -                      | -                  | -                ;  // 0x1DA0
    -                          | -          | -                      | -                  | -                ;  // 0x1DB0
    -                          | -          | -                      | -                  | -                ;  // 0x1DC0
    -                          | -          | -                      | -                  | -                ;  // 0x1DD0
    -                          | -          | -                      | -                  | -                ;  // 0x1DE0
    -                          | -          | -                      | -                  | -                ;  // 0x1DF0
    -                          | -          | -                      | -                  | -                ;  // 0x1E00
    -                          | -          | -                      | -                  | -                ;  // 0x1E10
    -                          | -          | -                      | -                  | -                ;  // 0x1E20
    -                          | -          | -                      | -                  | -                ;  // 0x1E30
    -                          | -          | -                      | -                  | -                ;  // 0x1E40
    -                          | -          | -                      | -                  | -                ;  // 0x1E50
    -                          | -          | -                      | -                  | -                ;  // 0x1E60
    -                          | -          | -                      | -                  | -                ;  // 0x1E70
    -                          | -          | -                      | -                  | -                ;  // 0x1E80
    -                          | -          | -                      | -                  | -                ;  // 0x1E90
    -                          | -          | -                      | -                  | -                ;  // 0x1EA0
    -                          | -          | -                      | -                  | -                ;  // 0x1EB0
    -                          | -          | -                      | -                  | -                ;  // 0x1EC0
    -                          | -          | -                      | -                  | -                ;  // 0x1ED0
    -                          | -          | -                      | -                  | -                ;  // 0x1EE0
    -                          | -          | -                      | -                  | -                ;  // 0x1EF0
    -                          | -          | -                      | -                  | -                ;  // 0x1F00
    -                          | -          | -                      | -                  | -                ;  // 0x1F10
    -                          | -          | -                      | -                  | -                ;  // 0x1F20
    -                          | -          | -                      | -                  | -                ;  // 0x1F30
    -                          | -          | -                      | -                  | -                ;  // 0x1F40
    -                          | -          | -                      | -                  | -                ;  // 0x1F50
    -                          | -          | -                      | -                  | -                ;  // 0x1F60
    -                          | -          | -                      | -                  | -                ;  // 0x1F70
    -                          | -          | -                      | -                  | -                ;  // 0x1F80
    -                          | -          | -                      | -                  | -                ;  // 0x1F90
    -                          | -          | -                      | -                  | -                ;  // 0x1FA0
    -                          | -          | -                      | -                  | -                ;  // 0x1FB0
    -                          | -          | -                      | -                  | -                ;  // 0x1FC0
    -                          | -          | -                      | -                  | -                ;  // 0x1FD0
    -                          | -          | -                      | -                  | -                ;  // 0x1FE0
    -                          | -          | -                      | -                  | -                ;  // 0x1FF0
    -                          | -          | -                      | -                  | -                ;  // 0x2000
    -                          | -          | -                      | -                  | -                ;  // 0x2010
    -                          | -          | -                      | -                  | -                ;  // 0x2020
    -                          | -          | -                      | -                  | -                ;  // 0x2030
    -                          | -          | -                      | -                  | -                ;  // 0x2040
    -                          | -          | -                      | -                  | -                ;  // 0x2050
    -                          | -          | -                      | -                  | -                ;  // 0x2060
    -                          | -          | -                      | -                  | -                ;  // 0x2070
    -                          | -          | -                      | -                  | -                ;  // 0x2080
    -                          | -          | -                      | -                  | -                ;  // 0x2090
    -                          | -          | -                      | -                  | -                ;  // 0x20A0
    -                          | -          | -                      | -                  | -                ;  // 0x20B0
    -                          | -          | -                      | -                  | -                ;  // 0x20C0
    -                          | -          | -                      | -                  | -                ;  // 0x20D0
    -                          | -          | -                      | -                  | -                ;  // 0x20E0
    -                          | -          | -                      | -                  | -                ;  // 0x20F0
    -                          | -          | -                      | -                  | -                ;  // 0x2100
    -                          | -          | -                      | -                  | -                ;  // 0x2110
    -                          | -          | -                      | -                  | -                ;  // 0x2120
    -                          | -          | -                      | -                  | -                ;  // 0x2130
    -                          | -          | -                      | -                  | -                ;  // 0x2140
    -                          | -          | -                      | -                  | -                ;  // 0x2150
    -                          | -          | -                      | -                  | -                ;  // 0x2160
    -                          | -          | -                      | -                  | -                ;  // 0x2170
    -                          | -          | -                      | -                  | -                ;  // 0x2180
    -                          | -          | -                      | -                  | -                ;  // 0x2190
    -                          | -          | -                      | -                  | -                ;  // 0x21A0
    -                          | -          | -                      | -                  | -                ;  // 0x21B0
    -                          | -          | -                      | -                  | -                ;  // 0x21C0
    -                          | -          | -                      | -                  | -                ;  // 0x21D0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x21E0
    -                          | -          | -                      | -                  | -                ;  // 0x21F0
    // __scribe_txt(R6 = direccion): escribe la longitud y las palabras
__scribe_txt:
    subi r14, r14, #4          | -          | -                      | -                  | -                ;  // 0x2200
    -                          | -          | -                      | -                  | -                ;  // 0x2210
    -                          | -          | -                      | -                  | -                ;  // 0x2220
    -                          | -          | sw r15, #0(r14)        | -                  | -                ;  // 0x2230
    -                          | -          | lw r7, #0(r6)          | -                  | -                ;  // 0x2240
    mov r9, r6                 | -          | -                      | -                  | -                ;  // 0x2250
    -                          | -          | -                      | -                  | -                ;  // 0x2260
    mov r6, r7                 | -          | -                      | -                  | -                ;  // 0x2270
    -                          | -          | -                      | -                  | -                ;  // 0x2280
    -                          | -          | -                      | -                  | -                ;  // 0x2290
    -                          | -          | -                      | -                  | -                ;  // 0x22A0
    -                          | -          | -                      | -                  | -                ;  // 0x22B0
    -                          | -          | -                      | -                  | -                ;  // 0x22C0
    -                          | -          | -                      | -                  | -                ;  // 0x22D0
    -                          | -          | -                      | -                  | -                ;  // 0x22E0
    -                          | -          | -                      | -                  | -                ;  // 0x22F0
    -                          | -          | -                      | -                  | -                ;  // 0x2300
    -                          | -          | -                      | -                  | -                ;  // 0x2310
    -                          | -          | -                      | -                  | -                ;  // 0x2320
    -                          | -          | -                      | -                  | -                ;  // 0x2330
    -                          | -          | -                      | -                  | -                ;  // 0x2340
    -                          | -          | -                      | -                  | -                ;  // 0x2350
    -                          | -          | -                      | -                  | -                ;  // 0x2360
    -                          | -          | -                      | -                  | -                ;  // 0x2370
    -                          | -          | -                      | -                  | -                ;  // 0x2380
    -                          | -          | -                      | -                  | -                ;  // 0x2390
    -                          | -          | -                      | -                  | -                ;  // 0x23A0
    -                          | -          | -                      | -                  | -                ;  // 0x23B0
    -                          | -          | -                      | -                  | -                ;  // 0x23C0
    -                          | -          | -                      | -                  | -                ;  // 0x23D0
    -                          | -          | -                      | -                  | -                ;  // 0x23E0
    -                          | -          | -                      | -                  | -                ;  // 0x23F0
    -                          | -          | -                      | -                  | -                ;  // 0x2400
    -                          | -          | -                      | -                  | -                ;  // 0x2410
    -                          | -          | -                      | -                  | -                ;  // 0x2420
    -                          | -          | -                      | -                  | -                ;  // 0x2430
    -                          | -          | -                      | -                  | -                ;  // 0x2440
    -                          | -          | -                      | -                  | -                ;  // 0x2450
    -                          | -          | -                      | -                  | -                ;  // 0x2460
    -                          | -          | -                      | -                  | -                ;  // 0x2470
    -                          | -          | -                      | -                  | -                ;  // 0x2480
    -                          | -          | -                      | -                  | -                ;  // 0x2490
    -                          | -          | -                      | -                  | -                ;  // 0x24A0
    -                          | -          | -                      | -                  | -                ;  // 0x24B0
    -                          | -          | -                      | -                  | -                ;  // 0x24C0
    -                          | -          | -                      | -                  | -                ;  // 0x24D0
    -                          | -          | -                      | -                  | -                ;  // 0x24E0
    -                          | -          | -                      | -                  | -                ;  // 0x24F0
    -                          | -          | -                      | -                  | -                ;  // 0x2500
    -                          | -          | -                      | -                  | -                ;  // 0x2510
    -                          | -          | -                      | -                  | -                ;  // 0x2520
    -                          | -          | -                      | -                  | -                ;  // 0x2530
    -                          | -          | -                      | -                  | -                ;  // 0x2540
    -                          | -          | -                      | -                  | -                ;  // 0x2550
    -                          | -          | -                      | -                  | -                ;  // 0x2560
    -                          | -          | -                      | -                  | -                ;  // 0x2570
    -                          | -          | -                      | -                  | -                ;  // 0x2580
    -                          | -          | -                      | -                  | -                ;  // 0x2590
    -                          | -          | -                      | -                  | -                ;  // 0x25A0
    -                          | -          | -                      | -                  | -                ;  // 0x25B0
    -                          | -          | -                      | -                  | -                ;  // 0x25C0
    -                          | -          | -                      | -                  | -                ;  // 0x25D0
    -                          | -          | -                      | -                  | -                ;  // 0x25E0
    -                          | -          | -                      | -                  | -                ;  // 0x25F0
    -                          | -          | -                      | -                  | -                ;  // 0x2600
    -                          | -          | -                      | -                  | -                ;  // 0x2610
    -                          | -          | -                      | -                  | -                ;  // 0x2620
    -                          | -          | -                      | -                  | -                ;  // 0x2630
    -                          | -          | -                      | -                  | -                ;  // 0x2640
    -                          | -          | -                      | -                  | -                ;  // 0x2650
    -                          | -          | -                      | -                  | -                ;  // 0x2660
    -                          | -          | -                      | -                  | -                ;  // 0x2670
    -                          | -          | -                      | -                  | -                ;  // 0x2680
    -                          | -          | -                      | -                  | -                ;  // 0x2690
    -                          | -          | -                      | -                  | -                ;  // 0x26A0
    -                          | -          | -                      | -                  | -                ;  // 0x26B0
    -                          | -          | -                      | -                  | -                ;  // 0x26C0
    -                          | -          | -                      | -                  | -                ;  // 0x26D0
    -                          | -          | -                      | -                  | -                ;  // 0x26E0
    -                          | -          | -                      | -                  | -                ;  // 0x26F0
    -                          | -          | -                      | -                  | -                ;  // 0x2700
    -                          | -          | -                      | -                  | -                ;  // 0x2710
    -                          | -          | -                      | -                  | -                ;  // 0x2720
    -                          | -          | -                      | -                  | -                ;  // 0x2730
    -                          | -          | -                      | -                  | -                ;  // 0x2740
    -                          | -          | -                      | -                  | -                ;  // 0x2750
    -                          | -          | -                      | -                  | -                ;  // 0x2760
    -                          | -          | -                      | -                  | -                ;  // 0x2770
    -                          | -          | -                      | -                  | -                ;  // 0x2780
    -                          | -          | -                      | -                  | -                ;  // 0x2790
    -                          | -          | -                      | -                  | -                ;  // 0x27A0
    -                          | -          | -                      | -                  | -                ;  // 0x27B0
    -                          | -          | -                      | -                  | -                ;  // 0x27C0
    -                          | -          | -                      | -                  | -                ;  // 0x27D0
    -                          | -          | -                      | -                  | -                ;  // 0x27E0
    -                          | -          | -                      | -                  | -                ;  // 0x27F0
    -                          | -          | -                      | -                  | -                ;  // 0x2800
    -                          | -          | -                      | -                  | -                ;  // 0x2810
    -                          | -          | -                      | -                  | -                ;  // 0x2820
    -                          | -          | -                      | -                  | -                ;  // 0x2830
    -                          | -          | -                      | -                  | -                ;  // 0x2840
    -                          | -          | -                      | -                  | -                ;  // 0x2850
    -                          | -          | -                      | -                  | -                ;  // 0x2860
    -                          | -          | -                      | -                  | -                ;  // 0x2870
    -                          | -          | -                      | -                  | -                ;  // 0x2880
    -                          | -          | -                      | -                  | -                ;  // 0x2890
    -                          | -          | -                      | -                  | -                ;  // 0x28A0
    -                          | -          | -                      | -                  | -                ;  // 0x28B0
    -                          | -          | -                      | -                  | -                ;  // 0x28C0
    -                          | -          | -                      | -                  | -                ;  // 0x28D0
    -                          | -          | -                      | -                  | -                ;  // 0x28E0
    -                          | -          | -                      | -                  | -                ;  // 0x28F0
    -                          | -          | -                      | -                  | -                ;  // 0x2900
    -                          | -          | -                      | -                  | -                ;  // 0x2910
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x2920
    -                          | -          | -                      | -                  | -                ;  // 0x2930
    addi r9, r9, #4            | -          | -                      | -                  | -                ;  // 0x2940
    addi r8, r7, #3            | -          | -                      | -                  | -                ;  // 0x2950
    -                          | -          | -                      | -                  | -                ;  // 0x2960
    -                          | -          | -                      | -                  | -                ;  // 0x2970
    srli r8, r8, #2            | -          | -                      | -                  | -                ;  // 0x2980
    -                          | -          | -                      | -                  | -                ;  // 0x2990
    -                          | -          | -                      | -                  | -                ;  // 0x29A0
__txt_bucle:
    cmpi r8, #0                | -          | -                      | -                  | -                ;  // 0x29B0
    -                          | -          | -                      | -                  | -                ;  // 0x29C0
    -                          | -          | -                      | -                  | -                ;  // 0x29D0
    -                          | -          | -                      | -                  | br.eq __txt_fin  ;  // 0x29E0
    -                          | -          | -                      | -                  | -                ;  // 0x29F0
    -                          | -          | lw r6, #0(r9)          | -                  | -                ;  // 0x2A00
    -                          | -          | -                      | -                  | -                ;  // 0x2A10
    -                          | -          | -                      | -                  | -                ;  // 0x2A20
    -                          | -          | -                      | -                  | jal.al __scribe_int ;  // 0x2A30
    -                          | -          | -                      | -                  | -                ;  // 0x2A40
    addi r9, r9, #4            | -          | -                      | -                  | -                ;  // 0x2A50
    subi r8, r8, #1            | -          | -                      | -                  | -                ;  // 0x2A60
    -                          | -          | -                      | -                  | -                ;  // 0x2A70
    -                          | -          | -                      | -                  | -                ;  // 0x2A80
    -                          | -          | -                      | -                  | br.al __txt_bucle ;  // 0x2A90
    -                          | -          | -                      | -                  | -                ;  // 0x2AA0
__txt_fin:
    -                          | -          | lw r15, #0(r14)        | -                  | -                ;  // 0x2AB0
    addi r14, r14, #4          | -          | -                      | -                  | -                ;  // 0x2AC0
    -                          | -          | -                      | -                  | -                ;  // 0x2AD0
    -                          | -          | -                      | -                  | -                ;  // 0x2AE0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x2AF0
    -                          | -          | -                      | -                  | -                ;  // 0x2B00
    // __dic_fin(): marca el fin de linea de 'dic' con 0x0A
__dic_fin:
    movi r6, #10               | -          | -                      | -                  | -                ;  // 0x2B10
    -                          | -          | -                      | -                  | -                ;  // 0x2B20
    -                          | -          | -                      | -                  | -                ;  // 0x2B30
    -                          | -          | -                      | -                  | -                ;  // 0x2B40
    -                          | -          | -                      | -                  | -                ;  // 0x2B50
    -                          | -          | -                      | -                  | -                ;  // 0x2B60
    -                          | -          | -                      | -                  | -                ;  // 0x2B70
    -                          | -          | -                      | -                  | -                ;  // 0x2B80
    -                          | -          | -                      | -                  | -                ;  // 0x2B90
    -                          | -          | -                      | -                  | -                ;  // 0x2BA0
    -                          | -          | -                      | -                  | -                ;  // 0x2BB0
    -                          | -          | -                      | -                  | -                ;  // 0x2BC0
    -                          | -          | -                      | -                  | -                ;  // 0x2BD0
    -                          | -          | -                      | -                  | -                ;  // 0x2BE0
    -                          | -          | -                      | -                  | -                ;  // 0x2BF0
    -                          | -          | -                      | -                  | -                ;  // 0x2C00
    -                          | -          | -                      | -                  | -                ;  // 0x2C10
    -                          | -          | -                      | -                  | -                ;  // 0x2C20
    -                          | -          | -                      | -                  | -                ;  // 0x2C30
    -                          | -          | -                      | -                  | -                ;  // 0x2C40
    -                          | -          | -                      | -                  | -                ;  // 0x2C50
    -                          | -          | -                      | -                  | -                ;  // 0x2C60
    -                          | -          | -                      | -                  | -                ;  // 0x2C70
    -                          | -          | -                      | -                  | -                ;  // 0x2C80
    -                          | -          | -                      | -                  | -                ;  // 0x2C90
    -                          | -          | -                      | -                  | -                ;  // 0x2CA0
    -                          | -          | -                      | -                  | -                ;  // 0x2CB0
    -                          | -          | -                      | -                  | -                ;  // 0x2CC0
    -                          | -          | -                      | -                  | -                ;  // 0x2CD0
    -                          | -          | -                      | -                  | -                ;  // 0x2CE0
    -                          | -          | -                      | -                  | -                ;  // 0x2CF0
    -                          | -          | -                      | -                  | -                ;  // 0x2D00
    -                          | -          | -                      | -                  | -                ;  // 0x2D10
    -                          | -          | -                      | -                  | -                ;  // 0x2D20
    -                          | -          | -                      | -                  | -                ;  // 0x2D30
    -                          | -          | -                      | -                  | -                ;  // 0x2D40
    -                          | -          | -                      | -                  | -                ;  // 0x2D50
    -                          | -          | -                      | -                  | -                ;  // 0x2D60
    -                          | -          | -                      | -                  | -                ;  // 0x2D70
    -                          | -          | -                      | -                  | -                ;  // 0x2D80
    -                          | -          | -                      | -                  | -                ;  // 0x2D90
    -                          | -          | -                      | -                  | -                ;  // 0x2DA0
    -                          | -          | -                      | -                  | -                ;  // 0x2DB0
    -                          | -          | -                      | -                  | -                ;  // 0x2DC0
    -                          | -          | -                      | -                  | -                ;  // 0x2DD0
    -                          | -          | -                      | -                  | -                ;  // 0x2DE0
    -                          | -          | -                      | -                  | -                ;  // 0x2DF0
    -                          | -          | -                      | -                  | -                ;  // 0x2E00
    -                          | -          | -                      | -                  | -                ;  // 0x2E10
    -                          | -          | -                      | -                  | -                ;  // 0x2E20
    -                          | -          | -                      | -                  | -                ;  // 0x2E30
    -                          | -          | -                      | -                  | -                ;  // 0x2E40
    -                          | -          | -                      | -                  | -                ;  // 0x2E50
    -                          | -          | -                      | -                  | -                ;  // 0x2E60
    -                          | -          | -                      | -                  | -                ;  // 0x2E70
    -                          | -          | -                      | -                  | -                ;  // 0x2E80
    -                          | -          | -                      | -                  | -                ;  // 0x2E90
    -                          | -          | -                      | -                  | -                ;  // 0x2EA0
    -                          | -          | -                      | -                  | -                ;  // 0x2EB0
    -                          | -          | -                      | -                  | -                ;  // 0x2EC0
    -                          | -          | -                      | -                  | -                ;  // 0x2ED0
    -                          | -          | -                      | -                  | -                ;  // 0x2EE0
    -                          | -          | -                      | -                  | -                ;  // 0x2EF0
    -                          | -          | -                      | -                  | -                ;  // 0x2F00
    -                          | -          | -                      | -                  | -                ;  // 0x2F10
    -                          | -          | -                      | -                  | -                ;  // 0x2F20
    -                          | -          | -                      | -                  | -                ;  // 0x2F30
    -                          | -          | -                      | -                  | -                ;  // 0x2F40
    -                          | -          | -                      | -                  | -                ;  // 0x2F50
    -                          | -          | -                      | -                  | -                ;  // 0x2F60
    -                          | -          | -                      | -                  | -                ;  // 0x2F70
    -                          | -          | -                      | -                  | -                ;  // 0x2F80
    -                          | -          | -                      | -                  | -                ;  // 0x2F90
    -                          | -          | -                      | -                  | -                ;  // 0x2FA0
    -                          | -          | -                      | -                  | -                ;  // 0x2FB0
    -                          | -          | -                      | -                  | -                ;  // 0x2FC0
    -                          | -          | -                      | -                  | -                ;  // 0x2FD0
    -                          | -          | -                      | -                  | -                ;  // 0x2FE0
    -                          | -          | -                      | -                  | -                ;  // 0x2FF0
    -                          | -          | -                      | -                  | -                ;  // 0x3000
    -                          | -          | -                      | -                  | -                ;  // 0x3010
    -                          | -          | -                      | -                  | -                ;  // 0x3020
    -                          | -          | -                      | -                  | -                ;  // 0x3030
    -                          | -          | -                      | -                  | -                ;  // 0x3040
    -                          | -          | -                      | -                  | -                ;  // 0x3050
    -                          | -          | -                      | -                  | -                ;  // 0x3060
    -                          | -          | -                      | -                  | -                ;  // 0x3070
    -                          | -          | -                      | -                  | -                ;  // 0x3080
    -                          | -          | -                      | -                  | -                ;  // 0x3090
    -                          | -          | -                      | -                  | -                ;  // 0x30A0
    -                          | -          | -                      | -                  | -                ;  // 0x30B0
    -                          | -          | -                      | -                  | -                ;  // 0x30C0
    -                          | -          | -                      | -                  | -                ;  // 0x30D0
    -                          | -          | -                      | -                  | -                ;  // 0x30E0
    -                          | -          | -                      | -                  | -                ;  // 0x30F0
    -                          | -          | -                      | -                  | -                ;  // 0x3100
    -                          | -          | -                      | -                  | -                ;  // 0x3110
    -                          | -          | -                      | -                  | -                ;  // 0x3120
    -                          | -          | -                      | -                  | -                ;  // 0x3130
    -                          | -          | -                      | -                  | -                ;  // 0x3140
    -                          | -          | -                      | -                  | -                ;  // 0x3150
    -                          | -          | -                      | -                  | -                ;  // 0x3160
    -                          | -          | -                      | -                  | -                ;  // 0x3170
    -                          | -          | -                      | -                  | -                ;  // 0x3180
    -                          | -          | -                      | -                  | -                ;  // 0x3190
    -                          | -          | -                      | -                  | -                ;  // 0x31A0
    -                          | -          | -                      | -                  | -                ;  // 0x31B0
    -                          | -          | -                      | -                  | -                ;  // 0x31C0
    -                          | -          | -                      | -                  | -                ;  // 0x31D0
    -                          | -          | -                      | -                  | -                ;  // 0x31E0
    -                          | -          | -                      | -                  | -                ;  // 0x31F0
    -                          | -          | -                      | -                  | -                ;  // 0x3200
    -                          | -          | -                      | -                  | -                ;  // 0x3210
    -                          | -          | -                      | -                  | -                ;  // 0x3220
    -                          | -          | -                      | -                  | -                ;  // 0x3230
    -                          | -          | -                      | -                  | -                ;  // 0x3240
    -                          | -          | -                      | -                  | -                ;  // 0x3250
    -                          | -          | -                      | -                  | -                ;  // 0x3260
    -                          | -          | -                      | -                  | -                ;  // 0x3270
    -                          | -          | -                      | -                  | -                ;  // 0x3280
    -                          | -          | -                      | -                  | -                ;  // 0x3290
    -                          | -          | -                      | -                  | -                ;  // 0x32A0
    -                          | -          | -                      | -                  | -                ;  // 0x32B0
    -                          | -          | -                      | -                  | -                ;  // 0x32C0
    -                          | -          | -                      | -                  | -                ;  // 0x32D0
    -                          | -          | -                      | -                  | -                ;  // 0x32E0
    -                          | -          | -                      | -                  | -                ;  // 0x32F0
    -                          | -          | -                      | -                  | -                ;  // 0x3300
    -                          | -          | -                      | -                  | -                ;  // 0x3310
    -                          | -          | -                      | -                  | -                ;  // 0x3320
    -                          | -          | -                      | -                  | -                ;  // 0x3330
    -                          | -          | -                      | -                  | -                ;  // 0x3340
    -                          | -          | -                      | -                  | -                ;  // 0x3350
    -                          | -          | -                      | -                  | -                ;  // 0x3360
    -                          | -          | -                      | -                  | -                ;  // 0x3370
    -                          | -          | -                      | -                  | -                ;  // 0x3380
    -                          | -          | -                      | -                  | -                ;  // 0x3390
    -                          | -          | -                      | -                  | -                ;  // 0x33A0
    -                          | -          | -                      | -                  | -                ;  // 0x33B0
    -                          | -          | -                      | -                  | br.al __scribe_int ;  // 0x33C0
    -                          | -          | -                      | -                  | -                ;  // 0x33D0

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __str0                       0x2000     DMEM (datos)
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   limitar                      0x0000     IMEM bundle 0
//   __limitar_cuerpo             0x0060     IMEM bundle 6
//   __c0_si                      0x0140     IMEM bundle 20
//   __c0_fin                     0x0170     IMEM bundle 23
//   L0                           0x0250     IMEM bundle 37
//   __c1_si                      0x0330     IMEM bundle 51
//   __c1_fin                     0x0360     IMEM bundle 54
//   L2                           0x0440     IMEM bundle 68
//   L3                           0x04A0     IMEM bundle 74
//   L1                           0x04A0     IMEM bundle 74
//   imprimir                     0x04F0     IMEM bundle 79
//   __imprimir_cuerpo            0x0560     IMEM bundle 86
//   L4                           0x05B0     IMEM bundle 91
//   __c2_si                      0x06D0     IMEM bundle 109
//   __c2_fin                     0x0700     IMEM bundle 112
//   L7                           0x07B0     IMEM bundle 123
//   __c3_si                      0x08D0     IMEM bundle 141
//   __c3_fin                     0x0900     IMEM bundle 144
//   __rango0_ok                  0x0A80     IMEM bundle 168
//   __rango1_ok                  0x0BA0     IMEM bundle 186
//   L8                           0x0D90     IMEM bundle 217
//   L9                           0x0E80     IMEM bundle 232
//   L5                           0x0F30     IMEM bundle 243
//   L6                           0x1020     IMEM bundle 258
//   es_impar                     0x1080     IMEM bundle 264
//   __es_impar_cuerpo            0x10D0     IMEM bundle 269
//   __c4_si                      0x12A0     IMEM bundle 298
//   __c4_fin                     0x12D0     IMEM bundle 301
//   __nova_div32                 0x1350     IMEM bundle 309
//   __dv_ok                      0x13F0     IMEM bundle 319
//   __dv_a_pos                   0x1530     IMEM bundle 339
//   __dv_b_pos                   0x1630     IMEM bundle 355
//   __dv_bucle                   0x1680     IMEM bundle 360
//   __dv_sigue                   0x1810     IMEM bundle 385
//   __dv_c_pos                   0x1990     IMEM bundle 409
//   __dv_r_pos                   0x1A70     IMEM bundle 423
//   __scribe_int                 0x1AC0     IMEM bundle 428
//   __scribe_txt                 0x2200     IMEM bundle 544
//   __txt_bucle                  0x29B0     IMEM bundle 667
//   __txt_fin                    0x2AB0     IMEM bundle 683
//   __dic_fin                    0x2B10     IMEM bundle 689
//   41 etiquetas de codigo, 3 de datos

// fin del programa
