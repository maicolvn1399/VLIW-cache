`timescale 1ns/1ps

// =============================================================================
// reg_if_id.sv - Registro de segmentacion entre busqueda y decodificacion.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es el mas pequeno de los tres porque la mayor parte de esta frontera ya
// existe: el registro de salida de imem.sv ES el registro del bundle. Lo que
// falta es lo que acompana al bundle y no sale de la memoria.
//
// -----------------------------------------------------------------------------
// POR QUE EL CONTADOR DE PROGRAMA TIENE QUE VIAJAR
// -----------------------------------------------------------------------------
// Dos unidades necesitan el PC DEL BUNDLE QUE ESTAN EJECUTANDO, no el que el
// contador tenga en ese momento:
//
//   bru.sv        calcula el destino relativo como pc + 16*(1+desp) y el
//                 enlace como pc + 32. Resuelve en decodificacion, asi que
//                 necesita el PC aqui.
//   key_vault.sv  compara el PC contra [SEC_BASE, SEC_LIMIT] para el cierre
//                 automatico de sesion. Ejecuta en EX, asi que lo necesita un
//                 registro mas adelante, y de eso se encarga reg_id_ex.sv.
//
// Si cualquiera de las dos mirara el contador vivo, estaria mirando el PC de un
// bundle posterior: en el ciclo en que el bundle n esta en decodificacion, el
// contador ya apunta al bundle n+1. El salto aterrizaria un bundle corrido y la
// boveda cerraria la sesion segun la posicion equivocada.
//
// -----------------------------------------------------------------------------
// NO HAY SENAL DE VACIADO, Y ESO NO ES UN OLVIDO
// -----------------------------------------------------------------------------
// Un pipeline con saltos normalmente necesita anular los bundles que entraron
// de forma especulativa. Aqui no entra ninguno, y la cuenta es esta:
//
//   ciclo n     IF   se busca el bundle n, que trae el salto
//   ciclo n+1   ID   la BRU resuelve el salto y presenta el destino al
//                    contador; en paralelo se busca el bundle n+1
//   ciclo n+2   IF   se busca el DESTINO
//
// El bundle n+1 es el delay slot, y el ISA dice que se ejecuta siempre, se tome
// el salto o no. El destino entra justo despues. Nunca se busca un bundle que
// haya que descartar, asi que no hay nada que vaciar: ni esta frontera ni las
// otras dos llevan senal de flush.
//
// Eso es exactamente lo que compra resolver el salto en decodificacion en vez
// de en ejecucion. Resolviendo en EX harian falta dos delay slots, o un delay
// slot mas logica de vaciado en las tres fronteras.
//
// -----------------------------------------------------------------------------
// LA SENAL VALID
// -----------------------------------------------------------------------------
// valid dice "en esta etapa hay un bundle de verdad". La ponen en cero el reset
// y, mas adelante, HALT: las unidades la usan para no registrar fallas de un
// bundle que no existe, que es el caso 10 de tb_lsu y el T19 de tb_key_vault.
// No sirve para vaciar nada, porque no hay nada que vaciar.
// =============================================================================

`include "cerbero_defs.svh"

module reg_if_id (
    input  logic clk,
    input  logic rst_n,              // reset sincrono, activo en bajo

    // ---- Desde la etapa de busqueda ----------------------------------------
    input  logic             valid_in,
    input  logic [`XLEN-1:0] pc_in,

    // ---- Hacia la etapa de decodificacion ----------------------------------
    output logic             valid_out,
    output logic [`XLEN-1:0] pc_out
);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      pc_out    <= {`XLEN{1'b0}};
    end else begin
      valid_out <= valid_in;
      pc_out    <= pc_in;
    end
  end

endmodule
