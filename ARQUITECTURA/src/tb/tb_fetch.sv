`timescale 1ns/1ps

// =============================================================================
// tb_fetch.sv - Testbench del contador de programa.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Prueba el modulo aislado, manejando a mano las tres senales que en el
// procesador vienen de la BRU. Que el delay slot y HALT funcionen con la
// memoria y la BRU de verdad lo comprueba tb_fetch_flow.sv.
//
// Todos los estimulos se cambian en el flanco de bajada y se observan en el
// siguiente flanco de bajada, lejos del de subida en que el modulo captura.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: PC inicial, sin detener, valid encendido
//   2. Avance secuencial de 16 en 16
//   3. Salto tomado: el siguiente PC es el destino
//   4. Destino desalineado: los cuatro bits bajos se fuerzan a cero
//   5. Sin salto tomado el destino se ignora
//   6. HALT congela el PC y apaga valid
//   7. Detenido, ignora saltos y nuevos HALT
//   8. El reset saca del estado detenido
//   9. El reset domina sobre salto y HALT en el mismo ciclo
//  10. RESET_PC distinto de cero
// =============================================================================

`include "cerbero_defs.svh"

module tb_fetch;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             rst_n;
  logic             taken;
  logic [`XLEN-1:0] target;
  logic             halt;
  logic [`XLEN-1:0] pc;
  logic             valid;
  logic             halted;

  fetch dut (
      .clk    (clk),
      .rst_n  (rst_n),
      .taken  (taken),
      .target (target),
      .halt   (halt),
      .pc     (pc),
      .valid  (valid),
      .halted (halted)
  );

  // Segunda instancia, solo para el caso 10. Comparte todas las entradas.
  logic [`XLEN-1:0] pc_alt;
  logic             valid_alt;
  logic             halted_alt;

  fetch #(.RESET_PC(32'h0000_7000)) dut_alt (
      .clk    (clk),
      .rst_n  (rst_n),
      .taken  (taken),
      .target (target),
      .halt   (halt),
      .pc     (pc_alt),
      .valid  (valid_alt),
      .halted (halted_alt)
  );

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check32(input string nombre,
                         input logic [`XLEN-1:0] obtenido,
                         input logic [`XLEN-1:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %08h, esperado %08h",
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

  // Fija las tres entradas de la BRU y deja pasar un flanco de subida. Llamada
  // siempre desde un flanco de bajada, termina en el siguiente.
  task automatic paso(input logic             t,
                      input logic [`XLEN-1:0] dest,
                      input logic             h);
    begin
      taken  = t;
      target = dest;
      halt   = h;
      @(negedge clk);
    end
  endtask

  task automatic avanzar();
    begin
      paso(1'b0, 32'h0, 1'b0);
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n = 1'b0;
      avanzar();
      rst_n = 1'b1;
    end
  endtask

  // Comprueba las tres salidas de la instancia principal
  task automatic estado(input string            nombre,
                        input logic [`XLEN-1:0] pc_esp,
                        input logic             halted_esp);
    begin
      check32({nombre, ": pc"},     pc,     pc_esp);
      check1 ({nombre, ": halted"}, halted, halted_esp);
      check1 ({nombre, ": valid"},  valid,  !halted_esp);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_fetch.vcd");
      $dumpvars(0, tb_fetch);
    end

    rst_n  = 1'b1;
    taken  = 1'b0;
    target = '0;
    halt   = 1'b0;
    @(negedge clk);

    $display("=== tb_fetch: contador de programa ===");

    // ------------------------------------------------------------------------
    $display("[1] reset");
    // ------------------------------------------------------------------------

    reiniciar();
    estado("tras el reset", 32'h0000_0000, 1'b0);

    // ------------------------------------------------------------------------
    $display("[2] avance secuencial");
    // ------------------------------------------------------------------------

    for (i = 1; i <= 4; i = i + 1) begin
      avanzar();
      check32($sformatf("bundle %0d", i), pc, 32'(16 * i));
    end

    // ------------------------------------------------------------------------
    $display("[3] salto tomado");
    // ------------------------------------------------------------------------

    paso(1'b1, 32'h0000_0400, 1'b0);
    estado("el PC toma el destino", 32'h0000_0400, 1'b0);
    avanzar();
    check32("y sigue avanzando desde ahi", pc, 32'h0000_0410);

    paso(1'b1, 32'h0000_0010, 1'b0);
    check32("salto hacia atras", pc, 32'h0000_0010);

    // ------------------------------------------------------------------------
    $display("[4] destino desalineado");
    // ------------------------------------------------------------------------

    paso(1'b1, 32'h0000_123F, 1'b0);
    check32("los cuatro bits bajos se borran", pc, 32'h0000_1230);
    paso(1'b1, 32'hFFFF_FFF9, 1'b0);
    check32("sin tocar los bits altos", pc, 32'hFFFF_FFF0);
    avanzar();
    check32("el avance da la vuelta en 32 bits", pc, 32'h0000_0000);

    // ------------------------------------------------------------------------
    $display("[5] sin salto tomado el destino no importa");
    // ------------------------------------------------------------------------

    paso(1'b0, 32'hDEAD_BEE0, 1'b0);
    check32("sigue el bundle contiguo", pc, 32'h0000_0010);

    // ------------------------------------------------------------------------
    $display("[6] HALT");
    // ------------------------------------------------------------------------

    paso(1'b0, 32'h0, 1'b1);
    estado("el PC se queda donde estaba", 32'h0000_0010, 1'b1);
    for (i = 0; i < 3; i = i + 1) avanzar();
    estado("tres ciclos despues, igual", 32'h0000_0010, 1'b1);

    // ------------------------------------------------------------------------
    $display("[7] detenido, ignora la BRU");
    // ------------------------------------------------------------------------

    paso(1'b1, 32'h0000_0800, 1'b0);
    estado("un salto tomado no mueve el PC", 32'h0000_0010, 1'b1);
    paso(1'b0, 32'h0, 1'b1);
    estado("otro HALT tampoco", 32'h0000_0010, 1'b1);
    paso(1'b1, 32'h0000_0800, 1'b1);
    estado("ni los dos juntos", 32'h0000_0010, 1'b1);

    // ------------------------------------------------------------------------
    $display("[8] el reset saca del estado detenido");
    // ------------------------------------------------------------------------

    reiniciar();
    estado("tras el reset", 32'h0000_0000, 1'b0);
    avanzar();
    check32("y vuelve a avanzar", pc, 32'h0000_0010);

    // ------------------------------------------------------------------------
    $display("[9] el reset domina");
    // ------------------------------------------------------------------------

    rst_n = 1'b0;
    paso(1'b1, 32'h0000_0800, 1'b1);
    rst_n = 1'b1;
    estado("salto y HALT durante el reset", 32'h0000_0000, 1'b0);

    // ------------------------------------------------------------------------
    $display("[10] RESET_PC distinto de cero");
    // ------------------------------------------------------------------------

    check32("arranca en RESET_PC", pc_alt, 32'h0000_7000);
    avanzar();
    check32("y avanza desde ahi", pc_alt, 32'h0000_7010);
    check1 ("sin detenerse", halted_alt, 1'b0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", pc, 32'h0000_0001);
`endif

    resumen();
  end

endmodule
