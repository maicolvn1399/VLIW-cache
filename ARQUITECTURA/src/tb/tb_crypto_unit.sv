`timescale 1ns/1ps

// =============================================================================
// tb_crypto_unit.sv - Testbench de la unidad Feistel4.
//
// SystemVerilog plano: Icarus 13.0 no soporta clases, restricciones ni
// aleatorizacion, asi que los casos son tareas con valores esperados
// explicitos y un contador de errores.
//
// 🚫 Los valores esperados son CONSTANTES, calculadas fuera del simulador y
// tomadas de la seccion 5 de docs/spec-crypto-unit.md. El testbench nunca
// recalcula la funcion de ronda. Si lo hiciera, un error en la formula
// apareceria en el modulo y en la prueba a la vez, y el caso pasaria.
//
// No hay reloj ni reset: la unidad es combinacional, asi que los casos
// avanzan con retardos simples. Por eso tampoco aplica la carrera de flancos
// que hubo que resolver en el testbench de la LSU.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto, para comprobar que el arnes sabe reportar una
// falla en lugar de pasar siempre por construccion.
// =============================================================================

module tb_crypto_unit;

  // Opcodes del slot S3 (isa.md 5)
  localparam logic [2:0] OP_F4E = 3'b001;
  localparam logic [2:0] OP_F4D = 3'b010;

  // --- interfaz del DUT ---
  logic [15:0] slot;
  logic        grant;
  logic [31:0] subkey;
  logic [31:0] l_val;
  logic [31:0] r_val;
  logic [3:0]  l_idx;
  logic [3:0]  r_idx;
  logic        wr_en;
  logic [31:0] l_new;
  logic [31:0] r_new;

  // --- control del modelo de boveda ---
  logic grant_in;
  logic gate_subkey;

  // --- contadores ---
  int tests_run;
  int tests_failed;

  // --- estado para el encadenamiento de rondas ---
  logic [31:0] cl;
  logic [31:0] cr;
  logic [1:0]  rsel;

  // ---------------------------------------------------------------------------
  // Instancias
  // ---------------------------------------------------------------------------

  crypto_unit dut (
      .slot   (slot),
      .grant  (grant),
      .subkey (subkey),
      .l_val  (l_val),
      .r_val  (r_val),
      .l_idx  (l_idx),
      .r_idx  (r_idx),
      .wr_en  (wr_en),
      .l_new  (l_new),
      .r_new  (r_new)
  );

  key_vault_model vault (
      .slot        (slot),
      .grant_in    (grant_in),
      .gate_subkey (gate_subkey),
      .subkey      (subkey),
      .grant       (grant)
  );

  // ---------------------------------------------------------------------------
  // Comprobadores
  // ---------------------------------------------------------------------------

  task automatic check32(input string nombre,
                         input logic [31:0] obtenido,
                         input logic [31:0] esperado);
    tests_run = tests_run + 1;
    if (obtenido !== esperado) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  %s: obtenido %08h, esperado %08h", nombre, obtenido, esperado);
    end
    else begin
      $display("  ok     %s", nombre);
    end
  endtask

  task automatic check1(input string nombre,
                        input logic obtenido,
                        input logic esperado);
    tests_run = tests_run + 1;
    if (obtenido !== esperado) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  %s: obtenido %b, esperado %b", nombre, obtenido, esperado);
    end
    else begin
      $display("  ok     %s", nombre);
    end
  endtask

  task automatic check4(input string nombre,
                        input logic [3:0] obtenido,
                        input logic [3:0] esperado);
    tests_run = tests_run + 1;
    if (obtenido !== esperado) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  %s: obtenido %0d, esperado %0d", nombre, obtenido, esperado);
    end
    else begin
      $display("  ok     %s", nombre);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Codificacion del slot S3, tipo F (isa.md 2.5)
  //   15:13 opcode | 12:10 par | 9:8 kv | 7:6 ronda | 5:0 reservado
  // ---------------------------------------------------------------------------

  function automatic [15:0] enc_f(input logic [2:0] opcode,
                                  input logic [2:0] par,
                                  input logic [1:0] kv,
                                  input logic [1:0] ronda);
    enc_f = {opcode, par, kv, ronda, 6'd0};
  endfunction

  // ---------------------------------------------------------------------------
  // Secuencias de apoyo
  // ---------------------------------------------------------------------------

  task automatic reposo();
    slot        = 16'd0;
    grant_in    = 1'b0;
    gate_subkey = 1'b1;
    l_val       = 32'd0;
    r_val       = 32'd0;
    #1;
  endtask

  // Emite una ronda de cifrado y comprueba las dos mitades nuevas.
  //
  // Los esperados llegan como argumentos y son constantes del spec. Esta
  // tarea no calcula nada.
  task automatic check_enc(input string nombre,
                           input logic [2:0]  par,
                           input logic [1:0]  kv,
                           input logic [1:0]  ronda,
                           input logic [31:0] l_in,
                           input logic [31:0] r_in,
                           input logic [31:0] l_esp,
                           input logic [31:0] r_esp);
    $display("[%s]", nombre);
    slot     = enc_f(OP_F4E, par, kv, ronda);
    grant_in = 1'b1;
    l_val    = l_in;
    r_val    = r_in;
    #1;
    check32("  mitad L nueva",      l_new, l_esp);
    check32("  mitad R nueva",      r_new, r_esp);
    check1 ("  habilita escritura", wr_en, 1'b1);
  endtask

  // Igual que check_enc pero para una ronda de descifrado.
  task automatic check_dec(input string nombre,
                           input logic [2:0]  par,
                           input logic [1:0]  kv,
                           input logic [1:0]  ronda,
                           input logic [31:0] l_in,
                           input logic [31:0] r_in,
                           input logic [31:0] l_esp,
                           input logic [31:0] r_esp);
    $display("[%s]", nombre);
    slot     = enc_f(OP_F4D, par, kv, ronda);
    grant_in = 1'b1;
    l_val    = l_in;
    r_val    = r_in;
    #1;
    check32("  mitad L nueva",      l_new, l_esp);
    check32("  mitad R nueva",      r_new, r_esp);
    check1 ("  habilita escritura", wr_en, 1'b1);
  endtask

  // Encadena las cuatro rondas de cifrado y despues las cuatro de descifrado,
  // realimentando la salida de cada ronda como entrada de la siguiente, igual
  // que lo haria el programa con cuatro instrucciones seguidas.
  //
  // Con `invertir` en bajo el descifrado usa los indices 3, 2, 1, 0 y debe
  // recuperar el bloque. En alto usa 0, 1, 2, 3 a proposito y NO debe
  // recuperarlo: ese caso negativo es lo que detecta una implementacion que
  // ignorara la subllave, porque sin la subllave el cifrado y el descifrado
  // serian inversos en cualquier orden y el ciclo pasaria igual.
  task automatic ciclo_completo(input string nombre,
                                input logic [1:0]  kv,
                                input logic [31:0] l0,
                                input logic [31:0] r0,
                                input logic        invertir,
                                input logic [31:0] cif_l_esp,
                                input logic [31:0] cif_r_esp);
    $display("[%s]", nombre);
    grant_in = 1'b1;
    cl = l0;
    cr = r0;

    for (int i = 0; i < 4; i = i + 1) begin
      slot  = enc_f(OP_F4E, 3'd0, kv, i[1:0]);
      l_val = cl;
      r_val = cr;
      #1;
      cl = l_new;
      cr = r_new;
    end

    if (!invertir) begin
      check32("  bloque cifrado, mitad L", cl, cif_l_esp);
      check32("  bloque cifrado, mitad R", cr, cif_r_esp);
    end

    for (int i = 0; i < 4; i = i + 1) begin
      rsel  = invertir ? i[1:0] : (2'd3 - i[1:0]);
      slot  = enc_f(OP_F4D, 3'd0, kv, rsel);
      l_val = cl;
      r_val = cr;
      #1;
      cl = l_new;
      cr = r_new;
    end

    if (!invertir) begin
      check32("  mitad L recuperada", cl, l0);
      check32("  mitad R recuperada", cr, r0);
    end
    else begin
      tests_run = tests_run + 1;
      if (cl === l0 && cr === r0) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  recupero el bloque con el orden de rondas equivocado");
      end
      else begin
        $display("  ok     con el orden equivocado no recupera el bloque");
      end
    end
  endtask

  // Comprueba que un par se traduzca a los dos indices de registro.
  //
  // Se emite sin permiso a proposito: los indices tienen que salir de todas
  // formas, porque el datapath los necesita para leer los operandos antes de
  // saber si la operacion procede.
  task automatic check_par(input logic [2:0] par,
                           input logic [3:0] l_esp,
                           input logic [3:0] r_esp);
    slot     = enc_f(OP_F4E, par, 2'd0, 2'd0);
    grant_in = 1'b0;
    #1;
    check4("indice de la mitad L", l_idx, l_esp);
    check4("indice de la mitad R", r_idx, r_esp);
  endtask

  task automatic resumen();
    $display("---");
    $display("casos: %0d   fallidos: %0d", tests_run, tests_failed);
    if (tests_failed != 0) begin
      $display("RESULTADO: FALLA");
      $fatal(1, "%0d caso(s) fallaron", tests_failed);
    end
    $display("RESULTADO: OK");
    $finish;
  endtask

  // ---------------------------------------------------------------------------
  // Casos
  // ---------------------------------------------------------------------------

  initial begin
    tests_run    = 0;
    tests_failed = 0;

    $display("=== testbench de la unidad Feistel4 ===");

    vault.clear_all();
    reposo();

    // -- Estado inerte del esqueleto -----------------------------------------
    // T1 no implementa comportamiento todavia. Se comprueba que sin permiso la
    // unidad no pide ninguna escritura, que es la precondicion de todos los
    // casos siguientes.
    $display("[estado inerte]");
    check1("sin permiso no habilita escritura", wr_en, 1'b0);

    // -- Modelo de la boveda -------------------------------------------------
    // Se valida el modelo contra si mismo, sin pasar por el DUT. Si el modelo
    // esta mal, todos los casos de T2 en adelante mienten.
    $display("[modelo de la boveda]");

    vault.set_key(2'd0, 32'h0BADC0DE, 32'h1337BEEF, 32'hDEADBEEF, 32'hFEEDFACE);
    vault.set_key(2'd2, 32'hAAAA0000, 32'hAAAA1111, 32'hAAAA2222, 32'hAAAA3333);

    grant_in = 1'b1;

    // El campo de ronda elige la palabra dentro de la llave.
    slot = enc_f(OP_F4E, 3'd0, 2'd0, 2'd0); #1;
    check32("llave 0, ronda 0", subkey, 32'h0BADC0DE);
    slot = enc_f(OP_F4E, 3'd0, 2'd0, 2'd1); #1;
    check32("llave 0, ronda 1", subkey, 32'h1337BEEF);
    slot = enc_f(OP_F4E, 3'd0, 2'd0, 2'd2); #1;
    check32("llave 0, ronda 2", subkey, 32'hDEADBEEF);
    slot = enc_f(OP_F4E, 3'd0, 2'd0, 2'd3); #1;
    check32("llave 0, ronda 3", subkey, 32'hFEEDFACE);

    // El campo kv elige la llave.
    slot = enc_f(OP_F4E, 3'd0, 2'd2, 2'd1); #1;
    check32("llave 2, ronda 1", subkey, 32'hAAAA1111);
    slot = enc_f(OP_F4E, 3'd0, 2'd1, 2'd0); #1;
    check32("llave 1 sin instalar queda en cero", subkey, 32'h0000_0000);

    // Sin permiso el modelo esconde la subllave, igual que la boveda real.
    grant_in = 1'b0;
    slot = enc_f(OP_F4E, 3'd0, 2'd0, 2'd0); #1;
    check32("sin permiso la boveda entrega cero", subkey, 32'h0000_0000);

    // Con la compuerta abierta la presenta de todas formas. Este modo existe
    // para probar que el aislamiento del DUT no depende de la boveda.
    gate_subkey = 1'b0; #1;
    check32("compuerta abierta: la subllave queda presente", subkey, 32'h0BADC0DE);
    check1 ("compuerta abierta: el permiso sigue en bajo",    grant,  1'b0);

    reposo();

    // -- T2: la funcion de ronda, aislada ------------------------------------
    //
    // Truco que evita agregar un puerto de depuracion: la ronda de cifrado
    // define la mitad R nueva como la L vieja en XOR con la funcion. Con la
    // mitad L en cero, la salida R ES la funcion de ronda. Asi se verifica
    // contra los vectores aislados a traves de la interfaz real.
    //
    // La mitad L nueva debe ser la R vieja en todos los casos.
    $display("[funcion de ronda, aislada con L en cero]");

    vault.set_key(2'd1, 32'h0000_0000, 32'h0000_0001, 32'hA5A5_A5A5, 32'h9E37_79B9);

    check_enc("solo rotaciones: x=00000001, k=0",
              3'd0, 2'd1, 2'd0,
              32'h0000_0000, 32'h0000_0001,
              32'h0000_0001, 32'h0000_2020);

    check_enc("el bit alto rota y no se pierde: x=80000000, k=0",
              3'd0, 2'd1, 2'd0,
              32'h0000_0000, 32'h8000_0000,
              32'h8000_0000, 32'h0000_1010);

    check_enc("la suma trunca el acarreo: x=FFFFFFFF, k=1",
              3'd0, 2'd1, 2'd1,
              32'h0000_0000, 32'hFFFF_FFFF,
              32'hFFFF_FFFF, 32'hFFFF_FFFF);

    check_enc("la subllave entra de verdad: x=0, k=A5A5A5A5",
              3'd0, 2'd1, 2'd2,
              32'h0000_0000, 32'h0000_0000,
              32'h0000_0000, 32'hA5A5_A5A5);

    // -- T2: el cruce de mitades ---------------------------------------------
    //
    // Las dos mitades son distintas a proposito. Si las asignaciones
    // estuvieran cruzadas, un caso con las mitades iguales pasaria igual y el
    // bug quedaria invisible. Es el error clasico de una red Feistel.
    //
    // Se evito el patron alternante 0x55555555 porque su funcion de ronda da
    // cero y el caso no distinguiria nada.
    $display("[cruce de mitades]");

    check_enc("L y R distintas: la L nueva es la R vieja",
              3'd0, 2'd1, 2'd3,
              32'hAAAA_AAAA, 32'h1234_5678,
              32'h1234_5678, 32'hC4A7_E057);

    // -- T2: la cadena de cuatro rondas de cifrado ---------------------------
    //
    // Tabla del spec seccion 5, con la llave 0 instalada en sus cuatro
    // palabras. El bloque inicial es L=01234567, R=89ABCDEF.
    $display("[cadena de cifrado, rondas 0 a 3]");

    check_enc("ronda 0",
              3'd0, 2'd0, 2'd0,
              32'h0123_4567, 32'h89AB_CDEF,
              32'h89AB_CDEF, 32'h39B9_CA9D);

    check_enc("ronda 1",
              3'd0, 2'd0, 2'd1,
              32'h89AB_CDEF, 32'h39B9_CA9D,
              32'h39B9_CA9D, 32'hFA89_784E);

    check_enc("ronda 2",
              3'd0, 2'd0, 2'd2,
              32'h39B9_CA9D, 32'hFA89_784E,
              32'hFA89_784E, 32'h396C_DD02);

    check_enc("ronda 3",
              3'd0, 2'd0, 2'd3,
              32'hFA89_784E, 32'h396C_DD02,
              32'h396C_DD02, 32'h4DA0_A476);

    // -- T3: la cadena de cuatro rondas de descifrado ------------------------
    //
    // La misma tabla del spec recorrida al reves. El descifrado copia la
    // mitad L vieja a la R nueva, al contrario del cifrado: si las dos
    // direcciones de copia estuvieran intercambiadas, estos casos lo
    // delatarian.
    $display("[cadena de descifrado, rondas 3 a 0]");

    check_dec("ronda 3",
              3'd0, 2'd0, 2'd3,
              32'h396C_DD02, 32'h4DA0_A476,
              32'hFA89_784E, 32'h396C_DD02);

    check_dec("ronda 2",
              3'd0, 2'd0, 2'd2,
              32'hFA89_784E, 32'h396C_DD02,
              32'h39B9_CA9D, 32'hFA89_784E);

    check_dec("ronda 1",
              3'd0, 2'd0, 2'd1,
              32'h39B9_CA9D, 32'hFA89_784E,
              32'h89AB_CDEF, 32'h39B9_CA9D);

    check_dec("ronda 0",
              3'd0, 2'd0, 2'd0,
              32'h89AB_CDEF, 32'h39B9_CA9D,
              32'h0123_4567, 32'h89AB_CDEF);

    // El inverso del caso de cruce de mitades de T2.
    check_dec("cruce de mitades inverso: la R nueva es la L vieja",
              3'd0, 2'd1, 2'd3,
              32'h1234_5678, 32'hC4A7_E057,
              32'hAAAA_AAAA, 32'h1234_5678);

    // -- T3: el ciclo completo de ida y vuelta -------------------------------
    //
    // Es la prueba mas fuerte del modulo: cualquier error en la funcion de
    // ronda, en las rotaciones o en el cruce de mitades la rompe.
    $display("[ciclo completo de ida y vuelta]");

    ciclo_completo("llave 0, bloque del spec", 2'd0,
                   32'h0123_4567, 32'h89AB_CDEF, 1'b0,
                   32'h396C_DD02, 32'h4DA0_A476);

    ciclo_completo("llave 2, otro bloque", 2'd2,
                   32'hCAFE_BABE, 32'h0D15_EA5E, 1'b0,
                   32'h5C93_E089, 32'h0EC9_0E70);

    // Caso negativo con las dos llaves: el orden de rondas importa.
    ciclo_completo("llave 0 con el orden de descifrado invertido", 2'd0,
                   32'h0123_4567, 32'h89AB_CDEF, 1'b1,
                   32'd0, 32'd0);

    ciclo_completo("llave 2 con el orden de descifrado invertido", 2'd2,
                   32'hCAFE_BABE, 32'h0D15_EA5E, 1'b1,
                   32'd0, 32'd0);

    // -- T4: decodificacion del par -----------------------------------------
    //
    // Pn = R(2n) : R(2n+1), con la mitad L en el registro par y la R en el
    // impar. Los ocho pares, para que ningun indice pueda estar fijo.
    $display("[decodificacion de los ocho pares]");

    check_par(3'd0, 4'd0,  4'd1);
    check_par(3'd1, 4'd2,  4'd3);
    check_par(3'd2, 4'd4,  4'd5);
    check_par(3'd3, 4'd6,  4'd7);
    check_par(3'd4, 4'd8,  4'd9);
    check_par(3'd5, 4'd10, 4'd11);
    check_par(3'd6, 4'd12, 4'd13);
    // El par 7 son el puntero de pila y el registro de enlace. Es un encoding
    // legal y la unidad no lo trata distinto: usarlo es problema del programa.
    check_par(3'd7, 4'd14, 4'd15);

    // Los indices no dependen del permiso: con permiso tienen que salir igual.
    $display("[los indices no dependen del permiso]");
    slot     = enc_f(OP_F4E, 3'd5, 2'd0, 2'd0);
    grant_in = 1'b1;
    #1;
    check4("con permiso, indice de la mitad L", l_idx, 4'd10);
    check4("con permiso, indice de la mitad R", r_idx, 4'd11);

    // -- T5: permiso y aislamiento de la subllave ----------------------------
    //
    // La via de fuga: con las dos mitades en cero, las dos rotaciones dan
    // cero, asi que la funcion de ronda queda igual a la subllave y el XOR con
    // la mitad opuesta, que tambien es cero, la deja intacta. En cifrado sale
    // por la mitad R y en descifrado por la mitad L.
    //
    // Primero se comprueba que la via existe de verdad, con permiso. Si no
    // existiera, la prueba de aislamiento no estaria probando nada.
    $display("[la via de fuga existe cuando hay permiso]");

    slot        = enc_f(OP_F4E, 3'd0, 2'd1, 2'd2);   // subllave A5A5A5A5
    grant_in    = 1'b1;
    gate_subkey = 1'b1;
    l_val       = 32'd0;
    r_val       = 32'd0;
    #1;
    check32("cifrando, la mitad R lleva la subllave", r_new, 32'hA5A5_A5A5);

    slot = enc_f(OP_F4D, 3'd0, 2'd1, 2'd2);
    #1;
    check32("descifrando, la mitad L lleva la subllave", l_new, 32'hA5A5_A5A5);

    // Ahora sin permiso, pero con el modelo presentando la subllave de todas
    // formas. El aislamiento tiene que sostenerse por merito de la unidad, no
    // porque la boveda le esconda la llave.
    $display("[sin permiso la subllave no sale, aunque este presente]");

    gate_subkey = 1'b0;
    grant_in    = 1'b0;

    slot = enc_f(OP_F4E, 3'd0, 2'd1, 2'd2);
    #1;
    check32("la subllave sigue presente en la entrada", subkey, 32'hA5A5_A5A5);
    check1 ("sin permiso no habilita escritura",        wr_en, 1'b0);
    check32("cifrando, la mitad L no filtra",           l_new, 32'h0000_0000);
    check32("cifrando, la mitad R no filtra",           r_new, 32'h0000_0000);

    slot = enc_f(OP_F4D, 3'd0, 2'd1, 2'd2);
    #1;
    check32("descifrando, la mitad L no filtra", l_new, 32'h0000_0000);
    check32("descifrando, la mitad R no filtra", r_new, 32'h0000_0000);

    // Con datos distintos de cero tampoco debe salir nada.
    l_val = 32'hDEAD_BEEF;
    r_val = 32'h1234_5678;
    #1;
    check32("sin permiso, la mitad L queda en cero", l_new, 32'h0000_0000);
    check32("sin permiso, la mitad R queda en cero", r_new, 32'h0000_0000);

    // La compuerta no se queda pegada: al volver el permiso, funciona.
    $display("[la compuerta no se queda pegada]");
    gate_subkey = 1'b1;
    grant_in    = 1'b1;
    slot        = enc_f(OP_F4E, 3'd0, 2'd0, 2'd0);
    l_val       = 32'h0123_4567;
    r_val       = 32'h89AB_CDEF;
    #1;
    check1 ("vuelve a habilitar escritura", wr_en, 1'b1);
    check32("vuelve a dar el resultado, L", l_new, 32'h89AB_CDEF);
    check32("vuelve a dar el resultado, R", r_new, 32'h39B9_CA9D);

    reposo();

`ifdef FORCE_FAIL
    // Autoprueba del arnes. Este caso tiene que fallar.
    $display("[autoprueba del arnes]");
    check32("caso deliberadamente incorrecto", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
