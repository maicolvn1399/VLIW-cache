`timescale 1ns/1ps

// =============================================================================
// mem_controller.sv - Controlador de memoria principal.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Aqui vive el TIEMPO de la memoria. El arreglo esta en main_memory.sv y las
// lineas sucias en eviction_buffer.sv; este modulo decide quien usa el bus y
// cuantos ciclos cuesta cada cosa.
//
// El enunciado pide expresamente que los delays se simulen con una maquina de
// estados, y eso es lo que hay: cinco estados y dos contadores.
//
// -----------------------------------------------------------------------------
// DE DONDE SALEN LOS 53 CICLOS
// -----------------------------------------------------------------------------
// El enunciado (seccion 3.2.5) descompone el costo de traer una linea en dos
// partes de naturaleza distinta:
//
//   latencia de primera palabra   25 ciclos de PROCESADOR. Es el costo de
//                                 abrir la fila y atravesar el bus. No depende
//                                 de la velocidad de la memoria.
//
//   resto del burst               7 palabras a una por ciclo de MEMORIA. Aqui
//                                 si manda la frecuencia: cada ciclo de
//                                 memoria son MEM_CLK_DIV ciclos de procesador.
//
//   T_mem = 25 + 7 * 4 = 53 ciclos de procesador
//
// La fase de burst se cuenta en ciclos de PROCESADOR (7 * 4 = 28) y no en
// flancos de memoria. Los dos criterios dan el mismo resultado, porque en una
// ventana de 28 ciclos caen exactamente 7 flancos de memoria sin importar en
// que fase empiece (tb_mem_clock_gen.sv lo comprueba para las cuatro fases).
// La diferencia esta en el determinismo: contando ciclos, T_mem vale 53
// siempre; contando flancos, valdria entre 50 y 53 segun donde cayera el
// primero, y una latencia que cambia sola seria imposible de contrastar contra
// el valor teorico.
//
// -----------------------------------------------------------------------------
// EL ARBITRAJE, Y POR QUE EL DRENADO NO ES SIEMPRE LO ULTIMO
// -----------------------------------------------------------------------------
// Hay dos clientes del bus: las lecturas de linea, que tienen al procesador
// esperando, y el drenado del eviction buffer, que no tiene a nadie esperando.
// La prioridad natural es la lectura, y esa es la regla general.
//
// Hay una excepcion, y es obligatoria: si la linea que se quiere leer todavia
// esta en el buffer sin drenar, la memoria tiene el valor VIEJO. Leer ahi
// devolveria datos obsoletos. Es el riesgo RAW de la seccion 3.4 del
// enunciado, y el grupo eligio resolverlo con stall: mientras haya conflicto,
// la lectura espera y el drenado toma el bus. Como el buffer avanza, el
// conflicto se despeja en a lo sumo EVICT_ENTRIES drenados.
//
// La inversion de prioridad es, entonces, lo que hace correcta la espera: si la
// lectura mantuviera la prioridad durante el conflicto, ninguno de los dos
// avanzaria y el sistema se trabaria.
//
// -----------------------------------------------------------------------------
// LOS CINCO ESTADOS
// -----------------------------------------------------------------------------
//   LIBRE       nadie usa el bus. Decide que transaccion empieza.
//   RD_LAT      25 ciclos de latencia. Al terminar, la palabra 0 ya se leyo.
//   RD_BURST    28 ciclos. Una palabra por flanco de memoria, palabras 1 a 7.
//   WR_LAT      lo mismo para una escritura: 25 ciclos antes de la primera.
//   WR_BURST    28 ciclos. Escribe solo las palabras marcadas en la mascara.
//
// Una escritura cuesta lo mismo que una lectura. Fisicamente es asi: la
// latencia de primera palabra es el costo de abrir la fila, y abrirla hay que
// hacerlo para leer y para escribir. La diferencia es que nadie la espera.
// =============================================================================

`include "cerbero_defs.svh"

