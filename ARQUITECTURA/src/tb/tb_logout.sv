`timescale 1ns/1ps

// =============================================================================
// tb_logout.sv - Que pasa con la boveda cuando el programa NO hace LOGOUT.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
//     make logout
//
// Es la pregunta directa: si una rutina abre sesion en la boveda y vuelve sin
// cerrarla, ¿queda el acceso abierto para el codigo que corra despues?
//
// La respuesta de CERBERO es que NO, y no porque el programa se porte bien
// sino porque el hardware no se lo permite. La sesion se cierra sola en el
// mismo flanco en que el PC abandona la region segura `[SEC_BASE, SEC_LIMIT]`,
// la ejecute quien la ejecute y haya o no un LOGOUT. Es el cierre automatico
// de isa.md 8.3.
//
// -----------------------------------------------------------------------------
// POR QUE ESTE TESTBENCH EXISTE APARTE
// -----------------------------------------------------------------------------
// La comprobacion ya estaba, dentro de `tb_ejemplos`, mezclada con dos
// programas mas. Eso bastaba para que la suite la corriera, y no bastaba para
// que alguien que viene a preguntar justo esto la encuentre: `make list` no la
// nombraba y no habia forma de correrla sola.
//
// Una propiedad de seguridad que no se puede enseñar en un comando es una
// propiedad que no esta demostrada para quien pregunta, aunque lo este para la
// suite. Por eso tiene nombre propio y sale en `make list`.
//
// -----------------------------------------------------------------------------
// LOS TRES CASOS, Y POR QUE HACEN FALTA LOS TRES
// -----------------------------------------------------------------------------
// Con solo el primero, un procesador que NUNCA abriera sesion pasaria la
// prueba. Los otros dos son los que descartan esa explicacion:
//
//   [1] La rutina se autentica DENTRO de la region. AUTH se enciende.
//       Prueba que la sesion de verdad se abre, y que el caso [2] no pasa
//       por un login que fallo.
//
//   [2] La rutina vuelve SIN LOGOUT. AUTH se apaga solo.
//       Es la pregunta del enunciado. El PC cruza la frontera y la sesion
//       muere con el.
//
//   [3] Ya fuera, el programa intenta una ronda Feistel4. Se anula con
//       DENIED y el PSW lo registra.
//       Prueba que el cierre no es cosmetico: la bandera baja Y el permiso
//       se retira de verdad.
//
// Y al final, el barrido de los 64 KB de memoria de datos: ninguna palabra de
// la llave instalada puede haber quedado visible.
//
// El programa es `tools/programas/sesion_sin_logout.s`, que toma tres fotos
// del PSW con MFPSW y las guarda en 0x300, 0x304 y 0x308.
// =============================================================================

`include "cerbero_defs.svh"

