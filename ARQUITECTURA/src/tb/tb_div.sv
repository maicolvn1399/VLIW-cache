`timescale 1ns/1ps

// =============================================================================
// tb_div.sv - La subrutina de division corriendo en el procesador.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Carga el binario de tools/programas/div32_prueba.s, que llama a __div32 con
// seis pares y guarda los doce resultados en memoria, y los compara contra los
// valores calculados fuera del simulador.
//
// -----------------------------------------------------------------------------
// POR QUE HACE FALTA EJECUTARLA
// -----------------------------------------------------------------------------
// __div32 es un lazo de 21 bundles que da 32 vueltas, con una cadena de
// dependencias de siete pasos y los tres bundles de separacion que exige el ISA
// en cada uno. Leerla no alcanza para convencerse: un paso mal calendarizado
// lee el valor de la vuelta anterior y produce un cociente equivocado sin que
// nada en la simulacion se queje.
//
// El ensamblador ya comprueba las separaciones DENTRO del flujo secuencial, y
// desde que tambien sigue las banderas eso cubre la cadena cmp -> setcc y la
// cmpi -> br.ne. Lo que no puede ver es la arista de vuelta del lazo, porque no
// razona sobre el flujo de control. Esa parte solo la verifica una corrida.
//
// -----------------------------------------------------------------------------
// LOS SEIS CASOS
// -----------------------------------------------------------------------------
//   normal           0x000003E8 / 0x0007  ->  0x0000008E  resto 0x00000006
//   divisor 1        0xFFFFFFFF / 0x0001  ->  0xFFFFFFFF  resto 0x00000000
//   dividendo menor  0x00000007 / 0x03E8  ->  0x00000000  resto 0x00000007
//   bit 31 puesto    0x80000000 / 0x0003  ->  0x2AAAAAAA  resto 0x00000002
//   division por 0   0x00000064 / 0x0000  ->  0xFFFFFFFF  resto 0x00000064
//   dividendo 0      0x00000000 / 0x0005  ->  0x00000000  resto 0x00000000
//
// El del bit 31 es el que separa una division sin signo de una con signo, que
// es el error clasico del algoritmo de restas desplazadas. El de divisor 1
// recorre las 32 vueltas poniendo un bit de cociente en cada una, asi que un
// error en el desplazamiento del acumulador se ve entero.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_div;

  localparam int N_BUNDLES = 128;
  localparam int N_WORDS   = 64;

  // Los resultados empiezan en 0x40, que es la palabra 16
  localparam int W_RES = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic                         halted;
  logic [`XLEN-1:0]             psw;
  logic [`NREGS-1:0][`XLEN-1:0] regs;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs_sin_uso;
  /* verilator lint_on UNUSEDSIGNAL */
  assign regs_sin_uso = regs;

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs)
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
        $display("  FALLA  %-40s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-40s %08h", nombre, obtenido);
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
        $display("  FALLA  %-40s obtenido %b, esperado %b",
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

  // Compara el par de palabras de un caso
  task automatic caso(input string nombre,
                      input integer i,
                      input logic [`XLEN-1:0] q,
                      input logic [`XLEN-1:0] r);
    begin
      check32({nombre, ", cociente"}, dut.u_dmem.storage[W_RES + 2*i],     q);
      check32({nombre, ", residuo "}, dut.u_dmem.storage[W_RES + 2*i + 1], r);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer ciclos;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_div.vcd");
      $dumpvars(0, tb_div);
    end

    $display("=== tb_div: __div32 sobre el procesador ===");

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    // Seis divisiones de unos 680 ciclos cada una
    ciclos = 0;
    while (!halted && ciclos < 20000) begin
      @(posedge clk);
      ciclos = ciclos + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("");
    $display("  el programa se detuvo tras %0d ciclos, o sea unos %0d por",
             ciclos, ciclos / 6);
    $display("  division contando la carga de operandos y el guardado");
    $display("");

    check1("el procesador se detuvo", halted, 1'b1);

    caso("1000 / 7        ", 0, 32'h0000_008E, 32'h0000_0006);
    caso("0xFFFFFFFF / 1  ", 1, 32'hFFFF_FFFF, 32'h0000_0000);
    caso("7 / 1000        ", 2, 32'h0000_0000, 32'h0000_0007);
    caso("0x80000000 / 3  ", 3, 32'h2AAA_AAAA, 32'h0000_0002);
    caso("100 / 0         ", 4, 32'hFFFF_FFFF, 32'h0000_0064);
    caso("0 / 5           ", 5, 32'h0000_0000, 32'h0000_0000);

    // La rutina no debe haber producido ninguna falla: ni accesos
    // desalineados, ni opcodes raros, ni conflictos de escritura
    check1("sin fallas en el PSW", psw[`PSW_EXC], 1'b0);

    // Y no tiene nada que ver con la boveda
    check1("la sesion de boveda nunca se abrio", psw[`PSW_AUTH], 1'b0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'd0, 32'd1);
`endif

    resumen();
  end

endmodule
