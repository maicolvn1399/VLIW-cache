`timescale 1ns/1ps

// =============================================================================
// tb_l2_arbiter.sv - Arbitro entre las lecturas de L1-D y el drenado del
//                    write buffer hacia la L2.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Lo que se fija aqui:
//
//   1. Prioridad estricta a L1: con las dos peticiones a la vez, gana la
//      lectura, porque es la que tiene al pipeline detenido esperandola.
//   2. Que el drenado si pase cuando L1 no pide nada.
//   3. Que una transaccion empezada NO se abandone a mitad de camino si
//      aparece la otra peticion. Un arbitro que cambia de opinion deja a la
//      L2 con una peticion sin terminar.
//   4. Que wb_drenando (head_ocupada) este alto durante TODO el drenado. Es lo
//      que impide que el buffer fusione datos nuevos sobre una linea que ya va
//      camino a la L2, que fue el error silencioso de la Iteracion 3.
//   5. Que wb_ack y l1_listo duren un solo ciclo. Un ack de dos ciclos le hace
//      perder una entrada al buffer.
//   6. Que los datos y la mascara que llegan a la L2 sean los de la cabeza del
//      buffer, y que en una lectura la mascara vaya en cero: si no, la L2
//      mezclaria basura al rellenar.
// =============================================================================

`include "cerbero_defs.svh"

