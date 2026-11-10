`timescale 1ns/1ps

// =============================================================================
// l2_arbiter.sv - Arbitrador entre L1-D y el Write Buffer hacia la Caché L2.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Implementación del Issue [L2-02]:
// Multiplexa las peticiones de lectura (provenientes de L1-D) y las peticiones 
// de escritura (drenados del Write Buffer) hacia el único puerto de la caché L2.
//
// - Otorga prioridad estricta a las lecturas para evitar stalls en el procesador.
// - Implementa 'wb_drenando' mapeada a 'head_ocupada' del eviction_buffer para
//   prevenir que se fusionen datos nuevos en la cabeza mientras la L2 la escribe.
// =============================================================================

`include "cerbero_defs.svh"

module l2_arbiter (
    input  logic clk,
    input  logic rst_n,

    // ---- Peticiones de lectura desde L1-D (mem_req) -------------------------
    input  logic                     l1_req,
    input  logic [`MEM_LIDX_W-1:0]   l1_linea,
    output logic                     l1_listo,
    output logic [`LINE_W-1:0]       l1_rdata,

    // ---- Peticiones de escritura desde el Write Buffer (L1 -> L2) -----------
    input  logic                     wb_req,        // head_valido
    input  logic [`MEM_LIDX_W-1:0]   wb_linea,      // head_linea
    input  logic [`LINE_W-1:0]       wb_datos,      // head_datos
    input  logic [`LINE_MASK_W-1:0]  wb_mascara,    // head_mascara
    output logic                     wb_ack,        // head_ack
    output logic                     wb_drenando,   // head_ocupada

    // ---- Interfaz hacia la Caché L2 unificada -------------------------------
    output logic                     l2_req_lectura,
    output logic                     l2_req_escritura,
    output logic [`MEM_LIDX_W-1:0]   l2_req_linea,
    output logic [`LINE_W-1:0]       l2_req_wdata,
    output logic [`LINE_MASK_W-1:0]  l2_req_wmask,
    input  logic [`LINE_W-1:0]       l2_rdata,
    input  logic                     l2_listo
);

  typedef enum logic [1:0] {
      LIBRE,
      SIRVIENDO_L1,
      SIRVIENDO_WB
  } estado_arb_t;

  estado_arb_t estado, proximo_estado;

  always_ff @(posedge clk) begin
      if (!rst_n) estado <= LIBRE;
      else        estado <= proximo_estado;
  end

  always_comb begin
      proximo_estado   = estado;
      
      l2_req_lectura   = 1'b0;
      l2_req_escritura = 1'b0;
      l2_req_linea     = '0;
      l2_req_wdata     = '0;
      l2_req_wmask     = '0;
      
      l1_listo         = 1'b0;
      wb_ack           = 1'b0;
      wb_drenando      = 1'b0;
      
      case (estado)
          LIBRE: begin
              // Prioridad estricta a L1. Si hay conflicto RAW, la L1 ya está
              // reteniendo su mem_req gracias al diseño en l1_dcache.sv.
              if (l1_req) begin
                  proximo_estado = SIRVIENDO_L1;
              end else if (wb_req) begin
                  proximo_estado = SIRVIENDO_WB;
              end
          end

          SIRVIENDO_L1: begin
              l2_req_lectura = 1'b1;
              l2_req_linea   = l1_linea;
              
              // Se mantiene el estado hasta que la L2 termine la latencia
              if (l2_listo) begin
                  l1_listo       = 1'b1;
                  proximo_estado = LIBRE;
              end
          end

          SIRVIENDO_WB: begin
              l2_req_escritura = 1'b1;
              l2_req_linea     = wb_linea;
              l2_req_wdata     = wb_datos;
              l2_req_wmask     = wb_mascara;
              wb_drenando      = 1'b1; // Excluye la cabeza de la fusión
              
              if (l2_listo) begin
                  wb_ack         = 1'b1;
                  proximo_estado = LIBRE;
              end
          end
          
          default: proximo_estado = LIBRE;
      endcase
  end

  // Camino de retorno de datos hacia la L1
  assign l1_rdata = l2_rdata;

endmodule