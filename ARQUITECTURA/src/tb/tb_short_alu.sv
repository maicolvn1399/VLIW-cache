`timescale 1ns/1ps

// =============================================================================
// tb_short_alu.sv - Testbench de la ALU corta.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// SystemVerilog plano: Icarus no soporta clases ni aleatorizacion, asi que los
// casos son tareas con valores esperados explicitos y un contador de errores.
//
// Los valores esperados son CONSTANTES escritas a mano. El testbench nunca
// recalcula la operacion: si lo hiciera, un error en la formula apareceria en
// el modulo y en la prueba a la vez, y el caso pasaria.
//
// No hay reloj: la unidad es combinacional.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto, para comprobar que el arnes sabe reportar una
// falla en lugar de pasar siempre por construccion.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. La unidad se queda callada cuando el slot le pertenece a otra unidad
//   2. Las ocho suboperaciones con operando de registro
//   3. Las seis suboperaciones con inmediato, que es SIN signo
//   4. Aritmetica envolvente de 32 bits
//   5. Las unarias operan sobre rd y no sobre el segundo operando
//   6. ILLOP: unaria con inmediato, bit reservado sucio, fuente no usada
//   7. Anulacion completa ante falla
// =============================================================================

`include "cerbero_defs.svh"

module tb_short_alu;

  // --- interfaz del DUT ---
  logic [15:0] slot;
  logic        valid;
  logic [3:0]  rd_idx, rs2_idx;
  logic [31:0] rd_val, rs2_val;
  logic        wr_en, fault;
  logic [31:0] result;
  logic [2:0]  cause;

  short_alu dut (
      .slot    (slot),
      .valid   (valid),
      .rd_idx  (rd_idx),
      .rs2_idx (rs2_idx),
      .rd_val  (rd_val),
      .rs2_val (rs2_val),
      .wr_en   (wr_en),
      .result  (result),
      .fault   (fault),
      .cause   (cause)
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
        $display("  FALLA  %-40s obtenido %08h, esperado %08h",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  task automatic check4(input string nombre,
                        input logic [3:0] obtenido,
                        input logic [3:0] esperado);
    begin
      tests_run = tests_run + 1;
      if (obtenido !== esperado) begin
        tests_failed = tests_failed + 1;
        $display("  FALLA  %-40s obtenido %b, esperado %b",
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
        $display("  FALLA  %-40s obtenido %b, esperado %b",
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
        $display("  FALLA  %-40s obtenido %b, esperado %b",
                 nombre, obtenido, esperado);
      end else begin
        $display("  ok     %s", nombre);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Construccion del slot (tipo AC)
  //
  //   [15:13] opcode | [12] i | [11:9] subop | [8:5] rd | [4:0] operando
  // ---------------------------------------------------------------------------

  function automatic logic [15:0] mk_ac(input logic       i,
                                        input logic [2:0] subop,
                                        input logic [3:0] rd,
                                        input logic [4:0] op2);
    mk_ac = {`CRP_SALU, i, subop, rd, op2};
  endfunction

  // ---------------------------------------------------------------------------
  // Aplicacion de estimulo
  // ---------------------------------------------------------------------------

  task automatic aplicar(input logic [15:0] s,
                         input logic [31:0] a,
                         input logic [31:0] b);
    begin
      valid   = 1'b1;
      slot    = s;
      rd_val  = a;
      rs2_val = b;
      #1;
    end
  endtask

  // Un caso con operando de registro. El campo de operando lleva el indice del
  // registro fuente en los cuatro bits bajos y el bit 4 en cero.
  task automatic check_reg(input string       nombre,
                           input logic [2:0]  subop,
                           input logic [31:0] a,
                           input logic [31:0] b,
                           input logic [31:0] esperado);
    begin
      aplicar(mk_ac(1'b0, subop, 4'd3, {1'b0, 4'd7}), a, b);
      check32({nombre, ": resultado"},     result, esperado);
      check1 ({nombre, ": habilita"},      wr_en,  1'b1);
      check1 ({nombre, ": sin falla"},     fault,  1'b0);
    end
  endtask

  // Un caso con inmediato
  task automatic check_imm(input string       nombre,
                           input logic [2:0]  subop,
                           input logic [31:0] a,
                           input logic [4:0]  imm,
                           input logic [31:0] esperado);
    begin
      aplicar(mk_ac(1'b1, subop, 4'd3, imm), a, 32'hDEADBEEF);
      check32({nombre, ": resultado"}, result, esperado);
      check1 ({nombre, ": habilita"},  wr_en,  1'b1);
      check1 ({nombre, ": sin falla"}, fault,  1'b0);
    end
  endtask

  // Un caso de falla: la causa y la anulacion completa
  task automatic check_falla(input string       nombre,
                             input logic [15:0] s);
    begin
      aplicar(s, 32'h1234_5678, 32'h8765_4321);
      check1 ({nombre, ": levanta falla"},  fault,  1'b1);
      check3 ({nombre, ": causa"},          cause,  `CAUSE_ILLOP);
      check1 ({nombre, ": no habilita"},    wr_en,  1'b0);
      check32({nombre, ": resultado nulo"}, result, 32'd0);
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

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_short_alu.vcd");
      $dumpvars(0, tb_short_alu);
    end

    valid = 1'b0; slot = 16'd0; rd_val = 32'd0; rs2_val = 32'd0;
    #1;

    $display("=== tb_short_alu: ALU corta del slot S3 ===");

    // ------------------------------------------------------------------------
    $display("[el slot le pertenece a otra unidad]");
    // ------------------------------------------------------------------------
    // Con cualquier opcode distinto de 110 el slot es de la unidad Feistel4 o
    // de la boveda. La ALU corta no debe escribir ni fallar: si lo hiciera,
    // toda ronda de cifrado arrastraria una escritura espuria.
    aplicar({`CRP_F4E, 13'h1FFF}, 32'hAAAA_AAAA, 32'h5555_5555);
    check1 ("F4E: no habilita",  wr_en, 1'b0);
    check1 ("F4E: no falla",     fault, 1'b0);
    check32("F4E: resultado nulo", result, 32'd0);

    aplicar({`CRP_VCTL, 13'h1FFF}, 32'hAAAA_AAAA, 32'h5555_5555);
    check1("VCTL: no habilita", wr_en, 1'b0);
    check1("VCTL: no falla",    fault, 1'b0);

    aplicar({`CRP_NOP, 13'd0}, 32'hAAAA_AAAA, 32'h5555_5555);
    check1("NOP: no habilita", wr_en, 1'b0);
    check1("NOP: no falla",    fault, 1'b0);

    // ------------------------------------------------------------------------
    $display("[suboperaciones con operando de registro]");
    // ------------------------------------------------------------------------
    check_reg("ADD.S", `SALU_ADD, 32'h0000_000F, 32'h0000_0003, 32'h0000_0012);
    check_reg("SUB.S", `SALU_SUB, 32'h0000_000F, 32'h0000_0003, 32'h0000_000C);
    check_reg("AND.S", `SALU_AND, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'hF000_F000);
    check_reg("OR.S",  `SALU_OR,  32'hF0F0_F0F0, 32'h0F0F_0F0F, 32'hFFFF_FFFF);
    check_reg("XOR.S", `SALU_XOR, 32'hAAAA_AAAA, 32'hFFFF_FFFF, 32'h5555_5555);
    check_reg("MOV.S", `SALU_MOV, 32'h0000_000F, 32'hCAFE_BABE, 32'hCAFE_BABE);

    // ------------------------------------------------------------------------
    $display("[aritmetica envolvente de 32 bits]");
    // ------------------------------------------------------------------------
    // Es la misma envolvente que exige la suma modular de la funcion de ronda.
    check_reg("ADD.S envolvente", `SALU_ADD,
              32'hFFFF_FFFF, 32'h0000_0002, 32'h0000_0001);
    check_reg("SUB.S por debajo de cero", `SALU_SUB,
              32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF);

    // ------------------------------------------------------------------------
    $display("[las unarias operan sobre rd, no sobre el segundo operando]");
    // ------------------------------------------------------------------------
    // El formato es destructivo y rd es a la vez fuente y destino, asi que el
    // campo de registro fuente no participa y debe ir en cero.
    aplicar(mk_ac(1'b0, `SALU_NOT, 4'd3, 5'd0), 32'h0F0F_0F0F, 32'hAAAA_AAAA);
    check32("NOT.S niega rd",  result, 32'hF0F0_F0F0);
    check1 ("NOT.S habilita",  wr_en,  1'b1);
    check1 ("NOT.S sin falla", fault,  1'b0);

    aplicar(mk_ac(1'b0, `SALU_NEG, 4'd3, 5'd0), 32'h0000_0005, 32'hAAAA_AAAA);
    check32("NEG.S niega rd",  result, 32'hFFFF_FFFB);
    check1 ("NEG.S habilita",  wr_en,  1'b1);

    aplicar(mk_ac(1'b0, `SALU_NEG, 4'd3, 5'd0), 32'd0, 32'hAAAA_AAAA);
    check32("NEG.S de cero", result, 32'h0000_0000);

    // ------------------------------------------------------------------------
    $display("[suboperaciones con inmediato, que es SIN signo]");
    // ------------------------------------------------------------------------
    check_imm("ADDI.S", `SALU_ADD, 32'h0000_000F, 5'd5,  32'h0000_0014);
    check_imm("SUBI.S", `SALU_SUB, 32'h0000_000F, 5'd5,  32'h0000_000A);
    check_imm("ANDI.S", `SALU_AND, 32'hFFFF_FFFF, 5'd12, 32'h0000_000C);
    check_imm("ORI.S",  `SALU_OR,  32'h0000_0000, 5'd31, 32'h0000_001F);
    check_imm("XORI.S", `SALU_XOR, 32'h0000_00FF, 5'd15, 32'h0000_00F0);
    check_imm("MOVI.S", `SALU_MOV, 32'hCAFE_BABE, 5'd5,  32'h0000_0005);

    // El inmediato mas grande se extiende con CEROS, no con signo: 31 no es -1
    check_imm("el inmediato maximo no se extiende con signo", `SALU_MOV,
              32'd0, 5'd31, 32'h0000_001F);
    check_imm("ADDI.S con el inmediato maximo", `SALU_ADD,
              32'h0000_0001, 5'd31, 32'h0000_0020);

    // ------------------------------------------------------------------------
    $display("[el inmediato ignora el registro fuente y viceversa]");
    // ------------------------------------------------------------------------
    aplicar(mk_ac(1'b1, `SALU_ADD, 4'd3, 5'd5), 32'd10, 32'hFFFF_FFFF);
    check32("con i = 1 no se mira rs2", result, 32'd15);

    aplicar(mk_ac(1'b0, `SALU_ADD, 4'd3, {1'b0, 4'd9}), 32'd10, 32'd7);
    check32("con i = 0 no se mira el inmediato", result, 32'd17);

    // ------------------------------------------------------------------------
    $display("[los indices salen del slot]");
    // ------------------------------------------------------------------------
    aplicar(mk_ac(1'b0, `SALU_ADD, 4'd11, {1'b0, 4'd6}), 32'd1, 32'd2);
    check4("indice de destino",  rd_idx,  4'd11);
    check4("indice de la fuente", rs2_idx, 4'd6);

    // ------------------------------------------------------------------------
    $display("[ILLOP: unaria con inmediato, que es combinacion reservada]");
    // ------------------------------------------------------------------------
    // Devolver cero en silencio seria peor que fallar: el programa no se
    // enteraria de que pidio algo que no existe.
    check_falla("NOT.S con inmediato", mk_ac(1'b1, `SALU_NOT, 4'd3, 5'd5));
    check_falla("NEG.S con inmediato", mk_ac(1'b1, `SALU_NEG, 4'd3, 5'd5));

    // ------------------------------------------------------------------------
    $display("[ILLOP: bits reservados sucios]");
    // ------------------------------------------------------------------------
    // Con i = 0 el bit 4 del campo de operando no se usa
    check_falla("ADD.S con el bit 4 encendido",
                mk_ac(1'b0, `SALU_ADD, 4'd3, {1'b1, 4'd7}));
    check_falla("MOV.S con el bit 4 encendido",
                mk_ac(1'b0, `SALU_MOV, 4'd3, {1'b1, 4'd0}));

    // Con una unaria el campo de registro fuente tampoco se usa
    check_falla("NOT.S con fuente distinta de cero",
                mk_ac(1'b0, `SALU_NOT, 4'd3, {1'b0, 4'd5}));
    check_falla("NEG.S con fuente distinta de cero",
                mk_ac(1'b0, `SALU_NEG, 4'd3, {1'b0, 4'd1}));

    // ------------------------------------------------------------------------
    $display("[el slot sin emitir no falla ni escribe]");
    // ------------------------------------------------------------------------
    valid   = 1'b0;
    slot    = mk_ac(1'b1, `SALU_NOT, 4'd3, 5'd5);   // combinacion reservada
    rd_val  = 32'hFFFF_FFFF;
    rs2_val = 32'hFFFF_FFFF;
    #1;
    check1("sin emitir no levanta falla", fault, 1'b0);
    check3("sin emitir la causa es nula", cause, `CAUSE_NONE);
    check1("sin emitir no habilita",      wr_en, 1'b0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
