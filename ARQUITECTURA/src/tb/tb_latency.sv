`timescale 1ns/1ps

// =============================================================================
// tb_latency.sv - Medicion de la latencia expuesta del banco de registros.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// La seccion 9 del ISA promete una latencia uniforme de 3 bundles, y ese
// numero es el contrato con el grupo de CE1108: su generador de codigo separa
// productor y consumidor contando bundles. Si el hardware diera 4, todo el
// codigo que ellos generen estaria mal calendarizado.
//
// tb_regfile.sv ya comprueba la propiedad local, que una escritura del posedge
// se lee en el negedge del mismo ciclo. Este testbench va un paso mas: monta
// el modelo de temporizacion del pipeline completo y MIDE cuantos bundles de
// separacion hacen falta, en vez de darlos por supuestos.
//
// -----------------------------------------------------------------------------
// EL MODELO
// -----------------------------------------------------------------------------
//   bundle n   IF en el ciclo n, y su WB en el ciclo n+4, donde escribe el
//              banco en el flanco de subida
//   bundle m   ID en el ciclo m+1, donde lee el banco en el flanco de bajada;
//              el registro de segmentacion ID/EX captura ese valor en el
//              flanco de subida del ciclo m+2, y EX lo usa despues
//
// El testbench instancia el banco real y un registro ID/EX, escribe un valor
// nuevo en el WB de un bundle conocido y recorre los bundles consumidores
// buscando el primero cuyo operando en EX ya trae el valor nuevo. La distancia
// entre los dos es la latencia expuesta.
//
// Que el resultado se MIDA y no se afirme es lo que hace util al caso: si
// alguien cambiara la convencion de flancos del banco, aqui saldria 4 y el
// make se detendria, en vez de que el problema apareciera en el primer
// programa que corra el grupo de CE1108.
// =============================================================================

`include "cerbero_defs.svh"

module tb_latency;

  // ---------------------------------------------------------------------------
  // Reloj e interfaz del banco
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                             reset_n;
  logic [`NREAD_PORTS-1:0][3:0]     ridx;
  logic [`NREAD_PORTS-1:0][31:0]    rval;
  logic [`NWRITE_PORTS-1:0]         wen;
  logic [`NWRITE_PORTS-1:0][3:0]    widx;
  logic [`NWRITE_PORTS-1:0][31:0]   wval;
  logic                             conflicto;
  logic [`NREGS-1:0][31:0]          dbg;

  regfile dut (
      .clk                     (clk),
      .reset_n                 (reset_n),
      .read_register_index     (ridx),
      .read_register_value     (rval),
      .write_enable            (wen),
      .write_register_index    (widx),
      .write_value             (wval),
      .write_conflict_detected (conflicto),
      .debug_register_values   (dbg)
  );

  // El registro de segmentacion ID/EX, que es quien de verdad le entrega el
  // operando a la unidad funcional.
  logic [31:0] id_ex;
  always_ff @(posedge clk) id_ex <= rval[`RP_S0_A];

  // ---------------------------------------------------------------------------
  // Parametros del experimento
  // ---------------------------------------------------------------------------

  localparam logic [31:0] VIEJO     = 32'hAAAA_AAAA;
  localparam logic [31:0] NUEVO     = 32'h0BAD_C0DE;
  localparam int          CICLO_WB  = 10;             // WB del productor
  localparam int          PRODUCTOR = CICLO_WB - 4;   // bundle n
  localparam int          ESPERADA  = 3;              // lo que promete el ISA

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check_int(input string  nombre,
                           input integer obtenido,
                           input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-44s obtenido %0d, esperado %0d",
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

  integer c, m;
  integer primer_m = -1;
  integer ultimo_viejo = -1;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_latency.vcd");
      $dumpvars(0, tb_latency);
    end

    ridx = '0; wen = '0; widx = '0; wval = '0;
    reset_n = 1'b0;
    repeat (2) @(posedge clk);
    #1 reset_n = 1'b1;

    // Valor de partida en R5, que es el que se va a leer
    @(negedge clk);
    wen = '0;
    wen[`WP_S0]  = 1'b1;
    widx[`WP_S0] = 4'd5;
    wval[`WP_S0] = VIEJO;
    ridx[`RP_S0_A] = 4'd5;
    @(posedge clk);
    #1 wen = '0;

    $display("=== tb_latency: latencia expuesta del banco de registros ===");
    $display("");
    $display("productor: bundle %0d, escribe en WB durante el ciclo %0d",
             PRODUCTOR, CICLO_WB);
    $display("");
    $display("  bundle m | ID en ciclo | operando en EX | separacion");
    $display("  ---------+-------------+----------------+-----------");

    for (c = 3; c <= CICLO_WB + 4; c = c + 1) begin
      @(negedge clk);
      wen = '0;
      if (c == CICLO_WB) begin
        wen[`WP_S0]  = 1'b1;              // el WB del bundle productor
        widx[`WP_S0] = 4'd5;
        wval[`WP_S0] = NUEVO;
      end
      @(posedge clk);
      #1;

      // En el posedge del ciclo c, ID/EX captura lo que ID leyo en el negedge
      // del ciclo c-1. Ese ID pertenece al bundle m = c - 2.
      m = c - 2;
      if (m >= PRODUCTOR) begin
        $display("  %8d | %11d | %08h       | %0d%s",
                 m, m + 1, id_ex, m - PRODUCTOR,
                 (id_ex === NUEVO && primer_m < 0) ? "   <-- el primero" : "");
        if (id_ex === NUEVO && primer_m < 0)  primer_m     = m;
        if (id_ex === VIEJO)                  ultimo_viejo = m;
      end
    end

    $display("");

    // ------------------------------------------------------------------------
    // Lo que se comprueba
    // ------------------------------------------------------------------------

    // 1. Algun bundle tiene que haber visto el valor nuevo. Si ninguno lo vio,
    //    el banco no esta escribiendo o no esta leyendo.
    tests_run = tests_run + 1;
    if (primer_m < 0) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  ningun bundle recibio el valor nuevo");
    end else begin
      $display("  ok     algun bundle recibio el valor nuevo");
    end

    if (primer_m >= 0) begin
      // 2. La latencia medida es la que promete el ISA.
      check_int("la latencia expuesta medida es la del ISA",
                primer_m - PRODUCTOR, ESPERADA);

      // 3. El bundle inmediatamente anterior todavia ve el valor viejo. Sin
      //    esta mitad, un banco que escribiera un ciclo antes de tiempo
      //    pasaria igual: daria el valor nuevo demasiado pronto y la prueba
      //    no lo notaria.
      check_int("el bundle anterior todavia ve el valor viejo",
                ultimo_viejo, primer_m - 1);
    end

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
