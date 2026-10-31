`timescale 1ns/1ps

// =============================================================================
// bru.sv - Unidad de saltos, slot S4 del bundle (tipos C y J).
//
// Evalua la condicion contra las banderas del registro de estado, calcula la
// direccion destino, produce el enlace de retorno y senala la detencion.
//
// Combinacional a proposito, y el motivo es una cuenta de ciclos: para que un
// solo delay slot alcance, el destino tiene que estar listo al final del ciclo
// en que el salto esta en decodificacion. Un salto en el bundle n se busca en
// el ciclo n, su delay slot en n+1, y el destino tiene que buscarse en n+2.
// Eso cuadra con la latencia de 3 bundles de las banderas, que las deja
// legibles justo en decodificacion. Resolver en ejecucion exigiria dos delay
// slots.
//
// El reparto temporal queda en el datapath. La escritura del enlace a R15
// tiene que retrasarse hasta la ultima etapa para respetar la latencia
// uniforme; esta unidad entrega el valor y el indice, no los registra.
//
// La unidad NO implementa el cierre automatico de sesion. key_vault.sv ya
// consume el contador de programa y lo compara contra la region segura.
// Duplicarlo crearia dos comparadores capaces de divergir.
// =============================================================================

`include "cerbero_defs.svh"

module bru (
    // Slot S4 crudo, bits 15:0 del bundle
    input  logic [15:0] slot,
    input  logic        valid,

    // Contador de programa del bundle que trae esta operacion
    input  logic [31:0] pc,

    // Banderas del registro de estado
    input  logic        flag_z,
    input  logic        flag_n,
    input  logic        flag_c,
    input  logic        flag_v,
    input  logic        flag_auth,

    // Registro fuente de los saltos indirectos
    output logic [3:0]  rs_idx,
    input  logic [31:0] rs_val,

    // Resolucion del salto
    output logic        taken,
    output logic [31:0] target,

    // Enlace de retorno
    output logic        link_we,
    output logic [3:0]  link_idx,
    output logic [31:0] link_val,

    // Detencion
    output logic        halt,

    // Falla hacia el registro de estado
    output logic        fault,
    output logic [2:0]  cause
);

  // ---------------------------------------------------------------------------
  // Opcodes del slot (isa.md 6)
  // ---------------------------------------------------------------------------

  localparam logic [2:0] OP_NOP  = `BRU_NOP;
  localparam logic [2:0] OP_BR   = `BRU_BR;
  localparam logic [2:0] OP_JAL  = `BRU_JAL;
  localparam logic [2:0] OP_JR   = `BRU_JR;
  localparam logic [2:0] OP_JALR = `BRU_JALR;
  localparam logic [2:0] OP_HALT = `BRU_HALT;

  // El enlace va siempre a R15, que el ISA fija como registro de enlace.
  localparam logic [3:0] REG_LINK = `REG_LINK;

  // ---------------------------------------------------------------------------
  // Causas de falla del registro de estado (isa.md 1.2)
  //
  // La unidad solo puede producir una: opcode invalido. El campo de condicion
  // tiene los ocho valores definidos, asi que nunca puede ser invalido, y el
  // tipo C no tiene bits reservados.
  // ---------------------------------------------------------------------------

  localparam logic [2:0] CAUSE_NONE  = `CAUSE_NONE;
  localparam logic [2:0] CAUSE_ILLOP = `CAUSE_ILLOP;

  // ---------------------------------------------------------------------------
  // Codigos de condicion (isa.md 6)
  //
  // Los ocho valores estan definidos, asi que el campo de condicion nunca
  // puede ser invalido y no hay falla posible por ese lado. Tampoco existe
  // una condicion que nunca se cumpla.
  // ---------------------------------------------------------------------------

  localparam logic [2:0] C_AL   = `COND_AL;
  localparam logic [2:0] C_EQ   = `COND_EQ;
  localparam logic [2:0] C_NE   = `COND_NE;
  localparam logic [2:0] C_LT   = `COND_LT;
  localparam logic [2:0] C_GE   = `COND_GE;
  localparam logic [2:0] C_LTU  = `COND_LTU;
  localparam logic [2:0] C_GEU  = `COND_GEU;
  localparam logic [2:0] C_AUTH = `COND_AUTH;

  // ---------------------------------------------------------------------------
  // Campos del slot
  //
  // El tipo C usa los diez bits bajos completos para el desplazamiento, asi
  // que no tiene ningun bit reservado. El tipo J si tiene seis: el bit 9 y
  // los cinco bajos.
  // ---------------------------------------------------------------------------

  logic [2:0] opcode;
  logic [2:0] cond;
  logic [9:0] desp;
  logic [3:0] rs;

  assign opcode = slot[`S4_OPC];
  assign cond   = slot[`S4_COND];
  assign desp   = slot[`S4_DESP];
  assign rs     = slot[`S4_RS];

  // Los dos campos de abajo se solapan: en el tipo C los diez bits bajos son
  // el desplazamiento, y en el tipo J son el bit reservado 9, el registro en
  // 8:5 y los cinco reservados bajos. Cada forma usa el que le corresponde y
  // el otro queda sin sentido, asi que el multiplexor de destino tiene que
  // elegir bien.
  //
  // La posicion 8:5 del registro es la que isa.md 2.6 fija para todos los
  // formatos cortos, de modo que el decodificador la extrae sin condicion.

  // El indice del registro fuente sale siempre, tambien cuando la condicion
  // no se cumple, porque el datapath necesita leer el registro antes de saber
  // si el salto procede.
  assign rs_idx = rs;

  // ---------------------------------------------------------------------------
  // Destino relativo
  //
  //   PC + 16 * (1 + signext(desp))
  //
  // El desplazamiento se cuenta en bundles y no en bytes, porque todo bundle
  // mide 16 bytes y codificar los cuatro bits bajos seria desperdiciar
  // alcance. De ahi que el producto por 16 sea un corrimiento de cuatro
  // lugares, o sea cableado.
  //
  // El mas uno hace que el desplazamiento se cuente desde el DELAY SLOT y no
  // desde el salto: un desplazamiento de cero apunta al propio delay slot y
  // uno al bundle siguiente. Es el error por uno mas facil de cometer aca.
  //
  // El campo es de 10 bits con signo, o sea 512 bundles hacia atras y 511
  // hacia adelante, unos 8 KB a cada lado.
  // ---------------------------------------------------------------------------

  logic [31:0] desp_ext;
  logic [31:0] target_rel;

  assign desp_ext   = {{22{desp[9]}}, desp};
  assign target_rel = pc + ((desp_ext + 32'd1) << 4);

  // ---------------------------------------------------------------------------
  // Evaluacion de la condicion
  //
  // Las dos condiciones con signo son las unicas que comparan dos banderas
  // entre si: menor que se cumple cuando signo y desbordamiento difieren, que
  // es exactamente un XOR, y mayor o igual es su negacion. Escribirlo de
  // cualquier otra forma, como exigir signo encendida y desbordamiento
  // apagada, falla en dos de las cuatro combinaciones.
  //
  // El case cubre los ocho valores del campo, asi que no hace falta rama por
  // omision.
  // ---------------------------------------------------------------------------

  logic cond_met;

  always_comb begin
    case (cond)
      C_AL:   cond_met = 1'b1;
      C_EQ:   cond_met =   flag_z;
      C_NE:   cond_met =  !flag_z;
      C_LT:   cond_met =   (flag_n ^ flag_v);
      C_GE:   cond_met =  !(flag_n ^ flag_v);
      C_LTU:  cond_met =   flag_c;
      C_GEU:  cond_met =  !flag_c;
      C_AUTH: cond_met =   flag_auth;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Resolucion
  //
  // El destino indirecto es el valor del registro tal cual. El ISA dice
  // PC = R[rs], sin sumas y sin alineacion, asi que la unidad lo pasa entero
  // aunque los bits bajos no sean cero.
  //
  // Las dos formas de salto comparten la evaluacion de la condicion, asi que
  // lo unico que cambia entre ellas es de donde sale el destino.
  // ---------------------------------------------------------------------------

  // Clasificacion por opcode, sin mirar si el slot se emitio ni si fallo. Los
  // chequeos de validez se calculan sobre ella, asi que no puede depender de
  // ellos.
  logic op_is_nop;
  logic op_is_rel;     // formas relativas: BR y JAL
  logic op_is_ind;     // formas indirectas: JR y JALR
  logic op_is_link;    // formas con enlace: JAL y JALR
  logic op_is_halt;
  logic op_is_type_j;  // JR, JALR y HALT
  logic op_defined;

  assign op_is_nop    = (opcode == OP_NOP);
  assign op_is_rel    = (opcode == OP_BR)  || (opcode == OP_JAL);
  assign op_is_ind    = (opcode == OP_JR)  || (opcode == OP_JALR);
  assign op_is_link   = (opcode == OP_JAL) || (opcode == OP_JALR);
  assign op_is_halt   = (opcode == OP_HALT);
  assign op_is_type_j = op_is_ind || op_is_halt;
  assign op_defined   = op_is_nop || op_is_rel || op_is_type_j;

  // ---------------------------------------------------------------------------
  // Falla de opcode
  //
  // Dos condiciones, y ninguna mas:
  //
  //   opcode no definido      los reservados 110 y 111
  //   bits reservados sucios  SOLO en el tipo J, que tiene el bit 9 y los
  //                           cinco bajos
  //
  // El tipo C NO tiene bits reservados: el desplazamiento ocupa los diez bits
  // bajos completos. Aplicarle la regla de reservados haria fallar todo salto
  // de desplazamiento grande, y una prueba con desplazamientos chicos no lo
  // notaria.
  //
  // La operacion nula ignora los campos que no usa. Si levantara falla por
  // ellos, todo bundle que no use este slot fallaria, y como cualquier falla
  // apaga el bit de autenticacion, romperia una sesion de cifrado en curso
  // por un slot que no hace nada.
  // ---------------------------------------------------------------------------

  logic rsv_dirty;
  logic illop;

  assign rsv_dirty = op_is_type_j &&
                     (slot[`S4_J_RSV_HI] || (slot[`S4_J_RSV_LO] != 5'b00000));
  assign illop     = valid && (!op_defined || rsv_dirty);

  assign fault = illop;
  assign cause = illop ? CAUSE_ILLOP : CAUSE_NONE;

  // ---------------------------------------------------------------------------
  // Lo que efectivamente ocurre. Anular es completo: ni salto, ni enlace, ni
  // detencion.
  // ---------------------------------------------------------------------------

  logic is_rel;
  logic is_ind;
  logic is_link;
  logic is_jump;

  assign is_rel  = valid && op_is_rel  && !illop;
  assign is_ind  = valid && op_is_ind  && !illop;
  assign is_link = valid && op_is_link && !illop;
  assign is_jump = is_rel || is_ind;

  assign taken  = is_jump && cond_met;
  assign target = !taken ? 32'd0
                : is_ind ? rs_val
                         : target_rel;

  // ---------------------------------------------------------------------------
  // Enlace de retorno
  //
  // El valor es el contador mas 32 y no mas 16, porque el bundle siguiente es
  // el delay slot y ya se ejecuto: el retorno debe apuntar al bundle
  // posterior a el.
  //
  // El enlace se escribe SOLO si el salto se toma. El ISA dice "R15 <- PC+32;
  // luego salta", y leido literalmente el enlace ocurriria siempre. Esa
  // lectura vuelve destructivo un salto condicional con enlace: si no se
  // toma, pisaria la direccion de retorno del llamador sin haber llamado a
  // nada. Es la decision 2 de docs/spec-bru.md y es una interpretacion, no
  // algo que el ISA fije.
  //
  // El valor sale siempre, tomado o no: lo que el salto gobierna es la
  // escritura. A diferencia de la subllave en la unidad criptografica, el
  // contador mas 32 no es un dato secreto, asi que apagar el valor no
  // agregaria seguridad y solo sumaria logica.
  // ---------------------------------------------------------------------------

  assign link_we  = taken && is_link;
  assign link_idx = REG_LINK;
  assign link_val = pc + 32'd32;

  // ---------------------------------------------------------------------------
  // Detencion
  //
  // El ISA dice textualmente que la detencion "no usa ningun campo salvo el
  // opcode", asi que es INCONDICIONAL: no mira el campo de condicion ni el de
  // registro. Por eso no entra en el multiplexor de salto y no aparece en
  // is_rel ni en is_ind, que es lo que la deja sin tomar salto y sin enlazar.
  //
  // Que hace la unidad de busqueda con esta senal, y si el delay slot se
  // ejecuta despues, queda fuera de este modulo. El ISA no lo dice.
  // ---------------------------------------------------------------------------

  logic is_halt;
  assign is_halt = valid && op_is_halt && !illop;

  assign halt = is_halt;

endmodule
