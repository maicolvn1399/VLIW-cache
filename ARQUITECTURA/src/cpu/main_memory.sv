`timescale 1ns/1ps

// =============================================================================
// main_memory.sv - Memoria principal, en el dominio lento.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// 64 KB organizados en 16384 palabras de 32 bits. Avanza solo en los flancos
// del reloj de memoria (25 MHz), de modo que no puede entregar ni aceptar mas
// de una palabra por ciclo de memoria. La latencia de primera palabra y la
// secuencia del burst las modela mem_controller.sv.
//
// -----------------------------------------------------------------------------
// POR QUE ESTE MODULO NO SE SENSIBILIZA A mem_clk
// -----------------------------------------------------------------------------
// Seria lo natural escribir aqui always_ff @(posedge mem_clk), ya que el modulo
// pertenece al dominio lento. Se hizo con clk y la habilitacion mem_tick, y el
// motivo es una carrera real.
//
// mem_clk lo produce mem_clock_gen.sv con una asignacion no bloqueante sobre
// clk. Los registros del controlador tambien. Las dos actualizaciones ocurren
// en el MISMO instante de simulacion, y el flanco de mem_clk que dispararia a
// este modulo llega despues de que los registros del controlador ya tomaron su
// valor nuevo. Es decir: la memoria veria la direccion del ciclo siguiente, con
// tiempo de establecimiento cero. En simulacion anda; en hardware no.
//
// Con clk y una habilitacion no hay dos relojes: todo el sistema conmuta en el
// mismo flanco y la memoria simplemente ignora los ciclos en que mem_tick esta
// apagado. Es exactamente lo que hace una herramienta de sintesis cuando se le
// pide un reloj derivado por division entera, y por eso el resultado es el
// mismo circuito sin la carrera.
//
// mem_clk sigue existiendo y se expone hacia afuera: sirve para ver los dos
// dominios en la forma de onda y para que el diagrama de bloques diga la
// verdad. Lo que no hace es controlar logica.
//
// -----------------------------------------------------------------------------
// LA LECTURA ES COMBINACIONAL, Y ESO ES UNA SIMPLIFICACION CONSCIENTE
// -----------------------------------------------------------------------------
// rdata sale directo del arreglo, sin registro. La alternativa realista seria
// una salida registrada, que es como se comporta un bloque de RAM de FPGA.
//
// Se eligio la combinacional porque cambia el conteo del burst. Con salida
// registrada, la palabra pedida en un flanco de memoria recien esta disponible
// en el siguiente, de modo que sacar las ocho palabras costaria ocho ciclos de
// memoria y no siete. El enunciado fija siete ciclos adicionales despues de la
// primera palabra (seccion 3.2.5), y con la lectura combinacional ese numero
// sale exacto, sin ajustes ni correcciones de un ciclo repartidas por el
// controlador, que es donde se esconden los errores de borde.
//
// Lo que se pierde: en una implementacion sobre FPGA habria que agregar una
// etapa de segmentacion en el controlador y T_mem subiria en un ciclo de
// memoria. Queda anotado en docs/memoria.md como limitacion conocida.
//
// La ESCRITURA si es sincrona y solo ocurre en los flancos de memoria, que es
// lo que impone el limite de una palabra por ciclo de memoria en el burst de
// drenado.
//
// -----------------------------------------------------------------------------
// LA CARGA INICIAL
// -----------------------------------------------------------------------------
// Igual que imem.sv y dmem.sv, acepta un archivo .hex por parametro. En
// simulacion los testbenches tambien la cargan por referencia jerarquica, que
// no depende de rutas relativas.
// =============================================================================

`include "cerbero_defs.svh"

module main_memory #(
    parameter int    NUM_WORDS = `MEM_WORDS,
    parameter string INIT_FILE = ""
) (
    input  logic clk,     // el del procesador; la memoria avanza solo con tick
    input  logic rst_n,
    input  logic tick,    // un flanco de memoria ocurre en este ciclo

    // Direccion de PALABRA, no de byte: el controlador ya descarto los dos bits
    // bajos. Una direccion fuera de rango lee cero y su escritura se ignora.
    input  logic [`XLEN-1:0] addr,
    input  logic             we,
    input  logic [`XLEN-1:0] wdata,

    output logic [`XLEN-1:0] rdata
);

  logic [`XLEN-1:0] storage [0:NUM_WORDS-1];

  logic en_rango;
  assign en_rango = (addr < NUM_WORDS);

  integer i;

  initial begin
    for (i = 0; i < NUM_WORDS; i = i + 1) storage[i] = '0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, storage);
  end

  // Lectura: ver la nota de arriba sobre por que no esta registrada.
  // Una direccion inexistente devuelve cero, igual que dmem.sv, como segunda
  // linea de defensa detras de la comprobacion de rango del controlador.
  assign rdata = en_rango ? storage[addr] : '0;

  // Escritura: solo en los flancos del reloj de memoria. Este es el limite
  // fisico que hace que drenar una linea cueste siete ciclos de memoria.
  always_ff @(posedge clk) begin
    if (rst_n && tick && we && en_rango)
      storage[addr] <= wdata;
  end

endmodule