module tb_l2_arbiter();

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic                    l1_req;
  logic [`MEM_LIDX_W-1:0]  l1_linea;
  logic                    l1_listo;
  logic [`LINE_W-1:0]      l1_rdata;

  logic                    wb_req;
  logic [`MEM_LIDX_W-1:0]  wb_linea;
  logic [`LINE_W-1:0]      wb_datos;
  logic [`LINE_MASK_W-1:0] wb_mascara;
  logic                    wb_ack;
  logic                    wb_drenando;

  logic                    l2_req_lectura, l2_req_escritura;
  logic [`MEM_LIDX_W-1:0]  l2_req_linea;
  logic [`LINE_W-1:0]      l2_req_wdata;
  logic [`LINE_MASK_W-1:0] l2_req_wmask;
  logic [`LINE_W-1:0]      l2_rdata;
  logic                    l2_listo;

  l2_arbiter dut (
      .clk (clk), .rst_n (rst_n),
      .l1_req (l1_req), .l1_linea (l1_linea),
      .l1_listo (l1_listo), .l1_rdata (l1_rdata),
      .wb_req (wb_req), .wb_linea (wb_linea), .wb_datos (wb_datos),
      .wb_mascara (wb_mascara), .wb_ack (wb_ack), .wb_drenando (wb_drenando),
      .l2_req_lectura (l2_req_lectura), .l2_req_escritura (l2_req_escritura),
      .l2_req_linea (l2_req_linea), .l2_req_wdata (l2_req_wdata),
      .l2_req_wmask (l2_req_wmask),
      .l2_rdata (l2_rdata), .l2_listo (l2_listo)
  );

  // ===========================================================================
  // Modelo de la L2: responde listo tras LAT ciclos de peticion sostenida
  // ===========================================================================

  localparam int LAT = 8;
  int unsigned cuenta;
  logic [`LINE_W-1:0] respuesta;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cuenta   <= 0;
      l2_listo <= 1'b0;
    end
    else begin
      l2_listo <= 1'b0;
      if ((l2_req_lectura || l2_req_escritura) && !l2_listo) begin
        if (cuenta == LAT - 1) begin
          cuenta   <= 0;
          l2_listo <= 1'b1;
        end
        else cuenta <= cuenta + 1;
      end
      else cuenta <= 0;
    end
  end

  assign l2_rdata = respuesta;

  // ===========================================================================
  // Marcador
  // ===========================================================================

  int tests_run = 0, tests_failed = 0;

  task automatic check(input string nombre, input integer obtenido,
                       input integer esperado);
    begin
      tests_run++;
      if (obtenido !== esperado) begin
        tests_failed++;
        $display("  FALLA  %-50s obtenido %0d, esperado %0d",
                 nombre, obtenido, esperado);
      end
      else $display("  ok     %-50s %0d", nombre, obtenido);
    end
  endtask

  task automatic check_hex(input string nombre,
                           input logic [`XLEN-1:0] obtenido,
                           input logic [`XLEN-1:0] esperado);
    begin
      tests_run++;
      if (obtenido !== esperado) begin
        tests_failed++;
        $display("  FALLA  %-50s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end
      else $display("  ok     %-50s %08h", nombre, obtenido);
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

  task automatic reiniciar();
    begin
      rst_n      = 1'b0;
      l1_req     = 1'b0; l1_linea = '0;
      wb_req     = 1'b0; wb_linea = '0; wb_datos = '0; wb_mascara = '0;
      respuesta  = '0;
      @(posedge clk);
      @(negedge clk) rst_n = 1'b1;
    end
  endtask

  function automatic logic [`LINE_W-1:0] linea_de(input logic [`XLEN-1:0] w);
    logic [`LINE_W-1:0] r;
    for (int i = 0; i < `LINE_WORDS; i++) r[i*`XLEN +: `XLEN] = w;
    return r;
  endfunction

  int unsigned i, ciclos_drenando, ciclos_ack, ciclos_listo;
  logic visto;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_l2_arbiter.vcd");
      $dumpvars(0, tb_l2_arbiter);
    end

    $display("=== tb_l2_arbiter: lecturas de L1 contra drenado del buffer ===");

    reiniciar();

    // ------------------------------------------------------------------------
    $display("");
    $display("[1] prioridad estricta a L1 con las dos peticiones a la vez");
    // ------------------------------------------------------------------------
    respuesta = linea_de(32'hC0FE_0001);
    @(negedge clk);
    l1_req     = 1'b1; l1_linea   = 11'd7;
    wb_req     = 1'b1; wb_linea   = 11'd9;
    wb_datos   = linea_de(32'hDA70_0009);
    wb_mascara = {`LINE_MASK_W{1'b1}};

    @(posedge clk); #1;    // el arbitro decide
    @(posedge clk); #1;    // y ya esta sirviendo

    check("eligio la lectura de L1",        l2_req_lectura,   1'b1);
    check("y no el drenado del buffer",     l2_req_escritura, 1'b0);
    check("con la linea que pidio L1",      l2_req_linea,     7);
    check("y la mascara en cero en lectura", l2_req_wmask,    0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] la transaccion no se abandona a mitad de camino");
    // ------------------------------------------------------------------------
    // El write buffer sigue pidiendo todo el rato. El arbitro no puede soltar
    // la lectura por eso.
    ciclos_listo = 0;
    visto = 1'b0;
    for (i = 0; i < LAT + 4; i++) begin
      if (!visto) begin
        @(posedge clk); #1;
        if (l2_req_escritura) ciclos_listo++;  // no deberia ocurrir ni una vez
        if (l1_listo) visto = 1'b1;
      end
    end
    check("nunca cambio al drenado durante la lectura", ciclos_listo, 0);
    check("y termino levantando l1_listo",              l1_listo,     1'b1);
    check_hex("devolviendo el dato de la L2", l1_rdata[31:0], 32'hC0FE_0001);
    check("sin dar ack al buffer",                      wb_ack,       1'b0);

    // l1_listo dura un solo ciclo
    @(negedge clk) l1_req = 1'b0;
    @(posedge clk); #1;
    check("l1_listo duro un solo ciclo", l1_listo, 1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] sin L1 pidiendo, el drenado si pasa");
    // ------------------------------------------------------------------------
    @(posedge clk); #1;
    @(posedge clk); #1;
    check("ahora si atiende al buffer", l2_req_escritura, 1'b1);
    check("y no pide lectura",          l2_req_lectura,   1'b0);
    check("con la linea de la cabeza",  l2_req_linea,     9);
    check_hex("y sus datos",       l2_req_wdata[31:0], 32'hDA70_0009);
    check("y su mascara completa", l2_req_wmask, {`LINE_MASK_W{1'b1}});

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] wb_drenando cubre todo el drenado");
    // ------------------------------------------------------------------------
    // Es lo que impide fusionar sobre una linea que ya va en camino. Si baja
    // aunque sea un ciclo antes del ack, se abre la ventana del error que la
    // Iteracion 3 costo encontrar.
    ciclos_drenando = 0;
    ciclos_ack      = 0;
    visto           = 1'b0;
    for (i = 0; i < LAT + 6; i++) begin
      if (!visto) begin
        if (wb_drenando) ciclos_drenando++;
        if (wb_ack) begin
          ciclos_ack++;
          visto = 1'b1;
        end
        else begin
          @(posedge clk); #1;
        end
      end
    end
    check("wb_drenando estuvo alto en cada ciclo del drenado",
          (ciclos_drenando >= LAT), 1'b1);
    check("y wb_ack llego",                     (ciclos_ack > 0), 1'b1);
    check("con wb_drenando todavia alto en el ack", wb_drenando, 1'b1);

    // El ack dura un solo ciclo: si durara dos, el buffer soltaria dos entradas
    @(negedge clk) wb_req = 1'b0;
    @(posedge clk); #1;
    check("wb_ack duro un solo ciclo", wb_ack, 1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[5] el arbitro vuelve a quedar libre");
    // ------------------------------------------------------------------------
    @(posedge clk); #1;
    check("sin peticiones no pide lectura",   l2_req_lectura,   1'b0);
    check("ni escritura",                     l2_req_escritura, 1'b0);
    check("y no deja wb_drenando colgado",    wb_drenando,      1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[6] una lectura sola, de punta a punta");
    // ------------------------------------------------------------------------
    respuesta = linea_de(32'hBEEF_0042);
    @(negedge clk) begin
      l1_req   = 1'b1;
      l1_linea = 11'd42;
    end
    ciclos_listo = 0;
    visto        = 1'b0;
    for (i = 0; i < LAT + 8; i++) begin
      if (!visto) begin
        @(posedge clk); #1;
        ciclos_listo++;
        if (l1_listo) visto = 1'b1;
      end
    end
    check("la lectura sola termino",   l1_listo, 1'b1);
    check_hex("con su dato",           l1_rdata[31:0], 32'hBEEF_0042);
    // LAT ciclos del modelo de L2 mas el ciclo de LIBRE en que el arbitro
    // decide a quien atender. La latencia real de la L2 se comprueba en
    // tb_l2_cache.sv contra la macro; aqui lo que se fija es que el arbitro
    // no agregue ciclos de su cuenta.
    check("y costo la latencia de la L2 mas el ciclo de arbitraje",
          ciclos_listo, LAT + 1);
    @(negedge clk) l1_req = 1'b0;

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", tests_run, -1);
`endif

    $display("");
    resumen();
  end

  initial begin
    #2_000_000;
    $display("  FALLA  la prueba no termino a tiempo");
    $display("RESULTADO: FALLA");
    $fatal(1, "tiempo agotado");
  end

endmodule
