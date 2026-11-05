`timescale 1ns/1ps

// =============================================================================
// tb_mem_system.sv - Testbench del subsistema de memoria principal.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Este arnes responde la pregunta central de la Iteracion 2: cuanto cuesta de
// verdad traer una linea de memoria principal. No se conforma con que el
// subsistema entregue los datos correctos; MIDE los ciclos y los compara contra
// el valor teorico calculado desde las constantes del enunciado:
//
//     T_mem = MEM_FIRST_WORD + (LINE_WORDS-1) * MEM_CLK_DIV = 25 + 7*4 = 53
//
// La comparacion es contra `T_MEM, no contra un 53 escrito a mano. Si alguien
// cambia la frecuencia de memoria en cerbero_defs.svh, la prueba se ajusta sola
// y sigue siendo una prueba: un numero fijo aqui convertiria el arnes en una
// copia del error que quiera cometerse alla.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Una lectura entrega la linea correcta, las 8 palabras
//   2. T_mem medido == T_mem teorico, y se repite en lecturas sucesivas
//   3. Un desalojo se acepta en un ciclo y se drena solo
//   4. El drenado escribe de verdad en memoria, y solo lo que la mascara marca
//   5. El riesgo RAW: leer una linea encolada devuelve el dato NUEVO
//   6. El drenado no le roba el bus a una lectura que no tiene conflicto
//   7. El buffer se llena y lo avisa
// =============================================================================

