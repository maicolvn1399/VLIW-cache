`timescale 1ns/1ps

// =============================================================================
// tb_lsu.sv - Testbench de la unidad de acceso a memoria.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// SystemVerilog plano: Icarus no soporta clases ni aleatorizacion, asi que los
// casos son tareas con valores esperados explicitos y un contador de errores.
//
// Los valores esperados son CONSTANTES escritas a mano, calculadas fuera del
// simulador. El testbench nunca recalcula la direccion efectiva ni la
// extension de signo: si lo hiciera, un error en la formula apareceria en el
// modulo y en la prueba a la vez, y el caso pasaria.
//
// No hay reloj: la unidad es combinacional, asi que los casos avanzan con
// retardos simples.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto, para comprobar que el arnes sabe reportar una
// falla en lugar de pasar siempre por construccion.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Operacion nula
//   2. Cargas: palabra, media palabra y byte, con y sin signo, en los cuatro
//      carriles
//   3. Almacenamientos: mascara de bytes y alineacion del dato en el carril
//   4. Desplazamiento con signo, positivo y negativo
//   5. Postincremento: la direccion es la base pura y el puntero avanza
//   6. Caso limite de LW.INC con rd igual a rbase
//   7. ILLOP sobre las tres familias de opcode reservado
//   8. MISALIGN en palabra y media palabra
//   9. RANGE por encima del limite y por envolvente hacia abajo
//  10. Prioridad de causas e independencia de la senal de emision
// =============================================================================

`include "cerbero_defs.svh"

