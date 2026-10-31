`timescale 1ns/1ps

// =============================================================================
// tb_credencial.sv - Una credencial incorrecta no cifra nada.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Corre cifrar_archivo.s sin cambiarle una linea, sobre un procesador cuyo
// ROT_SECRET NO es la credencial que el programa presenta. Es lo mismo que
// escribir mal la contrasena: el programa hace AUTHW con sus cuatro palabras,
// LOGIN las compara contra el secreto del hardware y no coinciden.
//
// Lo que el ISA promete en ese caso (8.2 y 1.2), y lo que se comprueba:
//
//   - LOGIN no es una falla: enciende AUTHFAIL y deja AUTH apagado
//   - KSETW sin sesion se anula y registra DENIED; es la primera falla, asi que
//     EXC queda encendido y CAUSE congelada en DENIED
//   - las rondas F4E tambien se anulan, asi que el par no se escribe y el
//     programa guarda de vuelta el mismo bloque que leyo: el buffer queda
//     identico al original, no cifrado y tampoco corrompido
//   - el procesador no se cuelga: llega a HALT igual que con la credencial
//     correcta
//   - ninguna subllave aparece en la memoria de datos
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_credencial;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int W_BUF     = 32'h4000 / 4;     // 4096

  // La credencial que presenta cargar_llave.s es 0123456789ABCDEF_FEDCBA9876543210.
  // Este secreto difiere en un solo bit, el mas bajo: basta para que LOGIN falle.
  localparam logic [127:0] SECRETO_DISTINTO =
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3211;

  localparam int CICLOS_MAX = 5000;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                         rst_n;
  logic                         halted;
  logic [`XLEN-1:0]             psw;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs;
  /* verilator lint_on UNUSEDSIGNAL */

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000),
      .ROT_SECRET  (SECRETO_DISTINTO)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs)
  );

  logic [31:0] original [0:N_WORDS-1];

  // ---------------------------------------------------------------------------
  // Comprobaciones
  // ---------------------------------------------------------------------------

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check1(input string nombre,
                        input logic obtenido,
                        input logic esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-42s obtenido %b, esperado %b",
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
        $display("  FALLA  %-42s obtenido %0d, esperado %0d",
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

  integer i, c, malos, n_palabras;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_credencial.vcd");
      $dumpvars(0, tb_credencial);
    end

    rst_n = 1'b0;

    // Los bloques initial de imem y dmem barren sus arreglos a cero en el
    // tiempo 0, asi que la carga va un paso despues para no competir con ellos.
    #1;
    $readmemh("../../tools/programas/cifrar_archivo.hex", dut.u_imem.storage);
    $readmemh("../../tools/programas/archivo_prueba.hex", dut.u_dmem.storage);

    for (i = 0; i < N_WORDS; i = i + 1)
      original[i] = dut.u_dmem.storage[i];
    n_palabras = 2 * original[W_BUF + 1];

    $display("=== tb_credencial: cifrar con la credencial equivocada ===");
    $display("");

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halted && c < CICLOS_MAX) begin
      @(posedge clk);
      c = c + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("  (se detuvo tras %0d ciclos, PSW = %08h)", c, psw);
    $display("");

    // ------------------------------------------------------------------------
    $display("[1] la boveda rechaza la credencial");
    // ------------------------------------------------------------------------

    check1("el procesador llega a HALT, no se cuelga", halted,             1'b1);
    check1("AUTHFAIL encendido: el LOGIN no coincidio", psw[`PSW_AUTHFAIL], 1'b1);
    check1("AUTH apagado: no hubo sesion",              psw[`PSW_AUTH],     1'b0);
    check1("EXC encendido: hubo una operacion anulada", psw[`PSW_EXC],      1'b1);
    check_int("y la causa es DENIED",
              psw[`PSW_CAUSE], `CAUSE_DENIED);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] el archivo no se cifro");
    // ------------------------------------------------------------------------

    malos = 0;
    for (i = 0; i < 2 + n_palabras; i = i + 1)
      if (dut.u_dmem.storage[W_BUF + i] !== original[W_BUF + i])
        malos = malos + 1;
    check_int("el buffer quedo identico al original", malos, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] aislamiento de la boveda");
    // ------------------------------------------------------------------------
    // La llave es la que arma cargar_llave.s. Aqui nunca llega a instalarse,
    // pero vive en registros, y ninguna instruccion debe haberla llevado a
    // memoria. El buffer se excluye por el mismo motivo que en tb_cifrado.sv:
    // con un archivo cualquiera podria traer esos valores legitimamente.

    malos = 0;
    for (i = 0; i < N_WORDS; i = i + 1) begin
      if (!(i >= W_BUF + 2 && i < W_BUF + 2 + n_palabras)) begin
        if (dut.u_dmem.storage[i] === 32'h1111_1111 ||
            dut.u_dmem.storage[i] === 32'h2222_2222 ||
            dut.u_dmem.storage[i] === 32'h3333_3333 ||
            dut.u_dmem.storage[i] === 32'h4444_4444) malos = malos + 1;
      end
    end
    check_int("ninguna subllave aparece en los 64 KB de datos", malos, 0);

`ifdef FORCE_FAIL
    $display("");
    $display("  [autoprueba del arnes]");
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    $display("");
    resumen();
  end

endmodule
