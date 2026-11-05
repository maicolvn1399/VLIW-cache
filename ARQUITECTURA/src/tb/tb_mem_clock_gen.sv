`timescale 1ns/1ps

// =============================================================================
// tb_mem_clock_gen.sv - Testbench del dominio de reloj de memoria.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Lo que importa de este modulo no es que genere "un reloj mas lento": es que
// mem_tick y mem_clk digan lo mismo. Toda la latencia de memoria se cuenta con
// mem_tick, y si ese pulso apareciera un ciclo corrido respecto del flanco de
// mem_clk, las palabras del burst se leerian de un arreglo que todavia no
// cambio y nada en la simulacion se quejaria.
//
// Por eso la prueba central es la 3: se verifica la invariante
//
//     mem_tick encendido  <=>  mem_clk sube en este mismo flanco
//
// en las dos direcciones, sobre varios periodos y para los tres divisores que
// el enunciado permite (4 para 25 MHz, 2 para 50 MHz, 5 para 20 MHz).
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. El reset deja el generador en un estado consistente
//   2. El periodo de mem_clk es de DIV ciclos de procesador
//   3. mem_tick coincide con el flanco de subida de mem_clk, siempre
//   4. Hay exactamente un tick por periodo
//   5. En 7*DIV ciclos ocurren exactamente 7 ticks, sea cual sea la fase
//   6. Los otros dos divisores del rango permitido se comportan igual
// =============================================================================

`include "cerbero_defs.svh"

