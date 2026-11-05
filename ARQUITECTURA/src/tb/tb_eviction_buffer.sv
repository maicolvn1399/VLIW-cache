`timescale 1ns/1ps

// =============================================================================
// tb_eviction_buffer.sv - Testbench del FIFO de lineas sucias.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Este modulo guarda datos que todavia no llegaron a memoria, asi que un error
// suyo no se ve como una falla: se ve como una palabra con el valor viejo,
// mucho despues, en un programa que calcula mal sin ninguna senal de alarma.
// Por eso el arnes insiste en los tres casos donde eso puede pasar:
//
//   - el conflicto RAW, que es la razon de ser de la senal 'conflicto'
//   - la fusion de escrituras a la misma linea, donde una palabra puede
//     perderse si se combina mal
//   - el deposito simultaneo con el drenado de la cabeza, que es el unico
//     instante en que dos punteros tocan la misma entrada
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: vacio, sin conflicto
//   2. Un deposito y su drenado, en orden FIFO
//   3. El buffer se llena y avisa; no pierde entradas al vaciarse
//   4. Conflicto RAW: se enciende con la linea encolada y se apaga al drenarla
//   5. Fusion: dos escrituras a la misma linea ocupan una sola entrada
//   6. Fusion: la palabra mas reciente gana, las demas se conservan
//   7. Deposito y drenado en el mismo ciclo
//   8. Fusion contra la cabeza mientras se drena: no se pierde el dato
// =============================================================================

`include "cerbero_defs.svh"

