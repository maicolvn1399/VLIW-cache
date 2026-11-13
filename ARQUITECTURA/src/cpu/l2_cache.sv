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

    // ---- Vaciado (flush) ----------------------------------------------------
    // Con write-back, una linea sucia solo sale de la L2 cuando alguien pide su
    // conjunto. Si el programa termina antes, el dato se queda adentro y nunca
    // llega a memoria principal. Por eso hace falta un vaciado explicito: es la
    // operacion de flush que cualquier jerarquia con un nivel write-back
    // necesita, no un parche para las pruebas.
    //
    //   vaciar       lo levanta top.sv cuando el pipeline ya se detuvo y no
    //                queda nada en vuelo aguas arriba
    //   tiene_sucias es la condicion de parada: mientras este en alto, quedan
    //                datos que no estan en memoria, y mem_drenada no puede
    //                levantarse
    input  logic                     vaciar,
    output logic                     tiene_sucias,

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
    input  logic                     ev_lleno,

    // ---- Contadores de rendimiento [ISSUE L2-04 y L2-05] --------------------
    output logic                     ev_stall_evict,
    output logic                     ev_l2_load_hit,
    output logic                     ev_l2_load_miss,
    output logic                     ev_l2_store_hit,
    output logic                     ev_l2_store_miss
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
      // Se usa una conversion de ancho, WAY_W'(v), y no un recorte de bits,
      // v[WAY_W-1:0]: el recorte dentro de un always_* Icarus no lo soporta
      // ("sorry: constant selects in always_* processes") y se lleva todos los
      // bits. La conversion dice lo mismo y si la acepta.
      for (int v = 0; v < WAYS; v++) begin
          if (acierto_via[v]) via_acertada = WAY_W'(v);
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
          if (edades[v][conjunto] == WAY_W'(WAYS - 1)) begin
              via_victima = WAY_W'(v);
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
      ACTUALIZAR,// Insertar línea en caché y levantar 'listo'
      VACIANDO   // Recorre toda la cache empujando lo que quedo sucio
  } estado_l2_t;

  estado_l2_t estado, proximo_estado;

  // El contador se dimensiona desde la macro en vez de fijarlo en 3 bits: asi
  // cambiar L2_HIT_CYCLES en cerbero_defs.svh de verdad cambia la latencia, que
  // es la convencion del resto del proyecto (T_mem se comprueba igual).
  localparam int LAT_W = (`L2_HIT_CYCLES <= 1) ? 1 : $clog2(`L2_HIT_CYCLES);
  logic [LAT_W-1:0] contador_latencia;

  // ---- Recorrido del vaciado -----------------------------------------------
  // Un solo contador recorre los pares (via, conjunto). El bit de mas arriba
  // avisa que ya se dio la vuelta completa.
  localparam int VAC_W = SET_W + WAY_W;
  logic [VAC_W:0]    vac_idx;
  logic [SET_W-1:0]  vac_conjunto;
  logic [WAY_W-1:0]  vac_via;
  logic              vac_fin, vac_sucia;

  assign vac_conjunto = vac_idx[SET_W-1:0];
  assign vac_via      = vac_idx[SET_W +: WAY_W];
  assign vac_fin      = vac_idx[VAC_W];
  assign vac_sucia    = !vac_fin && valido[vac_via][vac_conjunto]
                                 && sucio [vac_via][vac_conjunto];

  // Condicion de parada para mem_drenada: queda algo sin escribir en memoria.
  always_comb begin
      tiene_sucias = 1'b0;
      for (int v = 0; v < WAYS; v++)
          for (int s = 0; s < SETS; s++)
              if (valido[v][s] && sucio[v][s]) tiene_sucias = 1'b1;
  end

  always_ff @(posedge clk) begin
      if (!rst_n) estado <= ESPERA;
      else        estado <= proximo_estado;
  end

  always_comb begin
      proximo_estado = estado;
      case (estado)
          ESPERA: begin
              // Una peticion real siempre gana sobre el vaciado: el vaciado
              // solo corre cuando ya no hay nadie pidiendo nada.
              if (req_lectura || req_escritura)      proximo_estado = LATENCIA;
              else if (vaciar && tiene_sucias)       proximo_estado = VACIANDO;
          end

          VACIANDO: begin
              // Se recorre toda la cache una vez. Se sale al terminar la
              // vuelta, o antes si aparece una peticion de verdad.
              if (req_lectura || req_escritura) proximo_estado = LATENCIA;
              else if (vac_fin)                 proximo_estado = ESPERA;
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
  // El !mem_listo del final es el CONTRATO con mem_controller.sv, escrito en
  // su cabecera desde la Iteracion 2: req tiene que bajar durante el ciclo en
  // que el cliente ve listo encendido.
  //
  // El motivo es que listo y el regreso a LIBRE del controlador ocurren en el
  // mismo flanco, asi que durante el ciclo de listo la maquina ya esta libre y
  // vuelve a mirar req. Sin este termino, el controlador lee el pedido viejo
  // como uno nuevo y arranca una segunda lectura de 53 ciclos; cuando esa
  // lectura fantasma termina, entrega SUS datos al relleno que este en curso
  // en ese momento, que ya es el de otra linea. El sintoma era una linea
  // llenada con el contenido de la anterior.
  //
  // La L1 cumple el mismo contrato con su '!mem_listo' en el estado LLENA.
  assign mem_req   = (estado == ALLOCATE)
                  && !(req_escritura && mascara_completa_32B)
                  && !mem_listo;
  assign mem_linea = req_linea;

  // Hacia el eviction buffer (desalojo). Hay dos fuentes: el desalojo normal
  // por reemplazo (EVICT) y el vaciado de fin de programa (VACIANDO), que
  // recorre la cache con sus propios indices.
  assign ev_push    = ((estado == EVICT)    && !ev_lleno)
                   || ((estado == VACIANDO) && vac_sucia && !ev_lleno);

  assign ev_linea   = (estado == VACIANDO)
                        ? {etiqueta[vac_via][vac_conjunto], vac_conjunto}
                        : {etiqueta[via_victima][conjunto], conjunto};

  assign ev_datos   = (estado == VACIANDO)
                        ? datos[vac_via][vac_conjunto]
                        : datos[via_victima][conjunto];

  assign ev_mascara = {`LINE_MASK_W{1'b1}}; // L2 siempre expulsa líneas enteras

  // El L2 se detiene si necesita expulsar una línea pero el Eviction Buffer
  // de la memoria principal está lleno. Esto genera el contador 22.
  // El vaciado no cuenta aqui: ocurre con el procesador ya detenido, asi que
  // no le hace perder ciclos a nadie y sumarlo falsearia la metrica.
  assign ev_stall_evict = (estado == EVICT) && ev_lleno;

  // Hacia arriba (L1 - Invalidación Hacia Atrás)
  // Se reporta la línea que se reemplazará si la víctima era una entrada válida, 
  // independientemente de si estaba sucia (EVICT) o limpia (ALLOCATE -> ACTUALIZAR).
  assign l2_inv_req   = (estado == ACTUALIZAR && valido[via_victima][conjunto]) || 
                        (estado == EVALUAR && proximo_estado == EVICT);
  assign l2_inv_linea = {etiqueta[via_victima][conjunto], conjunto};

  // Hacia arriba (L1 - Respuestas)
  assign listo = ((estado == EVALUAR) && acierto) || (estado == ACTUALIZAR);
  assign rdata = acierto ? datos[via_acertada][conjunto] : datos_mezclados;

  // ---- Eventos de Rendimiento L2 [ISSUE L2-05] ----
  // Los eventos ocurren exclusivamente en el estado EVALUAR, donde 
  // la caché resuelve si la petición entrante es un hit o un miss.
  assign ev_l2_load_hit   = (estado == EVALUAR) && req_lectura   &&  acierto;
  assign ev_l2_load_miss  = (estado == EVALUAR) && req_lectura   && !acierto;
  assign ev_l2_store_hit  = (estado == EVALUAR) && req_escritura &&  acierto;
  assign ev_l2_store_miss = (estado == EVALUAR) && req_escritura && !acierto;

  // ===========================================================================
  // 7. Lógica Secuencial (Actualización de Datos y LRU)
  // ===========================================================================

  integer v, s;

  always_ff @(posedge clk) begin
      if (!rst_n) begin
          contador_latencia <= '0;
          vac_idx           <= '0;
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
                      // El contador arranca en L2_HIT_CYCLES-3 para que el
                      // acierto cueste EXACTAMENTE lo que dice la macro,
                      // medido de la peticion a listo. Son tres los ciclos que
                      // no pasa contando: el de ESPERA en que acepta la
                      // peticion, el de EVALUAR en que resuelve y levanta
                      // listo, y el ultimo de LATENCIA, en que el contador ya
                      // vale cero y la maquina esta saliendo.
                      //
                      // Es el mismo ajuste que mem_controller.sv hace con
                      // 'faltan <= MEM_FIRST_WORD - 2' para que T_mem de 53 y
                      // no 54. Un tiempo que no coincide con su macro no se
                      // puede contrastar, y contrastarlo es justamente lo que
                      // hace tb_l2_cache.sv.
                      contador_latencia <= LAT_W'(`L2_HIT_CYCLES - 3);
                  end
                  // Cada vaciado empieza su recorrido desde el principio
                  vac_idx <= '0;
              end

              LATENCIA: begin
                  contador_latencia <= contador_latencia - 1'b1;
              end

              VACIANDO: begin
                  // Se avanza cuando la entrada no esta sucia (no hay nada que
                  // escribir) o cuando si lo esta y el eviction buffer la
                  // acepto. Si el buffer esta lleno, se espera sin avanzar.
                  if (!vac_fin) begin
                      if (!vac_sucia) begin
                          vac_idx <= vac_idx + 1'b1;
                      end
                      else if (!ev_lleno) begin
                          // Ya quedo entregada al buffer: dejarla limpia para
                          // que tiene_sucias pueda bajar y no se escriba dos
                          // veces si alguien vuelve a pedir un vaciado.
                          sucio[vac_via][vac_conjunto] <= 1'b0;
                          vac_idx <= vac_idx + 1'b1;
                      end
                  end
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