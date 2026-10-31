//==============================================================================
// cerbero_defs.svh
// CERBERO-1 - Definiciones compartidas del ISA
//
// Unica fuente de verdad para anchos, posiciones de campo, opcodes, codigos de
// condicion y causas de falla. Todo modulo y todo testbench que necesite uno
// de esos numeros lo toma de aqui: si manana se renumera un opcode se cambia
// en una sola linea y el RTL y las pruebas quedan sincronizados.
//
// Los modulos pueden seguir declarando localparam con nombres locales, pero
// derivados de estas macros y no escritos a mano:
//
//     localparam logic [2:0] OP_F4D = `CRP_F4D;
//
// Se usan macros `define en lugar de un package de SystemVerilog porque el
// soporte de packages en Icarus Verilog es parcial segun la version. Las
// macros funcionan de forma identica en iverilog -g2012 y en Verilator.
//==============================================================================
`ifndef CERBERO_DEFS_SVH
`define CERBERO_DEFS_SVH

//------------------------------------------------------------------------------
// Anchos generales
//------------------------------------------------------------------------------
`define XLEN      32   // Ancho de registro y de dato
`define NREGS     16   // Cantidad de registros de proposito general
`define RIDX_W     4   // Ancho del campo de registro
`define BUNDLE_W 128   // Ancho del bundle
`define NSLOTS     5   // Cantidad de slots por bundle

// Registro de enlace, escrito implicitamente por JAL y JALR
`define REG_LINK  4'd15

//------------------------------------------------------------------------------
// Rangos de bits del bundle de 128 bits
//------------------------------------------------------------------------------
`define SLOT_S0 127:96   // ALU-0
`define SLOT_S1  95:64   // ALU-1
`define SLOT_S2  63:32   // LSU
`define SLOT_S3  31:16   // Criptografica / boveda / ALU corta
`define SLOT_S4  15:0    // BRU

//==============================================================================
// SLOTS DE 32 BITS  (S0, S1, S2)
//==============================================================================

//------------------------------------------------------------------------------
// Campos del slot de 32 bits (tipos A, I, U, M)
//------------------------------------------------------------------------------
`define F_OPC    31:27   // Opcode de 5 bits
`define F_RD     26:23   // Registro destino, o rs_dato en un store
`define F_RS1    22:19   // Primer operando fuente, o rbase en el tipo M
`define F_RS2    18:15   // Segundo operando fuente (tipo A)
`define F_RSVA   14:0    // Reservado del tipo A, debe valer cero
`define F_IMM19  18:0    // Inmediato con signo (tipos I y M)
`define F_IMM16  18:3    // Inmediato de 16 bits (tipo U)
`define F_COND   2:0     // Codigo de condicion (tipo U, SETcc)

//------------------------------------------------------------------------------
// Opcodes del slot ALU (S0 y S1)
// El bit 4 selecciona la forma del segundo operando:
//   0 = registro, 1 = inmediato.
// Excepciones documentadas: NEG, SETCC, MFPSW y MOVH.
//------------------------------------------------------------------------------
`define ALU_NOP   5'b00000
`define ALU_ADD   5'b00001
`define ALU_SUB   5'b00010
`define ALU_MUL   5'b00011
`define ALU_AND   5'b00100
`define ALU_OR    5'b00101
`define ALU_XOR   5'b00110
`define ALU_SLL   5'b00111
`define ALU_SRL   5'b01000
`define ALU_SRA   5'b01001
`define ALU_ROL   5'b01010
`define ALU_ROR   5'b01011
`define ALU_MOV   5'b01100
`define ALU_NOT   5'b01101
`define ALU_CMP   5'b01110   // solo S0
`define ALU_TEST  5'b01111   // solo S0
`define ALU_NEG   5'b10000
`define ALU_ADDI  5'b10001
`define ALU_SUBI  5'b10010
`define ALU_SETCC 5'b10011
`define ALU_ANDI  5'b10100
`define ALU_ORI   5'b10101
`define ALU_XORI  5'b10110
`define ALU_SLLI  5'b10111
`define ALU_SRLI  5'b11000
`define ALU_SRAI  5'b11001
`define ALU_ROLI  5'b11010
`define ALU_MFPSW 5'b11011
`define ALU_MOVI  5'b11100
`define ALU_MOVH  5'b11101
`define ALU_CMPI  5'b11110   // solo S0
`define ALU_TESTI 5'b11111   // solo S0

//------------------------------------------------------------------------------
// Opcodes del slot LSU (S2), tipo M
//
// El opcode esta estructurado por campos, de modo que la unidad decide que
// hacer mirando bits individuales en vez de decodificar el valor completo:
//
//   opcode[4] = INC   1 = escribe de vuelta el registro base
//   opcode[3] = ST    0 = load, 1 = store
//   opcode[2:1] = TAM 01 = byte, 10 = media palabra, 11 = palabra
//   opcode[0] = U     1 = extension con ceros (solo loads)
//
// Las combinaciones con TAM = 00, las de store con U = 1 y las variantes .INC
// no listadas quedan reservadas y producen ILLOP.
//------------------------------------------------------------------------------
`define LSU_NOP     5'b00000
`define LSU_LB      5'b00010
`define LSU_LBU     5'b00011
`define LSU_LH      5'b00100
`define LSU_LHU     5'b00101
`define LSU_LW      5'b00110
`define LSU_SB      5'b01010
`define LSU_SH      5'b01100
`define LSU_SW      5'b01110
`define LSU_LW_INC  5'b10110
`define LSU_SW_INC  5'b11110

