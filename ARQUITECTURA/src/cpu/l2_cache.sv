`timescale 1ns/1ps
`include "cerbero_defs.svh"

module l2_cache #(
    parameter int WAYS = 4,
    parameter int SETS = 128
) (
    input  logic clk,
    input  logic rst_n,

    // ---- Interfaz hacia arriba (Cachés L1 / Write Buffer) -------------------
    input  logic                     req_lectura,
    input  logic                     req_escritura,
    input  logic [`MEM_LIDX_W-1:0]   req_linea,
    input  logic [`LINE_W-1:0]       req_wdata,
    input  logic [`LINE_MASK_W-1:0]  req_wmask,
    
    output logic [`LINE_W-1:0]       rdata,
    output logic                     listo,

    // ---- Interfaz hacia abajo (Memoria Principal para lecturas/rellenos) ----
    output logic                     mem_req,
    output logic [`MEM_LIDX_W-1:0]   mem_linea,
    input  logic                     mem_listo,
    input  logic [`LINE_W-1:0]       mem_datos,

    // ---- Interfaz hacia abajo (Eviction Buffer para desalojos) --------------
    output logic                     ev_push,
    output logic [`MEM_LIDX_W-1:0]   ev_linea,
    output logic [`LINE_W-1:0]       ev_datos,
    output logic [`LINE_MASK_W-1:0]  ev_mascara,
    input  logic                     ev_lleno
);

  // ===========================================================================
  // 1. Definición Estructural de Arreglos y Direcciones
  // ===========================================================================

  localparam int SET_W = $clog2(SETS);
  localparam int TAG_W = `MEM_LIDX_W - SET_W;
  localparam int WAY_W = $clog2(WAYS);

  // Arreglos de memoria estática
  logic [TAG_W-1:0] etiqueta [0:WAYS-1][0:SETS-1];
  logic             valido   [0:WAYS-1][0:SETS-1];
  logic             sucio    [0:WAYS-1][0:SETS-1];
  logic [`LINE_W-1:0] datos  [0:WAYS-1][0:SETS-1];

  // Descomposición de la dirección solicitada
  logic [TAG_W-1:0] tag_buscado;
  logic [SET_W-1:0] conjunto;
  
  assign tag_buscado = req_linea[SET_W +: TAG_W];
  assign conjunto    = req_linea[0 +: SET_W];

  // ===========================================================================
  // 2. Búsqueda Paramétrica N-Vías
  // ===========================================================================

  logic [WAYS-1:0] acierto_via;
  logic            acierto;
  logic [WAY_W-1:0] via_acertada;

  // Generación combinacional de los comparadores
  genvar i;
  generate
      for (i = 0; i < WAYS; i++) begin : gen_comparadores
          assign acierto_via[i] = valido[i][conjunto] && (etiqueta[i][conjunto] == tag_buscado);
      end
  endgenerate

  // Reducción lógica: acierto global si cualquier vía levanta bandera
  assign acierto = |acierto_via;

  // Codificador de prioridad inverso (identifica el índice de la vía que acertó)
  always_comb begin
      via_acertada = '0;
      for (int v = 0; v < WAYS; v++) begin
          if (acierto_via[v]) via_acertada = v[WAY_W-1:0];
      end
  end

  // ===========================================================================
  // 3. Matriz de Edades y Víctima LRU Exacto
  // ===========================================================================

  logic [WAY_W-1:0] edades [0:WAYS-1][0:SETS-1];
  logic [WAY_W-1:0] via_victima;

  // Búsqueda de la víctima: la línea con la edad máxima (WAYS - 1)
  always_comb begin
      via_victima = '0;
      for (int v = 0; v < WAYS; v++) begin
          if (edades[v][conjunto] == (WAYS - 1)) begin
              via_victima = v[WAY_W-1:0];
          end
      end
  end

  // ===========================================================================
  // 4. Lógica de Fusión y Bypass
  // ===========================================================================

  logic mascara_completa_32B;
  assign mascara_completa_32B = (req_wmask == {`LINE_MASK_W{1'b1}});

  // Mezcla de datos para Write-Allocate parcial
  logic [`LINE_W-1:0] datos_mezclados;
  always_comb begin
      for (int b = 0; b < `LINE_BYTES; b++) begin
          if (req_wmask[b])
              datos_mezclados[b*8 +: 8] = req_wdata[b*8 +: 8];
          else
              datos_mezclados[b*8 +: 8] = mem_datos[b*8 +: 8];
      end
  end