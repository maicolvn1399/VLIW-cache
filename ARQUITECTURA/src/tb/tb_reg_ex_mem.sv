`timescale 1ns/1ps

// =============================================================================
// tb_reg_ex_mem.sv - Testbench del registro de segmentacion EX/MEM.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Esta frontera lleva los siete puertos de escritura del banco y las cinco
// fallas, los dos como arreglos. Un arreglo empaquetado concentra dos errores
// distintos y hay que buscar los dos:
//
//   El arreglo entero conectado al campo de al lado, que es el error de copiar
//   y pegar de siempre. Lo caza la prueba de aislamiento de la seccion 2, con
//   la misma huella de bits que tb_reg_id_ex.
//
//   Un elemento conectado al elemento vecino DENTRO del arreglo, del estilo
//   write_index_out[3] <= write_index_in[2]. Ese pasaria la prueba de
//   aislamiento sin problema, porque el arreglo completo sigue saliendo
//   distinto de cero. Por eso las secciones 3 y 4 cargan cada elemento con un
//   valor propio y los revisan uno por uno.
//
// El segundo error no es teorico: el indice de puerto ES la prioridad de
// escritura, asi que dos puertos cruzados cambian quien gana un conflicto, y lo
// hacen sin que ninguna unidad funcional se queje.
//
// Autoprueba del arnes: compilar con -DFORCE_FAIL inyecta un caso
// deliberadamente incorrecto.
//
// -----------------------------------------------------------------------------
// COBERTURA
// -----------------------------------------------------------------------------
//   1. Reset: los diez campos en cero
//   2. Aislamiento: los diez campos, uno por uno, con huella exacta
//   3. Los 7 puertos de escritura: habilitador, indice y valor por separado
//   4. Las 5 fallas y sus 5 causas, cada una en su posicion
//   5. Las salidas no se mueven antes del flanco de subida
//   6. El retraso es de exactamente un ciclo
// =============================================================================

`include "cerbero_defs.svh"

