`timescale 1ns/1ps

// =============================================================================
// tb_pipeline.sv - Medicion de la latencia expuesta sobre la cadena real.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// tb_latency.sv mide los 3 bundles con el banco de registros y un registro
// ID/EX de juguete escrito dentro del propio testbench. Esto es lo mismo pero
// con la cadena de verdad: reg_if_id, el banco, reg_id_ex y reg_ex_mem
// conectados como van a quedar en el datapath, con las escrituras pasando por
// el registro EX/MEM antes de llegar al banco.
//
// La pregunta que responde es si la cadena agrega un ciclo. Cada registro por
// separado ya se comprobo que retrasa exactamente uno, pero lo que el ISA
// promete al grupo de CE1108 no es el retraso de un registro: es el numero de
// bundles que hay que dejar entre un productor y su consumidor. Ese numero sale
// de donde esta cada registro respecto de los flancos del banco, y es lo que se
// mide aqui.
//
// -----------------------------------------------------------------------------
// EL MODELO DE TIEMPO
// -----------------------------------------------------------------------------
// Un bundle n recorre: IF en el ciclo n, ID en n+1, EX en n+2, MEM en n+3 y WB
// en n+4. En cada ciclo c el testbench presenta a la vez lo que le toca a tres
// bundles distintos, que es justo lo que hace un pipeline lleno:
//
//   IF del bundle c      el PC que entra a reg_if_id
//   ID del bundle c-1    los indices de lectura del banco
//   EX del bundle c-2    los puertos de escritura, que entran a reg_ex_mem
//
// Despues del flanco de subida que cierra el ciclo c:
//
//   reg_if_id.pc_out  trae el PC del bundle c, que entra a ID en c+1
//   reg_id_ex.pc_out  trae el PC del bundle c-1, que entra a EX en c+1
//   reg_id_ex.rval    trae el operando que el banco leyo en el negedge de c,
//                     que pertenece al bundle c-1
//
// Y una escritura presentada en el ciclo c sale de reg_ex_mem durante c+1, con
// lo que el banco la toma en el flanco que cierra c+1. Para el bundle n = c-2
// eso es el flanco que abre el ciclo n+4, o sea su WB. La cuenta cierra.
//
// -----------------------------------------------------------------------------
// LO QUE SE MIDE Y NO SE SUPONE
// -----------------------------------------------------------------------------
// El bundle 0 escribe un valor viejo y el bundle 5 escribe uno nuevo. El
// testbench recorre los bundles consumidores y busca el PRIMERO cuyo operando en
// EX ya trae el valor nuevo. La distancia hasta el bundle 5 es la latencia
// expuesta, y tiene que dar 3.
//
// Tambien se comprueba la mitad de abajo: que el bundle anterior todavia vea el
// valor viejo. Sin ella, una cadena que entregara el dato demasiado pronto
// pasaria igual, y eso seria un hardware mas permisivo que el documento.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_pipeline;

  localparam logic [`XLEN-1:0] PC0       = 32'h0000_1000;
  localparam logic [`XLEN-1:0] VIEJO     = 32'hAAAA_AAAA;
  localparam logic [`XLEN-1:0] NUEVO     = 32'h0BAD_C0DE;
  localparam int               REG       = 5;      // registro observado
  localparam int               PROD_VIEJO = 0;     // bundle que escribe VIEJO
  localparam int               PRODUCTOR  = 5;     // bundle que escribe NUEVO
  localparam int               ESPERADA   = 3;     // lo que promete el ISA
  localparam int               CICLO_FIN  = 14;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // ---------------------------------------------------------------------------
  // Frontera IF/ID
  // ---------------------------------------------------------------------------

  logic             valid_if;
  logic [`XLEN-1:0] pc_if;
  logic             valid_id;
  logic [`XLEN-1:0] pc_id;

  reg_if_id u_if_id (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid_in  (valid_if),
      .pc_in     (pc_if),
      .valid_out (valid_id),
      .pc_out    (pc_id)
  );

  // ---------------------------------------------------------------------------
  // Banco de registros
  //
  // Lee en el negedge de ID y escribe en el posedge, con los puertos que le
  // entrega reg_ex_mem.
  // ---------------------------------------------------------------------------

  logic [`NREAD_PORTS-1:0][`RIDX_W-1:0] ridx;
  logic [`NREAD_PORTS-1:0][`XLEN-1:0]   rval;
  logic                                 conflicto;
  logic [`NREGS-1:0][`XLEN-1:0]         dbg;

  logic [`NWRITE_PORTS-1:0]                wen_wb;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   widx_wb;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     wval_wb;

  regfile u_rf (
      .clk                     (clk),
      .reset_n                 (rst_n),
      .read_register_index     (ridx),
      .read_register_value     (rval),
      .write_enable            (wen_wb),
      .write_register_index    (widx_wb),
      .write_value             (wval_wb),
      .write_conflict_detected (conflicto),
      .debug_register_values   (dbg)
  );

  // ---------------------------------------------------------------------------
  // Frontera ID/EX
  // ---------------------------------------------------------------------------

  logic [`NREAD_PORTS-1:0][`XLEN-1:0] rval_ex;
  logic                               valid_ex;
  logic [`XLEN-1:0]                   pc_ex;
  logic [31:0]                        s0_ex, s1_ex, s2_ex;
  logic [15:0]                        s3_ex;
  logic                               link_we_ex;
  logic [`RIDX_W-1:0]                 link_idx_ex;
  logic [`XLEN-1:0]                   link_val_ex;
  logic                               s4_fault_ex;
  logic [2:0]                         s4_cause_ex;

  reg_id_ex u_id_ex (
      .clk          (clk),
      .rst_n        (rst_n),
      .valid_in     (valid_id),
      .pc_in        (pc_id),
      .s0_inst_in   (32'd0),
      .s1_inst_in   (32'd0),
      .s2_inst_in   (32'd0),
      .s3_inst_in   (16'd0),
      .rval_in      (rval),
      .link_we_in   (1'b0),
      .link_idx_in  ('0),
      .link_val_in  ('0),
      .s4_fault_in  (1'b0),
      .s4_cause_in  (`CAUSE_NONE),
      .valid_out    (valid_ex),
      .pc_out       (pc_ex),
      .s0_inst_out  (s0_ex),
      .s1_inst_out  (s1_ex),
      .s2_inst_out  (s2_ex),
      .s3_inst_out  (s3_ex),
      .rval_out     (rval_ex),
      .link_we_out  (link_we_ex),
      .link_idx_out (link_idx_ex),
      .link_val_out (link_val_ex),
      .s4_fault_out (s4_fault_ex),
      .s4_cause_out (s4_cause_ex)
  );

  // ---------------------------------------------------------------------------
  // Frontera EX/MEM
  //
  // Las escrituras que se presentan en EX salen de aqui durante MEM y el banco
  // las toma en el flanco que abre WB. No hay registro MEM/WB: los biestables
  // del banco son esa frontera.
  // ---------------------------------------------------------------------------

  logic [`NWRITE_PORTS-1:0]                wen_ex;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   widx_ex;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     wval_ex;

  logic             valid_mem;
  logic [31:0]      s2_mem;
  logic [1:0]       addr_lo_mem;
  logic [4:0]       fault_mem;
  logic [4:0][2:0]  cause_mem;
  logic             flags_we_mem;
  logic [3:0]       flags_mem;

  reg_ex_mem u_ex_mem (
      .clk              (clk),
      .rst_n            (rst_n),
      .valid_in         (valid_ex),
      .s2_inst_in       (s2_ex),
      .addr_lo_in       (2'd0),
      .write_enable_in  (wen_ex),
      .write_index_in   (widx_ex),
      .write_value_in   (wval_ex),
      .fault_in         (5'd0),
      .cause_in         ('0),
      .flags_we_in      (1'b0),
      .flags_in         (4'd0),
      .valid_out        (valid_mem),
      .s2_inst_out      (s2_mem),
      .addr_lo_out      (addr_lo_mem),
      .write_enable_out (wen_wb),
      .write_index_out  (widx_wb),
      .write_value_out  (wval_wb),
      .fault_out        (fault_mem),
      .cause_out        (cause_mem),
      .flags_we_out     (flags_we_mem),
      .flags_out        (flags_mem)
  );

  // ---------------------------------------------------------------------------
  // Comprobaciones
  // ---------------------------------------------------------------------------

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check_int(input string  nombre,
                           input integer obtenido,
                           input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %0d, esperado %0d",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  task automatic resumen();
    begin
      $display("---");
      $display("casos: %0d   fallidos: %0d", tests_run, tests_failed);
      if (tests_failed != 0) begin
        $display("RESULTADO: FALLA");
        $fatal(1, "%0d caso(s) fallaron", tests_failed);
      end
      $display("RESULTADO: OK");
      $finish;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer c, m, n;
  integer primer_m     = -1;
  integer ultimo_viejo = -1;
  integer malos_pc_id  = 0;
  integer malos_pc_ex  = 0;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_pipeline.vcd");
      $dumpvars(0, tb_pipeline);
    end

    valid_if = 1'b0;
    pc_if    = '0;
    ridx     = '0;
    wen_ex   = '0;
    widx_ex  = '0;
    wval_ex  = '0;

    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;

    $display("=== tb_pipeline: latencia expuesta sobre la cadena real ===");
    $display("");
    $display("el bundle %0d escribe %08h, el bundle %0d escribe %08h",
             PROD_VIEJO, VIEJO, PRODUCTOR, NUEVO);
    $display("");
    $display("  bundle m | EX en ciclo | operando en EX | separacion");
    $display("  ---------+-------------+----------------+-----------");

    for (c = 0; c <= CICLO_FIN; c = c + 1) begin
      @(negedge clk);
      #1;

      // --- IF del bundle c ---
      valid_if = 1'b1;
      pc_if    = PC0 + (c * 16);

      // --- ID del bundle c-1: todos leen el mismo registro ---
      ridx               = '0;
      ridx[`RP_S0_A]     = REG[`RIDX_W-1:0];

      // --- EX del bundle c-2: escrituras ---
      n       = c - 2;
      wen_ex  = '0;
      widx_ex = '0;
      wval_ex = '0;
      if (n == PROD_VIEJO) begin
        wen_ex[`WP_S0]  = 1'b1;
        widx_ex[`WP_S0] = REG[`RIDX_W-1:0];
        wval_ex[`WP_S0] = VIEJO;
      end else if (n == PRODUCTOR) begin
        wen_ex[`WP_S0]  = 1'b1;
        widx_ex[`WP_S0] = REG[`RIDX_W-1:0];
        wval_ex[`WP_S0] = NUEVO;
      end

      @(posedge clk);
      #1;

      // --- Lo que quedo en los registros ---
      // El PC que va a ver ID en el ciclo siguiente pertenece al bundle c
      if (pc_id !== (PC0 + (c * 16))) malos_pc_id = malos_pc_id + 1;

      // El PC que va a ver EX pertenece al bundle c-1
      if (c >= 1)
        if (pc_ex !== (PC0 + ((c - 1) * 16))) malos_pc_ex = malos_pc_ex + 1;

      // El operando que va a consumir EX pertenece al bundle c-1
      m = c - 1;
      if (m >= PRODUCTOR - 2) begin
        $display("  %8d | %11d | %08h       | %0d%s",
                 m, m + 2, rval_ex[`RP_S0_A], m - PRODUCTOR,
                 (rval_ex[`RP_S0_A] === NUEVO && primer_m < 0)
                   ? "   <-- el primero" : "");
        if (rval_ex[`RP_S0_A] === NUEVO && primer_m < 0) primer_m     = m;
        if (rval_ex[`RP_S0_A] === VIEJO)                 ultimo_viejo = m;
      end
    end

    $display("");

    // ------------------------------------------------------------------------
    // Lo que se comprueba
    // ------------------------------------------------------------------------

    // 1. La cadena entrega el valor nuevo en algun momento. Si no, algo de la
    //    cadena no esta conectado.
    tests_run = tests_run + 1;
    if (primer_m < 0) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  ningun bundle recibio el valor nuevo");
    end else begin
      $display("  ok     algun bundle recibio el valor nuevo");
    end

    if (primer_m >= 0) begin
      // 2. La latencia medida sobre la cadena real es la que promete el ISA
      check_int("la latencia expuesta de la cadena es la del ISA",
                primer_m - PRODUCTOR, ESPERADA);

      // 3. El bundle anterior todavia ve el valor viejo. Sin esta mitad, una
      //    cadena que entregara el dato un ciclo antes pasaria igual.
      check_int("el bundle anterior todavia ve el valor viejo",
                ultimo_viejo, primer_m - 1);
    end

    // 4. El PC acompana al bundle en las dos etapas que lo consumen. La BRU lo
    //    usa en ID para calcular el destino y la boveda en EX para el cierre
    //    automatico de sesion.
    check_int("el PC llega correcto a decodificacion", malos_pc_id, 0);
    check_int("el PC llega correcto a ejecucion",      malos_pc_ex, 0);

    // 5. La cadena no reporta conflictos: solo escribe un puerto por ciclo
    check_int("sin conflictos de escritura en la corrida", conflicto, 0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
