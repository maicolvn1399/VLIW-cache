`timescale 1ns/1ps

// =============================================================================
// tb_imem.sv - Testbench de la memoria de instrucciones.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Lo que de verdad hay que demostrar aqui no es que la memoria guarde datos,
// sino TRES propiedades que el resto del pipeline da por ciertas:
//
//   1. La lectura es SINCRONA y en el POSEDGE. Si alguien la convirtiera en
//      combinacional, el bundle llegaria medio ciclo antes y el registro de
//      segmentacion IF/ID dejaria de estar donde el diseno cree que esta.
//   2. El indice escala de 16 en 16 bytes y los cuatro bits bajos no cuentan.
//   3. Una direccion fuera de lo implementado entrega CEROS, no la palabra que
//      sale de truncar el indice. Esto ultimo importa mas de lo que parece:
//      index = index_full[IDX_W-1:0], asi que sin la comprobacion de rango la
//      direccion 2048*16 leeria el bundle 0. El caso correspondiente deja el
//      bundle 0 cargado con un patron distinto de cero justo para que ese
//      error se vea.
//
// SystemVerilog plano, sin clases ni aleatorizacion, para que Icarus lo
// compile. El contenido se carga de dos maneras: por referencia jerarquica
// (u_mem.storage[k]), que es como lo van a hacer los testbenches de
// integracion, y por $readmemh desde un archivo, que es como lo va a hacer la
// herramienta de carga del punto 7 del plan.
//
// OJO: el caso de $readmemh abre ../tb/imem_init.hex con ruta relativa, asi
// que este testbench se ejecuta desde src/build, que es lo que hace el make.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto, para comprobar que el arnes sabe reportar una
// falla en lugar de pasar siempre por construccion.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Memoria sin inicializar: bundles de operaciones nulas, no valores en X
//   2. Lectura de contenido cargado, incluido el ultimo bundle implementado
//   3. La lectura es sincrona: el bundle no cambia antes del flanco de subida
//   4. Los cuatro bits bajos de la direccion se ignoran
//   5. Fuera de rango: ceros, y sin envolver al bundle 0
//   6. Carga por $readmemh, incluidas las posiciones que el archivo no trae
// =============================================================================

`include "cerbero_defs.svh"

