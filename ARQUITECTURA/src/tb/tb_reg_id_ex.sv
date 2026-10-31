`timescale 1ns/1ps

// =============================================================================
// tb_reg_id_ex.sv - Testbench del registro de segmentacion ID/EX.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Un registro de segmentacion ancho es doce asignaciones casi identicas una
// debajo de la otra. El error que de verdad ocurre ahi no es olvidar un
// biestable: es que una salida tome la entrada de al lado, porque la linea se
// copio y se cambio solo la mitad del nombre. Eso no rompe la simulacion de
// nada hasta que un programa real mete datos distintos en dos campos vecinos.
//
// -----------------------------------------------------------------------------
// LA PRUEBA DE AISLAMIENTO
// -----------------------------------------------------------------------------
// La seccion 2 recorre los doce campos. En cada paso pone TODAS las entradas en
// cero menos una, avanza un ciclo y calcula una huella: un bit por cada salida
// distinta de cero. La huella tiene que tener encendido exactamente el bit del
// campo que se excito.
//
// Si alguien escribiera "s1_inst_out <= s0_inst_in", al excitar solo s0 la
// huella traeria dos bits y al excitar solo s1 no traeria ninguno. Las dos
// mitades del error se ven, y se ven en el mismo caso.
//
// Los nueve valores leidos del banco se prueban aparte, en la seccion 3, porque
// dentro del arreglo el mismo error de copiar y pegar es todavia mas facil: un
// rval_out[3] <= rval_in[2] pasaria la prueba de aislamiento del arreglo
// completo.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: los doce campos en cero
//   2. Aislamiento: los doce campos, uno por uno, con huella exacta
//   3. Los nueve puertos de lectura llegan cada uno a su sitio
//   4. Los doce campos a la vez, con valores distintos
//   5. Las salidas no se mueven antes del flanco de subida
//   6. El retraso es de exactamente un ciclo
// =============================================================================

`include "cerbero_defs.svh"

