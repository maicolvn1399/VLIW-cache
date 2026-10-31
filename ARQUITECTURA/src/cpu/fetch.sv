`timescale 1ns/1ps

// =============================================================================
// fetch.sv - Etapa de busqueda: contador de programa.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Mantiene el PC, lo presenta a la memoria de instrucciones y decide el
// siguiente: el bundle contiguo, el destino de un salto tomado, o ninguno
// despues de HALT.
//
// -----------------------------------------------------------------------------
// QUIEN TOMA EL PC Y CUANDO
// -----------------------------------------------------------------------------
// La salida pc es la del registro, sin logica de por medio, y va a dos lados
// que la capturan en el MISMO flanco:
//
//   imem.sv       addr      -> el bundle sale registrado en el ciclo siguiente
//   reg_if_id.sv  pc_in     -> el PC acompana al bundle hasta decodificacion
//
// Por eso la direccion no se registra en la frontera: imem.sv ya es el registro
// IF/ID del bundle, y si la direccion llegara un flanco tarde el pipeline
// entero correria un ciclo.
//
// -----------------------------------------------------------------------------
// EL DELAY SLOT SALE SOLO
// -----------------------------------------------------------------------------
// La BRU resuelve en decodificacion, con el PC del bundle que trae el salto.
// En ese mismo ciclo este registro ya apunta al bundle siguiente, que es el que
// se esta buscando:
//
//   ciclo k     ID tiene el salto (PC = p)   este registro vale p + 16
//   flanco      imem toma p + 16, el delay slot; este registro toma el destino
//   ciclo k+1   ID tiene el delay slot       este registro vale el destino
//
// No hay que elegir entre el contador y el destino para el delay slot ni
// anular nada: el siguiente PC es simplemente taken ? target : pc + 16.
//
// -----------------------------------------------------------------------------
// HALT TAMBIEN TIENE DELAY SLOT
// -----------------------------------------------------------------------------
// El ISA dice que despues de todo salto se ejecuta exactamente un bundle, pero
// no dice si HALT cuenta como salto. Se trata igual: cuando HALT esta en
// decodificacion el bundle siguiente ya se esta buscando, y anularlo exigiria
// una senal de vaciado que ninguna frontera tiene. Se ejecuta, y a partir del
// flanco en que la BRU senala HALT el PC queda congelado y valid baja.
//
// Los bundles que ya estaban dentro del pipeline terminan normalmente. Esperar
// a que se vacien antes de terminar la simulacion es trabajo de quien observa
// halted, no de este modulo.
//
// Una vez detenido, el modulo ignora taken y halt. El delay slot de HALT puede
// traer un salto y la BRU lo resolveria igual, pero ya no hay nada que buscar.
// Solo el reset lo saca de ese estado.
//
// -----------------------------------------------------------------------------
// ALINEACION
// -----------------------------------------------------------------------------
// isa.md 1.2 fija el PC como multiplo de 16. El avance secuencial y el destino
// relativo de la BRU siempre lo son, pero JR y JALR saltan a R[rs] tal cual, y
// el registro puede traer cualquier valor. Los cuatro bits bajos se fuerzan a
// cero aqui, en el unico lugar por el que entra un destino, para que el PC que
// ven la BRU (enlace PC + 32) y la boveda (region segura) sea el del bundle que
// de verdad se busco. imem.sv ignora esos bits de todas formas, asi que sin
// esto la memoria y el resto del procesador verian direcciones distintas.
// =============================================================================

`include "cerbero_defs.svh"

module fetch #(
    // Direccion del primer bundle. El codigo de usuario empieza en cero
    // segun el mapa de memoria de isa.md 1.4.
    parameter logic [`XLEN-1:0] RESET_PC = '0
) (
    input  logic clk,
    input  logic rst_n,                  // reset sincrono, activo en bajo

    // ---- Desde la BRU, en decodificacion -----------------------------------
    input  logic             taken,
    input  logic [`XLEN-1:0] target,
    input  logic             halt,

    // ---- Hacia imem.sv y reg_if_id.sv --------------------------------------
    output logic [`XLEN-1:0] pc,
    output logic             valid,      // el bundle que se busca es de verdad

    // ---- Hacia quien termina la simulacion ---------------------------------
    output logic             halted
);

  // Cada bundle ocupa 16 bytes
  localparam logic [`XLEN-1:0] BUNDLE_BYTES = `BUNDLE_W / 8;

  // Mascara que deja el PC alineado al bundle
  localparam logic [`XLEN-1:0] ALIGN_MASK = ~(BUNDLE_BYTES - 1);

  logic [`XLEN-1:0] pc_next;

  assign pc_next = taken ? (target & ALIGN_MASK) : (pc + BUNDLE_BYTES);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc     <= RESET_PC;
      halted <= 1'b0;
    end else if (!halted) begin
      pc     <= halt ? pc : pc_next;
      halted <= halt;
    end
  end

  assign valid = !halted;

endmodule
