`timescale 1ns/1ps

// =============================================================================
// tb_fetch_flow.sv - Busqueda y saltos con la memoria y la BRU de verdad.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Conecta fetch.sv, imem.sv, reg_if_id.sv y bru.sv como van en el procesador,
// corre un programa corto de saltos y registra que PC llega a decodificacion
// en cada ciclo. Comprueba lo que ningun testbench unitario puede ver: que los
// cuatro modulos juntos dan exactamente un delay slot, sin bundles de mas ni
// de menos, y que HALT deja ejecutar el suyo y despues apaga el flujo.
//
// El programa solo usa el slot S4; los otros cuatro van en cero, que es la
// operacion nula en todos. Se escribe directo en la memoria por referencia
// jerarquica para no depender de un archivo con ruta relativa.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// PROGRAMA (indice de bundle, direccion, slot S4)
// -----------------------------------------------------------------------------
//    0  0x000  nop
//    1  0x010  br.al  +2        destino 0x010 + 16*3 = 0x040 (bundle 4)
//    2  0x020  nop              delay slot, se ejecuta
//    3  0x030  halt             saltado: si llega a ID, el salto fallo
//    4  0x040  br.eq  +5        Z = 0, no se toma
//    5  0x050  jr.al  r3        R3 = 0x0A7, desalineado: destino 0x0A0
//    6  0x060  nop              delay slot
//    7  0x070  halt             saltado
//    8  0x080  halt             saltado: aqui caeria un JR sin alinear a medias
//    9  0x090  halt             saltado
//   10  0x0A0  jal.al +1        destino 0x0A0 + 16*2 = 0x0C0 (bundle 12)
//   11  0x0B0  nop              delay slot
//   12  0x0C0  halt
//   13  0x0D0  br.al  -14       delay slot de HALT: llega valido, pero el
//                               salto a 0x000 ya no se busca
//   14  0x0E0  halt             nunca se busca
// =============================================================================

`include "cerbero_defs.svh"

