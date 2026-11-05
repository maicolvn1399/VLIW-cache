`timescale 1ns/1ps

// =============================================================================
// tb_perf_counters.sv - Testbench de los contadores de rendimiento.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Un contador que se equivoca no rompe ningun programa: el procesador sigue
// calculando bien y el error aparece solo en el informe, como un numero
// plausible. Por eso esta unidad se prueba contra cuentas escritas a mano, caso
// por caso, en vez de confiar en que "se ve razonable" al final de una corrida.
//
// Lo que mas se cuida aqui es que cada bundle se cuente UNA vez. Hoy el
// pipeline no se detiene y eso es facil; el caso que importa es el que todavia
// no existe, un bundle congelado varios ciclos por un miss de cache, y por eso
// la prueba 6 lo simula con la entrada stall antes de que la cache exista.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: todos los contadores en cero
//   2. Ciclos: suben con o sin bundle, y se detienen con halted
//   3. Un bundle lleno suma cinco instrucciones, una por slot
//   4. Un bundle vacio se cuenta como bundle, no como instruccion
//   5. Un bundle invalido no se cuenta de ninguna forma
//   6. Un bundle congelado por stall se cuenta una sola vez, al avanzar
//   7. Saltos tomados y delay slots desperdiciados
//   8. Los contadores saturan y encienden el bit de desbordamiento
// =============================================================================

`include "cerbero_defs.svh"

