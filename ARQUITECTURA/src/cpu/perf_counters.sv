`timescale 1ns/1ps

// =============================================================================
// perf_counters.sv - Contadores de rendimiento del procesador.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// Mide lo que el procesador hizo de verdad mientras corria un programa:
// cuantos ciclos tardo, cuantos bundles despacho, cuantas operaciones reales
// llevaban esos bundles y cuantas ranuras se fueron en NOP. Es la linea base
// del analisis de rendimiento: cuando la jerarquia de cache entre en las
// iteraciones siguientes, el efecto se mide contra estos numeros.
//
// Esta unidad NO afecta la ejecucion. No tiene ninguna salida hacia el
// datapath: solo observa senales que ya existian y publica cuentas. Quitarla
// del procesador cambiaria el area, no el resultado de ningun programa.
//
// -----------------------------------------------------------------------------
// POR QUE SE CUENTA EN DECODIFICACION Y NO EN ESCRITURA
// -----------------------------------------------------------------------------
// Un contador de bundles puede mirarlos entrar (en ID, cuando el bundle existe
// completo) o salir (en WB, cuando ya escribio). En CERBERO-1 las dos cuentas
// dan el mismo numero, porque ningun bundle se descarta: no hay vaciado de
// pipeline (el delay slot lo evita, fetch.sv) ni excepciones que anulen un
// bundle entero (una falla anula su propio slot y el bundle sigue,
// microarchitecture.md 8.1).
//
// Se eligio ID porque es la unica etapa donde estan los 128 bits del bundle
// juntos. Los slots S0..S3 cruzan la frontera ID/EX, pero S4 no: la BRU
// resuelve en ID y a EX solo le llega lo que decidio. Contar en WB obligaria a
// arrastrar los cinco opcodes tres etapas mas, solo para medir.
//
// -----------------------------------------------------------------------------
// EL GANCHO PARA LOS STALLS DE LA CACHE
// -----------------------------------------------------------------------------
// Hoy el pipeline nunca se detiene y la entrada stall esta en cero. Cuando la
// cache L1-D entre (Iteracion 3), un miss va a congelar el bundle completo en
// sus etapas, y entonces el mismo bundle estaria en ID varios ciclos seguidos.
// Por eso un bundle se cuenta cuando AVANZA, no cuando esta:
//
//     contar un bundle  <=>  valid && !stall
//
// Con stall en cero eso es exactamente "cada bundle valido, una vez". Con
// stalls sigue siendo una vez, el ciclo en que el bundle deja ID. La
// alternativa, contar cada ciclo en que hay un bundle valido en ID, se
// convertiria en una cuenta de ciclos disfrazada de cuenta de bundles en
// cuanto apareciera el primer miss.
//
// El contador ciclos_stall ya existe por la misma razon: la Iteracion 3 le
// conecta cache_stall y no hay que volver a tocar este modulo ni top.sv.
//
// -----------------------------------------------------------------------------
// POR QUE LOS CONTADORES SATURAN EN VEZ DE DAR LA VUELTA
// -----------------------------------------------------------------------------
// Un contador de 32 bits que da la vuelta no avisa: a los 4 294 967 296 ciclos
// vuelve a cero y el informe sale con un numero chico, verosimil y falso. Aqui
// cada contador se queda en su tope y enciende desbordado, un bit pegajoso.
// Mientras ese bit este apagado, los numeros son exactos; si se enciende, el
// informe dice que no se puede confiar en ellos en vez de inventar una cifra.
//
// Con el tope de ciclos que usan los testbenches (2 000 000) ningun programa se
// acerca al limite, asi que en la practica el bit nunca se enciende. Esta para
// que el dia que se encienda alguien se entere.
//
// -----------------------------------------------------------------------------
// QUE CUENTA COMO "INSTRUCCION EJECUTADA"
// -----------------------------------------------------------------------------
// Una operacion no-NOP en cualquiera de los cinco slots de un bundle que se
// despacho. En los cinco slots el NOP es el opcode cero, asi que la prueba es
// la misma para todos aunque los campos midan 5 o 3 bits.
//
// Dos casos que podrian discutirse y se cuentan como ejecutados a proposito:
//
//   - Un salto condicional que NO se toma. La BRU lo evaluo: leyo las banderas
//     y decidio. Que la decision haya sido seguir de largo no lo vuelve un NOP.
//   - Una operacion que levanta una falla. Se decodifico y se ejecuto; lo que
//     se anula es su escritura (microarchitecture.md 8.1).
//
// La distincion importa porque instrucciones/bundles es la medida del
// paralelismo que el programa realmente usa, y las dos de arriba ocupan una
// ranura que ninguna otra operacion pudo usar.
// =============================================================================

`include "cerbero_defs.svh"

