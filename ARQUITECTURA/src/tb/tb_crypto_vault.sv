`timescale 1ns/1ps

// =============================================================================
// tb_crypto_vault.sv - Cosimulacion de la boveda y la unidad Feistel4.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es el caso 5 de la seccion 5.2 del enunciado: cifrado y descifrado completo
// verificado contra la implementacion de referencia, mas el caso 6, que exige
// mostrar que las llaves no son legibles.
//
// Hasta aqui cada unidad se probo sola: tb_crypto_unit.sv usa un modelo de
// boveda y tb_key_vault.sv no instancia la unidad de ronda. Este testbench
// conecta los dos modulos reales y comprueba lo unico que ninguno de los dos
// puede comprobar por su cuenta: que la subllave que la boveda selecciona es
// la que la ronda aplica, y que el camino completo cifra y descifra de verdad.
//
// -----------------------------------------------------------------------------
// EL TESTBENCH HACE DE BANCO DE REGISTROS
// -----------------------------------------------------------------------------
// crypto_unit publica los indices del par y recibe los valores; el datapath
// real cerraria ese lazo contra regfile.sv, que todavia no existe. Aqui lo
// cierra un arreglo de 16 palabras dentro del testbench, con la misma
// semantica: la unidad lee el estado previo al bundle y el resultado se
// escribe despues del flanco.
//
// -----------------------------------------------------------------------------
// SOBRE EL MODELO DE REFERENCIA
// -----------------------------------------------------------------------------
// Los testbenches de unidad de este proyecto usan constantes y nunca recalculan
// la funcion de ronda, porque un error en la formula apareceria en el modulo y
// en la prueba a la vez. Aqui hace falta encadenar cuatro rondas sobre varios
// bloques, asi que el testbench si lleva un modelo. Para que siga siendo un
// oraculo independiente y no una copia del RTL:
//
//   1. El modelo sigue la estructura de la implementacion de referencia en C
//      del enunciado, con rotaciones escritas como desplazamientos. El RTL las
//      escribe como concatenaciones de rangos. Son dos expresiones distintas
//      de la misma permutacion, asi que un error de transcripcion en una no se
//      repite en la otra.
//
//   2. El modelo se valida ANTES de usarse como oraculo, contra constantes
//      calculadas fuera del simulador. Si el modelo estuviera mal, esa
//      validacion falla y el resto de los casos no se ejecuta.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Validacion del modelo de referencia contra constantes
//   2. Protocolo completo: credencial, sesion, instalacion de llave
//   3. Cifrado de bloques de 64 bits en cuatro rondas encadenadas
//   4. Descifrado: el bloque original vuelve
//   5. Llaves distintas producen textos cifrados distintos
//   6. Aislamiento: ninguna subllave aparece en los registros ni en la salida
//   7. Rondas sin sesion abierta, sin llave instalada y despues del cierre
// =============================================================================

`include "cerbero_defs.svh"