module tb_reg_ex_mem;

  localparam int N_CAMPOS = 10;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------------------

  logic rst_n;

  logic        valid_in;
  logic [31:0] s2_in;
  logic [1:0]  addr_lo_in;
  logic [`NWRITE_PORTS-1:0]                wen_in;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   widx_in;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     wval_in;
  logic [4:0]       fault_in;
  logic [4:0][2:0]  cause_in;
  logic             flags_we_in;
  logic [3:0]       flags_in;

  logic        valid_out;
  logic [31:0] s2_out;
  logic [1:0]  addr_lo_out;
  logic [`NWRITE_PORTS-1:0]                wen_out;
  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   widx_out;
  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     wval_out;
  logic [4:0]       fault_out;
  logic [4:0][2:0]  cause_out;
  logic             flags_we_out;
  logic [3:0]       flags_out;

  reg_ex_mem dut (
      .clk              (clk),
      .rst_n            (rst_n),
      .valid_in         (valid_in),
      .s2_inst_in       (s2_in),
      .addr_lo_in       (addr_lo_in),
      .write_enable_in  (wen_in),
      .write_index_in   (widx_in),
      .write_value_in   (wval_in),
      .fault_in         (fault_in),
      .cause_in         (cause_in),
      .flags_we_in      (flags_we_in),
      .flags_in         (flags_in),
      .valid_out        (valid_out),
      .s2_inst_out      (s2_out),
      .addr_lo_out      (addr_lo_out),
      .write_enable_out (wen_out),
      .write_index_out  (widx_out),
      .write_value_out  (wval_out),
      .fault_out        (fault_out),
      .cause_out        (cause_out),
      .flags_we_out     (flags_we_out),
      .flags_out        (flags_out)
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
      s2_in       = 32'd0;
      addr_lo_in  = 2'd0;
      wen_in      = '0;
      widx_in     = '0;
      wval_in     = '0;
      fault_in    = 5'd0;
      cause_in    = '0;
      flags_we_in = 1'b0;
      flags_in    = 4'd0;
    end
  endtask

  task automatic solo(input integer campo);
    begin
      limpiar();
      case (campo)
        0: valid_in    = 1'b1;
        1: s2_in       = 32'h1111_1111;
        2: addr_lo_in  = 2'd2;
        3: wen_in[0]   = 1'b1;
        4: widx_in[0]  = 4'd4;
        5: wval_in[0]  = 32'h5555_5555;
        6: fault_in[0] = 1'b1;
        7: cause_in[0] = 3'd7;
        8: flags_we_in = 1'b1;
        9: flags_in    = 4'd9;
        default: ;
      endcase
    end
  endtask

  function automatic integer huella();
    integer h;
    begin
      h = 0;
      if (valid_out    !== 1'b0 ) h = h | (1 << 0);
      if (s2_out       !== 32'd0) h = h | (1 << 1);
      if (addr_lo_out  !== 2'd0 ) h = h | (1 << 2);
      if (wen_out      !== '0   ) h = h | (1 << 3);
      if (widx_out     !== '0   ) h = h | (1 << 4);
      if (wval_out     !== '0   ) h = h | (1 << 5);
      if (fault_out    !== 5'd0 ) h = h | (1 << 6);
      if (cause_out    !== '0   ) h = h | (1 << 7);
      if (flags_we_out !== 1'b0 ) h = h | (1 << 8);
      if (flags_out    !== 4'd0 ) h = h | (1 << 9);
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
      $dumpfile("tb_reg_ex_mem.vcd");
      $dumpvars(0, tb_reg_ex_mem);
    end

    nombres[0] = "valid";
    nombres[1] = "s2_inst";
    nombres[2] = "addr_lo";
    nombres[3] = "write_enable";
    nombres[4] = "write_index";
    nombres[5] = "write_value";
    nombres[6] = "fault";
    nombres[7] = "cause";
    nombres[8] = "flags_we";
    nombres[9] = "flags";

    limpiar();
    rst_n = 1'b1;

    $display("=== tb_reg_ex_mem: frontera EX/MEM ===");

    // ------------------------------------------------------------------------
    $display("[1] reset");
    // ------------------------------------------------------------------------

    solo(5);
    reiniciar();
    check_int("las diez salidas quedan en cero", huella(), 0);

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
    check_int("los 10 campos llegan solo a su propia salida", malos, 0);

    // ------------------------------------------------------------------------
    $display("[3] los siete puertos de escritura");
    // ------------------------------------------------------------------------
    // El indice de puerto es la prioridad de escritura, asi que dos puertos
    // cruzados cambian quien gana un WCONF. Cada uno lleva un valor propio.
    //
    // Los habilitadores van en un patron alterno y no todos en uno, porque con
    // todos encendidos un cruce entre dos de ellos pasaria inadvertido.

    reiniciar();
    limpiar();
    for (i = 0; i < `NWRITE_PORTS; i = i + 1) begin
      wen_in[i]  = (i % 2 == 0);
      widx_in[i] = i[`RIDX_W-1:0];
      wval_in[i] = 32'hB000_0000 + i;
    end
    pasar();

    malos = 0;
    for (i = 0; i < `NWRITE_PORTS; i = i + 1) begin
      if (wen_out[i]  !== (i % 2 == 0))           malos = malos + 1;
      if (widx_out[i] !== i[`RIDX_W-1:0])         malos = malos + 1;
      if (wval_out[i] !== (32'hB000_0000 + i))    malos = malos + 1;
    end
    check_int("los 7 puertos llevan su habilitador, indice y valor", malos, 0);

    // Un caso explicito sobre el puerto de la carga, que es el que la etapa de
    // memoria sustituye
    check_int("el habilitador del destino de la carga",
              wen_out[`WP_S2_RD], 1);
    check32  ("el indice del destino de la carga",
              {28'd0, widx_out[`WP_S2_RD]}, 32'h0000_0002);

    // ------------------------------------------------------------------------
    $display("[4] las cinco fallas y sus causas");
    // ------------------------------------------------------------------------
    // Causas distintas en cada slot: si dos posiciones se cruzaron, el PSW
    // registraria la causa de otro slot con la prioridad del propio.

    reiniciar();
    limpiar();
    fault_in = 5'b10101;
    cause_in[0] = `CAUSE_ILLOP;
    cause_in[1] = `CAUSE_MISALIGN;
    cause_in[2] = `CAUSE_RANGE;
    cause_in[3] = `CAUSE_DENIED;
    cause_in[4] = `CAUSE_NOKEY;
    pasar();

    check_int("el patron de fallas cruza entero", fault_out, 5'b10101);

    malos = 0;
    if (cause_out[0] !== `CAUSE_ILLOP)    malos = malos + 1;
    if (cause_out[1] !== `CAUSE_MISALIGN) malos = malos + 1;
    if (cause_out[2] !== `CAUSE_RANGE)    malos = malos + 1;
    if (cause_out[3] !== `CAUSE_DENIED)   malos = malos + 1;
    if (cause_out[4] !== `CAUSE_NOKEY)    malos = malos + 1;
    check_int("las 5 causas llegan a su slot", malos, 0);

    // ------------------------------------------------------------------------
    $display("[5] las salidas esperan el flanco");
    // ------------------------------------------------------------------------

    @(negedge clk);
    #1;
    fault_in = 5'b01010;
    #2;
    check_int("fault_out no cambia a mitad de ciclo", fault_out, 5'b10101);
    @(posedge clk);
    #1;
    check_int("fault_out cambia en el flanco",        fault_out, 5'b01010);

    // ------------------------------------------------------------------------
    $display("[6] el retraso es de un ciclo exacto");
    // ------------------------------------------------------------------------

    reiniciar();
    limpiar();
    valid_in = 1'b1;
    malos    = 0;

    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      #1 s2_in = 32'h0000_4000 + (i * 16);
      @(posedge clk);
      #1;
      if (s2_out !== (32'h0000_4000 + (i * 16))) begin
        malos = malos + 1;
        if (malos <= 3)
          $display("         paso %0d: s2_out=%08h, esperaba %08h",
                   i, s2_out, 32'h0000_4000 + (i * 16));
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
