`timescale 1ns/1ps

// =============================================================================
// dispatch.sv - Etapa ID: rebanado del bundle y enrutado de las lecturas.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Parte el bundle de 128 bits en sus cinco slots y decide QUE REGISTRO lee cada
// uno de los nueve puertos de lectura del banco. Es combinacional: el reparto
// por etapas vive en el datapath.
//
// -----------------------------------------------------------------------------
// POR QUE NO DETECTA FALLAS
// -----------------------------------------------------------------------------
// Puede parecer que la etapa de decodificacion es el lugar natural para
// detectar ILLOP y WCONF, porque las dos salen de los bits de la instruccion.
// Para ILLOP es cierto pero redundante, y para WCONF es directamente
// imposible. Las dos razones conviene dejarlas escritas, porque la tentacion de
// agregar esa logica aqui vuelve cada vez que alguien lee el modulo:
//
// ILLOP ya lo detecta cada unidad funcional, y tiene que detectarlo de todas
// formas: una unidad que recibe un opcode con un campo reservado distinto de
// cero necesita saberlo para anular su propio resultado. alu.sv, lsu.sv,
// short_alu.sv y key_vault.sv lo hacen y lo tienen verificado caso por caso. Si
// esta etapa lo volviera a derivar habria dos implementaciones de la misma
// tabla de campos reservados, que es la clase de duplicacion que se desincroniza
// en el primer cambio del ISA. De hecho ya paso: la version anterior de este
// modulo marcaba los opcodes 10011 y 11011 como ilegales, que era correcto en
// la Entrega 1 y dejo de serlo cuando SETcc y MFPSW los ocuparon en la v1.1.
//
// WCONF no se puede saber aqui, y esto es lo importante. "Dos slots escriben el
// mismo registro" depende de si cada slot ESCRIBE de verdad, y eso no se decide
// en ID:
//
//   - S4 escribe el enlace solo si el salto se toma, y la condicion se evalua
//     contra el PSW en EX.
//   - S2 no escribe si la direccion sale desalineada o fuera de rango, que la
//     LSU calcula en EX.
//   - S3 no escribe el par si la boveda no da permiso, que depende de AUTH,
//     de KVALID y del PC.
//
// Un detector en ID solo puede suponer que todo slot con opcode de escritura va
// a escribir, asi que reportaria WCONF en bundles que nunca llegan a chocar. Un
// falso positivo en el PSW es peor que no reportar nada, porque el programa lo
// consulta con MFPSW y actua sobre el. Por eso WCONF se detecta donde viven los
// habilitadores de escritura reales, ya filtrados por las fallas: en
// psw_fault_unit.sv.
//
// -----------------------------------------------------------------------------
// ENRUTADO DE LOS PUERTOS DE LECTURA
// -----------------------------------------------------------------------------
// El mapa de puertos es el de cerbero_defs.svh y no se repite aqui. Dos casos
// no son el obvio "el puerto A lee rs1":
//
//   MOVH lee rd en el puerto A. La instruccion sobrescribe la mitad alta de rd
//   conservando la baja, asi que necesita el valor actual de rd; su campo rs1
//   esta reservado en cero. Es la unica excepcion del slot ALU y esta
//   documentada igual en la cabecera de alu.sv.
//
//   En S3 el puerto A lee el campo [8:5] para la ALU corta y para las
//   operaciones de boveda, y la mitad L del par para F4E y F4D. Las tres
//   unidades de S3 se excluyen entre si, asi que comparten los dos puertos sin
//   conflicto. El par da dos registros de una vez: Pn = R(2n):R(2n+1), es decir
//   {par,0} para L y {par,1} para R.
//
// Los puertos que una instruccion no usa se dejan apuntando a lo que haya en el
// campo correspondiente en vez de forzarlos a cero. Leer un registro no tiene
// efectos secundarios, el valor simplemente no se consume, y asi el enrutado es
// un multiplexor de un bit en lugar de uno por puerto.
//
// -----------------------------------------------------------------------------
// LO QUE ESTA ETAPA NO PRODUCE
// -----------------------------------------------------------------------------
//   - La senal valid de las unidades: viene de fetch, que es quien sabe si el
//     bundle es real o es el hueco de un salto tomado.
//   - Los indices de ESCRITURA: los publica cada unidad en EX junto con su
//     habilitador, y los registros de segmentacion los llevan hasta WB. Si se
//     derivaran aqui tambien, habria dos fuentes para el mismo numero.
// =============================================================================

`include "cerbero_defs.svh"

