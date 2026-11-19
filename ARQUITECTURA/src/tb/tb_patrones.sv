`timescale 1ns/1ps

// =============================================================================
// tb_patrones.sv - Los tres patrones de acceso que pide la Iteracion 5
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// La seccion 7.1.5 del enunciado pide evaluar el sistema con benchmarks de
// distintos patrones de acceso a memoria: secuencial, aleatorio y stride. Este
// testbench corre los tres en paralelo y comprueba sus CONTADORES, no solo sus
// datos.
//
// Dos de los tres tienen oraculo exacto, calculable sin simular:
//
//   secuencial  paso de 4 B sobre 1024 palabras. Una linea son 8 palabras, asi
//               que la primera de cada linea falla y las siete siguientes
//               aciertan: 1024/8 = 128 fallos y 896 aciertos, 87.5 % exacto.
//
//   stride      paso de 32 B, que es justo el tamano de linea. Cada acceso cae
//               en una linea nueva y no se repite ninguna, asi que NINGUNA
//               cache de ningun tamano puede acertar: 1024 fallos, 0 aciertos.
//
//   aleatorio   no tiene oraculo exacto, porque depende de cuantas lineas
//               repite el generador y de cuales siguen cacheadas. Lo que si se
//               puede fijar son cotas: tiene que acertar MAS que el stride
//               (repite por casualidad) y MENOS que el secuencial (no tiene
//               localidad espacial). Eso es lo que se comprueba.
//
// Los tres hacen exactamente 1024 lecturas, asi que la cuenta de accesos es la
// misma y cualquier diferencia es atribuible al patron.
// =============================================================================

`include "cerbero_defs.svh"