module tb_lsu;

  // --- interfaz del DUT ---
  logic [31:0] slot;
  logic        valid;
  logic [3:0]  rd_idx, rbase_idx;
  logic [31:0] rbase_val, rs_data_val, mem_read_data;
  logic [31:0] eff_addr, mem_write_data, rd_load_data, rbase_updated;
  logic        mem_we, rd_write_en, rbase_write_en, fault;
  logic [3:0]  byte_enable;
  logic [2:0]  cause;

  lsu dut (
      .slot           (slot),
      .valid          (valid),
      .rd_idx         (rd_idx),
      .rbase_idx      (rbase_idx),
      .rbase_val      (rbase_val),
      .rs_data_val    (rs_data_val),
      .eff_addr       (eff_addr),
      .mem_write_data (mem_write_data),
      .mem_we         (mem_we),
      .byte_enable    (byte_enable),
      .mem_read_data  (mem_read_data),
      .rd_write_en    (rd_write_en),
      .rd_load_data   (rd_load_data),
      .rbase_write_en (rbase_write_en),
      .rbase_updated  (rbase_updated),
      .fault          (fault),
      .cause          (cause)
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

  task automatic check4(input string nombre,
                        input logic [3:0] obtenido,
                        input logic [3:0] esperado);
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
  // Construccion del slot (tipo M)
  //
  //   [31:27] opcode | [26:23] rd / rs_dato | [22:19] rbase | [18:0] imm19
  // ---------------------------------------------------------------------------

  function automatic logic [31:0] mk_m(input logic [4:0]  op,
                                       input logic [3:0]  rd,
                                       input logic [3:0]  rb,
                                       input logic [18:0] imm);
    mk_m = {op, rd, rb, imm};
  endfunction

  // ---------------------------------------------------------------------------
  // Carriles habilitados de un almacenamiento
  //
  // La unidad replica el dato en los cuatro carriles y deja que la mascara
  // decida cual se escribe. Comparar la palabra entera ataria la prueba a esa
  // decision; comparar solo los carriles habilitados comprueba lo unico que
  // de verdad importa, que es lo que la memoria va a escribir.
  // ---------------------------------------------------------------------------

  function automatic logic [31:0] enmascarar(input logic [31:0] d,
                                             input logic [3:0]  be);
    enmascarar = { be[3] ? d[31:24] : 8'd0,
                   be[2] ? d[23:16] : 8'd0,
                   be[1] ? d[15:8]  : 8'd0,
                   be[0] ? d[7:0]   : 8'd0 };
  endfunction

  // ---------------------------------------------------------------------------
  // Aplicacion de estimulo. El modulo es combinacional, basta un retardo.
  // ---------------------------------------------------------------------------

  task automatic aplicar(input logic [31:0] s,
                         input logic [31:0] base,
                         input logic [31:0] dato,
                         input logic [31:0] mem);
    begin
      valid         = 1'b1;
      slot          = s;
      rbase_val     = base;
      rs_data_val   = dato;
      mem_read_data = mem;
      #1;
    end
  endtask

  // Un caso de carga completo: direccion, dato extendido y habilitadores
  task automatic check_load(input string       nombre,
                            input logic [4:0]  op,
                            input logic [31:0] base,
                            input logic [18:0] imm,
                            input logic [31:0] mem,
                            input logic [31:0] ea_esp,
                            input logic [31:0] dato_esp);
    begin
      aplicar(mk_m(op, 4'd1, 4'd2, imm), base, 32'd0, mem);
      check32({nombre, ": direccion"},           eff_addr,     ea_esp);
      check32({nombre, ": dato"},                rd_load_data, dato_esp);
      check1 ({nombre, ": escribe rd"},          rd_write_en,  1'b1);
      check1 ({nombre, ": no escribe memoria"},  mem_we,       1'b0);
      check1 ({nombre, ": sin falla"},           fault,        1'b0);
    end
  endtask

  // Un caso de almacenamiento completo: mascara, carril y habilitadores
  task automatic check_store(input string       nombre,
                             input logic [4:0]  op,
                             input logic [31:0] base,
                             input logic [18:0] imm,
                             input logic [31:0] dato,
                             input logic [31:0] ea_esp,
                             input logic [3:0]  be_esp,
                             input logic [31:0] wdato_esp);
    begin
      aplicar(mk_m(op, 4'd1, 4'd2, imm), base, dato, 32'd0);
      check32({nombre, ": direccion"},         eff_addr,       ea_esp);
      check4 ({nombre, ": mascara de bytes"},  byte_enable,    be_esp);
      check32({nombre, ": carriles habilitados"},
              enmascarar(mem_write_data, byte_enable), wdato_esp);
      check1 ({nombre, ": escribe memoria"},   mem_we,         1'b1);
      check1 ({nombre, ": no escribe rd"},     rd_write_en,    1'b0);
      check1 ({nombre, ": sin falla"},         fault,          1'b0);
    end
  endtask

  // Un caso de falla: la causa y la anulacion completa
  task automatic check_falla(input string       nombre,
                             input logic [4:0]  op,
                             input logic [31:0] base,
                             input logic [18:0] imm,
                             input logic [2:0]  causa_esp);
    begin
      aplicar(mk_m(op, 4'd1, 4'd2, imm), base, 32'hCAFEBABE, 32'hDEADBEEF);
      check1 ({nombre, ": levanta falla"},        fault,          1'b1);
      check3 ({nombre, ": causa"},                cause,          causa_esp);
      check1 ({nombre, ": no escribe memoria"},   mem_we,         1'b0);
      check1 ({nombre, ": no escribe rd"},        rd_write_en,    1'b0);
      check1 ({nombre, ": no avanza el puntero"}, rbase_write_en, 1'b0);
      check4 ({nombre, ": mascara en cero"},      byte_enable,    4'b0000);
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
      $dumpfile("tb_lsu.vcd");
      $dumpvars(0, tb_lsu);
    end

    valid = 1'b0; slot = 32'd0;
    rbase_val = 32'd0; rs_data_val = 32'd0; mem_read_data = 32'd0;
    #1;

    $display("=== tb_lsu: unidad de acceso a memoria ===");

    // ------------------------------------------------------------------------
    $display("[la operacion nula no hace nada y no falla]");
    // ------------------------------------------------------------------------
    aplicar(mk_m(`LSU_NOP, 4'd5, 4'd6, 19'h7FFFF), 32'hFFFFFFFF, 32'hFFFFFFFF,
            32'hFFFFFFFF);
    check1 ("NOP no escribe memoria",   mem_we,         1'b0);
    check1 ("NOP no escribe rd",        rd_write_en,    1'b0);
    check1 ("NOP no avanza el puntero", rbase_write_en, 1'b0);
    check1 ("NOP no falla",             fault,          1'b0);
    check32("NOP no entrega dato",      rd_load_data,   32'd0);

    // ------------------------------------------------------------------------
    $display("[cargas de palabra]");
    // ------------------------------------------------------------------------
    check_load("LW con desplazamiento", `LSU_LW,
               32'h0000_1000, 19'd4, 32'hAABBCCDD, 32'h0000_1004, 32'hAABBCCDD);

    // 19'h7FFFC es -4 con extension de signo
    check_load("LW con desplazamiento negativo", `LSU_LW,
               32'h0000_1000, 19'h7FFFC, 32'h11223344, 32'h0000_0FFC, 32'h11223344);

    check_load("LW en el limite superior", `LSU_LW,
               32'h0000_FFFC, 19'd0, 32'h55667788, 32'h0000_FFFC, 32'h55667788);

    // ------------------------------------------------------------------------
    $display("[cargas de media palabra, los dos carriles y los dos signos]");
    // ------------------------------------------------------------------------
    check_load("LH carril bajo, positivo", `LSU_LH,
               32'h0000_1000, 19'd0, 32'hFFFF_7FFF, 32'h0000_1000, 32'h0000_7FFF);
    check_load("LH carril bajo, negativo", `LSU_LH,
               32'h0000_1000, 19'd0, 32'h0000_8001, 32'h0000_1000, 32'hFFFF_8001);
    check_load("LH carril alto, negativo", `LSU_LH,
               32'h0000_1002, 19'd0, 32'h8001_ABCD, 32'h0000_1002, 32'hFFFF_8001);
    check_load("LHU carril alto",          `LSU_LHU,
               32'h0000_1002, 19'd0, 32'h8001_ABCD, 32'h0000_1002, 32'h0000_8001);

    // ------------------------------------------------------------------------
    $display("[cargas de byte, los cuatro carriles]");
    // ------------------------------------------------------------------------
    check_load("LBU carril 0", `LSU_LBU,
               32'h0000_1000, 19'd0, 32'h8899AABB, 32'h0000_1000, 32'h0000_00BB);
    check_load("LBU carril 1", `LSU_LBU,
               32'h0000_1001, 19'd0, 32'h8899AABB, 32'h0000_1001, 32'h0000_00AA);
    check_load("LBU carril 2", `LSU_LBU,
               32'h0000_1002, 19'd0, 32'h8899AABB, 32'h0000_1002, 32'h0000_0099);
    check_load("LBU carril 3", `LSU_LBU,
               32'h0000_1003, 19'd0, 32'h8899AABB, 32'h0000_1003, 32'h0000_0088);
    check_load("LB carril 3, negativo", `LSU_LB,
               32'h0000_1003, 19'd0, 32'h8899AABB, 32'h0000_1003, 32'hFFFF_FF88);
    check_load("LB carril 0, positivo", `LSU_LB,
               32'h0000_1000, 19'd0, 32'h8899AA7F, 32'h0000_1000, 32'h0000_007F);

    // ------------------------------------------------------------------------
    $display("[almacenamientos]");
    // ------------------------------------------------------------------------
    check_store("SW", `LSU_SW,
                32'h0000_1000, 19'd8, 32'hCAFEBABE,
                32'h0000_1008, 4'b1111, 32'hCAFEBABE);
    check_store("SH carril bajo", `LSU_SH,
                32'h0000_1000, 19'd0, 32'h0000_BEEF,
                32'h0000_1000, 4'b0011, 32'h0000_BEEF);
    check_store("SH carril alto", `LSU_SH,
                32'h0000_1002, 19'd0, 32'h0000_BEEF,
                32'h0000_1002, 4'b1100, 32'hBEEF_0000);
    check_store("SB carril 0", `LSU_SB,
                32'h0000_1000, 19'd0, 32'h0000_00EF,
                32'h0000_1000, 4'b0001, 32'h0000_00EF);
    check_store("SB carril 1", `LSU_SB,
                32'h0000_1001, 19'd0, 32'h0000_00EF,
                32'h0000_1001, 4'b0010, 32'h0000_EF00);
    check_store("SB carril 2", `LSU_SB,
                32'h0000_1002, 19'd0, 32'h0000_00EF,
                32'h0000_1002, 4'b0100, 32'h00EF_0000);
    check_store("SB carril 3", `LSU_SB,
                32'h0000_1003, 19'd0, 32'h0000_00EF,
                32'h0000_1003, 4'b1000, 32'hEF00_0000);

    // ------------------------------------------------------------------------
    $display("[el dato se replica en los cuatro carriles]");
    // ------------------------------------------------------------------------
    // La unidad no corre el dato hacia su carril: lo replica y deja que la
    // mascara elija. El caso lo fija porque es un contrato con dmem.sv, que
    // DEBE honrar byte_enable. Una memoria que lo ignore va a parecer correcta
    // con SW, donde la mascara vale 1111, y va a corromper los bytes vecinos
    // en el primer SB.
    aplicar(mk_m(`LSU_SB, 4'd1, 4'd2, 19'd0), 32'h0000_1001, 32'h0000_00EF,
            32'd0);
    check32("SB replica el byte en la palabra", mem_write_data, 32'hEFEF_EFEF);
    check4 ("y solo habilita su carril",        byte_enable,    4'b0010);

    aplicar(mk_m(`LSU_SH, 4'd1, 4'd2, 19'd0), 32'h0000_1002, 32'h0000_BEEF,
            32'd0);
    check32("SH replica la media palabra", mem_write_data, 32'hBEEF_BEEF);
    check4 ("y habilita los dos carriles altos", byte_enable, 4'b1100);

    // ------------------------------------------------------------------------
    $display("[postincremento: la direccion es la base pura]");
    // ------------------------------------------------------------------------
    aplicar(mk_m(`LSU_LW_INC, 4'd1, 4'd2, 19'd4), 32'h0000_2000, 32'd0,
            32'h12345678);
    check32("LW.INC: el inmediato NO entra en la direccion", eff_addr,
            32'h0000_2000);
    check32("LW.INC: dato cargado",       rd_load_data,   32'h12345678);
    check1 ("LW.INC: escribe rd",         rd_write_en,    1'b1);
    check32("LW.INC: puntero avanzado",   rbase_updated,  32'h0000_2004);
    check1 ("LW.INC: habilita el avance", rbase_write_en, 1'b1);
    check1 ("LW.INC: sin falla",          fault,          1'b0);

    aplicar(mk_m(`LSU_SW_INC, 4'd1, 4'd2, 19'd4), 32'h0000_3000, 32'hDEADBEEF,
            32'd0);
    check32("SW.INC: direccion",          eff_addr,       32'h0000_3000);
    check32("SW.INC: dato",               mem_write_data, 32'hDEADBEEF);
    check4 ("SW.INC: mascara completa",   byte_enable,    4'b1111);
    check1 ("SW.INC: escribe memoria",    mem_we,         1'b1);
    check1 ("SW.INC: no escribe rd",      rd_write_en,    1'b0);
    check32("SW.INC: puntero avanzado",   rbase_updated,  32'h0000_3004);
    check1 ("SW.INC: habilita el avance", rbase_write_en, 1'b1);

    // Incremento negativo: recorrer un buffer hacia atras
    aplicar(mk_m(`LSU_LW_INC, 4'd1, 4'd2, 19'h7FFFC), 32'h0000_2000, 32'd0,
            32'd0);
    check32("LW.INC con incremento negativo", rbase_updated, 32'h0000_1FFC);

    // ------------------------------------------------------------------------
    $display("[caso limite: LW.INC con rd igual a rbase]");
    // ------------------------------------------------------------------------
    // Prevalece el dato cargado y el incremento se descarta, para que el
    // resultado no dependa del orden en que el arbitro atienda los dos
    // puertos de escritura de la unidad.
    aplicar(mk_m(`LSU_LW_INC, 4'd2, 4'd2, 19'd4), 32'h0000_2000, 32'd0,
            32'h12345678);
    check1 ("rd == rbase: gana el dato cargado",  rd_write_en,    1'b1);
    check1 ("rd == rbase: se descarta el avance", rbase_write_en, 1'b0);
    check32("rd == rbase: el dato es el leido",   rd_load_data,   32'h12345678);

    // Con un store no hay conflicto: rs_dato no es destino
    aplicar(mk_m(`LSU_SW_INC, 4'd2, 4'd2, 19'd4), 32'h0000_3000, 32'hAABBCCDD,
            32'd0);
    check1 ("SW.INC con rs == rbase si avanza", rbase_write_en, 1'b1);

    // ------------------------------------------------------------------------
    $display("[ILLOP: opcodes reservados]");
    // ------------------------------------------------------------------------
    // TAM = 00 no existe
    check_falla("TAM = 00 no esta definido", 5'b00001,
                32'h0000_1000, 19'd0, `CAUSE_ILLOP);
    // store con extension de ceros: no tiene sentido
    check_falla("store con U = 1", 5'b01011, 32'h0000_1000, 19'd0, `CAUSE_ILLOP);
    // postincremento que no es de palabra
    check_falla("LB.INC no esta definido", 5'b10010, 32'h0000_1000, 19'd0,
                `CAUSE_ILLOP);
    check_falla("SH.INC no esta definido", 5'b11100, 32'h0000_1000, 19'd0,
                `CAUSE_ILLOP);

    // ------------------------------------------------------------------------
    $display("[MISALIGN: alineacion natural obligatoria]");
    // ------------------------------------------------------------------------
    check_falla("LW en direccion +1", `LSU_LW, 32'h0000_1001, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("LW en direccion +2", `LSU_LW, 32'h0000_1002, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("LW en direccion +3", `LSU_LW, 32'h0000_1003, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("SW desalineado",     `LSU_SW, 32'h0000_1002, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("LH en direccion impar", `LSU_LH, 32'h0000_1001, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("SH en direccion impar", `LSU_SH, 32'h0000_1003, 19'd0,
                `CAUSE_MISALIGN);
    check_falla("LW.INC desalineado", `LSU_LW_INC, 32'h0000_2001, 19'd4,
                `CAUSE_MISALIGN);

    // El desplazamiento tambien puede desalinear una base alineada
    check_falla("LW alineado con desplazamiento impar", `LSU_LW,
                32'h0000_1000, 19'd1, `CAUSE_MISALIGN);

    // El byte nunca se desalinea
    aplicar(mk_m(`LSU_LB, 4'd1, 4'd2, 19'd0), 32'h0000_1003, 32'd0, 32'd0);
    check1("LB en direccion impar no falla", fault, 1'b0);

    // ------------------------------------------------------------------------
    $display("[RANGE: fuera de la memoria implementada]");
    // ------------------------------------------------------------------------
    check_falla("LW una palabra despues del limite", `LSU_LW,
                32'h0001_0000, 19'd0, `CAUSE_RANGE);
    check_falla("SW muy por encima del limite", `LSU_SW,
                32'h8000_0000, 19'd0, `CAUSE_RANGE);
    // Envolvente hacia abajo: base cero con desplazamiento negativo
    check_falla("LW con direccion envolvente", `LSU_LW,
                32'h0000_0000, 19'h7FFFC, `CAUSE_RANGE);

    // La ultima palabra implementada si es valida
    aplicar(mk_m(`LSU_LW, 4'd1, 4'd2, 19'd0), 32'h0000_FFFC, 32'd0, 32'd0);
    check1("LW en la ultima palabra no falla", fault, 1'b0);

    // ------------------------------------------------------------------------
    $display("[prioridad de causas]");
    // ------------------------------------------------------------------------
    // Opcode reservado Y direccion desalineada Y fuera de rango: gana ILLOP,
    // porque un opcode sin definir no tiene tamano y no se le puede juzgar la
    // alineacion.
    check_falla("opcode reservado gana sobre alineacion y rango", 5'b00001,
                32'h0001_0001, 19'd0, `CAUSE_ILLOP);

    // Desalineado Y fuera de rango: gana MISALIGN
    check_falla("alineacion gana sobre rango", `LSU_LW,
                32'h0001_0002, 19'd0, `CAUSE_MISALIGN);

    // ------------------------------------------------------------------------
    $display("[el slot sin emitir no falla ni escribe]");
    // ------------------------------------------------------------------------
    valid     = 1'b0;
    slot      = mk_m(5'b00001, 4'd1, 4'd2, 19'd0);   // opcode reservado
    rbase_val = 32'h0001_0001;                       // y direccion invalida
    #1;
    check1("sin emitir no levanta falla",   fault,          1'b0);
    check3("sin emitir la causa es nula",   cause,          `CAUSE_NONE);
    check1("sin emitir no escribe memoria", mem_we,         1'b0);
    check1("sin emitir no escribe rd",      rd_write_en,    1'b0);
    check1("sin emitir no avanza puntero",  rbase_write_en, 1'b0);

    // Los indices salen siempre, tambien sin emitir, porque el datapath
    // necesita leer los operandos antes de saber si la operacion procede.
    check4("el indice de destino sale igual", rd_idx,    4'd1);
    check4("el indice de base sale igual",    rbase_idx, 4'd2);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check32("caso deliberadamente incorrecto", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

    resumen();
  end

endmodule
