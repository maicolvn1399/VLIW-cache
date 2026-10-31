`timescale 1ns/1ps

// =============================================================================
// short_alu.sv - ALU corta, slot S3 del bundle (tipo AC).
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Existe para que los programas que no cifran no desperdicien un quinto de
// cada bundle emitiendo solo operaciones nulas en S3. Comparte el slot con la
// unidad Feistel4 y con la boveda, y el opcode decide cual de las tres actua:
// o el programa cifra, o usa la ALU corta, nunca las dos en el mismo bundle.
//
// El formato es DESTRUCTIVO, rd <- rd op operando, porque en 16 bits no caben
// tres campos de registro. Ese es el precio de meter una ALU en un slot corto.
//
// No escribe banderas: son exclusivas de S0.
//
// -----------------------------------------------------------------------------
// INTERFAZ CON EL DATAPATH
// -----------------------------------------------------------------------------
// Igual que crypto_unit.sv, key_vault.sv, lsu.sv y bru.sv: la unidad recibe el
// slot crudo, publica los indices que necesita y el datapath le devuelve los
// valores. Que las cinco se conecten igual es lo que permite que la etapa de
// decodificacion sea un rebanado de bits y cinco instancias, sin un camino
// especial para ninguna.
//
// -----------------------------------------------------------------------------
// OPERACIONES UNARIAS
// -----------------------------------------------------------------------------
// NOT y NEG operan sobre rd y no sobre el segundo operando, porque el formato
// es destructivo y rd es a la vez fuente y destino. En consecuencia:
//
//   - con i = 0 el campo de registro fuente no se usa y debe ir en cero;
//   - con i = 1 la combinacion no tiene sentido y queda RESERVADA.
//
// La sintaxis correcta es "not.s rd", sin segundo operando. Devolver cero en
// silencio ante una combinacion reservada seria peor que fallar: el programa
// no se enteraria.
// =============================================================================

`include "cerbero_defs.svh"

module short_alu (
    // Slot S3 crudo, bits 31:16 del bundle
    input  logic [15:0] slot,
    input  logic        valid,

    // Indices que el datapath debe leer del banco de registros
    output logic [3:0]  rd_idx,          // fuente y destino a la vez
    output logic [3:0]  rs2_idx,
    input  logic [31:0] rd_val,
    input  logic [31:0] rs2_val,

    // Resultado
    output logic        wr_en,
    output logic [31:0] result,

    // Falla hacia el registro de estado
    output logic        fault,
    output logic [2:0]  cause
);

  // ---------------------------------------------------------------------------
  // Campos del slot
  // ---------------------------------------------------------------------------

  logic [2:0] opcode;
  logic       i_bit;
  logic [2:0] subop;
  logic [4:0] imm5;
  logic       rsv_bit;

  assign opcode  = slot[`S3_OPC];
  assign i_bit   = slot[`S3_AC_I];
  assign subop   = slot[`S3_AC_SUBOP];
  assign rd_idx  = slot[`S3_AC_RD];
  assign rs2_idx = slot[`S3_AC_RS2];
  assign imm5    = slot[`S3_AC_OP2];
  assign rsv_bit = slot[`S3_AC_RSV];

  // La unidad solo actua cuando el opcode de S3 la selecciona. Con cualquier
  // otro valor el slot le pertenece a la unidad Feistel4 o a la boveda, y esta
  // unidad se queda callada: ni escribe ni falla.
  logic selected;
  assign selected = valid && (opcode == `CRP_SALU);

  // ---------------------------------------------------------------------------
  // Segundo operando
  //
  // El inmediato es SIN signo, de cero a 31. Cubre los contadores pequenos y
  // las cantidades de corrimiento, que es para lo que alcanzan cinco bits.
  // ---------------------------------------------------------------------------

  logic [31:0] operand2;
  assign operand2 = i_bit ? {27'd0, imm5} : rs2_val;

  // ---------------------------------------------------------------------------
  // Operaciones unarias y combinaciones reservadas
  // ---------------------------------------------------------------------------

  logic op_is_unary;
  assign op_is_unary = (subop == `SALU_NOT) || (subop == `SALU_NEG);

  // ---------------------------------------------------------------------------
  // Falla
  //
  //   combinacion reservada  una unaria con inmediato, que no significa nada
  //   reservado sucio        con i = 0 el bit 4 del campo de operando no se
  //                          usa, y con una unaria tampoco se usan los cuatro
  //                          bits del registro fuente
  // ---------------------------------------------------------------------------

  logic illop;

  always_comb begin
    illop = 1'b0;
    if (selected) begin
      if (op_is_unary && i_bit)                  illop = 1'b1;  // reservada
      else if (!i_bit && (rsv_bit != 1'b0))      illop = 1'b1;  // bit 4
      else if (!i_bit && op_is_unary &&
               (rs2_idx != 4'd0))                illop = 1'b1;  // fuente no usada
    end
  end

  assign fault = illop;
  assign cause = illop ? `CAUSE_ILLOP : `CAUSE_NONE;

  // ---------------------------------------------------------------------------
  // Operacion
  //
  // Las ocho suboperaciones estan definidas, asi que la rama por omision no es
  // alcanzable; esta por completitud del case.
  // ---------------------------------------------------------------------------

  logic [31:0] res_raw;

  always_comb begin
    case (subop)
      `SALU_ADD : res_raw = rd_val + operand2;
      `SALU_SUB : res_raw = rd_val - operand2;
      `SALU_AND : res_raw = rd_val & operand2;
      `SALU_OR  : res_raw = rd_val | operand2;
      `SALU_XOR : res_raw = rd_val ^ operand2;
      `SALU_MOV : res_raw = operand2;
      `SALU_NOT : res_raw = ~rd_val;
      `SALU_NEG : res_raw = 32'd0 - rd_val;
      default   : res_raw = 32'd0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Gobierno de la salida
  //
  // Anular es completo: sin seleccion o con falla no se habilita la escritura
  // y el resultado sale en cero, igual que en el resto de las unidades.
  // ---------------------------------------------------------------------------

  assign wr_en  = selected && !illop;
  assign result = wr_en ? res_raw : 32'd0;

endmodule
