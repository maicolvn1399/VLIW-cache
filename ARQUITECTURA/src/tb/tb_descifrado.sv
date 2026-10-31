`timescale 1ns/1ps

// =============================================================================
// tb_descifrado.sv - Descifrar un archivo cifrado que viene de disco.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es la otra mitad de "make solo-cifrar". Aquel deja el criptograma en un
// contenedor (.bin) en disco; este lo recibe ya convertido en imagen por
// load_file.py --cifrado, lo descifra en un solo procesador con
// descifrar_archivo.s y vuelca la memoria para que extract_data.py recupere
// el archivo.
//
// A diferencia de tb_cifrado.sv, aqui no hay copia de memoria entre dos
// procesadores: el criptograma hace el viaje completo por el disco, que es el
// camino que seguiria un archivo real.
//
// Lo que se comprueba dentro de la simulacion no depende del archivo:
//
//   - el procesador se detiene sin fallas y cierra la sesion
//   - la cabecera sobrevive, porque nunca se cifra
//   - ninguna subllave aparece en la memoria de datos
//
// Que el resultado sea el archivo correcto lo decide probar_descifrado.py,
// que descifra el mismo contenedor con el modelo de referencia y, si se le da,
// lo compara tambien contra el original.
//
// La imagen entra por contenedor_libre.hex, en el directorio de build, y la
// produce el makefile a partir de la variable CIFRADO.
//
// Con +DESCIFRAR= y +LLAVE= carga otro programa y busca otra llave en el
// chequeo de aislamiento. Es lo que hace el makefile con LLAVE=.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_descifrado;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int W_BUF     = 32'h4000 / 4;     // 4096

  localparam int CICLOS_BASE       = 1000;
  localparam int CICLOS_POR_BLOQUE = 100;

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
      .RESET_PC    (32'h0000_0000)
  ) des (
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

  // Traduce el PSW a palabras cuando algo salio mal. Las comprobaciones dicen
  // QUE fallo; esto dice POR QUE, que es lo que hace falta para corregirlo.
  task automatic diagnostico(input string quien, input logic [`XLEN-1:0] p);
    begin
      if (p[`PSW_EXC] || p[`PSW_AUTHFAIL]) begin
        $display("  >> diagnostico del procesador que %s, PSW = %08h", quien, p);
        if (p[`PSW_AUTHFAIL])
          $display("     AUTHFAIL: el LOGIN fallo. La credencial que arma cargar_llave.s en r1 a r4 no coincide con ROT_SECRET de top.sv");
        if (p[`PSW_EXC])
          case (p[`PSW_CAUSE])
            `CAUSE_DENIED:   $display("     CAUSE = DENIED: la boveda anulo una operacion por falta de sesion. Con AUTHFAIL, es consecuencia de la credencial");
            `CAUSE_NOKEY:    $display("     CAUSE = NOKEY: una ronda pidio una ranura de llave sin instalar");
            `CAUSE_ILLOP:    $display("     CAUSE = ILLOP: el programa tiene una instruccion invalida");
            `CAUSE_MISALIGN: $display("     CAUSE = MISALIGN: un acceso a memoria desalineado");
            `CAUSE_RANGE:    $display("     CAUSE = RANGE: un acceso fuera de la memoria de datos");
            `CAUSE_WCONF:    $display("     CAUSE = WCONF: dos slots escribieron el mismo registro");
            default:         $display("     CAUSE = %0d", p[`PSW_CAUSE]);
          endcase
        $display("     La llave de cifrado, r5 a r8, no produce fallas: una llave distinta solo da otro resultado");
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

  integer i, c, malos, limite;
  integer n_bytes, n_bloques, n_palabras;

  // El programa y la llave se pueden cambiar por plusarg. key[0] va en los
  // bits [127:96].
  string        prog_descifrar;
  logic [127:0] llave;

  function automatic logic es_subllave(input logic [31:0] w);
    return w === llave[127:96] || w === llave[95:64] ||
           w === llave[63:32]  || w === llave[31:0];
  endfunction

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_descifrado.vcd");
      $dumpvars(0, tb_descifrado);
    end

    if (!$value$plusargs("DESCIFRAR=%s", prog_descifrar))
      prog_descifrar = "../../tools/programas/descifrar_archivo.hex";
    if (!$value$plusargs("LLAVE=%h", llave))
      llave = 128'h1111_1111_2222_2222_3333_3333_4444_4444;
    rst_n = 1'b0;

    // Los bloques initial de imem y dmem barren sus arreglos a cero en el
    // tiempo 0, asi que la carga va un paso despues para no competir con ellos.
    #1;
    $readmemh(prog_descifrar,         des.u_imem.storage);
    $readmemh("contenedor_libre.hex", des.u_dmem.storage);

    n_bytes    = des.u_dmem.storage[W_BUF];
    n_bloques  = des.u_dmem.storage[W_BUF + 1];
    n_palabras = 2 * n_bloques;
    limite     = CICLOS_BASE + CICLOS_POR_BLOQUE * n_bloques;

    $display("=== tb_descifrado: descifrar un archivo cifrado desde disco ===");
    $display("");

    // ------------------------------------------------------------------------
    $display("[1] el contenedor que cargo load_file.py --cifrado");
    // ------------------------------------------------------------------------

    $display("  (archivo original de %0d bytes, %0d bloques cifrados)",
             n_bytes, n_bloques);

    check_int("la cabecera es coherente",
              n_bloques, (n_bytes + 7) / 8);
    check1("y el buffer cabe en la memoria de datos",
           W_BUF + 2 + n_palabras <= N_WORDS, 1'b1);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] el procesador descifra");
    // ------------------------------------------------------------------------

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halted && c < limite) begin
      @(posedge clk);
      c = c + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("  (se detuvo tras %0d ciclos)", c);

    check1("el procesador que descifra se detuvo", halted, 1'b1);
    check1("sin fallas en su PSW",                 psw[`PSW_EXC], 1'b0);
    check1("y la sesion se cerro al volver",       psw[`PSW_AUTH], 1'b0);
    diagnostico("descifra", psw);

    check_int("la cabecera sobrevivio, bytes",
              des.u_dmem.storage[W_BUF], n_bytes);
    check_int("y la cantidad de bloques",
              des.u_dmem.storage[W_BUF + 1], n_bloques);

    // Lo que extract_data.py convierte de vuelta en archivo
    $writememh("descifrado_libre.hex", des.u_dmem.storage);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] aislamiento de la boveda");
    // ------------------------------------------------------------------------
    // La llave es la que arma cargar_llave.s, o la de +LLAVE si se dio. Los
    // datos del buffer se excluyen
    // por el mismo motivo que en tb_cifrado.sv: con un archivo cualquiera
    // pueden traer esos valores legitimamente, y probar_descifrado.py los
    // compara uno por uno contra el modelo de referencia.

    malos = 0;
    for (i = 0; i < N_WORDS; i = i + 1) begin
      if (!(i >= W_BUF + 2 && i < W_BUF + 2 + n_palabras)) begin
        if (es_subllave(des.u_dmem.storage[i])) malos = malos + 1;
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
