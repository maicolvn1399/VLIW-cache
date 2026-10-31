`timescale 1ns/1ps

`include "cerbero_defs.svh"

module tb_sum;

  localparam int N_BUNDLES = 64;
  localparam int N_WORDS   = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic halted;
  logic [`XLEN-1:0] psw;
  logic [`NREGS-1:0][`XLEN-1:0] regs;

  top #(
      .NUM_BUNDLES (N_BUNDLES),
      .NUM_WORDS   (N_WORDS),
      .RESET_PC    (32'h0000_0000)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs)
  );

  integer cycles;

  initial begin
    $display("=== tb_sum: suma 10 + 15 en el procesador ===");

    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < 100) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    if (!halted) begin
      $display("  FALLA  el procesador no se detuvo");
      $fatal(1, "timeout ejecutando suma_10_15.s");
    end
    $display("  ok     el procesador se detuvo tras %0d ciclos", cycles);

    $display("  resultado: 10 + 15 = %0d (0x%08h)", regs[3], regs[3]);
    if (regs[3] !== 32'd25) begin
      $display("  FALLA  R3 deberia contener 25");
      $fatal(1, "resultado incorrecto: R3=%08h, esperado=00000019", regs[3]);
    end
    $display("  ok     R3 contiene la suma esperada");

    if (psw[`PSW_EXC] !== 1'b0) begin
      $display("  FALLA  el PSW registro una excepcion");
      $fatal(1, "PSW_EXC esta activo");
    end
    $display("  ok     sin excepciones");
    $display("RESULTADO: OK");
    $finish;
  end

endmodule
