`timescale 1ns/1ps

// =============================================================================
// tb_dispatch.sv - Testbench de la etapa de decodificacion y despacho.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// El modulo hace dos cosas y las dos se pueden equivocar de forma silenciosa:
// rebanar el bundle y decidir que registro lee cada puerto. Un error de un bit
// en los limites de un slot, o un puerto que lee rs1 donde debia leer rd, no se
// nota hasta que un programa entero da un resultado raro.
//
// De ahi la seccion 1: en vez de probar unos cuantos bundles, recorre los 128
// bits del bundle uno por uno, enciende solo ese y comprueba que aparece en el
// slot que le toca y en la posicion que le toca. Eso cubre los cinco limites y
// los 128 bits, que es lo que hace falta para no volver a mirar el rebanado.
//
// Los valores esperados se escriben a mano. El testbench nunca vuelve a rebanar
// el bundle con los mismos macros que usa el modulo: si lo hiciera, un macro
// mal puesto apareceria en los dos lados y el caso pasaria.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Los 128 bits del bundle caen en el slot y la posicion correctos
//   2. Bundle nulo y bundle con todos los bits en uno
//   3. S0 y S1: rs1 en el puerto A, rs2 en el puerto B, independientes
//   4. MOVH lee rd en el puerto A, que es la unica excepcion del slot ALU
//   5. S2: rbase en el puerto A, dato en el puerto B, en load y en store
//   6. S3: las ocho codificaciones de par dan {par,0} y {par,1}
//   7. S3: ALU corta y boveda leen el campo [8:5] en el puerto A
//   8. S4: rs de JR y JALR
// =============================================================================

`include "cerbero_defs.svh"

