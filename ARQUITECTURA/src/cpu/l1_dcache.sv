`timescale 1ns/1ps

// =============================================================================
// l1_dcache.sv - Cache de datos de primer nivel.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// 4 KB, 2 vias, linea de 32 bytes, 64 conjuntos. Write-through,
// no-write-allocate, reemplazo LRU. Se interpone entre la LSU y el resto de la
// jerarquia, en el mismo lugar donde el Proyecto I tenia la dmem ideal.
//
// Las tres politicas estan justificadas en docs/cache.md. Lo que sigue es como
// se implementan y por que el modulo tiene la forma que tiene.
//
// -----------------------------------------------------------------------------
// LA TEMPORIZACION ES LA MISMA QUE TENIA LA dmem
// -----------------------------------------------------------------------------
// La LSU calcula la direccion en EX y el dato se usa en MEM. La dmem del
// Proyecto I encajaba ahi porque su lectura estaba registrada: direccion en EX,
// dato en MEM, un ciclo.
//
// Esta cache conserva exactamente esa interfaz. Un acierto cuesta un ciclo y el
// dato aparece en MEM igual que antes; lo unico que se agrega es la salida
// 'stall', que se enciende cuando el acceso NO se puede resolver en este ciclo.
// Por eso el pipeline no necesitó una etapa nueva: el enunciado la permite
// (seccion 3.1.2) y no hizo falta.
//
// -----------------------------------------------------------------------------
// TODO EFECTO OCURRE EN EL CICLO EN QUE stall ESTA APAGADO
// -----------------------------------------------------------------------------
// Esta es la regla que hace correcto el modulo entero, y conviene leerla antes
// que el codigo.
//
// Mientras el pipeline esta detenido, el bundle de EX no se mueve: la LSU
// vuelve a presentar la MISMA peticion ciclo tras ciclo. Si los efectos
// laterales se dispararan con la peticion, un store se empujaria al write
// buffer 53 veces y la memoria terminaria con 53 escrituras donde el programa
// pedia una.
//
// Entonces: la peticion se MIRA todos los ciclos, pero solo se EJECUTA en el
// ciclo en que stall vale cero, que es el ciclo en que el bundle avanza. Eso
// vale para empujar al write buffer, para escribir el arreglo de datos y para
// actualizar el LRU.
//
// -----------------------------------------------------------------------------
// POR QUE UN STORE CASI NUNCA DETIENE EL PIPELINE
// -----------------------------------------------------------------------------
// Con write-through y no-write-allocate, un store no necesita la linea en la
// cache: el dato sale hacia abajo de todos modos y L1 nunca es la unica copia
// de nada. Si acierta, ademas actualiza la copia local; si falla, no se trae
// nada.
//
// La consecuencia es que un store se resuelve en un ciclo pase lo que pase, y
// la unica razon por la que podria esperar es que el write buffer este lleno.
// Un write miss, que con write-back costaria traer la linea entera, aqui no
// cuesta nada.
//
// De ahi que la condicion de stall tenga tres causas y no mas:
//
//     read miss            hay que traer la linea
//     write buffer lleno   no hay donde dejar el store
//     conflicto RAW        la linea que se quiere leer tiene escrituras
//                          pendientes en el write buffer
//
// -----------------------------------------------------------------------------
// EL CONFLICTO RAW, Y POR QUE SE MIRA ANTES DE PEDIR LA LINEA
// -----------------------------------------------------------------------------
// Un store que fallo no dejo rastro en la cache: su dato vive solo en el write
// buffer hasta que se drene. Si justo despues se lee esa misma linea, la cache
// falla, pide la linea al nivel de abajo, y el nivel de abajo todavia tiene el
// valor viejo.
//
// El grupo eligio resolverlo con stall (enunciado 3.4): mientras la linea este
// encolada, la lectura espera. El buffer drena solo, asi que la espera termina.
// Lo que importa es mirar el conflicto ANTES de emitir la peticion: una vez
// emitida, la lectura ya va en camino y el dato que vuelva sera el viejo.
//
// -----------------------------------------------------------------------------
// LRU EN DOS VIAS ES UN BIT
// -----------------------------------------------------------------------------
// Con dos vias basta recordar cual se uso de ultimo; la victima es la otra. Son
// 64 bits para toda la cache y es LRU exacto, no una aproximacion. El
// pseudo-LRU existe porque a partir de cuatro vias el exacto se encarece, y esa
// discusion aparece con la L2 de la Iteracion 4.
//
// -----------------------------------------------------------------------------
// LO QUE ESTE MODULO NO HACE
// -----------------------------------------------------------------------------
// No tiene bit de sucio ni camino de desalojo. Con write-through las lineas de
// L1 estan siempre limpias, asi que desalojar una es descartarla. Ese es el
// ahorro estructural de la politica, y es tambien lo que va a dejar barata la
// invalidacion hacia atras cuando entre la politica de inclusion en la
// Iteracion 4.
// =============================================================================

`include "cerbero_defs.svh"

