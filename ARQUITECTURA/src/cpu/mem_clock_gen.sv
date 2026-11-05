`timescale 1ns/1ps

// =============================================================================
// mem_clock_gen.sv - Dominio de reloj de la memoria principal.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
//
// El procesador corre a 100 MHz y la memoria principal a 25 MHz. Este modulo
// produce el reloj lento por division entera del rapido, que es lo que el
// enunciado permite como alternativa a un PLL (seccion 3.2.5).
//
// -----------------------------------------------------------------------------
// POR QUE UN DIVISOR Y NO UN PLL
// -----------------------------------------------------------------------------
// Un PLL de verdad vive en un bloque dedicado del FPGA, no se describe en RTL
// portable y no se simula en Icarus. Un divisor entero si, y ademas tiene una
// propiedad que un PLL no da gratis: el reloj lento queda en fase con el
// rapido, porque sale de el.
//
// Eso importa para el cruce de dominios. Dos relojes sin relacion de fase
// obligan a sincronizadores de dos biestables y a aceptar metaestabilidad; dos
// relojes donde uno es el otro dividido por un entero son MESOCRONOS: cada
// flanco de memoria cae exactamente sobre un flanco de procesador. El cruce se
// puede hacer entonces con una senal de habilitacion, sin sincronizadores y sin
// riesgo de metaestabilidad, que es justo lo que hace mem_controller.sv.
//
// Esto no es evitar el problema del cruce de dominios: es resolverlo eligiendo
// una relacion entre los relojes que lo vuelve tratable. Un sistema real con
// memoria externa suele estar en este caso, porque el reloj de memoria se
// deriva del mismo oscilador.
//
// -----------------------------------------------------------------------------
// LAS DOS SALIDAS
// -----------------------------------------------------------------------------
//   mem_clk    el reloj lento. Lo usa main_memory.sv para su arreglo. Existe
//              para que el modelo tenga de verdad dos dominios y se vea en las
//              formas de onda.
//
//   mem_tick   un pulso de un ciclo de PROCESADOR, encendido exactamente en el
//              ciclo donde mem_clk sube. Es la senal que usa la logica del
//              dominio rapido para saber "aqui hay un flanco de memoria".
//
// La regla de uso es estricta y vale la pena escribirla: la logica del dominio
// rapido NUNCA se sensibiliza a mem_clk, solo mira mem_tick dentro de un
// always_ff sobre clk. Mezclar los dos relojes en un mismo proceso es
// exactamente el error que el enunciado llama crossing mal hecho.
//
// -----------------------------------------------------------------------------
// CICLO DE TRABAJO CON DIVISOR IMPAR
// -----------------------------------------------------------------------------
// Con DIV par el reloj lento queda simetrico. Con DIV impar (el divisor 5 que
// daria 20 MHz) queda DIV/2 ciclos en alto y DIV-DIV/2 en bajo: 2 y 3. Es un
// ciclo de trabajo de 40 %, perfectamente usable para un modelo de simulacion,
// y no afecta en nada las latencias, que se cuentan por flancos de subida.
// =============================================================================

`include "cerbero_defs.svh"

module mem_clock_gen #(
    // Razon de frecuencias. 4 deja la memoria en 25 MHz.
    parameter int DIV = `MEM_CLK_DIV
) (
    input  logic clk,      // 100 MHz, el del procesador
    input  logic rst_n,

    output logic mem_clk,  // 100/DIV MHz
    output logic mem_tick  // un ciclo de clk, donde mem_clk sube
);

  // Cuenta de 0 a DIV-1. El cero es el ciclo en que mem_clk sube.
  localparam int CNT_W = (DIV <= 2) ? 1 : $clog2(DIV);

  logic [CNT_W-1:0] cuenta;

  // El reset deja la cuenta en DIV-1 y mem_clk en bajo, no en cero y alto.
  //
  // La diferencia importa y es sutil. mem_tick es combinacional sobre la cuenta
  // en cero, asi que un reset con la cuenta en cero encenderia el tick durante
  // todo el reset y tambien en el primer ciclo tras soltarlo, sin que mem_clk
  // hubiera subido en ninguno de los dos: la invariante que usa todo el resto
  // del sistema (mem_tick <=> flanco de subida de mem_clk) seria falsa
  // exactamente una vez, al arrancar, que es donde menos se mira.
  //
  // Con la cuenta en DIV-1 el primer flanco tras el reset la lleva a cero y
  // sube mem_clk en el MISMO flanco, asi que el primer tick de la simulacion ya
  // tiene su flanco detras. Y mientras el reset esta activo no hay ningun tick,
  // que es lo correcto: una memoria en reset no esta avanzando ciclos.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cuenta  <= DIV - 1;
      mem_clk <= 1'b0;
    end else begin
      cuenta <= (cuenta == DIV - 1) ? '0 : (cuenta + 1'b1);

      // mem_clk sube en el mismo flanco en que la cuenta vuelve a cero, de modo
      // que mem_tick (que mira la cuenta ya en cero) coincide con ese flanco.
      if (cuenta == DIV - 1)
        mem_clk <= 1'b1;
      else if (cuenta == DIV / 2 - 1)
        mem_clk <= 1'b0;
    end
  end

  assign mem_tick = (cuenta == '0);

endmodule
