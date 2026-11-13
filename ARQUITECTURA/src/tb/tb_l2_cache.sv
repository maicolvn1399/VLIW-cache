`timescale 1ns/1ps

// =============================================================================
// tb_l2_cache.sv - Cache unificada de segundo nivel
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Lo que se fija aqui:
//
//   1. Aciertos y fallos de lectura y escritura, y que los cuatro contadores
//      de evento pulsen exactamente una vez cada uno cuando toca.
//   2. Que el hit time sea el de la macro L2_HIT_CYCLES, medido, no supuesto.
//   3. Write-back: que una escritura NO baje a memoria en el momento, y que la
//      linea salga al eviction buffer recien cuando la expulsan.
//   4. Write-allocate: que una escritura que falla traiga la linea y conserve
//      los bytes que su mascara no cubre.
//   5. El atajo de linea completa: con los 32 bytes enmascarados no hay que
//      leer memoria, asi que el fallo no cuesta T_mem.
//   6. LRU exacto de cuatro vias: que la victima sea la menos usada y no otra.
//   7. Invalidacion hacia atras: que al expulsar una linea valida se avise a
//      L1 con el numero de linea correcto.
//   8. Que el stall por eviction buffer lleno se cuente.
//   9. El vaciado de fin de programa: que saque TODO lo sucio y que
//      tiene_sucias quede en bajo, que es de lo que depende mem_drenada.
//  10. El contrato con el nivel de abajo: que mem_req baje en el ciclo de
//      mem_listo. Sin eso el controlador lee el pedido viejo como uno nuevo.
//
// El modelo de memoria de abajo responde con un patron que depende de la
// linea pedida, asi que un relleno que traiga la linea equivocada se nota en
// el dato y no hay que ir a mirar senales internas para descubrirlo.
// =============================================================================

`include "cerbero_defs.svh"

