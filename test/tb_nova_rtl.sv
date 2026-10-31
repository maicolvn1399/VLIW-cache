`timescale 1ns/1ps

`include "cerbero_defs.svh"

`ifndef CERBERO_ROT_SECRET
  `define CERBERO_ROT_SECRET 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210
`endif

module tb_nova_rtl;

  localparam int MAX_CYCLES = 20000;
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
  integer expected;
  integer cycles;
  integer output_count;
  integer output_index;

  top #(.ROT_SECRET(`CERBERO_ROT_SECRET)) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs)
  );

  initial begin
    if (!$value$plusargs("EXPECTED=%d", expected)) expected = 25;

    $display("=== ejecutable Nova sobre el RTL CERBERO ===");
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < NOVA_MAX_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    if (!halted) $fatal(1, "el procesador no se detuvo tras %0d ciclos", cycles);
    $display("  ciclos: %0d", cycles);
    $display("  retorno R6: %0d (0x%08h)", regs[6], regs[6]);
    output_count = dut.u_dmem.storage[OUT_COUNT_WORD];
    if ($isunknown(output_count) || output_count < 0 ||
        output_count > OUT_BUFFER_CAPACITY)
      $fatal(1, "contador de scribe invalido en DMEM: %0d", output_count);
    $display("  scribe en DMEM del procesador (%0d valores):", output_count);
    for (output_index = 0; output_index < output_count; output_index = output_index + 1)
      $display("    [%0d] %0d (0x%08h)", output_index,
               dut.u_dmem.storage[OUT_BUFFER_WORD + output_index],
               dut.u_dmem.storage[OUT_BUFFER_WORD + output_index]);
    if (regs[6] !== expected)
      $fatal(1, "retorno incorrecto: esperado %0d, obtenido %0d", expected, regs[6]);
    if (psw[`PSW_EXC] !== 1'b0)
      $fatal(1, "el procesador registro una excepcion, PSW=0x%08h", psw);
    if (psw[`PSW_AUTH] !== 1'b0)
      $fatal(1, "la sesion de la boveda no se cerro, PSW=0x%08h", psw);
    if (psw[`PSW_AUTHFAIL] !== 1'b0)
      $fatal(1, "fallo la autenticacion, PSW=0x%08h", psw);

    $display("RESULTADO: OK");
    $finish;
  end

endmodule
