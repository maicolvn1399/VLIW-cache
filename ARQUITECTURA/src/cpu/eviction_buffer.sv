`timescale 1ns/1ps

// =============================================================================
// eviction_buffer.sv - FIFO de lineas sucias hacia memoria principal.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// El enunciado (seccion 3.4) lo hace obligatorio, con independencia de las
// politicas de escritura, reemplazo e inclusion que elija el grupo. Su trabajo
// es que un desalojo no bloquee la traida de la linea que lo provoco.
//
// -----------------------------------------------------------------------------
// QUE PROBLEMA RESUELVE
// -----------------------------------------------------------------------------
// Cuando un nivel de cache desaloja una linea sucia para hacerle lugar a otra,
// hay dos transacciones de memoria en juego: escribir la vieja y leer la nueva.
// Encadenarlas costaria 2 * T_mem = 106 ciclos, y el procesador esta detenido
// todo ese tiempo esperando la nueva.
//
// El buffer rompe la cadena: el desalojo se deposita aqui en UN ciclo y el
// controlador arranca de inmediato la lectura. La escritura se drena despues,
// cuando el bus este libre, con el procesador ya corriendo. El costo visible
// vuelve a ser T_mem en vez de 2 * T_mem.
//
// -----------------------------------------------------------------------------
// EL RIESGO RAW, Y POR QUE AQUI SE RESUELVE CON STALL
// -----------------------------------------------------------------------------
// Diferir una escritura crea un problema de correccion: mientras la linea vieja
// espera en el buffer, la memoria principal todavia tiene el dato viejo. Si en
// ese intervalo alguien lee esa misma linea, la memoria le entregaria un valor
// obsoleto. Es un Read After Write, y el enunciado obliga a elegir entre dos
// mecanismos:
//
//   Stall                   esperar a que la entrada en conflicto se drene
//   Store-to-load forwarding  entregar el dato desde el propio buffer
//
// Este modulo implementa el stall, y la decision esta razonada en
// docs/memoria.md. En resumen: el forwarding tendria que combinar la linea del
// buffer con la que viene de memoria palabra por palabra, usando la mascara,
// porque una entrada puede tener solo algunas palabras sucias. Eso es un
// multiplexor de 256 bits mas el camino de datos para alimentarlo, y el caso
// que acelera es raro. El stall es una comparacion y una espera.
//
// La salida que implementa el stall es 'conflicto': combinacional, encendida
// cuando la direccion consultada coincide con alguna entrada ocupada. El
// controlador la mira antes de aceptar una lectura y, mientras este encendida,
// drena en vez de leer. Como el FIFO avanza, el conflicto desaparece en a lo
// sumo EVICT_ENTRIES drenados, asi que no hay bloqueo indefinido.
//
// -----------------------------------------------------------------------------
// POR QUE CADA ENTRADA LLEVA UNA MASCARA DE PALABRAS
// -----------------------------------------------------------------------------
// Una entrada guarda una linea completa de 32 bytes mas ocho bits que dicen
// cuales de sus ocho palabras estan sucias. Con una linea desalojada de L2
// estaran las ocho; con una escritura suelta, una sola.
//
// La mascara existe para que el mismo modulo sirva a los dos usos sin cambios.
// En la Iteracion 4, L2 desaloja lineas enteras. En la Iteracion 2, que es la
// que corre hoy, no hay cache y una escritura ensucia una palabra: sin la
// mascara habria que leer la linea de memoria antes de escribirla, solo para
// rellenar las siete palabras que no cambiaron, y eso costaria un T_mem entero
// por cada store.
//
// -----------------------------------------------------------------------------
// FUSION DE ESCRITURAS A LA MISMA LINEA
// -----------------------------------------------------------------------------
// Si llega un deposito para una linea que ya esta en el buffer, se fusiona con
// la entrada existente (se combinan datos y mascaras) en vez de ocupar una
// entrada nueva. No es una optimizacion opcional: sin fusionar, dos entradas de
// la misma linea se drenarian en orden y la segunda pisaria a la primera, lo
// cual es correcto, pero un patron de escritura secuencial llenaria el buffer
// en ocho stores y lo volveria inutil justo en el caso que mas se usa.
// =============================================================================

`include "cerbero_defs.svh"