module perf_counters #(
    // Ancho de todos los contadores. 32 bits alcanzan para 4,29e9 eventos; el
    // bit de desbordamiento avisa si alguno llegara al tope.
    parameter int CNT_W = 32
) (
    input  logic clk,
    input  logic rst_n,

    // ---- Lo que se observa, todo en decodificacion --------------------------
    input  logic                  id_valid,   // hay un bundle real en ID
    input  logic [`BUNDLE_W-1:0]  id_bundle,  // los 128 bits de ese bundle
    input  logic                  id_taken,   // la BRU decidio saltar

    // ---- Estado del procesador ----------------------------------------------
    input  logic halted,  // despues de HALT ya no se cuentan ciclos
    input  logic stall,   // Iteracion 3: el pipeline esta congelado

    // ---- Las cuentas ---------------------------------------------------------
    output logic [CNT_W-1:0] ciclos,          // ciclos de ejecucion
    output logic [CNT_W-1:0] bundles,         // bundles despachados
    output logic [CNT_W-1:0] instrucciones,   // operaciones no-NOP
    output logic [`NSLOTS-1:0][CNT_W-1:0] ops_por_slot,  // ocupacion de cada slot

    // Accesos a memoria, separados por sentido. El enunciado los pide asi en su
    // tabla 2 (hits y misses desglosados por read y write), y hasta que exista
    // la cache son tambien la cuenta de cuantas veces el programa tendria que
    // ir a memoria principal: la base del calculo de la linea sin cache.
    output logic [CNT_W-1:0] accesos_load,
    output logic [CNT_W-1:0] accesos_store,
    output logic [CNT_W-1:0] bundles_vacios,  // bundles con sus cinco slots en NOP
    output logic [CNT_W-1:0] saltos_tomados,  // saltos que se tomaron
    output logic [CNT_W-1:0] delay_vacios,    // delay slots que no traian trabajo
    output logic [CNT_W-1:0] ciclos_stall,    // ciclos perdidos por stalls

    output logic desbordado  // pegajoso: algun contador llego al tope
);

  // ===========================================================================
  // Que trae cada slot del bundle que esta en ID
  //
  // Los rangos salen de cerbero_defs.svh, igual que en dispatch.sv. Este modulo
  // rebana el bundle por su cuenta y no toma las salidas de dispatch porque
  // necesita tambien S4, que no cruza la frontera ID/EX.
  // ===========================================================================

  logic [31:0] s0, s1, s2;
  logic [15:0] s3, s4;

  assign s0 = id_bundle[`SLOT_S0];
  assign s1 = id_bundle[`SLOT_S1];
  assign s2 = id_bundle[`SLOT_S2];
  assign s3 = id_bundle[`SLOT_S3];
  assign s4 = id_bundle[`SLOT_S4];

  // Una ranura ocupada es una con opcode distinto de NOP. En los cinco slots el
  // NOP es el opcode cero, pero cada uno se compara contra su propia constante
  // para que la prueba siga siendo correcta si alguna se renumera.
  logic [`NSLOTS-1:0] ocupado;

  assign ocupado[0] = (s0[`F_OPC]  != `ALU_NOP);
  assign ocupado[1] = (s1[`F_OPC]  != `ALU_NOP);
  assign ocupado[2] = (s2[`F_OPC]  != `LSU_NOP);
  assign ocupado[3] = (s3[`S3_OPC] != `CRP_NOP);
  assign ocupado[4] = (s4[`S4_OPC] != `BRU_NOP);

  // El opcode de S2 esta estructurado por campos (cerbero_defs.svh): el bit
  // LSU_BIT_ST distingue un store de un load. Mirar ese bit, en vez de
  // enumerar los once opcodes de la LSU, es lo que hace que agregar una
  // variante de acceso manana no obligue a tocar este modulo.
  // El opcode se extrae a una senal propia porque Icarus no acepta encadenar
  // un rango con un indice: s2[`F_OPC][`LSU_BIT_ST] no elabora.
  logic [4:0] s2_opc;
  assign s2_opc = s2[`F_OPC];

  logic es_load, es_store;
  assign es_store = ocupado[2] &&  s2_opc[`LSU_BIT_ST];
  assign es_load  = ocupado[2] && !s2_opc[`LSU_BIT_ST];

  // Cuantas ranuras ocupadas trae el bundle: de 0 a 5, tres bits
  logic [2:0] ranuras_usadas;

  always_comb begin
    integer k;
    ranuras_usadas = 3'd0;
    for (k = 0; k < `NSLOTS; k = k + 1)
      if (ocupado[k]) ranuras_usadas = ranuras_usadas + 3'd1;
  end

  // ===========================================================================
  // Cuando se cuenta
  //
  // avanza  el bundle de ID pasa a EX en este ciclo. Es el unico instante en
  //         que un bundle se cuenta, y ocurre una sola vez por bundle tanto
  //         ahora como cuando existan los stalls de la cache.
  // corre   el procesador todavia esta ejecutando: cuenta ciclos.
  // ===========================================================================

  logic avanza, corre;

  assign avanza = rst_n && id_valid && !stall;
  assign corre  = rst_n && !halted;

  // El delay slot: el bundle que viene inmediatamente despues de un salto
  // tomado. Se marca cuando el salto avanza y se mira en el bundle siguiente.
  logic es_delay_slot;

  always_ff @(posedge clk) begin
    if (!rst_n)       es_delay_slot <= 1'b0;
    else if (!stall)  es_delay_slot <= id_valid && id_taken;
  end

  // ===========================================================================
  // Los contadores
  //
  // Van en un arreglo y no en senales sueltas para que la saturacion y el bit
  // de desbordamiento se escriban una sola vez, en un lazo, en lugar de doce
  // veces iguales. Las salidas con nombre se asignan al final.
  // ===========================================================================

  localparam int NCONT = 14;

  localparam int C_CICLOS   = 0;
  localparam int C_BUNDLES  = 1;
  localparam int C_INSTR    = 2;
  localparam int C_SLOT0    = 3;   // C_SLOT0 + k es el slot k: 3, 4, 5, 6, 7
  localparam int C_VACIOS   = 8;
  localparam int C_SALTOS   = 9;
  localparam int C_DELAY    = 10;
  localparam int C_STALL    = 11;
  localparam int C_LOAD     = 12;
  localparam int C_STORE    = 13;

  localparam logic [CNT_W-1:0] TOPE = {CNT_W{1'b1}};

  logic [NCONT-1:0][CNT_W-1:0] cont;

  // Cuanto suma cada contador en este ciclo. Solo el de instrucciones puede
  // sumar mas de uno: hasta cinco, una por ranura ocupada.
  logic [NCONT-1:0][2:0] inc;

  always_comb begin
    integer k;
    for (k = 0; k < NCONT; k = k + 1) inc[k] = 3'd0;

    if (corre) begin
      inc[C_CICLOS] = 3'd1;
      if (stall) inc[C_STALL] = 3'd1;
    end

    if (avanza) begin
      inc[C_BUNDLES] = 3'd1;
      inc[C_INSTR]   = ranuras_usadas;

      for (k = 0; k < `NSLOTS; k = k + 1)
        if (ocupado[k]) inc[C_SLOT0 + k] = 3'd1;

      if (ranuras_usadas == 3'd0) inc[C_VACIOS] = 3'd1;
      if (id_taken)               inc[C_SALTOS] = 3'd1;
      if (es_load)                inc[C_LOAD]   = 3'd1;
      if (es_store)               inc[C_STORE]  = 3'd1;

      // Un delay slot vacio es el costo real de un salto en este procesador:
      // un bundle que se ejecuto por obligacion y no hizo nada.
      if (es_delay_slot && ranuras_usadas == 3'd0) inc[C_DELAY] = 3'd1;
    end
  end

  // Suma saturada. Un contador que llegaria al tope se queda ahi y enciende el
  // bit de desbordamiento, que ya no se apaga hasta el reset.
  always_ff @(posedge clk) begin
    integer k;
    if (!rst_n) begin
      for (k = 0; k < NCONT; k = k + 1) cont[k] <= '0;
      desbordado <= 1'b0;
    end else begin
      for (k = 0; k < NCONT; k = k + 1) begin
        if (inc[k] != 3'd0) begin
          if (cont[k] > TOPE - {{(CNT_W-3){1'b0}}, inc[k]}) begin
            cont[k]    <= TOPE;
            desbordado <= 1'b1;
          end else begin
            cont[k] <= cont[k] + {{(CNT_W-3){1'b0}}, inc[k]};
          end
        end
      end
    end
  end

  // ===========================================================================
  // Salidas
  // ===========================================================================

  assign ciclos         = cont[C_CICLOS];
  assign bundles        = cont[C_BUNDLES];
  assign instrucciones  = cont[C_INSTR];
  assign bundles_vacios = cont[C_VACIOS];
  assign saltos_tomados = cont[C_SALTOS];
  assign delay_vacios   = cont[C_DELAY];
  assign ciclos_stall   = cont[C_STALL];
  assign accesos_load   = cont[C_LOAD];
  assign accesos_store  = cont[C_STORE];

  genvar g;
  generate
    for (g = 0; g < `NSLOTS; g = g + 1) begin : g_slots
      assign ops_por_slot[g] = cont[C_SLOT0 + g];
    end
  endgenerate

endmodule
