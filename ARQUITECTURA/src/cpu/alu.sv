//==============================================================================
// alu.sv
// CERBERO-1 - Unidad Aritmetico-Logica
//
// Una sola descripcion sirve para los dos slots de ALU del bundle. El
// parametro IS_SLOT0 distingue la instancia:
//
//   IS_SLOT0 = 1  -> ALU-0, en el slot S0 [127:96]. Unica que escribe banderas.
//   IS_SLOT0 = 0  -> ALU-1, en el slot S1  [95:64]. Las comparaciones
//                    codificadas aqui se anulan y registran ILLOP.
//
// La unidad es puramente combinacional y vive en la etapa EX. Los registros
// de segmentacion estan fuera de este modulo.
//
//------------------------------------------------------------------------------
// CONTRATO CON LA ETAPA ID (dispatch)
//------------------------------------------------------------------------------
// op_a_i y op_b_i llegan ya leidos del banco de registros. La etapa ID debe
// enrutar los puertos de lectura asi:
//
//   Opcode                     puerto A            puerto B
//   -------------------------  ------------------  ----------------
//   ADD..ROR (tipo A, 3 op.)   R[rs1]              R[rs2]
//   MOV, NOT, NEG              R[rs1]              no se usa
//   CMP, TEST                  R[rs1]              R[rs2]
//   ADDI..ROLI, CMPI, TESTI    R[rs1]              no se usa
//   MOVI, SETcc, MFPSW         no se usa           no se usa
//   MOVH                       R[rd]   <-- OJO     no se usa
//
// MOVH es el unico caso en que el puerto A no lee rs1: la instruccion
// sobrescribe la mitad alta de rd conservando la mitad baja, asi que necesita
// el valor actual de rd. Su campo rs1 esta reservado en cero.
//
//------------------------------------------------------------------------------
// CAMPOS RESERVADOS
//------------------------------------------------------------------------------
// La especificacion exige que todo bit reservado se codifique en cero y que un
// valor distinto anule la operacion y registre ILLOP. Esta es la tabla que
// implementa el modulo:
//
//   Grupo                              Debe valer cero
//   ---------------------------------  ---------------------------
//   NOP                                (no se verifica nada)
//   ADD SUB MUL AND OR XOR
//   SLL SRL SRA ROL ROR                slot[14:0]
//   MOV NOT NEG                        slot[14:0] y rs2
//   CMP TEST                           slot[14:0] y rd
//   ADDI SUBI ANDI ORI XORI
//   SLLI SRLI SRAI ROLI                (todos los campos se usan)
//   CMPI TESTI                         rd
//   MOVI                               rs1
//   MOVH                               rs1 y cond
//   SETcc                              rs1 e imm16
//   MFPSW                              rs1, imm16 y cond
//
// Los 32 opcodes estan definidos, de modo que no existe el caso de "opcode
// desconocido": ILLOP solo proviene de un campo reservado distinto de cero o
// de una comparacion codificada en S1.
//==============================================================================
`timescale 1ns/1ps
`include "cerbero_defs.svh"

