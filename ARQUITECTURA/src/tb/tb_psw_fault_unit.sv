`timescale 1ns/1ps

// =============================================================================
// tb_psw_fault_unit.sv - Testbench del PSW y la resolucion de fallas.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Este modulo es el unico sitio del procesador donde se decide QUE SE LE CUENTA
// al programa cuando algo falla, y el programa lo consulta con MFPSW y actua
// sobre eso. Una causa equivocada o un EXC que no se enciende no rompen ninguna
// simulacion: simplemente mienten.
//
// Tres propiedades concentran casi todo el riesgo y cada una tiene su seccion:
//
//   La prioridad dentro de un bundle. Se prueban los diez pares de slots, no
//   uno de ejemplo. Un mux de prioridad con dos ramas cruzadas acierta en la
//   mayoria de los casos y falla solo en los pares que involucran esas dos, asi
//   que probar "S2 gana a S3" no dice nada sobre el resto.
//
//   Que EXC y CAUSE se marcan una sola vez. Hay que comprobar las dos mitades:
//   que la primera falla queda registrada y que la segunda NO la sobreescribe.
//   Sin la segunda mitad, un modulo que guardara siempre la ultima causa pasaria
//   igual.
//
//   Que WCONF es una condicion entre slots. Los dos puertos del slot S2 pueden
//   apuntar al mismo registro en un LW.INC con rd == rbase, y eso el ISA lo
//   define: gana el dato cargado y no es falla. Un detector que compare los
//   siete puertos contra todos los demas reportaria WCONF ahi, que es un falso
//   positivo en el PSW.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: el PSW entero en cero
//   2. Las 16 combinaciones de banderas, y que sin flags_we no se mueven
//   3. AUTH y AUTHFAIL son espejos de la boveda, sin reloj de por medio
//   4. Las seis causas, una por slot, con EXC encendido
//   5. Prioridad: los diez pares de slots y el caso de los cinco a la vez
//   6. EXC y CAUSE pegajosos: la segunda falla no cambia la causa
//   7. WCONF entre slots, puerto por puerto
//   8. Lo que NO es WCONF: mismo slot, y escrituras deshabilitadas
//   9. Una falla de unidad le gana a un WCONF de un slot posterior
//  10. Los bits 31:10 se leen como cero
// =============================================================================

`include "cerbero_defs.svh"