module tb_patrones;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;

  // El stride paga 1024 fallos hasta memoria principal: unos 73 000 ciclos.
  localparam int TOPE = 120000;

  // Lo que cada programa tiene que hacer, por construccion
  localparam int N_ACCESOS = 1024;
  localparam int SEC_FALLOS   = 128;   // 1024 / 8 palabras por linea
  localparam int SEC_ACIERTOS = 896;   // 1024 - 128
  localparam int STR_FALLOS   = 1024;  // una linea nueva cada vez
  localparam int STR_ACIERTOS = 0;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic hs, ha, hr;                       // halted de cada uno
  /* verilator lint_off UNUSEDSIGNAL */
  logic [`XLEN-1:0] ps, pa, pr;
  logic [`NREGS-1:0][`XLEN-1:0] rs, ra, rr;
  /* verilator lint_on UNUSEDSIGNAL */

  logic [31:0] s_ldh, s_ldm, s_sth, s_stm;
  logic [31:0] a_ldh, a_ldm, a_sth, a_stm;
  logic [31:0] r_ldh, r_ldm, r_sth, r_stm;
  logic [31:0] s_mem_acc, a_mem_acc, r_mem_acc;
  logic [31:0] s_inv, a_inv, r_inv;
  logic        s_dren, a_dren, r_dren;

  top #(.NUM_BUNDLES (N_BUNDLES), .NUM_WORDS (N_WORDS), .RESET_PC (32'h0))
  sec (
      .clk (clk), .rst_n (rst_n), .halted (hs), .psw (ps), .dbg_regs (rs),
      .perf_l1_load_hit (s_ldh), .perf_l1_load_miss (s_ldm),
      .perf_l1_store_hit (s_sth), .perf_l1_store_miss (s_stm),
      .perf_mem_accesos (s_mem_acc), .perf_inv_ejecutadas (s_inv),
      .mem_drenada (s_dren)
  );

  top #(.NUM_BUNDLES (N_BUNDLES), .NUM_WORDS (N_WORDS), .RESET_PC (32'h0))
  ale (
      .clk (clk), .rst_n (rst_n), .halted (ha), .psw (pa), .dbg_regs (ra),
      .perf_l1_load_hit (a_ldh), .perf_l1_load_miss (a_ldm),
      .perf_l1_store_hit (a_sth), .perf_l1_store_miss (a_stm),
      .perf_mem_accesos (a_mem_acc), .perf_inv_ejecutadas (a_inv),
      .mem_drenada (a_dren)
  );

  top #(.NUM_BUNDLES (N_BUNDLES), .NUM_WORDS (N_WORDS), .RESET_PC (32'h0))
  str (
      .clk (clk), .rst_n (rst_n), .halted (hr), .psw (pr), .dbg_regs (rr),
      .perf_l1_load_hit (r_ldh), .perf_l1_load_miss (r_ldm),
      .perf_l1_store_hit (r_sth), .perf_l1_store_miss (r_stm),
      .perf_mem_accesos (r_mem_acc), .perf_inv_ejecutadas (r_inv),
      .mem_drenada (r_dren)
  );

  // ---------------------------------------------------------------------------
  // Marcador
  // ---------------------------------------------------------------------------

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

  task automatic check1(input string nombre, input logic obtenido);
    begin
      tests_run++;
      if (obtenido !== 1'b1) begin
        tests_failed++;
        $display("  FALLA  %-50s no se cumplio", nombre);
      end
      else $display("  ok     %s", nombre);
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

  int c;
  real tasa_sec, tasa_ale, tasa_str;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_patrones.vcd");
      $dumpvars(0, tb_patrones);
    end

    $readmemh("../../tools/programas/patron_secuencial.hex", sec.u_imem.storage);
    $readmemh("../../tools/programas/patron_aleatorio.hex",  ale.u_imem.storage);
    $readmemh("../../tools/programas/patron_stride.hex",     str.u_imem.storage);

    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    @(negedge clk) rst_n = 1'b1;

    $display("");
    $display("=== tb_patrones: secuencial, aleatorio y stride ===");
    $display("    los tres hacen %0d lecturas sobre la misma jerarquia", N_ACCESOS);

    c = 0;
    while (!(hs && ha && hr) && c < TOPE) begin
      @(posedge clk);
      c++;
    end
    repeat (8) @(posedge clk);

    c = 0;
    while (!(s_dren && a_dren && r_dren) && c < 200000) begin
      @(posedge clk);
      c++;
    end
    #1;

    check1("los tres programas llegaron a HALT", hs && ha && hr);
    check1("y ninguno registro fallas",
           !ps[`PSW_EXC] && !pa[`PSW_EXC] && !pr[`PSW_EXC]);

    // ------------------------------------------------------------------------
    $display("");
    $display("[1] secuencial: localidad espacial perfecta");
    // ------------------------------------------------------------------------
    // Paso de 4 B. Un fallo trae 8 palabras, asi que sirve para 8 accesos.
    check("hizo las 1024 lecturas", s_ldh + s_ldm, N_ACCESOS);
    check("fallos = 1024/8, uno por linea",  s_ldm, SEC_FALLOS);
    check("aciertos = las otras siete de cada linea", s_ldh, SEC_ACIERTOS);
    check("ningun acierto de escritura (no-write-allocate)", s_sth, 0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] stride de una linea: localidad espacial nula");
    // ------------------------------------------------------------------------
    // Paso de 32 B, el tamano de linea. Cada acceso estrena linea y no se
    // repite ninguna: no hay cache que pueda acertar.
    check("hizo las 1024 lecturas", r_ldh + r_ldm, N_ACCESOS);
    check("fallo las 1024 veces",   r_ldm, STR_FALLOS);
    check("y no acerto ni una vez", r_ldh, STR_ACIERTOS);

    // Y como son 1024 lineas distintas, 32 KB, tampoco caben en la L2 de
    // 16 KB: los 1024 fallos llegan hasta memoria principal.
    check1("sus fallos llegaron a memoria principal",
           r_mem_acc >= STR_FALLOS);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] aleatorio: queda entre los dos, y por que");
    // ------------------------------------------------------------------------
    // No tiene oraculo exacto, pero si cotas que no pueden fallar:
    //   - acierta MAS que el stride, porque repite lineas por casualidad
    //   - acierta MENOS que el secuencial, porque no tiene localidad espacial
    check("hizo las 1024 lecturas", a_ldh + a_ldm, N_ACCESOS);
    check1("acerto mas que el stride",      a_ldh > r_ldh);
    check1("y menos que el secuencial",     a_ldh < s_ldh);

    // Recorre la misma region de 32 KB que el stride, al azar. Por el problema
    // del cumpleanos, 1024 tiradas sobre 1024 lineas tocan unas
    // 1024 x (1 - 1/e) = 647 distintas. Se comprueba contra esa prediccion con
    // holgura amplia, que es lo que confirma que el generador dispersa de
    // verdad y no se queda en un ciclo corto.
    check1("toco cerca de 647 lineas distintas, como predice la teoria",
           (a_mem_acc > 550) && (a_mem_acc < 750));

    // Y toca menos lineas que el stride, que las visita todas
    check1("pero menos lineas que el stride, que las recorre todas",
           a_mem_acc < r_mem_acc);

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] el orden de los tres es el que la teoria predice");
    // ------------------------------------------------------------------------
    tasa_sec = 100.0 * s_ldh / (s_ldh + s_ldm);
    tasa_ale = 100.0 * a_ldh / (a_ldh + a_ldm);
    tasa_str = 100.0 * r_ldh / (r_ldh + r_ldm);

    $display("    secuencial %6.2f %%   aleatorio %6.2f %%   stride %6.2f %%",
             tasa_sec, tasa_ale, tasa_str);
    check1("secuencial > aleatorio > stride", (tasa_sec > tasa_ale) &&
                                              (tasa_ale > tasa_str));

    // ------------------------------------------------------------------------
    $display("");
    $display("[5] cuanto cuesta la politica inclusiva (seccion 5.2)");
    // ------------------------------------------------------------------------
    // El enunciado exige contar las invalidaciones hacia atras cuando la
    // politica es inclusiva, para cuantificar su costo sobre el hit rate de
    // L1-D. Con L2 de 512 lineas contra L1 de 128, la L2 rara vez expulsa algo
    // que L1 todavia tenga, asi que el costo deberia ser bajo.
    $display("    invalidaciones ejecutadas: sec %0d, ale %0d, str %0d",
             s_inv, a_inv, r_inv);
    check1("el costo de la inclusion es bajo en los tres",
           (s_inv + a_inv + r_inv) < (N_ACCESOS / 4));

`ifdef FORCE_FAIL
    check("caso inyectado a proposito", tests_run, -1);
`endif

    $display("");
    resumen();
  end

endmodule
