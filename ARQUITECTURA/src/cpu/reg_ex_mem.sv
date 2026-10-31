`timescale 1ns/1ps

// =============================================================================
// reg_ex_mem.sv - Registro de segmentacion entre ejecucion y memoria.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Lleva todo lo que la etapa de memoria y la de escritura necesitan y que se
// produjo en ejecucion. El dato leido de memoria NO esta aqui: ese cruza por el
// registro de salida de dmem.sv, que es la otra mitad de esta misma frontera.
//
// -----------------------------------------------------------------------------
// NO HAY REGISTRO MEM/WB, Y ESO ES A PROPOSITO
// -----------------------------------------------------------------------------
// Son tres registros y no cuatro. El banco de registros escribe en el flanco de
// subida que abre WB, asi que sus entradas tienen que estar estables durante
// MEM, que es precisamente donde las deja este registro. Los biestables del
// banco SON la frontera MEM/WB. Lo mismo vale para el PSW, que captura las
// fallas en ese mismo flanco.
//
// Es el mismo patron que ya aparece dos veces en el diseno: el registro de
// salida de imem es IF/ID y el de dmem es EX/MEM. Un registro de segmentacion
// adicional delante del banco no agregaria nada y correria la escritura al
// ciclo n+5, con lo que la latencia expuesta pasaria de 3 bundles a 4.
//
// -----------------------------------------------------------------------------
// POR QUE CRUZAN LAS FALLAS Y LAS BANDERAS
// -----------------------------------------------------------------------------
// El PSW se actualiza en el mismo flanco que el banco de registros, no antes.
// Eso hace que la latencia de las banderas y la de un resultado sean el mismo
// numero, 3 bundles, que es lo que promete la seccion 9.2 del ISA: "la latencia
// es identica para todas las unidades, no hay tabla de casos especiales".
//
// Actualizar el PSW al final de EX seria medio pipeline mas temprano y dejaria
// las banderas legibles a los 2 bundles. No romperia ningun programa bien
// calendarizado, pero el hardware seria mas permisivo que el documento, y esa
// clase de diferencia es la que hace que un programa escrito a mano "funcione"
// y despues falle contra otra implementacion.
//
// Las cinco fallas llegan juntas: cuatro desde las unidades de EX y la del slot
// S4 desde decodificacion, que reg_id_ex.sv ya retraso un ciclo para alinearla.
//
// -----------------------------------------------------------------------------
// EL DATO DE LA CARGA ES EL UNICO HUECO
// -----------------------------------------------------------------------------
// write_value viaja completo, con los siete puertos, pero la entrada del puerto
// WP_S2_RD no tiene nada util todavia: el dato de la carga sale de dmem durante
// MEM. La etapa de memoria sustituye esa entrada por el dato ya extraido del
// carril antes de que el banco la vea.
//
// Viaja igual, en vez de excluirla, porque mantener el arreglo uniforme deja
// que la salida de este registro se conecte directo a la interfaz del banco.
// Son 32 biestables que no cargan informacion durante un ciclo; a cambio no hay
// un caso especial que alguien pueda conectar mal.
//
// Para terminar la carga, la etapa de memoria necesita dos cosas mas de EX:
//
//   s2_inst   el opcode dice el tamano del acceso y si extiende con signo
//   addr_lo   los dos bits bajos de la direccion efectiva dicen cual carril
//
// El resto de la direccion ya hizo su trabajo en la entrada de dmem y no cruza.
// =============================================================================

`include "cerbero_defs.svh"

module reg_ex_mem (
    input  logic clk,
    input  logic rst_n,              // reset sincrono, activo en bajo

    // ---- Desde la etapa de ejecucion ---------------------------------------
    input  logic             valid_in,

    // Lo que hace falta en MEM para terminar una carga
    input  logic [31:0]      s2_inst_in,
    input  logic [1:0]       addr_lo_in,

    // Puertos de escritura del banco, en el orden de los WP_*
    input  logic [`NWRITE_PORTS-1:0]                write_enable_in,
    input  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   write_index_in,
    input  logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     write_value_in,

    // Fallas de los cinco slots, en orden S0..S4
    input  logic [4:0]       fault_in,
    input  logic [4:0][2:0]  cause_in,

    // Banderas de ALU-0, con el orden {V, C, N, Z}
    input  logic             flags_we_in,
    input  logic [3:0]       flags_in,

    // ---- Hacia las etapas de memoria y escritura ---------------------------
    output logic             valid_out,

    output logic [31:0]      s2_inst_out,
    output logic [1:0]       addr_lo_out,

    output logic [`NWRITE_PORTS-1:0]                write_enable_out,
    output logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   write_index_out,
    output logic [`NWRITE_PORTS-1:0][`XLEN-1:0]     write_value_out,

    output logic [4:0]       fault_out,
    output logic [4:0][2:0]  cause_out,

    output logic             flags_we_out,
    output logic [3:0]       flags_out
);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out        <= 1'b0;
      s2_inst_out      <= 32'd0;
      addr_lo_out      <= 2'd0;
      write_enable_out <= '0;
      write_index_out  <= '0;
      write_value_out  <= '0;
      fault_out        <= '0;
      cause_out        <= '0;
      flags_we_out     <= 1'b0;
      flags_out        <= 4'd0;
    end else begin
      valid_out        <= valid_in;
      s2_inst_out      <= s2_inst_in;
      addr_lo_out      <= addr_lo_in;
      write_enable_out <= write_enable_in;
      write_index_out  <= write_index_in;
      write_value_out  <= write_value_in;
      fault_out        <= fault_in;
      cause_out        <= cause_in;
      flags_we_out     <= flags_we_in;
      flags_out        <= flags_in;
    end
  end

endmodule
