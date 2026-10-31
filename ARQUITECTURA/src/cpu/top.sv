`timescale 1ns/1ps

// =============================================================================
// top.sv - Procesador CERBERO-1 completo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Conecta las quince unidades en el pipeline de cinco etapas. Casi todo este
// archivo es cableado: cada unidad ya viene verificada por separado, asi que lo
// que puede salir mal aqui no es la logica de ninguna, es conectarlas mal.
//
//   IF    fetch presenta el PC; imem entrega el bundle; su registro de salida
//         es la frontera IF/ID
//   ID    dispatch rebana el bundle y enruta las nueve lecturas; el banco lee
//         en el flanco de bajada; la BRU resuelve el salto
//   EX    las dos ALU, la LSU, la boveda, la unidad de ronda y la ALU corta;
//         dmem toma la direccion y su registro de salida es la frontera EX/MEM
//   MEM   load_align extrae el carril del dato cargado
//   WB    el banco de registros y el PSW escriben en el mismo flanco
//
// -----------------------------------------------------------------------------
// LAS CUATRO RESPONSABILIDADES QUE SON DE ESTE ARCHIVO Y DE NINGUN OTRO
// -----------------------------------------------------------------------------
// Hay cuatro cosas que ninguna unidad puede hacer sola, porque hacen falta dos
// o mas para verlas. Son el verdadero contenido de este modulo y cada una tiene
// su seccion marcada abajo:
//
//   1. GATEAR LA ALU CON valid. alu.sv es la unica unidad funcional sin entrada
//      valid: la LSU, la ALU corta, la boveda y la BRU la tienen y se anulan
//      solas. La ALU no, asi que un bundle que no existe (durante el reset o
//      despues de HALT) tendria una ALU decodificando basura, escribiendo un
//      registro y reportando ILLOP. Se gatea aqui.
//
//   2. EL OPCODE 111 DE S3. El slot S3 lo comparten tres unidades y cada una
//      solo habla por sus propios opcodes: la boveda reconoce 001..101 y la ALU
//      corta solo 110. El 111 esta reservado y nadie lo reclama, asi que sin
//      esta seccion un opcode reservado no haria nada en silencio en vez de
//      registrar ILLOP. key_vault.sv ya lo anticipa en su decision D9: "lo
//      marca como ILLOP quien decodifique S3 completo", y ese es este archivo.
//
//   3. EL REPARTO DE S3. Las tres unidades se excluyen por opcode, pero las dos
//      que escriben comparten puertos del banco: la ALU corta escribe rd por el
//      puerto S3_L y la unidad de ronda escribe las dos mitades del par por
//      S3_L y S3_R. El multiplexor vive aqui.
//
//   4. EL HUECO DEL DATO CARGADO. La frontera EX/MEM lleva los siete puertos de
//      escritura, pero el valor del puerto del destino de la carga no existe
//      todavia en EX. La etapa de memoria lo sustituye por el dato extraido
//      antes de que el banco lo vea.
//
// -----------------------------------------------------------------------------
// POR QUE LA LSU SE INSTANCIA UNA VEZ Y LA EXTRACCION DEL CARRIL OTRA
// -----------------------------------------------------------------------------
// La LSU es la unica unidad que trabaja en dos etapas: la direccion en EX y la
// extraccion del carril en MEM, porque el dato de la memoria no existe hasta
// MEM. La instancia de EX tiene su entrada mem_read_data atada a cero a
// proposito: en EX no hay dato que leer, y conectarle la salida de dmem seria
// mezclar dos bundles distintos, porque esa salida pertenece al bundle que ya
// esta en MEM. Su salida rd_load_data no se usa.
//
// La extraccion de verdad la hace una instancia de load_align en MEM, con el
// slot y los dos bits bajos de la direccion que viajaron por la frontera. Es el
// mismo modulo que la LSU lleva dentro, asi que hay una sola copia de la tabla
// de tamanos y signos.
//
// -----------------------------------------------------------------------------
// COMO SE CARGA UN PROGRAMA
// -----------------------------------------------------------------------------
// Los nombres de archivo entran por MACRO y no por parametro, y el motivo es una
// limitacion de la herramienta: Icarus Verilog 12 no puede pasar un parametro de
// tipo string de un modulo a un submodulo. Un
//
//     parameter string IMEM_FILE = "";
//     imem #(.INIT_FILE (IMEM_FILE)) u_imem (...);
//
// falla en elaboracion con "Unable to bind variable", y tambien falla con el
// parametro sin tipo explicito. Una macro se expande como literal en el sitio
// de la instancia, asi que no cruza ninguna frontera de modulo y funciona.
//
//     make top IMEM=../tb/programa.hex DMEM=../tb/datos.hex
//
// En simulacion los testbenches cargan la memoria por referencia jerarquica, que
// no depende ni de archivos ni de rutas relativas, y es lo que hacen tb_top.sv y
// tb_fetch_flow.sv. Las macros estan para correr un programa de verdad producido
// por la herramienta de carga.
//
// -----------------------------------------------------------------------------
// AUTH NO SE DUPLICA
// -----------------------------------------------------------------------------
// Los bits AUTH y AUTHFAIL del PSW son cables directos desde key_vault, que es
// quien mantiene el estado de sesion y quien implementa el cierre automatico.
// El PSW los refleja sin registrarlos de nuevo. Por eso la regla "cualquier
// falla limpia AUTH" no aparece en este archivo: la cumple la boveda por su
// entrada fault_any, que recibe las fallas de los otros cuatro slots.
// =============================================================================

`include "cerbero_defs.svh"

