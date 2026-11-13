`timescale 1ns/1ps

// =============================================================================
// tb_ejemplos.sv - Los programas de demostracion, comprobados.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Corre fibonacci.s, estadisticas.s y sesion_sin_logout.s en el procesador
// completo y compara lo que dejan en memoria y en registros contra los valores
// que sus propias cabeceras documentan.
//
// -----------------------------------------------------------------------------
// POR QUE HACE FALTA
// -----------------------------------------------------------------------------
// Los tres programas se escribieron para correrse a mano con `make correr`, que
// usa tb_programa.sv. Ese ejecutor imprime los registros y la memoria al
// terminar, pero NO compara nada: su unica condicion de exito es que el
// programa llegue a HALT. Un error aritmetico no lo detiene, y la salida se ve
// igual de bien con el resultado correcto que con uno equivocado.
//
// Eso convierte a los tres programas en demostraciones y no en pruebas. La
// diferencia importa porque las cabeceras ya traen los valores esperados
// calculados a mano: el oraculo estaba escrito, solo que nadie lo comparaba.
// Este testbench es esa comparacion, y con el los tres entran en `make` y
// defienden al procesador de una regresion en vez de solo ilustrarlo.
//
// -----------------------------------------------------------------------------
// QUE EJERCITA CADA UNO
// -----------------------------------------------------------------------------
//   fibonacci.s          382 bundles de aritmetica encadenada con la latencia
//                        de 3 bundles al limite, cuatro slots ocupados por
//                        bundle y 47 vueltas de un lazo con delay slot
//   estadisticas.s       lw.inc, maximo y minimo sin saltos, y una llamada a
//                        la subrutina __div32 con enlace y retorno
//   sesion_sin_logout.s  el cierre automatico de sesion de isa.md 8.3, visto
//                        desde el programa: tres fotos del PSW tomadas con
//                        MFPSW a un lado y al otro de la frontera
//
// El oraculo de Fibonacci no son los numeros de la cabecera sino un lazo que
// este testbench calcula por su cuenta, con la misma aritmetica de 32 bits que
// desborda. Copiar los 47 valores a mano habria probado que el procesador
// coincide con lo que alguien escribio, no con la sucesion.
//
// lazo_estres.s no esta aqui: son 900 018 ciclos, casi dos minutos de Icarus,
// demasiado para la suite de cada compilacion. Se corre a mano con
// `make correr PROG=lazo_estres.s MOSTRAR=0x200 PALABRAS=2` y sus valores
// esperados estan en su cabecera.
// =============================================================================

`include "cerbero_defs.svh"

