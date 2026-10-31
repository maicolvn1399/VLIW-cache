`timescale 1ns/1ps

// =============================================================================
// imem.sv - Memoria de instrucciones.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Palabras de 128 bits, una por bundle. 32 KB por omision, o sea 2048 bundles,
// segun el mapa de memoria de isa.md 1.4.
//
// Es de solo lectura durante la ejecucion: el contenido entra por $readmemh al
// arrancar la simulacion. La arquitectura es Harvard, asi que ninguna
// instruccion puede escribir aqui, y por eso el modulo no tiene puerto de
// escritura.
//
// -----------------------------------------------------------------------------
// CONVENCION DE FLANCOS: LECTURA EN EL POSEDGE
// -----------------------------------------------------------------------------
// La lectura es SINCRONA: la direccion se toma en el flanco de subida y el
// bundle sale registrado, estable durante todo el ciclo siguiente.
//
// Es la convencion acordada para las memorias, y NO es la del banco de
// registros, que escribe en el posedge y lee en el negedge. Las dos conviven a
// proposito y estan documentadas en los dos lados, porque dos convenciones
// opuestas en el mismo diseno son justo lo que alguien "corrige" sin darse
// cuenta.
//
// -----------------------------------------------------------------------------
// EL REGISTRO DE SALIDA ES EL REGISTRO DE SEGMENTACION IF/ID
// -----------------------------------------------------------------------------
// De ahi que no haga falta un registro aparte para el bundle:
//
//   ciclo n     IF   el contador de programa presenta la direccion
//   posedge     la memoria la toma y entrega el bundle
//   ciclo n+1   ID   el bundle esta estable todo el ciclo; dispatch lo rebana
//
// Para que esto funcione, el contador de programa tiene que presentar la
// direccion de forma COMBINACIONAL durante el ciclo n, no registrada en la
// frontera. Si la direccion llegara ya registrada en el posedge de n+1, el
// bundle recien saldria en n+2 y el pipeline entero correria un ciclo.
//
// -----------------------------------------------------------------------------
// DIRECCIONAMIENTO
// -----------------------------------------------------------------------------
// La direccion es de BYTE, la misma que lleva el contador de programa, y
// siempre es multiplo de 16 porque cada bundle ocupa 16 bytes. El indice de
// bundle son los bits altos; los cuatro bajos no se usan y la memoria los
// ignora en vez de comprobarlos: el contador de programa avanza de 16 en 16 y
// la unidad de saltos calcula destinos en bundles, asi que no hay forma de
// construir un valor desalineado.
//
// -----------------------------------------------------------------------------
// FUERA DE RANGO
// -----------------------------------------------------------------------------
// Una direccion mas alla de lo implementado entrega un bundle de 128 ceros,
// que es un bundle de operaciones nulas perfectamente valido: el opcode cero
// es NOP en los cinco slots. El procesador no se cuelga ni propaga valores
// indefinidos, simplemente no hace nada y sigue avanzando.
//
// Eso tambien vale para la memoria sin inicializar: el bloque initial la deja
// en ceros antes de leer el archivo, de modo que las posiciones que el
// programa no ocupe sean bundles vacios y no valores indefinidos.
//
// -----------------------------------------------------------------------------
// SOBRE EL AVISO DE $readmemh
// -----------------------------------------------------------------------------
// Cuando el archivo trae menos bundles que la memoria, Icarus imprime
// "Not enough words in the file for the requested range". Es un aviso, no un
// error: significa que el programa es mas corto que la memoria, que es el caso
// normal, y las posiciones restantes quedan en los ceros del barrido.
//
// Para que no aparezca en las corridas de verdad, la herramienta de carga puede
// rellenar el archivo con lineas de ceros hasta NUM_BUNDLES. En los testbenches
// el aviso se deja a proposito, porque ahi se esta comprobando justo ese caso.
//
// El aviso contrario tambien existe: "Too many words in the file for the
// requested range" si el archivo trae MAS bundles que la memoria. Ese nunca es
// intencional, siempre significa que el relleno del ensamblador no coincide con
// el NUM_BUNDLES del testbench, y los bundles de sobra se descartan en silencio.
// El makefile declara el tamano de cada programa por separado justamente para
// que los dos numeros cuadren.
//
// -----------------------------------------------------------------------------
// VOLCADO PARA LOS TESTBENCHES
// -----------------------------------------------------------------------------
// El arreglo interno se llama storage y un testbench puede mirarlo por
// referencia jerarquica, por ejemplo dut.u_imem.storage[0]. No se expone como
// puerto porque serian 2048 por 128 bits de cables que en sintesis no van a
// ninguna parte.
// =============================================================================

`include "cerbero_defs.svh"

module imem #(
    // Cantidad de bundles. 2048 x 16 bytes = 32 KB.
    parameter int    NUM_BUNDLES = 2048,
    // Archivo en formato $readmemh, 32 digitos hexadecimales por linea. Si
    // queda vacio, la memoria arranca llena de bundles nulos.
    parameter string INIT_FILE   = ""
) (
    input  logic                  clk,

    // Direccion de byte, la del contador de programa
    input  logic [`XLEN-1:0]      addr,

    // Bundle registrado, valido durante todo el ciclo siguiente
    output logic [`BUNDLE_W-1:0]  bundle
);

  // Bits que hacen falta para nombrar un bundle
  localparam int IDX_W = $clog2(NUM_BUNDLES);

  // Cada bundle ocupa 16 bytes, asi que el indice son los bits a partir del 4
  localparam int SHIFT = $clog2(`BUNDLE_W / 8);

  // El limite, con tipo y ancho explicitos. NUM_BUNDLES es un int con signo y
  // el indice es un vector sin signo: comparar los dos directamente funciona,
  // pero deja la mezcla de signos a criterio de la herramienta.
  localparam logic [`XLEN-1:0] LIMITE = NUM_BUNDLES;

  logic [`BUNDLE_W-1:0] storage [0:NUM_BUNDLES-1];

  // ---------------------------------------------------------------------------
  // Carga inicial
  //
  // El barrido a cero va primero y siempre: $readmemh solo escribe las
  // posiciones que el archivo trae, y sin el barrido las demas quedarian
  // indefinidas. Un unico bit en X dentro de un bundle contamina los cinco
  // slots y vuelve ilegible cualquier forma de onda.
  // ---------------------------------------------------------------------------

  integer k;
  initial begin
    for (k = 0; k < NUM_BUNDLES; k = k + 1) storage[k] = {`BUNDLE_W{1'b0}};
    if (INIT_FILE != "") $readmemh(INIT_FILE, storage);
  end

  // ---------------------------------------------------------------------------
  // Decodificacion de la direccion
  //
  // Los cuatro bits bajos no participan: la direccion siempre es multiplo de
  // 16. El indice completo se calcula antes de recortarlo, para que la
  // comprobacion de rango mire la direccion entera y no solo los bits que
  // caben en el indice.
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
  // Lectura sincrona
  // ---------------------------------------------------------------------------

  always_ff @(posedge clk) begin
    bundle <= in_range ? storage[index] : {`BUNDLE_W{1'b0}};
  end

endmodule
