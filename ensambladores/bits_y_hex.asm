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
    // functio rotar
rotar:
    // marco de 20 bytes
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x00A0
    -                          | -          | sw r7, #0(r14)         | -                  | -                ;  // 0x00B0
__rotar_cuerpo:
    // Nova fuente: linea 7, columna 12
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x00C0
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x00D0
    -                          | -          | -                      | -                  | -                ;  // 0x00E0
    -                          | -          | -                      | -                  | -                ;  // 0x00F0
    sll r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0100
    -                          | -          | -                      | -                  | -                ;  // 0x0110
    -                          | -          | -                      | -                  | -                ;  // 0x0120
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0130
    // Nova fuente: linea 7, columna 30
    movi r10, #32              | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | -                      | -                  | -                ;  // 0x0150
    -                          | -          | -                      | -                  | -                ;  // 0x0160
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0170
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x0180
    -                          | -          | -                      | -                  | -                ;  // 0x0190
    -                          | -          | -                      | -                  | -                ;  // 0x01A0
    sub r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | -                      | -                  | -                ;  // 0x01C0
    -                          | -          | -                      | -                  | -                ;  // 0x01D0
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x01E0
    // Nova fuente: linea 7, columna 23
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x01F0
    -                          | -          | lw r11, #16(r14)       | -                  | -                ;  // 0x0200
    -                          | -          | -                      | -                  | -                ;  // 0x0210
    -                          | -          | -                      | -                  | -                ;  // 0x0220
    srl r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0230
    -                          | -          | -                      | -                  | -                ;  // 0x0240
    -                          | -          | -                      | -                  | -                ;  // 0x0250
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0260
    // Nova fuente: linea 7, columna 11
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0270
    -                          | -          | lw r11, #12(r14)       | -                  | -                ;  // 0x0280
    -                          | -          | -                      | -                  | -                ;  // 0x0290
    -                          | -          | -                      | -                  | -                ;  // 0x02A0
    or r10, r10, r11           | -          | -                      | -                  | -                ;  // 0x02B0
    -                          | -          | -                      | -                  | -                ;  // 0x02C0
    -                          | -          | -                      | -                  | -                ;  // 0x02D0
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x02E0
    // Nova fuente: linea 7, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x02F0
    addi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x0300
    -                          | -          | -                      | -                  | -                ;  // 0x0310
    -                          | -          | -                      | -                  | -                ;  // 0x0320
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x0330
    -                          | -          | -                      | -                  | -                ;  // 0x0340
    // functio es_par
es_par:
    // marco de 16 bytes
    subi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x0350
    -                          | -          | -                      | -                  | -                ;  // 0x0360
    -                          | -          | -                      | -                  | -                ;  // 0x0370
    -                          | -          | sw r6, #0(r14)         | -                  | -                ;  // 0x0380
__es_par_cuerpo:
    // Nova fuente: linea 11, columna 16
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0390
    -                          | -          | -                      | -                  | -                ;  // 0x03A0
    -                          | -          | -                      | -                  | -                ;  // 0x03B0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x03C0
    // Nova fuente: linea 11, columna 12
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x03D0
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x03E0
    -                          | -          | -                      | -                  | -                ;  // 0x03F0
    -                          | -          | -                      | -                  | -                ;  // 0x0400
    and r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0410
    -                          | -          | -                      | -                  | -                ;  // 0x0420
    -                          | -          | -                      | -                  | -                ;  // 0x0430
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0440
    // Nova fuente: linea 11, columna 22
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0450
    -                          | -          | -                      | -                  | -                ;  // 0x0460
    -                          | -          | -                      | -                  | -                ;  // 0x0470
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0480
    // Nova fuente: linea 11, columna 11
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x0490
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x04A0
    -                          | -          | -                      | -                  | -                ;  // 0x04B0
    -                          | -          | -                      | -                  | -                ;  // 0x04C0
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x04D0
    -                          | -          | -                      | -                  | -                ;  // 0x04E0
    -                          | -          | -                      | -                  | -                ;  // 0x04F0
    -                          | -          | -                      | -                  | br.eq __c0_si    ;  // 0x0500
    -                          | -          | -                      | -                  | -                ;  // 0x0510
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0520
    -                          | -          | -                      | -                  | -                ;  // 0x0530
    -                          | -          | -                      | -                  | -                ;  // 0x0540
    -                          | -          | -                      | -                  | br.al __c0_fin   ;  // 0x0550
    -                          | -          | -                      | -                  | -                ;  // 0x0560