module tb_mem_clock_gen;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // Tres generadores en paralelo, uno por divisor permitido
  logic mem_clk_4, tick_4;    // 25 MHz, el elegido
  logic mem_clk_2, tick_2;    // 50 MHz
  logic mem_clk_5, tick_5;    // 20 MHz

  mem_clock_gen #(.DIV (4)) dut (
      .clk (clk), .rst_n (rst_n), .mem_clk (mem_clk_4), .mem_tick (tick_4));

  mem_clock_gen #(.DIV (2)) dut_2 (
      .clk (clk), .rst_n (rst_n), .mem_clk (mem_clk_2), .mem_tick (tick_2));

  mem_clock_gen #(.DIV (5)) dut_5 (
      .clk (clk), .rst_n (rst_n), .mem_clk (mem_clk_5), .mem_tick (tick_5));

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

  task automatic check_ok(input string nombre, input logic condicion);
    begin
      tests_run = tests_run + 1;
      if (condicion !== 1'b1) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %s", nombre);
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
  // Vigilancia continua de la invariante
  //
  // Un proceso aparte mira cada flanco: si mem_clk paso de 0 a 1, tiene que
  // haber un tick, y si hay un tick, mem_clk tiene que haber pasado de 0 a 1.
  // Mirarlo asi, en vez de en puntos sueltos de la secuencia, hace que un
  // desfase en CUALQUIER ciclo de toda la corrida quede registrado.
  // ---------------------------------------------------------------------------

  // Durante el reset se fuerzan al valor que mem_clk tiene ahi, en bajo, en vez
  // de copiar la salida del DUT: en el primer flanco de la simulacion esa
  // salida todavia no fue asignada y copiarla dejaria una x que haria fallar la
  // primera comparacion sin que haya nada mal en el generador.
  logic   previo_4, previo_2, previo_5;
  integer desfases = 0;
  integer subidas  = 0;
  integer ticks    = 0;
  logic   vigilando = 1'b0;

  task automatic revisar(input string  nombre,
                         input logic   antes,
                         input logic   ahora,
                         input logic   tick);
    logic subio;
    begin
      subio = !antes && ahora;
      if (subio !== tick) begin
        desfases = desfases + 1;
        $display("  FALLA  %s: subio=%b tick=%b", nombre, subio, tick);
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && vigilando) begin
      revisar("DIV=4", previo_4, mem_clk_4, tick_4);
      revisar("DIV=2", previo_2, mem_clk_2, tick_2);
      revisar("DIV=5", previo_5, mem_clk_5, tick_5);
      if (!previo_4 && mem_clk_4) subidas = subidas + 1;
      if (tick_4)                 ticks   = ticks + 1;
    end

    // Durante el reset el valor previo se fuerza al que los tres generadores
    // tienen en reset, en vez de copiar la salida. En el primer flanco de toda
    // la simulacion esa salida todavia no fue asignada por el DUT y copiarla
    // dejaria una x que haria fallar la primera comparacion sin que haya nada
    // mal en el generador.
    if (!rst_n) begin
      previo_4 <= 1'b0;
      previo_2 <= 1'b0;
      previo_5 <= 1'b0;
    end else begin
      previo_4 <= mem_clk_4;
      previo_2 <= mem_clk_2;
      previo_5 <= mem_clk_5;
    end
  end

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i;
  integer ticks_en_ventana;
  integer periodo;
  integer fase;

  initial begin
    if ($test$plusargs("VCD") || $value$plusargs("VCD=%s", i)) begin
      $dumpfile("tb_mem_clock_gen.vcd");
      $dumpvars(0, tb_mem_clock_gen);
    end

    $display("");
    $display("=== tb_mem_clock_gen: el dominio de 25 MHz ===");

    rst_n = 1'b0;
    @(posedge clk);
    #1;

    // ---- 1. Reset ----------------------------------------------------------
    // Durante el reset no puede haber ticks: un tick significa flanco de
    // memoria, y una memoria en reset no esta avanzando ciclos. El primer tick
    // de la simulacion tiene que ser el del primer flanco despues de soltarlo.
    $display("");
    $display("[1] durante el reset no hay ticks");
    check_ok("mem_clk en bajo durante el reset",    mem_clk_4 === 1'b0);
    check_ok("mem_tick apagado durante el reset",   tick_4    === 1'b0);
    check_ok("y tampoco en los otros divisores",
             (tick_2 === 1'b0) && (tick_5 === 1'b0));

    rst_n     = 1'b1;
    vigilando = 1'b1;

    // ---- 2. El periodo -----------------------------------------------------
    // Se mide contando ciclos de procesador entre dos subidas de mem_clk, que
    // es la definicion de la razon de frecuencias: 100 MHz / 4 = 25 MHz.
    $display("");
    $display("[2] el periodo de mem_clk mide DIV ciclos de procesador");

    @(negedge mem_clk_4);
    @(posedge mem_clk_4);
    periodo = 0;
    fork
      begin : medir
        forever begin
          @(posedge clk);
          periodo = periodo + 1;
        end
      end
      begin
        @(posedge mem_clk_4);
        disable medir;
      end
    join

    check("ciclos de procesador por periodo", periodo, `MEM_CLK_DIV);

    // ---- 3 y 4. La invariante y el conteo ----------------------------------
    $display("");
    $display("[3] mem_tick coincide con el flanco de mem_clk, ciclo a ciclo");
    subidas = 0;
    ticks   = 0;
    repeat (20 * `MEM_CLK_DIV) @(posedge clk);
    #1;
    check("desfases en 20 periodos", desfases, 0);

    $display("");
    $display("[4] un tick por periodo, ni mas ni menos");
    check("subidas de mem_clk contadas", subidas, 20);
    check("ticks contados",              ticks,   20);

    // ---- 5. La ventana del burst -------------------------------------------
    // Esta es la propiedad de la que depende que T_mem sea exacto. El
    // controlador cuenta la fase de burst en CICLOS DE PROCESADOR
    // (MEM_BURST_REST * MEM_CLK_DIV = 28) y confia en que ahi caben exactamente
    // 7 flancos de memoria, empiece la ventana en la fase que empiece.
    //
    // Se prueban las DIV fases posibles. Si en alguna cayeran 6 u 8 ticks, el
    // burst leeria de menos o de mas y T_mem no seria deterministico.
    $display("");
    $display("[5] en %0d ciclos caben exactamente %0d ticks, en toda fase",
             `MEM_BURST_REST * `MEM_CLK_DIV, `MEM_BURST_REST);

    for (fase = 0; fase < `MEM_CLK_DIV; fase = fase + 1) begin
      // Alinear al inicio de un periodo y despues correr 'fase' ciclos, para
      // que la ventana empiece en cada uno de los desplazamientos posibles
      @(posedge mem_clk_4);
      for (i = 0; i < fase; i = i + 1) @(posedge clk);

      ticks_en_ventana = 0;
      for (i = 0; i < `MEM_BURST_REST * `MEM_CLK_DIV; i = i + 1) begin
        @(posedge clk);
        #1;
        if (tick_4) ticks_en_ventana = ticks_en_ventana + 1;
      end
      check($sformatf("ticks con la ventana en la fase %0d", fase),
            ticks_en_ventana, `MEM_BURST_REST);
    end

    // ---- 6. Los otros divisores --------------------------------------------
    // El enunciado deja elegir entre 20 y 50 MHz. Aunque el grupo eligio 25, el
    // modulo tiene que servir para los tres: el dia que se quiera medir con
    // otra frecuencia, basta cambiar MEM_CLK_DIV.
    $display("");
    $display("[6] los otros dos divisores del rango permitido");
    check("desfases acumulados en los tres divisores", desfases, 0);

    // DIV=2 (50 MHz): el divisor minimo, donde el reloj lento alterna en cada
    // ciclo y el margen entre flancos es el mas chico
    @(posedge mem_clk_2);
    periodo = 0;
    fork
      begin : medir2
        forever begin
          @(posedge clk);
          periodo = periodo + 1;
        end
      end
      begin
        @(posedge mem_clk_2);
        disable medir2;
      end
    join
    check("periodo con DIV=2 (50 MHz)", periodo, 2);

    // DIV=5 (20 MHz): divisor impar, el ciclo de trabajo queda en 40 % y lo que
    // se comprueba es que el periodo y el tick siguen siendo correctos
    @(posedge mem_clk_5);
    periodo = 0;
    fork
      begin : medir5
        forever begin
          @(posedge clk);
          periodo = periodo + 1;
        end
      end
      begin
        @(posedge mem_clk_5);
        disable medir5;
      end
    join
    check("periodo con DIV=5 (20 MHz, impar)", periodo, 5);

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", periodo, 999);
`endif

    $display("");
    resumen();
  end

endmodule
