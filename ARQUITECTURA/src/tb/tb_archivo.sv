`timescale 1ns/1ps

// =============================================================================
// tb_archivo.sv - Cifrar y descifrar un archivo completo, de ida y vuelta.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es el caso 6 del enunciado y la prueba mas fuerte del proyecto. Monta DOS
// procesadores: uno corre cifrar_archivo.s sobre la imagen que produjo
// load_file.py, y el otro corre descifrar_archivo.s sobre el resultado del
// primero. El archivo tiene que volver byte por byte.
//
// -----------------------------------------------------------------------------
// POR QUE DOS PROCESADORES Y NO UNO
// -----------------------------------------------------------------------------
// Cifrar y descifrar son dos programas distintos, porque las rondas van en
// orden inverso y el opcode cambia, y las macros de archivo de top.sv son
// globales: las dos instancias cargarian el mismo binario. Asi que los
// programas entran por referencia jerarquica, con un $readmemh por instancia.
//
// Entre las dos corridas, el testbench copia la memoria de datos del primero al
// segundo. Es lo que en la practica hacen extract_data.py y load_file.py, pero
// dentro de la misma simulacion, lo que la vuelve determinista y la deja
// corriendo dentro de un solo `make`.
//
// -----------------------------------------------------------------------------
// LA IDA Y VUELTA NO ALCANZA SOLA
// -----------------------------------------------------------------------------
// Que el archivo vuelva demuestra que F4D deshace a F4E, y eso se cumpliria
// igual si las dos estuvieran mal de forma inversa: son funciones inversas por
// construccion y un error simetrico sobreviviria la prueba.
//
// Por eso el criptograma intermedio tambien se compara, contra valores
// calculados fuera del simulador con la formula del enunciado. Las dos mitades
// juntas son lo que cierra el caso:
//
//   bloque 0   claro 42524543 2D4F5245  ->  cifrado 1BB0FF04 C1B93A0C
//   bloque 1   claro 69632031 20617266  ->  cifrado 610667D9 FA8F3559
//   bloque 2   claro 6F747365 00212121  ->  cifrado 9151652F 00F0DEDC
//
// -----------------------------------------------------------------------------
// LA CABECERA NO SE CIFRA
// -----------------------------------------------------------------------------
// Las dos palabras de 0x4000 y 0x4004 quedan como estaban: el puntero del
// programa arranca en 0x4008. Tiene que ser asi porque extract_data.py lee la
// cantidad de bytes para recortar el relleno, y porque la longitud de un
// archivo no es secreta. El testbench lo comprueba en las dos corridas.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_archivo;

  // La region segura por omision empieza en 0x7000, asi que hace falta toda la
  // memoria de instrucciones; y el buffer vive en 0x4000, o sea la palabra 4096
  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int W_BUF     = 32'h4000 / 4;     // 4096

  localparam int N_BYTES   = 23;
  localparam int N_BLOQUES = 3;

  // El archivo en claro, tal como lo deja load_file.py en el buffer, y su
  // criptograma, calculado fuera del simulador. Van como arreglos y no como
  // localparam porque Icarus no acepta un patron de asignacion en un
  // localparam de arreglo desempaquetado.
  logic [31:0] CLARO   [0:5];
  logic [31:0] CIFRADO [0:5];

  task automatic valores_esperados();
    begin
      CLARO[0] = 32'h42524543;  CLARO[1] = 32'h2D4F5245;
      CLARO[2] = 32'h69632031;  CLARO[3] = 32'h20617266;
      CLARO[4] = 32'h6F747365;  CLARO[5] = 32'h00212121;

      CIFRADO[0] = 32'h1BB0FF04;  CIFRADO[1] = 32'hC1B93A0C;
      CIFRADO[2] = 32'h610667D9;  CIFRADO[3] = 32'hFA8F3559;
      CIFRADO[4] = 32'h9151652F;  CIFRADO[5] = 32'h00F0DEDC;
    end
  endtask

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // ---------------------------------------------------------------------------
  // Dos procesadores identicos: cambia el programa que se les carga
  // ---------------------------------------------------------------------------

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
        $display("  FALLA  %-42s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-42s %08h", nombre, obtenido);
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

  integer i, c, malos;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_archivo.vcd");
      $dumpvars(0, tb_archivo);
    end

    valores_esperados();
    rst_n = 1'b0;

    // Los bloques initial de imem y dmem barren sus arreglos a cero en el
    // tiempo 0, asi que la carga va un paso despues para no competir con ellos.
    #1;
    $readmemh("../../tools/programas/cifrar_archivo.hex",    cif.u_imem.storage);
    $readmemh("../../tools/programas/descifrar_archivo.hex", des.u_imem.storage);
    $readmemh("../../tools/programas/archivo_prueba.hex",    cif.u_dmem.storage);

    $display("=== tb_archivo: cifrar y descifrar un archivo completo ===");
    $display("");

    // ------------------------------------------------------------------------
    $display("[1] el buffer que dejo load_file.py");
    // ------------------------------------------------------------------------

    check_int("la cabecera dice los bytes del archivo",
              cif.u_dmem.storage[W_BUF], N_BYTES);
    check_int("y la cantidad de bloques de 64 bits",
              cif.u_dmem.storage[W_BUF + 1], N_BLOQUES);

    malos = 0;
    for (i = 0; i < 2 * N_BLOQUES; i = i + 1)
      if (cif.u_dmem.storage[W_BUF + 2 + i] !== CLARO[i]) malos = malos + 1;
    check_int("y las seis palabras del archivo en claro", malos, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] el procesador cifra");
    // ------------------------------------------------------------------------

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halt_c && c < 2000) begin
      @(posedge clk);
      c = c + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("  (se detuvo tras %0d ciclos, %0d bloques)", c, N_BLOQUES);

    check1("el procesador que cifra se detuvo", halt_c, 1'b1);
    check1("sin fallas en su PSW",              psw_c[`PSW_EXC], 1'b0);
    // Al retornar de la rutina el PC dejo la region segura
    check1("y la sesion se cerro al volver",    psw_c[`PSW_AUTH], 1'b0);

    // El criptograma, contra los valores calculados aparte
    for (i = 0; i < 2 * N_BLOQUES; i = i + 1)
      check32($sformatf("palabra %0d cifrada", i),
              cif.u_dmem.storage[W_BUF + 2 + i], CIFRADO[i]);

    // La cabecera no se toca: el puntero arranca en 0x4008
    check_int("la cabecera sobrevivio al cifrado, bytes",
              cif.u_dmem.storage[W_BUF], N_BYTES);
    check_int("y la cantidad de bloques",
              cif.u_dmem.storage[W_BUF + 1], N_BLOQUES);

    // Y nada del claro quedo en el buffer
    malos = 0;
    for (i = 0; i < 2 * N_BLOQUES; i = i + 1)
      if (cif.u_dmem.storage[W_BUF + 2 + i] === CLARO[i]) malos = malos + 1;
    check_int("ninguna palabra quedo en claro", malos, 0);

    // Para que extract_data.py pueda trabajar sobre un volcado de verdad
    $writememh("cifrado_volcado.hex", cif.u_dmem.storage);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] la memoria cifrada pasa al segundo procesador");
    // ------------------------------------------------------------------------

    rst_n = 1'b0;
    @(negedge clk);
    for (i = 0; i < N_WORDS; i = i + 1)
      des.u_dmem.storage[i] = cif.u_dmem.storage[i];

    malos = 0;
    for (i = 0; i < 2 * N_BLOQUES; i = i + 1)
      if (des.u_dmem.storage[W_BUF + 2 + i] !== CIFRADO[i]) malos = malos + 1;
    check_int("el criptograma llego entero al segundo", malos, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] el procesador descifra");
    // ------------------------------------------------------------------------

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halt_d && c < 2000) begin
      @(posedge clk);
      c = c + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    $display("  (se detuvo tras %0d ciclos)", c);

    check1("el procesador que descifra se detuvo", halt_d, 1'b1);
    check1("sin fallas en su PSW",                 psw_d[`PSW_EXC], 1'b0);
    check1("y su sesion tambien se cerro",         psw_d[`PSW_AUTH], 1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[5] el archivo volvio");
    // ------------------------------------------------------------------------

    for (i = 0; i < 2 * N_BLOQUES; i = i + 1)
      check32($sformatf("palabra %0d en claro otra vez", i),
              des.u_dmem.storage[W_BUF + 2 + i], CLARO[i]);

    check_int("y la cabecera sigue intacta",
              des.u_dmem.storage[W_BUF], N_BYTES);

    // ------------------------------------------------------------------------
    $display("");
    $display("[6] aislamiento de la boveda");
    // ------------------------------------------------------------------------
    // Caso 6 del enunciado: despues de cifrar, ninguna subllave puede haber
    // quedado visible. Se recorre la memoria de datos COMPLETA de los dos
    // procesadores, no solo el buffer.

    malos = 0;
    for (i = 0; i < N_WORDS; i = i + 1) begin
      if (cif.u_dmem.storage[i] === 32'h1111_1111 ||
          cif.u_dmem.storage[i] === 32'h2222_2222 ||
          cif.u_dmem.storage[i] === 32'h3333_3333 ||
          cif.u_dmem.storage[i] === 32'h4444_4444) malos = malos + 1;
      if (des.u_dmem.storage[i] === 32'h1111_1111 ||
          des.u_dmem.storage[i] === 32'h2222_2222 ||
          des.u_dmem.storage[i] === 32'h3333_3333 ||
          des.u_dmem.storage[i] === 32'h4444_4444) malos = malos + 1;
    end
    check_int("ninguna subllave aparece en los 64 KB de datos", malos, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[7] ni la credencial ni la llave quedan en registros");
    // ------------------------------------------------------------------------
    // La memoria de datos no es el unico sitio donde se puede filtrar una
    // llave. vault_sesion.s la arma en R5 a R8 y la credencial en R1 a R4, y
    // KSETW no borra nada: sin un borrado explicito, las ocho palabras siguen
    // en el banco cuando el programa termina, FUERA de la region segura, a la
    // vista de cualquier codigo que corra despues.
    //
    // Por eso vault_sesion.s pone un `movi rN, #0` en las dos ALU de los mismos
    // bundles que llevan los KSETW. Es gratis en ciclos, porque todos los slots
    // de un bundle leen el estado de registros PREVIO al bundle: el KSETW toma
    // su palabra antes de que el borrado surta efecto, incluso en el cuarto
    // bundle, donde S1 escribe R8 y S3 lo lee.
    //
    // Esta seccion es la que obliga a que siga siendo asi. Sin ella el borrado
    // se puede quitar y la suite entera pasa igual, que fue justo lo que pasaba
    // cuando se escribio el borrado: el cambio era correcto y nada lo defendia.

    malos = 0;
    for (i = 1; i <= 8; i = i + 1) begin
      if (regs_c[i] !== 32'd0) malos = malos + 1;
      if (regs_d[i] !== 32'd0) malos = malos + 1;
    end
    check_int("R1 a R8 quedan en cero en los dos procesadores", malos, 0);

    // Y por si alguien reacomoda el programa y usa otros registros: se barren
    // los dieciseis contra las ocho palabras secretas. Las cuatro de la llave
    // son las de la ranura 0 y las otras cuatro son ROT_SECRET, que es la
    // contrasena del procesador y no debe sobrevivir a la sesion tampoco.
    malos = 0;
    for (i = 0; i < `NREGS; i = i + 1) begin
      if (regs_c[i] === 32'h1111_1111 || regs_c[i] === 32'h2222_2222 ||
          regs_c[i] === 32'h3333_3333 || regs_c[i] === 32'h4444_4444 ||
          regs_c[i] === 32'h7654_3210 || regs_c[i] === 32'hFEDC_BA98 ||
          regs_c[i] === 32'h89AB_CDEF || regs_c[i] === 32'h0123_4567)
        malos = malos + 1;
      if (regs_d[i] === 32'h1111_1111 || regs_d[i] === 32'h2222_2222 ||
          regs_d[i] === 32'h3333_3333 || regs_d[i] === 32'h4444_4444 ||
          regs_d[i] === 32'h7654_3210 || regs_d[i] === 32'hFEDC_BA98 ||
          regs_d[i] === 32'h89AB_CDEF || regs_d[i] === 32'h0123_4567)
        malos = malos + 1;
    end
    check_int("ninguno de los 16 registros trae llave ni credencial", malos, 0);

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