__c0_si:
    // Nova fuente: linea 11, columna 11
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0570
    -                          | -          | -                      | -                  | -                ;  // 0x0580
    -                          | -          | -                      | -                  | -                ;  // 0x0590
__c0_fin:
    // Nova fuente: linea 11, columna 11
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x05A0
    // Nova fuente: linea 11, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x05B0
    addi r14, r14, #16         | -          | -                      | -                  | -                ;  // 0x05C0
    -                          | -          | -                      | -                  | -                ;  // 0x05D0
    -                          | -          | -                      | -                  | -                ;  // 0x05E0
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x05F0
    -                          | -          | -                      | -                  | -                ;  // 0x0600
    // functio mezclar
mezclar:
    // marco de 24 bytes
    subi r14, r14, #24         | -          | -                      | -                  | -                ;  // 0x0610
    -                          | -          | -                      | -                  | -                ;  // 0x0620
    -                          | -          | -                      | -                  | -                ;  // 0x0630
    -                          | -          | sw r6, #8(r14)         | -                  | -                ;  // 0x0640
    -                          | -          | sw r7, #4(r14)         | -                  | -                ;  // 0x0650
    -                          | -          | sw r8, #0(r14)         | -                  | -                ;  // 0x0660
__mezclar_cuerpo:
    // Nova fuente: linea 15, columna 17
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0670
    -                          | -          | lw r11, #0(r14)        | -                  | -                ;  // 0x0680
    -                          | -          | -                      | -                  | -                ;  // 0x0690
    -                          | -          | -                      | -                  | -                ;  // 0x06A0
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x06B0
    -                          | -          | -                      | -                  | -                ;  // 0x06C0
    -                          | -          | -                      | -                  | -                ;  // 0x06D0
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x06E0
    // Nova fuente: linea 15, columna 26
    movi r10, #48879           | -          | -                      | -                  | -                ;  // 0x06F0
    -                          | -          | -                      | -                  | -                ;  // 0x0700
    -                          | -          | -                      | -                  | -                ;  // 0x0710
    movh r10, #57005           | -          | -                      | -                  | -                ;  // 0x0720
    -                          | -          | -                      | -                  | -                ;  // 0x0730
    -                          | -          | -                      | -                  | -                ;  // 0x0740
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x0750
    // Nova fuente: linea 15, columna 16
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x0760
    -                          | -          | lw r11, #16(r14)       | -                  | -                ;  // 0x0770
    -                          | -          | -                      | -                  | -                ;  // 0x0780
    -                          | -          | -                      | -                  | -                ;  // 0x0790
    and r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x07A0
    -                          | -          | -                      | -                  | -                ;  // 0x07B0
    -                          | -          | -                      | -                  | -                ;  // 0x07C0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x07D0
    // Nova fuente: linea 15, columna 11
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x07E0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x07F0
    -                          | -          | -                      | -                  | -                ;  // 0x0800
    -                          | -          | -                      | -                  | -                ;  // 0x0810
    xor r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0820
    -                          | -          | -                      | -                  | -                ;  // 0x0830
    -                          | -          | -                      | -                  | -                ;  // 0x0840
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0850
    // Nova fuente: linea 15, columna 38
    movi r10, #15              | -          | -                      | -                  | -                ;  // 0x0860
    -                          | -          | -                      | -                  | -                ;  // 0x0870
    -                          | -          | -                      | -                  | -                ;  // 0x0880
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x0890
    // Nova fuente: linea 15, columna 37
    not r10, r10               | -          | -                      | -                  | -                ;  // 0x08A0
    -                          | -          | -                      | -                  | -                ;  // 0x08B0
    -                          | -          | -                      | -                  | -                ;  // 0x08C0
    -                          | -          | sw r10, #20(r14)       | -                  | -                ;  // 0x08D0
    // Nova fuente: linea 15, columna 11
    -                          | -          | lw r10, #12(r14)       | -                  | -                ;  // 0x08E0
    -                          | -          | lw r11, #20(r14)       | -                  | -                ;  // 0x08F0
    -                          | -          | -                      | -                  | -                ;  // 0x0900
    -                          | -          | -                      | -                  | -                ;  // 0x0910
    xor r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0920
    -                          | -          | -                      | -                  | -                ;  // 0x0930
    -                          | -          | -                      | -                  | -                ;  // 0x0940
    -                          | -          | sw r10, #16(r14)       | -                  | -                ;  // 0x0950
    // Nova fuente: linea 15, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0960
    addi r14, r14, #24         | -          | -                      | -                  | -                ;  // 0x0970
    -                          | -          | -                      | -                  | -                ;  // 0x0980
    -                          | -          | -                      | -                  | -                ;  // 0x0990
    -                          | -          | -                      | -                  | jr.al r15        ;  // 0x09A0
    -                          | -          | -                      | -                  | -                ;  // 0x09B0
    // functio principale
