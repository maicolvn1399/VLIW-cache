`timescale 1ns/1ps

// =============================================================================
// tb_l1_dcache.sv - Testbench de la cache de datos de primer nivel.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// La cache es el componente del proyecto donde un error es mas facil de
// esconder: entrega datos correctos la mayor parte del tiempo y falla en la
// combinacion precisa de reemplazo, politica de escritura y orden de accesos.
// Por eso este arnes no se conforma con leer y escribir: prueba las tres
// politicas elegidas una por una, en los casos donde cada una se distingue de
// la alternativa que NO se eligio.
//
//   write-through      se verifica que un store llegue al nivel de abajo
//                      aunque acierte (write-back no lo haria)
//   no-write-allocate  se verifica que un store que falla NO traiga la linea
//                      (write-allocate si lo haria)
//   LRU                se verifica que la victima sea la menos usada, no la
//                      que entro primero (que es lo que haria FIFO)
//
// El caso 9 es el mas importante de todos y no prueba una politica sino la
// regla que sostiene al modulo: que un store se empuje UNA vez aunque el
// pipeline este detenido varios ciclos. Un error ahi no se ve como una falla:
// se ve como un programa que escribe el valor correcto, y la memoria tambien
// lo tiene, y sin embargo el contador de escrituras dice 53.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: todo invalido, el primer acceso falla
//   2. Un fallo de lectura trae la linea; el siguiente acceso acierta
//   3. Localidad espacial: las 8 palabras de la linea aciertan tras un fallo
//   4. Las dos vias de un conjunto se usan antes de reemplazar
//   5. LRU: la victima es la menos usada, no la que entro primero
//   6. Un acierto de lectura cuesta exactamente un ciclo
//   7. Write-through: un store que acierta actualiza L1 y baja igual
//   8. No-write-allocate: un store que falla no trae la linea
//   9. Un store se empuja una sola vez aunque el pipeline se detenga
//  10. Conflicto RAW: leer una linea con escrituras pendientes
//  11. Stores de byte y de media palabra (SB, SH)
//  12. La latencia real de T_mem no cambia nada del comportamiento
// =============================================================================

`include "cerbero_defs.svh"