module tb_dispatch;

  // ---------------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------------

  logic [`BUNDLE_W-1:0] bundle;
  logic [31:0]          s0_inst, s1_inst, s2_inst;
  logic [15:0]          s3_inst, s4_inst;
  logic [`NREAD_PORTS-1:0][`RIDX_W-1:0] ridx;

  dispatch dut (
      .bundle     (bundle),
      .s0_inst    (s0_inst),
      .s1_inst    (s1_inst),
      .s2_inst    (s2_inst),
      .s3_inst    (s3_inst),
      .s4_inst    (s4_inst),
      .read_index (ridx)
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
        $display("  FALLA  %-46s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  task automatic check16(input string nombre,
                         input logic [15:0] obtenido,
                         input logic [15:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido %04h, esperado %04h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  task automatic check_reg(input string nombre,
                           input logic [`RIDX_W-1:0] obtenido,
                           input logic [`RIDX_W-1:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-46s obtenido R%0d, esperado R%0d",
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
  // Constructores de instruccion
  //
  // Escritos con numeros literales y no con los macros de campo, para que el
  // testbench no herede un error de los macros.
  // ---------------------------------------------------------------------------

  function automatic logic [31:0] tipo_a(input logic [4:0] opc,
                                         input logic [3:0] rd,
                                         input logic [3:0] rs1,
                                         input logic [3:0] rs2);
    begin
      tipo_a = {opc, rd, rs1, rs2, 15'd0};
    end
  endfunction

  function automatic logic [31:0] tipo_i(input logic [4:0]  opc,
                                          input logic [3:0]  rd,
                                          input logic [3:0]  rs1,
                                          input logic [18:0] imm);
    begin
      tipo_i = {opc, rd, rs1, imm};
    end
  endfunction

  // Tipo F: opcode | par | kv | ronda | reservado
  function automatic logic [15:0] tipo_f(input logic [2:0] opc,
                                          input logic [2:0] par,
                                          input logic [1:0] kv,
                                          input logic [1:0] ronda);
    begin
      tipo_f = {opc, par, kv, ronda, 6'd0};
    end
  endfunction

  // Tipo AC: opcode | i | subop | rd | rs2 o imm5
  function automatic logic [15:0] tipo_ac(input logic       i,
                                           input logic [2:0] subop,
                                           input logic [3:0] rd,
                                           input logic [4:0] op2);
    begin
      tipo_ac = {3'b110, i, subop, rd, op2};
    end
  endfunction

  // Tipo V: opcode | [12:11] | [10:9] | rs | reservado
  function automatic logic [15:0] tipo_v(input logic [2:0] opc,
                                          input logic [1:0] alto,
                                          input logic [1:0] medio,
                                          input logic [3:0] rs);
    begin
      tipo_v = {opc, alto, medio, rs, 5'd0};
    end
  endfunction

  // Tipo J: opcode | cond | reservado | rs | reservado
  function automatic logic [15:0] tipo_j(input logic [2:0] opc,
                                          input logic [2:0] cond,
                                          input logic [3:0] rs);
    begin
      tipo_j = {opc, cond, 1'b0, rs, 5'd0};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i, malos;
  logic [2:0] par_v;
  integer esperado_slot, obtenido_slot;
  integer esperado_pos,  obtenido_pos;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_dispatch.vcd");
      $dumpvars(0, tb_dispatch);
    end

    $display("=== tb_dispatch: etapa de decodificacion y despacho ===");

    // ------------------------------------------------------------------------
    $display("[1] los 128 bits caen donde deben");
    // ------------------------------------------------------------------------
    // Para cada posicion se enciende un solo bit del bundle y se busca en que
    // slot aparecio y en que posicion dentro de ese slot. El reparto que fija
    // isa.md 2.3 es S0 en 127:96, S1 en 95:64, S2 en 63:32, S3 en 31:16 y S4 en
    // 15:0, asi que el bit n del bundle es:
    //
    //   n >= 96  -> S0, posicion n - 96
    //   n >= 64  -> S1, posicion n - 64
    //   n >= 32  -> S2, posicion n - 32
    //   n >= 16  -> S3, posicion n - 16
    //   resto    -> S4, posicion n

    malos = 0;
    for (i = 0; i < 128; i = i + 1) begin
      bundle = {`BUNDLE_W{1'b0}};
      bundle[i] = 1'b1;
      #1;

      if      (i >= 96) begin esperado_slot = 0; esperado_pos = i - 96; end
      else if (i >= 64) begin esperado_slot = 1; esperado_pos = i - 64; end
      else if (i >= 32) begin esperado_slot = 2; esperado_pos = i - 32; end
      else if (i >= 16) begin esperado_slot = 3; esperado_pos = i - 16; end
      else              begin esperado_slot = 4; esperado_pos = i;      end

      // Que slot quedo distinto de cero, y en que bit
      obtenido_slot = -1;
      obtenido_pos  = -1;
      if (s0_inst != 0) begin obtenido_slot = 0; obtenido_pos = $clog2(s0_inst); end
      if (s1_inst != 0) begin obtenido_slot = 1; obtenido_pos = $clog2(s1_inst); end
      if (s2_inst != 0) begin obtenido_slot = 2; obtenido_pos = $clog2(s2_inst); end
      if (s3_inst != 0) begin obtenido_slot = 3; obtenido_pos = $clog2(s3_inst); end
      if (s4_inst != 0) begin obtenido_slot = 4; obtenido_pos = $clog2(s4_inst); end

      if (obtenido_slot != esperado_slot || obtenido_pos != esperado_pos) begin
        malos = malos + 1;
        if (malos <= 5)
          $display("         bit %0d: esperaba S%0d[%0d], llego a S%0d[%0d]",
                   i, esperado_slot, esperado_pos, obtenido_slot, obtenido_pos);
      end
    end
    check_int("los 128 bits aparecen en su slot y su posicion", malos, 0);

    // ------------------------------------------------------------------------
    $display("[2] bundle nulo y bundle lleno");
    // ------------------------------------------------------------------------

    bundle = {`BUNDLE_W{1'b0}};
    #1;
    check32("S0 de un bundle nulo", s0_inst, 32'h0000_0000);
    check32("S1 de un bundle nulo", s1_inst, 32'h0000_0000);
    check32("S2 de un bundle nulo", s2_inst, 32'h0000_0000);
    check16("S3 de un bundle nulo", s3_inst, 16'h0000);
    check16("S4 de un bundle nulo", s4_inst, 16'h0000);

    bundle = {`BUNDLE_W{1'b1}};
    #1;
    check32("S0 de un bundle lleno", s0_inst, 32'hFFFF_FFFF);
    check32("S1 de un bundle lleno", s1_inst, 32'hFFFF_FFFF);
    check32("S2 de un bundle lleno", s2_inst, 32'hFFFF_FFFF);
    check16("S3 de un bundle lleno", s3_inst, 16'hFFFF);
    check16("S4 de un bundle lleno", s4_inst, 16'hFFFF);

    // ------------------------------------------------------------------------
    $display("[3] S0 y S1: rs1 al puerto A, rs2 al puerto B");
    // ------------------------------------------------------------------------
    // add r1, r2, r3  en S0  y  xor r4, r5, r6  en S1. Los seis registros son
    // distintos para que un cruce de puertos no pueda pasar inadvertido.

    bundle = { tipo_a(5'b00001, 4'd1, 4'd2, 4'd3),     // S0: add r1,r2,r3
               tipo_a(5'b00110, 4'd4, 4'd5, 4'd6),     // S1: xor r4,r5,r6
               32'h0000_0000,
               16'h0000,
               16'h0000 };
    #1;
    check32("S0 extraido", s0_inst, tipo_a(5'b00001, 4'd1, 4'd2, 4'd3));
    check32("S1 extraido", s1_inst, tipo_a(5'b00110, 4'd4, 4'd5, 4'd6));
    check_reg("puerto A de S0 lee rs1", ridx[`RP_S0_A], 4'd2);
    check_reg("puerto B de S0 lee rs2", ridx[`RP_S0_B], 4'd3);
    check_reg("puerto A de S1 lee rs1", ridx[`RP_S1_A], 4'd5);
    check_reg("puerto B de S1 lee rs2", ridx[`RP_S1_B], 4'd6);

    // ------------------------------------------------------------------------
    $display("[4] MOVH lee rd en el puerto A");
    // ------------------------------------------------------------------------
    // Es la unica excepcion del slot ALU: MOVH conserva la mitad baja de rd, asi
    // que necesita su valor actual. Su campo rs1 esta reservado en cero, de modo
    // que un puerto A que leyera rs1 traeria R0 y el bug seria casi invisible:
    // el programa veria la mitad baja en ceros en vez de la que tenia. Aqui el
    // campo rs1 se pone distinto de cero a proposito para separar los dos casos.

    bundle = { tipo_i(5'b11101, 4'd9, 4'd7, 19'h0_1234),  // S0: movh r9 (rs1=7)
               tipo_i(5'b11101, 4'd3, 4'd0, 19'h0_5678),  // S1: movh r3 (rs1=0)
               32'h0000_0000, 16'h0000, 16'h0000 };
    #1;
    check_reg("puerto A de S0 lee rd en MOVH",   ridx[`RP_S0_A], 4'd9);
    check_reg("puerto A de S1 lee rd en MOVH",   ridx[`RP_S1_A], 4'd3);

    // Y que no sea que el puerto A lee rd siempre: con un ADD vuelve a rs1
    bundle = { tipo_a(5'b00001, 4'd9, 4'd7, 4'd0),
               32'h0000_0000, 32'h0000_0000, 16'h0000, 16'h0000 };
    #1;
    check_reg("con ADD el puerto A vuelve a rs1", ridx[`RP_S0_A], 4'd7);

    // ------------------------------------------------------------------------
    $display("[5] S2: rbase al puerto A, dato al puerto B");
    // ------------------------------------------------------------------------
    // En un load el campo [26:23] es el destino y en un store es la fuente del
    // dato. El enrutado de lectura es el mismo en los dos casos, porque leer un
    // registro que no se va a usar no tiene efecto.

    bundle = { 32'h0000_0000, 32'h0000_0000,
               tipo_i(5'b00000, 4'd11, 4'd12, 19'h0_0004),   // lw r11, 4(r12)
               16'h0000, 16'h0000 };
    #1;
    check_reg("puerto A de S2 lee rbase en un load", ridx[`RP_S2_A], 4'd12);
    check_reg("puerto B de S2 lee el campo de dato", ridx[`RP_S2_B], 4'd11);

    bundle = { 32'h0000_0000, 32'h0000_0000,
               tipo_i(5'b01010, 4'd13, 4'd14, 19'h0_0008),   // sw r13, 8(r14)
               16'h0000, 16'h0000 };
    #1;
    check_reg("puerto A de S2 lee rbase en un store", ridx[`RP_S2_A], 4'd14);
    check_reg("puerto B de S2 lee el dato del store", ridx[`RP_S2_B], 4'd13);

    // ------------------------------------------------------------------------
    $display("[6] S3: las ocho codificaciones de par");
    // ------------------------------------------------------------------------
    // Pn = R(2n) : R(2n+1), con L en el registro par y R en el impar. Se
    // recorren los ocho pares con F4E y los ocho con F4D.

    malos = 0;
    for (i = 0; i < 8; i = i + 1) begin
      par_v = i[2:0];
      bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
                 tipo_f(3'b001, par_v, 2'd0, 2'd0),      // f4e
                 16'h0000 };
      #1;
      if (ridx[`RP_S3_A] !== (2*i)     ) malos = malos + 1;
      if (ridx[`RP_S3_B] !== (2*i + 1) ) malos = malos + 1;

      bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
                 tipo_f(3'b010, par_v, 2'd3, 2'd3),      // f4d
                 16'h0000 };
      #1;
      if (ridx[`RP_S3_A] !== (2*i)     ) malos = malos + 1;
      if (ridx[`RP_S3_B] !== (2*i + 1) ) malos = malos + 1;
    end
    check_int("los 8 pares dan {par,0} y {par,1} en F4E y F4D", malos, 0);

    // Un caso explicito, para que quede a la vista en la salida
    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
               tipo_f(3'b001, 3'd5, 2'd1, 2'd2),          // f4e p5, k1, #2
               16'h0000 };
    #1;
    check_reg("P5 pone R10 en el puerto A", ridx[`RP_S3_A], 4'd10);
    check_reg("P5 pone R11 en el puerto B", ridx[`RP_S3_B], 4'd11);

    // ------------------------------------------------------------------------
    $display("[7] S3: ALU corta y boveda leen [8:5]");
    // ------------------------------------------------------------------------
    // Las tres unidades de S3 se excluyen entre si, asi que comparten los dos
    // puertos. El campo de registro principal esta en [8:5] en los dos formatos
    // cortos que lo usan, que es lo que fija isa.md 2.6.

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
               tipo_ac(1'b0, 3'b000, 4'd6, 5'b0_0111),    // add.s r6, r7
               16'h0000 };
    #1;
    check_reg("ALU corta: puerto A lee rd",  ridx[`RP_S3_A], 4'd6);
    check_reg("ALU corta: puerto B lee rs2", ridx[`RP_S3_B], 4'd7);

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
               tipo_ac(1'b1, 3'b000, 4'd6, 5'd31),        // add.s r6, #31
               16'h0000 };
    #1;
    check_reg("ALU corta con inmediato: puerto A sigue en rd",
              ridx[`RP_S3_A], 4'd6);

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
               tipo_v(3'b011, 2'd1, 2'd2, 4'd8),          // ksetw k1,#2, r8
               16'h0000 };
    #1;
    check_reg("KSETW: puerto A lee rs", ridx[`RP_S3_A], 4'd8);

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
               tipo_v(3'b100, 2'd0, 2'd3, 4'd4),          // authw #3, r4
               16'h0000 };
    #1;
    check_reg("AUTHW: puerto A lee rs", ridx[`RP_S3_A], 4'd4);

    // ------------------------------------------------------------------------
    $display("[8] S4: rs de los saltos indirectos");
    // ------------------------------------------------------------------------

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 16'h0000,
               tipo_j(3'b011, 3'b000, 4'd15) };           // jr r15
    #1;
    check_reg("JR lee rs", ridx[`RP_S4], 4'd15);

    bundle = { 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 16'h0000,
               tipo_j(3'b100, 3'b001, 4'd2) };            // jalr.eq r2
    #1;
    check_reg("JALR lee rs", ridx[`RP_S4], 4'd2);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
