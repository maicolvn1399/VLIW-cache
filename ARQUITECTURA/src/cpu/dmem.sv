`timescale 1ns/1ps

// =============================================================================
// dmem.sv - Memoria de datos.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// 64 KB direccionados por byte, organizados internamente en palabras de 32
// bits con escritura por carril, segun el mapa de memoria de isa.md 1.4.
//
// -----------------------------------------------------------------------------
// CONVENCION DE FLANCOS: LECTURA EN EL POSEDGE, ESCRITURA EN EL NEGEDGE
// -----------------------------------------------------------------------------
// Dentro de un mismo ciclo la lectura ocurre ANTES que la escritura, asi que
// una lectura NO ve la escritura de su propio ciclo. Es la convencion contraria
// a la del banco de registros, y las dos conviven a proposito.
//
// Lo que compra, en concreto:
//
//   - Un SW escribe a mitad de su ciclo y un LW posterior lee en el flanco de
//     subida de un ciclo mas tarde, que llega despues. El dato ya esta, asi que
//     no hay riesgo de almacenamiento a carga y el contrato con el compilador
//     no necesita una regla extra para la secuencia SW seguido de LW.
//
//   - Lectura y escritura no coinciden NUNCA en el mismo instante. Con los dos
//     accesos en el mismo flanco el resultado seria correcto en simulacion,
//     porque las asignaciones no bloqueantes ya ordenan la lectura antes de la
//     escritura, pero en sintesis quedaria dependiendo del modo de
//     lectura-durante-escritura de la memoria que infiera la herramienta, que
//     no es algo que convenga dejar al azar.
//
// Por lo primero, la propiedad visible desde fuera es casi la misma con las dos
// convenciones; por lo segundo, no lo es dentro. De ahi que tb_dmem.sv la
// compruebe mirando el arreglo interno despues de cada flanco y no solo el
// resultado de las lecturas: de la otra forma, una version que escribiera en el
// flanco de subida pasaria todas las pruebas.
//
// -----------------------------------------------------------------------------
// EL REGISTRO DE SALIDA ES EL REGISTRO DE SEGMENTACION EX/MEM
// -----------------------------------------------------------------------------
// Igual que en la memoria de instrucciones, no hace falta un registro aparte
// para el dato cargado:
//
//   ciclo n+2   EX    la LSU calcula la direccion y la presenta
//   posedge     la memoria la toma y entrega el dato
//   ciclo n+3   MEM   el dato esta estable; la LSU extrae el carril y extiende
//   posedge     el banco de registros escribe el resultado
//
// Para que esto funcione, la LSU tiene que presentar direccion, dato, mascara
// y habilitador de forma COMBINACIONAL durante EX, no registrados en la
// frontera EX/MEM. Si la direccion llegara ya registrada, el dato saldria un
// ciclo mas tarde y la latencia expuesta de la carga pasaria de 3 a 4 bundles,
// rompiendo el contrato con el grupo de CE1108.
//
// -----------------------------------------------------------------------------
// LA MASCARA DE BYTES NO ES OPCIONAL
// -----------------------------------------------------------------------------
// La LSU REPLICA el dato en los cuatro carriles de la palabra y deja que
// byte_enable decida cual se escribe. Los carriles que la mascara no marca
// traen una copia del dato, no ceros.
//
// En consecuencia, esta memoria debe escribir UNICAMENTE los carriles
// marcados. Una implementacion que ignore la mascara va a parecer correcta con
// SW, donde vale 1111, y va a corromper los tres bytes vecinos en el primer SB.
// Es el error mas facil de cometer en este modulo y el mas dificil de ver
// despues, porque solo aparece con accesos de byte y de media palabra.
//
// -----------------------------------------------------------------------------
// ORDEN DE BYTES
// -----------------------------------------------------------------------------
// Little-endian, como fija isa.md 1.4: el byte de la direccion A vive en los
// bits [7:0] de su palabra, el de A+1 en [15:8], y asi. La organizacion interna
// por palabras lo da sin logica adicional, porque el carril 0 de la mascara
// corresponde al byte de direccion mas baja.
//
// -----------------------------------------------------------------------------
// FUERA DE RANGO
// -----------------------------------------------------------------------------
// Una lectura fuera de lo implementado entrega ceros y una escritura se
// descarta. Es defensa en profundidad y no la comprobacion principal: la LSU
// ya levanta RANGE y apaga el habilitador antes de llegar aqui. Esta aqui para
// que un error en el datapath no se convierta en una escritura a una posicion
// que no existe, que en simulacion es un indice fuera del arreglo.
//
// La memoria tampoco comprueba alineacion: eso es MISALIGN y lo resuelve la
// LSU, que es quien conoce el tamano del acceso. Aqui los dos bits bajos de la
// direccion simplemente no participan.
//
// -----------------------------------------------------------------------------
// SOBRE EL AVISO DE $readmemh
// -----------------------------------------------------------------------------
// Cuando el archivo trae menos palabras que la memoria, Icarus imprime
// "Not enough words in the file for the requested range". Es un aviso, no un
// error: las posiciones restantes quedan en los ceros del barrido inicial. La
// herramienta de carga puede rellenar el archivo con lineas de ceros hasta
// NUM_WORDS para que no aparezca; en los testbenches se deja a proposito,
// porque ahi se esta comprobando justo ese caso.
//
// El aviso contrario tambien existe: "Too many words in the file for the
// requested range" si el archivo trae MAS palabras que la memoria. Ese nunca es
// intencional, siempre significa que el relleno del ensamblador no coincide con
// el NUM_WORDS del testbench, y las palabras de sobra se descartan en silencio.
// El makefile declara el tamano de cada programa por separado justamente para
// que los dos numeros cuadren.
//
// -----------------------------------------------------------------------------
// VOLCADO PARA LOS TESTBENCHES
// -----------------------------------------------------------------------------
// El arreglo interno se llama storage y un testbench puede mirarlo por
// referencia jerarquica, por ejemplo dut.u_dmem.storage[0]. Es lo que necesita
// el caso 6 del enunciado, que pide volcar la memoria despues de cifrar para
// comprobar que ninguna subllave quedo visible.
// =============================================================================

`include "cerbero_defs.svh"