module tb_logout;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  localparam int N_BUNDLES = 2048;
  localparam int N_WORDS   = 16384;
  localparam int TOPE      = 2000;

  // Donde el programa deja las tres fotos del PSW
  localparam int W_FOTOS = 32'h0300 / 4;

  // La region segura que declara top.sv por omision
  localparam logic [`XLEN-1:0] SEC_BASE  = 32'h0000_7000;
  localparam logic [`XLEN-1:0] SEC_LIMIT = 32'h0000_7FFF;

  // La llave que instala el programa, para el barrido de fugas
  localparam logic [31:0] K0 = 32'h1111_1111;
  localparam logic [31:0] K1 = 32'h2222_2222;
  localparam logic [31:0] K2 = 32'h3333_3333;
  localparam logic [31:0] K3 = 32'h4444_4444;

  logic             halted;
  logic [`XLEN-1:0] psw;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`NREGS-1:0][`XLEN-1:0] regs;
  /* verilator lint_on UNUSEDSIGNAL */

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs)
  );

  // ---------------------------------------------------------------------------
  // Observacion de la sesion mientras corre
  // ---------------------------------------------------------------------------
  // No basta con mirar el PSW al final: lo que se quiere demostrar es CUANDO
  // sube y cuando baja AUTH, y con que PC. Se anota el primer flanco de cada
  // sentido junto al PC del bundle que lo provoco.

  logic             auth_previo = 1'b0;
  integer           ciclo       = 0;
  integer           ciclo_sube  = -1;
  integer           ciclo_baja  = -1;
  logic [`XLEN-1:0] pc_sube     = '0;
  logic [`XLEN-1:0] pc_baja     = '0;
  logic             hubo_sesion = 1'b0;

  // El PC del bundle que esta en decodificacion, que es donde la boveda
  // compara contra la region segura
  wire [`XLEN-1:0] pc_id = dut.u_if_id.pc_out;

  always @(posedge clk) begin
    if (rst_n) begin
      ciclo <= ciclo + 1;
      if (psw[`PSW_AUTH] && !auth_previo) begin
        hubo_sesion <= 1'b1;
        if (ciclo_sube < 0) begin
          ciclo_sube <= ciclo;
          pc_sube    <= pc_id;
        end
      end
      if (!psw[`PSW_AUTH] && auth_previo && ciclo_baja < 0) begin
        ciclo_baja <= ciclo;
        pc_baja    <= pc_id;
      end
      auth_previo <= psw[`PSW_AUTH];
    end
  end

  // ---------------------------------------------------------------------------
  // Comprobaciones
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
        $display("  FALLA  %-50s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-50s %08h", nombre, obtenido);
      end
    end
  endtask

  task automatic check(input string nombre, input logic condicion);
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

  task automatic check_int(input string  nombre,
                           input integer obtenido,
                           input integer esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-50s obtenido %0d, esperado %0d",
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

  integer i, c, malos;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_logout.vcd");
      $dumpvars(0, tb_logout);
    end

    rst_n = 1'b0;
    #1;
    $readmemh("../../tools/programas/sesion_sin_logout.hex", dut.u_imem.storage);

    $display("=== tb_logout: la boveda cuando el programa NO hace LOGOUT ===");
    $display("");

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    c = 0;
    while (!halted && c < TOPE) begin
      @(posedge clk);
      c = c + 1;
    end
    $display("  (el programa corrio %0d ciclos)", c);
    $display("");

    check("el programa llego a HALT y no se colgo", halted);

    // ------------------------------------------------------------------------
    $display("");
    $display("[1] la rutina SI abre sesion, dentro de la region segura");
    // ------------------------------------------------------------------------
    // Sin esto, un procesador que jamas encendiera AUTH pasaria el caso [2]
    // por la razon equivocada.

    check("AUTH se encendio en algun momento", hubo_sesion);
    check_int("y se encendio en un ciclo concreto", ciclo_sube >= 0, 1);
    $display("         subio en el ciclo %0d, con el PC en 0x%08h",
             ciclo_sube, pc_sube);
    check("el PC estaba DENTRO de [0x7000, 0x7FFF] al abrirla",
          (pc_sube >= SEC_BASE) && (pc_sube <= SEC_LIMIT));
    check32("foto 1: AUTH = 1 estando dentro",
            dut.u_dmem.storage[W_FOTOS + 0], 32'h0000_0010);

    // ------------------------------------------------------------------------
    $display("");
    $display("[2] la rutina vuelve SIN LOGOUT y la sesion se cierra sola");
    // ------------------------------------------------------------------------
    // Esta es la pregunta. El programa no ejecuta ni un LOGOUT: lo unico que
    // hace es saltar de vuelta, y eso basta.

    check_int("AUTH volvio a cero", ciclo_baja >= 0, 1);
    $display("         bajo en el ciclo %0d, con el PC en 0x%08h",
             ciclo_baja, pc_baja);
    check("el PC estaba FUERA de la region al cerrarse",
          (pc_baja < SEC_BASE) || (pc_baja > SEC_LIMIT));
    check("y se cerro despues de haberse abierto, no antes",
          ciclo_baja > ciclo_sube);
    check32("foto 2: AUTH = 0 ya afuera, sin haber ejecutado LOGOUT",
            dut.u_dmem.storage[W_FOTOS + 1], 32'h0000_0000);
    check("AUTH sigue en cero al terminar", psw[`PSW_AUTH] === 1'b0);

    // ------------------------------------------------------------------------
    $display("");
    $display("[3] el cierre no es cosmetico: el permiso se retiro de verdad");
    // ------------------------------------------------------------------------
    // Una bandera apagada no demuestra nada por si sola. Lo que lo demuestra
    // es que una operacion privilegiada intentada despues se ANULA.

    check32("foto 3: la ronda de afuera se anulo con DENIED",
            dut.u_dmem.storage[W_FOTOS + 2], 32'h0000_0240);
    check("el PSW final trae EXC encendido", psw[`PSW_EXC] === 1'b1);
    check_int("y la causa registrada es DENIED",
              psw[`PSW_CAUSE], `CAUSE_DENIED);

    // ------------------------------------------------------------------------
    $display("");
    $display("[4] y la llave no quedo a la vista en ninguna parte");
    // ------------------------------------------------------------------------

    malos = 0;
    for (i = 0; i < N_WORDS; i = i + 1)
      if (dut.u_dmem.storage[i] === K0 || dut.u_dmem.storage[i] === K1 ||
          dut.u_dmem.storage[i] === K2 || dut.u_dmem.storage[i] === K3)
        malos = malos + 1;
    check_int("ninguna subllave aparece en los 64 KB de datos", malos, 0);

    malos = 0;
    for (i = 0; i < `NREGS; i = i + 1)
      if (regs[i] === K0 || regs[i] === K1 ||
          regs[i] === K2 || regs[i] === K3)
        malos = malos + 1;
    check_int("ni en ninguno de los 16 registros", malos, 0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("");
    $display("  [autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'd0, 32'd1);
`endif

    $display("");
    resumen();
  end

endmodule
