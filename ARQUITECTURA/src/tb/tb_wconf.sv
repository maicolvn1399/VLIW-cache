`timescale 1ns/1ps

// =============================================================================
// tb_wconf.sv - Cosimulacion de los dos detectores de conflicto de escritura.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// En el diseno hay dos implementaciones independientes de "dos puertos
// escriben el mismo registro", escritas por personas distintas y con
// estructuras distintas:
//
//   regfile.sv       21 comparadores por pares, generados con un generate
//                    anidado, que produce write_conflict_detected
//   psw_fault_unit.sv comparaciones agrupadas por slot, escritas a mano, que
//                    producen wconf_any
//
// Tener dos no es un descuido: la del banco es diagnostico local y la del PSW
// es la que llega al programa por MFPSW. Pero no son la misma funcion, y la
// diferencia es exactamente el punto de este testbench.
//
// -----------------------------------------------------------------------------
// LA DIFERENCIA, Y POR QUE ES A PROPOSITO
// -----------------------------------------------------------------------------
// WCONF, como lo define isa.md 1.2, es una condicion ENTRE slots: "dos slots
// escriben el mismo registro". Dos puertos del MISMO slot coincidiendo no es
// falla:
//
//   S2 escribe dos veces en LW.INC, el destino y el registro base. Si rd es
//   igual a rbase el ISA ya dice quien gana, el dato cargado, y lo da por
//   valido. Reportar WCONF ahi seria un falso positivo que el programa veria
//   con MFPSW.
//
//   S3 escribe las dos mitades del par. Nunca pueden ser el mismo registro,
//   porque son {par,0} y {par,1}, pero la exclusion esta escrita igual para
//   que la intencion quede en el codigo y no en la suerte.
//
// El banco incluye esos dos pares, porque alli la pregunta es la otra: "hubo
// dos escrituras al mismo registro", que es lo que decide la prioridad de
// puerto. Asi que la relacion que debe cumplirse no es la igualdad sino:
//
//     conflicto_del_banco  ==  wconf_del_psw  ||  choque_intra_slot
//
// Este testbench recorre vectores aleatorios de los siete habilitadores y los
// siete indices y comprueba esa ecuacion en cada uno. Si alguien "arregla"
// cualquiera de los dos detectores para que coincidan sin mas, o se olvida de
// excluir los pares intra-slot, aqui se cae.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_wconf;

  localparam int VECTORES = 4000;

  // ---------------------------------------------------------------------------
  // Reloj
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Estimulos compartidos por las dos unidades
  // ---------------------------------------------------------------------------

  logic [`NWRITE_PORTS-1:0]               wen;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]  widx;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]    wval;

  // ---------------------------------------------------------------------------
  // Banco de registros
  // ---------------------------------------------------------------------------

  logic [`NREAD_PORTS-1:0][`RIDX_W-1:0] ridx;
  logic [`NREAD_PORTS-1:0][`XLEN-1:0]   rval;
  logic                                 conf_banco;
  logic [`NREGS-1:0][`XLEN-1:0]         dbg;

  regfile u_rf (
      .clk                     (clk),
      .reset_n                 (1'b1),
      .read_register_index     (ridx),
      .read_register_value     (rval),
      .write_enable            (wen),
      .write_register_index    (widx),
      .write_value             (wval),
      .write_conflict_detected (conf_banco),
      .debug_register_values   (dbg)
  );

  // ---------------------------------------------------------------------------
  // Unidad de PSW
  // ---------------------------------------------------------------------------

  logic             conf_psw;
  logic [`XLEN-1:0] psw;

  psw_fault_unit u_psw (
      .clk          (clk),
      .rst_n        (1'b1),
      .flags_we     (1'b0),
      .flags        (4'b0000),
      .auth         (1'b0),
      .authfail     (1'b0),
      .s0_fault     (1'b0), .s0_cause (`CAUSE_NONE),
      .s1_fault     (1'b0), .s1_cause (`CAUSE_NONE),
      .s2_fault     (1'b0), .s2_cause (`CAUSE_NONE),
      .s3_fault     (1'b0), .s3_cause (`CAUSE_NONE),
      .s4_fault     (1'b0), .s4_cause (`CAUSE_NONE),
      .write_enable (wen),
      .write_index  (widx),
      .psw          (psw),
      .wconf_any    (conf_psw)
  );

  // ---------------------------------------------------------------------------
  // Choque intra-slot, calculado aqui de forma independiente
  //
  // Es la unica diferencia que se permite entre los dos detectores. Se escribe
  // con los indices de puerto y no copiando codigo de ninguno de los dos.
  // ---------------------------------------------------------------------------

  logic choque_s2, choque_s3, intra;

  assign choque_s2 = wen[`WP_S2_RD] && wen[`WP_S2_BASE] &&
                     (widx[`WP_S2_RD] == widx[`WP_S2_BASE]);
  assign choque_s3 = wen[`WP_S3_L] && wen[`WP_S3_R] &&
                     (widx[`WP_S3_L] == widx[`WP_S3_R]);
  assign intra     = choque_s2 || choque_s3;

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

  task automatic check1(input string nombre,
                        input logic obtenido,
                        input logic esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %b, esperado %b",
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

  integer i, p, semilla;
  integer malos, con_conflicto, con_intra, solo_intra;
  integer aleatorio;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_wconf.vcd");
      $dumpvars(0, tb_wconf);
    end

    ridx = '0;
    wval = '0;
    wen  = '0;
    widx = '0;
    semilla = 32'h0CA5_C0DE;   // fija, para que la corrida sea reproducible

    $display("=== tb_wconf: los dos detectores de conflicto de escritura ===");

    // ------------------------------------------------------------------------
    $display("[1] casos dirigidos");
    // ------------------------------------------------------------------------

    wen = '0; widx = '0;
    #1;
    check1("sin escrituras: el banco no ve conflicto", conf_banco, 1'b0);
    check1("sin escrituras: el PSW tampoco",           conf_psw,   1'b0);

    wen = '0; widx = '0;
    wen[`WP_S0] = 1'b1;  widx[`WP_S0] = 4'd7;
    wen[`WP_S1] = 1'b1;  widx[`WP_S1] = 4'd7;
    #1;
    check1("S0 contra S1: el banco lo ve",  conf_banco, 1'b1);
    check1("S0 contra S1: el PSW tambien",  conf_psw,   1'b1);

    wen = '0; widx = '0;
    wen[`WP_S2_RD]   = 1'b1;  widx[`WP_S2_RD]   = 4'd4;
    wen[`WP_S2_BASE] = 1'b1;  widx[`WP_S2_BASE] = 4'd4;
    #1;
    check1("LW.INC con rd = rbase: el banco lo ve",      conf_banco, 1'b1);
    check1("LW.INC con rd = rbase: el PSW NO lo reporta", conf_psw,  1'b0);
    check1("y el termino intra-slot explica la diferencia", intra,   1'b1);

    wen = '0; widx = '0;
    wen[`WP_S3_L] = 1'b1;  widx[`WP_S3_L] = 4'd12;
    wen[`WP_S3_R] = 1'b1;  widx[`WP_S3_R] = 4'd12;
    #1;
    check1("las dos mitades del par: el PSW NO lo reporta", conf_psw, 1'b0);
    check1("y tambien lo explica el termino intra-slot",    intra,    1'b1);

    // ------------------------------------------------------------------------
    $display("[2] vectores aleatorios");
    // ------------------------------------------------------------------------
    // La ecuacion que debe cumplirse en todos:
    //     conf_banco == conf_psw || intra

    malos         = 0;
    con_conflicto = 0;
    con_intra     = 0;
    solo_intra    = 0;

    for (i = 0; i < VECTORES; i = i + 1) begin
      // Habilitadores: se sesgan hacia el 1 para que haya conflictos de sobra
      for (p = 0; p < `NWRITE_PORTS; p = p + 1) begin
        aleatorio = $random(semilla);
        wen[p]    = (aleatorio % 4) != 0;      // 3 de cada 4 habilitados
        aleatorio = $random(semilla);
        // Indices en un rango corto, para que las coincidencias sean frecuentes
        widx[p]   = aleatorio % 6;
      end
      #1;

      if (conf_banco !== (conf_psw || intra)) begin
        malos = malos + 1;
        if (malos <= 5)
          $display("         wen=%b widx=%h banco=%b psw=%b intra=%b",
                   wen, widx, conf_banco, conf_psw, intra);
      end

      if (conf_banco)             con_conflicto = con_conflicto + 1;
      if (intra)                  con_intra     = con_intra + 1;
      if (intra && !conf_psw)     solo_intra    = solo_intra + 1;
    end

    $display("         %0d vectores: %0d con conflicto en el banco, %0d con",
             VECTORES, con_conflicto, con_intra);
    $display("         choque intra-slot, %0d de ellos que SOLO son intra-slot",
             solo_intra);

    check_int("la ecuacion se cumple en todos los vectores", malos, 0);

    // Que el experimento haya tocado de verdad los dos lados de la ecuacion.
    // Sin esto, un lazo que generara siempre vectores sin escrituras pasaria.
    tests_run = tests_run + 1;
    if (con_conflicto < VECTORES/10) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  los vectores casi no produjeron conflictos (%0d)",
               con_conflicto);
    end else begin
      $display("  ok     los vectores produjeron conflictos de sobra");
    end

    tests_run = tests_run + 1;
    if (solo_intra == 0) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  ningun vector aislo el caso intra-slot");
    end else begin
      $display("  ok     hubo vectores que solo chocan dentro de un slot");
    end

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