module tb_ejemplos;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;

  // Tope de ciclos. El mas largo es recorrido_cache.s, que con la geometria de
  // serie termina en unos 17 800 ciclos porque paga 128 fallos de arranque mas
  // los 642 accesos; 25 000 deja holgura y corta un cuelgue enseguida. Los
  // otros cuatro caben de sobra (el siguiente son los 820 de estadisticas).
  localparam int TOPE = 25000;

  // Donde cada programa deja sus resultados
  localparam int W_FIB = 32'h0100 / 4;         // 64,  47 palabras
  localparam int W_EST = 32'h0040 / 4;         // 16,   6 palabras
  localparam int W_SES = 32'h0300 / 4;         // 192,  3 palabras
  localparam int W_CNT = 32'h0400 / 4;         // 256, 10 palabras
  localparam int W_REC = 32'h0100 / 4;         // 64,   2 palabras
  localparam int W_ARR = 32'h2000 / 4;         // 2048, el arreglo recorrido

  localparam int N_FIB = 47;

  // recorrido_cache.s: 128 lineas de 32 B recorridas 4 veces. Los contadores
  // de cache tienen que dar exactamente estos numeros, que no son una medicion
  // sino aritmetica (ver la cabecera del programa).
  localparam int N_LINEAS = 128;
  localparam int N_PASADAS = 4;

  // ---------------------------------------------------------------------------
  // Tres procesadores identicos, un programa cada uno
  // ---------------------------------------------------------------------------

  logic             halt_f, halt_e, halt_s, halt_c, halt_r;
  logic [`XLEN-1:0] psw_f,  psw_e,  psw_s,  psw_c,  psw_r;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs_f, regs_e, regs_s, regs_c, regs_r;
  /* verilator lint_on UNUSEDSIGNAL */

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) fib (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_f), .psw (psw_f), .dbg_regs (regs_f)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) est (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_e), .psw (psw_e), .dbg_regs (regs_e)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) ses (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_s), .psw (psw_s), .dbg_regs (regs_s)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) cnt (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_c), .psw (psw_c), .dbg_regs (regs_c)
  );

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) rec (
      .clk (clk), .rst_n (rst_n),
      .halted (halt_r), .psw (psw_r), .dbg_regs (regs_r)
  );

  // ---------------------------------------------------------------------------
  // El oraculo de Fibonacci, calculado aqui y no copiado
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] fibo [0:N_FIB + 1];

  task automatic calcular_fibonacci();
    integer k;
    begin
      fibo[0] = 32'd0;
      fibo[1] = 32'd1;
      // La suma trunca a 32 bits sola, que es lo que hace el procesador: F(48)
      // ya no cabe y los dos tienen que desbordar igual.
      for (k = 2; k <= N_FIB + 1; k = k + 1)
        fibo[k] = fibo[k-1] + fibo[k-2];
    end
  endtask

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

  task automatic check_int(input string  nombre,
                           input integer obtenido,
                           input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-44s obtenido %0d, esperado %0d",
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

  integer guarda_drenado;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_ejemplos.vcd");
      $dumpvars(0, tb_ejemplos);
    end

    calcular_fibonacci();
    rst_n = 1'b0;

    // Un paso despues del tiempo 0, para no competir con los initial de imem y
    // dmem que barren sus arreglos a cero.
    #1;
    $readmemh("../../tools/programas/fibonacci.hex",   fib.u_imem.storage);
    $readmemh("../../tools/programas/estadisticas.hex", est.u_imem.storage);
    $readmemh("../../tools/programas/sesion_sin_logout.hex", ses.u_imem.storage);
    $readmemh("../../tools/programas/contar_hasta_n.hex", cnt.u_imem.storage);
    $readmemh("../../tools/programas/recorrido_cache.hex", rec.u_imem.storage);
    // estadisticas.s es el unico de los tres con seccion .data: el arreglo de
    // ocho palabras que recorre.
    $readmemh("../../tools/programas/estadisticas_datos.hex", est.u_mem_sys.u_mem.storage);

    $display("=== tb_ejemplos: los programas de demostracion, comprobados ===");
    $display("");

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!(halt_f && halt_e && halt_s && halt_c && halt_r) && c < TOPE) begin
      @(posedge clk);
      c = c + 1;
    end

    // Y espera a que la jerarquia de memoria termine de escribir. Desde la
    // Iteracion 3 un store pasa por la cache y por dos buffers antes de llegar
    // a memoria principal, asi que revisarla apenas el programa se detiene
    // daria por perdidos stores que seguian en camino. Son ciclos del ARNES.
    guarda_drenado = 0;
    while (!(fib.mem_drenada && est.mem_drenada && ses.mem_drenada && cnt.mem_drenada
             && rec.mem_drenada) && guarda_drenado < 200000) begin
      @(posedge clk);
      guarda_drenado = guarda_drenado + 1;
    end
    #1;

    $display("  (los cinco corrieron en paralelo, %0d ciclos hasta el ultimo HALT)", c);
    $display("");

    // ------------------------------------------------------------------------
    $display("[1] fibonacci.s: F(0) a F(46) en memoria desde 0x100");
    // ------------------------------------------------------------------------

    check_int("el programa llego a HALT", halt_f, 1'b1);
    check_int("sin fallas en su PSW", psw_f[`PSW_EXC], 1'b0);

    // Los 47 valores contra la sucesion calculada arriba. Se cuentan los que no
    // coinciden en vez de imprimir 47 lineas; si alguno falla, se dice cual.
    malos = 0;
    for (i = 0; i < N_FIB; i = i + 1)
      if (fib.u_mem_sys.u_mem.storage[W_FIB + i] !== fibo[i]) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         F(%0d): %08h, esperado %08h", i,
                   fib.u_mem_sys.u_mem.storage[W_FIB + i], fibo[i]);
      end
    check_int("los 47 valores coinciden con la sucesion", malos, 0);

    // Los tres que el enunciado del programa fija a mano, que son justamente
    // los que desbordan: F(47) ya no cabe con signo y F(48) no cabe del todo.
    check32("r1 = F(47), que solo cabe sin signo", regs_f[1], fibo[47]);
    check32("r2 = F(48), truncado a 32 bits",      regs_f[2], fibo[48]);
    check32("r3 = 0, el contador llego al final",  regs_f[3], 32'd0);
    check32("r4 = 0x1BC, el puntero tras el ultimo",
            regs_f[4], 32'h0000_01BC);
    check32("F(46) es el ultimo que cabe con signo",
            fib.u_mem_sys.u_mem.storage[W_FIB + 46], 32'h6D73_E55F);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] estadisticas.s: seis resultados sobre ocho palabras con signo");
    // ------------------------------------------------------------------------

    check_int("el programa llego a HALT", halt_e, 1'b1);
    check_int("sin fallas en su PSW", psw_e[`PSW_EXC], 1'b0);

    // arreglo: 15, -3, 42, 7, -20, 8, 100, 6
    check32("suma      = 155", est.u_mem_sys.u_mem.storage[W_EST + 0], 32'h0000_009B);
    check32("maximo    = 100", est.u_mem_sys.u_mem.storage[W_EST + 1], 32'h0000_0064);
    check32("minimo    = -20", est.u_mem_sys.u_mem.storage[W_EST + 2], 32'hFFFF_FFEC);
    check32("negativos =   2", est.u_mem_sys.u_mem.storage[W_EST + 3], 32'h0000_0002);
    // Los dos ultimos salen de __div32: 155 / 8 = 19, residuo 3. Es la unica
    // prueba del proyecto que llama a la subrutina desde un programa de
    // verdad, con enlace y retorno, en vez de con los pares de div32_prueba.s.
    check32("promedio  =  19 (155 / 8 por __div32)",
            est.u_mem_sys.u_mem.storage[W_EST + 4], 32'h0000_0013);
    check32("residuo   =   3",  est.u_mem_sys.u_mem.storage[W_EST + 5], 32'h0000_0003);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] sesion_sin_logout.s: la sesion se cierra sola al salir");
    // ------------------------------------------------------------------------
    // Las tres palabras son fotos del PSW tomadas con MFPSW. Es el caso 8.3 del
    // ISA visto desde el lado del programa: el hardware cierra la sesion sin
    // que nadie ejecute LOGOUT, solo porque el PC salio de la region.

    check_int("el programa llego a HALT", halt_s, 1'b1);

    check32("dentro de la region, tras LOGIN: AUTH = 1",
            ses.u_mem_sys.u_mem.storage[W_SES + 0], 32'h0000_0010);
    check32("de vuelta afuera, sin LOGOUT: AUTH = 0",
            ses.u_mem_sys.u_mem.storage[W_SES + 1], 32'h0000_0000);
    check32("tras intentar F4E afuera: EXC con DENIED",
            ses.u_mem_sys.u_mem.storage[W_SES + 2], 32'h0000_0240);

    // Y el PSW final, leido del puerto y no de la memoria, tiene que contar lo
    // mismo: la ronda de afuera se anulo y la causa quedo registrada.
    check_int("el PSW final trae EXC encendido", psw_s[`PSW_EXC], 1'b1);
    check_int("y la causa es DENIED",
              psw_s[`PSW_CAUSE], `CAUSE_DENIED);
    check_int("la sesion quedo cerrada", psw_s[`PSW_AUTH], 1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] contar_hasta_n.s: el lazo minimo del manual");
    // ------------------------------------------------------------------------
    // Es el programa de referencia de docs/escribir_programas.md, el que se
    // escribe de memoria en una revision. Que este aqui comprobado es lo que
    // lo distingue de un ejemplo que nadie corrio.

    check_int("el programa llego a HALT", halt_c, 1'b1);
    check_int("sin fallas en su PSW", psw_c[`PSW_EXC], 1'b0);

    // Guarda 1, 2, 3 ... 10 desde 0x400
    malos = 0;
    for (i = 0; i < 10; i = i + 1)
      if (cnt.u_mem_sys.u_mem.storage[W_CNT + i] !== i + 1) malos = malos + 1;
    check_int("guardo 1 a 10 en memoria desde 0x400", malos, 0);

    // Y la suma, que es 1+2+...+10 = 55
    check32("la suma quedo en r6", regs_c[6], 32'd55);
    check32("y tambien en 0x440",
            cnt.u_mem_sys.u_mem.storage[32'h0440 / 4], 32'd55);

    // ------------------------------------------------------------------------
    $display("");
    $display("[5] recorrido_cache.s: los contadores de cache contra la aritmetica");
    // ------------------------------------------------------------------------
    // Este es el unico caso donde el oraculo no son solo los datos sino los
    // CONTADORES. El profesor pidio validar que las metricas son reales, y la
    // unica forma de hacerlo es con un programa cuyo numero de aciertos y
    // fallos se pueda calcular sin simular.
    //
    // El programa recorre 128 lineas en ciclo, 4 veces, sobre una cache que con
    // la geometria de serie tiene capacidad para exactamente 128 lineas. Por
    // eso:
    //
    //   fallos de lectura   = 128    solo los de arranque: la pasada 1 toca
    //                                cada linea por primera vez
    //   aciertos de lectura = 384    las pasadas 2, 3 y 4 completas,
    //                                128 x 3, porque el conjunto cabe justo
    //   fallos de escritura = 130    los 128 de la pasada de escritura mas los
    //                                2 del guardado final. Con
    //                                no-write-allocate NINGUN almacenamiento
    //                                acierta, porque ninguno trae su linea
    //   aciertos de escritura = 0    corolario del anterior
    //
    // Si la cache acertara de mas, el LRU estaria conservando lineas que
    // debio expulsar; si acertara de menos, estaria expulsando lineas que
    // caben. Las dos cosas se ven aqui y en ningun otro programa de la suite.

    check_int("el programa llego a HALT", halt_r, 1'b1);
    check_int("sin fallas en su PSW", psw_r[`PSW_EXC], 1'b0);

    // Primero los datos, porque un contador correcto sobre un calculo
    // equivocado no prueba nada
    malos = 0;
    for (i = 0; i < N_LINEAS; i = i + 1)
      if (rec.u_mem_sys.u_mem.storage[W_ARR + i * 8] !== i) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         linea %0d: %08h, esperado %08h", i,
                   rec.u_mem_sys.u_mem.storage[W_ARR + i * 8], i);
      end
    check_int("escribio i en la primera palabra de las 128 lineas", malos, 0);

    // 4 x (0 + 1 + ... + 127) = 4 x 8128 = 32512
    check32("r4 = suma de las cuatro pasadas", regs_r[4],
            N_PASADAS * (N_LINEAS * (N_LINEAS - 1)) / 2);
    check32("r8 = 128, el ultimo valor escrito mas uno", regs_r[8], N_LINEAS);
    check32("r2 = 0, no quedan pasadas",   regs_r[2], 32'd0);
    check32("r1 volvio a la base 0x2000",  regs_r[1], 32'h0000_2000);
    check32("la suma quedo en 0x100",
            rec.u_mem_sys.u_mem.storage[W_REC + 0],
            N_PASADAS * (N_LINEAS * (N_LINEAS - 1)) / 2);
    check32("y el contador en 0x104",
            rec.u_mem_sys.u_mem.storage[W_REC + 1], N_LINEAS);

    // Y ahora los contadores, que es el punto del caso. Se comparan solo si la
    // geometria compilada es la que hace valido el calculo: con otra
    // capacidad los numeros de arriba son distintos y compararlos seria
    // inventar una falla.
    if ((`L1D_SETS * `L1D_WAYS) == N_LINEAS) begin
      check_int("fallos de lectura = 128 (todos de arranque)",
                rec.perf_l1_load_miss, N_LINEAS);
      check_int("aciertos de lectura = 384 (las pasadas 2 a 4)",
                rec.perf_l1_load_hit, N_LINEAS * (N_PASADAS - 1));
      check_int("aciertos de escritura = 0 (no-write-allocate)",
                rec.perf_l1_store_hit, 0);
      check_int("fallos de escritura = 130 (128 del arreglo + 2 del final)",
                rec.perf_l1_store_miss, N_LINEAS + 2);
    end
    else begin
      $display("    nota   geometria de %0d lineas, no 128: no se comparan",
               `L1D_SETS * `L1D_WAYS);
      $display("           los contadores, porque el calculo a mano no aplica");
    end

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