module dispatch (
    // Bundle recien salido de la memoria de instrucciones
    input  logic [`BUNDLE_W-1:0] bundle,

    // Slots crudos, uno por unidad funcional
    output logic [31:0]          s0_inst,
    output logic [31:0]          s1_inst,
    output logic [31:0]          s2_inst,
    output logic [15:0]          s3_inst,
    output logic [15:0]          s4_inst,

    // Indices que el banco de registros debe leer, en el orden de los RP_*
    output logic [`NREAD_PORTS-1:0][`RIDX_W-1:0] read_index
);

  // ---------------------------------------------------------------------------
  // Rebanado del bundle
  // ---------------------------------------------------------------------------

  assign s0_inst = bundle[`SLOT_S0];
  assign s1_inst = bundle[`SLOT_S1];
  assign s2_inst = bundle[`SLOT_S2];
  assign s3_inst = bundle[`SLOT_S3];
  assign s4_inst = bundle[`SLOT_S4];

  // ---------------------------------------------------------------------------
  // Campos
  //
  // Todos los recortes de bits se hacen con asignaciones continuas y no dentro
  // de un always_comb: Icarus no soporta recortes constantes dentro de un
  // proceso y los acepta en silencio incluyendo la palabra completa, que es un
  // error que no avisa en simulacion.
  // ---------------------------------------------------------------------------

  logic [4:0] s0_opc, s1_opc;
  logic [3:0] s0_rd, s0_rs1, s0_rs2;
  logic [3:0] s1_rd, s1_rs1, s1_rs2;

  assign s0_opc = s0_inst[`F_OPC];
  assign s0_rd  = s0_inst[`F_RD];
  assign s0_rs1 = s0_inst[`F_RS1];
  assign s0_rs2 = s0_inst[`F_RS2];

  assign s1_opc = s1_inst[`F_OPC];
  assign s1_rd  = s1_inst[`F_RD];
  assign s1_rs1 = s1_inst[`F_RS1];
  assign s1_rs2 = s1_inst[`F_RS2];

  // S2: el campo [26:23] es el destino de un load o la fuente de un store, y en
  // los dos casos lo lee o lo escribe el mismo puerto. [22:19] es la base.
  logic [3:0] s2_dato, s2_rbase;
  assign s2_dato  = s2_inst[`F_RD];
  assign s2_rbase = s2_inst[`F_RS1];

  // S3: opcode de 3 bits, par de 3 bits y el campo de registro principal
  logic [2:0] s3_opc, s3_par;
  logic [3:0] s3_reg, s3_rs2;
  assign s3_opc = s3_inst[`S3_OPC];
  assign s3_par = s3_inst[`S3_PAR];
  assign s3_reg = s3_inst[`S3_RS];      // [8:5], comun a ALU corta y boveda
  assign s3_rs2 = s3_inst[`S3_AC_RS2];  // [3:0], solo con i = 0

  // S4
  logic [3:0] s4_rs;
  assign s4_rs = s4_inst[`S4_RS];

  // ---------------------------------------------------------------------------
  // Enrutado
  // ---------------------------------------------------------------------------

  // MOVH es la unica instruccion del slot ALU cuyo puerto A no lee rs1
  logic s0_es_movh, s1_es_movh;
  assign s0_es_movh = (s0_opc == `ALU_MOVH);
  assign s1_es_movh = (s1_opc == `ALU_MOVH);

  // F4E y F4D son las unicas de S3 que leen un par de registros
  logic s3_es_par;
  assign s3_es_par = (s3_opc == `CRP_F4E) || (s3_opc == `CRP_F4D);

  always_comb begin
    read_index = '0;

    read_index[`RP_S0_A] = s0_es_movh ? s0_rd : s0_rs1;
    read_index[`RP_S0_B] = s0_rs2;

    read_index[`RP_S1_A] = s1_es_movh ? s1_rd : s1_rs1;
    read_index[`RP_S1_B] = s1_rs2;

    read_index[`RP_S2_A] = s2_rbase;
    read_index[`RP_S2_B] = s2_dato;

    read_index[`RP_S3_A] = s3_es_par ? {s3_par, 1'b0} : s3_reg;
    read_index[`RP_S3_B] = s3_es_par ? {s3_par, 1'b1} : s3_rs2;

    read_index[`RP_S4]   = s4_rs;
  end

endmodule