module tb_reg_id_ex;

  localparam int N_CAMPOS = 12;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------------

  logic             rst_n;

  logic             valid_in;
  logic [`XLEN-1:0] pc_in;
  logic [31:0]      s0_in, s1_in, s2_in;
  logic [15:0]      s3_in;
  logic [`NREAD_PORTS-1:0][`XLEN-1:0] rval_in;
  logic                   link_we_in;
  logic [`RIDX_W-1:0]     link_idx_in;
  logic [`XLEN-1:0]       link_val_in;
  logic                   s4_fault_in;
  logic [2:0]             s4_cause_in;

  logic             valid_out;
  logic [`XLEN-1:0] pc_out;
  logic [31:0]      s0_out, s1_out, s2_out;
  logic [15:0]      s3_out;
  logic [`NREAD_PORTS-1:0][`XLEN-1:0] rval_out;
  logic                   link_we_out;
  logic [`RIDX_W-1:0]     link_idx_out;
  logic [`XLEN-1:0]       link_val_out;
  logic                   s4_fault_out;
  logic [2:0]             s4_cause_out;

  reg_id_ex dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .valid_in     (valid_in),
      .pc_in        (pc_in),
      .s0_inst_in   (s0_in),
      .s1_inst_in   (s1_in),
      .s2_inst_in   (s2_in),
      .s3_inst_in   (s3_in),
      .rval_in      (rval_in),
      .link_we_in   (link_we_in),
      .link_idx_in  (link_idx_in),
      .link_val_in  (link_val_in),
      .s4_fault_in  (s4_fault_in),
      .s4_cause_in  (s4_cause_in),
      .valid_out    (valid_out),
      .pc_out       (pc_out),
      .s0_inst_out  (s0_out),
      .s1_inst_out  (s1_out),
      .s2_inst_out  (s2_out),
      .s3_inst_out  (s3_out),
      .rval_out     (rval_out),
      .link_we_out  (link_we_out),
      .link_idx_out (link_idx_out),
      .link_val_out (link_val_out),
      .s4_fault_out (s4_fault_out),
      .s4_cause_out (s4_cause_out)
  );

  integer tests_run    = 0;
  integer tests_failed = 0;

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
  // Estimulos
  // ---------------------------------------------------------------------------

  task automatic limpiar();
    begin
      valid_in    = 1'b0;
      pc_in       = '0;
      s0_in       = 32'd0;
      s1_in       = 32'd0;
      s2_in       = 32'd0;
      s3_in       = 16'd0;
      rval_in     = '0;
      link_we_in  = 1'b0;
      link_idx_in = '0;
      link_val_in = '0;
      s4_fault_in = 1'b0;
      s4_cause_in = 3'd0;
    end
  endtask

  // Deja todo en cero menos el campo indicado
  task automatic solo(input integer campo);
    begin
      limpiar();
      case (campo)
        0:  valid_in    = 1'b1;
        1:  pc_in       = 32'h0000_1110;
        2:  s0_in       = 32'h2222_2222;
        3:  s1_in       = 32'h3333_3333;
        4:  s2_in       = 32'h4444_4444;
        5:  s3_in       = 16'h5555;
        6:  rval_in[0]  = 32'h6666_6666;
        7:  link_we_in  = 1'b1;
        8:  link_idx_in = 4'd8;
        9:  link_val_in = 32'h9999_9999;
        10: s4_fault_in = 1'b1;
        11: s4_cause_in = 3'd3;
        default: ;
      endcase
    end
  endtask

  // Un bit por salida distinta de cero
  function automatic integer huella();
    integer h;
    begin
      h = 0;
      if (valid_out    !== 1'b0) h = h | (1 <<  0);
      if (pc_out       !== '0  ) h = h | (1 <<  1);
      if (s0_out       !== 32'd0) h = h | (1 <<  2);
      if (s1_out       !== 32'd0) h = h | (1 <<  3);
      if (s2_out       !== 32'd0) h = h | (1 <<  4);
      if (s3_out       !== 16'd0) h = h | (1 <<  5);
      if (rval_out     !== '0  ) h = h | (1 <<  6);
      if (link_we_out  !== 1'b0) h = h | (1 <<  7);
      if (link_idx_out !== '0  ) h = h | (1 <<  8);
      if (link_val_out !== '0  ) h = h | (1 <<  9);
      if (s4_fault_out !== 1'b0) h = h | (1 << 10);
      if (s4_cause_out !== 3'd0) h = h | (1 << 11);
      huella = h;
    end
  endfunction

  task automatic reiniciar();
    begin
      rst_n = 1'b0;
      @(posedge clk);
      #1 rst_n = 1'b1;
    end
  endtask

  // Presenta los estimulos durante un ciclo completo y los captura
  task automatic pasar();
    begin
      @(negedge clk);
      #1;
      @(posedge clk);
      #1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  integer i, malos, h;
  string nombres [0:N_CAMPOS-1];

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_reg_id_ex.vcd");
      $dumpvars(0, tb_reg_id_ex);
    end

    nombres[0]  = "valid";
    nombres[1]  = "pc";
    nombres[2]  = "s0_inst";
    nombres[3]  = "s1_inst";
    nombres[4]  = "s2_inst";
    nombres[5]  = "s3_inst";
    nombres[6]  = "rval";
    nombres[7]  = "link_we";
    nombres[8]  = "link_idx";
    nombres[9]  = "link_val";
    nombres[10] = "s4_fault";
    nombres[11] = "s4_cause";

    limpiar();
    rst_n = 1'b1;

    $display("=== tb_reg_id_ex: frontera ID/EX ===");

    // ------------------------------------------------------------------------
    $display("[1] reset");
    // ------------------------------------------------------------------------

    solo(2);                 // algo distinto de cero en la entrada
    reiniciar();
    check_int("las doce salidas quedan en cero", huella(), 0);

    // ------------------------------------------------------------------------
    $display("[2] aislamiento campo por campo");
    // ------------------------------------------------------------------------

    malos = 0;
    for (i = 0; i < N_CAMPOS; i = i + 1) begin
      reiniciar();
      solo(i);
      pasar();
      h = huella();
      if (h !== (1 << i)) begin
        malos = malos + 1;
        $display("         campo %0d (%s): huella %0h, esperaba %0h",
                 i, nombres[i], h, 1 << i);
      end
    end
    check_int("los 12 campos llegan solo a su propia salida", malos, 0);

    // ------------------------------------------------------------------------
    $display("[3] los nueve puertos de lectura");
    // ------------------------------------------------------------------------
    // Cada puerto con un valor distinto, de una sola pasada: si dos puertos se
    // cruzaron, los valores aparecen intercambiados.

    reiniciar();
    limpiar();
    for (i = 0; i < `NREAD_PORTS; i = i + 1)
      rval_in[i] = 32'h0A00_0000 + i;
    pasar();

    malos = 0;
    for (i = 0; i < `NREAD_PORTS; i = i + 1)
      if (rval_out[i] !== (32'h0A00_0000 + i)) begin
        malos = malos + 1;
        $display("         puerto %0d: %08h, esperaba %08h",
                 i, rval_out[i], 32'h0A00_0000 + i);
      end
    check_int("los 9 valores leidos llegan a su puerto", malos, 0);

    // ------------------------------------------------------------------------
    $display("[4] los doce campos a la vez");
    // ------------------------------------------------------------------------

    reiniciar();
    limpiar();
    valid_in    = 1'b1;
    pc_in       = 32'h0000_7010;
    s0_in       = 32'h8D50_0004;
    s1_in       = 32'hE280_0002;
    s2_in       = 32'hB670_0000;
    s3_in       = 16'h2041;
    for (i = 0; i < `NREAD_PORTS; i = i + 1)
      rval_in[i] = 32'hC0DE_0000 + i;
    link_we_in  = 1'b1;
    link_idx_in = `REG_LINK;
    link_val_in = 32'h0000_7030;
    s4_fault_in = 1'b1;
    s4_cause_in = `CAUSE_ILLOP;
    pasar();

    check_int("valid",       valid_out,    1);
    check32  ("pc",          pc_out,       32'h0000_7010);
    check32  ("s0_inst",     s0_out,       32'h8D50_0004);
    check32  ("s1_inst",     s1_out,       32'hE280_0002);
    check32  ("s2_inst",     s2_out,       32'hB670_0000);
    check32  ("s3_inst",     {16'd0, s3_out}, 32'h0000_2041);
    check32  ("rval del puerto 4", rval_out[4], 32'hC0DE_0004);
    check_int("link_we",     link_we_out,  1);
    check32  ("link_idx",    {28'd0, link_idx_out}, 32'h0000_000F);
    check32  ("link_val",    link_val_out, 32'h0000_7030);
    check_int("s4_fault",    s4_fault_out, 1);
    check32  ("s4_cause",    {29'd0, s4_cause_out}, 32'h0000_0001);

    // ------------------------------------------------------------------------
    $display("[5] las salidas esperan el flanco");
    // ------------------------------------------------------------------------

    @(negedge clk);
    #1;
    s0_in = 32'hFFFF_0000;
    #2;
    check32("s0_inst_out no cambia a mitad de ciclo", s0_out, 32'h8D50_0004);
    @(posedge clk);
    #1;
    check32("s0_inst_out cambia en el flanco",        s0_out, 32'hFFFF_0000);

    // ------------------------------------------------------------------------
    $display("[6] el retraso es de un ciclo exacto");
    // ------------------------------------------------------------------------
    // Igual que en IF/ID: una secuencia por ciclo, y cada valor tiene que
    // aparecer en la salida en el ciclo inmediatamente siguiente. Dos ciclos
    // aqui correrian la etapa de ejecucion y la latencia expuesta pasaria a 4
    // bundles.

    reiniciar();
    limpiar();
    valid_in = 1'b1;
    malos    = 0;

    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      #1 pc_in = 32'h0000_3000 + (i * 16);
      @(posedge clk);
      #1;
      if (pc_out !== (32'h0000_3000 + (i * 16))) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         paso %0d: pc_out=%08h, esperaba %08h",
                   i, pc_out, 32'h0000_3000 + (i * 16));
      end
    end
    check_int("los 8 pasos de la secuencia salen a tiempo", malos, 0);

`ifdef FORCE_FAIL
    // ------------------------------------------------------------------------
    $display("[autoprueba del arnes]");
    // ------------------------------------------------------------------------
    check_int("caso deliberadamente incorrecto", 0, 1);
`endif

    resumen();
  end

endmodule
