`timescale 1ns/1ps

// =============================================================================
// tb_cifrado.sv - Cifrar y descifrar un archivo cualquiera.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es tb_archivo.sv sin valores fijos. Aquel prueba un archivo conocido contra
// un criptograma calculado aparte; este acepta el archivo que se le de, asi
// que no puede traer el criptograma escrito. Lee la cantidad de bytes y de
// bloques de la cabecera que deja load_file.py y comprueba lo que se puede
// comprobar sin conocer el archivo:
//
//   - los dos procesadores se detienen sin fallas y cierran la sesion
//   - la cabecera sobrevive a las dos corridas
//   - ninguna palabra del buffer queda en claro despues de cifrar
//   - el archivo vuelve byte por byte despues de descifrar
//   - ninguna subllave aparece en la memoria de datos
//
// Que el criptograma sea Feistel4 y no otra funcion invertible lo decide
// probar_flujo.py, que descifra el volcado con un modelo escrito aparte. Por
// eso este testbench se corre con "make cifrar", que encadena los dos.
//
// La imagen entra por archivo_libre.hex, en el directorio de build, y la
// produce el makefile a partir de la variable ARCHIVO.
//
// Con el plusarg +SOLO_CIFRAR corre solo el primer procesador y se salta los
// puntos [3] a [5]. Es lo que usa "make solo-cifrar".
//
// Con +CIFRAR=, +DESCIFRAR= y +LLAVE= carga otros programas y busca otra llave
// en el chequeo de aislamiento. Es lo que hace el makefile con LLAVE=.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_cifrado;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int W_BUF     = 32'h4000 / 4;     // 4096

  // Ciclos por bloque con holgura. El lazo de cifrar_archivo.s gasta unos
  // pocos bundles por ronda; el limite solo existe para que un programa
  // colgado no deje la simulacion corriendo para siempre.
  localparam int CICLOS_BASE       = 1000;
  localparam int CICLOS_POR_BLOQUE = 100;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  logic             halt_c, halt_d;
  logic [`XLEN-1:0] psw_c,  psw_d;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs_c, regs_d;
  /* verilator lint_on UNUSEDSIGNAL */

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) cif (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halt_c),
      .psw      (psw_c),
      .dbg_regs (regs_c)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) des (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halt_d),
      .psw      (psw_d),
      .dbg_regs (regs_d)
  );

  // Copia de la memoria antes de cifrar: es la referencia del viaje de vuelta
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
        $display("     La llave de cifrado, r5 a r8, no produce fallas: una llave distinta solo da otro criptograma");
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
  logic   solo_cifrar;

  // Los programas y la llave se pueden cambiar por plusarg; es lo que hace el
  // makefile cuando se le da LLAVE=. key[0] va en los bits [127:96].
  string        prog_cifrar, prog_descifrar;
  logic [127:0] llave;

  function automatic logic es_subllave(input logic [31:0] w);
    return w === llave[127:96] || w === llave[95:64] ||
           w === llave[63:32]  || w === llave[31:0];
  endfunction

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_cifrado.vcd");
      $dumpvars(0, tb_cifrado);
    end

    solo_cifrar = $test$plusargs("SOLO_CIFRAR");
    if (!$value$plusargs("CIFRAR=%s", prog_cifrar))
      prog_cifrar = "../../tools/programas/cifrar_archivo.hex";
    if (!$value$plusargs("DESCIFRAR=%s", prog_descifrar))
      prog_descifrar = "../../tools/programas/descifrar_archivo.hex";
    if (!$value$plusargs("LLAVE=%h", llave))
      llave = 128'h1111_1111_2222_2222_3333_3333_4444_4444;
    rst_n = 1'b0;

    // Los bloques initial de imem y dmem barren sus arreglos a cero en el
    // tiempo 0, asi que la carga va un paso despues para no competir con ellos.
    #1;
    $readmemh(prog_cifrar,         cif.u_imem.storage);
    $readmemh(prog_descifrar,      des.u_imem.storage);
    $readmemh("archivo_libre.hex", cif.u_dmem.storage);

    for (i = 0; i < N_WORDS; i = i + 1)
      original[i] = cif.u_dmem.storage[i];

    n_bytes    = original[W_BUF];
    n_bloques  = original[W_BUF + 1];
    n_palabras = 2 * n_bloques;
    limite     = CICLOS_BASE + CICLOS_POR_BLOQUE * n_bloques;

    if (solo_cifrar)
      $display("=== tb_cifrado: solo cifrar un archivo cualquiera ===");
    else
      $display("=== tb_cifrado: cifrar y descifrar un archivo cualquiera ===");
    $display("");

    // ------------------------------------------------------------------------
    $display("[1] el buffer que dejo load_file.py");
    // ------------------------------------------------------------------------

    $display("  (%0d bytes en %0d bloques de 64 bits)", n_bytes, n_bloques);

    // La cabecera tiene que ser coherente: 8 bytes por bloque, redondeando
    check_int("la cabecera es coherente",
              n_bloques, (n_bytes + 7) / 8);
    check1("y el buffer cabe en la memoria de datos",
           W_BUF + 2 + n_palabras <= N_WORDS, 1'b1);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] el procesador cifra");
    // ------------------------------------------------------------------------

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halt_c && c < limite) begin
      @(posedge clk);
      c = c + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("  (se detuvo tras %0d ciclos)", c);

    check1("el procesador que cifra se detuvo", halt_c, 1'b1);
    check1("sin fallas en su PSW",              psw_c[`PSW_EXC], 1'b0);
    check1("y la sesion se cerro al volver",    psw_c[`PSW_AUTH], 1'b0);
    diagnostico("cifra", psw_c);

    check_int("la cabecera sobrevivio al cifrado, bytes",
              cif.u_dmem.storage[W_BUF], n_bytes);
    check_int("y la cantidad de bloques",
              cif.u_dmem.storage[W_BUF + 1], n_bloques);

    malos = 0;
    for (i = 0; i < n_palabras; i = i + 1)
      if (cif.u_dmem.storage[W_BUF + 2 + i] === original[W_BUF + 2 + i])
        malos = malos + 1;
    check_int("ninguna palabra quedo en claro", malos, 0);

    // Lo que probar_flujo.py descifra con el modelo de referencia
    $writememh("cifrado_libre.hex", cif.u_dmem.storage);

    // Con +SOLO_CIFRAR la corrida termina aqui: el segundo procesador no
    // arranca y el criptograma lo verifica probar_flujo.py por su cuenta.
    if (!solo_cifrar) begin
      // ----------------------------------------------------------------------
      $display("");
      $display("[3] la memoria cifrada pasa al segundo procesador");
      // ----------------------------------------------------------------------

      rst_n = 1'b0;
      @(negedge clk);
      for (i = 0; i < N_WORDS; i = i + 1)
        des.u_dmem.storage[i] = cif.u_dmem.storage[i];

      // ----------------------------------------------------------------------
      $display("");
      $display("[4] el procesador descifra");
      // ----------------------------------------------------------------------

      repeat (3) @(posedge clk);
      #1 rst_n = 1'b1;

      c = 0;
      while (!halt_d && c < limite) begin
        @(posedge clk);
        c = c + 1;
      end
      repeat (8) @(posedge clk);
      #1;

      $display("  (se detuvo tras %0d ciclos)", c);

      check1("el procesador que descifra se detuvo", halt_d, 1'b1);
      check1("sin fallas en su PSW",                 psw_d[`PSW_EXC], 1'b0);
      check1("y su sesion tambien se cerro",         psw_d[`PSW_AUTH], 1'b0);
      diagnostico("descifra", psw_d);

      // ----------------------------------------------------------------------
      $display("");
      $display("[5] el archivo volvio");
      // ----------------------------------------------------------------------

      malos = 0;
      for (i = 0; i < 2 + n_palabras; i = i + 1)
        if (des.u_dmem.storage[W_BUF + i] !== original[W_BUF + i]) begin
          if (malos < 4)
            $display("  palabra %0d: %08h, esperado %08h", i,
                     des.u_dmem.storage[W_BUF + i], original[W_BUF + i]);
          malos = malos + 1;
        end
      check_int("cabecera y datos iguales al original", malos, 0);
    end

    // ------------------------------------------------------------------------
    $display("");
    $display("[6] aislamiento de la boveda");
    // ------------------------------------------------------------------------
    // La llave es la que instala vault_sesion.s, o la de +LLAVE si se dio.
    // Se recorre la memoria de datos completa de los dos procesadores, MENOS
    // los datos del buffer.
    //
    // Los datos del buffer se excluyen porque con un archivo cualquiera pueden
    // contener esos valores legitimamente. Con la llave por omision, un bloque
    // de ocho bytes en cero se cifra como L=22222222 R=AAAAAAAA, y la mitad L
    // coincide con la subllave k1; una imagen PNG trae decenas de bloques asi.
    // Esas
    // palabras no quedan sin revisar: las cifradas las compara una por una el
    // modelo de referencia de probar_flujo.py, y las descifradas el punto [5].
    // Una subllave escrita en el buffer haria fallar cualquiera de los dos.

    malos = 0;
    for (i = 0; i < N_WORDS; i = i + 1) begin
      if (!(i >= W_BUF + 2 && i < W_BUF + 2 + n_palabras)) begin
        if (es_subllave(cif.u_dmem.storage[i])) malos = malos + 1;
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