module l1_dcache (
    input  logic clk,
    input  logic rst_n,

    // ---- Lado del procesador (la LSU, en EX) --------------------------------
    input  logic                     req,       // hay un acceso a memoria
    input  logic [`XLEN-1:0]         addr,      // direccion de byte
    input  logic                     we,        // 1 = store, 0 = load
    input  logic [3:0]               be,        // bytes que toca el store
    input  logic [`XLEN-1:0]         wdata,

    output logic [`XLEN-1:0]         rdata,     // registrada: valida en MEM
    output logic                     stall,     // el acceso no termina hoy

    // ---- Write buffer hacia el nivel siguiente ------------------------------
    output logic                     wb_push,
    output logic [`MEM_LIDX_W-1:0]   wb_linea,
    output logic [`LINE_W-1:0]       wb_datos,
    output logic [`LINE_MASK_W-1:0]  wb_mascara,
    input  logic                     wb_lleno,
    output logic [`MEM_LIDX_W-1:0]   wb_consulta,   // la linea que se quiere leer
    input  logic                     wb_conflicto,  // ... tiene escrituras pendientes

    // ---- Lado de la memoria (relleno de linea) ------------------------------
    output logic                     mem_req,
    output logic [`MEM_LIDX_W-1:0]   mem_linea,
    input  logic                     mem_listo,
    input  logic [`LINE_W-1:0]       mem_datos,

    // ---- Contadores, para las metricas del enunciado ------------------------
    output logic                     ev_load_hit,
    output logic                     ev_load_miss,
    output logic                     ev_store_hit,
    output logic                     ev_store_miss,
    output logic                     ev_stall_miss,   // ciclo perdido por miss
    output logic                     ev_stall_wb,     // ... por buffer lleno
    output logic                     ev_stall_raw     // ... por conflicto RAW
);

  // ===========================================================================
  // El arreglo
  // ===========================================================================

  logic [`L1D_TAG_W-1:0] etiqueta [0:`L1D_WAYS-1][0:`L1D_SETS-1];
  logic                  valido   [0:`L1D_WAYS-1][0:`L1D_SETS-1];
  logic [`LINE_W-1:0]    datos    [0:`L1D_WAYS-1][0:`L1D_SETS-1];

  // Un bit por conjunto: cual via se uso de ultimo. La victima es la contraria.
  logic                  mru      [0:`L1D_SETS-1];

  // ===========================================================================
  // Descomposicion de la direccion
  // ===========================================================================

  logic [`L1D_TAG_W-1:0]  tag;
  logic [`L1D_SIDX_W-1:0] conjunto;
  logic [2:0]             palabra;     // cual de las 8 palabras de la linea
  logic [1:0]             byte_en_pal;

  assign tag         = addr[`L1D_TAG];
  assign conjunto    = addr[`L1D_SET];
  assign palabra     = addr[`LINE_WIDX];
  assign byte_en_pal = addr[`LINE_BOFF];

  // La linea en el espacio de memoria principal, que es como la nombran el
  // write buffer y el controlador de memoria.
  logic [`MEM_LIDX_W-1:0] linea_mem;
  assign linea_mem = addr[`LINE_OFF_W + `MEM_LIDX_W - 1 : `LINE_OFF_W];

  // ===========================================================================
  // Busqueda
  // ===========================================================================

  logic acierto_v0, acierto_v1, acierto;
  logic via_acertada;

  assign acierto_v0 = valido[0][conjunto] && (etiqueta[0][conjunto] == tag);
  assign acierto_v1 = valido[1][conjunto] && (etiqueta[1][conjunto] == tag);
  assign acierto    = acierto_v0 || acierto_v1;

  assign via_acertada = acierto_v1;   // si acierta la 1; si no, la 0

  // La via que se va a reemplazar en un relleno: la que NO es la mas usada.
  logic via_victima;
  assign via_victima = ~mru[conjunto];

  // ===========================================================================
  // Clasificacion del acceso
  // ===========================================================================

  logic es_load, es_store;

  assign es_load  = req && !we;
  assign es_store = req &&  we;

  // ===========================================================================
  // Estado del relleno
  // ===========================================================================

  localparam logic ESPERA = 1'b0;   // atendiendo accesos normales
  localparam logic LLENA  = 1'b1;   // esperando la linea del nivel de abajo

  logic estado;

  // La linea que se esta trayendo. Se registra al emitir la peticion para que
  // el relleno no dependa de que la direccion siga presente: si el pipeline
  // hiciera algo inesperado durante la espera, la linea en vuelo es esta.
  logic [`MEM_LIDX_W-1:0]   linea_en_vuelo;
  logic [`L1D_TAG_W-1:0]    tag_en_vuelo;
  logic [`L1D_SIDX_W-1:0]   conjunto_en_vuelo;
  logic                     via_en_vuelo;

  // ===========================================================================
  // Por que se detiene, si se detiene
  //
  // Las tres causas se calculan por separado, y no como un unico booleano, para
  // que cada una tenga su contador: el enunciado pide los ciclos perdidos
  // desglosados, y con un solo booleano habria que adivinar a que se debieron.
  // ===========================================================================

  logic falla_lectura;      // una lectura que no esta en la cache
  logic espera_raw;         // ... y ademas la linea tiene escrituras pendientes
  logic espera_buffer;      // un store sin lugar donde dejarlo

  assign falla_lectura = es_load && !acierto;
  assign espera_raw    = falla_lectura && wb_conflicto;
  assign espera_buffer = es_store && wb_lleno;

  assign wb_consulta = linea_mem;

  always_comb begin
    case (estado)
      // Atendiendo: se detiene si la lectura falla o si el store no cabe
      ESPERA: stall = falla_lectura || espera_buffer;

      // Rellenando: se detiene hasta que la linea llegue. El ciclo en que llega
      // ya no es stall, porque el dato se entrega en ese mismo flanco.
      LLENA:  stall = !mem_listo;

      default: stall = 1'b0;
    endcase
  end

  // La peticion al nivel de abajo se emite cuando hay una falla de lectura sin
  // conflicto RAW. Con conflicto se espera: pedir la linea ahora traeria el
  // valor anterior a las escrituras que siguen en el buffer.
  //
  // Durante el relleno la peticion se sostiene, pero se BAJA en el ciclo en que
  // llega mem_listo. Ese es el contrato que fijó mem_controller.sv en la
  // Iteracion 2: listo y el regreso del bus a LIBRE ocurren en el mismo flanco,
  // asi que durante el ciclo de listo el controlador ya esta libre y vuelve a
  // mirar la peticion. Sostenerla ahi arrancaria una segunda lectura de la
  // misma linea, que no da un dato incorrecto pero ocupa el bus 53 ciclos y
  // retrasa al siguiente fallo de verdad.
  assign mem_req   = (estado == ESPERA) ? (falla_lectura && !wb_conflicto)
                                        : !mem_listo;
  assign mem_linea = (estado == ESPERA) ? linea_mem : linea_en_vuelo;

  // ===========================================================================
  // El camino de escritura hacia el write buffer
  //
  // Un store se empuja como una linea con solo sus bytes marcados. El buffer
  // fusiona los depositos consecutivos a la misma linea, asi que un recorrido
  // secuencial de escritura no la llena entrada por entrada.
  // ===========================================================================

  logic [`LINE_W-1:0]      store_datos;
  logic [`LINE_MASK_W-1:0] store_mascara;

  integer p;

  always_comb begin
    store_datos   = '0;
    store_mascara = '0;
    // El dato va en la palabra que le toca dentro de la linea, y la mascara de
    // bytes de la LSU se corre a esa misma posicion.
    for (p = 0; p < `LINE_WORDS; p = p + 1) begin
      if (p == {29'd0, palabra}) begin
        store_datos[p*`XLEN +: `XLEN]  = wdata;
        store_mascara[p*4 +: 4]        = be;
      end
    end
  end

  // Se empuja SOLO en el ciclo en que el acceso se completa (ver la nota de
  // arriba): si no, el mismo store entraria una vez por cada ciclo de stall.
  assign wb_push    = es_store && !stall;
  assign wb_linea   = linea_mem;
  assign wb_datos   = store_datos;
  assign wb_mascara = store_mascara;

  // ===========================================================================
  // Lectura: de donde sale el dato
  //
  // En un acierto, de la via que acerto. En el ciclo en que termina un relleno,
  // de la linea que viene llegando: el arreglo se escribe en ese mismo flanco,
  // asi que leerlo daria el contenido viejo. Es el arranque temprano clasico, y
  // es lo que hace que un relleno no cueste un ciclo extra.
  // ===========================================================================

  logic [`LINE_W-1:0] linea_leida;
  logic [`XLEN-1:0]   palabra_leida;

  assign linea_leida = (estado == LLENA) ? mem_datos
                                         : datos[via_acertada][conjunto];

  assign palabra_leida = linea_leida[{29'd0, palabra} * `XLEN +: `XLEN];

  // ===========================================================================
  // Contadores
  //
  // Un acceso se cuenta una sola vez, en el ciclo en que se completa, por la
  // misma razon que el store se empuja una sola vez. Los ciclos de stall, en
  // cambio, se cuentan TODOS: ahi lo que se mide es tiempo perdido.
  // ===========================================================================

  logic completa;
  assign completa = req && !stall;

  // En un relleno, el acceso que lo provoco era una lectura y se contabiliza
  // como fallo cuando se emite la peticion, no cuando llega la linea.
  assign ev_load_hit   = (estado == ESPERA) && es_load  && acierto && !stall;
  assign ev_load_miss  = (estado == ESPERA) && falla_lectura && !wb_conflicto;
  assign ev_store_hit  = (estado == ESPERA) && es_store && acierto && completa;
  assign ev_store_miss = (estado == ESPERA) && es_store && !acierto && completa;

  assign ev_stall_raw  = (estado == ESPERA) && espera_raw;
  assign ev_stall_wb   = (estado == ESPERA) && espera_buffer;
  assign ev_stall_miss = ((estado == ESPERA) && falla_lectura && !wb_conflicto)
                      || ((estado == LLENA)  && !mem_listo);

  // ===========================================================================
  // Secuencial
  // ===========================================================================

  integer v, s;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      estado <= ESPERA;
      rdata  <= '0;
      for (v = 0; v < `L1D_WAYS; v = v + 1)
        for (s = 0; s < `L1D_SETS; s = s + 1) begin
          valido  [v][s] <= 1'b0;
          etiqueta[v][s] <= '0;
          datos   [v][s] <= '0;
        end
      for (s = 0; s < `L1D_SETS; s = s + 1) mru[s] <= 1'b0;
      linea_en_vuelo    <= '0;
      tag_en_vuelo      <= '0;
      conjunto_en_vuelo <= '0;
      via_en_vuelo      <= 1'b0;
    end else begin
      case (estado)

        ESPERA: begin
          if (falla_lectura && !wb_conflicto) begin
            // Arranca el relleno. Se guarda a donde va la linea para no
            // depender de que la direccion siga presente durante la espera.
            estado            <= LLENA;
            linea_en_vuelo    <= linea_mem;
            tag_en_vuelo      <= tag;
            conjunto_en_vuelo <= conjunto;
            via_en_vuelo      <= via_victima;
          end

          if (!stall) begin
            // El acceso se completa en este ciclo: aqui, y solo aqui, ocurren
            // los efectos.
            if (es_load && acierto) begin
              rdata           <= palabra_leida;
              mru[conjunto]   <= via_acertada;
            end

            // Un store que acierta actualiza tambien la copia local, para que
            // una lectura posterior no traiga de abajo un valor viejo. Es lo
            // que hace coherente el write-through.
            if (es_store && acierto) begin
              for (p = 0; p < 4; p = p + 1)
                if (be[p])
                  datos[via_acertada][conjunto]
                       [({29'd0, palabra} * `XLEN) + p*8 +: 8] <= wdata[p*8 +: 8];
              mru[conjunto] <= via_acertada;
            end
            // Un store que falla no toca la cache: no-write-allocate.
          end
        end

        LLENA: begin
          if (mem_listo) begin
            // La linea entra en la via victima y el dato pedido sale por el
            // camino de arranque temprano, en este mismo flanco.
            datos   [via_en_vuelo][conjunto_en_vuelo] <= mem_datos;
            etiqueta[via_en_vuelo][conjunto_en_vuelo] <= tag_en_vuelo;
            valido  [via_en_vuelo][conjunto_en_vuelo] <= 1'b1;
            mru[conjunto_en_vuelo] <= via_en_vuelo;

            rdata  <= palabra_leida;
            estado <= ESPERA;
          end
        end

        default: estado <= ESPERA;
      endcase
    end
  end

endmodule