module tb_fetch_flow;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // ---- Busqueda --------------------------------------------------------------
  logic                 taken;
  logic [`XLEN-1:0]     target;
  logic                 halt;
  logic [`XLEN-1:0]     fetch_pc;
  logic                 fetch_valid;
  logic                 halted;

  // ---- Decodificacion --------------------------------------------------------
  logic [`BUNDLE_W-1:0] bundle;
  logic                 id_valid;
  logic [`XLEN-1:0]     id_pc;

  // ---- Lo que la BRU entrega y este arnes no usa -----------------------------
  /* verilator lint_off UNUSEDSIGNAL */
  logic [3:0]           rs_idx;
  logic                 link_we;
  logic [3:0]           link_idx;
  logic [`XLEN-1:0]     link_val;
  logic                 bru_fault;
  logic [2:0]           bru_cause;
  /* verilator lint_on UNUSEDSIGNAL */

  // Valor de R3 para el JR, sin multiplexar: el programa solo lee R3
  localparam logic [`XLEN-1:0] R3_VAL = 32'h0000_00A7;

  fetch u_fetch (
      .clk    (clk),
      .rst_n  (rst_n),
      .taken  (taken),
      .target (target),
      .halt   (halt),
      .pc     (fetch_pc),
      .valid  (fetch_valid),
      .halted (halted)
  );

  imem #(.NUM_BUNDLES(64)) u_imem (
      .clk    (clk),
      .addr   (fetch_pc),
      .bundle (bundle)
  );

  reg_if_id u_if_id (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid_in  (fetch_valid),
      .pc_in     (fetch_pc),
      .valid_out (id_valid),
      .pc_out    (id_pc)
  );

  bru u_bru (
      .slot      (bundle[`SLOT_S4]),
      .valid     (id_valid),
      .pc        (id_pc),
      .flag_z    (1'b0),
      .flag_n    (1'b0),
      .flag_c    (1'b0),
      .flag_v    (1'b0),
      .flag_auth (1'b0),
      .rs_idx    (rs_idx),
      .rs_val    (R3_VAL),
      .taken     (taken),
      .target    (target),
      .link_we   (link_we),
      .link_idx  (link_idx),
      .link_val  (link_val),
      .halt      (halt),
      .fault     (bru_fault),
      .cause     (bru_cause)
  );

  // ---------------------------------------------------------------------------
  // Codificacion del slot S4 (isa.md 2.5)
  // ---------------------------------------------------------------------------

  function automatic logic [15:0] s4_c(input logic [2:0] op,
                                       input logic [2:0] cond,
                                       input integer     desp);
    logic [9:0] d;
    d = desp[9:0];
    return {op, cond, d};
  endfunction

  function automatic logic [15:0] s4_j(input logic [2:0] op,
                                       input logic [2:0] cond,
                                       input logic [3:0] rs);
    return {op, cond, 1'b0, rs, 5'b00000};
  endfunction

  localparam logic [15:0] NOP  = 16'h0000;
  localparam logic [15:0] HALT = {`BRU_HALT, 13'b0};

  task automatic cargar(input integer idx, input logic [15:0] s4);
    begin
      u_imem.storage[idx] = {112'b0, s4};
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verificacion
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
        $display("  FALLA  %-46s obtenido %08h, esperado %08h",
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
  // Secuencia
  // ---------------------------------------------------------------------------

  // Bundles que deben llegar validos a decodificacion, en orden
  localparam int N_ESP = 10;
  logic [`XLEN-1:0] esperado [0:N_ESP-1];

  // Lo que de verdad llego. Holgura de sobra por si llegan bundles de mas.
  localparam int MAX_TRAZA = 32;
  logic [`XLEN-1:0] traza [0:MAX_TRAZA-1];
  integer n_traza;
  integer ciclo, ciclos_detenido, i;
  logic   halted_visto;
  logic [`XLEN-1:0] pc_congelado;

  // Segundo programa: un salto DENTRO del delay slot de otro salto
  localparam int N_ESP2 = 6;
  logic [`XLEN-1:0] esperado2 [0:N_ESP2-1];
  logic [`XLEN-1:0] traza2 [0:MAX_TRAZA-1];
  integer n_traza2;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_fetch_flow.vcd");
      $dumpvars(0, tb_fetch_flow);
    end

    rst_n = 1'b0;

    // El barrido a cero de imem.sv corre en su propio initial en el tiempo 0.
    // Se espera un paso para no competir con el.
    #1;
    cargar( 0, NOP);
    cargar( 1, s4_c(`BRU_BR,  `COND_AL,  2));
    cargar( 2, NOP);
    cargar( 3, HALT);
    cargar( 4, s4_c(`BRU_BR,  `COND_EQ,  5));
    cargar( 5, s4_j(`BRU_JR,  `COND_AL,  4'd3));
    cargar( 6, NOP);
    cargar( 7, HALT);
    cargar( 8, HALT);
    cargar( 9, HALT);
    cargar(10, s4_c(`BRU_JAL, `COND_AL,  1));
    cargar(11, NOP);
    cargar(12, HALT);
    cargar(13, s4_c(`BRU_BR,  `COND_AL, -14));
    cargar(14, HALT);

    esperado[ 0] = 32'h000;
    esperado[ 1] = 32'h010;
    esperado[ 2] = 32'h020;
    esperado[ 3] = 32'h040;
    esperado[ 4] = 32'h050;
    esperado[ 5] = 32'h060;
    esperado[ 6] = 32'h0A0;
    esperado[ 7] = 32'h0B0;
    esperado[ 8] = 32'h0C0;
    esperado[ 9] = 32'h0D0;

    $display("=== tb_fetch_flow: busqueda, delay slot y HALT ===");

    // Reset de dos flancos y liberacion en un flanco de bajada
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Se muestrea en el flanco de bajada, con todo estable. Se corre hasta
    // bastante despues de HALT para ver que no llega nada mas.
    n_traza         = 0;
    ciclos_detenido = 0;
    halted_visto    = 1'b0;
    pc_congelado    = '0;
    for (ciclo = 0; ciclo < 30; ciclo = ciclo + 1) begin
      @(negedge clk);
      if (id_valid) begin
        if (n_traza < MAX_TRAZA) traza[n_traza] = id_pc;
        n_traza = n_traza + 1;
      end
      if (halted) begin
        if (!halted_visto) pc_congelado = fetch_pc;
        else if (fetch_pc !== pc_congelado) ciclos_detenido = -1000;
        halted_visto = 1'b1;
        if (ciclos_detenido >= 0) ciclos_detenido = ciclos_detenido + 1;
      end
    end

    // ------------------------------------------------------------------------
    $display("[1] secuencia de bundles en decodificacion");
    // ------------------------------------------------------------------------

    check_int("cantidad de bundles validos", n_traza, N_ESP);
    for (i = 0; i < N_ESP; i = i + 1) begin
      if (i < n_traza)
        check32($sformatf("bundle valido %0d", i), traza[i], esperado[i]);
    end

    // ------------------------------------------------------------------------
    $display("[2] HALT");
    // ------------------------------------------------------------------------

    check1 ("la busqueda quedo detenida", halted, 1'b1);
    check1 ("valid apagado en la busqueda", fetch_valid, 1'b0);
    check1 ("valid apagado en decodificacion", id_valid, 1'b0);
    check32("el PC se congela en el delay slot de HALT",
            pc_congelado, 32'h0000_00D0);
    check1 ("y no se movio mientras estuvo detenido",
            ciclos_detenido > 0, 1'b1);

    // ------------------------------------------------------------------------
    $display("[3] un salto dentro del delay slot de otro salto");
    // ------------------------------------------------------------------------
    // El ISA dice que despues de todo salto se ejecuta exactamente un bundle,
    // pero no dice que puede haber EN ese bundle. Si trae otro salto, esto es
    // lo que el hardware hace, y conviene tenerlo medido y no deducido:
    //
    //    1  0x010  br.al +5   destino 0x010 + 16*6 = 0x070
    //    2  0x020  br.al +0   delay slot del primero, y a su vez salto:
    //                         destino 0x020 + 16*1 = 0x030
    //
    // Los dos saltos surten efecto, encadenados. El bundle 0x070, que era el
    // destino del primero, acaba siendo el DELAY SLOT del segundo: se ejecuta
    // una sola vez y despues el control cae en 0x030.
    //
    // Es comportamiento definido y reproducible, pero casi seguro no es lo que
    // pretende quien escribe el codigo: el destino del primer salto corre un
    // bundle y se abandona. Por eso la v1.2 del ISA prohibe la combinacion en
    // vez de documentarla como una tecnica. Este caso existe para que, si
    // alguien la usa de todas formas, al menos el hardware no cambie de opinion
    // en silencio.

    rst_n = 1'b0;
    @(negedge clk);

    cargar( 0, NOP);
    cargar( 1, s4_c(`BRU_BR, `COND_AL,  5));
    cargar( 2, s4_c(`BRU_BR, `COND_AL,  0));
    for (i = 3; i < 16; i = i + 1) cargar(i, NOP);

    esperado2[0] = 32'h000;
    esperado2[1] = 32'h010;
    esperado2[2] = 32'h020;   // delay slot del primer salto, y salto el mismo
    esperado2[3] = 32'h070;   // destino del primero, usado como delay slot
    esperado2[4] = 32'h030;   // destino del segundo
    esperado2[5] = 32'h040;   // y sigue el flujo contiguo

    @(negedge clk);
    rst_n = 1'b1;

    n_traza2 = 0;
    for (ciclo = 0; ciclo < N_ESP2; ciclo = ciclo + 1) begin
      @(negedge clk);
      if (id_valid) begin
        traza2[n_traza2] = id_pc;
        n_traza2 = n_traza2 + 1;
      end
    end

    check_int("los dos saltos encadenados dan 6 bundles validos",
              n_traza2, N_ESP2);
    for (i = 0; i < N_ESP2; i = i + 1) begin
      if (i < n_traza2)
        check32($sformatf("encadenado %0d", i), traza2[i], esperado2[i]);
    end

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", n_traza, N_ESP + 1);
`endif

    resumen();
  end

endmodule