module tb_l1_dcache;

  // Latencia del modelo de memoria del arnes. Corta por defecto para que la
  // bateria sea rapida; el caso 12 la sube a la real.
  localparam int LAT_CORTA = 5;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // ---- Lado del procesador ---------------------------------------------------
  logic                    req;
  logic [`XLEN-1:0]        addr;
  logic                    we;
  logic [3:0]              be;
  logic [`XLEN-1:0]        wdata;
  logic [`XLEN-1:0]        rdata;
  logic                    stall;

  // ---- Write buffer -----------------------------------------------------------
  logic                    wb_push;
  logic [`MEM_LIDX_W-1:0]  wb_linea;
  logic [`LINE_W-1:0]      wb_datos;
  logic [`LINE_MASK_W-1:0] wb_mascara;
  logic                    wb_lleno;
  logic [`MEM_LIDX_W-1:0]  wb_consulta;
  logic                    wb_conflicto;

  // ---- Memoria -----------------------------------------------------------------
  logic                    mem_req;
  logic [`MEM_LIDX_W-1:0]  mem_linea;
  logic                    mem_listo;
  logic [`LINE_W-1:0]      mem_datos;

  // ---- Invalidacion hacia atras desde L2 ---------------------------------------
  // La politica es inclusiva: cuando L2 expulsa una linea valida avisa a L1
  // para que la descarte. Estos puertos existen desde la Iteracion 4 y antes
  // quedaban flotando aqui, asi que todos los casos de abajo corrian con x en
  // la entrada y la invalidacion no la probaba nadie.
  logic                    inv_req;
  logic [`MEM_LIDX_W-1:0]  inv_linea;

  // ---- Contadores ---------------------------------------------------------------
  logic ev_load_hit, ev_load_miss, ev_store_hit, ev_store_miss;
  logic ev_stall_miss, ev_stall_wb, ev_stall_raw;

  l1_dcache dut (
      .clk           (clk),
      .rst_n         (rst_n),
      .inv_req       (inv_req),
      .inv_linea     (inv_linea),
      .req           (req),
      .addr          (addr),
      .we            (we),
      .be            (be),
      .wdata         (wdata),
      .rdata         (rdata),
      .stall         (stall),
      .wb_push       (wb_push),
      .wb_linea      (wb_linea),
      .wb_datos      (wb_datos),
      .wb_mascara    (wb_mascara),
      .wb_lleno      (wb_lleno),
      .wb_consulta   (wb_consulta),
      .wb_conflicto  (wb_conflicto),
      .mem_req       (mem_req),
      .mem_linea     (mem_linea),
      .mem_listo     (mem_listo),
      .mem_datos     (mem_datos),
      .ev_load_hit   (ev_load_hit),
      .ev_load_miss  (ev_load_miss),
      .ev_store_hit  (ev_store_hit),
      .ev_store_miss (ev_store_miss),
      .ev_stall_miss (ev_stall_miss),
      .ev_stall_wb   (ev_stall_wb),
      .ev_stall_raw  (ev_stall_raw)
  );

  // ---------------------------------------------------------------------------
  // El write buffer de verdad
  //
  // Se instancia el mismo eviction_buffer.sv que usa el subsistema de memoria,
  // porque es el que top.sv va a poner aqui. Probar la cache contra un modelo
  // simplificado dejaria sin verificar justamente la interaccion que importa:
  // la deteccion de conflicto RAW, que vive en ese modulo.
  // ---------------------------------------------------------------------------

  logic                    wb_head_valido;
  logic [`MEM_LIDX_W-1:0]  wb_head_linea;
  logic [`LINE_W-1:0]      wb_head_datos;
  logic [`LINE_MASK_W-1:0] wb_head_mascara;
  logic                    wb_head_ack;
  logic                    wb_vacio;
  logic [`EVICT_IDX_W:0]   wb_ocupadas;

  eviction_buffer #(.ENTRIES (`WB_ENTRIES)) u_wb (
      .clk            (clk),
      .rst_n          (rst_n),
      .push           (wb_push),
      .push_linea     (wb_linea),
      .push_datos     (wb_datos),
      .push_mascara   (wb_mascara),
      .head_valido    (wb_head_valido),
      .head_linea     (wb_head_linea),
      .head_datos     (wb_head_datos),
      .head_mascara   (wb_head_mascara),
      .head_ack       (wb_head_ack),
      // El drenado de este arnes consume la cabeza en un ciclo, asi que no
      // existe la ventana en que la entrada esta siendo escrita.
      .head_ocupada   (1'b0),
      .consulta_linea (wb_consulta),
      .conflicto      (wb_conflicto),
      .lleno          (wb_lleno),
      .vacio          (wb_vacio),
      .ocupadas       (wb_ocupadas)
  );

  // ---------------------------------------------------------------------------
  // Modelo de memoria del arnes
  //
  // Un arreglo plano de palabras con dos clientes: las lecturas de linea de la
  // cache y el drenado del write buffer. La latencia es un parametro de la
  // simulacion para poder probar con una corta (rapida) y con la real (53).
  //
  // El drenado se puede congelar con 'drenado_detenido', que es como se fuerza
  // el buffer lleno del caso 9 sin depender de la velocidad relativa.
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] memoria [0:`MEM_WORDS-1];

  integer latencia        = LAT_CORTA;
  logic   drenado_detenido = 1'b0;
  integer escrituras_a_memoria = 0;   // cuantas veces se drenó una entrada

  integer cuenta_lat;
  logic [`MEM_LIDX_W-1:0] linea_pedida;

  // --- lado de lectura ---
  integer rd_estado;   // 0 = libre, 1 = contando
  integer k;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_estado  <= 0;
      cuenta_lat <= 0;
      mem_listo  <= 1'b0;
      mem_datos  <= '0;
    end else begin
      mem_listo <= 1'b0;

      if (rd_estado == 0) begin
        if (mem_req) begin
          linea_pedida <= mem_linea;
          cuenta_lat   <= latencia - 1;
          rd_estado    <= 1;
        end
      end else begin
        // Se dispara en 1 y no en 0 porque mem_listo esta registrado: la senal
        // se ve un ciclo despues de asignarse. Asi la latencia OBSERVABLE, de
        // la peticion a listo, es exactamente 'latencia' ciclos y el costo de
        // un fallo queda en latencia+1, que es lo que las pruebas esperan.
        // Requiere latencia >= 2, que se cumple en los dos valores usados.
        if (cuenta_lat <= 1) begin
          for (k = 0; k < `LINE_WORDS; k = k + 1)
            mem_datos[k*`XLEN +: `XLEN] <=
                memoria[{21'd0, linea_pedida} * `LINE_WORDS + k];
          mem_listo <= 1'b1;
          rd_estado <= 0;
        end else begin
          cuenta_lat <= cuenta_lat - 1;
        end
      end
    end
  end

  // --- lado de drenado del write buffer ---
  // Escribe la entrada de la cabeza byte por byte, segun su mascara, y la
  // confirma. Una entrada por ciclo cuando esta habilitado.
  integer b;
  integer pal;

  always_ff @(posedge clk) begin
    wb_head_ack <= 1'b0;
    if (rst_n && wb_head_valido && !drenado_detenido && !wb_head_ack) begin
      for (b = 0; b < `LINE_BYTES; b = b + 1) begin
        if (wb_head_mascara[b]) begin
          pal = {21'd0, wb_head_linea} * `LINE_WORDS + (b / 4);
          memoria[pal][(b % 4)*8 +: 8] <= wb_head_datos[b*8 +: 8];
        end
      end
      wb_head_ack          <= 1'b1;
      escrituras_a_memoria <= escrituras_a_memoria + 1;
    end
  end

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
  // Acceso
  //
  // Sostiene la peticion hasta que la cache deja de pedir espera, cuenta los
  // ciclos que ocupo y devuelve el dato. Es exactamente lo que hace el pipeline
  // cuando se congela: la misma peticion, ciclo tras ciclo, hasta que pasa.
  // ---------------------------------------------------------------------------

  integer ciclos_del_acceso;
  logic [`XLEN-1:0] dato_leido;

  task automatic acceder(input logic [`XLEN-1:0] a,
                         input logic             escribe,
                         input logic [3:0]       bytes,
                         input logic [`XLEN-1:0] dato);
    begin
      req               = 1'b1;
      addr              = a;
      we                = escribe;
      be                = bytes;
      wdata             = dato;
      ciclos_del_acceso = 0;

      forever begin
        #1;
        ciclos_del_acceso = ciclos_del_acceso + 1;
        if (!stall) begin
          @(posedge clk);
          #1;
          req        = 1'b0;
          dato_leido = rdata;
          disable acceder;
        end
        @(posedge clk);
        if (ciclos_del_acceso > 2000) begin
          $display("  FALLA  el acceso a %08h nunca termino", a);
          tests_failed = tests_failed + 1;
          req = 1'b0;
          disable acceder;
        end
      end
    end
  endtask

  task automatic leer(input logic [`XLEN-1:0] a);
    begin
      acceder(a, 1'b0, 4'b1111, 32'd0);
    end
  endtask

  task automatic escribir(input logic [`XLEN-1:0] a,
                          input logic [3:0]       bytes,
                          input logic [`XLEN-1:0] dato);
    begin
      acceder(a, 1'b1, bytes, dato);
    end
  endtask

  task automatic ocioso(input integer n);
    begin
      req = 1'b0;
      repeat (n) @(posedge clk);
      #1;
    end
  endtask

  task automatic esperar_drenado();
    integer guarda;
    begin
      req    = 1'b0;
      guarda = 0;
      while (!wb_vacio && guarda < 5000) begin
        @(posedge clk);
        #1;
        guarda = guarda + 1;
      end
    end
  endtask

  // Siembra la memoria con un patron donde cada palabra lleva su direccion, de
  // modo que leer la palabra equivocada se delate solo.
  task automatic sembrar();
    integer w;
    begin
      for (w = 0; w < `MEM_WORDS; w = w + 1) memoria[w] = 32'hDA7A_0000 + w;
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n            = 1'b0;
      req              = 1'b0;
      addr             = '0;
      we               = 1'b0;
      be               = 4'b1111;
      wdata            = '0;
      latencia             = LAT_CORTA;
      drenado_detenido     = 1'b0;
      // Se reinicia con el DUT: es una cuenta por caso, no acumulada. Sin esto,
      // el caso 9 heredaria los drenados de los casos 7 y 8 y su numero diria
      // 11 donde la prueba espera 9, por una razon que no tiene nada que ver
      // con lo que ese caso verifica.
      escrituras_a_memoria = 0;
      @(posedge clk);
      #1 rst_n = 1'b1;
      @(posedge clk);
      #1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  // Dos direcciones que caen en el MISMO conjunto difieren en 2048 bytes:
  // 64 conjuntos x 32 bytes por via = 2048.
  localparam int PASO_CONJUNTO = `L1D_SETS * `LINE_BYTES;   // 2048

  integer i;
  integer empujes;

  initial begin
    if ($test$plusargs("VCD") || $value$plusargs("VCD=%s", i)) begin
      $dumpfile("tb_l1_dcache.vcd");
      $dumpvars(0, tb_l1_dcache);
    end

    $display("");
    $display("=== tb_l1_dcache: write-through, no-write-allocate, LRU ===");
    $display("");
    $display("  geometria");
    $display("    tamano          %0d bytes", `L1D_BYTES);
    $display("    vias            %0d", `L1D_WAYS);
    $display("    conjuntos       %0d", `L1D_SETS);
    $display("    linea           %0d bytes", `LINE_BYTES);
    $display("    mismo conjunto cada %0d bytes", PASO_CONJUNTO);

    inv_req   = 1'b0;
    inv_linea = '0;

    sembrar();
    reiniciar();

    // ---- 1 y 2. El primer fallo y el acierto que sigue ---------------------
    $display("");
    $display("[1] tras el reset todo esta invalido: el primer acceso falla");
    leer(32'h0000_0100);
    check("ciclos del primer acceso", ciclos_del_acceso, LAT_CORTA + 1);
    check_hex("y trajo el dato correcto", dato_leido,
              32'hDA7A_0000 + 32'h100/4);

    $display("");
    $display("[2] el mismo acceso, ahora en la cache");
    leer(32'h0000_0100);
    check("ciclos del segundo acceso", ciclos_del_acceso, 1);
    check_hex("mismo dato", dato_leido, 32'hDA7A_0000 + 32'h100/4);

    // ---- 3. Localidad espacial ---------------------------------------------
    // Traer 32 bytes cuando se pidieron 4 solo vale la pena si las otras siete
    // palabras se aprovechan. Esto lo comprueba.
    $display("");
    $display("[3] las otras 7 palabras de la linea ya estan");
    for (i = 1; i < `LINE_WORDS; i = i + 1) begin
      leer(32'h0000_0100 + i*4);
      check($sformatf("palabra %0d de la linea: ciclos", i),
            ciclos_del_acceso, 1);
      check_hex($sformatf("palabra %0d: dato", i), dato_leido,
                32'hDA7A_0000 + (32'h100/4) + i[`XLEN-1:0]);
    end

    // ---- 4. Las dos vias ---------------------------------------------------
    $display("");
    $display("[4] dos lineas del mismo conjunto caben a la vez");
    reiniciar();
    sembrar();

    leer(32'h0000_0000);                    // conjunto 0, via A
    check("linea A: falla", ciclos_del_acceso, LAT_CORTA + 1);
    leer(32'h0000_0000 + PASO_CONJUNTO);    // conjunto 0, via B
    check("linea B: falla", ciclos_del_acceso, LAT_CORTA + 1);

    leer(32'h0000_0000);
    check("linea A sigue en la cache", ciclos_del_acceso, 1);
    leer(32'h0000_0000 + PASO_CONJUNTO);
    check("linea B sigue en la cache", ciclos_del_acceso, 1);

    // ---- 5. LRU ------------------------------------------------------------
    // El caso que distingue LRU de FIFO. Se cargan A y B, se vuelve a tocar A
    // (que pasa a ser la mas reciente) y se trae C.
    //
    //   LRU  desaloja B, porque es la menos usada  -> A sigue, B no
    //   FIFO desaloja A, porque entro primero      -> B sigue, A no
    //
    // Si esta prueba pasa con una implementacion FIFO, es que no prueba nada.
    $display("");
    $display("[5] la victima es la menos usada, no la que entro primero");
    reiniciar();
    sembrar();

    leer(32'h0000_0000);                      // A entra
    leer(32'h0000_0000 + PASO_CONJUNTO);      // B entra
    leer(32'h0000_0000);                      // A se vuelve la mas reciente

    leer(32'h0000_0000 + 2*PASO_CONJUNTO);    // C entra: desaloja a la menos usada
    check("C: falla, como corresponde", ciclos_del_acceso, LAT_CORTA + 1);

    leer(32'h0000_0000);
    check("A sigue (LRU la conservo)", ciclos_del_acceso, 1);

    leer(32'h0000_0000 + PASO_CONJUNTO);
    check("B se fue (era la menos usada)", ciclos_del_acceso, LAT_CORTA + 1);

    // ---- 6. El costo de un acierto -----------------------------------------
    $display("");
    $display("[6] un acierto de lectura cuesta un ciclo y no mas");
    leer(32'h0000_0000 + PASO_CONJUNTO);
    check("ciclos", ciclos_del_acceso, `L1_HIT_CYCLES);

    // ---- 7. Write-through --------------------------------------------------
    // Lo que distingue write-through de write-back: el store baja aunque
    // acierte. Con write-back el dato se quedaria en L1 y el buffer estaria
    // vacio.
    $display("");
    $display("[7] un store que acierta actualiza L1 y baja igual");
    reiniciar();
    sembrar();
    drenado_detenido = 1'b1;    // para poder mirar el buffer antes de que drene

    leer(32'h0000_0200);                        // trae la linea
    escribir(32'h0000_0200, 4'b1111, 32'hCAFE_0001);
    check("el store no detuvo el pipeline", ciclos_del_acceso, 1);
    check("y bajo al write buffer", wb_ocupadas, 1);

    leer(32'h0000_0200);
    check("la lectura siguiente acierta", ciclos_del_acceso, 1);
    check_hex("y ve el dato nuevo (L1 se actualizo)", dato_leido,
              32'hCAFE_0001);

    drenado_detenido = 1'b0;
    esperar_drenado();
    check_hex("y el dato llego a memoria", memoria[32'h200/4], 32'hCAFE_0001);

    // ---- 8. No-write-allocate ----------------------------------------------
    // Lo que distingue no-write-allocate de write-allocate: el store que falla
    // NO trae la linea. Se comprueba de dos formas, porque cada una sola
    // podria pasar por casualidad: el store no cuesta ciclos extra, y la
    // lectura posterior a esa linea sigue fallando.
    $display("");
    $display("[8] un store que falla no trae la linea");
    reiniciar();
    sembrar();

    escribir(32'h0000_1000, 4'b1111, 32'hBEEF_0001);
    check("el write miss no costo ciclos", ciclos_del_acceso, 1);

    // Se espera el drenado antes de leer para que el costo de la lectura sea
    // solo el del fallo. Sin esto, la lectura ademas chocaria con el store
    // pendiente en el buffer y pagaria tambien la espera del conflicto RAW,
    // mezclando dos efectos en un numero. El RAW tiene su propio caso, el 10.
    esperar_drenado();

    leer(32'h0000_1000);
    check("la linea NO estaba en la cache", ciclos_del_acceso,
          LAT_CORTA + 1);
    check_hex("y la lectura ve el dato escrito", dato_leido, 32'hBEEF_0001);

    // ---- 9. Un store, un empuje --------------------------------------------
    // La regla que sostiene todo el modulo. Se llena el write buffer con el
    // drenado congelado, se intenta un store mas (que tiene que esperar), se
    // libera el drenado y se cuenta cuantas entradas llegaron a memoria.
    //
    // Si el store se empujara en cada ciclo de espera, el buffer recibiria el
    // mismo deposito muchas veces. Como el buffer fusiona por linea, el
    // sintoma no seria un dato equivocado sino un contador de escrituras
    // inflado, que es exactamente la clase de error que el enunciado pide
    // vigilar al validar metricas.
    $display("");
    $display("[9] un store se empuja una sola vez aunque el pipeline espere");
    reiniciar();
    sembrar();
    drenado_detenido = 1'b1;

    // Llenar el buffer con lineas DISTINTAS, para que no se fusionen
    for (i = 0; i < `WB_ENTRIES; i = i + 1)
      escribir(32'h0000_2000 + i*`LINE_BYTES, 4'b1111, 32'hA000_0000 + i);

    check("el buffer quedo lleno", wb_lleno, 1'b1);
    check("con todas sus entradas", wb_ocupadas, `WB_ENTRIES);

    // Un store mas: no cabe, tiene que esperar
    fork
      begin
        escribir(32'h0000_3000, 4'b1111, 32'h9999_9999);
      end
      begin
        // Dejarlo esperar varios ciclos antes de liberar el drenado
        repeat (12) @(posedge clk);
        #1 drenado_detenido = 1'b0;
      end
    join

    check("el store espero por el buffer lleno", (ciclos_del_acceso > 1), 1);

    esperar_drenado();

    // Nueve stores a nueve lineas distintas: nueve drenados, ni uno mas
    check("entradas drenadas a memoria", escrituras_a_memoria,
          `WB_ENTRIES + 1);
    check_hex("y el ultimo store llego bien",
              memoria[32'h3000/4], 32'h9999_9999);

    // ---- 10. Conflicto RAW -------------------------------------------------
    // Un store que falla deja su dato solo en el write buffer. Leer esa misma
    // linea antes de que drene tiene que esperar: pedirla abajo ahora traeria
    // el valor anterior al store.
    $display("");
    $display("[10] leer una linea con escrituras pendientes");
    reiniciar();
    sembrar();
    drenado_detenido = 1'b1;

    escribir(32'h0000_4000, 4'b1111, 32'h1234_5678);   // falla, va al buffer
    check("el store esta en el buffer", wb_ocupadas, 1);

    req  = 1'b1;
    addr = 32'h0000_4000;
    we   = 1'b0;
    #1;
    check("la cache detecta el conflicto", ev_stall_raw, 1'b1);
    check("y NO pide la linea abajo",      mem_req,      1'b0);
    req = 1'b0;
    #1;

    // Al liberar el drenado, la lectura puede completarse y tiene que ver el
    // dato NUEVO, no el que estaba en memoria antes
    drenado_detenido = 1'b0;
    leer(32'h0000_4000);
    check_hex("la lectura ve el dato del store", dato_leido, 32'h1234_5678);
    check("y tardo mas que un fallo normal",
          (ciclos_del_acceso > LAT_CORTA + 1), 1);

    // ---- 11. Stores parciales ----------------------------------------------
    // SB y SH tienen que llegar a memoria sin pisar los bytes vecinos. Es la
    // razon por la que la mascara de los buffers es por byte.
    $display("");
    $display("[11] stores de byte y de media palabra");
    reiniciar();
    sembrar();

    // Un SB al byte 0 de una palabra que NO esta en la cache
    escribir(32'h0000_5000, 4'b0001, 32'h0000_00AA);
    esperar_drenado();
    check_hex("SB escribio su byte y respeto los otros 3",
              memoria[32'h5000/4],
              ((32'hDA7A_0000 + 32'h5000/4) & 32'hFFFF_FF00) | 32'h0000_00AA);

    // Un SH a la mitad alta de otra palabra
    escribir(32'h0000_5006, 4'b1100, 32'hBBBB_0000);
    esperar_drenado();
    check_hex("SH escribio su mitad y respeto la otra",
              memoria[32'h5004/4],
              ((32'hDA7A_0000 + 32'h5004/4) & 32'h0000_FFFF) | 32'hBBBB_0000);

    // Dos SB a bytes distintos de la misma palabra, sin drenar en medio
    drenado_detenido = 1'b1;
    escribir(32'h0000_6000, 4'b0001, 32'h0000_0011);
    escribir(32'h0000_6001, 4'b0010, 32'h0000_2200);
    drenado_detenido = 1'b0;
    esperar_drenado();
    check_hex("dos SB a la misma palabra no se pisaron",
              memoria[32'h6000/4] & 32'h0000_FFFF, 32'h0000_2211);

    // ---- 12. Con la latencia real ------------------------------------------
    // Todo lo anterior corrio con una latencia corta para que la bateria sea
    // rapida. Aqui se comprueba que con los 53 ciclos reales el comportamiento
    // es el mismo y solo cambia el tiempo.
    $display("");
    $display("[12] con T_mem real (%0d ciclos)", `T_MEM);
    reiniciar();
    sembrar();
    latencia = `T_MEM;

    leer(32'h0000_7000);
    check("un fallo cuesta T_mem mas el ciclo del acceso",
          ciclos_del_acceso, `T_MEM + 1);
    check_hex("y el dato es correcto", dato_leido,
              32'hDA7A_0000 + 32'h7000/4);

    leer(32'h0000_7000);
    check("y el acierto siguiente sigue costando uno",
          ciclos_del_acceso, `L1_HIT_CYCLES);

    // -------------------------------------------------------------------------
    $display("");
    $display("[INV] invalidacion hacia atras desde la L2");
    // -------------------------------------------------------------------------
    // La politica es inclusiva, asi que cuando la L2 expulsa una linea valida
    // avisa a la L1 para que la descarte. Si la L1 no la descartara, se
    // quedaria sirviendo una copia de algo que el nivel de abajo ya no tiene.
    //
    // OJO con el ancho: la L2 manda el numero de linea en el espacio de
    // memoria principal (MEM_LIDX_W bits), no la direccion. Reconstruir la
    // etiqueta de L1 desde ahi es lo que estaba roto hasta la Iteracion 4:
    // se leian bits fuera de rango y la comparacion no daba verdadero nunca.

    // Se trae una linea y se comprueba que de verdad quedo en la cache
    leer(32'h0000_1000);
    check("la linea esta en la cache tras el fallo",
          ciclos_del_acceso, `T_MEM + 1);
    leer(32'h0000_1000);
    check("y el acceso siguiente es un acierto de un ciclo",
          ciclos_del_acceso, `L1_HIT_CYCLES);

    // La L2 avisa que expulso esa misma linea
    @(negedge clk);
    inv_req   = 1'b1;
    inv_linea = 32'h0000_1000 >> `LINE_OFF_W;
    @(posedge clk);
    @(negedge clk);
    inv_req   = 1'b0;
    #1;

    // Ahora el mismo acceso tiene que volver a fallar
    leer(32'h0000_1000);
    check("tras la invalidacion la linea ya no esta",
          ciclos_del_acceso, `T_MEM + 1);
    check_hex("y la volvio a traer correcta", dato_leido,
              32'hDA7A_0000 + 32'h1000/4);

    // Y una invalidacion de OTRA linea no puede tocar esta
    leer(32'h0000_1000);                       // queda caliente otra vez
    @(negedge clk);
    inv_req   = 1'b1;
    inv_linea = 32'h0000_2000 >> `LINE_OFF_W;  // una linea distinta
    @(posedge clk);
    @(negedge clk);
    inv_req   = 1'b0;
    #1;

    leer(32'h0000_1000);
    check("invalidar otra linea no afecta a esta",
          ciclos_del_acceso, `L1_HIT_CYCLES);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", ciclos_del_acceso, 777);
`endif

    $display("");
    resumen();
  end

endmodule
