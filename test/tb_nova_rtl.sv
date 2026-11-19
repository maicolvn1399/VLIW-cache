`timescale 1ns/1ps

`include "cerbero_defs.svh"

`ifndef CERBERO_ROT_SECRET
  `define CERBERO_ROT_SECRET 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210
`endif

module tb_nova_rtl;

  localparam int MAX_CYCLES = 20000;
  localparam int DMEM_WORDS = 16384;
  localparam int OUT_COUNT_WORD = 'h3000 / 4;
  localparam int OUT_BUFFER_WORD = 'h3004 / 4;
  localparam int OUT_BUFFER_CAPACITY = ('h4000 - 'h3004) / 4;
`ifdef CERBERO_MAX_CYCLES
  localparam int NOVA_MAX_CYCLES = `CERBERO_MAX_CYCLES;
`else
  localparam int NOVA_MAX_CYCLES = MAX_CYCLES;
`endif

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic halted;
  logic [`XLEN-1:0] psw;
  logic [`NREGS-1:0][`XLEN-1:0] regs;
  logic [31:0] perf_ciclos;
  logic [31:0] perf_instrucciones;
  // Desde que CERBERO tiene jerarquia de memoria, 'halted' ya no significa que
  // lo que escribio el programa este en la memoria principal: la L2 es
  // write-back y puede retener lineas sucias. 'mem_drenada' es la senal que
  // dice que de verdad no queda nada en vuelo.
  logic mem_drenada;
  integer drain_guard;
  integer expected;
  integer cycles;
  integer output_count;
  integer output_index;
  integer dmem_dump_index;
  integer dmem_dump_file;
  string expected_out;
  string actual_out;
  string dmem_dump_path;
  bit check_expected_out;
  bit check_expected_return;
  bit dump_dmem;
  bit dump_plusarg_ok;
  // Volcado de los contadores de rendimiento (Iteracion 5). Se leen de
  // 'dut.u_perf' por nombre jerarquico, igual que la memoria: top.sv solo saca
  // al exterior 'ciclos' e 'instrucciones', pero perf_counters cuenta mucho
  // mas, y nada de esto exige tocar ARQUITECTURA/.
  string metricas_path;
  integer metricas_file;
  integer slot_index;
  bit dump_metricas;

  top #(.ROT_SECRET(`CERBERO_ROT_SECRET)) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs),
      .perf_ciclos (perf_ciclos),
      .perf_instrucciones (perf_instrucciones),
      .mem_drenada (mem_drenada)
  );

  initial begin
    if (!$value$plusargs("EXPECTED=%d", expected)) expected = 25;
    expected_out = "";
    check_expected_out = $test$plusargs("EXPECTED_OUT=");
    check_expected_return = !$test$plusargs("OMITIR_VERIFICACION_RETORNO");
    dmem_dump_path = "";
    dump_dmem = $value$plusargs("DMEM_DUMP=%s", dmem_dump_path);
    metricas_path = "";
    dump_metricas = $value$plusargs("METRICAS=%s", metricas_path);
    // El resultado se descarta a proposito -- check_expected_out ya dijo que el
    // argumento esta --, pero hay que recogerlo igual: llamar a $value$plusargs
    // como tarea hace que Icarus avise en cada corrida, y eran 164 advertencias
    // por bateria tapando la salida de verdad.
    if (check_expected_out)
      dump_plusarg_ok = $value$plusargs("EXPECTED_OUT=%s", expected_out);

    $display("=== ejecutable Nova sobre el RTL CERBERO ===");
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < NOVA_MAX_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    // Esperar a que la jerarquia de memoria escriba lo que le quedaba.
    //
    // Antes bastaban 8 ciclos fijos porque los stores llegaban directo a la
    // memoria. Ahora el ultimo store atraviesa el write buffer, la L2 (que
    // retiene la linea sucia hasta que top.sv le pide vaciarse) y el eviction
    // buffer. Un bundle detenido en un fallo puede quedarse decenas de ciclos
    // en su etapa, asi que una espera fija no sirve: hay que esperar la senal.
    //
    // Son ciclos del ARNES: 'cycles' no avanza aqui y nada de esta espera
    // entra en las metricas que se reportan.
    drain_guard = 0;
    while (!mem_drenada && drain_guard < 500000) begin
      @(posedge clk);
      drain_guard = drain_guard + 1;
    end
    #1;

    if (halted && !mem_drenada)
      $fatal(1, "la memoria no termino de drenar tras %0d ciclos de espera",
             drain_guard);

    if (!halted)
      $fatal(1, "el procesador no se detuvo tras %0d ciclos (PC=0x%08h, R14=0x%08h, R15=0x%08h)",
             cycles, dut.if_pc, regs[14], regs[15]);
    $display("  ciclos: %0d", cycles);
    $display("  ciclos RTL: %0d", perf_ciclos);
    $display("  instrucciones RTL: %0d", perf_instrucciones);
    $display("  retorno R6: %0d (0x%08h)", regs[6], regs[6]);
    output_count = dut.u_mem_sys.u_mem.storage[OUT_COUNT_WORD];
    if ($isunknown(output_count) || output_count < 0 ||
        output_count > OUT_BUFFER_CAPACITY)
      $fatal(1, "contador de salida invalido en DMEM: %0d", output_count);
    $display("  salida en DMEM del procesador (%0d valores):", output_count);
    actual_out = "";
    for (output_index = 0; output_index < output_count; output_index = output_index + 1) begin
      if (output_index != 0) actual_out = {actual_out, ","};
      actual_out = {actual_out,
                    $sformatf("%0d",
                              $signed(dut.u_mem_sys.u_mem.storage[OUT_BUFFER_WORD + output_index]))};
      $display("    [%0d] %0d (0x%08h)", output_index,
               $signed(dut.u_mem_sys.u_mem.storage[OUT_BUFFER_WORD + output_index]),
               dut.u_mem_sys.u_mem.storage[OUT_BUFFER_WORD + output_index]);
    end
    if (check_expected_out && actual_out != expected_out)
      $fatal(1, "salida incorrecta: esperado [%s], obtenido [%s]",
             expected_out, actual_out);
    if (check_expected_return && regs[6] !== expected)
      $fatal(1, "retorno incorrecto: esperado %0d, obtenido %0d", expected, regs[6]);
    if (psw[`PSW_EXC] !== 1'b0)
      $fatal(1, "el procesador registro una excepcion, PSW=0x%08h", psw);
    if (psw[`PSW_AUTH] !== 1'b0)
      $fatal(1, "la sesion de la boveda no se cerro, PSW=0x%08h", psw);
    if (psw[`PSW_AUTHFAIL] !== 1'b0)
      $fatal(1, "fallo la autenticacion, PSW=0x%08h", psw);

    // Los contadores quedan congelados desde 'halted', asi que los ciclos que
    // el arnes esperó a que drenara la memoria no entran en ninguna cuenta.
    if (dump_metricas) begin
      metricas_file = $fopen(metricas_path, "w");
      if (metricas_file == 0)
        $fatal(1, "no se pudo abrir el volcado de metricas: %s", metricas_path);
      $fdisplay(metricas_file, "ciclos %0d",          dut.u_perf.ciclos);
      $fdisplay(metricas_file, "bundles %0d",         dut.u_perf.bundles);
      $fdisplay(metricas_file, "instrucciones %0d",   dut.u_perf.instrucciones);
      $fdisplay(metricas_file, "bundles_vacios %0d",  dut.u_perf.bundles_vacios);
      $fdisplay(metricas_file, "saltos_tomados %0d",  dut.u_perf.saltos_tomados);
      $fdisplay(metricas_file, "delay_vacios %0d",    dut.u_perf.delay_vacios);
      $fdisplay(metricas_file, "accesos_load %0d",    dut.u_perf.accesos_load);
      $fdisplay(metricas_file, "accesos_store %0d",   dut.u_perf.accesos_store);
      for (slot_index = 0; slot_index < `NSLOTS; slot_index = slot_index + 1)
        $fdisplay(metricas_file, "ops_slot%0d %0d", slot_index,
                  dut.u_perf.ops_por_slot[slot_index]);
      $fdisplay(metricas_file, "ciclos_stall %0d",    dut.u_perf.ciclos_stall);
      $fdisplay(metricas_file, "stall_por_miss %0d",  dut.u_perf.stall_por_miss);
      $fdisplay(metricas_file, "stall_por_wb %0d",    dut.u_perf.stall_por_wb);
      $fdisplay(metricas_file, "stall_por_raw %0d",   dut.u_perf.stall_por_raw);
      $fdisplay(metricas_file, "stall_por_evict %0d", dut.u_perf.stall_por_evict);
      $fdisplay(metricas_file, "l1_load_hit %0d",     dut.u_perf.l1_load_hit);
      $fdisplay(metricas_file, "l1_load_miss %0d",    dut.u_perf.l1_load_miss);
      $fdisplay(metricas_file, "l1_store_hit %0d",    dut.u_perf.l1_store_hit);
      $fdisplay(metricas_file, "l1_store_miss %0d",   dut.u_perf.l1_store_miss);
      $fdisplay(metricas_file, "l2_load_hit %0d",     dut.u_perf.l2_load_hit);
      $fdisplay(metricas_file, "l2_load_miss %0d",    dut.u_perf.l2_load_miss);
      $fdisplay(metricas_file, "l2_store_hit %0d",    dut.u_perf.l2_store_hit);
      $fdisplay(metricas_file, "l2_store_miss %0d",   dut.u_perf.l2_store_miss);
      $fdisplay(metricas_file, "inv_ejecutadas %0d",  dut.u_perf.inv_ejecutadas);
      $fdisplay(metricas_file, "mem_accesos %0d",     dut.u_perf.mem_accesos);
      $fdisplay(metricas_file, "mem_ciclos %0d",      dut.u_perf.mem_ciclos);
      // Pegajoso: si algun contador llego al tope, toda cifra derivada de el
      // es falsa, y hay que saberlo antes de ponerla en una tabla.
      $fdisplay(metricas_file, "desbordado %0d",      dut.u_perf.desbordado);
      $fclose(metricas_file);
    end

    if (dump_dmem) begin
      dmem_dump_file = $fopen(dmem_dump_path, "w");
      if (dmem_dump_file == 0)
        $fatal(1, "no se pudo abrir el volcado DMEM: %s", dmem_dump_path);
      for (dmem_dump_index = 0; dmem_dump_index < DMEM_WORDS;
           dmem_dump_index = dmem_dump_index + 1)
        $fdisplay(dmem_dump_file, "%04h %08h", dmem_dump_index * 4,
                  dut.u_mem_sys.u_mem.storage[dmem_dump_index]);
      $fclose(dmem_dump_file);
    end

    $display("RESULTADO: OK");
    $finish;
  end

endmodule