module tb_eviction_buffer;

  localparam int ENTRIES = `EVICT_ENTRIES;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                    rst_n;
  logic                    push;
  logic [`MEM_LIDX_W-1:0]  push_linea;
  logic [`LINE_W-1:0]      push_datos;
  logic [`LINE_WORDS-1:0]  push_mascara;

  logic                    head_valido;
  logic [`MEM_LIDX_W-1:0]  head_linea;
  logic [`LINE_W-1:0]      head_datos;
  logic [`LINE_WORDS-1:0]  head_mascara;
  logic                    head_ack;

  logic [`MEM_LIDX_W-1:0]  consulta_linea;
  logic                    conflicto;
  logic                    lleno, vacio;
  logic [`EVICT_IDX_W:0]   ocupadas;

  eviction_buffer #(.ENTRIES (ENTRIES)) dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .push           (push),
      .push_linea     (push_linea),
      .push_datos     (push_datos),
      .push_mascara   (push_mascara),
      .head_valido    (head_valido),
      .head_linea     (head_linea),
      .head_datos     (head_datos),
      .head_mascara   (head_mascara),
      .head_ack       (head_ack),
      .consulta_linea (consulta_linea),
      .conflicto      (conflicto),
      .lleno          (lleno),
      .vacio          (vacio),
      .ocupadas       (ocupadas)
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

  // Una linea donde cada palabra vale base + su indice, para que un error de
  // orden de palabras se vea de inmediato en vez de confundirse con otro valor
  function automatic logic [`LINE_W-1:0] linea_patron(input logic [`XLEN-1:0] base);
    integer w;
    begin
      linea_patron = '0;
      for (w = 0; w < `LINE_WORDS; w = w + 1)
        linea_patron[w*`XLEN +: `XLEN] = base + w;
    end
  endfunction

  function automatic logic [`XLEN-1:0] palabra(input logic [`LINE_W-1:0] l,
                                               input integer w);
    begin
      palabra = l[w*`XLEN +: `XLEN];
    end
  endfunction

  task automatic depositar(input logic [`MEM_LIDX_W-1:0] l,
                           input logic [`LINE_W-1:0]     d,
                           input logic [`LINE_WORDS-1:0] m);
    begin
      push         = 1'b1;
      push_linea   = l;
      push_datos   = d;
      push_mascara = m;
      @(posedge clk);
      #1;
      push = 1'b0;
    end
  endtask

  // Cambiar la consulta y dejar que la logica combinacional se reevalue antes
  // de mirar 'conflicto'. Sin el retardo se leeria el valor del instante
  // anterior, que es un error del arnes y no del modulo.
  task automatic consultar(input logic [`MEM_LIDX_W-1:0] l);
    begin
      consulta_linea = l;
      #1;
    end
  endtask

  task automatic drenar();
    begin
      head_ack = 1'b1;
      @(posedge clk);
      #1;
      head_ack = 1'b0;
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n          = 1'b0;
      push           = 1'b0;
      push_linea     = '0;
      push_datos     = '0;
      push_mascara   = '0;
      head_ack       = 1'b0;
      consulta_linea = '0;
      @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i;
  logic [`LINE_W-1:0] esperada;

  initial begin
    if ($test$plusargs("VCD") || $value$plusargs("VCD=%s", i)) begin
      $dumpfile("tb_eviction_buffer.vcd");
      $dumpvars(0, tb_eviction_buffer);
    end

    $display("");
    $display("=== tb_eviction_buffer: el FIFO de lineas sucias ===");

    // ---- 1. Reset ----------------------------------------------------------
    $display("");
    $display("[1] el reset deja el buffer vacio");
    reiniciar();
    check1("vacio",            vacio,       1'b1);
    check1("no lleno",         lleno,       1'b0);
    check1("cabeza invalida",  head_valido, 1'b0);
    check1("sin conflicto",    conflicto,   1'b0);
    check("entradas ocupadas", ocupadas,    0);

    // ---- 2. Deposito y drenado ---------------------------------------------
    $display("");
    $display("[2] una linea entra, sale igual");
    depositar(11'h123, linea_patron(32'hAA00_0000), 8'hFF);
    check("ocupadas tras depositar", ocupadas, 1);
    check1("la cabeza es valida",    head_valido, 1'b1);
    check("la linea de la cabeza",   head_linea,  11'h123);
    check_hex("palabra 0",           palabra(head_datos, 0), 32'hAA00_0000);
    check_hex("palabra 7",           palabra(head_datos, 7), 32'hAA00_0007);
    check("la mascara",              head_mascara, 8'hFF);

    drenar();
    check1("vacio tras drenar", vacio, 1'b1);

    // ---- 3. Llenado --------------------------------------------------------
    // El controlador mira 'lleno' para decidir si puede aceptar un desalojo.
    // Si el buffer dijera que hay lugar cuando no lo hay, el deposito se
    // perderia en silencio y esa linea nunca llegaria a memoria.
    $display("");
    $display("[3] se llena, avisa, y se vacia en orden");
    reiniciar();
    for (i = 0; i < ENTRIES; i = i + 1)
      depositar(11'h200 + i[`MEM_LIDX_W-1:0], linea_patron(i * 32'h100), 8'hFF);

    check("ocupadas",       ocupadas, ENTRIES);
    check1("lleno",         lleno,    1'b1);
    check1("no vacio",      vacio,    1'b0);

    // Salen en el orden en que entraron
    for (i = 0; i < ENTRIES; i = i + 1) begin
      check($sformatf("la entrada %0d sale en su turno", i),
            head_linea, 11'h200 + i);
      drenar();
    end
    check1("vacio al final", vacio, 1'b1);

    // ---- 4. Conflicto RAW --------------------------------------------------
    // Esta es la senal de la que depende la correccion de todo el esquema. Si
    // no se encendiera, una lectura a una linea encolada traeria de memoria el
    // valor anterior a la escritura pendiente.
    $display("");
    $display("[4] el conflicto RAW se enciende y se apaga cuando corresponde");
    reiniciar();
    consultar(11'h0AB);
    check1("sin conflicto con el buffer vacio", conflicto, 1'b0);

    depositar(11'h0AB, linea_patron(32'hBB00_0000), 8'hFF);
    check1("conflicto con la linea encolada", conflicto, 1'b1);

    consultar(11'h0AC);
    check1("pero no con una linea vecina",    conflicto, 1'b0);

    consultar(11'h0AB);
    drenar();
    check1("se apaga al drenarla",            conflicto, 1'b0);

    $display("");
    $display("    el conflicto sigue encendido mientras la entrada espera");
    reiniciar();
    consultar(11'h300);
    depositar(11'h100, linea_patron(32'h1000), 8'hFF);
    depositar(11'h200, linea_patron(32'h2000), 8'hFF);
    depositar(11'h300, linea_patron(32'h3000), 8'hFF);
    check1("conflicto con la tercera entrada", conflicto, 1'b1);
    drenar();
    check1("sigue tras drenar la primera",     conflicto, 1'b1);
    drenar();
    check1("sigue tras drenar la segunda",     conflicto, 1'b1);
    drenar();
    check1("se apaga tras drenar la tercera",  conflicto, 1'b0);

    // ---- 5 y 6. Fusion -----------------------------------------------------
    // Sin fusion, ocho stores seguidos a la misma linea llenarian el buffer.
    // Con fusion mal hecha, una palabra se pierde. Las dos cosas se prueban
    // aqui: primero que no crece, despues que el contenido es el correcto.
    $display("");
    $display("[5] dos escrituras a la misma linea ocupan una sola entrada");
    reiniciar();
    depositar(11'h0F0, linea_patron(32'hC000_0000), 8'b0000_0001);
    check("ocupadas tras la primera", ocupadas, 1);
    depositar(11'h0F0, linea_patron(32'hD000_0000), 8'b0000_0010);
    check("ocupadas tras la segunda", ocupadas, 1);
    check("la mascara se combino",    head_mascara, 8'b0000_0011);

    $display("");
    $display("[6] la palabra mas reciente gana, las demas se conservan");
    reiniciar();
    // Primero la linea entera con el patron C
    depositar(11'h0F0, linea_patron(32'hC000_0000), 8'hFF);
    // Despues solo la palabra 3, con el patron D
    esperada                      = linea_patron(32'hC000_0000);
    esperada[3*`XLEN +: `XLEN]    = 32'hD000_0003;
    depositar(11'h0F0, linea_patron(32'hD000_0000), 8'b0000_1000);

    check("sigue siendo una entrada", ocupadas, 1);
    check_hex("palabra 2 sin tocar",  palabra(head_datos, 2),
              palabra(esperada, 2));
    check_hex("palabra 3 actualizada", palabra(head_datos, 3),
              palabra(esperada, 3));
    check_hex("palabra 4 sin tocar",  palabra(head_datos, 4),
              palabra(esperada, 4));
    check("la mascara sigue completa", head_mascara, 8'hFF);

    // ---- 7. Deposito y drenado a la vez ------------------------------------
    // El controlador drena mientras la cache sigue desalojando. Son punteros
    // distintos y tienen que poder moverse en el mismo flanco.
    $display("");
    $display("[7] depositar y drenar en el mismo ciclo");
    reiniciar();
    depositar(11'h400, linea_patron(32'h4000), 8'hFF);
    depositar(11'h401, linea_patron(32'h4100), 8'hFF);
    check("ocupadas antes", ocupadas, 2);

    push         = 1'b1;
    push_linea   = 11'h402;
    push_datos   = linea_patron(32'h4200);
    push_mascara = 8'hFF;
    head_ack     = 1'b1;
    @(posedge clk);
    #1;
    push     = 1'b0;
    head_ack = 1'b0;

    check("ocupadas despues (una entro, una salio)", ocupadas, 2);
    check("la cabeza avanzo",  head_linea, 11'h401);

    // ---- 8. Fusion contra la cabeza que se esta drenando -------------------
    // El unico caso en que los dos punteros tocan la misma entrada. Si se
    // fusionara con una cabeza que ya se esta retirando, el dato nuevo se
    // escribiria en una entrada que deja de existir en ese mismo flanco, y esa
    // escritura jamas llegaria a memoria.
    $display("");
    $display("[8] fusionar contra la cabeza que se drena NO pierde el dato");
    reiniciar();
    depositar(11'h500, linea_patron(32'h5000_0000), 8'hFF);
    check("una entrada encolada", ocupadas, 1);

    // Deposito a la MISMA linea en el ciclo en que la cabeza se confirma
    push         = 1'b1;
    push_linea   = 11'h500;
    push_datos   = linea_patron(32'h9000_0000);
    push_mascara = 8'hFF;
    head_ack     = 1'b1;
    @(posedge clk);
    #1;
    push     = 1'b0;
    head_ack = 1'b0;

    check("queda una entrada, no cero",  ocupadas, 1);
    check1("y la cabeza es valida",      head_valido, 1'b1);
    check("de la misma linea",           head_linea, 11'h500);
    check_hex("con el dato NUEVO",       palabra(head_datos, 0),
              32'h9000_0000);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", ocupadas, 99);
`endif

    $display("");
    resumen();
  end

endmodule
