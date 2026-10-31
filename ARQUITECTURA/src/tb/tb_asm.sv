`timescale 1ns/1ps

// =============================================================================
// tb_asm.sv - El ensamblador contra el procesador de verdad.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Carga en el procesador el binario que produjo cerbero_asm.py a partir de
// tools/programas/feistel.s y comprueba que cifra bien. Es el unico testbench
// que no construye su programa adentro: el .hex entra por las macros
// CERBERO_IMEM_FILE y CERBERO_DMEM_FILE, que el makefile define al compilar.
//
// -----------------------------------------------------------------------------
// QUE DEMUESTRA, Y POR QUE ES LA PRUEBA QUE CIERRA LA CADENA
// -----------------------------------------------------------------------------
// tb_top.sv ya corre el mismo cifrado, pero construye los bundles con funciones
// de codificacion escritas dentro del propio testbench. Eso prueba el hardware
// y no prueba el ensamblador.
//
// Aqui los bundles los produce la herramienta, desde texto, con su propia tabla
// de campos. Si el ensamblador pusiera un campo un bit corrido, el procesador
// ejecutaria otra cosa y el bloque saldria distinto. Que los dos caminos
// terminen en el mismo criptograma es lo que dice que la cadena completa
// (fuente en ensamblador -> binario -> RTL) es correcta de punta a punta.
//
// Los valores esperados se calcularon FUERA del simulador con la formula del
// enunciado, asi que no vienen ni del RTL ni del ensamblador:
//
//   F(x,k) = (ROL32(x,5) + k) XOR ROL32(x,13)
//   cifrar: (L,R) -> (R, L XOR F(R,k))
//
//   claro    L=DEADBEEF  R=CAFEBABE
//   cifrado  L=677DE658  R=47BBFB52
//
// -----------------------------------------------------------------------------
// EL CIERRE AUTOMATICO DE SESION
// -----------------------------------------------------------------------------
// El programa no ejecuta LOGOUT. La rutina de cifrado vive en la region segura
// y, al retornar, el PC la abandona: la boveda cierra la sesion por su cuenta.
// De ahi que al final AUTH tenga que estar APAGADO aunque el cifrado haya salido
// bien. Es la propiedad del ISA 8.3 y es la unica forma de comprobarla sobre un
// programa real, porque hace falta que el PC se mueva de verdad.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_asm;

  // Tiene que alcanzar para la region segura, que empieza en 0x7000
  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 64;

  localparam logic [31:0] CLARO_L = 32'hDEAD_BEEF;
  localparam logic [31:0] CLARO_R = 32'hCAFE_BABE;
  localparam logic [31:0] CIFRA_L = 32'h677D_E658;
  localparam logic [31:0] CIFRA_R = 32'h47BB_FB52;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic                         halted;
  logic [`XLEN-1:0]             psw;
  logic [`NREGS-1:0][`XLEN-1:0] regs;

  // Las memorias se inicializan desde los archivos que pasa el makefile; la
  // region segura y el secreto quedan en sus valores por omision, que son los
  // que supone el programa.
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
        $display("  FALLA  %-44s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-44s %08h", nombre, obtenido);
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
        $display("  FALLA  %-44s obtenido %b, esperado %b",
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

  integer ciclos;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_asm.vcd");
      $dumpvars(0, tb_asm);
    end

    $display("=== tb_asm: el binario del ensamblador sobre el procesador ===");

    // El programa esta ya en las memorias: lo cargo $readmemh al elaborar
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    // El programa es corto, pero la rutina esta en 0x7000 y se llega por un
    // salto indirecto, asi que el tope solo cubre los bundles ejecutados.
    ciclos = 0;
    while (!halted && ciclos < 500) begin
      @(posedge clk);
      ciclos = ciclos + 1;
    end
    // Que terminen los bundles en vuelo
    repeat (8) @(posedge clk);
    #1;

    $display("");
    $display("  el programa se detuvo tras %0d ciclos", ciclos);
    $display("");

    check1 ("el procesador se detuvo", halted, 1'b1);

    // ------------------------------------------------------------------------
    // El cifrado
    // ------------------------------------------------------------------------

    check32("la mitad L cifrada, en R10", regs[10], CIFRA_L);
    check32("la mitad R cifrada, en R11", regs[11], CIFRA_R);

    // Y guardada en memoria por los dos SW del final
    check32("la mitad L guardada en 0x40", dut.u_dmem.storage[16], CIFRA_L);
    check32("la mitad R guardada en 0x44", dut.u_dmem.storage[17], CIFRA_R);

    // El bloque claro tiene que seguir donde estaba: el programa no lo pisa
    check32("el bloque claro quedo intacto, L", dut.u_dmem.storage[8], CLARO_L);
    check32("el bloque claro quedo intacto, R", dut.u_dmem.storage[9], CLARO_R);

    // ------------------------------------------------------------------------
    // El estado de la boveda y del PSW
    // ------------------------------------------------------------------------

    check1 ("sin fallas en el PSW", psw[`PSW_EXC], 1'b0);
    check1 ("sin AUTHFAIL: el LOGIN salio bien", psw[`PSW_AUTHFAIL], 1'b0);
    // Al retornar, el PC dejo la region segura y la boveda cerro sola
    check1 ("la sesion se cerro al salir de la region segura",
            psw[`PSW_AUTH], 1'b0);

    // ------------------------------------------------------------------------
    // El enlace de la llamada
    // ------------------------------------------------------------------------
    // El jalr esta en 0x00A0 y el enlace vale PC + 32, que es 0x00C0. Que R15
    // traiga ese valor es lo que hizo que el retorno aterrizara en el bundle
    // correcto, dos adelante del salto.

    check32("R15 trae el enlace de la llamada", regs[15], 32'h0000_00C0);

    // ------------------------------------------------------------------------
    // Aislamiento: ninguna palabra de la llave puede haber salido de su sitio
    // ------------------------------------------------------------------------
    // Las palabras 4 a 7 son las que el programa cargo a proposito. Fuera de
    // ahi, encontrar una subllave significaria que la boveda se filtro.

    tests_run = tests_run + 1;
    if (dut.u_dmem.storage[16] === 32'h1111_1111 ||
        dut.u_dmem.storage[17] === 32'h1111_1111 ||
        regs[1] === 32'h1111_1111) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  una palabra de la llave aparecio fuera de su sitio");
    end else begin
      $display("  ok     ninguna subllave se filtro");
    end

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'd0, 32'd1);
`endif

    resumen();
  end

endmodule