principale:
    // marco de 20 bytes, guarda R15 en #16(r14)
    subi r14, r14, #20         | -          | -                      | -                  | -                ;  // 0x09C0
    -                          | -          | -                      | -                  | -                ;  // 0x09D0
    -                          | -          | -                      | -                  | -                ;  // 0x09E0
    -                          | -          | sw r15, #16(r14)       | -                  | -                ;  // 0x09F0
__principale_cuerpo:
    // Nova fuente: linea 19, columna 25
    movi r10, #255             | -          | -                      | -                  | -                ;  // 0x0A00
    -                          | -          | -                      | -                  | -                ;  // 0x0A10
    -                          | -          | -                      | -                  | -                ;  // 0x0A20
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0A30
    // Nova fuente: linea 19, columna 11
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0A40
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0A50
    // Nova fuente: linea 20, columna 18
    movi r10, #8               | -          | -                      | -                  | -                ;  // 0x0A60
    -                          | -          | -                      | -                  | -                ;  // 0x0A70
    -                          | -          | -                      | -                  | -                ;  // 0x0A80
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0A90
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x0AA0
    // Nova fuente: linea 20, columna 9
    -                          | -          | -                      | -                  | -                ;  // 0x0AB0
    -                          | -          | -                      | -                  | -                ;  // 0x0AC0
    -                          | -          | -                      | -                  | jal.al rotar     ;  // 0x0AD0
    -                          | -          | -                      | -                  | -                ;  // 0x0AE0
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x0AF0
    // Nova fuente: linea 20, columna 23
    movi r10, #165             | -          | -                      | -                  | -                ;  // 0x0B00
    -                          | -          | -                      | -                  | -                ;  // 0x0B10
    -                          | -          | -                      | -                  | -                ;  // 0x0B20
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0B30
    // Nova fuente: linea 20, columna 9
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0B40
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0B50
    -                          | -          | -                      | -                  | -                ;  // 0x0B60
    -                          | -          | -                      | -                  | -                ;  // 0x0B70
    xor r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0B80
    -                          | -          | -                      | -                  | -                ;  // 0x0B90
    -                          | -          | -                      | -                  | -                ;  // 0x0BA0
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0BB0
    // Nova fuente: linea 20, columna 5
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x0BC0
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x0BD0
    // Nova fuente: linea 21, columna 13
    -                          | -          | -                      | -                  | -                ;  // 0x0BE0
    -                          | -          | -                      | -                  | -                ;  // 0x0BF0
    -                          | -          | -                      | -                  | jal.al es_par    ;  // 0x0C00
    -                          | -          | -                      | -                  | -                ;  // 0x0C10
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x0C20
    // Nova fuente: linea 21, columna 9
    mov r10, r6                | -          | -                      | -                  | -                ;  // 0x0C30
    -                          | -          | -                      | -                  | -                ;  // 0x0C40
    -                          | -          | -                      | -                  | -                ;  // 0x0C50
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0C60
    -                          | -          | -                      | -                  | -                ;  // 0x0C70
    -                          | -          | -                      | -                  | -                ;  // 0x0C80
    -                          | -          | -                      | -                  | br.eq __n0_si    ;  // 0x0C90
    -                          | -          | -                      | -                  | -                ;  // 0x0CA0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0CB0
    -                          | -          | -                      | -                  | -                ;  // 0x0CC0
    -                          | -          | -                      | -                  | -                ;  // 0x0CD0
    -                          | -          | -                      | -                  | br.al __n0_fin   ;  // 0x0CE0
    -                          | -          | -                      | -                  | -                ;  // 0x0CF0
__n0_si:
    // Nova fuente: linea 21, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0D00
    -                          | -          | -                      | -                  | -                ;  // 0x0D10
    -                          | -          | -                      | -                  | -                ;  // 0x0D20