module tb_psw_fault_unit;

  // ---------------------------------------------------------------------------
  // Reloj e interfaz
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic       rst_n;
  logic       flags_we;
  logic [3:0] flags;
  logic       auth, authfail;

  logic       f0, f1, f2, f3, f4;
  logic [2:0] c0, c1, c2, c3, c4;

  logic [`NWRITE_PORTS-1:0]                wen;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   widx;

  logic [`XLEN-1:0] psw;
  logic             wconf_any;

  psw_fault_unit dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .flags_we     (flags_we),
      .flags        (flags),
      .auth         (auth),
      .authfail     (authfail),
      .s0_fault     (f0), .s0_cause (c0),
      .s1_fault     (f1), .s1_cause (c1),
      .s2_fault     (f2), .s2_cause (c2),
      .s3_fault     (f3), .s3_cause (c3),
      .s4_fault     (f4), .s4_cause (c4),
      .write_enable (wen),
      .write_index  (widx),
      .psw          (psw),
      .wconf_any    (wconf_any)
  );

  // Campos del PSW sacados a senales continuas. Los recortes de bits se hacen
  // aqui y no dentro del bloque de estimulos, que es la regla que sigue todo el
  // proyecto desde que Icarus mostro que ignora en silencio los recortes
  // constantes dentro de un proceso.
  logic [2:0]  psw_cause;
  logic        psw_exc, psw_auth, psw_authfail;
  logic [21:0] psw_rsv;
  logic [3:0]  psw_flags;

  assign psw_cause    = psw[`PSW_CAUSE];
  assign psw_exc      = psw[`PSW_EXC];
  assign psw_auth     = psw[`PSW_AUTH];
  assign psw_authfail = psw[`PSW_AUTHFAIL];
  assign psw_rsv      = psw[31:10];
  assign psw_flags    = psw[3:0];

  integer tests_run    = 0;
  integer tests_failed = 0;

  // ---------------------------------------------------------------------------
  // Comprobaciones
  // ---------------------------------------------------------------------------

  task automatic check32(input string nombre,
                         input logic [`XLEN-1:0] obtenido,
                         input logic [`XLEN-1:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  task automatic check3(input string nombre,
                        input logic [2:0] obtenido,
                        input logic [2:0] esperado);
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

  task automatic check_int(input string  nombre,
                           input integer obtenido,
                           input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %0d, esperado %0d",
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
  // Manejo de estimulos
  // ---------------------------------------------------------------------------

  task automatic sin_fallas();
    begin
      f0 = 1'b0; c0 = `CAUSE_NONE;
      f1 = 1'b0; c1 = `CAUSE_NONE;
      f2 = 1'b0; c2 = `CAUSE_NONE;
      f3 = 1'b0; c3 = `CAUSE_NONE;
      f4 = 1'b0; c4 = `CAUSE_NONE;
    end
  endtask

  task automatic sin_escrituras();
    begin
      wen  = '0;
      widx = '0;
    end
  endtask

  task automatic esc(input integer p,
                     input logic   en,
                     input logic [`RIDX_W-1:0] r);
    begin
      wen[p]  = en;
      widx[p] = r;
    end
  endtask

  // Un ciclo completo con los estimulos que esten puestos
  task automatic pulso();
    begin
      @(posedge clk);
      #1;
    end
  endtask

  // Reset sincrono: hace falta un flanco con rst_n en bajo
  task automatic reiniciar();
    begin
      rst_n = 1'b0;
      @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // Inyecta una falla en un solo slot y deja el PSW con el resultado
  task automatic falla_en(input integer slot, input logic [2:0] causa);
    begin
      sin_fallas();
      case (slot)
        0: begin f0 = 1'b1; c0 = causa; end
        1: begin f1 = 1'b1; c1 = causa; end
        2: begin f2 = 1'b1; c2 = causa; end
        3: begin f3 = 1'b1; c3 = causa; end
        4: begin f4 = 1'b1; c4 = causa; end
        default: ;
      endcase
      pulso();
      sin_fallas();
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i, j, malos;
  logic [2:0] causa_i, causa_j, obtenida;
  logic [3:0] banderas;

  // Las seis causas que existen, en orden de codigo
  logic [2:0] causas [0:5];

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_psw_fault_unit.vcd");
      $dumpvars(0, tb_psw_fault_unit);
    end

    causas[0] = `CAUSE_ILLOP;
    causas[1] = `CAUSE_MISALIGN;
    causas[2] = `CAUSE_RANGE;
    causas[3] = `CAUSE_DENIED;
    causas[4] = `CAUSE_NOKEY;
    causas[5] = `CAUSE_WCONF;

    flags_we = 1'b0;
    flags    = 4'b0000;
    auth     = 1'b0;
    authfail = 1'b0;
    sin_fallas();
    sin_escrituras();
    rst_n = 1'b1;

    $display("=== tb_psw_fault_unit: PSW y resolucion de fallas ===");

    // ------------------------------------------------------------------------
    $display("[1] reset");
    // ------------------------------------------------------------------------

    reiniciar();
    check32("el PSW entero queda en cero", psw, 32'h0000_0000);

    // ------------------------------------------------------------------------
    $display("[2] banderas de ALU-0");
    // ------------------------------------------------------------------------
    // flags llega con el orden {V, C, N, Z}, que es el de flags_o en alu.sv, y
    // ocupa los bits 3:0 del PSW en el mismo orden.

    malos = 0;
    for (i = 0; i < 16; i = i + 1) begin
      banderas = i;
      flags_we = 1'b1;
      flags    = banderas;
      pulso();
      if (psw_flags !== banderas) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         flags=%b dio psw[3:0]=%b", banderas, psw_flags);
      end
    end
    flags_we = 1'b0;
    check_int("las 16 combinaciones de banderas", malos, 0);

    // El ultimo valor escrito fue 1111; sin habilitador no debe moverse
    flags    = 4'b0000;
    flags_we = 1'b0;
    pulso();
    pulso();
    check32("sin flags_we las banderas no cambian", psw, 32'h0000_000F);

    // ------------------------------------------------------------------------
    $display("[3] AUTH y AUTHFAIL son espejos");
    // ------------------------------------------------------------------------
    // Son cables desde key_vault, no registros de este modulo: el PSW tiene que
    // reflejarlos sin esperar un flanco.

    reiniciar();
    auth = 1'b1; authfail = 1'b0;
    #1;
    check1("AUTH aparece sin flanco de reloj", psw_auth, 1'b1);
    check1("AUTHFAIL sigue apagado",           psw_authfail, 1'b0);

    auth = 1'b0; authfail = 1'b1;
    #1;
    check1("AUTH se apaga sin flanco",      psw_auth, 1'b0);
    check1("AUTHFAIL aparece sin flanco",   psw_authfail, 1'b1);

    auth = 1'b0; authfail = 1'b0;
    #1;
    check32("con la boveda en reposo el PSW vuelve a cero", psw, 32'h0000_0000);

    // ------------------------------------------------------------------------
    $display("[4] las seis causas, una por slot");
    // ------------------------------------------------------------------------

    malos = 0;
    for (i = 0; i < 5; i = i + 1) begin
      for (j = 0; j < 6; j = j + 1) begin
        reiniciar();
        falla_en(i, causas[j]);
        if (psw_exc !== 1'b1)        malos = malos + 1;
        if (psw_cause !== causas[j]) malos = malos + 1;
      end
    end
    check_int("5 slots x 6 causas encienden EXC con su causa", malos, 0);

    // Un caso explicito, para que quede a la vista
    reiniciar();
    falla_en(2, `CAUSE_MISALIGN);
    check1("EXC encendido por MISALIGN en S2", psw_exc, 1'b1);
    check3("CAUSE registra MISALIGN", psw_cause, `CAUSE_MISALIGN);

    // Sin fallas, EXC no se enciende solo
    reiniciar();
    pulso();
    pulso();
    check1("sin fallas EXC sigue apagado", psw_exc, 1'b0);

    // ------------------------------------------------------------------------
    $display("[5] prioridad entre slots");
    // ------------------------------------------------------------------------
    // Los diez pares. En cada uno los dos slots fallan con causas distintas y
    // tiene que quedar la del indice menor.

    malos = 0;
    for (i = 0; i < 5; i = i + 1) begin
      for (j = i + 1; j < 5; j = j + 1) begin
        reiniciar();
        sin_fallas();
        causa_i = causas[i];
        causa_j = causas[j];
        case (i)
          0: begin f0 = 1'b1; c0 = causa_i; end
          1: begin f1 = 1'b1; c1 = causa_i; end
          2: begin f2 = 1'b1; c2 = causa_i; end
          3: begin f3 = 1'b1; c3 = causa_i; end
          default: ;
        endcase
        case (j)
          1: begin f1 = 1'b1; c1 = causa_j; end
          2: begin f2 = 1'b1; c2 = causa_j; end
          3: begin f3 = 1'b1; c3 = causa_j; end
          4: begin f4 = 1'b1; c4 = causa_j; end
          default: ;
        endcase
        pulso();
        obtenida = psw_cause;
        sin_fallas();
        if (obtenida !== causa_i) begin
          malos = malos + 1;
          $display("         S%0d(%b) con S%0d(%b) dio %b",
                   i, causa_i, j, causa_j, obtenida);
        end
      end
    end
    check_int("los 10 pares de slots resuelven al indice menor", malos, 0);

    // Los cinco a la vez
    reiniciar();
    f0 = 1'b1; c0 = `CAUSE_ILLOP;
    f1 = 1'b1; c1 = `CAUSE_MISALIGN;
    f2 = 1'b1; c2 = `CAUSE_RANGE;
    f3 = 1'b1; c3 = `CAUSE_DENIED;
    f4 = 1'b1; c4 = `CAUSE_NOKEY;
    pulso();
    sin_fallas();
    check3("con los cinco fallando gana S0", psw_cause, `CAUSE_ILLOP);

    // ------------------------------------------------------------------------
    $display("[6] EXC y CAUSE se marcan una sola vez");
    // ------------------------------------------------------------------------

    reiniciar();
    falla_en(3, `CAUSE_NOKEY);
    check3("primera falla: NOKEY en S3", psw_cause, `CAUSE_NOKEY);

    falla_en(0, `CAUSE_ILLOP);
    check3("la segunda falla no cambia la causa", psw_cause, `CAUSE_NOKEY);
    check1("EXC sigue encendido", psw_exc, 1'b1);

    pulso();
    pulso();
    check3("y los ciclos sin falla tampoco la limpian",
           psw_cause, `CAUSE_NOKEY);

    reiniciar();
    check1("solo el reset apaga EXC",   psw_exc, 1'b0);
    check3("y limpia la causa",         psw_cause, `CAUSE_NONE);

    // ------------------------------------------------------------------------
    $display("[7] WCONF entre slots");
    // ------------------------------------------------------------------------
    // Los habilitadores son los reales del banco de registros, ya filtrados por
    // las fallas de cada unidad. El puerto que pierde es el de numero mayor.

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b1, 4'd5);
    esc(`WP_S1, 1'b1, 4'd5);
    #1;
    check1("S1 contra S0 al mismo registro levanta WCONF", wconf_any, 1'b1);
    pulso();
    check3("y la causa registrada es WCONF", psw_cause, `CAUSE_WCONF);

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b1, 4'd5);
    esc(`WP_S1, 1'b1, 4'd6);
    #1;
    check1("a registros distintos no hay conflicto", wconf_any, 1'b0);
    pulso();
    check1("y EXC no se enciende", psw_exc, 1'b0);

    reiniciar();
    sin_escrituras();
    esc(`WP_S1, 1'b1, 4'd7);
    esc(`WP_S2_RD, 1'b1, 4'd7);
    #1;
    check1("el destino de un load contra S1", wconf_any, 1'b1);

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b1, 4'd3);
    esc(`WP_S2_BASE, 1'b1, 4'd3);
    #1;
    check1("el postincremento de la LSU contra S0", wconf_any, 1'b1);

    reiniciar();
    sin_escrituras();
    esc(`WP_S2_RD, 1'b1, 4'd8);
    esc(`WP_S3_L, 1'b1, 4'd8);
    #1;
    check1("la mitad L del par contra la LSU", wconf_any, 1'b1);

    reiniciar();
    sin_escrituras();
    esc(`WP_S1, 1'b1, 4'd9);
    esc(`WP_S3_R, 1'b1, 4'd9);
    #1;
    check1("la mitad R del par contra S1", wconf_any, 1'b1);

    reiniciar();
    sin_escrituras();
    esc(`WP_S3_L, 1'b1, 4'd15);
    esc(`WP_S4_LINK, 1'b1, 4'd15);
    #1;
    check1("el enlace de JAL contra la mitad L del par", wconf_any, 1'b1);

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b1, 4'd15);
    esc(`WP_S4_LINK, 1'b1, 4'd15);
    #1;
    check1("el enlace de JAL contra S0 escribiendo R15", wconf_any, 1'b1);

    // ------------------------------------------------------------------------
    $display("[8] lo que NO es WCONF");
    // ------------------------------------------------------------------------
    // WCONF es una condicion ENTRE slots. Los dos puertos del slot S2 coinciden
    // en un LW.INC con rd == rbase, y el ISA ya define que gana el dato cargado;
    // no es falla. Lo mismo valdria para las dos mitades del par, que de todas
    // formas nunca pueden ser el mismo registro.

    reiniciar();
    sin_escrituras();
    esc(`WP_S2_RD,   1'b1, 4'd4);
    esc(`WP_S2_BASE, 1'b1, 4'd4);
    #1;
    check1("LW.INC con rd igual a rbase no es WCONF", wconf_any, 1'b0);
    pulso();
    check1("y no enciende EXC", psw_exc, 1'b0);

    reiniciar();
    sin_escrituras();
    esc(`WP_S3_L, 1'b1, 4'd6);
    esc(`WP_S3_R, 1'b1, 4'd6);
    #1;
    check1("las dos mitades del par al mismo registro tampoco",
           wconf_any, 1'b0);

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b0, 4'd5);       // habilitador apagado
    esc(`WP_S1, 1'b1, 4'd5);
    #1;
    check1("un puerto deshabilitado no entra en el conflicto",
           wconf_any, 1'b0);

    reiniciar();
    sin_escrituras();
    esc(`WP_S0, 1'b1, 4'd5);
    esc(`WP_S1, 1'b0, 4'd5);
    #1;
    check1("ni el de arriba cuando es el otro el apagado",
           wconf_any, 1'b0);

    reiniciar();
    sin_escrituras();
    #1;
    check1("sin ninguna escritura no hay conflicto", wconf_any, 1'b0);

    // ------------------------------------------------------------------------
    $display("[9] una falla de unidad le gana a un WCONF posterior");
    // ------------------------------------------------------------------------
    // La prioridad es por slot, no por tipo de causa: un ILLOP en S0 se reporta
    // antes que un conflicto que pierde S3.

    reiniciar();
    sin_escrituras();
    esc(`WP_S1,   1'b1, 4'd2);
    esc(`WP_S3_L, 1'b1, 4'd2);
    sin_fallas();
    f0 = 1'b1; c0 = `CAUSE_ILLOP;
    #1;
    check1("el conflicto esta presente", wconf_any, 1'b1);
    pulso();
    sin_fallas();
    check3("pero la causa registrada es la de S0", psw_cause,
           `CAUSE_ILLOP);

    // Y al revés: si el ILLOP es de S4, gana el WCONF de S3
    reiniciar();
    sin_escrituras();
    esc(`WP_S1,   1'b1, 4'd2);
    esc(`WP_S3_L, 1'b1, 4'd2);
    sin_fallas();
    f4 = 1'b1; c4 = `CAUSE_ILLOP;
    pulso();
    sin_fallas();
    check3("con el ILLOP en S4 gana el WCONF de S3", psw_cause,
           `CAUSE_WCONF);

    // ------------------------------------------------------------------------
    $display("[10] bits reservados");
    // ------------------------------------------------------------------------

    reiniciar();
    sin_escrituras();
    flags_we = 1'b1; flags = 4'b1111;
    auth = 1'b1; authfail = 1'b1;
    falla_en(0, `CAUSE_WCONF);
    flags_we = 1'b0;
    // Todo encendido: causa 110, EXC, AUTHFAIL, AUTH y las cuatro banderas
    check32("el PSW con todos sus campos en uno", psw, 32'h0000_037F);
    check_int("los bits 31:10 se leen como cero", psw_rsv, 0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
