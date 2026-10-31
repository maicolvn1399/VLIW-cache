`timescale 1ns/1ps

// =============================================================================
// lsu.sv - Unidad de acceso a memoria, slot S2 del bundle (tipo M).
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Calcula la direccion efectiva, alinea el dato en los dos sentidos, maneja el
// postincremento del registro base y detecta las tres fallas que el ISA le
// asigna a esta unidad.
//
// Combinacional a proposito. La memoria de datos vive en la etapa MEM y el
// reparto temporal queda en el datapath; esta unidad no registra nada.
//
// -----------------------------------------------------------------------------
// INTERFAZ CON EL DATAPATH
// -----------------------------------------------------------------------------
// La unidad recibe el slot crudo y publica los indices de registro que
// necesita; el datapath los lee del banco y devuelve los valores. Es el mismo
// contrato que usan crypto_unit.sv y bru.sv, de modo que las unidades de los
// slots S2 a S4 se conectan igual y la etapa de decodificacion no necesita un
// camino especial para ninguna.
//
//   slot  ->  rd_idx, rbase_idx  ->  (banco de registros)  ->  rbase_val,
//                                                              rs_data_val
//
// -----------------------------------------------------------------------------
// ESTRUCTURA DEL OPCODE
// -----------------------------------------------------------------------------
//   opcode[4] = INC   1 = escribe de vuelta el registro base
//   opcode[3] = ST    0 = load, 1 = store
//   opcode[2:1] = TAM 01 = byte, 10 = media palabra, 11 = palabra
//   opcode[0] = U     1 = extension con ceros (solo loads)
//
// Decidir si hay que escribir de vuelta el registro base cuesta mirar un bit,
// no decodificar el opcode completo. Esa es la ventaja de haber asignado los
// numeros por estructura y no por orden de aparicion.
//
// -----------------------------------------------------------------------------
// FALLAS (isa.md 1.2)
// -----------------------------------------------------------------------------
//   ILLOP     opcode no definido. Las combinaciones con TAM = 00, los stores
//             con U = 1 y las variantes .INC que no son de palabra quedan
//             reservadas.
//   MISALIGN  direccion no alineada al tamano del acceso.
//   RANGE     direccion fuera de la memoria de datos implementada.
//
// El orden de prioridad es ILLOP, MISALIGN, RANGE, y no es arbitrario: un
// opcode no definido no tiene tamano, asi que no se le puede juzgar la
// alineacion; y una direccion desalineada ya esta mal aunque ademas caiga
// fuera del rango. Informar la causa mas temprana es informar la causa raiz.
//
// La politica es la del ISA, "anular y marcar": el acceso no ocurre, no se
// escribe ningun registro, y la causa queda en el PSW. El pipeline no se
// detiene.
//
// El tipo M no tiene bits reservados: opcode, rd, rbase e inmediato suman los
// 32 bits del slot. Por eso aqui no hay chequeo de reservados, a diferencia
// del tipo A de la ALU.
// =============================================================================

`include "cerbero_defs.svh"