__n0_fin:
    // Nova fuente: linea 21, columna 9
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0D30
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0D40
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0D50
    -                          | -          | -                      | -                  | -                ;  // 0x0D60
    -                          | -          | -                      | -                  | -                ;  // 0x0D70
    -                          | -          | -                      | -                  | br.eq L2         ;  // 0x0D80
    -                          | -          | -                      | -                  | -                ;  // 0x0D90
    // Nova fuente: linea 21, columna 31
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0DA0
    -                          | -          | -                      | -                  | -                ;  // 0x0DB0
    -                          | -          | -                      | -                  | -                ;  // 0x0DC0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0DD0
    // Nova fuente: linea 21, columna 26
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x0DE0
    -                          | -          | lw r11, #8(r14)        | -                  | -                ;  // 0x0DF0
    -                          | -          | -                      | -                  | -                ;  // 0x0E00
    -                          | -          | -                      | -                  | -                ;  // 0x0E10
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x0E20
    -                          | -          | -                      | -                  | -                ;  // 0x0E30
    -                          | -          | -                      | -                  | -                ;  // 0x0E40
    -                          | -          | -                      | -                  | br.ge __c1_si    ;  // 0x0E50
    -                          | -          | -                      | -                  | -                ;  // 0x0E60
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0E70
    -                          | -          | -                      | -                  | -                ;  // 0x0E80
    -                          | -          | -                      | -                  | -                ;  // 0x0E90
    -                          | -          | -                      | -                  | br.al __c1_fin   ;  // 0x0EA0
    -                          | -          | -                      | -                  | -                ;  // 0x0EB0
__c1_si:
    // Nova fuente: linea 21, columna 26
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x0EC0
    -                          | -          | -                      | -                  | -                ;  // 0x0ED0
    -                          | -          | -                      | -                  | -                ;  // 0x0EE0
__c1_fin:
    // Nova fuente: linea 21, columna 26
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x0EF0
    // Nova fuente: linea 21, columna 9
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0F00
    -                          | -          | -                      | -                  | br.al L3         ;  // 0x0F10
    -                          | -          | -                      | -                  | -                ;  // 0x0F20
L2:
    // Nova fuente: linea 21, columna 9
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x0F30
    -                          | -          | -                      | -                  | -                ;  // 0x0F40
    -                          | -          | -                      | -                  | -                ;  // 0x0F50
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0F60
L3:
    // Nova fuente: linea 21, columna 9
    -                          | -          | lw r10, #4(r14)        | -                  | -                ;  // 0x0F70
    -                          | -          | -                      | -                  | -                ;  // 0x0F80
    -                          | -          | -                      | -                  | -                ;  // 0x0F90
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0FA0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x0FB0
    -                          | -          | -                      | -                  | -                ;  // 0x0FC0
    -                          | -          | -                      | -                  | -                ;  // 0x0FD0
    -                          | -          | -                      | -                  | br.ne L0         ;  // 0x0FE0
    -                          | -          | -                      | -                  | -                ;  // 0x0FF0
    // Nova fuente: linea 21, columna 42
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x1000
    -                          | -          | -                      | -                  | -                ;  // 0x1010
    -                          | -          | -                      | -                  | -                ;  // 0x1020
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x1030
    // Nova fuente: linea 21, columna 37
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x1040
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x1050
    -                          | -          | -                      | -                  | -                ;  // 0x1060
    -                          | -          | -                      | -                  | -                ;  // 0x1070
    cmp r10, r11               | -          | -                      | -                  | -                ;  // 0x1080
    -                          | -          | -                      | -                  | -                ;  // 0x1090
    -                          | -          | -                      | -                  | -                ;  // 0x10A0
    -                          | -          | -                      | -                  | br.ne __c2_si    ;  // 0x10B0
    -                          | -          | -                      | -                  | -                ;  // 0x10C0
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x10D0
    -                          | -          | -                      | -                  | -                ;  // 0x10E0
    -                          | -          | -                      | -                  | -                ;  // 0x10F0
    -                          | -          | -                      | -                  | br.al __c2_fin   ;  // 0x1100
    -                          | -          | -                      | -                  | -                ;  // 0x1110
__c2_si:
    // Nova fuente: linea 21, columna 37
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1120
    -                          | -          | -                      | -                  | -                ;  // 0x1130
    -                          | -          | -                      | -                  | -                ;  // 0x1140
__c2_fin:
    // Nova fuente: linea 21, columna 37
    -                          | -          | sw r10, #12(r14)       | -                  | -                ;  // 0x1150
    // Nova fuente: linea 21, columna 9
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x1160
    -                          | -          | -                      | -                  | br.al L1         ;  // 0x1170
    -                          | -          | -                      | -                  | -                ;  // 0x1180