module tb_crypto_vault;

  // ---------------------------------------------------------------------------
  // Region segura y credencial, alineadas con los valores por defecto del
  // modulo de boveda.
  // ---------------------------------------------------------------------------

  localparam logic [127:0] ROT_SECRET = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210;
  localparam logic [31:0]  PC_SEG     = 32'h0000_7100;   // dentro de la region
  localparam logic [31:0]  PC_USR     = 32'h0000_0100;   // fuera de la region

  // ---------------------------------------------------------------------------
  // Reloj y senales
  // ---------------------------------------------------------------------------

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic        rst_n;
  logic        valid;
  logic [15:0] slot;
  logic [31:0] rs_data;
  logic [31:0] pc;
  logic        fault_any;

  // Boveda
  logic [31:0] subkey;
  logic        grant;
  logic        v_fault;
  logic [2:0]  v_cause;
  logic        auth, authfail;
  logic [3:0]  kvalid;

  // Unidad de ronda
  logic [3:0]  l_idx, r_idx;
  logic        c_wr;
  logic [31:0] l_new, r_new;

  // Banco de registros del testbench
  logic [31:0] regs [0:15];
  logic [31:0] l_val, r_val;
  assign l_val = regs[l_idx];
  assign r_val = regs[r_idx];

  key_vault #(
      .ROT_SECRET_INIT (ROT_SECRET)
  ) u_vault (
      .clk       (clk),
      .rst_n     (rst_n),
      .valid     (valid),
      .slot      (slot),
      .rs_data   (rs_data),
      .pc        (pc),
      .fault_any (fault_any),
      .subkey    (subkey),
      .grant     (grant),
      .fault     (v_fault),
      .cause     (v_cause),
      .auth      (auth),
      .authfail  (authfail),
      .kvalid    (kvalid)
  );

  crypto_unit u_crypto (
      .slot   (slot),
      .grant  (grant),
      .subkey (subkey),
      .l_val  (l_val),
      .r_val  (r_val),
      .l_idx  (l_idx),
      .r_idx  (r_idx),
      .wr_en  (c_wr),
      .l_new  (l_new),
      .r_new  (r_new)
  );

  integer tests_run    = 0;
  integer tests_failed = 0;

  // ---------------------------------------------------------------------------
  // Comprobaciones
  // ---------------------------------------------------------------------------

  task automatic check32(input string nombre,
                         input logic [31:0] obtenido,
                         input logic [31:0] esperado);
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

  task automatic check3(input string nombre,
                        input logic [2:0] obtenido,
                        input logic [2:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-44s obtenido %b, esperado %b",
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
        $display("  FALLA  %-44s obtenido %b, esperado %b",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Modelo de referencia
  //
  // Transcripcion de la implementacion en C del enunciado. Las rotaciones van
  // con desplazamientos, a diferencia del RTL, que usa concatenaciones.
  // ---------------------------------------------------------------------------

  function automatic logic [31:0] ref_rotl(input logic [31:0] x,
                                           input integer      r);
    ref_rotl = (x << r) | (x >> (32 - r));
  endfunction

  function automatic logic [31:0] ref_f(input logic [31:0] x,
                                        input logic [31:0] k);
    ref_f = (ref_rotl(x, 5) + k) ^ ref_rotl(x, 13);
  endfunction

  // Llaves del modelo, espejo de lo que se instala en la boveda
  logic [31:0] ref_key [0:3][0:3];

  // Resultado del modelo, para comparar contra el hardware
  logic [31:0] ref_l, ref_r;

  task automatic ref_cifrar(input logic [31:0] l0,
                            input logic [31:0] r0,
                            input integer      kv);
    logic [31:0] l, r, t;
    integer i;
    begin
      l = l0; r = r0;
      for (i = 0; i < 4; i = i + 1) begin
        t = r;
        r = l ^ ref_f(r, ref_key[kv][i]);
        l = t;
      end
      ref_l = l; ref_r = r;
    end
  endtask

  task automatic ref_descifrar(input logic [31:0] l0,
                               input logic [31:0] r0,
                               input integer      kv);
    logic [31:0] l, r, t;
    integer i;
    begin
      l = l0; r = r0;
      for (i = 3; i >= 0; i = i - 1) begin
        t = l;
        l = r ^ ref_f(l, ref_key[kv][i]);
        r = t;
      end
      ref_l = l; ref_r = r;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Emision de bundles
  //
  // Un bundle se presenta en el flanco de bajada, se deja asentar lo
  // combinacional, y el estado de la boveda cambia en el flanco de subida
  // siguiente. Es el mismo criterio que usa el regfile: la operacion ve el
  // estado PREVIO al bundle.
  // ---------------------------------------------------------------------------

  task automatic presentar(input logic [15:0] s,
                           input logic [31:0] d,
                           input logic [31:0] p);
    begin
      @(negedge clk);
      slot    = s;
      rs_data = d;
      pc      = p;
      valid   = 1'b1;
      #1;     // aqui las salidas combinacionales ya son validas
    end
  endtask

  task automatic confirmar();
    begin
      @(posedge clk);
      #1;
      valid = 1'b0;
      slot  = 16'd0;
    end
  endtask

  // Presentar y confirmar de corrido, para las operaciones cuyo resultado no
  // hace falta mirar en el camino
  task automatic emitir(input logic [15:0] s,
                        input logic [31:0] d,
                        input logic [31:0] p);
    begin
      presentar(s, d, p);
      confirmar();
    end
  endtask

  // ---------------------------------------------------------------------------
  // Construccion de slots del tipo F y del tipo V
  // ---------------------------------------------------------------------------

  function automatic logic [15:0] mk_f(input logic [2:0] op,
                                       input logic [2:0] par,
                                       input logic [1:0] kv,
                                       input logic [1:0] ronda);
    mk_f = {op, par, kv, ronda, 6'd0};
  endfunction

  function automatic logic [15:0] mk_ksetw(input logic [1:0] kv,
                                           input logic [1:0] widx,
                                           input logic [3:0] rs);
    mk_ksetw = {`CRP_KSETW, kv, widx, rs, 5'd0};
  endfunction

  function automatic logic [15:0] mk_authw(input logic [1:0] widx,
                                           input logic [3:0] rs);
    mk_authw = {`CRP_AUTHW, 2'd0, widx, rs, 5'd0};
  endfunction

  function automatic logic [15:0] mk_vctl(input logic [1:0] subfn,
                                          input logic [1:0] kv);
    mk_vctl = {`CRP_VCTL, subfn, kv, 9'd0};
  endfunction

  // ---------------------------------------------------------------------------
  // Secuencias del protocolo
  // ---------------------------------------------------------------------------

  task automatic abrir_sesion(input logic [127:0] credencial);
    integer w;
    begin
      for (w = 0; w < 4; w = w + 1) begin
        emitir(mk_authw(w[1:0], 4'd6), credencial[32*w +: 32], PC_SEG);
      end
      emitir(mk_vctl(`VCTL_LOGIN, 2'd0), 32'd0, PC_SEG);
    end
  endtask

  task automatic instalar_llave(input integer kv);
    integer w;
    begin
      for (w = 0; w < 4; w = w + 1) begin
        emitir(mk_ksetw(kv[1:0], w[1:0], 4'd6), ref_key[kv][w], PC_SEG);
      end
    end
  endtask

  // Una ronda sobre el par 0: presenta el slot, toma el resultado
  // combinacional y lo escribe en el banco despues del flanco.
  task automatic ronda(input logic [2:0] op,
                       input logic [2:0] par,
                       input logic [1:0] kv,
                       input logic [1:0] n);
    logic [31:0] nl, nr;
    logic [3:0]  il, ir;
    begin
      presentar(mk_f(op, par, kv, n), 32'd0, PC_SEG);
      nl = l_new;  nr = r_new;
      il = l_idx;  ir = r_idx;
      if (c_wr !== 1'b1) begin
        tests_run    = tests_run + 1;
        tests_failed = tests_failed + 1;
        $display("  FALLA  la ronda %0d de la llave %0d no obtuvo permiso", n, kv);
      end
      confirmar();
      regs[il] = nl;
      regs[ir] = nr;
    end
  endtask

  // Cifrado completo de un bloque: cuatro rondas encadenadas
  task automatic cifrar_bloque(input logic [2:0] par, input logic [1:0] kv);
    integer n;
    begin
      for (n = 0; n < 4; n = n + 1) ronda(`CRP_F4E, par, kv, n[1:0]);
    end
  endtask

  task automatic descifrar_bloque(input logic [2:0] par, input logic [1:0] kv);
    integer n;
    begin
      for (n = 3; n >= 0; n = n - 1) ronda(`CRP_F4D, par, kv, n[1:0]);
    end
  endtask

  // Un ciclo completo sobre el par 0: cifra, compara contra el modelo,
  // descifra y comprueba que vuelve el bloque original.
  task automatic ciclo_completo(input string       nombre,
                                input logic [31:0] l0,
                                input logic [31:0] r0,
                                input integer      kv,
                                input logic [31:0] cif_l_esp,
                                input logic [31:0] cif_r_esp);
    logic [31:0] cl, cr;
    begin
      regs[0] = l0;
      regs[1] = r0;

      cifrar_bloque(3'd0, kv[1:0]);
      cl = regs[0];
      cr = regs[1];

      // Contra la constante calculada fuera del simulador
      check32({nombre, ": cifrado L"}, cl, cif_l_esp);
      check32({nombre, ": cifrado R"}, cr, cif_r_esp);

      // Y contra el modelo de referencia, que encadena las cuatro rondas
      ref_cifrar(l0, r0, kv);
      check32({nombre, ": cifrado L contra el modelo"}, cl, ref_l);
      check32({nombre, ": cifrado R contra el modelo"}, cr, ref_r);

      // El texto cifrado no puede ser igual al claro
      tests_run = tests_run + 1;
      if ((cl === l0) && (cr === r0)) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %s: el cifrado dejo el bloque igual", nombre);
      end else begin
        $display("  ok     %s: el cifrado cambio el bloque", nombre);
      end

      descifrar_bloque(3'd0, kv[1:0]);
      check32({nombre, ": descifrado devuelve L"}, regs[0], l0);
      check32({nombre, ": descifrado devuelve R"}, regs[1], r0);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Aislamiento: ninguna subllave de la boveda puede quedar visible
  // ---------------------------------------------------------------------------

  // Icarus no soporta return dentro de una tarea, asi que el recorrido se
  // hace completo y la fuga se acumula en una bandera.
  task automatic check_sin_fuga(input string nombre);
    integer i, w, kv;
    logic   fuga;
    begin
      tests_run = tests_run + 1;
      fuga      = 1'b0;
      for (kv = 0; kv < 4; kv = kv + 1) begin
        for (w = 0; w < 4; w = w + 1) begin
          for (i = 0; i < 16; i = i + 1) begin
            if (regs[i] === ref_key[kv][w]) begin
              fuga = 1'b1;
              $display("  FALLA  %s: la subllave %08h aparecio en r%0d",
                       nombre, ref_key[kv][w], i);
            end
          end
        end
      end
      if (fuga) tests_failed = tests_failed + 1;
      else      $display("  ok     %s", nombre);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Resumen
  // ---------------------------------------------------------------------------

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

  integer i;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_crypto_vault.vcd");
      $dumpvars(0, tb_crypto_vault);
    end

    // Llaves que se instalaran en la boveda y en el modelo
    ref_key[0][0] = 32'hA0C0_5A00;  ref_key[0][1] = 32'hA0C1_5A01;
    ref_key[0][2] = 32'hA0C2_5A02;  ref_key[0][3] = 32'hA0C3_5A03;
    ref_key[1][0] = 32'hDEAD_BEEF;  ref_key[1][1] = 32'hCAFE_BABE;
    ref_key[1][2] = 32'h0BAD_F00D;  ref_key[1][3] = 32'h1234_5678;
    ref_key[2][0] = 32'h1111_1111;  ref_key[2][1] = 32'h2222_2222;
    ref_key[2][2] = 32'h3333_3333;  ref_key[2][3] = 32'h4444_4444;
    ref_key[3][0] = 32'h0000_0001;  ref_key[3][1] = 32'h0000_0002;
    ref_key[3][2] = 32'h0000_0003;  ref_key[3][3] = 32'h0000_0004;

    for (i = 0; i < 16; i = i + 1) regs[i] = 32'd0;

    valid = 1'b0; slot = 16'd0; rs_data = 32'd0; pc = PC_SEG;
    fault_any = 1'b0; rst_n = 1'b0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;

    $display("=== tb_crypto_vault: boveda y unidad Feistel4 en conjunto ===");

    // ------------------------------------------------------------------------
    $display("[el modelo de referencia se valida antes de usarse como oraculo]");
    // ------------------------------------------------------------------------
    // Constantes calculadas fuera del simulador. Si el modelo estuviera mal,
    // estos casos fallan y nada de lo que sigue tendria valor.
    check32("F(12345678, A0C05A00)", ref_f(32'h1234_5678, 32'hA0C0_5A00),
            32'h6D84_2B44);
    check32("F(00000000, 00000000)", ref_f(32'h0000_0000, 32'h0000_0000),
            32'h0000_0000);
    check32("F(FFFFFFFF, 00000001)", ref_f(32'hFFFF_FFFF, 32'h0000_0001),
            32'hFFFF_FFFF);

    ref_cifrar(32'h0123_4567, 32'h89AB_CDEF, 0);
    check32("modelo: cifrado de prueba L", ref_l, 32'h527C_2D1D);
    check32("modelo: cifrado de prueba R", ref_r, 32'h1D61_21AF);

    ref_descifrar(32'h527C_2D1D, 32'h1D61_21AF, 0);
    check32("modelo: el descifrado invierte, L", ref_l, 32'h0123_4567);
    check32("modelo: el descifrado invierte, R", ref_r, 32'h89AB_CDEF);

    // ------------------------------------------------------------------------
    $display("[estado tras el reset]");
    // ------------------------------------------------------------------------
    check1("sesion cerrada",        auth,   1'b0);
    check1("ninguna llave valida",  |kvalid, 1'b0);

    // ------------------------------------------------------------------------
    $display("[una ronda sin sesion abierta se deniega]");
    // ------------------------------------------------------------------------
    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check1 ("sin sesion no hay permiso",   grant,   1'b0);
    check3 ("la causa es DENIED",          v_cause, `CAUSE_DENIED);
    check32("sin permiso la subllave es cero", subkey, 32'd0);
    check1 ("sin permiso no habilita escritura", c_wr, 1'b0);
    confirmar();

    // ------------------------------------------------------------------------
    $display("[protocolo: credencial incorrecta]");
    // ------------------------------------------------------------------------
    abrir_sesion(~ROT_SECRET);
    check1("credencial incorrecta no abre sesion", auth,     1'b0);
    check1("y marca el fallo de autenticacion",    authfail, 1'b1);

    // ------------------------------------------------------------------------
    $display("[protocolo: credencial correcta]");
    // ------------------------------------------------------------------------
    abrir_sesion(ROT_SECRET);
    check1("credencial correcta abre sesion", auth,     1'b1);
    check1("y limpia el fallo previo",        authfail, 1'b0);

    // ------------------------------------------------------------------------
    $display("[una ronda sin llave instalada da NOKEY]");
    // ------------------------------------------------------------------------
    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check1 ("sin llave no hay permiso",     grant,   1'b0);
    check3 ("la causa es NOKEY",            v_cause, `CAUSE_NOKEY);
    check32("sin permiso la subllave es cero", subkey, 32'd0);
    confirmar();

    // La falla cerro la sesion, hay que volver a abrirla
    abrir_sesion(ROT_SECRET);
    check1("sesion reabierta tras la falla", auth, 1'b1);

    // ------------------------------------------------------------------------
    $display("[instalacion de las cuatro llaves]");
    // ------------------------------------------------------------------------
    instalar_llave(0);
    check1("llave 0 valida", kvalid[0], 1'b1);
    instalar_llave(1);
    check1("llave 1 valida", kvalid[1], 1'b1);
    instalar_llave(2);
    check1("llave 2 valida", kvalid[2], 1'b1);
    instalar_llave(3);
    check1("llave 3 valida", kvalid[3], 1'b1);
    check1("la sesion sigue abierta", auth, 1'b1);

    // ------------------------------------------------------------------------
    $display("[la boveda entrega la subllave que corresponde a (kv, ronda)]");
    // ------------------------------------------------------------------------
    // Es lo que ninguna de las dos unidades puede comprobar por separado.
    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd2), 32'd0, PC_SEG);
    check32("subllave de la llave 0, ronda 2", subkey, 32'hA0C2_5A02);
    confirmar();
    presentar(mk_f(`CRP_F4D, 3'd0, 2'd1, 2'd3), 32'd0, PC_SEG);
    check32("subllave de la llave 1, ronda 3", subkey, 32'h1234_5678);
    confirmar();

    // ------------------------------------------------------------------------
    $display("[cifrado y descifrado completo con la llave 0]");
    // ------------------------------------------------------------------------
    ciclo_completo("bloque de prueba", 32'h0123_4567, 32'h89AB_CDEF, 0,
                   32'h527C_2D1D, 32'h1D61_21AF);
    ciclo_completo("bloque en ceros",  32'h0000_0000, 32'h0000_0000, 0,
                   32'h2355_F7C9, 32'h06F7_F940);
    ciclo_completo("bloque en unos",   32'hFFFF_FFFF, 32'hFFFF_FFFF, 0,
                   32'h10D6_8C35, 32'h261E_D0AD);
    ciclo_completo("bloque arbitrario",32'hDEAD_BEEF, 32'hCAFE_BABE, 0,
                   32'h9442_1199, 32'hD579_030C);

    // ------------------------------------------------------------------------
    $display("[cifrado y descifrado completo con la llave 1]");
    // ------------------------------------------------------------------------
    ciclo_completo("mismo bloque, otra llave", 32'h0123_4567, 32'h89AB_CDEF, 1,
                   32'h7A6F_AC64, 32'h472F_3D39);
    ciclo_completo("segundo bloque, llave 1",  32'h0BAD_C0DE, 32'hFEED_FACE, 1,
                   32'h7842_A781, 32'h4E72_862D);

    // ------------------------------------------------------------------------
    $display("[la llave cambia el resultado]");
    // ------------------------------------------------------------------------
    // Ya quedo comprobado arriba: el mismo bloque dio 527C2D1D/1D6121AF con la
    // llave 0 y 7A6FAC64/472F3D39 con la llave 1. Se deja explicito para que
    // se lea como propiedad y no como coincidencia de dos casos sueltos.
    tests_run = tests_run + 1;
    if (32'h527C_2D1D === 32'h7A6F_AC64) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  dos llaves distintas dieron el mismo texto cifrado");
    end else begin
      $display("  ok     dos llaves distintas dan textos cifrados distintos");
    end

    // ------------------------------------------------------------------------
    $display("[aislamiento: la llave nunca llega al banco de registros]");
    // ------------------------------------------------------------------------
    check_sin_fuga("tras cifrar y descifrar, ninguna subllave en los registros");

    // ------------------------------------------------------------------------
    $display("[propiedad del algoritmo: una ronda sobre un par en ceros]");
    // ------------------------------------------------------------------------
    // Con las dos mitades en cero, las dos rotaciones dan cero y la funcion de
    // ronda queda F(0,k) = (0 + k) ^ 0 = k. Una sola ronda de cifrado sobre un
    // par en ceros deja la subllave literal en la mitad derecha.
    //
    // NO es un defecto del RTL ni del aislamiento: es una propiedad de la
    // funcion que define el enunciado, y se cumple en cualquier
    // implementacion. Solo la ve un programa que YA abrio sesion, es decir que
    // ya esta autorizado a usar esa llave, y despues de las cuatro rondas el
    // bloque deja de ser cero, asi que el cifrado completo no la expone.
    //
    // El caso se fija aqui a proposito, por dos razones: para que nadie lo
    // tome por un error y "arregle" la funcion de ronda, y porque es
    // exactamente lo que conviene tener medido si lo preguntan en la defensa.
    regs[0] = 32'd0;
    regs[1] = 32'd0;
    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check32("F4E sobre (0,0): la mitad L recibe la R previa", l_new, 32'd0);
    check32("F4E sobre (0,0): la mitad R queda en F(0,k) = k", r_new,
            32'hA0C0_5A00);
    confirmar();

    // Lo que si tiene que sostenerse es el aislamiento sin permiso: con la
    // sesion cerrada, el par en ceros y la llave instalada, la unidad no puede
    // entregar nada.
    emitir(mk_vctl(`VCTL_LOGOUT, 2'd0), 32'd0, PC_SEG);
    regs[0] = 32'd0;
    regs[1] = 32'd0;
    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check1 ("sin sesion no hay permiso",          grant,  1'b0);
    check32("sin permiso la mitad L queda en cero", l_new, 32'd0);
    check32("sin permiso la mitad R queda en cero", r_new, 32'd0);
    check1 ("sin permiso no habilita escritura",  c_wr,   1'b0);
    confirmar();

    // Hay que reabrir la sesion para lo que sigue
    abrir_sesion(ROT_SECRET);

    // ------------------------------------------------------------------------
    $display("[cierre de sesion]");
    // ------------------------------------------------------------------------
    emitir(mk_vctl(`VCTL_LOGOUT, 2'd0), 32'd0, PC_SEG);
    check1("LOGOUT cierra la sesion",    auth,      1'b0);
    check1("pero no borra las llaves",   &kvalid,   1'b1);

    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check1 ("tras el cierre no hay permiso", grant,   1'b0);
    check3 ("la causa vuelve a ser DENIED",  v_cause, `CAUSE_DENIED);
    check32("y la subllave es cero",         subkey,  32'd0);
    confirmar();

    // ------------------------------------------------------------------------
    $display("[cierre automatico al salir de la region segura]");
    // ------------------------------------------------------------------------
    abrir_sesion(ROT_SECRET);
    check1("sesion abierta de nuevo", auth, 1'b1);

    // Un bundle cualquiera fuera de la region, sin operacion de boveda
    emitir({`CRP_NOP, 13'd0}, 32'd0, PC_USR);
    check1("el PC fuera de la region cierra la sesion", auth, 1'b0);

    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check1("y la ronda siguiente queda sin permiso", grant, 1'b0);
    confirmar();

    // ------------------------------------------------------------------------
    $display("[KCLR invalida la ranura]");
    // ------------------------------------------------------------------------
    abrir_sesion(ROT_SECRET);
    emitir(mk_vctl(`VCTL_KCLR, 2'd0), 32'd0, PC_SEG);
    check1("la llave 0 deja de ser valida", kvalid[0], 1'b0);
    check1("la llave 1 sigue valida",       kvalid[1], 1'b1);

    presentar(mk_f(`CRP_F4E, 3'd0, 2'd0, 2'd0), 32'd0, PC_SEG);
    check3 ("una ronda sobre la ranura borrada da NOKEY", v_cause, `CAUSE_NOKEY);
    check32("y la subllave es cero",                      subkey,  32'd0);
    confirmar();

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