// Subcampos del opcode de S2
`define LSU_BIT_INC  4
`define LSU_BIT_ST   3
`define LSU_FLD_TAM  2:1
`define LSU_BIT_U    0

// Codificacion del campo de tamano
`define LSU_TAM_RSV  2'b00
`define LSU_TAM_B    2'b01
`define LSU_TAM_H    2'b10
`define LSU_TAM_W    2'b11

//==============================================================================
// SLOT S3  (16 bits): criptografia, boveda y ALU corta
//==============================================================================

//------------------------------------------------------------------------------
// Opcodes de S3
//------------------------------------------------------------------------------
`define CRP_NOP   3'b000
`define CRP_F4E   3'b001   // tipo F
`define CRP_F4D   3'b010   // tipo F
`define CRP_KSETW 3'b011   // tipo V
`define CRP_AUTHW 3'b100   // tipo V
`define CRP_VCTL  3'b101   // tipo V
`define CRP_SALU  3'b110   // tipo AC
`define CRP_RSV   3'b111   // reservado

//------------------------------------------------------------------------------
// Subfunciones de VCTL, campo [12:11]
//------------------------------------------------------------------------------
`define VCTL_LOGIN  2'b00
`define VCTL_LOGOUT 2'b01
`define VCTL_PWSET  2'b10
`define VCTL_KCLR   2'b11

//------------------------------------------------------------------------------
// Campos de S3
//
//   Tipo F   [15:13] opcode | [12:10] par  | [9:8] kv     | [7:6] ronda | [5:0] rsv
//   Tipo V   [15:13] opcode | [12:11] A    | [10:9] B     | [8:5] rs    | [4:0] rsv
//   Tipo AC  [15:13] opcode | [12] i       | [11:9] subop | [8:5] rd    | [4:0] op2
//
// En el tipo V los campos A y B cambian de significado segun el opcode:
//
//   KSETW    A = kv      B = widx
//   AUTHW    A = rsv     B = widx     (decision D1, isa.md 5.2)
//   VCTL     A = subfn   B = kv, solo en KCLR
//
// El campo de registro principal ocupa siempre [8:5] en los tres formatos
// cortos, de modo que el decodificador lo extrae sin logica condicional.
//------------------------------------------------------------------------------
`define S3_OPC     15:13
`define S3_PAR     12:10
`define S3_KV       9:8
`define S3_RONDA    7:6
`define S3_F_RSV    5:0

`define S3_FLD_A   12:11
`define S3_FLD_B   10:9
`define S3_RS       8:5
`define S3_V_RSV    4:0

`define S3_AC_I       12
`define S3_AC_SUBOP 11:9
`define S3_AC_RD     8:5
`define S3_AC_OP2    4:0
`define S3_AC_RS2    3:0
`define S3_AC_RSV      4

//------------------------------------------------------------------------------
// Suboperaciones de la ALU corta, campo [11:9]
//
// Formato destructivo: rd <- rd op operando. Las dos unarias ignoran el
// operando, asi que con i = 1 la combinacion queda reservada.
//------------------------------------------------------------------------------
`define SALU_ADD 3'b000
`define SALU_SUB 3'b001
`define SALU_AND 3'b010
`define SALU_OR  3'b011
`define SALU_XOR 3'b100
`define SALU_MOV 3'b101
`define SALU_NOT 3'b110   // solo con i = 0
`define SALU_NEG 3'b111   // solo con i = 0

//==============================================================================
// SLOT S4  (16 bits): control de flujo
//==============================================================================

//------------------------------------------------------------------------------
// Opcodes de S4
//------------------------------------------------------------------------------
`define BRU_NOP  3'b000
`define BRU_BR   3'b001   // tipo C
`define BRU_JAL  3'b010   // tipo C
`define BRU_JR   3'b011   // tipo J
`define BRU_JALR 3'b100   // tipo J
`define BRU_HALT 3'b101   // tipo J

//------------------------------------------------------------------------------
// Campos de S4
//
//   Tipo C   [15:13] opcode | [12:10] cond | [9:0] desp
//   Tipo J   [15:13] opcode | [12:10] cond | [9] rsv | [8:5] rs | [4:0] rsv
//
// El tipo C NO tiene bits reservados: el desplazamiento ocupa los diez bits
// bajos completos.
//------------------------------------------------------------------------------
`define S4_OPC    15:13
`define S4_COND   12:10
`define S4_DESP     9:0
`define S4_RS       8:5
`define S4_J_RSV_HI    9
`define S4_J_RSV_LO  4:0

//==============================================================================
// CODIGOS COMPARTIDOS
//==============================================================================

//------------------------------------------------------------------------------
// Codigos de condicion (BRU y SETcc)
//------------------------------------------------------------------------------
`define COND_AL   3'b000
`define COND_EQ   3'b001
`define COND_NE   3'b010
`define COND_LT   3'b011
`define COND_GE   3'b100
`define COND_LTU  3'b101
`define COND_GEU  3'b110
`define COND_AUTH 3'b111

//------------------------------------------------------------------------------
// Posiciones de bit del PSW
//------------------------------------------------------------------------------
`define PSW_Z         0
`define PSW_N         1
`define PSW_C         2
`define PSW_V         3
`define PSW_AUTH      4
`define PSW_AUTHFAIL  5
`define PSW_EXC       6
`define PSW_CAUSE   9:7

// Indices dentro del vector compacto de banderas {V, C, N, Z}
`define FLG_Z 0
`define FLG_N 1
`define FLG_C 2
`define FLG_V 3

//------------------------------------------------------------------------------
// Codigos de causa de falla
//------------------------------------------------------------------------------
`define CAUSE_NONE     3'b000
`define CAUSE_ILLOP    3'b001
`define CAUSE_MISALIGN 3'b010
`define CAUSE_RANGE    3'b011
`define CAUSE_DENIED   3'b100
`define CAUSE_NOKEY    3'b101
`define CAUSE_WCONF    3'b110