L0:
    // Nova fuente: linea 21, columna 9
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1190
    -                          | -          | -                      | -                  | -                ;  // 0x11A0
    -                          | -          | -                      | -                  | -                ;  // 0x11B0
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x11C0
L1:
    // Nova fuente: linea 21, columna 5
    -                          | -          | lw r10, #8(r14)        | -                  | -                ;  // 0x11D0
    -                          | -          | -                      | -                  | -                ;  // 0x11E0
    -                          | -          | -                      | -                  | -                ;  // 0x11F0
    cmpi r10, #0               | -          | -                      | -                  | -                ;  // 0x1200
    -                          | -          | -                      | -                  | -                ;  // 0x1210
    -                          | -          | -                      | -                  | -                ;  // 0x1220
    -                          | -          | -                      | -                  | br.eq L4         ;  // 0x1230
    -                          | -          | -                      | -                  | -                ;  // 0x1240
    -                          | -          | lw r6, #0(r14)         | -                  | -                ;  // 0x1250
    // Nova fuente: linea 22, columna 26
    movi r10, #1               | -          | -                      | -                  | -                ;  // 0x1260
    -                          | -          | -                      | -                  | -                ;  // 0x1270
    -                          | -          | -                      | -                  | -                ;  // 0x1280
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x1290
    mov r7, r10                | -          | -                      | -                  | -                ;  // 0x12A0
    // Nova fuente: linea 22, columna 29
    movi r10, #31              | -          | -                      | -                  | -                ;  // 0x12B0
    -                          | -          | -                      | -                  | -                ;  // 0x12C0
    -                          | -          | -                      | -                  | -                ;  // 0x12D0
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x12E0
    mov r8, r10                | -          | -                      | -                  | -                ;  // 0x12F0
    // Nova fuente: linea 22, columna 15
    -                          | -          | -                      | -                  | -                ;  // 0x1300
    -                          | -          | -                      | -                  | -                ;  // 0x1310
    -                          | -          | -                      | -                  | jal.al mezclar   ;  // 0x1320
    -                          | -          | -                      | -                  | -                ;  // 0x1330
    -                          | -          | sw r6, #4(r14)         | -                  | -                ;  // 0x1340
    // Nova fuente: linea 22, columna 9
    -                          | -          | -                      | -                  | halt             ;  // 0x1350
    -                          | -          | -                      | -                  | -                ;  // 0x1360
L4:
    // Nova fuente: linea 24, columna 11
    movi r10, #0               | -          | -                      | -                  | -                ;  // 0x1370
    -                          | -          | -                      | -                  | -                ;  // 0x1380
    -                          | -          | -                      | -                  | -                ;  // 0x1390
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x13A0
    // Nova fuente: linea 24, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x13B0
    -                          | -          | -                      | -                  | -                ;  // 0x13C0
    -                          | -          | -                      | -                  | -                ;  // 0x13D0
    -                          | -          | -                      | -                  | halt             ;  // 0x13E0
    -                          | -          | -                      | -                  | -                ;  // 0x13F0

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   rotar                        0x0070     IMEM bundle 7
//   __rotar_cuerpo               0x00C0     IMEM bundle 12
//   es_par                       0x0350     IMEM bundle 53
//   __es_par_cuerpo              0x0390     IMEM bundle 57
//   __c0_si                      0x0570     IMEM bundle 87
//   __c0_fin                     0x05A0     IMEM bundle 90
//   mezclar                      0x0610     IMEM bundle 97
//   __mezclar_cuerpo             0x0670     IMEM bundle 103
//   principale                   0x09C0     IMEM bundle 156
//   __principale_cuerpo          0x0A00     IMEM bundle 160
//   __n0_si                      0x0D00     IMEM bundle 208
//   __n0_fin                     0x0D30     IMEM bundle 211
//   __c1_si                      0x0EC0     IMEM bundle 236
//   __c1_fin                     0x0EF0     IMEM bundle 239
//   L2                           0x0F30     IMEM bundle 243
//   L3                           0x0F70     IMEM bundle 247
//   __c2_si                      0x1120     IMEM bundle 274
//   __c2_fin                     0x1150     IMEM bundle 277
//   L0                           0x1190     IMEM bundle 281
//   L1                           0x11D0     IMEM bundle 285
//   L4                           0x1370     IMEM bundle 311
//   22 etiquetas de codigo, 2 de datos

// fin del programa
