`timescale 1ns/1ps

// =============================================================================
// tb_top.sv - Testbench del procesador completo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Corre PROGRAMAS, no vectores. Los diecinueve testbenches anteriores ya
// comprueban la logica de cada unidad y de cada frontera, asi que lo que falta
// no es logica: es cableado. Un operando conectado al puerto de al lado, una
// falla que llega un ciclo corrida, el dato de una carga que nunca se sustituye.
// Nada de eso se ve mirando una unidad sola, y todo se ve cuando un programa
// real da un resultado equivocado.
//
// -----------------------------------------------------------------------------
// DE DONDE SALEN LOS VALORES ESPERADOS
// -----------------------------------------------------------------------------
// De fuera del simulador. Los resultados del cifrado se calcularon aparte con
// la formula del enunciado y estan escritos aqui como constantes:
//
//   F(x,k) = (ROL32(x,5) + k) XOR ROL32(x,13)
//   cifrar: (L,R) -> (R, L XOR F(R,k))
//
//   claro            L=DEADBEEF  R=CAFEBABE
//   ronda 0 con k0   L=CAFEBABE  R=79120F5A
//   ronda 1 con k1   L=79120F5A  R=CF71F8ED
//   ronda 2 con k2   L=CF71F8ED  R=677DE658
//   ronda 3 con k3   L=677DE658  R=47BBFB52
//
// El testbench no recalcula la funcion de ronda. Si lo hiciera, un error en la
// formula aparecería en el RTL y en la prueba a la vez y el caso pasaria.
//
// -----------------------------------------------------------------------------
// LOS PROGRAMAS
// -----------------------------------------------------------------------------
//   P1  aritmetica: constantes, suma con registros y con inmediato, y una
//       cadena de dependencias separada por los 3 bundles que promete el ISA
//   P2  memoria: almacenar y volver a cargar palabra, media palabra y byte,
//       con y sin signo, y el postincremento
//   P3  saltos: una llamada con JAL, retorno con JR, y el delay slot de cada uno
//   P4  cifrado completo: credencial, LOGIN, instalar la llave y cuatro rondas
//       sobre un bloque conocido, con el resultado guardado en memoria
//   P5  la misma rutina de cifrado FUERA de la region segura, que debe ser
//       denegada y no producir nada
//   P6  fallas: el opcode reservado de S3 y un acceso desalineado
//
// Se escriben en la memoria por referencia jerarquica, no por archivo, para no
// depender de una ruta relativa.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
// =============================================================================

`include "cerbero_defs.svh"