module lsu #(
    parameter logic [31:0] DMEM_BASE  = `DMEM_BASE,
    parameter logic [31:0] DMEM_LIMIT = `DMEM_LIMIT
) (
    // Slot S2 crudo, bits 63:32 del bundle
    input  logic [31:0] slot,
    input  logic        valid,

    // Indices que el datapath debe leer del banco de registros
    output logic [3:0]  rd_idx,          // destino de un load, fuente de un store
    output logic [3:0]  rbase_idx,
    input  logic [31:0] rbase_val,
    input  logic [31:0] rs_data_val,

    // Hacia la memoria de datos
    output logic [31:0] eff_addr,
    output logic [31:0] mem_write_data,
    output logic        mem_we,
    output logic [3:0]  byte_enable,
    input  logic [31:0] mem_read_data,

    // Hacia el banco de registros
    output logic        rd_write_en,
    output logic [31:0] rd_load_data,
    output logic        rbase_write_en,
    output logic [31:0] rbase_updated,

    // Hacia el registro de estado
    output logic        fault,
    output logic [2:0]  cause
);

  // ---------------------------------------------------------------------------
  // Campos del slot
  //
  // Los indices salen siempre, tambien cuando la operacion falla, porque el
  // datapath necesita leer los operandos antes de saber si procede.
  // ---------------------------------------------------------------------------

  logic [4:0]  opcode;
  logic [18:0] imm19;

  assign opcode    = slot[`F_OPC];
  assign rd_idx    = slot[`F_RD];
  assign rbase_idx = slot[`F_RS1];
  assign imm19     = slot[`F_IMM19];

  // ---------------------------------------------------------------------------
  // Desglose estructurado del opcode
  // ---------------------------------------------------------------------------

  // El bit de extension con ceros no aparece aqui: solo lo usa la extraccion
  // del carril, que vive en load_align.sv.
  logic       is_inc;
  logic       is_st;
  logic [1:0] tam;

  assign is_inc      = opcode[`LSU_BIT_INC];
  assign is_st       = opcode[`LSU_BIT_ST];
  assign tam         = opcode[`LSU_FLD_TAM];

  // ---------------------------------------------------------------------------
  // Opcodes definidos
  //
  // Se enumeran en vez de deducirse del desglose, porque no toda combinacion
  // de los cuatro subcampos es una instruccion: TAM = 00 no existe, un store
  // no tiene version con extension de ceros, y el postincremento solo esta
  // definido para la palabra completa.
  // ---------------------------------------------------------------------------

  logic op_is_nop;
  logic op_defined;

  assign op_is_nop = (opcode == `LSU_NOP);

  always_comb begin
    case (opcode)
      `LSU_NOP,
      `LSU_LB,  `LSU_LBU,
      `LSU_LH,  `LSU_LHU,
      `LSU_LW,
      `LSU_SB,  `LSU_SH,  `LSU_SW,
      `LSU_LW_INC, `LSU_SW_INC : op_defined = 1'b1;
      default                  : op_defined = 1'b0;
    endcase
  end

  // Una operacion que de verdad toca memoria: definida y distinta de la nula
  logic op_is_access;
  assign op_is_access = op_defined && !op_is_nop;

  // ---------------------------------------------------------------------------
  // Direccion efectiva
  //
  // Las variantes .INC son POSTincremento: acceden a la direccion actual y
  // despues avanzan el puntero. El inmediato es el incremento, no un
  // desplazamiento de acceso. Es la unica parte del tipo M donde el inmediato
  // no entra en la direccion, y confundirlo desplaza todo el lazo de cifrado
  // una palabra.
  // ---------------------------------------------------------------------------

  logic [31:0] sign_ext_imm;
  assign sign_ext_imm = {{13{imm19[18]}}, imm19};

  assign eff_addr      = is_inc ? rbase_val : (rbase_val + sign_ext_imm);
  assign rbase_updated = rbase_val + sign_ext_imm;

  // ---------------------------------------------------------------------------
  // Alineacion natural
  //
  // El byte siempre esta alineado; la media palabra exige el bit 0 en cero y
  // la palabra los dos bits bajos.
  // ---------------------------------------------------------------------------

  // Los recortes de bits se calculan con asignaciones continuas y no dentro
  // del always_comb: Icarus Verilog no infiere sensibilidad sobre recortes
  // constantes dentro de un proceso y emite un aviso por cada uno. Sacarlos
  // aqui deja la compilacion limpia sin cambiar el comportamiento.
  logic [1:0] addr_lo;
  logic       odd_addr;
  logic       unaligned_word;
  logic       misaligned;

  assign addr_lo        = eff_addr[1:0];
  assign odd_addr       = (addr_lo[0] != 1'b0);
  assign unaligned_word = (addr_lo    != 2'b00);

  always_comb begin
    case (tam)
      `LSU_TAM_B : misaligned = 1'b0;
      `LSU_TAM_H : misaligned = odd_addr;
      `LSU_TAM_W : misaligned = unaligned_word;
      default    : misaligned = 1'b0;   // TAM = 00 ya es ILLOP
    endcase
  end

  // ---------------------------------------------------------------------------
  // Rango implementado
  //
  // Basta comprobar la direccion de inicio. Como la alineacion ya se exigio y
  // el limite superior mas uno es multiplo de cuatro, un acceso alineado que
  // empieza dentro del rango termina dentro del rango.
  // ---------------------------------------------------------------------------

  // La comparacion contra el limite inferior es constantemente falsa mientras
  // DMEM_BASE valga cero, y el analisis estatico lo senala. Se conserva igual
  // porque el modulo esta parametrizado: con una base distinta de cero la
  // comparacion se vuelve real, y quitarla dejaria un agujero que solo
  // aparece el dia que alguien mueva la memoria.
  logic out_of_range;
  /* verilator lint_off UNSIGNED */
  assign out_of_range = (eff_addr < DMEM_BASE) || (eff_addr > DMEM_LIMIT);
  /* verilator lint_on UNSIGNED */

  // ---------------------------------------------------------------------------
  // Falla
  //
  // La operacion nula no falla nunca, ni siquiera por los campos que no usa.
  // Si levantara falla, todo bundle que no use este slot fallaria, y como
  // cualquier falla apaga el bit de autenticacion, romperia una sesion de
  // cifrado en curso por un slot que no hace nada.
  // ---------------------------------------------------------------------------

  always_comb begin
    cause = `CAUSE_NONE;
    if (valid) begin
      if      (!op_defined)                   cause = `CAUSE_ILLOP;
      else if (op_is_access && misaligned)    cause = `CAUSE_MISALIGN;
      else if (op_is_access && out_of_range)  cause = `CAUSE_RANGE;
    end
  end

  assign fault = (cause != `CAUSE_NONE);

  // La operacion procede solo si se emitio, es un acceso real y no fallo
  logic exec;
  assign exec = valid && op_is_access && !fault;

  // ---------------------------------------------------------------------------
  // Escrituras hacia el banco de registros
  //
  // Caso limite de LW.INC con rd igual a rbase: prevalece el dato cargado y el
  // incremento se descarta. Sin esta regla el resultado dependeria del orden
  // en que el arbitro atendiera los dos puertos de escritura de la unidad.
  // ---------------------------------------------------------------------------

  logic rd_rbase_clash;
  assign rd_rbase_clash = !is_st && (rd_idx == rbase_idx);

  assign rd_write_en    = exec && !is_st;
  assign rbase_write_en = exec && is_inc && !rd_rbase_clash;

  // ---------------------------------------------------------------------------
  // Escritura en memoria
  //
  // El dato se REPLICA en los cuatro carriles de la palabra y la mascara de
  // bytes decide cual se escribe de verdad. Es mas barato que correr el dato
  // hacia su carril: replicar es cableado, mientras que correrlo por una
  // cantidad que depende de la direccion exige un desplazador de barril de 32
  // bits, que ademas deja la mitad de su salida sin usar.
  //
  // CONTRATO CON dmem.sv: la memoria DEBE escribir unicamente los carriles
  // marcados en byte_enable. Los demas traen una copia del dato, no ceros, y
  // escribirlos corromperia los bytes vecinos. Una memoria que ignore la
  // mascara va a parecer que funciona con SW, donde la mascara vale 1111, y
  // va a corromper datos en el primer SB.
  // ---------------------------------------------------------------------------

  logic [3:0]  be_byte;
  logic [3:0]  be_half;
  logic [31:0] data_byte;
  logic [31:0] data_half;

  assign be_byte   = 4'b0001 << addr_lo;
  assign be_half   = 4'b0011 << addr_lo;
  assign data_byte = {4{rs_data_val[7:0]}};
  assign data_half = {2{rs_data_val[15:0]}};

  assign mem_we = exec && is_st;

  always_comb begin
    byte_enable    = 4'b0000;
    mem_write_data = 32'd0;

    if (mem_we) begin
      case (tam)
        `LSU_TAM_B : begin
          byte_enable    = be_byte;
          mem_write_data = data_byte;
        end
        `LSU_TAM_H : begin
          byte_enable    = be_half;
          mem_write_data = data_half;
        end
        `LSU_TAM_W : begin
          byte_enable    = 4'b1111;
          mem_write_data = rs_data_val;
        end
        default    : begin
          byte_enable    = 4'b0000;
          mem_write_data = 32'd0;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Lectura desde memoria
  //
  // La extraccion del carril vive en load_align.sv, que es un modulo aparte
  // porque el datapath lo necesita por su cuenta: la LSU calcula la direccion
  // en EX, pero el dato de la memoria no existe hasta MEM, y un modulo
  // combinacional no puede estar en dos ciclos a la vez. La etapa de memoria
  // instancia ese mismo modulo con lo que le llega por la frontera EX/MEM.
  //
  // Instanciarlo aqui tambien, en vez de dejar la logica suelta en el
  // datapath, es lo que mantiene una sola copia de la tabla de tamanos y
  // signos, y lo que hace que los casos de carga de tb_lsu.sv sigan cubriendola.
  // ---------------------------------------------------------------------------

  load_align u_align (
      .slot          (slot),
      .addr_lo       (addr_lo),
      .rd_write_en   (rd_write_en),
      .mem_read_data (mem_read_data),
      .rd_load_data  (rd_load_data)
  );

endmodule