//==============================================================================
// BANCO DE REGISTROS
//==============================================================================

//------------------------------------------------------------------------------
// Puertos de lectura
//
// Nueve en total, repartidos segun lo que cada slot necesita leer. Las tres
// unidades de S3 comparten los dos mismos puertos porque se excluyen entre si:
// o el bundle trae una ronda de cifrado, o una operacion de boveda, o una de
// la ALU corta, nunca dos a la vez.
//------------------------------------------------------------------------------
`define RP_S0_A  0   // ALU-0: rs1, o rd en MOVH
`define RP_S0_B  1   // ALU-0: rs2
`define RP_S1_A  2   // ALU-1: rs1, o rd en MOVH
`define RP_S1_B  3   // ALU-1: rs2
`define RP_S2_A  4   // LSU:   rbase
`define RP_S2_B  5   // LSU:   rs_dato de un store
`define RP_S3_A  6   // S3:    mitad L del par, o rd de la ALU corta
`define RP_S3_B  7   // S3:    mitad R del par, o rs2 de la ALU corta
`define RP_S4    8   // BRU:   rs de JR y JALR

`define NREAD_PORTS 9

//------------------------------------------------------------------------------
// Puertos de escritura
//
// Siete en total. EL ORDEN ES LA PRIORIDAD: el indice mas bajo gana, que es la
// regla S0 > S1 > S2 > S3 > S4 que fija el ISA para WCONF. Reordenar estas
// constantes cambia el comportamiento del procesador.
//
// S2 escribe dos veces porque el postincremento actualiza el registro base
// ademas del destino; S3 tambien, porque una ronda reescribe las dos mitades
// del par.
//------------------------------------------------------------------------------
`define WP_S0       0   // ALU-0: rd
`define WP_S1       1   // ALU-1: rd
`define WP_S2_RD    2   // LSU:   destino de un load
`define WP_S2_BASE  3   // LSU:   registro base de una variante .INC
`define WP_S3_L     4   // S3:    mitad L del par, o rd de la ALU corta
`define WP_S3_R     5   // S3:    mitad R del par
`define WP_S4_LINK  6   // BRU:   enlace de retorno, siempre R15

`define NWRITE_PORTS 7

//------------------------------------------------------------------------------
// Mapa de memoria de datos (isa.md 1.4)
//
// Los accesos fuera de este rango producen RANGE.
//------------------------------------------------------------------------------
`define DMEM_BASE  32'h0000_0000
`define DMEM_LIMIT 32'h0000_FFFF

//------------------------------------------------------------------------------
// Region segura de la memoria de instrucciones (isa.md 1.4)
//------------------------------------------------------------------------------
`define SEC_BASE_DEF  32'h0000_7000
`define SEC_LIMIT_DEF 32'h0000_7FFF

`endif // CERBERO_DEFS_SVH
