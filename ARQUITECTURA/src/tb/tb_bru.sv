`timescale 1ns/1ps

// =============================================================================
// tb_bru.sv - Testbench de la unidad de saltos.
//
// SystemVerilog plano: Icarus 13.0 no soporta clases, restricciones ni
// aleatorizacion, asi que los casos son tareas con valores esperados
// explicitos y un contador de errores.
//
// Los destinos esperados son CONSTANTES, calculadas a mano fuera del
// simulador. El testbench nunca aplica la formula del destino. El calculo
// lleva un mas uno que cuenta desde el delay slot; si el testbench
// reprodujera la formula, un error por uno apareceria en el modulo y en la
// prueba a la vez, y el caso pasaria.
//
// No hay reloj ni reset: la unidad es combinacional, asi que los casos
// avanzan con retardos simples.
//
// Esta unidad no habla con memoria ni con la boveda, asi que no hace falta
// ningun modelo auxiliar: el testbench maneja todas sus entradas.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto, para comprobar que el arnes sabe reportar una
// falla en lugar de pasar siempre por construccion.
// =============================================================================

module tb_bru;

  // Opcodes del slot S4 (isa.md 6)
  localparam logic [2:0] OP_NOP  = 3'b000;
  localparam logic [2:0] OP_BR   = 3'b001;
  localparam logic [2:0] OP_JAL  = 3'b010;
  localparam logic [2:0] OP_JR   = 3'b011;
  localparam logic [2:0] OP_JALR = 3'b100;
  localparam logic [2:0] OP_HALT = 3'b101;

  // Codigos de condicion (isa.md 6)
  localparam logic [2:0] C_AL   = 3'b000;
  localparam logic [2:0] C_EQ   = 3'b001;
  localparam logic [2:0] C_NE   = 3'b010;
  localparam logic [2:0] C_LT   = 3'b011;
  localparam logic [2:0] C_GE   = 3'b100;
  localparam logic [2:0] C_LTU  = 3'b101;
  localparam logic [2:0] C_GEU  = 3'b110;
  localparam logic [2:0] C_AUTH = 3'b111;

  // Causas de falla del registro de estado (isa.md 1.2)
  localparam logic [2:0] CAUSE_NONE  = 3'b000;
  localparam logic [2:0] CAUSE_ILLOP = 3'b001;

  // --- interfaz del DUT ---
  logic [15:0] slot;
  logic        valid;
  logic [31:0] pc;
  logic        flag_z;
  logic        flag_n;
  logic        flag_c;
  logic        flag_v;
  logic        flag_auth;
  logic [3:0]  rs_idx;
  logic [31:0] rs_val;
  logic        taken;
  logic [31:0] target;
  logic        link_we;
  logic [3:0]  link_idx;
  logic [31:0] link_val;
  logic        halt;
  logic        fault;
  logic [2:0]  cause;

  // --- contadores ---
  int tests_run;
  int tests_failed;

  // Variable de apoyo: Icarus no acepta indexar el resultado de una funcion
  // directamente, asi que el patron codificado pasa por aca antes de mirarle
  // los bits.
  logic [15:0] patron;

  // ---------------------------------------------------------------------------
  // Instancia
  // ---------------------------------------------------------------------------

  bru dut (
      .slot      (slot),
      .valid     (valid),
      .pc        (pc),
      .flag_z    (flag_z),
      .flag_n    (flag_n),
      .flag_c    (flag_c),
      .flag_v    (flag_v),
      .flag_auth (flag_auth),
      .rs_idx    (rs_idx),
      .rs_val    (rs_val),
      .taken     (taken),
      .target    (target),
      .link_we   (link_we),
      .link_idx  (link_idx),
      .link_val  (link_val),
      .halt      (halt),
      .fault     (fault),
      .cause     (cause)
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

  task automatic check16(input string nombre,
                         input logic [15:0] obtenido,
                         input logic [15:0] esperado);
    tests_run = tests_run + 1;
    if (obtenido !== esperado) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  %s: obtenido %04h, esperado %04h", nombre, obtenido, esperado);
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

  task automatic check3(input string nombre,
                        input logic [2:0] obtenido,
                        input logic [2:0] esperado);
    tests_run = tests_run + 1;
    if (obtenido !== esperado) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  %s: obtenido %03b, esperado %03b", nombre, obtenido, esperado);
    end
    else begin
      $display("  ok     %s", nombre);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Codificacion de los dos formatos del slot S4 (isa.md 2.5)
  //
  //   Tipo C   15:13 opcode | 12:10 cond | 9:0 desp con signo, en bundles
  //   Tipo J   15:13 opcode | 12:10 cond | 9 rsv | 8:5 rs | 4:0 rsv
  // ---------------------------------------------------------------------------

  function automatic [15:0] enc_c(input logic [2:0] opcode,
                                  input logic [2:0] cond,
                                  input logic [9:0] desp);
    enc_c = {opcode, cond, desp};
  endfunction

  function automatic [15:0] enc_j(input logic [2:0] opcode,
                                  input logic [2:0] cond,
                                  input logic [3:0] rs);
    enc_j = {opcode, cond, 1'b0, rs, 5'b00000};
  endfunction

  // ---------------------------------------------------------------------------
  // Secuencias de apoyo
  // ---------------------------------------------------------------------------

  task automatic reposo();
    slot      = 16'd0;
    valid     = 1'b0;
    pc        = 32'd0;
    flag_z    = 1'b0;
    flag_n    = 1'b0;
    flag_c    = 1'b0;
    flag_v    = 1'b0;
    flag_auth = 1'b0;
    rs_val    = 32'd0;
    #1;
  endtask

  // Emite un salto relativo y comprueba la resolucion.
  //
  // El destino esperado llega como argumento y es una constante precalculada.
  // Esta tarea no aplica la formula.
  //
  // Apaga todas las banderas a proposito, para quedar autocontenida. Si
  // heredara las que dejo el caso anterior, el resultado dependeria del orden
  // de ejecucion y un caso podria pasar o fallar segun lo que corriera antes.
  // El barrido de condiciones con banderas especificas es tarea de
  // check_cond.
  task automatic check_br(input string nombre,
                          input logic [2:0]  cond,
                          input logic [9:0]  desp,
                          input logic [31:0] pc_in,
                          input logic        taken_esp,
                          input logic [31:0] target_esp);
    $display("[%s]", nombre);
    slot      = enc_c(OP_BR, cond, desp);
    valid     = 1'b1;
    pc        = pc_in;
    flag_z    = 1'b0;
    flag_n    = 1'b0;
    flag_c    = 1'b0;
    flag_v    = 1'b0;
    flag_auth = 1'b0;
    #1;
    check1 ("  toma el salto", taken,   taken_esp);
    check32("  destino",       target,  target_esp);
    check1 ("  sin enlace",    link_we, 1'b0);
    check1 ("  sin detencion", halt,    1'b0);
    check1 ("  sin falla",     fault,   1'b0);
  endtask

  // Emite un salto relativo con una combinacion de banderas y comprueba solo
  // si la condicion se cumple. El destino ya lo valida check_br.
  task automatic check_cond(input string nombre,
                            input logic [2:0] cond,
                            input logic z,
                            input logic n,
                            input logic c,
                            input logic v,
                            input logic auth,
                            input logic taken_esp);
    slot      = enc_c(OP_BR, cond, 10'h001);
    valid     = 1'b1;
    pc        = 32'h0000_7100;
    flag_z    = z;
    flag_n    = n;
    flag_c    = c;
    flag_v    = v;
    flag_auth = auth;
    #1;
    check1(nombre, taken, taken_esp);
  endtask

  // Emite un salto indirecto y comprueba la resolucion.
  //
  // Apaga todas las banderas, por el mismo motivo que check_br: queda
  // autocontenida y no depende del orden de ejecucion. Con las banderas
  // apagadas, la condicion de siempre y la de distinto se cumplen, y la de
  // igualdad y la de sesion abierta no.
  task automatic check_jr(input string nombre,
                          input logic [2:0]  cond,
                          input logic [3:0]  rs,
                          input logic [31:0] rs_in,
                          input logic        taken_esp,
                          input logic [31:0] target_esp);
    $display("[%s]", nombre);
    slot      = enc_j(OP_JR, cond, rs);
    valid     = 1'b1;
    pc        = 32'h0000_7100;
    rs_val    = rs_in;
    flag_z    = 1'b0;
    flag_n    = 1'b0;
    flag_c    = 1'b0;
    flag_v    = 1'b0;
    flag_auth = 1'b0;
    #1;
    check1 ("  toma el salto",   taken,   taken_esp);
    check32("  destino",         target,  target_esp);
    check4 ("  indice fuente",   rs_idx,  rs);
    check1 ("  sin enlace",      link_we, 1'b0);
    check1 ("  sin detencion",   halt,    1'b0);
    check1 ("  sin falla",       fault,   1'b0);
  endtask

  // Emite un salto con enlace, en la forma relativa o en la indirecta, y
  // comprueba la resolucion mas el enlace.
  //
  // El valor del enlace se espera presente siempre, tomado o no: lo que el
  // permiso gobierna es la ESCRITURA. El valor es el contador mas 32, que no
  // es un dato secreto, a diferencia de la subllave en la unidad
  // criptografica, asi que apagarlo no agregaria seguridad.
  task automatic check_link(input string nombre,
                            input logic        indirecto,
                            input logic [2:0]  cond,
                            input logic [9:0]  desp,
                            input logic [3:0]  rs,
                            input logic [31:0] pc_in,
                            input logic [31:0] rs_in,
                            input logic        taken_esp,
                            input logic [31:0] target_esp,
                            input logic        link_esp,
                            input logic [31:0] link_val_esp);
    $display("[%s]", nombre);
    if (indirecto) slot = enc_j(OP_JALR, cond, rs);
    else           slot = enc_c(OP_JAL,  cond, desp);
    valid     = 1'b1;
    pc        = pc_in;
    rs_val    = rs_in;
    flag_z    = 1'b0;
    flag_n    = 1'b0;
    flag_c    = 1'b0;
    flag_v    = 1'b0;
    flag_auth = 1'b0;
    #1;
    check1 ("  toma el salto",      taken,    taken_esp);
    check32("  destino",            target,   target_esp);
    check1 ("  escribe el enlace",  link_we,  link_esp);
    check32("  valor del enlace",   link_val, link_val_esp);
    check4 ("  registro de enlace", link_idx, 4'd15);
    check1 ("  sin detencion",      halt,     1'b0);
    check1 ("  sin falla",          fault,    1'b0);
  endtask

  // Emite una detencion y comprueba que detiene sin saltar ni enlazar.
  //
  // El campo de condicion y el de registro llegan como argumentos para poder
  // comprobar que la unidad los IGNORA: el ISA dice que la detencion no usa
  // ningun campo salvo el opcode.
  task automatic check_halt(input string nombre,
                            input logic [2:0] cond,
                            input logic [3:0] rs,
                            input logic z,
                            input logic n,
                            input logic c,
                            input logic v,
                            input logic auth);
    $display("[%s]", nombre);
    slot      = enc_j(OP_HALT, cond, rs);
    valid     = 1'b1;
    pc        = 32'h0000_7100;
    rs_val    = 32'hDEAD_BEEF;
    flag_z    = z;
    flag_n    = n;
    flag_c    = c;
    flag_v    = v;
    flag_auth = auth;
    #1;
    check1("  detiene",             halt,    1'b1);
    check1("  no toma el salto",    taken,   1'b0);
    check1("  no escribe el enlace", link_we, 1'b0);
    check1("  sin falla",           fault,   1'b0);
  endtask

  // Emite una instruccion que debe fallar y comprueba que la anulacion es
  // completa.
  //
  // Las banderas quedan TODAS encendidas a proposito, para que cualquier
  // condicion que pudiera cumplirse se cumpla. Asi lo unico que puede impedir
  // el salto, el enlace o la detencion es la anulacion.
  task automatic check_illop(input string nombre, input logic [15:0] instr);
    $display("[%s]", nombre);
    slot      = instr;
    valid     = 1'b1;
    pc        = 32'h0000_7100;
    rs_val    = 32'hDEAD_BEEF;
    flag_z    = 1'b1;
    flag_n    = 1'b1;
    flag_c    = 1'b1;
    flag_v    = 1'b1;
    flag_auth = 1'b1;
    #1;
    check1("  falla",                fault,   1'b1);
    check3("  causa",                cause,   CAUSE_ILLOP);
    check1("  no toma el salto",     taken,   1'b0);
    check1("  no escribe el enlace", link_we, 1'b0);
    check1("  no detiene",           halt,    1'b0);
  endtask

  // Emite una instruccion que NO debe fallar y comprueba solo eso.
  task automatic check_sin_falla(input string nombre,
                                 input logic [15:0] instr,
                                 input logic        valid_in);
    slot      = instr;
    valid     = valid_in;
    pc        = 32'h0000_7100;
    rs_val    = 32'hDEAD_BEEF;
    flag_z    = 1'b1;
    flag_n    = 1'b1;
    flag_c    = 1'b1;
    flag_v    = 1'b1;
    flag_auth = 1'b1;
    #1;
    check1(nombre, fault, 1'b0);
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

    $display("=== testbench de la unidad BRU ===");

    reposo();

    // -- Estado inerte del esqueleto -----------------------------------------
    // T1 no implementa comportamiento todavia. Se comprueba que con el slot
    // sin emitir la unidad no resuelve nada, que es la precondicion de todos
    // los casos siguientes.
    $display("[estado inerte]");
    check1("sin emitir no toma el salto", taken,   1'b0);
    check1("sin emitir no escribe enlace", link_we, 1'b0);
    check1("sin emitir no detiene",        halt,    1'b0);
    check1("sin emitir no falla",          fault,   1'b0);

    // -- Codificadores del propio testbench ----------------------------------
    // Sin modelo auxiliar que validar, lo que hay que probar contra si mismo
    // son los codificadores. Si estan mal, todos los casos de T2 en adelante
    // mienten. Los patrones estan calculados a mano, fuera del simulador.
    $display("[codificadores del testbench]");

    check16("tipo C: BR.AL   con desp=1",
            enc_c(OP_BR,  C_AL,   10'h001), 16'h2001);
    check16("tipo C: JAL.LT  con desp=-1",
            enc_c(OP_JAL, C_LT,   10'h3FF), 16'h4FFF);
    check16("tipo C: BR.AUTH con desp=511",
            enc_c(OP_BR,  C_AUTH, 10'h1FF), 16'h3DFF);
    check16("tipo C: BR.AL   con desp=-512",
            enc_c(OP_BR,  C_AL,   10'h200), 16'h2200);

    check16("tipo J: JR.AL   con rs=R15",
            enc_j(OP_JR,   C_AL, 4'd15), 16'h61E0);
    check16("tipo J: JALR.EQ con rs=R4",
            enc_j(OP_JALR, C_EQ, 4'd4),  16'h8480);
    check16("tipo J: HALT",
            enc_j(OP_HALT, C_AL, 4'd0),  16'hA000);

    // El tipo J deja en cero los seis bits reservados, el 9 y los cinco bajos.
    patron = enc_j(OP_JR, C_AL, 4'd15);
    check1 ("tipo J: el bit 9 queda en cero",      patron[9], 1'b0);
    check32("tipo J: los bits 4:0 quedan en cero", {27'd0, patron[4:0]}, 32'd0);

    // -- T2: salto relativo incondicional ------------------------------------
    //
    // Destinos precalculados con el contador del bundle en 0x00007100, que
    // cae dentro de la region segura. Los valores salen de la tabla del plan,
    // calculados fuera del simulador.
    //
    // El desplazamiento se cuenta desde el DELAY SLOT, no desde el salto, por
    // el mas uno de la formula del ISA.
    $display("[salto relativo, desplazamientos]");

    // Desplazamiento cero: apunta al propio delay slot. Es el caso que
    // atrapa el error por uno. Un modulo que omitiera el mas uno daria el
    // contador en lugar del delay slot.
    check_br("desp = 0, el propio delay slot",
             C_AL, 10'h000, 32'h0000_7100, 1'b1, 32'h0000_7110);

    check_br("desp = 1, el bundle siguiente al delay slot",
             C_AL, 10'h001, 32'h0000_7100, 1'b1, 32'h0000_7120);

    check_br("desp = 2, dos despues del salto",
             C_AL, 10'h002, 32'h0000_7100, 1'b1, 32'h0000_7130);

    // Desplazamiento negativo: apunta al propio salto, que es el lazo mas
    // corto posible.
    check_br("desp = -1, el propio salto",
             C_AL, 10'h3FF, 32'h0000_7100, 1'b1, 32'h0000_7100);

    // Los extremos del rango atrapan una extension de signo tomada del bit
    // equivocado: 8 KB hacia cada lado.
    check_br("desp = 511, maximo hacia adelante",
             C_AL, 10'h1FF, 32'h0000_7100, 1'b1, 32'h0000_9100);

    check_br("desp = -512, maximo hacia atras",
             C_AL, 10'h200, 32'h0000_7100, 1'b1, 32'h0000_5110);

    // Con el contador en cero, para que el destino no pueda ser el contador
    // solo. Y con otro contador, para que no pueda ser el desplazamiento solo.
    $display("[el destino depende de los dos operandos]");

    check_br("contador en cero, desp = 1",
             C_AL, 10'h001, 32'h0000_0000, 1'b1, 32'h0000_0020);

    check_br("contador en cero, desp = -1",
             C_AL, 10'h3FF, 32'h0000_0000, 1'b1, 32'h0000_0000);

    check_br("otro contador, desp = 1",
             C_AL, 10'h001, 32'h0000_1000, 1'b1, 32'h0000_1020);

    check_br("otro contador, desp = -1",
             C_AL, 10'h3FF, 32'h0000_1000, 1'b1, 32'h0000_1000);

    // -- T3: las ocho condiciones --------------------------------------------
    //
    // Cada una con las banderas en los dos estados, para que ninguna pase por
    // casualidad. Orden de los argumentos de banderas: z, n, c, v, auth.
    $display("[condicion de siempre]");
    check_cond("AL con todas las banderas apagadas", C_AL, 0,0,0,0,0, 1'b1);
    check_cond("AL con todas las banderas encendidas", C_AL, 1,1,1,1,1, 1'b1);

    $display("[igualdad, sobre la bandera de cero]");
    check_cond("EQ con cero apagada no salta",  C_EQ, 0,0,0,0,0, 1'b0);
    check_cond("EQ con cero encendida salta",   C_EQ, 1,0,0,0,0, 1'b1);
    check_cond("NE con cero apagada salta",     C_NE, 0,0,0,0,0, 1'b1);
    check_cond("NE con cero encendida no salta", C_NE, 1,0,0,0,0, 1'b0);
    // La igualdad no debe mirar el acarreo.
    check_cond("EQ no responde al acarreo",     C_EQ, 0,0,1,0,0, 1'b0);

    // Las dos condiciones con signo son las unicas que comparan DOS banderas
    // entre si, asi que se prueban con las cuatro combinaciones. Con solo dos,
    // una implementacion que resolviera menor que como "signo encendida y
    // desbordamiento apagada" pasaria igual.
    $display("[menor que, las cuatro combinaciones de signo y desbordamiento]");
    check_cond("LT con signo 0 y desbordamiento 0 no salta", C_LT, 0,0,0,0,0, 1'b0);
    check_cond("LT con signo 0 y desbordamiento 1 salta",    C_LT, 0,0,0,1,0, 1'b1);
    check_cond("LT con signo 1 y desbordamiento 0 salta",    C_LT, 0,1,0,0,0, 1'b1);
    check_cond("LT con signo 1 y desbordamiento 1 no salta", C_LT, 0,1,0,1,0, 1'b0);

    $display("[mayor o igual, las mismas cuatro combinaciones invertidas]");
    check_cond("GE con signo 0 y desbordamiento 0 salta",    C_GE, 0,0,0,0,0, 1'b1);
    check_cond("GE con signo 0 y desbordamiento 1 no salta", C_GE, 0,0,0,1,0, 1'b0);
    check_cond("GE con signo 1 y desbordamiento 0 no salta", C_GE, 0,1,0,0,0, 1'b0);
    check_cond("GE con signo 1 y desbordamiento 1 salta",    C_GE, 0,1,0,1,0, 1'b1);

    $display("[sin signo, sobre el acarreo]");
    check_cond("LTU con acarreo apagado no salta",   C_LTU, 0,0,0,0,0, 1'b0);
    check_cond("LTU con acarreo encendido salta",    C_LTU, 0,0,1,0,0, 1'b1);
    check_cond("GEU con acarreo apagado salta",      C_GEU, 0,0,0,0,0, 1'b1);
    check_cond("GEU con acarreo encendido no salta", C_GEU, 0,0,1,0,0, 1'b0);

    // La condicion de sesion abierta tiene que mirar su propia bandera y
    // ninguna otra. Se prueba con las de comparacion en el estado contrario.
    $display("[sesion abierta, sobre su propia bandera]");
    check_cond("AUTH apagada no salta", C_AUTH, 0,0,0,0,0, 1'b0);
    check_cond("AUTH encendida salta",  C_AUTH, 0,0,0,0,1, 1'b1);
    check_cond("AUTH apagada no salta aunque las demas esten encendidas",
               C_AUTH, 1,1,1,1,0, 1'b0);
    check_cond("AUTH encendida salta aunque las demas esten apagadas",
               C_AUTH, 0,0,0,0,1, 1'b1);

    // Cuando la condicion no se cumple, el destino queda en cero.
    $display("[sin saltar, el destino queda en cero]");
    check_br("EQ con cero apagada",
             C_EQ, 10'h001, 32'h0000_7100, 1'b0, 32'h0000_0000);
    check_br("AUTH apagada",
             C_AUTH, 10'h1FF, 32'h0000_7100, 1'b0, 32'h0000_0000);

    // -- T4: salto indirecto -------------------------------------------------
    //
    // El destino es el valor del registro tal cual. El ISA dice PC = R[rs],
    // sin sumas y sin alineacion, asi que la unidad lo pasa entero.
    $display("[salto indirecto, el destino es el registro]");

    check_jr("destino desde R15",
             C_AL, 4'd15, 32'h1234_5678, 1'b1, 32'h1234_5678);

    check_jr("destino con todos los bits encendidos",
             C_AL, 4'd4, 32'hFFFF_FFFF, 1'b1, 32'hFFFF_FFFF);

    // Los bits bajos distintos de cero NO se alinean: el ISA no lo pide. Si
    // la unidad los enmascarara, este caso lo delataria.
    check_jr("destino con los bits bajos encendidos, no se alinea",
             C_AL, 4'd0, 32'h0000_0003, 1'b1, 32'h0000_0003);

    check_jr("destino con el bit alto encendido",
             C_AL, 4'd7, 32'h8000_000F, 1'b1, 32'h8000_000F);

    // El indice del registro sale de los bits 8:5, probado con varios valores
    // para que no pueda estar fijo.
    $display("[el indice del registro fuente sale de los bits 8:5]");

    check_jr("indice R1",  C_AL, 4'd1,  32'h0000_1000, 1'b1, 32'h0000_1000);
    check_jr("indice R8",  C_AL, 4'd8,  32'h0000_2000, 1'b1, 32'h0000_2000);
    check_jr("indice R12", C_AL, 4'd12, 32'h0000_3000, 1'b1, 32'h0000_3000);

    // Las condiciones funcionan igual que en la forma relativa, porque la
    // evaluacion es compartida. Con las banderas apagadas, distinto se cumple
    // e igualdad no.
    $display("[las condiciones valen igual en la forma indirecta]");

    check_jr("condicion de distinto se cumple",
             C_NE, 4'd5, 32'h0000_4000, 1'b1, 32'h0000_4000);

    // Cuando no se toma, el destino queda en cero pero el indice del registro
    // sigue saliendo: el datapath lo necesita para leer antes de saber si el
    // salto procede.
    check_jr("condicion de igualdad no se cumple, el indice igual sale",
             C_EQ, 4'd9, 32'h0000_5000, 1'b0, 32'h0000_0000);

    check_jr("condicion de sesion abierta no se cumple",
             C_AUTH, 4'd14, 32'h0000_6000, 1'b0, 32'h0000_0000);

    // -- T5: enlace de retorno -----------------------------------------------
    //
    // El enlace vale el contador mas 32 y va siempre a R15. Son 32 y no 16
    // porque el bundle siguiente es el delay slot y ya se ejecuto: el retorno
    // debe apuntar al bundle posterior a el.
    //
    // Con el contador en 0x00007100, el enlace vale 0x00007120.
    $display("[enlace en la forma relativa]");

    // Desplazamiento grande a proposito, para que el destino no coincida con
    // el enlace y los dos valores se distingan.
    check_link("JAL con desp = 511", 1'b0,
               C_AL, 10'h1FF, 4'd0,
               32'h0000_7100, 32'd0,
               1'b1, 32'h0000_9100,          // destino
               1'b1, 32'h0000_7120);         // enlace

    check_link("JAL con desp = -512", 1'b0,
               C_AL, 10'h200, 4'd0,
               32'h0000_7100, 32'd0,
               1'b1, 32'h0000_5110,
               1'b1, 32'h0000_7120);

    $display("[enlace en la forma indirecta]");

    check_link("JALR hacia una direccion lejana", 1'b1,
               C_AL, 10'd0, 4'd15,
               32'h0000_7100, 32'hDEAD_BEE0,
               1'b1, 32'hDEAD_BEE0,
               1'b1, 32'h0000_7120);

    // El valor del enlace no depende del destino: con el registro en cero, el
    // enlace sigue siendo el contador mas 32.
    check_link("JALR con el registro en cero, el enlace no cambia", 1'b1,
               C_AL, 10'd0, 4'd3,
               32'h0000_7100, 32'h0000_0000,
               1'b1, 32'h0000_0000,
               1'b1, 32'h0000_7120);

    // El enlace sigue al contador, no es una constante.
    check_link("JALR con otro contador", 1'b1,
               C_AL, 10'd0, 4'd8,
               32'h0000_1000, 32'h0000_ABCD,
               1'b1, 32'h0000_ABCD,
               1'b1, 32'h0000_1020);

    // El caso que motiva la decision 2 de la spec. Un salto condicional con
    // enlace que no se toma NO debe escribir el enlace: pisaria la direccion
    // de retorno del llamador sin haber llamado a nada.
    $display("[sin tomarse, el enlace no se escribe]");

    check_link("JAL condicional que no se toma", 1'b0,
               C_EQ, 10'h1FF, 4'd0,
               32'h0000_7100, 32'd0,
               1'b0, 32'h0000_0000,
               1'b0, 32'h0000_7120);

    check_link("JALR condicional que no se toma", 1'b1,
               C_EQ, 10'd0, 4'd15,
               32'h0000_7100, 32'hDEAD_BEE0,
               1'b0, 32'h0000_0000,
               1'b0, 32'h0000_7120);

    check_link("JAL con sesion cerrada no se toma ni enlaza", 1'b0,
               C_AUTH, 10'h001, 4'd0,
               32'h0000_7100, 32'd0,
               1'b0, 32'h0000_0000,
               1'b0, 32'h0000_7120);

    // -- T6: detencion -------------------------------------------------------
    //
    // El ISA dice textualmente que la detencion "no usa ningun campo salvo el
    // opcode". Asi que es incondicional e ignora tambien el campo de
    // registro. Los casos de abajo pasan condiciones que NO se cumplen y un
    // registro distinto de cero, y la detencion tiene que ocurrir igual.
    $display("[detencion]");

    check_halt("con la condicion de siempre", C_AL, 4'd0, 0,0,0,0,0);

    // Condiciones falsas: si la unidad las respetara, estos casos no
    // detendrian.
    check_halt("con igualdad falsa, igual detiene",
               C_EQ, 4'd0, 0,0,0,0,0);
    check_halt("con sesion cerrada, igual detiene",
               C_AUTH, 4'd0, 0,0,0,0,0);
    check_halt("con menor que falsa, igual detiene",
               C_LT, 4'd0, 0,0,0,0,0);
    check_halt("con distinto falsa, igual detiene",
               C_NE, 4'd0, 1,1,1,1,1);

    // El campo de registro tampoco se usa.
    check_halt("con el campo de registro distinto de cero, igual detiene",
               C_AL, 4'd7, 0,0,0,0,0);

    // -- T7: falla de opcode y anulacion -------------------------------------
    //
    // Barrido de los ocho opcodes con los bits reservados limpios, para que
    // la unica razon posible de falla sea el opcode mismo.
    $display("[barrido de los ocho opcodes]");

    check_sin_falla("000 NOP  no falla",  enc_j(OP_NOP,  C_AL, 4'd0), 1'b1);
    check_sin_falla("001 BR   no falla",  enc_c(OP_BR,   C_AL, 10'h001), 1'b1);
    check_sin_falla("010 JAL  no falla",  enc_c(OP_JAL,  C_AL, 10'h001), 1'b1);
    check_sin_falla("011 JR   no falla",  enc_j(OP_JR,   C_AL, 4'd5), 1'b1);
    check_sin_falla("100 JALR no falla",  enc_j(OP_JALR, C_AL, 4'd5), 1'b1);
    check_sin_falla("101 HALT no falla",  enc_j(OP_HALT, C_AL, 4'd0), 1'b1);

    check_illop("110 reservado", enc_j(3'b110, C_AL, 4'd0));
    check_illop("111 reservado", enc_j(3'b111, C_AL, 4'd0));

    // Los seis bits reservados del tipo J: el bit 9 y los cinco bajos. Se
    // prueban por separado y en las tres formas del tipo J.
    $display("[bits reservados del tipo J, el bit 9]");
    check_illop("JR con el bit 9 encendido",
                enc_j(OP_JR,   C_AL, 4'd5) | 16'h0200);
    check_illop("JALR con el bit 9 encendido",
                enc_j(OP_JALR, C_AL, 4'd5) | 16'h0200);
    check_illop("HALT con el bit 9 encendido",
                enc_j(OP_HALT, C_AL, 4'd0) | 16'h0200);

    $display("[bits reservados del tipo J, los cinco bajos]");
    check_illop("JR con los bits 4:0 encendidos",
                enc_j(OP_JR,   C_AL, 4'd5) | 16'h001F);
    check_illop("JALR con los bits 4:0 encendidos",
                enc_j(OP_JALR, C_AL, 4'd5) | 16'h001F);
    check_illop("HALT con los bits 4:0 encendidos",
                enc_j(OP_HALT, C_AL, 4'd0) | 16'h001F);
    check_illop("JR con un solo bit bajo encendido",
                enc_j(OP_JR,   C_AL, 4'd5) | 16'h0001);

    // La trampa de esta tarea. El tipo C NO tiene bits reservados: el
    // desplazamiento ocupa los diez bits bajos completos. Si la unidad
    // aplicara la regla de reservados a esta forma, todo salto de
    // desplazamiento grande fallaria, y las pruebas con desplazamientos
    // chicos no lo notarian.
    $display("[el tipo C no tiene bits reservados]");

    check_sin_falla("BR con los diez bits bajos llenos no falla",
                    enc_c(OP_BR,  C_AL, 10'h3FF), 1'b1);
    check_sin_falla("JAL con los diez bits bajos llenos no falla",
                    enc_c(OP_JAL, C_AL, 10'h3FF), 1'b1);
    check_sin_falla("BR con el maximo positivo no falla",
                    enc_c(OP_BR,  C_AL, 10'h1FF), 1'b1);
    check_sin_falla("BR con el maximo negativo no falla",
                    enc_c(OP_BR,  C_AL, 10'h200), 1'b1);

    // La operacion nula ignora los campos que no usa. Si levantara falla por
    // ellos, todo bundle que no use el slot de saltos fallaria.
    $display("[la operacion nula ignora los demas campos]");

    check_sin_falla("NOP con basura en todos los demas campos",
                    enc_c(OP_NOP, C_AUTH, 10'h3FF), 1'b1);
    check_sin_falla("NOP todo en ceros",
                    16'h0000, 1'b1);

    // El slot sin emitir no hace nada ni falla, aunque el opcode sea invalido.
    $display("[el slot sin emitir]");

    check_sin_falla("opcode reservado sin emitir no falla",
                    enc_j(3'b111, C_AL, 4'd0), 1'b0);
    check_sin_falla("tipo J con reservados sucios sin emitir no falla",
                    enc_j(OP_JR, C_AL, 4'd5) | 16'h021F, 1'b0);

    reposo();

`ifdef FORCE_FAIL
    // Autoprueba del arnes. Este caso tiene que fallar.
    $display("[autoprueba del arnes]");
    check32("caso deliberadamente incorrecto", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