`include "cerbero_defs.svh"

module tb_mem_system;

  localparam int NUM_WORDS = `MEM_WORDS;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                    rst_n;
  logic                    req;
  logic [`MEM_LIDX_W-1:0]  req_linea;
  logic                    listo;
  logic [`LINE_W-1:0]      linea_datos;

  logic                    ev_push;
  logic [`MEM_LIDX_W-1:0]  ev_linea;
  logic [`LINE_W-1:0]      ev_datos;
  logic [`LINE_WORDS-1:0]  ev_mascara;
  logic                    ev_lleno;

  logic                    mem_clk, ocupado, ev_vacio, raw_conflicto;
  logic [`EVICT_IDX_W:0]   ev_ocupadas;
  logic                    inicia_lectura, inicia_drenado;

  mem_system #(.NUM_WORDS (NUM_WORDS)) dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .req            (req),
      .req_linea      (req_linea),
      .listo          (listo),
      .linea_datos    (linea_datos),
      .ev_push        (ev_push),
      .ev_linea       (ev_linea),
      .ev_datos       (ev_datos),
      .ev_mascara     (ev_mascara),
      .ev_lleno       (ev_lleno),
      .mem_clk        (mem_clk),
      .ocupado        (ocupado),
      .ev_vacio       (ev_vacio),
      .ev_ocupadas    (ev_ocupadas),
      .raw_conflicto  (raw_conflicto),
      .inicia_lectura (inicia_lectura),
      .inicia_drenado (inicia_drenado)
  );

  // ---------------------------------------------------------------------------
  // Arnes
  // ---------------------------------------------------------------------------

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check(input string nombre,
                       input integer obtenido,
                       input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %0d, esperado %0d",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-46s %0d", nombre, obtenido);
      end
    end
  endtask

  task automatic check_hex(input string nombre,
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

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  function automatic logic [`XLEN-1:0] palabra(input logic [`LINE_W-1:0] l,
                                               input integer w);
    begin
      palabra = l[w*`XLEN +: `XLEN];
    end
  endfunction

  function automatic logic [`LINE_W-1:0] linea_patron(input logic [`XLEN-1:0] base);
    integer w;
    begin
      linea_patron = '0;
      for (w = 0; w < `LINE_WORDS; w = w + 1)
        linea_patron[w*`XLEN +: `XLEN] = base + w;
    end
  endfunction

  // Carga la memoria con un patron reconocible: cada palabra guarda su propia
  // direccion de palabra con un prefijo. Asi, una linea leida de la direccion
  // equivocada o con las palabras desordenadas se delata sola.
  task automatic sembrar_memoria();
    integer w;
    begin
      for (w = 0; w < NUM_WORDS; w = w + 1)
        dut.u_mem.storage[w] = 32'h5EED_0000 + w;
    end
  endtask

  // Lee una linea y devuelve cuantos ciclos pasaron desde que se emitio la
  // solicitud hasta que llego el dato. Esta es la medicion de T_mem.
  task automatic leer_linea(input  logic [`MEM_LIDX_W-1:0] l,
                            output integer                 ciclos,
                            output logic [`LINE_W-1:0]     datos);
    begin
      // Se emite la solicitud justo despues de un flanco, de modo que el
      // siguiente flanco sea el primero en que el controlador la ve.
      req       = 1'b1;
      req_linea = l;
      ciclos    = 0;

      forever begin
        @(posedge clk);
        #1;
        ciclos = ciclos + 1;
        if (listo) begin
          datos = linea_datos;
          req   = 1'b0;
          disable leer_linea;
        end
        if (ciclos > 1000) begin
          $display("  FALLA  la lectura de la linea %0d nunca termino", l);
          tests_failed = tests_failed + 1;
          req = 1'b0;
          disable leer_linea;
        end
      end
    end
  endtask

  task automatic depositar(input logic [`MEM_LIDX_W-1:0] l,
                           input logic [`LINE_W-1:0]     d,
                           input logic [`LINE_WORDS-1:0] m);
    begin
      ev_push    = 1'b1;
      ev_linea   = l;
      ev_datos   = d;
      ev_mascara = m;
      @(posedge clk);
      #1;
      ev_push = 1'b0;
    end
  endtask

  task automatic esperar_drenado();
    integer guarda;
    begin
      guarda = 0;
      while (!ev_vacio && guarda < 5000) begin
        @(posedge clk);
        #1;
        guarda = guarda + 1;
      end
      if (guarda >= 5000) begin
        $display("  FALLA  el buffer nunca se drenó");
        tests_failed = tests_failed + 1;
      end
      // Que termine la transaccion en vuelo
      while (ocupado) begin
        @(posedge clk);
        #1;
      end
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n      = 1'b0;
      req        = 1'b0;
      req_linea  = '0;
      ev_push    = 1'b0;
      ev_linea   = '0;
      ev_datos   = '0;
      ev_mascara = '0;
      @(posedge clk);
      #1 rst_n = 1'b1;
      @(posedge clk);
      #1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i, ciclos, ciclos2;
  logic [`LINE_W-1:0] datos;
  logic [`XLEN-1:0]   base;

  initial begin
    if ($test$plusargs("VCD") || $value$plusargs("VCD=%s", i)) begin
      $dumpfile("tb_mem_system.vcd");
      $dumpvars(0, tb_mem_system);
    end

    $display("");
    $display("=== tb_mem_system: la memoria principal con su latencia real ===");
    $display("");
    $display("  configuracion");
    $display("    frecuencia del procesador        100 MHz");
    $display("    divisor de memoria               %0d", `MEM_CLK_DIV);
    $display("    frecuencia de memoria            %0d MHz", 100 / `MEM_CLK_DIV);
    $display("    latencia de primera palabra      %0d ciclos de procesador",
             `MEM_FIRST_WORD);
    $display("    resto del burst                  %0d palabras x %0d = %0d ciclos",
             `MEM_BURST_REST, `MEM_CLK_DIV, `MEM_BURST_REST * `MEM_CLK_DIV);
    $display("    T_mem teorico                    %0d ciclos de procesador",
             `T_MEM);

    reiniciar();
    sembrar_memoria();

    // ---- 1. Una lectura ----------------------------------------------------
    $display("");
    $display("[1] una lectura entrega la linea completa y correcta");
    leer_linea(11'd10, ciclos, datos);
    base = 32'h5EED_0000 + 10 * `LINE_WORDS;
    for (i = 0; i < `LINE_WORDS; i = i + 1)
      check_hex($sformatf("palabra %0d de la linea 10", i),
                palabra(datos, i), base + i);

    // ---- 2. T_mem ----------------------------------------------------------
    // El numero que esta iteracion existe para producir.
    $display("");
    $display("[2] T_mem medido contra T_mem teorico");
    check("ciclos de la lectura anterior", ciclos, `T_MEM);

    leer_linea(11'd200, ciclos2, datos);
    check("ciclos de una segunda lectura", ciclos2, `T_MEM);
    base = 32'h5EED_0000 + 200 * `LINE_WORDS;
    check_hex("y su palabra 0 es la correcta", palabra(datos, 0), base);
    check_hex("y su palabra 7 tambien",        palabra(datos, 7), base + 7);

    // Una lectura inmediatamente despues de otra, sin ciclos muertos: el
    // protocolo tiene que soportarlo sin que la segunda herede nada de la
    // primera.
    leer_linea(11'd201, ciclos2, datos);
    check("ciclos de una lectura encadenada", ciclos2, `T_MEM);

    // ---- 3. Desalojo y drenado ----------------------------------------------
    // El punto del eviction buffer: el desalojo se acepta en UN ciclo, no en
    // T_mem. Lo que tarde en llegar a memoria ya no detiene a nadie.
    $display("");
    $display("[3] un desalojo se acepta en un ciclo y se drena solo");
    reiniciar();
    sembrar_memoria();

    check1("el buffer arranca vacio", ev_vacio, 1'b1);
    depositar(11'd50, linea_patron(32'hDEAD_0000), 8'hFF);
    check("una entrada encolada", ev_ocupadas, 1);

    esperar_drenado();
    check1("el buffer se vacio solo", ev_vacio, 1'b1);

    // ---- 4. El drenado escribe de verdad -----------------------------------
    // Se comprueba contra el arreglo de la memoria, no contra la salida del
    // buffer: lo que importa es que el dato HAYA LLEGADO.
    $display("");
    $display("[4] lo drenado quedo escrito en memoria");
    for (i = 0; i < `LINE_WORDS; i = i + 1)
      check_hex($sformatf("memoria, palabra %0d de la linea 50", i),
                dut.u_mem.storage[50 * `LINE_WORDS + i], 32'hDEAD_0000 + i);

    $display("");
    $display("    y una mascara parcial solo toca sus palabras");
    reiniciar();
    sembrar_memoria();
    // Solo las palabras 2 y 5 estan sucias
    depositar(11'd60, linea_patron(32'hBEEF_0000), 8'b0010_0100);
    esperar_drenado();

    base = 32'h5EED_0000 + 60 * `LINE_WORDS;
    check_hex("palabra 1 intacta",     dut.u_mem.storage[60*`LINE_WORDS + 1],
              base + 1);
    check_hex("palabra 2 escrita",     dut.u_mem.storage[60*`LINE_WORDS + 2],
              32'hBEEF_0002);
    check_hex("palabra 3 intacta",     dut.u_mem.storage[60*`LINE_WORDS + 3],
              base + 3);
    check_hex("palabra 5 escrita",     dut.u_mem.storage[60*`LINE_WORDS + 5],
              32'hBEEF_0005);
    check_hex("palabra 7 intacta",     dut.u_mem.storage[60*`LINE_WORDS + 7],
              base + 7);

    // ---- 5. El riesgo RAW ---------------------------------------------------
    // El caso que justifica toda la logica de conflicto. Se desaloja una linea
    // y se pide INMEDIATAMENTE esa misma linea, antes de que el drenado haya
    // podido ocurrir. Si el conflicto no funcionara, la lectura traeria de
    // memoria el valor viejo y el error pasaria inadvertido.
    $display("");
    $display("[5] leer una linea que todavia esta en el buffer");
    reiniciar();
    sembrar_memoria();

    depositar(11'd70, linea_patron(32'hCAFE_0000), 8'hFF);
    req       = 1'b1;
    req_linea = 11'd70;
    #1;
    check1("el conflicto RAW se detecta", raw_conflicto, 1'b1);
    req = 1'b0;
    #1;

    leer_linea(11'd70, ciclos, datos);
    $display("    la lectura tardo %0d ciclos (T_mem mas la espera del drenado)",
             ciclos);
    check1("tardo mas que una lectura sin conflicto", (ciclos > `T_MEM), 1'b1);

    for (i = 0; i < `LINE_WORDS; i = i + 1)
      check_hex($sformatf("palabra %0d: el dato NUEVO, no el viejo", i),
                palabra(datos, i), 32'hCAFE_0000 + i);

    // ---- 6. Prioridad sin conflicto ----------------------------------------
    // Sin conflicto, el drenado no puede hacer esperar a una lectura: el
    // procesador esta detenido esperandola y el buffer no tiene a nadie.
    $display("");
    $display("[6] sin conflicto, la lectura tiene prioridad sobre el drenado");
    reiniciar();
    sembrar_memoria();

    // Se encola un desalojo a una linea LEJANA y se pide otra en el mismo ciclo
    depositar(11'd500, linea_patron(32'hF00D_0000), 8'hFF);
    leer_linea(11'd600, ciclos, datos);
    check("la lectura no espero al drenado", ciclos, `T_MEM);

    base = 32'h5EED_0000 + 600 * `LINE_WORDS;
    check_hex("y trajo la linea correcta", palabra(datos, 0), base);

    // El desalojo sigue pendiente y se drena despues, sin que nadie espere
    esperar_drenado();
    check_hex("el desalojo llego a memoria igual",
              dut.u_mem.storage[500 * `LINE_WORDS], 32'hF00D_0000);

    // ---- 7. Buffer lleno ----------------------------------------------------
    // Quien desaloja tiene que mirar ev_lleno. Si el subsistema dijera que hay
    // lugar cuando no lo hay, la linea se perderia en silencio.
    $display("");
    $display("[7] el buffer avisa cuando se llena");
    reiniciar();
    sembrar_memoria();

    // Se deposita mas rapido de lo que el bus puede drenar: ocho lineas
    // distintas en ocho ciclos, contra T_mem ciclos por drenado
    for (i = 0; i < `EVICT_ENTRIES; i = i + 1)
      depositar(11'd1000 + i[`MEM_LIDX_W-1:0],
                linea_patron(32'hA000_0000 + i * 32'h1000), 8'hFF);

    check1("el buffer esta lleno", ev_lleno, 1'b1);

    // Y se vacia solo, sin perder ninguna
    esperar_drenado();
    check1("se vacio", ev_vacio, 1'b1);
    for (i = 0; i < `EVICT_ENTRIES; i = i + 1)
      check_hex($sformatf("la linea %0d llego a memoria", 1000 + i),
                dut.u_mem.storage[(1000 + i) * `LINE_WORDS],
                32'hA000_0000 + i * 32'h1000);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", ciclos, 12345);
`endif

    $display("");
    resumen();
  end

endmodule