module eviction_buffer #(
    parameter int ENTRIES = `EVICT_ENTRIES
) (
    input  logic clk,     // dominio del procesador
    input  logic rst_n,

    // ---- Deposito: desde la cache (o, hoy, desde un store) ------------------
    input  logic                     push,
    input  logic [`MEM_LIDX_W-1:0]   push_linea,
    input  logic [`LINE_W-1:0]       push_datos,
    input  logic [`LINE_WORDS-1:0]   push_mascara,

    // ---- Drenado: hacia el controlador de memoria ---------------------------
    output logic                     head_valido,
    output logic [`MEM_LIDX_W-1:0]   head_linea,
    output logic [`LINE_W-1:0]       head_datos,
    output logic [`LINE_WORDS-1:0]   head_mascara,
    input  logic                     head_ack,   // la escritura se completo

    // ---- Consulta de conflicto RAW ------------------------------------------
    input  logic [`MEM_LIDX_W-1:0]   consulta_linea,
    output logic                     conflicto,

    // ---- Estado --------------------------------------------------------------
    output logic                     lleno,
    output logic                     vacio,
    output logic [`EVICT_IDX_W:0]    ocupadas
);

  // Un bit mas que el indice, para distinguir lleno de vacio: con punteros del
  // mismo ancho que el arreglo, head == tail significa las dos cosas.
  localparam int PTR_W = `EVICT_IDX_W + 1;

  logic [`MEM_LIDX_W-1:0] linea   [0:ENTRIES-1];
  logic [`LINE_W-1:0]     datos   [0:ENTRIES-1];
  logic [`LINE_WORDS-1:0] mascara [0:ENTRIES-1];

  logic [PTR_W-1:0] head, tail;

  assign ocupadas = tail - head;
  assign vacio    = (ocupadas == 0);
  assign lleno    = (ocupadas == ENTRIES);

  // Los punteros llevan un bit de mas que el arreglo; el indice real es el
  // resto. Se recortan aqui, en asignaciones continuas, y no dentro de los
  // procesos: una seleccion de bits constante dentro de un always_comb obliga
  // al simulador a meter el vector entero en la lista de sensibilidad y lo
  // reporta como aviso.
  logic [`EVICT_IDX_W-1:0] head_idx, tail_idx;
  assign head_idx = head[`EVICT_IDX_W-1:0];
  assign tail_idx = tail[`EVICT_IDX_W-1:0];

  assign head_valido  = !vacio;
  assign head_linea   = linea  [head_idx];
  assign head_datos   = datos  [head_idx];
  assign head_mascara = mascara[head_idx];

  // ---------------------------------------------------------------------------
  // Busqueda asociativa, para el conflicto RAW y para la fusion
  //
  // Recorre las ENTRIES posiciones y se queda con las ocupadas. Comparar contra
  // los punteros en vez de llevar un bit de valido por entrada evita tener dos
  // nociones de ocupacion que podrian discrepar.
  // ---------------------------------------------------------------------------

  logic                    fusiona;
  logic [`EVICT_IDX_W-1:0] fusion_idx;
  logic                    hay_conflicto;

  integer                  k;
  logic [`EVICT_IDX_W-1:0] idx;
  logic                    es_cabeza;

  always_comb begin
    fusiona       = 1'b0;
    fusion_idx    = '0;
    hay_conflicto = 1'b0;

    // Se recorren las entradas desde la cabeza. La k-esima esta ocupada si
    // k < ocupadas, que es la misma condicion que estar en [head, tail) sin
    // tener que restar punteros.
    for (k = 0; k < ENTRIES; k = k + 1) begin
      // La suma se trunca sola al ancho de idx, que es justo el modulo ENTRIES
      // que hace falta para recorrer el arreglo circular.
      idx = head_idx + k;
      if (k < ocupadas) begin
        if (linea[idx] == consulta_linea) hay_conflicto = 1'b1;

        // Una entrada que el controlador esta retirando en este mismo ciclo ya
        // no sirve para fusionar: lo que se escribiera en ella se perderia
        // cuando la cabeza avance. En ese caso el deposito tiene que ir a una
        // entrada nueva, y por eso la cabeza se excluye cuando hay head_ack.
        es_cabeza = (k == 0);
        if ((linea[idx] == push_linea) && !(es_cabeza && head_ack)) begin
          fusiona    = 1'b1;
          fusion_idx = idx;
        end
      end
    end
  end

  // El conflicto RAW sigue incluyendo a la cabeza aunque se este drenando: el
  // dato llega a la memoria recien en el flanco, asi que una lectura emitida en
  // este ciclo todavia veria el valor viejo.
  assign conflicto = hay_conflicto;

  // ---------------------------------------------------------------------------
  // Deposito y drenado
  //
  // Los dos pueden ocurrir en el mismo ciclo: el controlador confirma el
  // drenado de la cabeza mientras la cache deposita otra linea. Son punteros
  // distintos, asi que no compiten.
  // ---------------------------------------------------------------------------

  integer w;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      head <= '0;
      tail <= '0;
      for (w = 0; w < ENTRIES; w = w + 1) begin
        linea[w]   <= '0;
        datos[w]   <= '0;
        mascara[w] <= '0;
      end
    end else begin
      // ---- drenado de la cabeza -------------------------------------------
      if (head_ack && !vacio) head <= head + 1'b1;

      // ---- deposito --------------------------------------------------------
      if (push) begin
        if (fusiona) begin
          // Misma linea ya encolada: se combinan. Para cada palabra, la que
          // llega gana si viene marcada en la mascara nueva; si no, se conserva
          // la que ya estaba. Asi la entrada queda con la version mas reciente
          // de cada palabra, que es lo que la memoria tiene que terminar
          // teniendo.
          for (w = 0; w < `LINE_WORDS; w = w + 1)
            if (push_mascara[w])
              datos[fusion_idx][w*`XLEN +: `XLEN] <=
                  push_datos[w*`XLEN +: `XLEN];
          mascara[fusion_idx] <= mascara[fusion_idx] | push_mascara;
        end else if (!lleno) begin
          linea  [tail_idx] <= push_linea;
          datos  [tail_idx] <= push_datos;
          mascara[tail_idx] <= push_mascara;
          tail <= tail + 1'b1;
        end
        // Si esta lleno y no fusiona, el deposito se pierde. Quien deposita
        // tiene que mirar 'lleno' antes: el controlador no acepta un desalojo
        // con el buffer lleno, detiene al procesador hasta que haya lugar.
      end
    end
  end

endmodule
