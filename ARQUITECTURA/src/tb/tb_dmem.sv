`timescale 1ns/1ps

// =============================================================================
// tb_dmem.sv - Testbench de la memoria de datos.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Esta memoria tiene dos propiedades que no se pueden dar por supuestas,
// porque el resto del diseno descansa sobre ellas:
//
//   1. byte_enable MANDA. La LSU replica el dato en los cuatro carriles de la
//      palabra y deja que la mascara decida cual se escribe, asi que los
//      carriles no marcados traen una copia del dato, no ceros. Una memoria
//      que ignore la mascara se ve perfecta con SW, donde vale 1111, y
//      corrompe los tres bytes vecinos en el primer SB. La seccion 3 escribe
//      0xEFEFEFEF con mascaras de un solo carril justo para que ese error no
//      tenga donde esconderse.
//
//   2. La LECTURA es en el POSEDGE y la ESCRITURA en el NEGEDGE, en ese orden
//      dentro del ciclo. De ahi sale que no haya riesgo de almacenamiento a
//      carga: una lectura no ve la escritura de su propio ciclo, pero si ve la
//      del ciclo anterior. La seccion 5 mide las dos mitades de esa frase; sin
//      la primera, una memoria con escritura en el posedge pasaria igual.
//
// Los valores esperados son constantes escritas a mano. El testbench nunca
// recalcula la mezcla de carriles: si lo hiciera, un error en la formula
// apareceria en el modulo y en la prueba a la vez y el caso pasaria.
//
// OJO: el caso de $readmemh abre ../tb/dmem_init.hex con ruta relativa, asi
// que este testbench se ejecuta desde src/build, que es lo que hace el make.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Memoria sin inicializar: ceros, no valores en X
//   2. Escritura y lectura de palabra completa, y volcado jerarquico
//   3. Las ocho combinaciones de mascara que importan, con dato replicado
//   4. Orden de bytes little-endian
//   5. La lectura no ve la escritura de su ciclo, pero si la del anterior
//   6. Escalado del indice y los dos bits bajos de la direccion
//   7. Una escritura por carril no toca las palabras vecinas
//   8. Fuera de rango: lectura en ceros, escritura descartada, sin envolver
//   9. Carga por $readmemh, incluidas las posiciones que el archivo no trae
// =============================================================================

`include "cerbero_defs.svh"

