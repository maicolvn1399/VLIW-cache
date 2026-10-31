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
    // marco de 12 bytes
    subi r14, r14, #12         | -          | -                      | -                  | -                ;  // 0x0070
    -                          | -          | -                      | -                  | -                ;  // 0x0080
    -                          | -          | -                      | -                  | -                ;  // 0x0090
__principale_cuerpo:
    // Nova fuente: linea 2, columna 11
    movi r10, #10              | -          | -                      | -                  | -                ;  // 0x00A0
    -                          | -          | -                      | -                  | -                ;  // 0x00B0
    -                          | -          | -                      | -                  | -                ;  // 0x00C0
    -                          | -          | sw r10, #0(r14)        | -                  | -                ;  // 0x00D0
    // Nova fuente: linea 2, columna 16
    movi r10, #15              | -          | -                      | -                  | -                ;  // 0x00E0
    -                          | -          | -                      | -                  | -                ;  // 0x00F0
    -                          | -          | -                      | -                  | -                ;  // 0x0100
    -                          | -          | sw r10, #4(r14)        | -                  | -                ;  // 0x0110
    // Nova fuente: linea 2, columna 11
    -                          | -          | lw r10, #0(r14)        | -                  | -                ;  // 0x0120
    -                          | -          | lw r11, #4(r14)        | -                  | -                ;  // 0x0130
    -                          | -          | -                      | -                  | -                ;  // 0x0140
    -                          | -          | -                      | -                  | -                ;  // 0x0150
    add r10, r10, r11          | -          | -                      | -                  | -                ;  // 0x0160
    -                          | -          | -                      | -                  | -                ;  // 0x0170
    -                          | -          | -                      | -                  | -                ;  // 0x0180
    -                          | -          | sw r10, #8(r14)        | -                  | -                ;  // 0x0190
    // Nova fuente: linea 2, columna 5
    mov r6, r10                | -          | -                      | -                  | -                ;  // 0x01A0
    -                          | -          | -                      | -                  | -                ;  // 0x01B0
    -                          | -          | -                      | -                  | -                ;  // 0x01C0
    -                          | -          | -                      | -                  | halt             ;  // 0x01D0
    -                          | -          | -                      | -                  | -                ;  // 0x01E0

// =====================================================
// Tabla de simbolos: etiquetas y direcciones resueltas
// =====================================================
//   ETIQUETA                     DIRECCION  UBICACION
//   __out_n                      0x3000     DMEM (datos)
//   __out_buf                    0x3004     DMEM (datos)
//   __inicio                     0x0000     IMEM bundle 0
//   principale                   0x0070     IMEM bundle 7
//   __principale_cuerpo          0x00A0     IMEM bundle 10
//   3 etiquetas de codigo, 2 de datos

// fin del programa
