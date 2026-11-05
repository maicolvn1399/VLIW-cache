`timescale 1ns/1ps

// =============================================================================
// mem_system.sv - Subsistema de memoria principal completo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Junta las cuatro piezas de la Iteracion 2 y expone hacia afuera una interfaz
// de LINEA, que es la que va a usar la cache L2 desde la Iteracion 4:
//
//     mem_clock_gen    el dominio de 25 MHz
//     mem_controller   la maquina de estados que modela T_mem
//     eviction_buffer  el FIFO de lineas sucias
//     main_memory      los 64 KB
//
// -----------------------------------------------------------------------------
// POR QUE LA INTERFAZ ES DE LINEA Y NO DE PALABRA
// -----------------------------------------------------------------------------
// La memoria principal de este sistema solo sabe mover lineas de 32 bytes:
// traer una palabra suelta cuesta exactamente lo mismo que traer las ocho, y
// escribir una sola tambien. Una interfaz de palabra esconderia ese hecho justo
// donde mas importa entenderlo.
//
// Ademas, el unico cliente que va a tener este modulo es la cache L2, y una
// cache habla en lineas por definicion. Darle una interfaz de palabra obligaria
// a la L2 a desarmar y rearmar lineas para nada.
//
// -----------------------------------------------------------------------------
// EL PROTOCOLO
// -----------------------------------------------------------------------------
// Lectura:   se levanta req con req_linea y se sostiene hasta ver listo. En el
//            ciclo de listo, linea_datos trae las ocho palabras. El controlador
//            ignora req durante ese ciclo, asi que soltar req al verlo o un
//            ciclo despues da lo mismo.
//
// Desalojo:  se levanta ev_push con la linea, sus datos y la mascara de cuales
//            palabras estan sucias. Se acepta en un ciclo, salvo que ev_lleno
//            este encendido: ahi quien desaloja tiene que esperar.
//
// El drenado no se pide: ocurre solo, cuando el bus esta libre.
//
// -----------------------------------------------------------------------------
// LO QUE ESTE MODULO TODAVIA NO HACE
// -----------------------------------------------------------------------------
// No se conecta al procesador. La Iteracion 2 lo deja verificado como bloque y
// mide su latencia real; la integracion con el pipeline, con los stalls que
// congelan el bundle completo, es el trabajo de la Iteracion 3, que es donde el
// enunciado la pone (secciones 3.3 y 7.1.3).
//
// Por eso top.sv no cambio en esta iteracion y los 31 testbenches del Proyecto
// I siguen pasando sin tocarles una linea.
// =============================================================================

`include "cerbero_defs.svh"

// Archivo de carga de la memoria principal. Tiene que ser una MACRO y no un
// parametro: Icarus Verilog 12 no puede pasar un parametro de tipo string de un
// modulo a un submodulo, y falla en elaboracion con "Unable to bind variable".
// Una macro se expande como literal en el sitio de la instancia, asi que no
// cruza ninguna frontera de modulo. Es la misma solucion que usan imem.sv y
// dmem.sv desde el Proyecto I, y esta explicada en top.sv.
//
// En simulacion los testbenches cargan la memoria por referencia jerarquica
// (dut.u_mem.storage), que no depende ni de archivos ni de rutas relativas.
`ifndef CERBERO_MAINMEM_FILE
  `define CERBERO_MAINMEM_FILE ""
`endif

module mem_system #(
    parameter int NUM_WORDS  = `MEM_WORDS,
    parameter int CLK_DIV    = `MEM_CLK_DIV,
    parameter int EV_ENTRIES = `EVICT_ENTRIES
) (
    input  logic clk,
    input  logic rst_n,

    // ---- Lectura de linea ----------------------------------------------------
    input  logic                     req,
    input  logic [`MEM_LIDX_W-1:0]   req_linea,
    output logic                     listo,
    output logic [`LINE_W-1:0]       linea_datos,

    // ---- Desalojo de linea sucia ---------------------------------------------
    input  logic                     ev_push,
    input  logic [`MEM_LIDX_W-1:0]   ev_linea,
    input  logic [`LINE_W-1:0]       ev_datos,
    input  logic [`LINE_WORDS-1:0]   ev_mascara,
    output logic                     ev_lleno,

    // ---- Observacion ----------------------------------------------------------
    output logic                     mem_clk,         // solo para la forma de onda
    output logic                     ocupado,
    output logic                     ev_vacio,
    output logic [`EVICT_IDX_W:0]    ev_ocupadas,
    output logic                     raw_conflicto,
    output logic                     inicia_lectura,
    output logic                     inicia_drenado
);

  logic tick;

  mem_clock_gen #(.DIV (CLK_DIV)) u_clk (
      .clk      (clk),
      .rst_n    (rst_n),
      .mem_clk  (mem_clk),
      .mem_tick (tick)
  );

  // ---- Eviction buffer -------------------------------------------------------

  logic                    ev_head_valido;
  logic [`MEM_LIDX_W-1:0]  ev_head_linea;
  logic [`LINE_W-1:0]      ev_head_datos;
  logic [`LINE_WORDS-1:0]  ev_head_mascara;
  logic                    ev_head_ack;

  eviction_buffer #(.ENTRIES (EV_ENTRIES)) u_evict (
      .clk            (clk),
      .rst_n          (rst_n),
      .push           (ev_push),
      .push_linea     (ev_linea),
      .push_datos     (ev_datos),
      .push_mascara   (ev_mascara),
      .head_valido    (ev_head_valido),
      .head_linea     (ev_head_linea),
      .head_datos     (ev_head_datos),
      .head_mascara   (ev_head_mascara),
      .head_ack       (ev_head_ack),
      // La consulta de conflicto es siempre la linea que se esta pidiendo: si
      // esa linea tiene escrituras pendientes, leerla de memoria daria el valor
      // viejo.
      .consulta_linea (req_linea),
      .conflicto      (raw_conflicto),
      .lleno          (ev_lleno),
      .vacio          (ev_vacio),
      .ocupadas       (ev_ocupadas)
  );

  // ---- Controlador -----------------------------------------------------------

  logic [`XLEN-1:0] mem_addr, mem_wdata, mem_rdata;
  logic             mem_we;

  mem_controller u_ctrl (
      .clk            (clk),
      .rst_n          (rst_n),
      .tick           (tick),
      .req            (req),
      .req_linea      (req_linea),
      .listo          (listo),
      .linea_datos    (linea_datos),
      .ocupado        (ocupado),
      .ev_valido      (ev_head_valido),
      .ev_linea       (ev_head_linea),
      .ev_datos       (ev_head_datos),
      .ev_mascara     (ev_head_mascara),
      .ev_conflicto   (raw_conflicto),
      .ev_ack         (ev_head_ack),
      .mem_addr       (mem_addr),
      .mem_we         (mem_we),
      .mem_wdata      (mem_wdata),
      .mem_rdata      (mem_rdata),
      .inicia_lectura (inicia_lectura),
      .inicia_drenado (inicia_drenado)
  );

  // ---- Memoria ---------------------------------------------------------------

  main_memory #(
      .NUM_WORDS (NUM_WORDS),
      .INIT_FILE (`CERBERO_MAINMEM_FILE)
  ) u_mem (
      .clk   (clk),
      .rst_n (rst_n),
      .tick  (tick),
      .addr  (mem_addr),
      .we    (mem_we),
      .wdata (mem_wdata),
      .rdata (mem_rdata)
  );

endmodule