module tb_l2_cache();

  localparam int WAYS = 4;
  localparam int SETS = 128;

  // Latencia de memoria del modelo de abajo. No es T_MEM porque aqui no hay
  // mem_controller: es un numero corto para que la prueba no tarde, y lo unico
  // que importa es poder distinguir "fue a memoria" de "no fue".
  localparam int MEM_LAT = 6;

  logic clk = 1'b0;
  logic rst_n;

  always #5 clk = ~clk;

  // ---- Hacia arriba ---------------------------------------------------------
  logic                     req_lectura, req_escritura;
  logic [`MEM_LIDX_W-1:0]   req_linea;
  logic [`LINE_W-1:0]       req_wdata;
  logic [`LINE_MASK_W-1:0]  req_wmask;
  logic [`LINE_W-1:0]       rdata;
  logic                     listo;
  logic                     l2_inv_req;
  logic [`MEM_LIDX_W-1:0]   l2_inv_linea;
  logic                     vaciar, tiene_sucias;

  // ---- Hacia abajo ----------------------------------------------------------
  logic                     mem_req;
  logic [`MEM_LIDX_W-1:0]   mem_linea;
  logic                     mem_listo;
  logic [`LINE_W-1:0]       mem_datos;

  logic                     ev_push;
  logic [`MEM_LIDX_W-1:0]   ev_linea;
  logic [`LINE_W-1:0]       ev_datos;
  logic [`LINE_MASK_W-1:0]  ev_mascara;
  logic                     ev_lleno;

  logic ev_stall_evict, ev_l2_load_hit, ev_l2_load_miss;
  logic ev_l2_store_hit, ev_l2_store_miss;

  l2_cache #(.WAYS(WAYS), .SETS(SETS)) dut (
      .clk (clk), .rst_n (rst_n),
      .req_lectura (req_lectura), .req_escritura (req_escritura),
      .req_linea (req_linea), .req_wdata (req_wdata), .req_wmask (req_wmask),
      .rdata (rdata), .listo (listo),
      .l2_inv_req (l2_inv_req), .l2_inv_linea (l2_inv_linea),
      .vaciar (vaciar), .tiene_sucias (tiene_sucias),
      .mem_req (mem_req), .mem_linea (mem_linea),
      .mem_listo (mem_listo), .mem_datos (mem_datos),
      .ev_push (ev_push), .ev_linea (ev_linea), .ev_datos (ev_datos),
      .ev_mascara (ev_mascara), .ev_lleno (ev_lleno),
      .ev_stall_evict (ev_stall_evict),
      .ev_l2_load_hit (ev_l2_load_hit), .ev_l2_load_miss (ev_l2_load_miss),
      .ev_l2_store_hit (ev_l2_store_hit), .ev_l2_store_miss (ev_l2_store_miss)
  );

  // ===========================================================================
  // Modelo de la memoria de abajo
  //
  // Devuelve un patron que depende de la linea, para que un relleno con la
  // linea equivocada se vea en el dato. Respeta el mismo contrato que
  // mem_controller.sv: listo es un pulso de un ciclo.
  // ===========================================================================

  function automatic logic [`LINE_W-1:0] patron(input int unsigned l);
    logic [`LINE_W-1:0] p;
    for (int w = 0; w < `LINE_WORDS; w++)
      p[w*`XLEN +: `XLEN] = 32'h00A0_0000 + (l << 8) + w;
    return p;
  endfunction

  int unsigned mem_cuenta;
  int unsigned lecturas_a_memoria;   // cuantas veces de verdad bajo a memoria

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mem_listo          <= 1'b0;
      mem_datos          <= '0;
      mem_cuenta         <= 0;
      lecturas_a_memoria <= 0;
    end
    else begin
      mem_listo <= 1'b0;
      if (mem_req && mem_cuenta == 0) begin
        mem_cuenta         <= MEM_LAT;
        lecturas_a_memoria <= lecturas_a_memoria + 1;
      end
      else if (mem_cuenta == 1) begin
        mem_cuenta <= 0;
        mem_listo  <= 1'b1;
        mem_datos  <= patron(mem_linea);
      end
      else if (mem_cuenta > 1) begin
        mem_cuenta <= mem_cuenta - 1;
      end
    end
  end

  // Vigilante del contrato: si mem_req sigue arriba en el ciclo de mem_listo,
  // el controlador real leeria el pedido viejo como uno nuevo.
  int unsigned violaciones_contrato;
  always_ff @(posedge clk)
    if (!rst_n)                 violaciones_contrato <= 0;
    else if (mem_listo && mem_req) violaciones_contrato <= violaciones_contrato + 1;

  // ===========================================================================
  // Registro de lo que sale por el eviction buffer
  // ===========================================================================

  localparam int MAX_EV = 64;
  logic [`MEM_LIDX_W-1:0] ev_lineas_vistas [0:MAX_EV-1];
  logic [`LINE_W-1:0]     ev_datos_vistos  [0:MAX_EV-1];
  int unsigned            ev_n;

  always_ff @(posedge clk)
    if (!rst_n) ev_n <= 0;
    else if (ev_push && !ev_lleno && ev_n < MAX_EV) begin
      ev_lineas_vistas[ev_n] <= ev_linea;
      ev_datos_vistos[ev_n]  <= ev_datos;
      ev_n                   <= ev_n + 1;
    end

  // Invalidaciones vistas
  int unsigned            inv_n;
  logic [`MEM_LIDX_W-1:0] inv_ultima;
  always_ff @(posedge clk)
    if (!rst_n) begin inv_n <= 0; inv_ultima <= '0; end
    else if (l2_inv_req) begin
      inv_n      <= inv_n + 1;
      inv_ultima <= l2_inv_linea;
    end

  // ===========================================================================
  // Marcador
  // ===========================================================================

  int tests_run = 0, tests_failed = 0;

  task automatic check(input string nombre, input integer obtenido,
                       input integer esperado);
    begin
      tests_run++;
      if (obtenido !== esperado) begin
        tests_failed++;
        $display("  FALLA  %-50s obtenido %0d, esperado %0d",
                 nombre, obtenido, esperado);
      end
      else $display("  ok     %-50s %0d", nombre, obtenido);
    end
  endtask

  task automatic check_hex(input string nombre,
                           input logic [`XLEN-1:0] obtenido,
                           input logic [`XLEN-1:0] esperado);
    begin
      tests_run++;
      if (obtenido !== esperado) begin
        tests_failed++;
        $display("  FALLA  %-50s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end
      else $display("  ok     %-50s %08h", nombre, obtenido);
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

  // ===========================================================================
  // Accesos
  //
  // Sostienen la peticion hasta ver listo y la sueltan ahi mismo, que es lo
  // que hace el arbitro de verdad. Cuentan los ciclos que costo el acceso.
  // ===========================================================================

  int unsigned ciclos_acceso;
  logic        listo_visto;
  logic [`LINE_W-1:0] dato_leido;

  // Contadores de evento acumulados durante el ultimo acceso
  int unsigned n_ld_hit, n_ld_miss, n_st_hit, n_st_miss, n_stall_ev;

  task automatic limpiar_eventos();
    begin
      n_ld_hit = 0; n_ld_miss = 0; n_st_hit = 0; n_st_miss = 0; n_stall_ev = 0;
    end
  endtask

  task automatic muestrear_eventos();
    begin
      if (ev_l2_load_hit)   n_ld_hit++;
      if (ev_l2_load_miss)  n_ld_miss++;
      if (ev_l2_store_hit)  n_st_hit++;
      if (ev_l2_store_miss) n_st_miss++;
      if (ev_stall_evict)   n_stall_ev++;
    end
  endtask

  task automatic leer(input int unsigned l);
    begin
      limpiar_eventos();
      ciclos_acceso = 0;
      @(negedge clk);
      req_lectura = 1'b1; req_escritura = 1'b0;
      req_linea   = l[`MEM_LIDX_W-1:0];
      req_wdata   = '0; req_wmask = '0;
      listo_visto = 1'b0;
      while (!listo_visto) begin
        @(posedge clk);
        muestrear_eventos();
        ciclos_acceso++;
        if (listo) begin
          dato_leido  = rdata;
          listo_visto = 1'b1;
        end
      end
      @(negedge clk);
      req_lectura = 1'b0;
    end
  endtask

  task automatic escribir(input int unsigned l,
                          input logic [`LINE_W-1:0] d,
                          input logic [`LINE_MASK_W-1:0] m);
    begin
      limpiar_eventos();
      ciclos_acceso = 0;
      @(negedge clk);
      req_lectura = 1'b0; req_escritura = 1'b1;
      req_linea   = l[`MEM_LIDX_W-1:0];
      req_wdata   = d; req_wmask = m;
      listo_visto = 1'b0;
      while (!listo_visto) begin
        @(posedge clk);
        muestrear_eventos();
        ciclos_acceso++;
        if (listo) listo_visto = 1'b1;
      end
      @(negedge clk);
      req_escritura = 1'b0;
    end
  endtask

  // Una linea entera con la misma palabra repetida, util para escribir rapido
  function automatic logic [`LINE_W-1:0] linea_de(input logic [`XLEN-1:0] w);
    logic [`LINE_W-1:0] r;
    for (int i = 0; i < `LINE_WORDS; i++) r[i*`XLEN +: `XLEN] = w;
    return r;
  endfunction

  // ===========================================================================
  // Programa de pruebas
  // ===========================================================================

  int unsigned ev_antes, lect_antes, i;
  int          lin;
  logic [`MEM_LIDX_W-1:0] linea_aux;
  logic [`XLEN-1:0] w0, esperado_w0;
  logic [`LINE_W-1:0] linea_patron;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_l2_cache.vcd");
      $dumpvars(0, tb_l2_cache);
    end

    req_lectura = 0; req_escritura = 0; req_linea = '0;
    req_wdata = '0; req_wmask = '0; ev_lleno = 0; vaciar = 0;
    rst_n = 0;
    repeat (4) @(posedge clk);
    @(negedge clk) rst_n = 1;
    repeat (2) @(posedge clk);

    $display("=== tb_l2_cache: cache L2 de %0d KB, %0d vias, %0d conjuntos ===",
             (SETS * WAYS * `LINE_BYTES) / 1024, WAYS, SETS);

    // ------------------------------------------------------------------------
    $display("");
    $display("[1] fallo y acierto de lectura");
    // ------------------------------------------------------------------------
    lect_antes = lecturas_a_memoria;
    leer(32'd5);
    check("el primer acceso a la linea 5 es un fallo", n_ld_miss, 1);
    check("y no se conto como acierto",                n_ld_hit,  0);
    check("bajo a memoria exactamente una vez",
          lecturas_a_memoria - lect_antes, 1);
    linea_patron = patron(5);
    check_hex("trajo la linea 5, no otra", dato_leido[31:0], linea_patron[31:0]);

    lect_antes = lecturas_a_memoria;
    leer(32'd5);
    check("el segundo acceso a la linea 5 es un acierto", n_ld_hit,  1);
    check("y ya no es fallo",                             n_ld_miss, 0);
    check("y no volvio a bajar a memoria",
          lecturas_a_memoria - lect_antes, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] el hit time es el de la macro, medido");
    // ------------------------------------------------------------------------
    // Un acierto cuesta la latencia emulada mas el ciclo en que se resuelve.
    leer(32'd5);
    check("un acierto cuesta exactamente L2_HIT_CYCLES",
          ciclos_acceso, `L2_HIT_CYCLES);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] el contrato con el nivel de abajo");
    // ------------------------------------------------------------------------
    // Si mem_req sigue arriba en el ciclo de mem_listo, el controlador real
    // arranca una lectura fantasma y el siguiente relleno recibe los datos de
    // la linea anterior.
    check("mem_req bajo en todos los ciclos de mem_listo",
          violaciones_contrato, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] write-back: la escritura no baja a memoria");
    // ------------------------------------------------------------------------
    ev_antes = ev_n;
    escribir(32'd5, linea_de(32'hAAAA_0005), {`LINE_MASK_W{1'b1}});
    check("escribir sobre una linea presente es acierto", n_st_hit,  1);
    check("y no es fallo",                                n_st_miss, 0);
    check("no salio nada al eviction buffer", ev_n - ev_antes, 0);
    check("la L2 quedo con dato sucio",       tiene_sucias, 1'b1);

    leer(32'd5);
    check_hex("y la lectura devuelve lo que se escribio",
              dato_leido[31:0], 32'hAAAA_0005);

    // ------------------------------------------------------------------------
    $display("");
    $display("[5] write-allocate parcial conserva los bytes de afuera");
    // ------------------------------------------------------------------------
    // La linea 9 no esta. Se escribe solo su palabra 0; las otras siete tienen
    // que quedar con lo que traiga la memoria, no en cero.
    lect_antes = lecturas_a_memoria;
    escribir(32'd9, linea_de(32'hBBBB_0009), {{(`LINE_MASK_W-4){1'b0}}, 4'hF});
    check("escribir una linea ausente es fallo", n_st_miss, 1);
    check("y trajo la linea de memoria",
          lecturas_a_memoria - lect_antes, 1);

    leer(32'd9);
    check_hex("la palabra escrita quedo", dato_leido[31:0],   32'hBBBB_0009);
    linea_patron = patron(9);
    check_hex("y la vecina conservo lo de memoria",
              dato_leido[1*`XLEN +: `XLEN], linea_patron[1*`XLEN +: `XLEN]);

    // ------------------------------------------------------------------------
    $display("");
    $display("[6] linea completa: no hace falta leer memoria");
    // ------------------------------------------------------------------------
    lect_antes = lecturas_a_memoria;
    escribir(32'd11, linea_de(32'hCCCC_0011), {`LINE_MASK_W{1'b1}});
    check("con los 32 bytes enmascarados no bajo a memoria",
          lecturas_a_memoria - lect_antes, 0);
    leer(32'd11);
    check_hex("y la linea quedo con el dato escrito",
              dato_leido[31:0], 32'hCCCC_0011);

    // ------------------------------------------------------------------------
    $display("");
    $display("[7] LRU exacto de cuatro vias");
    // ------------------------------------------------------------------------
    // Cinco lineas distintas que caen en el mismo conjunto. Con SETS=128, las
    // lineas 0, 128, 256, 384 y 512 comparten el conjunto 0.
    // Se tocan cuatro, se vuelve a tocar la primera para que deje de ser la
    // mas vieja, y la quinta tiene que expulsar a la SEGUNDA.
    for (i = 0; i < 4; i++) leer(i * SETS);     // llena las cuatro vias
    leer(0);                                    // la 0 pasa a ser la mas nueva

    ev_antes = ev_n;
    inv_n    = 0;
    leer(4 * SETS);                             // la quinta: alguien sale

    check("la quinta linea del conjunto es un fallo", n_ld_miss, 1);
    check("hubo invalidacion hacia atras",            (inv_n > 0), 1'b1);
    linea_aux = SETS[`MEM_LIDX_W-1:0];
    check("y se invalido la linea 128, la menos usada",
          inv_ultima, linea_aux);

    // Las cinco lineas eran limpias, asi que no debio salir nada al buffer
    check("una victima limpia no va al eviction buffer", ev_n - ev_antes, 0);

    // Y la linea 0, que se refresco, tiene que seguir estando
    lect_antes = lecturas_a_memoria;
    leer(0);
    check("la linea que se refresco sigue en la cache", n_ld_hit, 1);
    check("y no volvio a bajar a memoria",
          lecturas_a_memoria - lect_antes, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[8] una victima sucia si sale por el eviction buffer");
    // ------------------------------------------------------------------------
    escribir(2 * SETS, linea_de(32'hDDDD_0002), {`LINE_MASK_W{1'b1}});
    ev_antes = ev_n;
    leer(5 * SETS);                             // fuerza otra expulsion
    leer(6 * SETS);
    leer(7 * SETS);
    leer(8 * SETS);

    check("salieron lineas por el eviction buffer", (ev_n > ev_antes), 1'b1);

    // La linea sucia 256 tiene que aparecer entre las expulsadas, con su dato
    w0 = 32'h0;
    linea_aux = (2 * SETS);
    for (i = ev_antes; i < ev_n; i++)
      if (ev_lineas_vistas[i] == linea_aux)
        w0 = ev_datos_vistos[i][31:0];
    check_hex("la linea sucia salio con el dato que se le escribio",
              w0, 32'hDDDD_0002);

    // ------------------------------------------------------------------------
    $display("");
    $display("[9] stall por eviction buffer lleno");
    // ------------------------------------------------------------------------
    escribir(32'd600, linea_de(32'hEEEE_0600), {`LINE_MASK_W{1'b1}});
    ev_lleno = 1'b1;

    // Se pide la linea que comparte conjunto con 600 hasta llenar las vias y
    // forzar que la victima sucia tenga que salir. Con el buffer lleno la L2
    // se queda en EVICT levantando el contador.
    fork
      begin
        for (i = 1; i <= WAYS; i++) leer(600 + i * SETS);
      end
      begin
        // Corta la espera por si la L2 se quedara atascada de verdad
        repeat (2000) @(posedge clk);
      end
    join_any
    disable fork;

    check("se contaron ciclos de stall por buffer lleno",
          (n_stall_ev > 0), 1'b1);
    ev_lleno = 1'b0;
    repeat (40) @(posedge clk);

    // ------------------------------------------------------------------------
    $display("");
    $display("[10] vaciado de fin de programa");
    // ------------------------------------------------------------------------
    // Es de lo que depende mem_drenada: si queda algo sucio adentro, el
    // programa termino con datos que nunca llegaron a memoria principal.
    escribir(32'd20, linea_de(32'h1111_0020), {`LINE_MASK_W{1'b1}});
    escribir(32'd21, linea_de(32'h2222_0021), {`LINE_MASK_W{1'b1}});
    escribir(32'd22, linea_de(32'h3333_0022), {`LINE_MASK_W{1'b1}});

    check("antes de vaciar hay dato sucio", tiene_sucias, 1'b1);

    ev_antes = ev_n;
    @(negedge clk) vaciar = 1'b1;

    i = 0;
    while (tiene_sucias && i < 40000) begin
      @(posedge clk);
      i++;
    end
    repeat (4) @(posedge clk);

    check("tras el vaciado no queda nada sucio", tiene_sucias, 1'b0);
    check("y las tres lineas salieron al eviction buffer",
          (ev_n - ev_antes >= 3), 1'b1);

    // Las tres tienen que estar, con su dato
    for (lin = 20; lin <= 22; lin++) begin
      w0 = 32'hDEAD_DEAD;
      linea_aux = lin[`MEM_LIDX_W-1:0];
      for (i = ev_antes; i < ev_n; i++)
        if (ev_lineas_vistas[i] == linea_aux)
          w0 = ev_datos_vistos[i][31:0];
      if      (lin == 20) esperado_w0 = 32'h1111_0020;
      else if (lin == 21) esperado_w0 = 32'h2222_0021;
      else                esperado_w0 = 32'h3333_0022;
      check_hex("la linea vaciada salio con su dato", w0, esperado_w0);
    end

    @(negedge clk) vaciar = 1'b0;

    // Y lo mas importante: el vaciado no puede inventar escrituras nuevas si
    // se vuelve a pedir, porque ya dejo las lineas limpias.
    ev_antes = ev_n;
    @(negedge clk) vaciar = 1'b1;
    repeat (600) @(posedge clk);
    check("un segundo vaciado no vuelve a escribir nada",
          ev_n - ev_antes, 0);
    @(negedge clk) vaciar = 1'b0;

    // ------------------------------------------------------------------------
    $display("");
    $display("[11] el contrato se respeto durante toda la prueba");
    // ------------------------------------------------------------------------
    check("ninguna violacion del handshake con memoria",
          violaciones_contrato, 0);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", tests_run, -1);
`endif

    $display("");
    resumen();
  end

  // Red de seguridad: si algo se cuelga, que no quede corriendo para siempre
  initial begin
    #5_000_000;
    $display("  FALLA  la prueba no termino a tiempo");
    $display("RESULTADO: FALLA");
    $fatal(1, "tiempo agotado");
  end

endmodule