module dmem #(
    // Cantidad de palabras de 32 bits. 16384 x 4 bytes = 64 KB.
    parameter int    NUM_WORDS = 16384,
    // Archivo en formato $readmemh, 8 digitos hexadecimales por linea. Lo
    // produce la herramienta de carga de archivos.
    parameter string INIT_FILE = ""
) (
    input  logic              clk,

    // Direccion de BYTE, tal como la calcula la LSU
    input  logic [`XLEN-1:0]  addr,

    // Escritura
    input  logic              we,
    input  logic [3:0]        byte_enable,
    input  logic [`XLEN-1:0]  wdata,

    // Lectura registrada, valida durante todo el ciclo siguiente
    output logic [`XLEN-1:0]  rdata
);

  localparam int IDX_W = $clog2(NUM_WORDS);
  localparam int SHIFT = 2;   // cuatro bytes por palabra

  // El limite, con tipo y ancho explicitos. NUM_WORDS es un int con signo y el
  // indice es un vector sin signo: comparar los dos directamente funciona, pero
  // deja la mezcla de signos a criterio de la herramienta.
  localparam logic [`XLEN-1:0] LIMITE = NUM_WORDS;

  logic [`XLEN-1:0] storage [0:NUM_WORDS-1];

  // ---------------------------------------------------------------------------
  // Carga inicial
  //
  // El barrido a cero va primero y siempre, por el mismo motivo que en la
  // memoria de instrucciones: $readmemh solo escribe lo que el archivo trae.
  // ---------------------------------------------------------------------------

  integer k;
  initial begin
    for (k = 0; k < NUM_WORDS; k = k + 1) storage[k] = {`XLEN{1'b0}};
    if (INIT_FILE != "") $readmemh(INIT_FILE, storage);
  end

  // ---------------------------------------------------------------------------
  // Decodificacion de la direccion
  //
  // Los dos bits bajos no participan: el carril dentro de la palabra ya viene
  // resuelto en la mascara que arma la LSU.
  // ---------------------------------------------------------------------------

  /* verilator lint_off UNUSEDSIGNAL */
  logic [`XLEN-1:0] addr_in;
  /* verilator lint_on UNUSEDSIGNAL */
  assign addr_in = addr;

  logic [`XLEN-1:0] index_full;
  logic             in_range;
  logic [IDX_W-1:0] index;

  assign index_full = addr_in >> SHIFT;
  assign in_range   = (index_full < LIMITE);
  assign index      = index_full[IDX_W-1:0];

  // ---------------------------------------------------------------------------
  // Lectura, en el flanco de subida
  // ---------------------------------------------------------------------------

  always_ff @(posedge clk) begin
    rdata <= in_range ? storage[index] : {`XLEN{1'b0}};
  end

  // ---------------------------------------------------------------------------
  // Escritura, en el flanco de bajada
  //
  // Un habilitador por carril, escritos como cuatro condiciones separadas en
  // vez de un bucle: deja a la vista que son cuatro grupos de ocho biestables
  // con su propia senal de habilitacion, que es lo que se va a sintetizar.
  // ---------------------------------------------------------------------------

  logic escribe;
  assign escribe = we && in_range;

  always_ff @(negedge clk) begin
    if (escribe) begin
      if (byte_enable[0]) storage[index][7:0]   <= wdata[7:0];
      if (byte_enable[1]) storage[index][15:8]  <= wdata[15:8];
      if (byte_enable[2]) storage[index][23:16] <= wdata[23:16];
      if (byte_enable[3]) storage[index][31:24] <= wdata[31:24];
    end
  end

endmodule
