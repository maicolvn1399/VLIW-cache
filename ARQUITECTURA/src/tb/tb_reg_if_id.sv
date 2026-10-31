`timescale 1ns/1ps

// =============================================================================
// tb_reg_if_id.sv - Testbench del registro de segmentacion IF/ID.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// El modulo es pequeno, pero lo que comprueba este arnes no es que un biestable
// funcione: es que el PC se retrase EXACTAMENTE un ciclo. La BRU calcula su
// destino como pc + 16*(1+desp) con el PC que le entrega este registro, asi que
// un ciclo de mas o de menos aqui hace que todos los saltos relativos aterricen
// un bundle corrido, sin que nada en la simulacion se queje.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: las dos salidas en cero
//   2. La salida no se mueve antes del flanco de subida
//   3. El retraso es de exactamente un ciclo, medido sobre una secuencia
//   4. valid y pc son independientes
//   5. El reset en medio de la secuencia corta el flujo
// =============================================================================

`include "cerbero_defs.svh"

module tb_reg_if_id;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             rst_n;
  logic             valid_in;
  logic [`XLEN-1:0] pc_in;
  logic             valid_out;
  logic [`XLEN-1:0] pc_out;

  reg_if_id dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid_in  (valid_in),
      .pc_in     (pc_in),
      .valid_out (valid_out),
      .pc_out    (pc_out)
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

  task automatic reiniciar();
    begin
      rst_n = 1'b0;
      @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i, malos, retraso;
  logic [`XLEN-1:0] esperado_pc;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_reg_if_id.vcd");
      $dumpvars(0, tb_reg_if_id);
    end

    valid_in = 1'b0;
    pc_in    = '0;
    rst_n    = 1'b1;

    $display("=== tb_reg_if_id: frontera IF/ID ===");

    // ------------------------------------------------------------------------
    $display("[1] reset");
    // ------------------------------------------------------------------------

    valid_in = 1'b1;
    pc_in    = 32'hDEAD_BEE0;
    reiniciar();
    check1 ("valid en cero tras el reset", valid_out, 1'b0);
    check32("pc en cero tras el reset",    pc_out,    32'h0000_0000);

    // ------------------------------------------------------------------------
    $display("[2] la salida espera el flanco");
    // ------------------------------------------------------------------------

    @(negedge clk);
    #1 pc_in = 32'h0000_1230;
    #2;
    check32("pc_out no cambia a mitad de ciclo", pc_out, 32'h0000_0000);

    @(posedge clk);
    #1;
    check32("pc_out cambia en el flanco de subida", pc_out, 32'h0000_1230);

    // ------------------------------------------------------------------------
    $display("[3] el retraso es de un ciclo exacto");
    // ------------------------------------------------------------------------
    // Se empuja una secuencia de PCs consecutivos, uno por ciclo, y se mide
    // cuantos ciclos tarda cada uno en salir. La BRU depende de que sea 1.

    reiniciar();
    valid_in = 1'b1;
    malos    = 0;
    retraso  = -1;

    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      #1 pc_in = 32'h0000_2000 + (i * 16);
      @(posedge clk);
      #1;
      // En este punto la salida debe traer el PC presentado en ESTE ciclo
      esperado_pc = 32'h0000_2000 + (i * 16);
      if (pc_out !== esperado_pc) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         ciclo %0d: pc_out=%08h, esperaba %08h",
                   i, pc_out, esperado_pc);
      end else if (retraso < 0) begin
        retraso = 1;
      end
    end
    check_int("los 8 PCs de la secuencia salen a tiempo", malos, 0);
    check_int("el retraso medido es de un ciclo",         retraso, 1);

    // ------------------------------------------------------------------------
    $display("[4] valid y pc son independientes");
    // ------------------------------------------------------------------------
    // El error de copiar y pegar que importa aqui es que una salida tome la
    // entrada de la otra. Con un solo campo distinto de cero cada vez, solo esa
    // salida debe moverse.

    reiniciar();
    valid_in = 1'b1;
    pc_in    = 32'h0000_0000;
    @(negedge clk); @(posedge clk); #1;
    check1 ("solo valid: valid_out encendido", valid_out, 1'b1);
    check32("solo valid: pc_out sigue en cero", pc_out,   32'h0000_0000);

    reiniciar();
    valid_in = 1'b0;
    pc_in    = 32'hA5A5_A5A0;
    @(negedge clk); @(posedge clk); #1;
    check1 ("solo pc: valid_out apagado", valid_out, 1'b0);
    check32("solo pc: pc_out trae el valor", pc_out,  32'hA5A5_A5A0);

    // ------------------------------------------------------------------------
    $display("[5] el reset corta el flujo");
    // ------------------------------------------------------------------------

    valid_in = 1'b1;
    pc_in    = 32'h0000_7000;
    @(negedge clk); @(posedge clk); #1;
    check32("el registro trae el ultimo PC", pc_out, 32'h0000_7000);

    reiniciar();
    check1 ("el reset apaga valid aunque la entrada este en uno",
            valid_out, 1'b0);
    check32("y borra el PC", pc_out, 32'h0000_0000);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
