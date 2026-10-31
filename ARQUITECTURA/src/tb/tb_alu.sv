//==============================================================================
// tb_alu.sv
// CERBERO-1 - Testbench autoverificable de la unidad aritmetico-logica
//
// Instancia las dos ALU del bundle con el mismo estimulo:
//   u_alu0 -> IS_SLOT0 = 1 (slot S0, escribe banderas)
//   u_alu1 -> IS_SLOT0 = 0 (slot S1, no escribe banderas)
//
// Cubre los 32 opcodes, la extension de signo del inmediato, el enmascarado de
// la cantidad de desplazamiento, las cuatro banderas, los ocho codigos de
// condicion de SETcc, y las dos fuentes de ILLOP.
//
// Uso:
//   iverilog -g2012 -I rtl -o build/tb_alu rtl/alu.sv tb/tb_alu.sv
//   vvp build/tb_alu
//==============================================================================
`timescale 1ns/1ps
`include "cerbero_defs.svh"

module tb_alu;

    //--------------------------------------------------------------------------
    // Estimulo compartido por las dos instancias
    //--------------------------------------------------------------------------
    logic [31:0] slot_q, a_q, b_q, psw_q;

    logic [31:0] res0, res1;
    logic [3:0]  rd0,  rd1;
    logic        we0,  we1;
    logic        fwe0, fwe1;
    logic [3:0]  flg0, flg1;
    logic        ill0, ill1;

    alu #(.IS_SLOT0(1'b1)) u_alu0 (
        .slot_i(slot_q), .op_a_i(a_q), .op_b_i(b_q), .psw_i(psw_q),
        .result_o(res0), .rd_o(rd0), .rd_we_o(we0),
        .flags_we_o(fwe0), .flags_o(flg0), .illop_o(ill0)
    );

    alu #(.IS_SLOT0(1'b0)) u_alu1 (
        .slot_i(slot_q), .op_a_i(a_q), .op_b_i(b_q), .psw_i(psw_q),
        .result_o(res1), .rd_o(rd1), .rd_we_o(we1),
        .flags_we_o(fwe1), .flags_o(flg1), .illop_o(ill1)
    );

    //--------------------------------------------------------------------------
    // Contadores
    //--------------------------------------------------------------------------
    integer pruebas = 0;
    integer errores = 0;

    //--------------------------------------------------------------------------
    // Constructores de slot
    //--------------------------------------------------------------------------
    function automatic [31:0] mk_a(input [4:0]  op,
                                   input [3:0]  rd,
                                   input [3:0]  rs1,
                                   input [3:0]  rs2);
        mk_a = {op, rd, rs1, rs2, 15'd0};
    endfunction

    function automatic [31:0] mk_i(input [4:0]  op,
                                   input [3:0]  rd,
                                   input [3:0]  rs1,
                                   input [18:0] imm);
        mk_i = {op, rd, rs1, imm};
    endfunction

    function automatic [31:0] mk_u(input [4:0]  op,
                                   input [3:0]  rd,
                                   input [15:0] i16,
                                   input [2:0]  cnd);
        mk_u = {op, rd, 4'd0, i16, cnd};
    endfunction

    //--------------------------------------------------------------------------
    // Aplicacion de estimulo. El modulo es combinacional, basta un delta.
    //--------------------------------------------------------------------------
    task automatic aplicar(input [31:0] slot,
                           input [31:0] a,
                           input [31:0] b,
                           input [31:0] psw);
        begin
            slot_q = slot;
            a_q    = a;
            b_q    = b;
            psw_q  = psw;
            #1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Comprobaciones
    //--------------------------------------------------------------------------
    task automatic chk32(input string nombre,
                         input [31:0] obtenido,
                         input [31:0] esperado);
        begin
            pruebas = pruebas + 1;
            if (obtenido !== esperado) begin
                errores = errores + 1;
                $display("  FALLO  %-34s obtenido=%08h esperado=%08h",
                         nombre, obtenido, esperado);
            end
        end
    endtask

    task automatic chk1(input string nombre,
                        input logic obtenido,
                        input logic esperado);
        begin
            pruebas = pruebas + 1;
            if (obtenido !== esperado) begin
                errores = errores + 1;
                $display("  FALLO  %-34s obtenido=%b esperado=%b",
                         nombre, obtenido, esperado);
            end
        end
    endtask

    task automatic chk4(input string nombre,
                        input [3:0] obtenido,
                        input [3:0] esperado);
        begin
            pruebas = pruebas + 1;
            if (obtenido !== esperado) begin
                errores = errores + 1;
                $display("  FALLO  %-34s obtenido=%b (VCNZ) esperado=%b",
                         nombre, obtenido, esperado);
            end
        end
    endtask

    // Operacion ordinaria: las dos ALU deben coincidir, escribir y no fallar
    task automatic chk_ambos(input string nombre, input [31:0] esperado);
        begin
            chk32({nombre, " [S0]"}, res0, esperado);
            chk32({nombre, " [S1]"}, res1, esperado);
            chk1 ({nombre, " we0"},  we0,  1'b1);
            chk1 ({nombre, " we1"},  we1,  1'b1);
            chk1 ({nombre, " ill0"}, ill0, 1'b0);
            chk1 ({nombre, " ill1"}, ill1, 1'b0);
        end
    endtask

    //--------------------------------------------------------------------------
    // Secuencia de pruebas
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_alu.vcd");
        $dumpvars(0, tb_alu);

        slot_q = 32'd0; a_q = 32'd0; b_q = 32'd0; psw_q = 32'd0;
        #1;

        $display("================================================================");
        $display(" CERBERO-1 : testbench de la unidad aritmetico-logica");
        $display("================================================================");

        //======================================================================
        $display("-- 1. NOP ------------------------------------------------------");
        //======================================================================
        aplicar(32'd0, 32'hDEADBEEF, 32'h12345678, 32'd0);
        chk1("NOP no escribe registro S0", we0,  1'b0);
        chk1("NOP no escribe registro S1", we1,  1'b0);
        chk1("NOP no escribe banderas",    fwe0, 1'b0);
        chk1("NOP sin falla",              ill0, 1'b0);

        //======================================================================
        $display("-- 2. Aritmetica de registro -----------------------------------");
        //======================================================================
        aplicar(mk_a(`ALU_ADD, 4'd3, 4'd1, 4'd2), 32'h00000010, 32'h00000020, 32'd0);
        chk_ambos("ADD", 32'h00000030);
        chk4("ADD no toca banderas (we)", {3'b000, fwe0}, 4'b0000);
        chk32("ADD propaga rd", {28'd0, rd0}, 32'd3);

        // Envolvente de 32 bits, como exige la aritmetica modular de Nova
        aplicar(mk_a(`ALU_ADD, 4'd3, 4'd1, 4'd2), 32'hFFFFFFFF, 32'h00000001, 32'd0);
        chk_ambos("ADD envolvente", 32'h00000000);

        aplicar(mk_a(`ALU_SUB, 4'd3, 4'd1, 4'd2), 32'h00000030, 32'h00000010, 32'd0);
        chk_ambos("SUB", 32'h00000020);

        aplicar(mk_a(`ALU_SUB, 4'd3, 4'd1, 4'd2), 32'h00000010, 32'h00000030, 32'd0);
        chk_ambos("SUB negativa", 32'hFFFFFFE0);

        aplicar(mk_a(`ALU_MUL, 4'd3, 4'd1, 4'd2), 32'd7, 32'd6, 32'd0);
        chk_ambos("MUL", 32'd42);

        // La multiplicacion entrega los 32 bits bajos
        aplicar(mk_a(`ALU_MUL, 4'd3, 4'd1, 4'd2), 32'h00010000, 32'h00010000, 32'd0);
        chk_ambos("MUL truncada", 32'h00000000);

        aplicar(mk_a(`ALU_MUL, 4'd3, 4'd1, 4'd2), 32'd7, 32'hFFFFFFFD, 32'd0);
        chk_ambos("MUL con signo", 32'hFFFFFFEB);

        aplicar(mk_a(`ALU_NEG, 4'd3, 4'd1, 4'd0), 32'd5, 32'd0, 32'd0);
        chk_ambos("NEG", 32'hFFFFFFFB);

        aplicar(mk_a(`ALU_NEG, 4'd3, 4'd1, 4'd0), 32'd0, 32'd0, 32'd0);
        chk_ambos("NEG de cero", 32'h00000000);

        //======================================================================
        $display("-- 3. Logica ---------------------------------------------------");
        //======================================================================
        aplicar(mk_a(`ALU_AND, 4'd3, 4'd1, 4'd2), 32'hF0F0F0F0, 32'hFF00FF00, 32'd0);
        chk_ambos("AND", 32'hF000F000);

        aplicar(mk_a(`ALU_OR, 4'd3, 4'd1, 4'd2), 32'hF0F0F0F0, 32'h0F0F0F0F, 32'd0);
        chk_ambos("OR", 32'hFFFFFFFF);

        aplicar(mk_a(`ALU_XOR, 4'd3, 4'd1, 4'd2), 32'hAAAAAAAA, 32'hFFFFFFFF, 32'd0);
        chk_ambos("XOR", 32'h55555555);

        aplicar(mk_a(`ALU_NOT, 4'd3, 4'd1, 4'd0), 32'h0F0F0F0F, 32'd0, 32'd0);
        chk_ambos("NOT", 32'hF0F0F0F0);

        aplicar(mk_a(`ALU_MOV, 4'd3, 4'd1, 4'd0), 32'hDEADBEEF, 32'd0, 32'd0);
        chk_ambos("MOV", 32'hDEADBEEF);

        //======================================================================
        $display("-- 4. Desplazamientos y rotaciones -----------------------------");
        //======================================================================
        aplicar(mk_a(`ALU_SLL, 4'd3, 4'd1, 4'd2), 32'h00000001, 32'd31, 32'd0);
        chk_ambos("SLL 31", 32'h80000000);

        // Solo cuentan los cinco bits bajos del operando B
        aplicar(mk_a(`ALU_SLL, 4'd3, 4'd1, 4'd2), 32'h00000001, 32'h00000025, 32'd0);
        chk_ambos("SLL enmascarado a [4:0]", 32'h00000020);

        aplicar(mk_a(`ALU_SRL, 4'd3, 4'd1, 4'd2), 32'h80000000, 32'd4, 32'd0);
        chk_ambos("SRL", 32'h08000000);

        aplicar(mk_a(`ALU_SRA, 4'd3, 4'd1, 4'd2), 32'h80000000, 32'd4, 32'd0);
        chk_ambos("SRA negativo", 32'hF8000000);

        aplicar(mk_a(`ALU_SRA, 4'd3, 4'd1, 4'd2), 32'h40000000, 32'd4, 32'd0);
        chk_ambos("SRA positivo", 32'h04000000);

        aplicar(mk_a(`ALU_ROL, 4'd3, 4'd1, 4'd2), 32'h80000001, 32'd1, 32'd0);
        chk_ambos("ROL 1", 32'h00000003);

        // Caso critico: rotacion de cero posiciones
        aplicar(mk_a(`ALU_ROL, 4'd3, 4'd1, 4'd2), 32'h12345678, 32'd0, 32'd0);
        chk_ambos("ROL 0 es identidad", 32'h12345678);

        aplicar(mk_a(`ALU_ROR, 4'd3, 4'd1, 4'd2), 32'h80000001, 32'd1, 32'd0);
        chk_ambos("ROR 1", 32'hC0000000);

        aplicar(mk_a(`ALU_ROR, 4'd3, 4'd1, 4'd2), 32'h12345678, 32'd0, 32'd0);
        chk_ambos("ROR 0 es identidad", 32'h12345678);

        //======================================================================
        $display("-- 5. Formas inmediatas y extension de signo -------------------");
        //======================================================================
        aplicar(mk_i(`ALU_ADDI, 4'd3, 4'd1, 19'd100), 32'd10, 32'd0, 32'd0);
        chk_ambos("ADDI positivo", 32'd110);

        // 19'h7FFFF es -1 con extension de signo
        aplicar(mk_i(`ALU_ADDI, 4'd3, 4'd1, 19'h7FFFF), 32'd10, 32'd0, 32'd0);
        chk_ambos("ADDI negativo", 32'd9);

        aplicar(mk_i(`ALU_SUBI, 4'd3, 4'd1, 19'd1), 32'd10, 32'd0, 32'd0);
        chk_ambos("SUBI", 32'd9);

        aplicar(mk_i(`ALU_ANDI, 4'd3, 4'd1, 19'h000FF), 32'h12345678, 32'd0, 32'd0);
        chk_ambos("ANDI", 32'h00000078);

        aplicar(mk_i(`ALU_ORI, 4'd3, 4'd1, 19'h7FFFF), 32'h00000000, 32'd0, 32'd0);
        chk_ambos("ORI con inmediato negativo", 32'hFFFFFFFF);

        aplicar(mk_i(`ALU_XORI, 4'd3, 4'd1, 19'h7FFFF), 32'h0000FFFF, 32'd0, 32'd0);
        chk_ambos("XORI", 32'hFFFF0000);

        aplicar(mk_i(`ALU_SLLI, 4'd3, 4'd1, 19'd4), 32'h00000001, 32'd0, 32'd0);
        chk_ambos("SLLI", 32'h00000010);

        aplicar(mk_i(`ALU_SRLI, 4'd3, 4'd1, 19'd4), 32'h80000000, 32'd0, 32'd0);
        chk_ambos("SRLI", 32'h08000000);

        aplicar(mk_i(`ALU_SRAI, 4'd3, 4'd1, 19'd4), 32'h80000000, 32'd0, 32'd0);
        chk_ambos("SRAI", 32'hF8000000);

        aplicar(mk_i(`ALU_ROLI, 4'd3, 4'd1, 19'd8), 32'h12345678, 32'd0, 32'd0);
        chk_ambos("ROLI 8", 32'h34567812);

        //======================================================================
        $display("-- 6. Construccion de constantes de 32 bits --------------------");
        //======================================================================
        aplicar(mk_i(`ALU_MOVI, 4'd3, 4'd0, 19'h01234), 32'd0, 32'd0, 32'd0);
        chk_ambos("MOVI positivo", 32'h00001234);

        // 19'h7FF9C es -100
        aplicar(mk_i(`ALU_MOVI, 4'd3, 4'd0, 19'h7FF9C), 32'd0, 32'd0, 32'd0);
        chk_ambos("MOVI negativo", 32'hFFFFFF9C);

        // MOVH conserva la mitad baja de rd, que ID debe enrutar por el puerto A
        aplicar(mk_u(`ALU_MOVH, 4'd3, 16'hDEAD, 3'd0), 32'h0000BEEF, 32'd0, 32'd0);
        chk_ambos("MOVH conserva mitad baja", 32'hDEADBEEF);

        aplicar(mk_u(`ALU_MOVH, 4'd3, 16'h0000, 3'd0), 32'hFFFFFFFF, 32'd0, 32'd0);
        chk_ambos("MOVH con mitad alta nula", 32'h0000FFFF);

        //======================================================================
        $display("-- 7. Banderas de comparacion (solo S0) ------------------------");
        //======================================================================
        // Vector de banderas: {V, C, N, Z}
        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'd5, 32'd5, 32'd0);
        chk1("CMP activa escritura de banderas", fwe0, 1'b1);
        chk1("CMP no escribe registro",          we0,  1'b0);
        chk4("CMP iguales", flg0, 4'b0001);

        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'd3, 32'd5, 32'd0);
        chk4("CMP menor con signo", flg0, 4'b0110);

        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'd5, 32'd3, 32'd0);
        chk4("CMP mayor", flg0, 4'b0000);

        // -2^31 menos 1 desborda con signo pero no pide prestamo sin signo
        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'h80000000, 32'd1, 32'd0);
        chk4("CMP con desbordamiento", flg0, 4'b1000);

        // 0xFFFFFFFF es -1 con signo, pero el mayor sin signo
        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'hFFFFFFFF, 32'd1, 32'd0);
        chk4("CMP -1 contra 1", flg0, 4'b0010);

        aplicar(mk_i(`ALU_CMPI, 4'd0, 4'd1, 19'd10), 32'd10, 32'd0, 32'd0);
        chk4("CMPI iguales", flg0, 4'b0001);

        // 0 contra -1: con signo 0 > -1 (LT falso), pero sin signo
        // 0 < 0xFFFFFFFF, asi que se pide prestamo y C = 1
        aplicar(mk_i(`ALU_CMPI, 4'd0, 4'd1, 19'h7FFFF), 32'd0, 32'd0, 32'd0);
        chk4("CMPI contra -1", flg0, 4'b0100);

        //======================================================================
        $display("-- 8. Banderas de TEST -----------------------------------------");
        //======================================================================
        aplicar(mk_a(`ALU_TEST, 4'd0, 4'd1, 4'd2), 32'h000000F0, 32'h0000000F, 32'd0);
        chk4("TEST sin bits comunes", flg0, 4'b0001);

        aplicar(mk_a(`ALU_TEST, 4'd0, 4'd1, 4'd2), 32'h80000000, 32'hFFFFFFFF, 32'd0);
        chk4("TEST con bit de signo", flg0, 4'b0010);

        aplicar(mk_i(`ALU_TESTI, 4'd0, 4'd1, 19'd4), 32'd5, 32'd0, 32'd0);
        chk4("TESTI bit encendido", flg0, 4'b0000);

        //======================================================================
        $display("-- 9. SETcc sobre los ocho codigos de condicion ----------------");
        //======================================================================
        // PSW con Z = 1
        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_AL), 32'd0, 32'd0, 32'h00000001);
        chk_ambos("SETcc AL", 32'd1);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_EQ), 32'd0, 32'd0, 32'h00000001);
        chk_ambos("SETcc EQ con Z=1", 32'd1);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_NE), 32'd0, 32'd0, 32'h00000001);
        chk_ambos("SETcc NE con Z=1", 32'd0);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_EQ), 32'd0, 32'd0, 32'h00000000);
        chk_ambos("SETcc EQ con Z=0", 32'd0);

        // PSW con N = 1 y V = 0  ->  LT verdadero
        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_LT), 32'd0, 32'd0, 32'h00000002);
        chk_ambos("SETcc LT con N=1 V=0", 32'd1);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_GE), 32'd0, 32'd0, 32'h00000002);
        chk_ambos("SETcc GE con N=1 V=0", 32'd0);

        // PSW con N = 1 y V = 1  ->  LT falso
        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_LT), 32'd0, 32'd0, 32'h0000000A);
        chk_ambos("SETcc LT con N=1 V=1", 32'd0);

        // PSW con C = 1
        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_LTU), 32'd0, 32'd0, 32'h00000004);
        chk_ambos("SETcc LTU con C=1", 32'd1);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_GEU), 32'd0, 32'd0, 32'h00000004);
        chk_ambos("SETcc GEU con C=1", 32'd0);

        // PSW con AUTH = 1
        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_AUTH), 32'd0, 32'd0, 32'h00000010);
        chk_ambos("SETcc AUTH con sesion abierta", 32'd1);

        aplicar(mk_u(`ALU_SETCC, 4'd3, 16'd0, `COND_AUTH), 32'd0, 32'd0, 32'h00000000);
        chk_ambos("SETcc AUTH sin sesion", 32'd0);

        //======================================================================
        $display("-- 10. MFPSW ---------------------------------------------------");
        //======================================================================
        aplicar(mk_u(`ALU_MFPSW, 4'd3, 16'd0, 3'd0), 32'd0, 32'd0, 32'h000001AB);
        chk_ambos("MFPSW copia el PSW", 32'h000001AB);

        //======================================================================
        $display("-- 11. ILLOP por campo reservado distinto de cero --------------");
        //======================================================================
        // ADD con basura en slot[14:0]
        aplicar({`ALU_ADD, 4'd3, 4'd1, 4'd2, 15'h0001}, 32'd1, 32'd1, 32'd0);
        chk1("ADD con reservado sucio marca ILLOP", ill0, 1'b1);
        chk1("ADD con reservado sucio no escribe",  we0,  1'b0);
        chk32("ADD con reservado sucio da cero",    res0, 32'h00000000);

        // MOV con rs2 distinto de cero
        aplicar({`ALU_MOV, 4'd3, 4'd1, 4'd5, 15'd0}, 32'hAA, 32'd0, 32'd0);
        chk1("MOV con rs2 sucio marca ILLOP", ill0, 1'b1);

        // CMP con rd distinto de cero
        aplicar({`ALU_CMP, 4'd7, 4'd1, 4'd2, 15'd0}, 32'd1, 32'd1, 32'd0);
        chk1("CMP con rd sucio marca ILLOP",      ill0, 1'b1);
        chk1("CMP con rd sucio no toca banderas", fwe0, 1'b0);

        // MOVI con rs1 distinto de cero
        aplicar({`ALU_MOVI, 4'd3, 4'd2, 19'd5}, 32'd0, 32'd0, 32'd0);
        chk1("MOVI con rs1 sucio marca ILLOP", ill0, 1'b1);

        // MFPSW con cond distinto de cero
        aplicar({`ALU_MFPSW, 4'd3, 4'd0, 16'd0, 3'd1}, 32'd0, 32'd0, 32'd0);
        chk1("MFPSW con cond sucio marca ILLOP", ill0, 1'b1);

        // MOVH con cond distinto de cero
        aplicar({`ALU_MOVH, 4'd3, 4'd0, 16'hDEAD, 3'd2}, 32'd0, 32'd0, 32'd0);
        chk1("MOVH con cond sucio marca ILLOP", ill0, 1'b1);

        //======================================================================
        $display("-- 12. ILLOP por comparacion codificada en S1 ------------------");
        //======================================================================
        aplicar(mk_a(`ALU_CMP, 4'd0, 4'd1, 4'd2), 32'd5, 32'd5, 32'd0);
        chk1("CMP valida en S0",             ill0, 1'b0);
        chk1("CMP escribe banderas en S0",   fwe0, 1'b1);
        chk1("CMP ilegal en S1",             ill1, 1'b1);
        chk1("CMP no escribe banderas en S1",fwe1, 1'b0);

        aplicar(mk_a(`ALU_TEST, 4'd0, 4'd1, 4'd2), 32'hFF, 32'hFF, 32'd0);
        chk1("TEST ilegal en S1", ill1, 1'b1);

        aplicar(mk_i(`ALU_CMPI, 4'd0, 4'd1, 19'd1), 32'd1, 32'd0, 32'd0);
        chk1("CMPI ilegal en S1", ill1, 1'b1);

        aplicar(mk_i(`ALU_TESTI, 4'd0, 4'd1, 19'd1), 32'd1, 32'd0, 32'd0);
        chk1("TESTI ilegal en S1", ill1, 1'b1);

        // Una operacion ordinaria sigue siendo valida en los dos slots
        aplicar(mk_a(`ALU_ADD, 4'd3, 4'd1, 4'd2), 32'd1, 32'd2, 32'd0);
        chk_ambos("ADD valido en ambos slots", 32'd3);

`ifdef FORCE_FAIL
        //======================================================================
        $display("-- autoprueba del arnes --------------------------------------");
        //======================================================================
        chk32("caso deliberadamente incorrecto", 32'h00000000, 32'hFFFFFFFF);
`endif

        //======================================================================
        $display("---");
        $display("casos: %0d   fallidos: %0d", pruebas, errores);
        if (errores != 0) begin
            $display("RESULTADO: FALLA");
            $fatal(1, "%0d caso(s) fallaron", errores);
        end
        $display("RESULTADO: OK");
        $finish;
    end

endmodule
