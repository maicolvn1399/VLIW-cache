`timescale 1ns/1ps

// =============================================================================
// tb_vliw.sv - Cuanto cuesta no llenar el bundle.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
//     make vliw
//
// Corre el MISMO calculo escrito de dos formas y mide los ciclos de cada una.
// Los dos programas suman los cuadrados de las 64 palabras que hay en 0x100 y
// tienen que dar 89440; lo que cambia es cuanto trabajo independiente le dan
// al procesador.
//
//   suma_simple   un elemento por vuelta. La cadena lw -> mul -> add cuesta
//                 seis bundles de latencia con las cinco ranuras libres.
//   suma_vliw     cuatro elementos por vuelta y cuatro acumuladores, de modo
//                 que ni los productos ni las sumas dependen entre si.
//
// Los dos pasan por tools/empacar.py antes de ensamblarse, asi que la
// diferencia no es el empaquetado -- lo tienen los dos -- sino que el segundo
// LE DA ALGO QUE EMPAQUETAR.
//
// -----------------------------------------------------------------------------
// POR QUE ESTE TESTBENCH ESTA EN LA SUITE
// -----------------------------------------------------------------------------
// Que un VLIW ejecute cinco operaciones por ciclo no se demuestra enseñando el
// diagrama del bundle: se demuestra midiendo. Aqui estan los dos numeros, y la
// comprobacion de que las dos versiones dan el mismo resultado, que es lo que
// hace honesta la comparacion. Una version rapida que calcula otra cosa no
// prueba nada.
//
// El testbench falla si la aceleracion cae por debajo de 2x. No es una
// medida de calidad del planificador sino una alarma: si alguien rompe el
// empaquetado o cambia la latencia del ISA, ese numero se desploma y aqui se
// nota, en vez de notarse en la revision.
// =============================================================================

`include "cerbero_defs.svh"

module tb_vliw;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int TOPE      = 20000;

  localparam int W_RES = 32'h0200 / 4;
  localparam logic [`XLEN-1:0] ESPERADO = 32'd89440;   // suma de 1^2 a 64^2

  // La aceleracion por debajo de la cual algo se rompio
  localparam real MINIMO = 2.0;

  logic             halt_s, halt_v;
  logic [`XLEN-1:0] psw_s,  psw_v;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs_s, regs_v;
  /* verilator lint_on UNUSEDSIGNAL */

  top #(
      .NUM_BUNDLES (N_BUNDLES), .NUM_WORDS (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) simple (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_s), .psw (psw_s), .dbg_regs (regs_s)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES), .NUM_WORDS (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) vliw (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_v), .psw (psw_v), .dbg_regs (regs_v)
  );

  // ---------------------------------------------------------------------------
  // Comprobaciones
  // ---------------------------------------------------------------------------

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
        $display("  ok     %-46s %08h", nombre, obtenido);
      end
    end
  endtask

  task automatic check(input string nombre, input logic condicion);
    begin
      tests_run = tests_run + 1;
      if (condicion !== 1'b1) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %s", nombre);
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

  integer c, ciclos_s, ciclos_v;
  real    aceleracion;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_vliw.vcd");
      $dumpvars(0, tb_vliw);
    end

    rst_n = 1'b0;
    #1;
    $readmemh("../../tools/programas/suma_simple_emp.hex",  simple.u_imem.storage);
    $readmemh("../../tools/programas/suma_simple_emp_datos.hex", simple.u_dmem.storage);
    $readmemh("../../tools/programas/suma_vliw_emp.hex",    vliw.u_imem.storage);
    $readmemh("../../tools/programas/suma_vliw_emp_datos.hex", vliw.u_dmem.storage);

    $display("=== tb_vliw: el mismo calculo, con y sin trabajo independiente ===");
    $display("");

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    // Los dos corren a la vez; cada uno se para cuando llega a su HALT
    c = 0;
    ciclos_s = 0;
    ciclos_v = 0;
    while (!(halt_s && halt_v) && c < TOPE) begin
      @(posedge clk);
      c = c + 1;
      if (!halt_s) ciclos_s = c;
      if (!halt_v) ciclos_v = c;
    end

    // ------------------------------------------------------------------------
    $display("[1] las dos versiones calculan lo mismo");
    // ------------------------------------------------------------------------
    // Sin esto la comparacion de ciclos no significa nada: una version rapida
    // que da otro numero no es una version rapida.

    check("la version simple llego a HALT", halt_s);
    check("la version VLIW llego a HALT",   halt_v);
    check32("suma_simple deja 89440 en 0x200",
            simple.u_dmem.storage[W_RES], ESPERADO);
    check32("suma_vliw   deja 89440 en 0x200",
            vliw.u_dmem.storage[W_RES],   ESPERADO);
    check("ninguna de las dos registro fallas",
          (psw_s[`PSW_EXC] === 1'b0) && (psw_v[`PSW_EXC] === 1'b0));

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] y una tarda mucho menos");
    // ------------------------------------------------------------------------

    aceleracion = (ciclos_v > 0) ? (1.0 * ciclos_s) / (1.0 * ciclos_v) : 0.0;

    $display("         suma_simple  %0d ciclos", ciclos_s);
    $display("         suma_vliw    %0d ciclos", ciclos_v);
    $display("         aceleracion  %0.2fx", aceleracion);
    $display("");
    $display("         La diferencia no es el empaquetado, que lo tienen los");
    $display("         dos: es que el lazo desenrollado tiene trabajo");
    $display("         independiente con que llenar los huecos de la latencia.");

    check("la version VLIW es mas rapida", ciclos_v < ciclos_s);
    check($sformatf("y la aceleracion llega a %0.1fx", MINIMO),
          aceleracion >= MINIMO);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("");
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'd0, 32'd1);
`endif

    $display("");
    resumen();
  end

endmodule