// Archivos de carga. Ver la nota de arriba: tienen que ser macros.
`ifndef CERBERO_IMEM_FILE
  `define CERBERO_IMEM_FILE ""
`endif
`ifndef CERBERO_DMEM_FILE
  `define CERBERO_DMEM_FILE ""
`endif

module top #(
    parameter int    NUM_BUNDLES = 2048,
    parameter int    NUM_WORDS   = 16384,
    parameter logic [`XLEN-1:0] RESET_PC  = '0,
    // Region segura: el unico rango donde AUTH puede quedar encendido. Se
    // expone como parametro, y no se fija dentro de la boveda, porque el mapa
    // de memoria depende de donde se cargue el programa.
    parameter logic [`XLEN-1:0] SEC_BASE  = `SEC_BASE_DEF,
    parameter logic [`XLEN-1:0] SEC_LIMIT = `SEC_LIMIT_DEF,
    // Secreto de raiz de confianza, contra el que LOGIN compara la credencial
    parameter logic [127:0] ROT_SECRET = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210
) (
    input  logic clk,
    input  logic rst_n,

    // ---- Observacion, para el testbench y para la placa ---------------------
    output logic                          halted,
    output logic [`XLEN-1:0]              psw,
    output logic [`NREGS-1:0][`XLEN-1:0]  dbg_regs
);

  // ===========================================================================
  // ETAPA IF
  // ===========================================================================

  logic             if_valid;
  logic [`XLEN-1:0] if_pc;
  logic             id_taken;
  logic [`XLEN-1:0] id_target;
  logic             id_halt;

  fetch #(.RESET_PC (RESET_PC)) u_fetch (
      .clk    (clk),
      .rst_n  (rst_n),
      .taken  (id_taken),
      .target (id_target),
      .halt   (id_halt),
      .pc     (if_pc),
      .valid  (if_valid),
      .halted (halted)
  );

  logic [`BUNDLE_W-1:0] id_bundle;

  imem #(
      .NUM_BUNDLES (NUM_BUNDLES),
      .INIT_FILE   (`CERBERO_IMEM_FILE)
  ) u_imem (
      .clk    (clk),
      .addr   (if_pc),
      .bundle (id_bundle)
  );

  // Frontera IF/ID. El bundle ya cruzo dentro de imem; aqui cruza lo demas.
  logic             id_valid;
  logic [`XLEN-1:0] id_pc;

  reg_if_id u_if_id (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid_in  (if_valid),
      .pc_in     (if_pc),
      .valid_out (id_valid),
      .pc_out    (id_pc)
  );

  // ===========================================================================
  // ETAPA ID
  // ===========================================================================

  logic [31:0] id_s0, id_s1, id_s2;
  logic [15:0] id_s3, id_s4;
  logic [`NREAD_PORTS-1:0][`RIDX_W-1:0] id_ridx;

  dispatch u_dispatch (
      .bundle     (id_bundle),
      .s0_inst    (id_s0),
      .s1_inst    (id_s1),
      .s2_inst    (id_s2),
      .s3_inst    (id_s3),
      .s4_inst    (id_s4),
      .read_index (id_ridx)
  );

  // Banco de registros: lee en el negedge de ID, escribe en el posedge de WB
  logic [`NREAD_PORTS-1:0][`XLEN-1:0]  id_rval;
  logic                                rf_conflicto;

  logic [`NWRITE_PORTS-1:0]                wb_wen;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   wb_widx;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     wb_wval;

  /* verilator lint_off UNUSEDSIGNAL */
  // El banco publica su propio detector de conflicto. El que llega al PSW lo
  // calcula psw_fault_unit, que excluye los pares intra-slot; tb_wconf.sv
  // comprueba que los dos coinciden salvo por esos pares.
  logic conflicto_del_banco;
  /* verilator lint_on UNUSEDSIGNAL */
  assign conflicto_del_banco = rf_conflicto;

  regfile u_regfile (
      .clk                     (clk),
      .reset_n                 (rst_n),
      .read_register_index     (id_ridx),
      .read_register_value     (id_rval),
      .write_enable            (wb_wen),
      .write_register_index    (wb_widx),
      .write_value             (wb_wval),
      .write_conflict_detected (rf_conflicto),
      .debug_register_values   (dbg_regs)
  );

  // Banderas del PSW, sacadas a senales continuas para no recortar bits dentro
  // de un proceso
  logic psw_z, psw_n, psw_c, psw_v, psw_auth;
  assign psw_z    = psw[`PSW_Z];
  assign psw_n    = psw[`PSW_N];
  assign psw_c    = psw[`PSW_C];
  assign psw_v    = psw[`PSW_V];
  assign psw_auth = psw[`PSW_AUTH];

  // ---------------------------------------------------------------------------
  // Unidad de saltos. Resuelve en ID, que es lo que hace que un solo delay slot
  // alcance, y lee su registro fuente del puerto S4 del banco.
  // ---------------------------------------------------------------------------

  /* verilator lint_off UNUSEDSIGNAL */
  // La BRU publica el indice que necesita leer, igual que la LSU y la ALU
  // corta. Aqui no se usa porque las lecturas las enruta dispatch en ID, que es
  // la etapa donde el banco lee; esta salida existe para que la unidad se pueda
  // probar sola. tb_top.sv comprueba que los dos indices coinciden.
  logic [3:0] bru_rs_idx;
  /* verilator lint_on UNUSEDSIGNAL */

  logic             id_link_we;
  logic [3:0]       id_link_idx;
  logic [`XLEN-1:0] id_link_val;
  logic             id_s4_fault;
  logic [2:0]       id_s4_cause;

  bru u_bru (
      .slot      (id_s4),
      .valid     (id_valid),
      .pc        (id_pc),
      .flag_z    (psw_z),
      .flag_n    (psw_n),
      .flag_c    (psw_c),
      .flag_v    (psw_v),
      .flag_auth (psw_auth),
      .rs_idx    (bru_rs_idx),
      .rs_val    (id_rval[`RP_S4]),
      .taken     (id_taken),
      .target    (id_target),
      .link_we   (id_link_we),
      .link_idx  (id_link_idx),
      .link_val  (id_link_val),
      .halt      (id_halt),
      .fault     (id_s4_fault),
      .cause     (id_s4_cause)
  );

  // Frontera ID/EX
  logic             ex_valid;
  logic [`XLEN-1:0] ex_pc;
  logic [31:0]      ex_s0, ex_s1, ex_s2;
  logic [15:0]      ex_s3;
  /* verilator lint_off UNUSEDSIGNAL */
  // El puerto RP_S4 del banco lo consume la BRU, que trabaja en ID, asi que su
  // valor cruza la frontera ID/EX sin que nadie lo lea en EX. Son 32 biestables
  // de mas, y cruzan igual porque mantener el arreglo de nueve puertos uniforme
  // deja que la salida del registro se conecte directo al reparto de operandos.
  // Es la misma decision que el hueco del dato cargado en la frontera EX/MEM:
  // un caso especial que alguien pueda conectar mal cuesta mas que los
  // biestables.
  logic [`NREAD_PORTS-1:0][`XLEN-1:0] ex_rval;
  /* verilator lint_on UNUSEDSIGNAL */
  logic             ex_link_we;
  logic [3:0]       ex_link_idx;
  logic [`XLEN-1:0] ex_link_val;
  logic             ex_s4_fault;
  logic [2:0]       ex_s4_cause;

  reg_id_ex u_id_ex (
      .clk          (clk),
      .rst_n        (rst_n),
      .valid_in     (id_valid),
      .pc_in        (id_pc),
      .s0_inst_in   (id_s0),
      .s1_inst_in   (id_s1),
      .s2_inst_in   (id_s2),
      .s3_inst_in   (id_s3),
      .rval_in      (id_rval),
      .link_we_in   (id_link_we),
      .link_idx_in  (id_link_idx),
      .link_val_in  (id_link_val),
      .s4_fault_in  (id_s4_fault),
      .s4_cause_in  (id_s4_cause),
      .valid_out    (ex_valid),
      .pc_out       (ex_pc),
      .s0_inst_out  (ex_s0),
      .s1_inst_out  (ex_s1),
      .s2_inst_out  (ex_s2),
      .s3_inst_out  (ex_s3),
      .rval_out     (ex_rval),
      .link_we_out  (ex_link_we),
      .link_idx_out (ex_link_idx),
      .link_val_out (ex_link_val),
      .s4_fault_out (ex_s4_fault),
      .s4_cause_out (ex_s4_cause)
  );

  // ===========================================================================
  // ETAPA EX
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // S0 y S1: las dos ALU
  //
  // RESPONSABILIDAD 1: alu.sv no tiene entrada valid, asi que las tres salidas
  // que tienen efecto se gatean aqui. Sin esto, los bundles que entran durante
  // el reset o despues de HALT escribirian registros y levantarian ILLOP.
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0]   a0_result, a1_result;
  logic [`RIDX_W-1:0] a0_rd, a1_rd;
  logic               a0_we_raw, a1_we_raw;
  logic               a0_fwe_raw, a1_fwe_raw;
  logic [3:0]         a0_flags, a1_flags;
  logic               a0_illop_raw, a1_illop_raw;

  alu #(.IS_SLOT0 (1'b1)) u_alu0 (
      .slot_i     (ex_s0),
      .op_a_i     (ex_rval[`RP_S0_A]),
      .op_b_i     (ex_rval[`RP_S0_B]),
      .psw_i      (psw),
      .result_o   (a0_result),
      .rd_o       (a0_rd),
      .rd_we_o    (a0_we_raw),
      .flags_we_o (a0_fwe_raw),
      .flags_o    (a0_flags),
      .illop_o    (a0_illop_raw)
  );

  /* verilator lint_off UNUSEDSIGNAL */
  // ALU-1 nunca escribe banderas: son exclusivas de S0, y una comparacion
  // codificada en S1 es ILLOP. La salida existe porque las dos instancias son
  // del mismo modulo.
  logic [3:0] a1_flags_sin_uso;
  logic       a1_fwe_sin_uso;
  /* verilator lint_on UNUSEDSIGNAL */
  assign a1_flags_sin_uso = a1_flags;
  assign a1_fwe_sin_uso   = a1_fwe_raw;

  alu #(.IS_SLOT0 (1'b0)) u_alu1 (
      .slot_i     (ex_s1),
      .op_a_i     (ex_rval[`RP_S1_A]),
      .op_b_i     (ex_rval[`RP_S1_B]),
      .psw_i      (psw),
      .result_o   (a1_result),
      .rd_o       (a1_rd),
      .rd_we_o    (a1_we_raw),
      .flags_we_o (a1_fwe_raw),
      .flags_o    (a1_flags),
      .illop_o    (a1_illop_raw)
  );

  logic a0_we, a1_we, a0_fwe, a0_illop, a1_illop;

  assign a0_we    = ex_valid && a0_we_raw;
  assign a1_we    = ex_valid && a1_we_raw;
  assign a0_fwe   = ex_valid && a0_fwe_raw;
  assign a0_illop = ex_valid && a0_illop_raw;
  assign a1_illop = ex_valid && a1_illop_raw;

  // ---------------------------------------------------------------------------
  // S2: acceso a memoria
  //
  // La entrada mem_read_data va en cero: en EX no hay dato que leer. La
  // extraccion del carril la hace una instancia de load_align en MEM.
  // ---------------------------------------------------------------------------

  logic [3:0]       lsu_rd_idx, lsu_rbase_idx;
  logic [`XLEN-1:0] lsu_eff_addr, lsu_wdata, lsu_rbase_upd;
  logic             lsu_mem_we, lsu_rd_we, lsu_rbase_we, lsu_fault;
  logic [3:0]       lsu_be;
  logic [2:0]       lsu_cause;

  /* verilator lint_off UNUSEDSIGNAL */
  // La instancia de EX no extrae carriles; su salida de dato queda sin usar.
  logic [`XLEN-1:0] lsu_load_sin_uso;
  /* verilator lint_on UNUSEDSIGNAL */

  lsu u_lsu (
      .slot           (ex_s2),
      .valid          (ex_valid),
      .rd_idx         (lsu_rd_idx),
      .rbase_idx      (lsu_rbase_idx),
      .rbase_val      (ex_rval[`RP_S2_A]),
      .rs_data_val    (ex_rval[`RP_S2_B]),
      .eff_addr       (lsu_eff_addr),
      .mem_write_data (lsu_wdata),
      .mem_we         (lsu_mem_we),
      .byte_enable    (lsu_be),
      .mem_read_data  ({`XLEN{1'b0}}),
      .rd_write_en    (lsu_rd_we),
      .rd_load_data   (lsu_load_sin_uso),
      .rbase_write_en (lsu_rbase_we),
      .rbase_updated  (lsu_rbase_upd),
      .fault          (lsu_fault),
      .cause          (lsu_cause)
  );

  // ---------------------------------------------------------------------------
  // S3: boveda, ronda Feistel4 y ALU corta
  //
  // RESPONSABILIDAD 2: el opcode reservado 111.
  // RESPONSABILIDAD 3: el reparto de los puertos de escritura.
  // ---------------------------------------------------------------------------

  logic [2:0] ex_s3_opc;
  assign ex_s3_opc = ex_s3[`S3_OPC];

  logic s3_es_salu, s3_es_reservado;
  assign s3_es_salu      = (ex_s3_opc == `CRP_SALU);
  assign s3_es_reservado = ex_valid && (ex_s3_opc == `CRP_RSV);

  // La boveda necesita saber si fallo otro slot del mismo bundle, para el
  // cierre automatico de sesion. Entra todo menos su propia falla, que ella
  // misma considera, y por eso no hay lazo combinacional.
  logic s3_otros_fallan;

  logic [`XLEN-1:0] kv_subkey;
  logic             kv_grant, kv_fault, kv_auth, kv_authfail;
  logic [2:0]       kv_cause;

  /* verilator lint_off UNUSEDSIGNAL */
  // El estado de las ranuras no es dato secreto y sirve para depurar, pero
  // ninguna otra unidad lo consume.
  logic [3:0] kv_kvalid;
  /* verilator lint_on UNUSEDSIGNAL */

  key_vault #(
      .ROT_SECRET_INIT (ROT_SECRET),
      .SEC_BASE        (SEC_BASE),
      .SEC_LIMIT       (SEC_LIMIT)
  ) u_key_vault (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid     (ex_valid),
      .slot      (ex_s3),
      .rs_data   (ex_rval[`RP_S3_A]),
      .pc        (ex_pc),
      .fault_any (s3_otros_fallan),
      .subkey    (kv_subkey),
      .grant     (kv_grant),
      .fault     (kv_fault),
      .cause     (kv_cause),
      .auth      (kv_auth),
      .authfail  (kv_authfail),
      .kvalid    (kv_kvalid)
  );

  logic [3:0]       cu_l_idx, cu_r_idx;
  logic             cu_we;
  logic [`XLEN-1:0] cu_l_new, cu_r_new;

  crypto_unit u_crypto (
      .slot   (ex_s3),
      .grant  (kv_grant),
      .subkey (kv_subkey),
      .l_val  (ex_rval[`RP_S3_A]),
      .r_val  (ex_rval[`RP_S3_B]),
      .l_idx  (cu_l_idx),
      .r_idx  (cu_r_idx),
      .wr_en  (cu_we),
      .l_new  (cu_l_new),
      .r_new  (cu_r_new)
  );

  logic [3:0]       sa_rd_idx;
  logic             sa_we, sa_fault;
  logic [`XLEN-1:0] sa_result;
  logic [2:0]       sa_cause;

  /* verilator lint_off UNUSEDSIGNAL */
  // Igual que en la BRU: la ALU corta publica el indice de su segundo operando,
  // pero la lectura la enruta dispatch en ID.
  logic [3:0] sa_rs2_idx;
  /* verilator lint_on UNUSEDSIGNAL */

  short_alu u_short_alu (
      .slot     (ex_s3),
      .valid    (ex_valid),
      .rd_idx   (sa_rd_idx),
      .rs2_idx  (sa_rs2_idx),
      .rd_val   (ex_rval[`RP_S3_A]),
      .rs2_val  (ex_rval[`RP_S3_B]),
      .wr_en    (sa_we),
      .result   (sa_result),
      .fault    (sa_fault),
      .cause    (sa_cause)
  );

  // Falla de S3: las tres unidades se excluyen por opcode, asi que a lo sumo
  // una dispara. El opcode reservado lo marca este archivo.
  logic       s3_fault;
  logic [2:0] s3_cause;

  assign s3_fault = kv_fault || sa_fault || s3_es_reservado;
  assign s3_cause = kv_fault ? kv_cause :
                    sa_fault ? sa_cause : `CAUSE_ILLOP;

  assign s3_otros_fallan = a0_illop || a1_illop || lsu_fault ||
                           sa_fault || s3_es_reservado || ex_s4_fault;

  // ---------------------------------------------------------------------------
  // Memoria de datos. La direccion, el dato y la mascara se presentan
  // combinacionalmente durante EX; el registro de salida es la frontera EX/MEM.
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] mem_rdata;

  dmem #(
      .NUM_WORDS (NUM_WORDS),
      .INIT_FILE (`CERBERO_DMEM_FILE)
  ) u_dmem (
      .clk         (clk),
      .addr        (lsu_eff_addr),
      .we          (lsu_mem_we),
      .byte_enable (lsu_be),
      .wdata       (lsu_wdata),
      .rdata       (mem_rdata)
  );

  // ---------------------------------------------------------------------------
  // Los siete puertos de escritura, tal como salen de EX
  //
  // El orden es el de los WP_*, y ese orden ES la prioridad ante un conflicto.
  // El valor del puerto del destino de la carga va en cero: todavia no existe,
  // y MEM lo sustituye.
  // ---------------------------------------------------------------------------

  logic [`NWRITE_PORTS-1:0]                ex_wen;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   ex_widx;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     ex_wval;

  always_comb begin
    ex_wen  = '0;
    ex_widx = '0;
    ex_wval = '0;

    // S0
    ex_wen [`WP_S0] = a0_we;
    ex_widx[`WP_S0] = a0_rd;
    ex_wval[`WP_S0] = a0_result;

    // S1
    ex_wen [`WP_S1] = a1_we;
    ex_widx[`WP_S1] = a1_rd;
    ex_wval[`WP_S1] = a1_result;

    // S2: destino de la carga, con el valor pendiente hasta MEM
    ex_wen [`WP_S2_RD] = lsu_rd_we;
    ex_widx[`WP_S2_RD] = lsu_rd_idx;

    // S2: registro base de una variante .INC
    ex_wen [`WP_S2_BASE] = lsu_rbase_we;
    ex_widx[`WP_S2_BASE] = lsu_rbase_idx;
    ex_wval[`WP_S2_BASE] = lsu_rbase_upd;

    // S3: la ALU corta escribe rd; la ronda escribe las dos mitades del par
    ex_wen [`WP_S3_L] = s3_es_salu ? sa_we     : cu_we;
    ex_widx[`WP_S3_L] = s3_es_salu ? sa_rd_idx : cu_l_idx;
    ex_wval[`WP_S3_L] = s3_es_salu ? sa_result : cu_l_new;

    ex_wen [`WP_S3_R] = !s3_es_salu && cu_we;
    ex_widx[`WP_S3_R] = cu_r_idx;
    ex_wval[`WP_S3_R] = cu_r_new;

    // S4: enlace de retorno, calculado en ID y retrasado hasta aqui
    ex_wen [`WP_S4_LINK] = ex_link_we;
    ex_widx[`WP_S4_LINK] = ex_link_idx;
    ex_wval[`WP_S4_LINK] = ex_link_val;
  end

  // Las cinco fallas, en orden S0..S4
  logic [4:0]      ex_fault;
  logic [4:0][2:0] ex_cause;

  always_comb begin
    ex_fault = 5'd0;
    ex_cause = '0;

    ex_fault[0] = a0_illop;
    ex_cause[0] = a0_illop ? `CAUSE_ILLOP : `CAUSE_NONE;

    ex_fault[1] = a1_illop;
    ex_cause[1] = a1_illop ? `CAUSE_ILLOP : `CAUSE_NONE;

    ex_fault[2] = lsu_fault;
    ex_cause[2] = lsu_cause;

    ex_fault[3] = s3_fault;
    ex_cause[3] = s3_cause;

    ex_fault[4] = ex_s4_fault;
    ex_cause[4] = ex_s4_cause;
  end

  logic [1:0] ex_addr_lo;
  assign ex_addr_lo = lsu_eff_addr[1:0];

  // Frontera EX/MEM
  logic             mem_valid;
  logic [31:0]      mem_s2;
  logic [1:0]       mem_addr_lo;
  logic [`NWRITE_PORTS-1:0]                mem_wen;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   mem_widx;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     mem_wval;
  logic [4:0]       mem_fault;
  logic [4:0][2:0]  mem_cause;
  logic             mem_flags_we;
  logic [3:0]       mem_flags;

  /* verilator lint_off UNUSEDSIGNAL */
  // En MEM no hay unidad que consuma valid: los habilitadores de escritura ya
  // vienen filtrados desde EX. Cruza para que la forma de onda diga a que
  // bundle pertenece cada ciclo de MEM.
  logic mem_valid_sin_uso;
  /* verilator lint_on UNUSEDSIGNAL */
  assign mem_valid_sin_uso = mem_valid;

  reg_ex_mem u_ex_mem (
      .clk              (clk),
      .rst_n            (rst_n),
      .valid_in         (ex_valid),
      .s2_inst_in       (ex_s2),
      .addr_lo_in       (ex_addr_lo),
      .write_enable_in  (ex_wen),
      .write_index_in   (ex_widx),
      .write_value_in   (ex_wval),
      .fault_in         (ex_fault),
      .cause_in         (ex_cause),
      .flags_we_in      (a0_fwe),
      .flags_in         (a0_flags),
      .valid_out        (mem_valid),
      .s2_inst_out      (mem_s2),
      .addr_lo_out      (mem_addr_lo),
      .write_enable_out (mem_wen),
      .write_index_out  (mem_widx),
      .write_value_out  (mem_wval),
      .fault_out        (mem_fault),
      .cause_out        (mem_cause),
      .flags_we_out     (mem_flags_we),
      .flags_out        (mem_flags)
  );

  // ===========================================================================
  // ETAPA MEM
  //
  // RESPONSABILIDAD 4: sustituir el valor del puerto del destino de la carga.
  // ===========================================================================

  logic [`XLEN-1:0] mem_load_data;

  load_align u_load_align (
      .slot          (mem_s2),
      .addr_lo       (mem_addr_lo),
      .rd_write_en   (mem_wen[`WP_S2_RD]),
      .mem_read_data (mem_rdata),
      .rd_load_data  (mem_load_data)
  );

  integer p;

  always_comb begin
    wb_wen  = mem_wen;
    wb_widx = mem_widx;
    for (p = 0; p < `NWRITE_PORTS; p = p + 1)
      wb_wval[p] = mem_wval[p];
    wb_wval[`WP_S2_RD] = mem_load_data;
  end

  // ===========================================================================
  // ETAPA WB
  //
  // El banco de registros ya esta arriba: escribe con wb_wen, wb_widx y
  // wb_wval en el flanco que abre WB. El PSW escribe en el mismo flanco, y por
  // eso no hace falta un registro MEM/WB: los biestables de los dos modulos
  // SON esa frontera.
  // ===========================================================================

  /* verilator lint_off UNUSEDSIGNAL */
  logic psw_wconf;
  /* verilator lint_on UNUSEDSIGNAL */

  psw_fault_unit u_psw (
      .clk          (clk),
      .rst_n        (rst_n),
      .flags_we     (mem_flags_we),
      .flags        (mem_flags),
      .auth         (kv_auth),
      .authfail     (kv_authfail),
      .s0_fault     (mem_fault[0]), .s0_cause (mem_cause[0]),
      .s1_fault     (mem_fault[1]), .s1_cause (mem_cause[1]),
      .s2_fault     (mem_fault[2]), .s2_cause (mem_cause[2]),
      .s3_fault     (mem_fault[3]), .s3_cause (mem_cause[3]),
      .s4_fault     (mem_fault[4]), .s4_cause (mem_cause[4]),
      .write_enable (wb_wen),
      .write_index  (wb_widx),
      .psw          (psw),
      .wconf_any    (psw_wconf)
  );

endmodule
