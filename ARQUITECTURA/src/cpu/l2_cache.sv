`timescale 1ns/1ps

// =============================================================================
// l2_cache.sv - Cache unificada de segundo nivel (N-Vías, LRU exacto).
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Implementación del Issue [L2-01]:
// - Generalización a N-vías paramétrica (bloques generate).
// - Política de reemplazo LRU exacto mediante matriz de edades.
// - Máquina de estados con políticas Write-Back y Write-Allocate.
// - Optimización de latencia: bypass de memoria en sobrescrituras de 32B.
//
// Implementación del Issue [L2-03]: Invalidación hacia atrás.
// - Se exponen 'l2_inv_req' y 'l2_inv_linea' hacia L1-D.
// - Cuando una línea válida se desaloja de L2 (ya sea a EVICT por estar sucia o
//   se sobreescribe limpiamente en ACTUALIZAR), la señal l2_inv_req se levanta 
//   para forzar a la L1 a descartarla.
//
// Esta caché se interpone entre las cachés L1 (y sus Write Buffers) y el 
// subsistema de memoria principal (mem_system.sv).
// =============================================================================

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

    // ---- Interfaz hacia arriba (Invalidación Hacia Atrás para L1-D) ---------
    output logic                     l2_inv_req,
    output logic [`MEM_LIDX_W-1:0]   l2_inv_linea,

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

  // ===========================================================================
  // 5. Máquina de Estados L2 (Write-Back y Write-Allocate)
  // ===========================================================================

  typedef enum logic [2:0] {
      ESPERA,
      LATENCIA,  // Simula los 8 ciclos de hit time
      EVALUAR,   // Decide si es hit, miss sucio o miss limpio
      EVICT,     // Expulsión de la víctima sucia hacia el Eviction Buffer
      ALLOCATE,  // Traer nueva línea desde memoria (si aplica)
      ACTUALIZAR // Insertar línea en caché y levantar 'listo'
  } estado_l2_t;

  estado_l2_t estado, proximo_estado;
  logic [2:0] contador_latencia;

  always_ff @(posedge clk) begin
      if (!rst_n) estado <= ESPERA;
      else        estado <= proximo_estado;
  end

  always_comb begin
      proximo_estado = estado;
      case (estado)
          ESPERA: begin
              if (req_lectura || req_escritura) proximo_estado = LATENCIA;
          end
          
          LATENCIA: begin
              // Hit time emulado de 8 ciclos (el contador arranca en 7)
              if (contador_latencia == 0) proximo_estado = EVALUAR;
          end

          EVALUAR: begin
              if (acierto) begin
                  proximo_estado = ESPERA; 
              end else begin
                  // Fallo: ¿la víctima está sucia?
                  if (valido[via_victima][conjunto] && sucio[via_victima][conjunto]) 
                      proximo_estado = EVICT;
                  else 
                      proximo_estado = ALLOCATE;
              end
          end
          
          EVICT: begin
              // Si el eviction buffer no está lleno, el depósito entra en 1 ciclo
              if (!ev_lleno) proximo_estado = ALLOCATE; 
          end
          
          ALLOCATE: begin
              // Bypass total: si se escriben los 32B completos, no necesitamos leer memoria
              if (req_escritura && mascara_completa_32B) 
                  proximo_estado = ACTUALIZAR;
              else if (mem_listo) 
                  proximo_estado = ACTUALIZAR;
          end
          
          ACTUALIZAR: begin
              proximo_estado = ESPERA;
          end
          
          default: proximo_estado = ESPERA;
      endcase
  end

  // ===========================================================================
  // 6. Señales de Control e Interfaz
  // ===========================================================================

  // Hacia la memoria principal (lectura)
  assign mem_req   = (estado == ALLOCATE) && !(req_escritura && mascara_completa_32B);
  assign mem_linea = req_linea;

  // Hacia el eviction buffer (desalojo)
  assign ev_push    = (estado == EVICT) && !ev_lleno;
  assign ev_linea   = {etiqueta[via_victima][conjunto], conjunto};
  assign ev_datos   = datos[via_victima][conjunto];
  assign ev_mascara = {`LINE_MASK_W{1'b1}}; // L2 siempre expulsa líneas enteras

  // Hacia arriba (L1 - Invalidación Hacia Atrás)
  // Se reporta la línea que se reemplazará si la víctima era una entrada válida, 
  // independientemente de si estaba sucia (EVICT) o limpia (ALLOCATE -> ACTUALIZAR).
  assign l2_inv_req   = (estado == ACTUALIZAR && valido[via_victima][conjunto]) || 
                        (estado == EVALUAR && proximo_estado == EVICT);
  assign l2_inv_linea = {etiqueta[via_victima][conjunto], conjunto};

  // Hacia arriba (L1 - Respuestas)
  assign listo = ((estado == EVALUAR) && acierto) || (estado == ACTUALIZAR);
  assign rdata = acierto ? datos[via_acertada][conjunto] : datos_mezclados;

  // ===========================================================================
  // 7. Lógica Secuencial (Actualización de Datos y LRU)
  // ===========================================================================

  integer v, s;

  always_ff @(posedge clk) begin
      if (!rst_n) begin
          contador_latencia <= '0;
          for (v = 0; v < WAYS; v++) begin
              for (s = 0; s < SETS; s++) begin
                  valido[v][s] <= 1'b0;
                  sucio[v][s]  <= 1'b0;
                  edades[v][s] <= v[WAY_W-1:0]; // Inicialización escalonada del LRU
              end
          end
      end else begin
          case (estado)
              ESPERA: begin
                  if (req_lectura || req_escritura) begin
                      contador_latencia <= 3'd7; // 8 ciclos de penalización de hit
                  end
              end
              
              LATENCIA: begin
                  contador_latencia <= contador_latencia - 1'b1;
              end
              
              EVALUAR: begin
                  if (acierto) begin
                      // ---- UPDATE HIT: Datos y Suciedad ----
                      if (req_escritura) begin
                          sucio[via_acertada][conjunto] <= 1'b1;
                          for (int b = 0; b < `LINE_BYTES; b++) begin
                              if (req_wmask[b]) 
                                  datos[via_acertada][conjunto][b*8 +: 8] <= req_wdata[b*8 +: 8];
                          end
                      end
                      
                      // ---- UPDATE HIT: Edades LRU ----
                      for (int v = 0; v < WAYS; v++) begin
                          if (v == via_acertada) begin
                              edades[v][conjunto] <= '0; // Rejuvenece a 0
                          end else if (edades[v][conjunto] < edades[via_acertada][conjunto]) begin
                              edades[v][conjunto] <= edades[v][conjunto] + 1'b1; // Envejecen los más recientes
                          end
                      end
                  end
              end

              ACTUALIZAR: begin
                  // ---- UPDATE MISS: Insertar nueva línea en la víctima ----
                  valido[via_victima][conjunto]   <= 1'b1;
                  etiqueta[via_victima][conjunto] <= tag_buscado;
                  
                  if (req_escritura) begin
                      sucio[via_victima][conjunto] <= 1'b1;
                      if (mascara_completa_32B)
                          datos[via_victima][conjunto] <= req_wdata;
                      else
                          datos[via_victima][conjunto] <= datos_mezclados;
                  end else begin
                      sucio[via_victima][conjunto] <= 1'b0;
                      datos[via_victima][conjunto] <= mem_datos;
                  end

                  // ---- UPDATE MISS: Edades LRU ----
                  for (int v = 0; v < WAYS; v++) begin
                      if (v == via_victima) begin
                          edades[v][conjunto] <= '0; // La víctima pasa a ser la más joven
                      end else begin
                          edades[v][conjunto] <= edades[v][conjunto] + 1'b1; // El resto envejece inevitablemente
                      end
                  end
              end
          endcase
      end
  end

endmodule