module tb_top;

  // Memorias chicas: el programa mas largo ocupa unos 60 bundles
  localparam int N_BUNDLES = 128;
  localparam int N_WORDS   = 64;

  // Region segura puesta donde cabe el programa de cifrado
  localparam logic [`XLEN-1:0] SEC_B = 32'h0000_0100;
  localparam logic [`XLEN-1:0] SEC_L = 32'h0000_03FF;

  localparam logic [127:0] SECRETO =
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  // ---------------------------------------------------------------------------
  // Dos instancias: una arranca dentro de la region segura y otra fuera.
  // Es la unica forma de probar las dos mitades del control de acceso sin
  // reparametrizar en medio de la simulacion.
  // ---------------------------------------------------------------------------

  logic                         halted_s, halted_i;
  logic [`XLEN-1:0]             psw_s, psw_i;
  logic [`NREGS-1:0][`XLEN-1:0] regs_s, regs_i;

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (SEC_B),
      .SEC_BASE    (SEC_B),
      .SEC_LIMIT   (SEC_L),
      .ROT_SECRET  (SECRETO)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted_s),
      .psw      (psw_s),
      .dbg_regs (regs_s)
  );

  // La misma configuracion pero arrancando en cero, fuera de [SEC_B, SEC_L]
  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000),
      .SEC_BASE    (SEC_B),
      .SEC_LIMIT   (SEC_L),
      .ROT_SECRET  (SECRETO)
  ) dut_fuera (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted_i),
      .psw      (psw_i),
      .dbg_regs (regs_i)
  );

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
        $display("  FALLA  %-44s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %-44s %08h", nombre, obtenido);
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
  // Ensamblador minimo
  //
  // Un constructor por formato, con numeros literales y no con los macros de
  // campo, para que el arnes no herede un error de los macros.
  // ---------------------------------------------------------------------------

  // Tipo A: opcode | rd | rs1 | rs2 | reservado
  function automatic logic [31:0] a_rrr(input logic [4:0] opc,
                                        input logic [3:0] rd,
                                        input logic [3:0] rs1,
                                        input logic [3:0] rs2);
    begin
      a_rrr = {opc, rd, rs1, rs2, 15'd0};
    end
  endfunction

  // Tipos I y M: opcode | rd | rs1 | imm19
  function automatic logic [31:0] a_rri(input logic [4:0]  opc,
                                        input logic [3:0]  rd,
                                        input logic [3:0]  rs1,
                                        input integer      imm);
    logic [18:0] i19;
    begin
      i19   = imm[18:0];
      a_rri = {opc, rd, rs1, i19};
    end
  endfunction

  // Tipo U de MOVH: opcode | rd | 0000 | imm16 | cond=000
  function automatic logic [31:0] a_movh(input logic [3:0]  rd,
                                         input logic [15:0] imm);
    begin
      a_movh = {5'b11101, rd, 4'd0, imm, 3'd0};
    end
  endfunction

  // Tipo F de S3: opcode | par | kv | ronda | reservado
  function automatic logic [15:0] s3_f(input logic [2:0] opc,
                                       input logic [2:0] par,
                                       input logic [1:0] kv,
                                       input logic [1:0] ronda);
    begin
      s3_f = {opc, par, kv, ronda, 6'd0};
    end
  endfunction

  // Tipo V de S3: opcode | [12:11] | [10:9] | rs | reservado
  function automatic logic [15:0] s3_v(input logic [2:0] opc,
                                       input logic [1:0] alto,
                                       input logic [1:0] medio,
                                       input logic [3:0] rs);
    begin
      s3_v = {opc, alto, medio, rs, 5'd0};
    end
  endfunction

  // Tipo AC de S3: 110 | i | subop | rd | rs2 o imm5
  function automatic logic [15:0] s3_ac(input logic       i,
                                        input logic [2:0] subop,
                                        input logic [3:0] rd,
                                        input logic [4:0] op2);
    begin
      s3_ac = {3'b110, i, subop, rd, op2};
    end
  endfunction

  // Tipo C de S4: opcode | cond | desp
  function automatic logic [15:0] s4_c(input logic [2:0] opc,
                                       input logic [2:0] cond,
                                       input integer     desp);
    logic [9:0] d;
    begin
      d     = desp[9:0];
      s4_c  = {opc, cond, d};
    end
  endfunction

  // Tipo J de S4: opcode | cond | reservado | rs | reservado
  function automatic logic [15:0] s4_j(input logic [2:0] opc,
                                       input logic [2:0] cond,
                                       input logic [3:0] rs);
    begin
      s4_j = {opc, cond, 1'b0, rs, 5'd0};
    end
  endfunction

  localparam logic [31:0] NOP32 = 32'd0;
  localparam logic [15:0] NOP16 = 16'd0;
  localparam logic [15:0] HALT  = {`BRU_HALT, 13'd0};

  // Arma un bundle a partir de sus cinco slots
  function automatic logic [`BUNDLE_W-1:0] bundle(input logic [31:0] s0,
                                                   input logic [31:0] s1,
                                                   input logic [31:0] s2,
                                                   input logic [15:0] s3,
                                                   input logic [15:0] s4);
    begin
      bundle = {s0, s1, s2, s3, s4};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Carga de programa y de datos
  // ---------------------------------------------------------------------------

  // Indice de bundle del primer bundle del programa seguro
  localparam int BASE_S = 32'h100 / 16;   // 16

  task automatic prog_s(input integer idx, input logic [`BUNDLE_W-1:0] b);
    begin
      dut.u_imem.storage[idx] = b;
    end
  endtask

  task automatic prog_i(input integer idx, input logic [`BUNDLE_W-1:0] b);
    begin
      dut_fuera.u_imem.storage[idx] = b;
    end
  endtask

  task automatic dato_s(input integer w, input logic [31:0] v);
    begin
      dut.u_dmem.storage[w] = v;
    end
  endtask

  task automatic dato_i(input integer w, input logic [31:0] v);
    begin
      dut_fuera.u_dmem.storage[w] = v;
    end
  endtask

  task automatic limpiar_imem_s();
    integer k;
    begin
      for (k = 0; k < N_BUNDLES; k = k + 1)
        dut.u_imem.storage[k] = {`BUNDLE_W{1'b0}};
    end
  endtask

  task automatic reiniciar();
    begin
      rst_n = 1'b0;
      repeat (3) @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // Corre hasta que el procesador se detenga, con tope por si nunca lo hace
  task automatic correr_hasta_halt(input integer tope);
    integer c;
    begin
      c = 0;
      while (!halted_s && c < tope) begin
        @(posedge clk);
        c = c + 1;
      end
      // Deja que los bundles en vuelo terminen sus cinco etapas
      repeat (6) @(posedge clk);
      #1;
      if (c >= tope)
        $display("  AVISO  el programa no se detuvo en %0d ciclos", tope);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Valores del programa de cifrado, calculados fuera del simulador
  // ---------------------------------------------------------------------------

  localparam logic [31:0] CRED0 = 32'h7654_3210;   // palabras de SECRETO
  localparam logic [31:0] CRED1 = 32'hFEDC_BA98;
  localparam logic [31:0] CRED2 = 32'h89AB_CDEF;
  localparam logic [31:0] CRED3 = 32'h0123_4567;

  localparam logic [31:0] LLAVE0 = 32'h1111_1111;
  localparam logic [31:0] LLAVE1 = 32'h2222_2222;
  localparam logic [31:0] LLAVE2 = 32'h3333_3333;
  localparam logic [31:0] LLAVE3 = 32'h4444_4444;

  localparam logic [31:0] CLARO_L = 32'hDEAD_BEEF;
  localparam logic [31:0] CLARO_R = 32'hCAFE_BABE;

  localparam logic [31:0] CIFRA_L = 32'h677D_E658;
  localparam logic [31:0] CIFRA_R = 32'h47BB_FB52;

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer b, i;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_top.vcd");
      $dumpvars(0, tb_top);
    end

    rst_n = 1'b0;
    #1;

    $display("=== tb_top: el procesador completo corriendo programas ===");

    // ========================================================================
    $display("");
    $display("[P1] aritmetica y latencia de 3 bundles");
    // ========================================================================
    // movi r1,#100 / movi r2,#23 / add r3,r1,r2 / addi r4,r3,#1
    // Cada consumidor va tres bundles despues de su productor, que es la regla
    // unica del ISA. Si el pipeline entregara los operandos un ciclo tarde,
    // r3 saldria con los valores viejos y seria cero.

    limpiar_imem_s();
    b = BASE_S;
    prog_s(b+0, bundle(a_rri(`ALU_MOVI, 4'd1, 4'd0, 100), NOP32, NOP32, NOP16, NOP16));
    prog_s(b+1, bundle(a_rri(`ALU_MOVI, 4'd2, 4'd0,  23), NOP32, NOP32, NOP16, NOP16));
    // r2 se escribe en b+1, asi que su consumidor no puede ir antes de b+4:
    // la regla del ISA es m >= n+3 y se cuenta en bundles ejecutados.
    prog_s(b+4, bundle(a_rrr(`ALU_ADD, 4'd3, 4'd1, 4'd2), NOP32, NOP32, NOP16, NOP16));
    prog_s(b+7, bundle(a_rri(`ALU_ADDI, 4'd4, 4'd3, 1), NOP32, NOP32, NOP16, NOP16));
    // Las dos ALU en el mismo bundle, a registros distintos
    prog_s(b+8, bundle(a_rri(`ALU_MOVI, 4'd5, 4'd0, 7),
                       a_rri(`ALU_MOVI, 4'd6, 4'd0, 9), NOP32, NOP16, NOP16));
    // La ALU corta en S3, destructiva sobre r5, tres bundles despues
    prog_s(b+11, bundle(NOP32, NOP32, NOP32, s3_ac(1'b1, `SALU_ADD, 4'd5, 5'd3), NOP16));
    prog_s(b+14, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+15, bundle(NOP32, NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(200);

    check32("r1 = movi #100",            regs_s[1], 32'd100);
    check32("r2 = movi #23",             regs_s[2], 32'd23);
    check32("r3 = r1 + r2",              regs_s[3], 32'd123);
    check32("r4 = r3 + 1",               regs_s[4], 32'd124);
    check32("r6 = movi en la segunda ALU", regs_s[6], 32'd9);
    check32("r5 = 7, y la ALU corta le sumo 3", regs_s[5], 32'd10);
    check1 ("el procesador se detuvo",   halted_s, 1'b1);
    check1 ("sin fallas en el PSW",      psw_s[`PSW_EXC], 1'b0);

    // ========================================================================
    $display("");
    $display("[P2] memoria: almacenar, cargar y postincrementar");
    // ========================================================================
    // Este programa es el que prueba la responsabilidad 4 del top: el valor del
    // puerto del destino de la carga no existe en EX y la etapa de memoria lo
    // sustituye. Si la sustitucion no ocurriera, toda carga daria cero.

    limpiar_imem_s();
    for (i = 0; i < N_WORDS; i = i + 1) dato_s(i, 32'd0);
    dato_s(8, 32'h8899_AABB);      // palabra en la direccion 0x20

    b = BASE_S;
    // r1 = 0x20, la direccion base
    prog_s(b+0,  bundle(a_rri(`ALU_MOVI, 4'd1, 4'd0, 32), NOP32, NOP32, NOP16, NOP16));
    // lw r2, 0(r1)
    prog_s(b+3,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd2, 4'd1, 0), NOP16, NOP16));
    // lbu r3, 0(r1) y lb r4, 1(r1): el carril bajo es BB, el siguiente AA
    prog_s(b+4,  bundle(NOP32, NOP32, a_rri(`LSU_LBU, 4'd3, 4'd1, 0), NOP16, NOP16));
    prog_s(b+5,  bundle(NOP32, NOP32, a_rri(`LSU_LB,  4'd4, 4'd1, 1), NOP16, NOP16));
    // lhu r5, 2(r1): la media palabra alta es 0x8899
    prog_s(b+6,  bundle(NOP32, NOP32, a_rri(`LSU_LHU, 4'd5, 4'd1, 2), NOP16, NOP16));
    // lh r6, 2(r1): la misma con signo
    prog_s(b+7,  bundle(NOP32, NOP32, a_rri(`LSU_LH,  4'd6, 4'd1, 2), NOP16, NOP16));
    // sw r2, 16(r1) guarda la palabra en 0x30, y lw r7 la trae de vuelta
    prog_s(b+8,  bundle(NOP32, NOP32, a_rri(`LSU_SW,  4'd2, 4'd1, 16), NOP16, NOP16));
    prog_s(b+11, bundle(NOP32, NOP32, a_rri(`LSU_LW,  4'd7, 4'd1, 16), NOP16, NOP16));
    // sb r3, 32(r1) escribe un solo byte en 0x40, sin tocar los vecinos
    prog_s(b+12, bundle(NOP32, NOP32, a_rri(`LSU_SB,  4'd3, 4'd1, 32), NOP16, NOP16));
    // lw.inc r8, 0(r1): carga de 0x20 y deja r1 en 0x24
    prog_s(b+15, bundle(NOP32, NOP32, a_rri(`LSU_LW_INC, 4'd8, 4'd1, 4), NOP16, NOP16));
    prog_s(b+19, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+20, bundle(NOP32, NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(200);

    check32("lw trae la palabra completa",       regs_s[2], 32'h8899_AABB);
    check32("lbu extiende con ceros",            regs_s[3], 32'h0000_00BB);
    check32("lb extiende con signo",             regs_s[4], 32'hFFFF_FFAA);
    check32("lhu extiende con ceros",            regs_s[5], 32'h0000_8899);
    check32("lh extiende con signo",             regs_s[6], 32'hFFFF_8899);
    check32("sw y lw de vuelta",                 regs_s[7], 32'h8899_AABB);
    check32("sb escribio solo su carril",        dut.u_dmem.storage[16], 32'h0000_00BB);
    check32("lw.inc trajo el dato",              regs_s[8], 32'h8899_AABB);
    check32("y dejo la base incrementada",       regs_s[1], 32'h0000_0024);
    check1 ("sin fallas en el PSW",              psw_s[`PSW_EXC], 1'b0);

    // ========================================================================
    $display("");
    $display("[P3] saltos, enlace y delay slot");
    // ========================================================================
    // jal a una rutina que pone r9, y retorno con jr r15. El delay slot de cada
    // salto lleva una operacion de verdad, para comprobar que se ejecuta.

    limpiar_imem_s();
    b = BASE_S;
    // b+0: movi r1,#1 ; jal +2 -> destino b+0 + 16*3 = b+3
    prog_s(b+0, bundle(a_rri(`ALU_MOVI, 4'd1, 4'd0, 1), NOP32, NOP32, NOP16,
                       s4_c(`BRU_JAL, `COND_AL, 2)));
    // b+1: delay slot del jal, con una operacion que debe ocurrir
    prog_s(b+1, bundle(a_rri(`ALU_MOVI, 4'd2, 4'd0, 2), NOP32, NOP32, NOP16, NOP16));
    // b+2: aqui aterriza el retorno, porque el enlace vale PC + 32. Pone r3 y
    // detiene: sin el HALT aqui el programa volveria a entrar a la rutina y se
    // ciclaria, porque r15 sigue apuntando a este bundle.
    prog_s(b+2, bundle(a_rri(`ALU_MOVI, 4'd3, 4'd0, 99), NOP32, NOP32, NOP16, HALT));
    // b+3: la rutina. En bundles EJECUTADOS, el jal es el primero y el jr el
    // cuarto, asi que r15 lleva los tres bundles de separacion que pide el ISA.
    prog_s(b+3, bundle(a_rri(`ALU_MOVI, 4'd9, 4'd0, 42), NOP32, NOP32, NOP16, NOP16));
    prog_s(b+4, bundle(NOP32, NOP32, NOP32, NOP16, s4_j(`BRU_JR, `COND_AL, 4'd15)));
    // b+5: delay slot del jr
    prog_s(b+5, bundle(a_rri(`ALU_MOVI, 4'd4, 4'd0, 4), NOP32, NOP32, NOP16, NOP16));
    // b+6: nunca se ejecuta
    prog_s(b+6, bundle(a_rri(`ALU_MOVI, 4'd5, 4'd0, 99), NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(200);

    check32("r1 del bundle con el jal",        regs_s[1], 32'd1);
    check32("r2 del delay slot del jal",       regs_s[2], 32'd2);
    check32("r9 de la rutina",                 regs_s[9], 32'd42);
    check32("r4 del delay slot del jr",        regs_s[4], 32'd4);
    check32("r15 trae el enlace, PC + 32",     regs_s[15], SEC_B + 32);
    // El retorno cae en b+2, que pone r3 = 99. r5 nunca se ejecuta.
    check32("el retorno aterrizo en PC + 32",  regs_s[3], 32'd99);
    check32("y no siguio de largo",            regs_s[5], 32'd0);

    // ========================================================================
    $display("");
    $display("[P4] cifrado Feistel4 completo");
    // ========================================================================
    // El programa del enunciado: presentar la credencial, autenticar, instalar
    // la llave y cifrar un bloque con cuatro rondas. Todo dentro de la region
    // segura, porque la boveda cierra la sesion en cuanto el PC sale de ella.
    //
    // Es el caso que recorre el procesador entero: carga de memoria, la boveda
    // con su protocolo, la unidad de ronda leyendo y escribiendo un par de
    // registros, y el resultado guardado de vuelta en memoria.

    limpiar_imem_s();
    for (i = 0; i < N_WORDS; i = i + 1) dato_s(i, 32'd0);
    dato_s(0, CRED0);  dato_s(1, CRED1);  dato_s(2, CRED2);  dato_s(3, CRED3);
    dato_s(4, LLAVE0); dato_s(5, LLAVE1); dato_s(6, LLAVE2); dato_s(7, LLAVE3);
    dato_s(8, CLARO_L); dato_s(9, CLARO_R);

    b = BASE_S;
    // Cargar credencial en r1..r4 y llave en r5..r8
    prog_s(b+0,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd1, 4'd0,  0), NOP16, NOP16));
    prog_s(b+1,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd2, 4'd0,  4), NOP16, NOP16));
    prog_s(b+2,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd3, 4'd0,  8), NOP16, NOP16));
    prog_s(b+3,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd4, 4'd0, 12), NOP16, NOP16));
    prog_s(b+4,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd5, 4'd0, 16), NOP16, NOP16));
    prog_s(b+5,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd6, 4'd0, 20), NOP16, NOP16));
    prog_s(b+6,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd7, 4'd0, 24), NOP16, NOP16));
    prog_s(b+7,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd8, 4'd0, 28), NOP16, NOP16));
    // El bloque va al par P5, que son r10 y r11
    prog_s(b+8,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd10, 4'd0, 32), NOP16, NOP16));
    prog_s(b+9,  bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd11, 4'd0, 36), NOP16, NOP16));
    // Credencial: cuatro palabras al registro de desafio
    prog_s(b+10, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_AUTHW, 2'd0, 2'd0, 4'd1), NOP16));
    prog_s(b+11, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_AUTHW, 2'd0, 2'd1, 4'd2), NOP16));
    prog_s(b+12, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_AUTHW, 2'd0, 2'd2, 4'd3), NOP16));
    prog_s(b+13, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_AUTHW, 2'd0, 2'd3, 4'd4), NOP16));
    // LOGIN
    prog_s(b+14, bundle(NOP32, NOP32, NOP32,
                        s3_v(`CRP_VCTL, `VCTL_LOGIN, 2'd0, 4'd0), NOP16));
    // Instalar la llave en la ranura 0, tres bundles despues del login
    prog_s(b+17, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_KSETW, 2'd0, 2'd0, 4'd5), NOP16));
    prog_s(b+18, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_KSETW, 2'd0, 2'd1, 4'd6), NOP16));
    prog_s(b+19, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_KSETW, 2'd0, 2'd2, 4'd7), NOP16));
    prog_s(b+20, bundle(NOP32, NOP32, NOP32, s3_v(`CRP_KSETW, 2'd0, 2'd3, 4'd8), NOP16));
    // Cuatro rondas, separadas por los 3 bundles de la latencia
    prog_s(b+23, bundle(NOP32, NOP32, NOP32, s3_f(`CRP_F4E, 3'd5, 2'd0, 2'd0), NOP16));
    prog_s(b+26, bundle(NOP32, NOP32, NOP32, s3_f(`CRP_F4E, 3'd5, 2'd0, 2'd1), NOP16));
    prog_s(b+29, bundle(NOP32, NOP32, NOP32, s3_f(`CRP_F4E, 3'd5, 2'd0, 2'd2), NOP16));
    prog_s(b+32, bundle(NOP32, NOP32, NOP32, s3_f(`CRP_F4E, 3'd5, 2'd0, 2'd3), NOP16));
    // Guardar el resultado en 0x40 y 0x44
    prog_s(b+35, bundle(NOP32, NOP32, a_rri(`LSU_SW, 4'd10, 4'd0, 64), NOP16, NOP16));
    prog_s(b+36, bundle(NOP32, NOP32, a_rri(`LSU_SW, 4'd11, 4'd0, 68), NOP16, NOP16));
    prog_s(b+37, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+38, bundle(NOP32, NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(300);

    check1 ("la sesion quedo abierta",   psw_s[`PSW_AUTH], 1'b1);
    check1 ("y sin AUTHFAIL",            psw_s[`PSW_AUTHFAIL], 1'b0);
    check1 ("sin fallas en el PSW",      psw_s[`PSW_EXC], 1'b0);
    check32("la mitad L cifrada",        regs_s[10], CIFRA_L);
    check32("la mitad R cifrada",        regs_s[11], CIFRA_R);
    check32("L guardada en memoria",     dut.u_dmem.storage[16], CIFRA_L);
    check32("R guardada en memoria",     dut.u_dmem.storage[17], CIFRA_R);

    // Aislamiento: ninguna subllave puede haber quedado visible. Es el caso 6
    // del enunciado, y aqui se revisa la memoria entera y los 16 registros.
    tests_run = tests_run + 1;
    i = 0;
    for (b = 0; b < N_WORDS; b = b + 1)
      if (dut.u_dmem.storage[b] === LLAVE0 || dut.u_dmem.storage[b] === LLAVE1 ||
          dut.u_dmem.storage[b] === LLAVE2 || dut.u_dmem.storage[b] === LLAVE3)
        if (b > 7) i = i + 1;    // 4..7 son las palabras que el programa cargo
    if (i != 0) begin
      tests_failed = tests_failed + 1;
      $display("  FALLA  hay %0d palabras de llave fuera de su sitio", i);
    end else begin
      $display("  ok     ninguna subllave se filtro a la memoria");
    end

    // ========================================================================
    $display("");
    $display("[P5] la misma rutina fuera de la region segura");
    // ========================================================================
    // El mismo codigo en la instancia que arranca en cero. KSETW y F4E son
    // privilegiadas y exigen AUTH y estar dentro de la region, asi que aqui
    // deben ser denegadas y el bloque tiene que salir intacto.

    for (i = 0; i < N_BUNDLES; i = i + 1)
      dut_fuera.u_imem.storage[i] = {`BUNDLE_W{1'b0}};
    for (i = 0; i < N_WORDS; i = i + 1) dato_i(i, 32'd0);
    dato_i(0, CRED0);  dato_i(1, CRED1);  dato_i(2, CRED2);  dato_i(3, CRED3);
    dato_i(4, LLAVE0); dato_i(5, LLAVE1); dato_i(6, LLAVE2); dato_i(7, LLAVE3);
    dato_i(8, CLARO_L); dato_i(9, CLARO_R);

    // Se copia el programa seguro al principio de la otra memoria
    for (i = 0; i <= 38; i = i + 1)
      dut_fuera.u_imem.storage[i] = dut.u_imem.storage[BASE_S + i];

    reiniciar();
    i = 0;
    while (!halted_i && i < 300) begin
      @(posedge clk);
      i = i + 1;
    end
    repeat (6) @(posedge clk);
    #1;

    check1 ("la sesion NO se abrio fuera de la region", psw_i[`PSW_AUTH], 1'b0);
    check1 ("el PSW registra una falla",                psw_i[`PSW_EXC], 1'b1);
    check3 ("y la causa es DENIED",  psw_i[`PSW_CAUSE], `CAUSE_DENIED);
    check32("la mitad L quedo sin cifrar",              regs_i[10], CLARO_L);
    check32("la mitad R quedo sin cifrar",              regs_i[11], CLARO_R);

    // ========================================================================
    $display("");
    $display("[P6] fallas: opcode reservado de S3 y acceso desalineado");
    // ========================================================================
    // El opcode 111 de S3 no lo reclama ninguna de las tres unidades del slot:
    // la boveda reconoce 001..101 y la ALU corta solo 110. Lo marca el top, y
    // este caso es el unico sitio donde eso se puede comprobar.

    limpiar_imem_s();
    b = BASE_S;
    prog_s(b+0, bundle(NOP32, NOP32, NOP32, {`CRP_RSV, 13'd0}, NOP16));
    prog_s(b+3, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+4, bundle(NOP32, NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(100);

    check1 ("el opcode reservado de S3 levanta una falla", psw_s[`PSW_EXC], 1'b1);
    check3 ("y la causa es ILLOP", psw_s[`PSW_CAUSE], `CAUSE_ILLOP);

    // Acceso desalineado: lw con desplazamiento impar
    limpiar_imem_s();
    b = BASE_S;
    prog_s(b+0, bundle(a_rri(`ALU_MOVI, 4'd1, 4'd0, 2), NOP32, NOP32, NOP16, NOP16));
    prog_s(b+3, bundle(NOP32, NOP32, a_rri(`LSU_LW, 4'd2, 4'd1, 0), NOP16, NOP16));
    prog_s(b+6, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+7, bundle(NOP32, NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(100);

    check1 ("un lw desalineado levanta una falla", psw_s[`PSW_EXC], 1'b1);
    check3 ("y la causa es MISALIGN", psw_s[`PSW_CAUSE], `CAUSE_MISALIGN);
    check32("y la carga se anulo",    regs_s[2], 32'd0);

    // ========================================================================
    $display("");
    $display("[P7] un bundle sin operaciones no hace nada");
    // ========================================================================
    // Comprueba la responsabilidad 1 del top: alu.sv no tiene entrada valid, asi
    // que si el top no la gateara, los bundles que siguen a HALT escribirian
    // registros.
    //
    // El detalle que hace falta para que la prueba sirva: despues de HALT el
    // contador queda CONGELADO en la direccion del delay slot, asi que la
    // memoria entrega ese mismo bundle una y otra vez. Si el delay slot
    // escribiera una constante, repetirlo cien veces daria el mismo valor y el
    // error seria invisible. Por eso lleva una operacion ACUMULATIVA: con el
    // gateo se ejecuta exactamente una vez y r7 queda en 1; sin el, r7 crece
    // mientras la simulacion siga corriendo.

    limpiar_imem_s();
    b = BASE_S;
    prog_s(b+0, bundle(NOP32, NOP32, NOP32, NOP16, HALT));
    prog_s(b+1, bundle(a_rri(`ALU_ADDI, 4'd7, 4'd7, 1), NOP32, NOP32, NOP16, NOP16));

    reiniciar();
    correr_hasta_halt(100);
    repeat (30) @(posedge clk);
    #1;

    check32("el delay slot de HALT se ejecuto una sola vez", regs_s[7], 32'd1);
    check1 ("sin fallas de bundles inexistentes", psw_s[`PSW_EXC], 1'b0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("");
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'd0, 32'd1);
`endif

    $display("");
    resumen();
  end

endmodule