module mem_controller (
    input  logic clk,
    input  logic rst_n,
    input  logic tick,              // flanco del reloj de memoria

    // ---- Cliente: hoy el testbench, desde la Iteracion 4 la cache L2 --------
    input  logic                     req,          // se sostiene hasta listo
    input  logic [`MEM_LIDX_W-1:0]   req_linea,
    output logic                     listo,        // un pulso: la linea salio
    output logic [`LINE_W-1:0]       linea_datos,
    output logic                     ocupado,      // el bus esta en uso

    // ---- Eviction buffer -----------------------------------------------------
    input  logic                     ev_valido,
    input  logic [`MEM_LIDX_W-1:0]   ev_linea,
    input  logic [`LINE_W-1:0]       ev_datos,
    input  logic [`LINE_WORDS-1:0]   ev_mascara,
    input  logic                     ev_conflicto, // RAW con req_linea
    output logic                     ev_ack,

    // ---- Memoria principal ----------------------------------------------------
    output logic [`XLEN-1:0]         mem_addr,     // direccion de palabra
    output logic                     mem_we,
    output logic [`XLEN-1:0]         mem_wdata,
    input  logic [`XLEN-1:0]         mem_rdata,

    // ---- Observacion, para contadores y testbenches --------------------------
    output logic                     inicia_lectura,  // pulso al empezar
    output logic                     inicia_drenado   // pulso al empezar
);

  // ---------------------------------------------------------------------------
  // Estados
  // ---------------------------------------------------------------------------

  localparam logic [2:0] LIBRE    = 3'd0;
  localparam logic [2:0] RD_LAT   = 3'd1;
  localparam logic [2:0] RD_BURST = 3'd2;
  localparam logic [2:0] WR_LAT   = 3'd3;
  localparam logic [2:0] WR_BURST = 3'd4;

  logic [2:0] estado;

  // Contador de ciclos de procesador que faltan en la fase actual. El valor mas
  // grande que guarda es MEM_FIRST_WORD o MEM_BURST_REST*MEM_CLK_DIV, los dos
  // por debajo de 64.
  logic [6:0] faltan;

  // Cual palabra de la linea se esta moviendo
  logic [3:0] idx;

  // La linea en curso y su direccion base
  logic [`MEM_LIDX_W-1:0] linea_actual;
  logic [`LINE_W-1:0]     buffer_linea;
  logic [`LINE_WORDS-1:0] mascara_actual;

  // ---------------------------------------------------------------------------
  // Direccion hacia la memoria
  //
  // La direccion de palabra es la linea por LINE_WORDS mas el indice dentro de
  // la linea. Se arma combinacionalmente desde los registros de estado, asi que
  // la memoria siempre ve la palabra que corresponde al ciclo actual.
  // ---------------------------------------------------------------------------

  assign mem_addr  = {{(`XLEN - `MEM_LIDX_W - 3){1'b0}}, linea_actual, idx[2:0]};
  assign mem_wdata = buffer_linea[idx[2:0]*`XLEN +: `XLEN];

  // Solo se escribe en las fases de escritura, y solo las palabras que la
  // mascara marca como sucias. Una palabra no marcada no se toca: la memoria ya
  // tiene el valor bueno y reescribirlo con lo que haya en el buffer seria
  // perder datos que nadie modifico.
  //
  // WR_LAT tambien escribe, y es a proposito. La palabra 0 de una lectura sale
  // gratis porque el arreglo la tiene lista en su salida durante toda la
  // latencia; una escritura no tiene ese regalo, necesita un flanco de memoria
  // propio. Si la palabra 0 esperara al burst, las ocho palabras necesitarian
  // ocho flancos y en la ventana solo caben siete: la ultima no se escribiria y
  // la linea quedaria con una palabra vieja, en silencio.
  //
  // Durante la latencia la direccion esta fija en la palabra 0, asi que la
  // memoria la escribe una vez por cada flanco que ocurra ahi. Son escrituras
  // identicas y sin efecto a partir de la primera; lo que importa es que al
  // terminar la latencia la palabra 0 ya esta puesta, igual que en la lectura.
  assign mem_we = ((estado == WR_LAT) || (estado == WR_BURST)) &&
                  mascara_actual[idx[2:0]];

  assign ocupado = (estado != LIBRE);

  // ---------------------------------------------------------------------------
  // Que transaccion empieza
  //
  // Un solo lugar decide, para que la prioridad sea legible de un vistazo y no
  // quede repartida entre ramas del case.
  // ---------------------------------------------------------------------------

  logic puede_leer, puede_drenar;

  // Una lectura puede empezar si hay pedido y la linea NO esta esperando en el
  // buffer. Con conflicto, la lectura cede el bus: ver la nota de arriba.
  //
  // CONTRATO CON EL CLIENTE: req tiene que bajar durante el ciclo en que el
  // cliente ve listo encendido.
  //
  // El motivo es que listo y el regreso a LIBRE ocurren en el mismo flanco, asi
  // que durante el ciclo de listo la maquina ya esta libre y vuelve a mirar
  // req. Como no hay forma de distinguir "el pedido viejo que todavia no se
  // soltó" de "un pedido nuevo a la misma linea", el que sabe cual es cual es
  // el cliente.
  //
  // Se probo la alternativa de bloquear aqui con un !listo. Funciona, pero le
  // cuesta un ciclo a toda lectura que siga inmediatamente a otra, y entonces
  // T_mem deja de ser 53 y pasa a depender de si la lectura anterior estaba
  // pegada o no. Un numero que cambia segun el contexto no se puede contrastar
  // contra el valor teorico, que es justamente lo que esta iteracion produce.
  assign puede_leer   = req && !ev_conflicto;

  // El drenado arranca cuando no hay lectura que atender, o cuando la hay pero
  // esta bloqueada por el conflicto, que es justamente el caso en que drenar es
  // lo unico que lo desbloquea.
  //
  // El !ev_ack es el mismo problema del lado del buffer: la cabeza avanza en el
  // flanco, asi que durante el ciclo del ack el buffer todavia muestra la
  // entrada que se acaba de escribir. Sin la guarda, se drenaria dos veces.
  assign puede_drenar = ev_valido && (!req || ev_conflicto) && !ev_ack;

  // ---------------------------------------------------------------------------
  // La maquina
  // ---------------------------------------------------------------------------

  integer w;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      estado         <= LIBRE;
      faltan         <= '0;
      idx            <= '0;
      linea_actual   <= '0;
      buffer_linea   <= '0;
      mascara_actual <= '0;
      listo          <= 1'b0;
      ev_ack         <= 1'b0;
      linea_datos    <= '0;
      inicia_lectura <= 1'b0;
      inicia_drenado <= 1'b0;
    end else begin
      // Los pulsos duran un ciclo salvo que la maquina los vuelva a encender
      listo          <= 1'b0;
      ev_ack         <= 1'b0;
      inicia_lectura <= 1'b0;
      inicia_drenado <= 1'b0;

      case (estado)

        // ---- nadie usa el bus --------------------------------------------
        LIBRE: begin
          // El contador arranca en MEM_FIRST_WORD-2 y no en -1 porque ESTE
          // ciclo, el del arbitraje, ya es el primero de la latencia. El
          // enunciado mide los 25 ciclos "desde que se emite la solicitud", y
          // la solicitud esta puesta en este ciclo. Contar desde -1 daria 54
          // ciclos de punta a punta en vez de 53, un error de uno que nadie
          // notaria mirando la forma de onda.
          if (puede_leer) begin
            estado         <= RD_LAT;
            linea_actual   <= req_linea;
            idx            <= '0;          // la palabra 0 durante toda la
            faltan         <= `MEM_FIRST_WORD - 2;  // latencia
            inicia_lectura <= 1'b1;
          end else if (puede_drenar) begin
            estado         <= WR_LAT;
            linea_actual   <= ev_linea;
            buffer_linea   <= ev_datos;
            mascara_actual <= ev_mascara;
            idx            <= '0;
            faltan         <= `MEM_FIRST_WORD - 2;
            inicia_drenado <= 1'b1;
          end
        end

        // ---- latencia de primera palabra, lectura --------------------------
        // Durante estos 25 ciclos la direccion apunta a la palabra 0, asi que
        // al salir de aqui el dato ya esta en mem_rdata y se guarda sin costo
        // adicional: esa es, literalmente, la primera palabra del burst.
        RD_LAT: begin
          if (faltan == 0) begin
            buffer_linea[0 +: `XLEN] <= mem_rdata;
            idx    <= 4'd1;
            faltan <= `MEM_BURST_REST * `MEM_CLK_DIV - 1;
            estado <= RD_BURST;
          end else begin
            faltan <= faltan - 1'b1;
          end
        end

        // ---- burst de lectura ----------------------------------------------
        // Una palabra por flanco de memoria. La ventana dura 28 ciclos de
        // procesador y contiene exactamente 7 flancos, uno por cada palabra que
        // falta. El contador de ciclos es el que decide cuando termina; el tick
        // decide cuando se mueve cada palabra.
        RD_BURST: begin
          if (tick && (idx < `LINE_WORDS)) begin
            buffer_linea[idx[2:0]*`XLEN +: `XLEN] <= mem_rdata;
            idx <= idx + 1'b1;
          end

          if (faltan == 0) begin
            estado <= LIBRE;
            listo  <= 1'b1;
            // La ultima palabra se guarda en este mismo flanco si el tick cae
            // justo aqui, asi que la salida se arma con el dato que entra ahora
            // en vez de con el registro, que todavia no cambio.
            for (w = 0; w < `LINE_WORDS; w = w + 1)
              linea_datos[w*`XLEN +: `XLEN] <=
                  (tick && (idx == w[3:0])) ? mem_rdata
                                            : buffer_linea[w*`XLEN +: `XLEN];
          end else begin
            faltan <= faltan - 1'b1;
          end
        end

        // ---- latencia de primera palabra, escritura ------------------------
        // La palabra 0 se escribe en el primer flanco de memoria del burst, no
        // aqui: a diferencia de la lectura, donde el dato ya estaba esperando
        // en la salida del arreglo, una escritura necesita su propio flanco.
        WR_LAT: begin
          if (faltan == 0) begin
            // La palabra 0 ya quedo escrita durante la latencia (ver la nota de
            // mem_we), asi que el burst empieza por la 1, igual que en una
            // lectura. Sin este salto, los 7 flancos del burst escribirian las
            // palabras 0 a 6 y la 7 nunca llegaria a memoria.
            idx    <= 4'd1;
            faltan <= `MEM_BURST_REST * `MEM_CLK_DIV - 1;
            estado <= WR_BURST;
          end else begin
            faltan <= faltan - 1'b1;
          end
        end

        // ---- burst de escritura ---------------------------------------------
        WR_BURST: begin
          if (tick && (idx < `LINE_WORDS))
            idx <= idx + 1'b1;

          if (faltan == 0) begin
            estado <= LIBRE;
            ev_ack <= 1'b1;   // recien ahora la linea esta en memoria
          end else begin
            faltan <= faltan - 1'b1;
          end
        end

        default: estado <= LIBRE;
      endcase
    end
  end

endmodule