module tb_perf_counters;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                 rst_n;
  logic                 id_valid;
  logic [`BUNDLE_W-1:0] id_bundle;
  logic                 id_taken;
  logic                 halted;
  logic                 stall;

  logic [31:0] ciclos, bundles, instrucciones;
  logic [`NSLOTS-1:0][31:0] ops_por_slot;
  logic [31:0] accesos_load, accesos_store;
  logic [31:0] bundles_vacios, saltos_tomados, delay_vacios, ciclos_stall;
  logic        desbordado;

  perf_counters dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .id_valid       (id_valid),
      .id_bundle      (id_bundle),
      .id_taken       (id_taken),
      .halted         (halted),
      .stall          (stall),
      .ciclos         (ciclos),
      .bundles        (bundles),
      .instrucciones  (instrucciones),
      .ops_por_slot   (ops_por_slot),
      .accesos_load   (accesos_load),
      .accesos_store  (accesos_store),
      .bundles_vacios (bundles_vacios),
      .saltos_tomados (saltos_tomados),
      .delay_vacios   (delay_vacios),
      .ciclos_stall   (ciclos_stall),
      .desbordado     (desbordado)
  );

  // Una segunda instancia angosta, para llegar al tope en 255 ciclos en vez de
  // en 4 294 967 295. Es el mismo RTL con otro parametro: lo que se comprueba
  // es la aritmetica de saturacion, que no depende del ancho.
  localparam int ANGOSTO = 8;
  localparam logic [ANGOSTO-1:0] TOPE_ANGOSTO = {ANGOSTO{1'b1}};

  logic [ANGOSTO-1:0] ciclos_chico, bundles_chico, instr_chico;
  logic [`NSLOTS-1:0][ANGOSTO-1:0] ops_chico;
  logic [ANGOSTO-1:0] vacios_chico, saltos_chico, delay_chico, stall_chico;
  logic               desbordado_chico;

  perf_counters #(.CNT_W (ANGOSTO)) dut_chico (
      .clk            (clk),
      .rst_n          (rst_n),
      .id_valid       (id_valid),
      .id_bundle      (id_bundle),
      .id_taken       (id_taken),
      .halted         (halted),
      .stall          (stall),
      .ciclos         (ciclos_chico),
      .bundles        (bundles_chico),
      .instrucciones  (instr_chico),
      .ops_por_slot   (ops_chico),
      .accesos_load   (),
      .accesos_store  (),
      .bundles_vacios (vacios_chico),
      .saltos_tomados (saltos_chico),
      .delay_vacios   (delay_chico),
      .ciclos_stall   (stall_chico),
      .desbordado     (desbordado_chico)
  );

  // ---------------------------------------------------------------------------
  // Arnes
  // ---------------------------------------------------------------------------

  integer tests_run    = 0;
  integer tests_failed = 0;

  task automatic check(input string nombre,
                       input logic [31:0] obtenido,
                       input logic [31:0] esperado);
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
  // Construccion de bundles
  //
  // Solo importa el opcode de cada slot: el resto de los campos no cambia si
  // una ranura esta ocupada o no, asi que van en cero. Los opcodes se escriben
  // en los mismos rangos que usa dispatch.sv.
  // ---------------------------------------------------------------------------

  function automatic logic [`BUNDLE_W-1:0] arma(input logic [4:0] op0,
                                                input logic [4:0] op1,
                                                input logic [4:0] op2,
                                                input logic [2:0] op3,
                                                input logic [2:0] op4);
    logic [31:0] s0, s1, s2;
    logic [15:0] s3, s4;
    begin
      s0 = '0;  s0[`F_OPC]  = op0;
      s1 = '0;  s1[`F_OPC]  = op1;
      s2 = '0;  s2[`F_OPC]  = op2;
      s3 = '0;  s3[`S3_OPC] = op3;
      s4 = '0;  s4[`S4_OPC] = op4;
      arma = {s0, s1, s2, s3, s4};
    end
  endfunction

  // Los cinco slots ocupados, y los cinco en NOP
  localparam logic [`BUNDLE_W-1:0] VACIO = 128'h0;

  logic [`BUNDLE_W-1:0] LLENO, SOLO_S2, SOLO_SALTO;
  logic [`BUNDLE_W-1:0] SOLO_LOAD, SOLO_STORE, LOAD_INC, STORE_INC;
  logic [`BUNDLE_W-1:0] LOAD_BYTE, STORE_HALF;

  initial begin
    LLENO      = arma(`ALU_ADD, `ALU_SUB, `LSU_LW,  `CRP_SALU, `BRU_BR);
    SOLO_S2    = arma(`ALU_NOP, `ALU_NOP, `LSU_SW,  `CRP_NOP,  `BRU_NOP);
    SOLO_SALTO = arma(`ALU_NOP, `ALU_NOP, `LSU_NOP, `CRP_NOP,  `BRU_BR);

    // Los accesos a memoria, uno de cada forma. Se prueban todas las variantes
    // porque el contador no decodifica el opcode completo: mira un solo bit, y
    // una variante nueva que lo pusiera al reves se contaria del lado opuesto
    // sin que nada mas cambiara.
    SOLO_LOAD  = arma(`ALU_NOP, `ALU_NOP, `LSU_LW,     `CRP_NOP, `BRU_NOP);
    SOLO_STORE = arma(`ALU_NOP, `ALU_NOP, `LSU_SW,     `CRP_NOP, `BRU_NOP);
    LOAD_INC   = arma(`ALU_NOP, `ALU_NOP, `LSU_LW_INC, `CRP_NOP, `BRU_NOP);
    STORE_INC  = arma(`ALU_NOP, `ALU_NOP, `LSU_SW_INC, `CRP_NOP, `BRU_NOP);
    LOAD_BYTE  = arma(`ALU_NOP, `ALU_NOP, `LSU_LBU,    `CRP_NOP, `BRU_NOP);
    STORE_HALF = arma(`ALU_NOP, `ALU_NOP, `LSU_SH,     `CRP_NOP, `BRU_NOP);
  end

  // ---------------------------------------------------------------------------
  // Un ciclo de reloj con las entradas que se le indiquen. Al volver, los
  // contadores ya reflejan ese ciclo.
  // ---------------------------------------------------------------------------

  task automatic paso(input logic [`BUNDLE_W-1:0] b,
                      input logic                 v,
                      input logic                 tk);
    begin
      id_bundle = b;
      id_valid  = v;
      id_taken  = tk;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n     = 1'b0;
      id_valid  = 1'b0;
      id_bundle = VACIO;
      id_taken  = 1'b0;
      halted    = 1'b0;
      stall     = 1'b0;
      @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i;

  initial begin
    if ($test$plusargs("VCD") || $value$plusargs("VCD=%s", i)) begin
      $dumpfile("tb_perf_counters.vcd");
      $dumpvars(0, tb_perf_counters);
    end

    $display("");
    $display("=== tb_perf_counters ===");

    // ---- 1. Reset ----------------------------------------------------------
    $display("");
    $display("[1] el reset deja todos los contadores en cero");
    reiniciar();
    check("ciclos",          ciclos,         0);
    check("bundles",         bundles,        0);
    check("instrucciones",   instrucciones,  0);
    check("bundles vacios",  bundles_vacios, 0);
    check("saltos tomados",  saltos_tomados, 0);
    check("delay vacios",    delay_vacios,   0);
    check("ciclos de stall", ciclos_stall,   0);
    check1("sin desbordamiento", desbordado, 1'b0);

    // ---- 2. Ciclos ---------------------------------------------------------
    // Los ciclos cuentan el tiempo, no el trabajo: un ciclo sin bundle valido
    // (una burbuja, o el arranque) tambien es un ciclo que el programa tardo.
    $display("");
    $display("[2] los ciclos corren con o sin bundle, y HALT los detiene");
    repeat (4) paso(VACIO, 1'b0, 1'b0);
    check("4 ciclos sin bundle valido",  ciclos,  4);
    check("y ningun bundle contado",     bundles, 0);

    repeat (3) paso(LLENO, 1'b1, 1'b0);
    check("3 ciclos mas, con bundles",   ciclos,  7);

    halted = 1'b1;
    repeat (5) paso(VACIO, 1'b0, 1'b0);
    check("halted congela los ciclos",   ciclos,  7);
    halted = 1'b0;

    // ---- 3. Un bundle lleno ------------------------------------------------
    $display("");
    $display("[3] un bundle con sus cinco ranuras ocupadas");
    reiniciar();
    paso(LLENO, 1'b1, 1'b0);
    check("bundles",                 bundles,          1);
    check("instrucciones",           instrucciones,    5);
    check("ocupacion de S0 (ALU-0)", ops_por_slot[0],  1);
    check("ocupacion de S1 (ALU-1)", ops_por_slot[1],  1);
    check("ocupacion de S2 (LSU)",   ops_por_slot[2],  1);
    check("ocupacion de S3 (cripto)",ops_por_slot[3],  1);
    check("ocupacion de S4 (BRU)",   ops_por_slot[4],  1);
    check("ningun bundle vacio",     bundles_vacios,   0);

    $display("");
    $display("    un bundle con una sola operacion, en S2");
    paso(SOLO_S2, 1'b1, 1'b0);
    check("bundles",                 bundles,          2);
    check("instrucciones",           instrucciones,    6);
    check("S2 subio",                ops_por_slot[2],  2);
    check("S0 no subio",             ops_por_slot[0],  1);

    // ---- 4. Un bundle vacio ------------------------------------------------
    // Un bundle de puros NOP cuesta un ciclo igual que cualquier otro. Se
    // cuenta como bundle y como vacio, pero no suma instrucciones: esa
    // diferencia es justamente la que mide cuanto del bundle se desperdicia.
    $display("");
    $display("[4] un bundle de puros NOP");
    paso(VACIO, 1'b1, 1'b0);
    check("bundles",               bundles,        3);
    check("instrucciones iguales", instrucciones,  6);
    check("bundles vacios",        bundles_vacios, 1);

    // ---- 5. Un bundle invalido ---------------------------------------------
    // Durante el reset y despues de HALT entra basura en el pipeline con valid
    // en cero. Si se contara, todo programa terminaria con bundles de mas.
    $display("");
    $display("[5] un bundle con valid en cero no existe para los contadores");
    paso(LLENO, 1'b0, 1'b0);
    check("bundles",        bundles,        3);
    check("instrucciones",  instrucciones,  6);
    check("bundles vacios", bundles_vacios, 1);

    // ---- 6. Stall ----------------------------------------------------------
    // El caso que todavia no puede ocurrir: el mismo bundle, quieto en ID
    // durante cuatro ciclos porque la jerarquia de memoria no responde. Tiene
    // que contarse una sola vez, el ciclo en que avanza.
    $display("");
    $display("[6] un bundle congelado por stall se cuenta una sola vez");
    reiniciar();
    stall = 1'b1;
    repeat (4) paso(LLENO, 1'b1, 1'b0);
    check("4 ciclos de stall",          ciclos_stall,   4);
    check("los ciclos igual corren",    ciclos,         4);
    check("ningun bundle contado aun",  bundles,        0);
    check("ninguna instruccion aun",    instrucciones,  0);

    stall = 1'b0;
    paso(LLENO, 1'b1, 1'b0);
    check("el bundle avanza y se cuenta", bundles,       1);
    check("con sus cinco instrucciones",  instrucciones, 5);
    check("el stall no subio mas",        ciclos_stall,  4);
    check("5 ciclos en total",            ciclos,        5);

    // ---- 7. Saltos y delay slots -------------------------------------------
    // En CERBERO-1 un salto no vacia el pipeline: ejecuta el bundle siguiente
    // pase lo que pase (microarchitecture.md 4.1). El costo de un salto es,
    // entonces, un delay slot que no trae trabajo. Eso es lo que se mide.
    $display("");
    $display("[7] saltos tomados y delay slots desperdiciados");
    reiniciar();

    paso(SOLO_SALTO, 1'b1, 1'b1);   // salto tomado
    paso(VACIO,      1'b1, 1'b0);   // su delay slot, vacio
    check("saltos tomados",        saltos_tomados, 1);
    check("delay slots perdidos",  delay_vacios,   1);

    paso(SOLO_SALTO, 1'b1, 1'b1);   // otro salto tomado
    paso(SOLO_S2,    1'b1, 1'b0);   // su delay slot, con trabajo util
    check("saltos tomados",              saltos_tomados, 2);
    check("un delay slot aprovechado",   delay_vacios,   1);

    paso(VACIO, 1'b1, 1'b0);        // bundle vacio que NO sigue a un salto
    check("un vacio suelto no es delay", delay_vacios,   1);
    check("pero si cuenta como vacio",   bundles_vacios, 2);

    $display("");
    $display("    un salto que no se toma igual ocupo su ranura");
    reiniciar();
    paso(SOLO_SALTO, 1'b1, 1'b0);   // la BRU evaluo y decidio no saltar
    check("instrucciones",     instrucciones,   1);
    check("ocupacion de S4",   ops_por_slot[4], 1);
    check("saltos tomados",    saltos_tomados,  0);

    // ---- 7b. Loads y stores -------------------------------------------------
    // La tabla 2 del enunciado pide los accesos desglosados por read y write, y
    // hasta que exista la cache estos dos contadores son tambien la base del
    // calculo de la linea sin cache: cada uno de ellos seria un viaje a memoria
    // principal de T_mem ciclos.
    $display("");
    $display("[7b] los accesos a memoria, separados por sentido");
    reiniciar();

    paso(SOLO_LOAD,  1'b1, 1'b0);
    check("un load contado",     accesos_load,  1);
    check("y ningun store",      accesos_store, 0);

    paso(SOLO_STORE, 1'b1, 1'b0);
    check("un store contado",    accesos_store, 1);
    check("y el load no subio",  accesos_load,  1);

    $display("");
    $display("    todas las variantes de acceso caen del lado correcto");
    paso(LOAD_INC,   1'b1, 1'b0);
    check("LW.INC cuenta como load",  accesos_load,  2);
    paso(LOAD_BYTE,  1'b1, 1'b0);
    check("LBU cuenta como load",     accesos_load,  3);
    paso(STORE_INC,  1'b1, 1'b0);
    check("SW.INC cuenta como store", accesos_store, 2);
    paso(STORE_HALF, 1'b1, 1'b0);
    check("SH cuenta como store",     accesos_store, 3);

    $display("");
    $display("    la suma cierra contra la ranura S2");
    check("loads + stores", accesos_load + accesos_store, ops_por_slot[2]);

    // Un bundle sin acceso a memoria no mueve ninguno de los dos
    paso(SOLO_SALTO, 1'b1, 1'b0);
    check("un bundle sin LSU no suma loads",  accesos_load,  3);
    check("ni stores",                        accesos_store, 3);

    // Y un bundle invalido tampoco, igual que con el resto de los contadores
    paso(SOLO_LOAD, 1'b0, 1'b0);
    check("un bundle invalido no suma loads", accesos_load,  3);

    // ---- 8. Saturacion -----------------------------------------------------
    // La instancia angosta llega al tope en 255 ciclos. Lo que se comprueba es
    // que se queda ahi y lo avisa, en vez de volver a cero en silencio.
    $display("");
    $display("[8] los contadores saturan y avisan");
    reiniciar();
    check1("arranca sin desbordamiento", desbordado_chico, 1'b0);

    for (i = 0; i < TOPE_ANGOSTO; i = i + 1) paso(VACIO, 1'b0, 1'b0);
    check("el contador angosto llego al tope", {24'd0, ciclos_chico},
          {24'd0, TOPE_ANGOSTO});
    check1("todavia sin desbordamiento",       desbordado_chico, 1'b0);

    repeat (3) paso(VACIO, 1'b0, 1'b0);
    check("el contador se queda en el tope",   {24'd0, ciclos_chico},
          {24'd0, TOPE_ANGOSTO});
    check1("y el bit de desbordamiento prendio", desbordado_chico, 1'b1);

    // El de 32 bits conto lo mismo sin acercarse a su tope: el desbordamiento
    // es del contador, no de la prueba.
    check("el contador de 32 bits no desbordo", ciclos,
          {24'd0, TOPE_ANGOSTO} + 3);
    check1("y su bit sigue apagado",            desbordado, 1'b0);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", bundles, 32'hDEAD);
`endif

    $display("");
    resumen();
  end

endmodule