module tb_imem;

  localparam int N_GRANDE  = 2048;   // la de verdad, 32 KB
  localparam int N_CHICA   = 4;      // una pequena, para el caso de $readmemh

  localparam logic [`BUNDLE_W-1:0] NOPS = {`BUNDLE_W{1'b0}};

  // ---------------------------------------------------------------------------
  // Reloj
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Instancia principal, sin archivo de carga
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0]     addr;
  logic [`BUNDLE_W-1:0] bundle;

  imem #(
      .NUM_BUNDLES (N_GRANDE),
      .INIT_FILE   ("")
  ) u_mem (
      .clk    (clk),
      .addr   (addr),
      .bundle (bundle)
  );

  // ---------------------------------------------------------------------------
  // Instancia pequena, cargada desde archivo
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0]     addr_f;
  logic [`BUNDLE_W-1:0] bundle_f;

  imem #(
      .NUM_BUNDLES (N_CHICA),
      .INIT_FILE   ("../tb/imem_init.hex")
  ) u_arch (
      .clk    (clk),
      .addr   (addr_f),
      .bundle (bundle_f)
  );

  // ---------------------------------------------------------------------------
  // Contadores y comprobaciones
  // ---------------------------------------------------------------------------

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check128(input string nombre,
                          input logic [`BUNDLE_W-1:0] obtenido,
                          input logic [`BUNDLE_W-1:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-44s", nombre);
        $display("           obtenido %032h", obtenido);
        $display("           esperado %032h", esperado);
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
  // Acceso
  //
  // La direccion se presenta justo despues de un flanco de bajada, de modo que
  // este estable durante todo el ciclo siguiente, que es lo que va a hacer el
  // contador de programa. El bundle se mira despues del flanco de subida que
  // lo registra.
  // ---------------------------------------------------------------------------

  task automatic leer(input logic [`XLEN-1:0] a);
    begin
      @(negedge clk);
      #1 addr = a;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic leer_arch(input logic [`XLEN-1:0] a);
    begin
      @(negedge clk);
      #1 addr_f = a;
      @(posedge clk);
      #1;
    end
  endtask

  // Patrones de prueba. Se derivan del indice para que cada bundle sea
  // distinguible de los demas y de un bundle nulo. Nada de part-selects:
  // Icarus se queja de ellos en algunos contextos y aqui no hacen falta.
  function automatic logic [`BUNDLE_W-1:0] patron(input integer k);
    logic [31:0] base;
    begin
      base   = 32'h1111_1111 * k;
      patron = { 32'hC0DE_0000 + base,
                 32'hA5A5_5A5A ^ base,
                 ~base,
                 base };
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_imem.vcd");
      $dumpvars(0, tb_imem);
    end

    addr   = '0;
    addr_f = '0;

    $display("=== tb_imem: memoria de instrucciones ===");

    // ------------------------------------------------------------------------
    $display("[1] memoria sin inicializar");
    // ------------------------------------------------------------------------
    // El bloque initial del modulo barre el arreglo a cero. Sin ese barrido
    // aqui saldrian X, que dentro de un bundle contaminan los cinco slots.

    leer(32'h0000_0000);
    check128("bundle 0 de una memoria vacia es nulo", bundle, NOPS);

    leer(32'h0000_0010);
    check128("bundle 1 de una memoria vacia es nulo", bundle, NOPS);

    leer(32'h0000_7FF0);
    check128("ultimo bundle de una memoria vacia es nulo", bundle, NOPS);

    // ------------------------------------------------------------------------
    $display("[2] lectura de contenido cargado");
    // ------------------------------------------------------------------------
    // Carga por referencia jerarquica, igual que van a hacer los testbenches
    // de integracion y el volcado del caso 6 del enunciado.

    u_mem.storage[0]            = patron(1);   // distinto de cero a proposito
    u_mem.storage[1]            = patron(2);
    u_mem.storage[2]            = patron(3);
    u_mem.storage[5]            = patron(6);
    u_mem.storage[N_GRANDE-1]   = patron(7);

    leer(32'h0000_0000);
    check128("bundle en la direccion 0x0000", bundle, patron(1));

    leer(32'h0000_0010);
    check128("bundle en la direccion 0x0010", bundle, patron(2));

    leer(32'h0000_0020);
    check128("bundle en la direccion 0x0020", bundle, patron(3));

    leer(32'h0000_0050);
    check128("bundle en la direccion 0x0050", bundle, patron(6));

    leer(32'h0000_7FF0);
    check128("ultimo bundle implementado, 0x7FF0", bundle, patron(7));

    leer(32'h0000_0030);
    check128("una posicion no cargada sigue siendo nula", bundle, NOPS);

    // ------------------------------------------------------------------------
    $display("[3] la lectura es sincrona");
    // ------------------------------------------------------------------------
    // Se cambia la direccion a mitad de ciclo y se comprueba que la salida NO
    // se mueve hasta el flanco de subida. Una memoria con lectura
    // combinacional pasaria todos los casos anteriores y fallaria aqui.

    leer(32'h0000_0000);                       // la salida trae patron(1)

    #1 addr = 32'h0000_0010;                   // nueva direccion, mismo ciclo
    #2;
    check128("la salida no cambia antes del flanco", bundle, patron(1));

    @(posedge clk);
    #1;
    check128("la salida cambia en el flanco de subida", bundle, patron(2));

    // ------------------------------------------------------------------------
    $display("[4] los cuatro bits bajos de la direccion se ignoran");
    // ------------------------------------------------------------------------
    // El contador de programa avanza de 16 en 16 y la unidad de saltos calcula
    // en bundles, asi que no hay forma de construir un valor desalineado. La
    // memoria los descarta en vez de comprobarlos.

    leer(32'h0000_0011);
    check128("la direccion 0x0011 cae en el bundle 1", bundle, patron(2));

    leer(32'h0000_001F);
    check128("la direccion 0x001F cae en el bundle 1", bundle, patron(2));

    leer(32'h0000_0020);
    check128("la direccion 0x0020 ya es el bundle 2", bundle, patron(3));

    // ------------------------------------------------------------------------
    $display("[5] fuera de rango");
    // ------------------------------------------------------------------------
    // El bundle 0 tiene un patron distinto de cero, asi que si la
    // comprobacion de rango no estuviera, la direccion 0x8000 devolveria ese
    // patron en vez de ceros: el indice truncado de 2048 es 0.

    leer(32'h0000_8000);
    check128("0x8000 entrega ceros, no el bundle 0", bundle, NOPS);

    leer(32'h0001_0000);
    check128("una direccion muy alta entrega ceros", bundle, NOPS);

    leer(32'hFFFF_FFF0);
    check128("la ultima direccion del espacio entrega ceros", bundle, NOPS);

    leer(32'h0000_7FF0);
    check128("vuelve a leer bien despues de salirse de rango",
             bundle, patron(7));

    // ------------------------------------------------------------------------
    $display("[6] carga por $readmemh");
    // ------------------------------------------------------------------------
    // La instancia pequena tiene 4 bundles y el archivo trae 3. Lo que el
    // archivo no cubre tiene que quedar nulo, no indefinido.

    leer_arch(32'h0000_0000);
    check128("bundle 0 del archivo", bundle_f,
             128'h00112233445566778899AABBCCDDEEFF);

    leer_arch(32'h0000_0010);
    check128("bundle 1 del archivo", bundle_f,
             128'h0F1E2D3C4B5A69788796A5B4C3D2E1F0);

    leer_arch(32'h0000_0020);
    check128("bundle 2 del archivo", bundle_f,
             128'hDEADBEEFCAFEBABE0123456789ABCDEF);

    leer_arch(32'h0000_0030);
    check128("el bundle que el archivo no trae queda nulo", bundle_f, NOPS);

    leer_arch(32'h0000_0040);
    check128("fuera de la memoria pequena entrega ceros", bundle_f, NOPS);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check128("caso deliberadamente incorrecto", NOPS, patron(1));
`endif

    resumen();
  end

endmodule
