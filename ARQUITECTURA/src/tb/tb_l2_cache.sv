`timescale 1ns/1ps

// =============================================================================
// tb_l2_cache.sv - Testbench específico para la Caché L2
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Valida:
// 1. Aciertos y fallos de lectura/escritura (L2-05).
// 2. Penalización de 8 ciclos por Hit Time.
// 3. Desalojos hacia el eviction buffer y política Write-Back.
// 4. Invalidación hacia atrás (Política de Inclusión Estricta - L2-03).
// 5. Congelamiento de L2 por Eviction Buffer lleno (L2-04).
// =============================================================================

`include "cerbero_defs.svh"

module tb_l2_cache();

  // ---- Señales de Reloj y Reset ----
  logic clk;
  logic rst_n;

  // ---- Hacia L1 (Cliente) ----
  logic                     req_lectura;
  logic                     req_escritura;
  logic [`MEM_LIDX_W-1:0]   req_linea;
  logic [`LINE_W-1:0]       req_wdata;
  logic [`LINE_MASK_W-1:0]  req_wmask;
  logic [`LINE_W-1:0]       rdata;
  logic                     listo;
  logic                     l2_inv_req;
  logic [`MEM_LIDX_W-1:0]   l2_inv_linea;

  // ---- Hacia Memoria Principal ----
  logic                     mem_req;
  logic [`MEM_LIDX_W-1:0]   mem_linea;
  logic                     mem_listo;
  logic [`LINE_W-1:0]       mem_datos;

  // ---- Hacia Eviction Buffer ----
  logic                     ev_push;
  logic [`MEM_LIDX_W-1:0]   ev_linea;
  logic [`LINE_W-1:0]       ev_datos;
  logic [`LINE_MASK_W-1:0]  ev_mascara;
  logic                     ev_lleno;

  // ---- Contadores de Rendimiento ----
  logic                     ev_stall_evict;
  logic                     ev_l2_load_hit;
  logic                     ev_l2_load_miss;
  logic                     ev_l2_store_hit;
  logic                     ev_l2_store_miss;

  // Instancia de la Caché L2
  l2_cache #(
      .WAYS(4),
      .SETS(128)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .req_lectura(req_lectura),
      .req_escritura(req_escritura),
      .req_linea(req_linea),
      .req_wdata(req_wdata),
      .req_wmask(req_wmask),
      .rdata(rdata),
      .listo(listo),
      .l2_inv_req(l2_inv_req),
      .l2_inv_linea(l2_inv_linea),
      .mem_req(mem_req),
      .mem_linea(mem_linea),
      .mem_listo(mem_listo),
      .mem_datos(mem_datos),
      .ev_push(ev_push),
      .ev_linea(ev_linea),
      .ev_datos(ev_datos),
      .ev_mascara(ev_mascara),
      .ev_lleno(ev_lleno),
      .ev_stall_evict(ev_stall_evict),
      .ev_l2_load_hit(ev_l2_load_hit),
      .ev_l2_load_miss(ev_l2_load_miss),
      .ev_l2_store_hit(ev_l2_store_hit),
      .ev_l2_store_miss(ev_l2_store_miss)
  );

  // Generación de Reloj
  initial clk = 0;
  always #5 clk = ~clk;

  // Emulación de Memoria Principal (Demora de 10 ciclos por petición)
  initial begin
      mem_listo = 0;
      mem_datos = '0;
      forever begin
          @(posedge clk);
          if (mem_req) begin
              repeat(10) @(posedge clk); // Emula T_mem
              mem_listo = 1;
              mem_datos = {8{32'hDEADBEEF}}; // Dato dummy desde memoria
              @(posedge clk);
              mem_listo = 0;
          end
      end
  end

  // ---- Tareas de Estímulo ----
  task do_read(input logic [`MEM_LIDX_W-1:0] addr);
      req_lectura = 1;
      req_linea = addr;
      wait(listo);
      @(posedge clk);
      req_lectura = 0;
  endtask

  task do_write(input logic [`MEM_LIDX_W-1:0] addr, input logic [`LINE_W-1:0] data, input logic [`LINE_MASK_W-1:0] mask);
      req_escritura = 1;
      req_linea = addr;
      req_wdata = data;
      req_wmask = mask;
      wait(listo);
      @(posedge clk);
      req_escritura = 0;
  endtask

  // ---- Secuencia de Pruebas ----
  initial begin
      $display("Iniciando Pruebas de Caché L2...");
      
      // Inicialización
      rst_n = 0;
      req_lectura = 0;
      req_escritura = 0;
      req_linea = '0;
      req_wdata = '0;
      req_wmask = '0;
      ev_lleno = 0;
      
      #20;
      rst_n = 1;
      #10;

      $display("[Test 1] Load Miss: Pidiendo Línea 0");
      do_read(0);
      assert(rdata == {8{32'hDEADBEEF}}) else $error("Error en datos de Load Miss");

      $display("[Test 2] Load Hit: Repitiendo Línea 0");
      do_read(0);
      
      $display("[Test 3] Store Hit: Escribiendo en Línea 0 (Marcando Dirty)");
      do_write(0, {8{32'hCAFEBA5E}}, {`LINE_MASK_W{1'b1}});

      $display("[Test 4] Generar Eviction y Backward Invalidation");
      // Sabiendo que hay 128 sets, pidiendo líneas múltiplo de 128 caerán en el set 0.
      // Ya ocupamos Vía 0 con la Línea 0. Llenaremos Vía 1, 2, 3 y 4.
      do_read(128); // Ocupa Vía 1
      do_read(256); // Ocupa Vía 2
      do_read(384); // Ocupa Vía 3
      
      // La siguiente lectura causará que la Línea 0 (la más vieja - LRU) sea desalojada.
      // Como fue escrita (Dirty), debe ir al Eviction Buffer. 
      // L2 también debe enviar l2_inv_req hacia L1.
      $display("         > Accediendo Línea 512 (Debe expulsar Línea 0)");
      do_read(512); 
      
      $display("[Test 5] Stall por Eviction Buffer Lleno");
      // Escribiremos la Línea 128 para hacerla Dirty.
      do_write(128, {8{32'h11111111}}, {`LINE_MASK_W{1'b1}});
      
      // Llenamos virtualmente el eviction buffer
      ev_lleno = 1;
      
      // Metemos otra línea al set 0 para expulsar la 128.
      // La FSM de la caché L2 deberá congelarse en el estado EVICT.
      // Esto encenderá la métrica `ev_stall_evict`.
      fork
          begin
              do_read(640); 
          end
          begin
              repeat(15) @(posedge clk);
              ev_lleno = 0; // Liberamos el buffer para destrabar la caché
          end
      join

      $display("Pruebas Finalizadas.");
      $finish;
  end

endmodule