module tb_dmem;

  localparam int N_GRANDE = 16384;   // la de verdad, 64 KB
  localparam int N_CHICA  = 4;       // una pequena, para el caso de $readmemh

  localparam logic [`XLEN-1:0] CEROS = {`XLEN{1'b0}};

  // ---------------------------------------------------------------------------
  // Reloj
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Instancia principal
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] addr;
  logic             we;
  logic [3:0]       byte_enable;
  logic [`XLEN-1:0] wdata;
  logic [`XLEN-1:0] rdata;

  dmem #(
      .NUM_WORDS (N_GRANDE),
      .INIT_FILE ("")
  ) u_mem (
      .clk         (clk),
      .addr        (addr),
      .we          (we),
      .byte_enable (byte_enable),
      .wdata       (wdata),
      .rdata       (rdata)
  );

  // ---------------------------------------------------------------------------
  // Instancia pequena, cargada desde archivo. Solo se lee.
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] addr_f;
  logic [`XLEN-1:0] rdata_f;

  dmem #(
      .NUM_WORDS (N_CHICA),
      .INIT_FILE ("../tb/dmem_init.hex")
  ) u_arch (
      .clk         (clk),
      .addr        (addr_f),
      .we          (1'b0),
      .byte_enable (4'b0000),
      .wdata       (CEROS),
      .rdata       (rdata_f)
  );

  // ---------------------------------------------------------------------------
  // Contadores y comprobaciones
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
  // Las senales se presentan justo despues de un flanco de bajada y quedan
  // estables durante todo el ciclo siguiente. Es lo que va a hacer la LSU, que
  // las entrega de forma combinacional durante EX.
  // ---------------------------------------------------------------------------

  task automatic escribir(input logic [`XLEN-1:0] a,
                          input logic [3:0]       be,
                          input logic [`XLEN-1:0] d);
    begin
      @(negedge clk);
      #1;
      addr        = a;
      we          = 1'b1;
      byte_enable = be;
      wdata       = d;
      @(negedge clk);          // este flanco es el que escribe
      #1 we = 1'b0;
    end
  endtask

  task automatic leer(input logic [`XLEN-1:0] a);
    begin
      @(negedge clk);
      #1;
      addr = a;
      we   = 1'b0;
      @(posedge clk);          // este flanco registra el dato
      #1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  logic [`XLEN-1:0] en_su_ciclo;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_dmem.vcd");
      $dumpvars(0, tb_dmem);
    end

    addr        = '0;
    we          = 1'b0;
    byte_enable = 4'b0000;
    wdata       = '0;
    addr_f      = '0;

    $display("=== tb_dmem: memoria de datos ===");

    // ------------------------------------------------------------------------
    $display("[1] memoria sin inicializar");
    // ------------------------------------------------------------------------

    leer(32'h0000_0000);
    check32("la palabra 0 de una memoria vacia es cero", rdata, CEROS);

    leer(32'h0000_0004);
    check32("la palabra 1 de una memoria vacia es cero", rdata, CEROS);

    leer(32'h0000_FFFC);
    check32("la ultima palabra de una memoria vacia es cero", rdata, CEROS);

    // ------------------------------------------------------------------------
    $display("[2] escritura y lectura de palabra completa");
    // ------------------------------------------------------------------------

    escribir(32'h0000_0010, 4'b1111, 32'h1122_3344);
    leer(32'h0000_0010);
    check32("SW y su lectura posterior", rdata, 32'h1122_3344);

    // El volcado por referencia jerarquica es lo que necesita el caso 6 del
    // enunciado, que pide revisar la memoria despues de cifrar.
    check32("la misma palabra vista por referencia jerarquica",
            u_mem.storage[4], 32'h1122_3344);

    // ------------------------------------------------------------------------
    $display("[3] mascara de bytes con dato replicado");
    // ------------------------------------------------------------------------
    // En cada caso se recarga la palabra completa y despues se escribe
    // 0xEFEFEFEF, que es como llega el dato desde la LSU: replicado en los
    // cuatro carriles. Solo los carriles marcados deben cambiar.
    //
    // Las direcciones van de 0x20 a 0x23, que son la MISMA palabra: el carril
    // lo elige la mascara, no los bits bajos de la direccion. La LSU ya
    // tradujo unos en la otra.

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0020, 4'b0001, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SB con mascara 0001 toca solo el carril 0",
            rdata, 32'h1122_33EF);

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0021, 4'b0010, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SB con mascara 0010 toca solo el carril 1",
            rdata, 32'h1122_EF44);

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0022, 4'b0100, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SB con mascara 0100 toca solo el carril 2",
            rdata, 32'h11EF_3344);

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0023, 4'b1000, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SB con mascara 1000 toca solo el carril 3",
            rdata, 32'hEF22_3344);

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0020, 4'b0011, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SH con mascara 0011 toca la media palabra baja",
            rdata, 32'h1122_EFEF);

    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0022, 4'b1100, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("SH con mascara 1100 toca la media palabra alta",
            rdata, 32'hEFEF_3344);

    // Mascara vacia con habilitador activo: no deberia pasar en operacion
    // normal, pero si la mascara no estuviera cableada a los habilitadores de
    // carril este caso escribiria la palabra entera.
    escribir(32'h0000_0020, 4'b1111, 32'h1122_3344);
    escribir(32'h0000_0020, 4'b0000, 32'hEFEF_EFEF);
    leer(32'h0000_0020);
    check32("mascara 0000 no escribe nada", rdata, 32'h1122_3344);

    // Habilitador apagado con mascara llena: la que manda es we.
    @(negedge clk);
    #1;
    addr        = 32'h0000_0020;
    we          = 1'b0;
    byte_enable = 4'b1111;
    wdata       = 32'hEFEF_EFEF;
    @(negedge clk);
    #1;
    leer(32'h0000_0020);
    check32("con we en cero la mascara llena no escribe",
            rdata, 32'h1122_3344);

    // ------------------------------------------------------------------------
    $display("[4] orden de bytes");
    // ------------------------------------------------------------------------
    // isa.md 1.4 fija little-endian: el byte de la direccion A vive en los
    // bits [7:0] de su palabra. La organizacion interna por palabras lo da sin
    // logica extra, pero conviene dejarlo clavado.

    escribir(32'h0000_0030, 4'b1111, 32'h4433_2211);
    leer(32'h0000_0030);
    check32("palabra de referencia", rdata, 32'h4433_2211);

    escribir(32'h0000_0030, 4'b0001, 32'hABAB_ABAB);
    leer(32'h0000_0030);
    check32("el byte de la direccion 0x30 esta en los bits [7:0]",
            rdata, 32'h4433_22AB);

    escribir(32'h0000_0033, 4'b1000, 32'hCDCD_CDCD);
    leer(32'h0000_0030);
    check32("el byte de la direccion 0x33 esta en los bits [31:24]",
            rdata, 32'hCD33_22AB);

    // ------------------------------------------------------------------------
    $display("[5] orden de los flancos dentro del ciclo");
    // ------------------------------------------------------------------------
    // Aqui se clava la convencion de la que depende el resto del pipeline, y
    // se clava mirando CADA flanco por separado. Comprobar solo el resultado
    // visible no alcanza: una memoria que escriba en el flanco de subida pasa
    // todas las pruebas de comportamiento, porque las asignaciones no
    // bloqueantes ya ordenan la lectura antes de la escritura dentro de un
    // mismo flanco. Para distinguirlas hay que mirar el arreglo interno justo
    // despues de cada flanco, que es lo que hacen los dos casos de 5b.
    //
    // La diferencia no es cosmetica: con los dos flancos separados, lectura y
    // escritura no coinciden nunca en el mismo instante, asi que el resultado
    // no depende del modo de lectura-durante-escritura de la memoria que
    // termine infiriendo la herramienta de sintesis.

    // --- 5a: la lectura es sincrona -----------------------------------------
    // Si fuera combinacional, el dato llegaria medio ciclo antes y el registro
    // de segmentacion EX/MEM dejaria de estar donde el diseno cree.

    escribir(32'h0000_0060, 4'b1111, 32'h1111_0000);
    escribir(32'h0000_0064, 4'b1111, 32'h2222_0000);

    leer(32'h0000_0060);
    #1 addr = 32'h0000_0064;           // nueva direccion a mitad de ciclo
    #2;
    check32("la salida no cambia antes del flanco de subida",
            rdata, 32'h1111_0000);

    @(posedge clk);
    #1;
    check32("la salida cambia en el flanco de subida", rdata, 32'h2222_0000);

    // --- 5b y 5c: la escritura es en el flanco de bajada --------------------
    // La palabra 0x40 es el indice 16 del arreglo interno.

    escribir(32'h0000_0040, 4'b1111, 32'hAAAA_AAAA);

    @(negedge clk);
    #1;
    addr        = 32'h0000_0040;
    we          = 1'b1;
    byte_enable = 4'b1111;
    wdata       = 32'hBBBB_BBBB;

    @(posedge clk);                    // lectura del mismo ciclo
    #1;
    en_su_ciclo = rdata;
    check32("despues del flanco de subida todavia no escribio",
            u_mem.storage[16], 32'hAAAA_AAAA);

    @(negedge clk);                    // aqui escribe
    #1;
    check32("despues del flanco de bajada ya escribio",
            u_mem.storage[16], 32'hBBBB_BBBB);
    we = 1'b0;

    @(posedge clk);                    // lectura del ciclo siguiente
    #1;

    check32("la lectura no ve la escritura de su propio ciclo",
            en_su_ciclo, 32'hAAAA_AAAA);
    check32("la lectura del ciclo siguiente ya ve el dato nuevo",
            rdata, 32'hBBBB_BBBB);

    // ------------------------------------------------------------------------
    $display("[6] escalado del indice y bits bajos de la direccion");
    // ------------------------------------------------------------------------
    // Los dos bits bajos no participan: el carril ya viene resuelto en la
    // mascara. La alineacion la comprueba la LSU, que es quien conoce el
    // tamano del acceso, y levanta MISALIGN antes de llegar aqui.

    escribir(32'h0000_0008, 4'b1111, 32'hDEAD_0008);

    leer(32'h0000_0008);
    check32("la direccion 0x08 es la palabra 2", rdata, 32'hDEAD_0008);

    leer(32'h0000_0009);
    check32("la direccion 0x09 cae en la misma palabra", rdata, 32'hDEAD_0008);

    leer(32'h0000_000B);
    check32("la direccion 0x0B cae en la misma palabra", rdata, 32'hDEAD_0008);

    leer(32'h0000_000C);
    check32("la direccion 0x0C ya es la palabra 3", rdata, CEROS);

    // ------------------------------------------------------------------------
    $display("[7] las palabras vecinas no se tocan");
    // ------------------------------------------------------------------------

    escribir(32'h0000_0050, 4'b1111, 32'h5555_5555);
    escribir(32'h0000_0054, 4'b1111, 32'h6666_6666);
    escribir(32'h0000_0058, 4'b1111, 32'h7777_7777);

    escribir(32'h0000_0055, 4'b0010, 32'h9999_9999);

    leer(32'h0000_0050);
    check32("la palabra anterior queda intacta", rdata, 32'h5555_5555);

    leer(32'h0000_0054);
    check32("solo cambio el carril marcado", rdata, 32'h6666_9966);

    leer(32'h0000_0058);
    check32("la palabra siguiente queda intacta", rdata, 32'h7777_7777);

    // ------------------------------------------------------------------------
    $display("[8] fuera de rango");
    // ------------------------------------------------------------------------
    // La LSU ya levanta RANGE y apaga el habilitador, asi que esto es defensa
    // en profundidad. Importa porque el indice se recorta a IDX_W bits: sin la
    // comprobacion, la direccion 16384*4 escribiria la palabra 0.

    escribir(32'h0000_0000, 4'b1111, 32'hC0DE_C0DE);
    escribir(32'h0001_0000, 4'b1111, 32'h0BAD_0BAD);

    leer(32'h0000_0000);
    check32("una escritura fuera de rango no envuelve a la palabra 0",
            rdata, 32'hC0DE_C0DE);

    leer(32'h0001_0000);
    check32("una lectura fuera de rango entrega ceros", rdata, CEROS);

    leer(32'hFFFF_FFFC);
    check32("la ultima direccion del espacio entrega ceros", rdata, CEROS);

    leer(32'h0000_0010);
    check32("vuelve a leer bien despues de salirse de rango",
            rdata, 32'h1122_3344);

    // ------------------------------------------------------------------------
    $display("[9] carga por $readmemh");
    // ------------------------------------------------------------------------
    // La instancia pequena tiene 4 palabras y el archivo trae 3.

    @(negedge clk); #1 addr_f = 32'h0000_0000; @(posedge clk); #1;
    check32("palabra 0 del archivo", rdata_f, 32'hA1B2_C3D4);

    @(negedge clk); #1 addr_f = 32'h0000_0004; @(posedge clk); #1;
    check32("palabra 1 del archivo", rdata_f, 32'h1122_3344);

    @(negedge clk); #1 addr_f = 32'h0000_0008; @(posedge clk); #1;
    check32("palabra 2 del archivo", rdata_f, 32'h0000_FFFF);

    @(negedge clk); #1 addr_f = 32'h0000_000C; @(posedge clk); #1;
    check32("la palabra que el archivo no trae queda en cero",
            rdata_f, CEROS);

    @(negedge clk); #1 addr_f = 32'h0000_0010; @(posedge clk); #1;
    check32("fuera de la memoria pequena entrega ceros", rdata_f, CEROS);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", CEROS, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