module alu #(
    parameter bit IS_SLOT0 = 1'b0
) (
    // Slot crudo de 32 bits proveniente del bundle
    input  logic [31:0]        slot_i,
    // Operandos ya leidos del banco de registros
    input  logic [`XLEN-1:0]   op_a_i,
    input  logic [`XLEN-1:0]   op_b_i,
    // PSW actual, necesario para SETcc y MFPSW
    input  logic [`XLEN-1:0]   psw_i,

    // Resultado hacia el arbitro de escritura
    output logic [`XLEN-1:0]   result_o,
    output logic [`RIDX_W-1:0] rd_o,
    output logic               rd_we_o,
    // Banderas hacia el PSW. Solo la instancia con IS_SLOT0 = 1 las activa.
    output logic               flags_we_o,
    output logic [3:0]         flags_o,     // {V, C, N, Z}
    // Falla de operacion ilegal
    output logic               illop_o
);

    //--------------------------------------------------------------------------
    // Extraccion de campos
    //--------------------------------------------------------------------------
    logic [4:0]  opc;
    logic [3:0]  rd_f, rs1_f, rs2_f;
    logic [14:0] rsv_a;
    logic [18:0] imm19;
    logic [15:0] imm16;
    logic [2:0]  cond_f;

    assign opc    = slot_i[`F_OPC];
    assign rd_f   = slot_i[`F_RD];
    assign rs1_f  = slot_i[`F_RS1];
    assign rs2_f  = slot_i[`F_RS2];
    assign rsv_a  = slot_i[`F_RSVA];
    assign imm19  = slot_i[`F_IMM19];
    assign imm16  = slot_i[`F_IMM16];
    assign cond_f = slot_i[`F_COND];

    // Inmediato de 19 bits con extension de signo a 32
    logic [`XLEN-1:0] imm_ext;
    assign imm_ext = {{(`XLEN-19){imm19[18]}}, imm19};

    // Cantidades de desplazamiento: solo cuentan los 5 bits bajos
    logic [4:0] sh_reg, sh_imm;
    assign sh_reg = op_b_i[4:0];
    assign sh_imm = imm19[4:0];

    //--------------------------------------------------------------------------
    // Complemento de la cantidad de desplazamiento, para las rotaciones
    //
    // Se calcula en seis bits a proposito. Con sh = 0 el complemento vale 32, y
    // el estandar define que desplazar una palabra de 32 bits por 32 o mas da
    // cero, de modo que la rotacion de cero posiciones devuelve el operando sin
    // cambios. Calcularlo en cinco bits tambien funcionaria por el envolvente,
    // pero dependeria de un detalle de truncamiento en vez de una regla del
    // lenguaje. El testbench cubre explicitamente el caso sh = 0.
    //--------------------------------------------------------------------------
    logic [5:0] inv_reg, inv_imm;
    assign inv_reg = 6'd32 - {1'b0, sh_reg};
    assign inv_imm = 6'd32 - {1'b0, sh_imm};

    //--------------------------------------------------------------------------
    // Resta y AND para las instrucciones de comparacion
    //
    // C se define como PRESTAMO: C = 1 cuando op_a < cmp_b sin signo. Es la
    // convencion que exige la tabla de condiciones del ISA, donde LTU
    // corresponde a C = 1. Notese que es la opuesta a la de ARM.
    //--------------------------------------------------------------------------
    logic [`XLEN-1:0] cmp_b, diff, and_res;
    logic             c_borrow, v_ovf;

    assign cmp_b = (opc == `ALU_CMPI || opc == `ALU_TESTI) ? imm_ext : op_b_i;
    assign {c_borrow, diff} = {1'b0, op_a_i} - {1'b0, cmp_b};
    assign v_ovf  = (op_a_i[`XLEN-1] ^ cmp_b[`XLEN-1]) &
                    (op_a_i[`XLEN-1] ^ diff[`XLEN-1]);
    assign and_res = op_a_i & cmp_b;

    //--------------------------------------------------------------------------
    // Evaluacion de condicion para SETcc
    //
    // Se resuelve con asignaciones continuas y no con una funcion llamada desde
    // el always_comb, porque las selecciones de bit del PSW dentro de un
    // proceso disparan el aviso de sensibilidad de Icarus Verilog.
    //
    // Es la misma tabla de condiciones que usa la BRU, de modo que ambos
    // modulos deben mantenerse sincronizados con la seccion 6 del ISA.
    //--------------------------------------------------------------------------
    logic psw_z, psw_n, psw_c, psw_v, psw_au;

    assign psw_z  = psw_i[`PSW_Z];
    assign psw_n  = psw_i[`PSW_N];
    assign psw_c  = psw_i[`PSW_C];
    assign psw_v  = psw_i[`PSW_V];
    assign psw_au = psw_i[`PSW_AUTH];

    logic cond_true;

    assign cond_true = (cond_f == `COND_AL)   ? 1'b1             :
                       (cond_f == `COND_EQ)   ? psw_z            :
                       (cond_f == `COND_NE)   ? ~psw_z           :
                       (cond_f == `COND_LT)   ? (psw_n ^ psw_v)  :
                       (cond_f == `COND_GE)   ? ~(psw_n ^ psw_v) :
                       (cond_f == `COND_LTU)  ? psw_c            :
                       (cond_f == `COND_GEU)  ? ~psw_c           :
                                                psw_au;   // COND_AUTH

    logic [`XLEN-1:0] setcc_w;
    assign setcc_w = {{(`XLEN-1){1'b0}}, cond_true};

    //--------------------------------------------------------------------------
    // Verificacion de campos reservados
    //--------------------------------------------------------------------------
    logic rsv_bad;

    always_comb begin
        rsv_bad = 1'b0;
        case (opc)
            `ALU_NOP   : rsv_bad = 1'b0;

            `ALU_ADD, `ALU_SUB, `ALU_MUL, `ALU_AND, `ALU_OR, `ALU_XOR,
            `ALU_SLL, `ALU_SRL, `ALU_SRA, `ALU_ROL, `ALU_ROR :
                         rsv_bad = (rsv_a != 15'd0);

            `ALU_MOV, `ALU_NOT, `ALU_NEG :
                         rsv_bad = (rsv_a != 15'd0) || (rs2_f != 4'd0);

            `ALU_CMP, `ALU_TEST :
                         rsv_bad = (rsv_a != 15'd0) || (rd_f != 4'd0);

            `ALU_CMPI, `ALU_TESTI :
                         rsv_bad = (rd_f != 4'd0);

            `ALU_MOVI  : rsv_bad = (rs1_f != 4'd0);

            `ALU_MOVH  : rsv_bad = (rs1_f != 4'd0) || (cond_f != 3'd0);

            `ALU_SETCC : rsv_bad = (rs1_f != 4'd0) || (imm16 != 16'd0);

            `ALU_MFPSW : rsv_bad = (rs1_f != 4'd0) || (imm16 != 16'd0) ||
                                   (cond_f != 3'd0);

            default    : rsv_bad = 1'b0;   // formas inmediatas: usan todo
        endcase
    end

    //--------------------------------------------------------------------------
    // Comparaciones fuera de S0
    //--------------------------------------------------------------------------
    logic slot_bad;
    assign slot_bad = (IS_SLOT0 == 1'b0) &&
                      ((opc == `ALU_CMP)  || (opc == `ALU_TEST) ||
                       (opc == `ALU_CMPI) || (opc == `ALU_TESTI));

    assign illop_o = rsv_bad || slot_bad;

    //--------------------------------------------------------------------------
    // Resultados parciales
    //
    // Los recortes de bits se calculan con asignaciones continuas y no dentro
    // del always_comb. Icarus Verilog no infiere sensibilidad sobre recortes
    // constantes dentro de un proceso y emite un aviso por cada uno; sacarlos
    // aqui deja la compilacion limpia sin cambiar el comportamiento.
    //--------------------------------------------------------------------------
    logic [`XLEN-1:0] rotl_reg_w, rotr_reg_w, rotl_imm_w, movh_w, zero_w;
    logic [3:0]       flg_cmp, flg_test;

    assign zero_w     = {`XLEN{1'b0}};
    assign rotl_reg_w = (op_a_i << sh_reg) | (op_a_i >> inv_reg);
    assign rotr_reg_w = (op_a_i >> sh_reg) | (op_a_i << inv_reg);
    assign rotl_imm_w = (op_a_i << sh_imm) | (op_a_i >> inv_imm);
    assign movh_w     = {imm16, op_a_i[15:0]};

    // Vector de banderas en el orden {V, C, N, Z}
    assign flg_cmp  = { v_ovf, c_borrow, diff[`XLEN-1],    (diff    == zero_w) };
    assign flg_test = { 1'b0,  1'b0,     and_res[`XLEN-1], (and_res == zero_w) };

    //--------------------------------------------------------------------------
    // Operacion principal
    //--------------------------------------------------------------------------
    logic [`XLEN-1:0] res_raw;
    logic             we_raw, fwe_raw;
    logic [3:0]       flg_raw;

    always_comb begin
        res_raw = zero_w;
        we_raw  = 1'b0;
        fwe_raw = 1'b0;
        flg_raw = 4'b0000;

        case (opc)
            //---- Tipo A: tres operandos ------------------------------------
            `ALU_NOP  : begin end
            `ALU_ADD  : begin res_raw = op_a_i + op_b_i;            we_raw = 1'b1; end
            `ALU_SUB  : begin res_raw = op_a_i - op_b_i;            we_raw = 1'b1; end
            `ALU_MUL  : begin res_raw = op_a_i * op_b_i;            we_raw = 1'b1; end
            `ALU_AND  : begin res_raw = op_a_i & op_b_i;            we_raw = 1'b1; end
            `ALU_OR   : begin res_raw = op_a_i | op_b_i;            we_raw = 1'b1; end
            `ALU_XOR  : begin res_raw = op_a_i ^ op_b_i;            we_raw = 1'b1; end
            `ALU_SLL  : begin res_raw = op_a_i << sh_reg;           we_raw = 1'b1; end
            `ALU_SRL  : begin res_raw = op_a_i >> sh_reg;           we_raw = 1'b1; end
            `ALU_SRA  : begin res_raw = $signed(op_a_i) >>> sh_reg; we_raw = 1'b1; end
            `ALU_ROL  : begin res_raw = rotl_reg_w;                 we_raw = 1'b1; end
            `ALU_ROR  : begin res_raw = rotr_reg_w;                 we_raw = 1'b1; end

            //---- Tipo A: dos operandos -------------------------------------
            `ALU_MOV  : begin res_raw = op_a_i;                     we_raw = 1'b1; end
            `ALU_NOT  : begin res_raw = ~op_a_i;                    we_raw = 1'b1; end
            `ALU_NEG  : begin res_raw = zero_w - op_a_i;            we_raw = 1'b1; end

            //---- Comparaciones: no escriben registro, si banderas -----------
            // El vector se asigna completo, en el orden {V, C, N, Z}.
            `ALU_CMP, `ALU_CMPI : begin
                fwe_raw = 1'b1;
                flg_raw = flg_cmp;
            end

            `ALU_TEST, `ALU_TESTI : begin
                fwe_raw = 1'b1;
                flg_raw = flg_test;   // TEST limpia C y V
            end

            //---- Tipo I ----------------------------------------------------
            `ALU_ADDI : begin res_raw = op_a_i + imm_ext;            we_raw = 1'b1; end
            `ALU_SUBI : begin res_raw = op_a_i - imm_ext;            we_raw = 1'b1; end
            `ALU_ANDI : begin res_raw = op_a_i & imm_ext;            we_raw = 1'b1; end
            `ALU_ORI  : begin res_raw = op_a_i | imm_ext;            we_raw = 1'b1; end
            `ALU_XORI : begin res_raw = op_a_i ^ imm_ext;            we_raw = 1'b1; end
            `ALU_SLLI : begin res_raw = op_a_i << sh_imm;            we_raw = 1'b1; end
            `ALU_SRLI : begin res_raw = op_a_i >> sh_imm;            we_raw = 1'b1; end
            `ALU_SRAI : begin res_raw = $signed(op_a_i) >>> sh_imm;  we_raw = 1'b1; end
            `ALU_ROLI : begin res_raw = rotl_imm_w;                  we_raw = 1'b1; end
            `ALU_MOVI : begin res_raw = imm_ext;                     we_raw = 1'b1; end

            //---- Tipo U ----------------------------------------------------
            // MOVH conserva la mitad baja de rd, que llega por op_a_i.
            `ALU_MOVH : begin res_raw = movh_w;                      we_raw = 1'b1; end
            `ALU_SETCC: begin res_raw = setcc_w;                     we_raw = 1'b1; end
            `ALU_MFPSW: begin res_raw = psw_i;                       we_raw = 1'b1; end

            default   : begin end
        endcase
    end

    //--------------------------------------------------------------------------
    // Anulacion ante falla
    //
    // Politica de "anular y marcar": el slot que falla se comporta como NOP y
    // la causa se registra en el PSW. El pipeline no se detiene.
    //--------------------------------------------------------------------------
    assign result_o   = illop_o ? {`XLEN{1'b0}} : res_raw;
    assign rd_we_o    = illop_o ? 1'b0          : we_raw;
    assign flags_we_o = illop_o ? 1'b0          : fwe_raw;
    assign flags_o    = illop_o ? 4'b0000       : flg_raw;
    assign rd_o       = rd_f;

endmodule
