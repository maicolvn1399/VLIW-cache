`timescale 1ns/1ps

// =============================================================================
// reg_id_ex.sv - Registro de segmentacion entre decodificacion y ejecucion.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es la frontera mas ancha del pipeline, porque es donde se juntan las dos
// cosas que la etapa de ejecucion necesita y que vienen de sitios distintos:
// los slots, que salen del rebanado del bundle, y los nueve valores leidos del
// banco de registros.
//
// -----------------------------------------------------------------------------
// EL REGISTRO QUE SOSTIENE LA LATENCIA DE 3 BUNDLES
// -----------------------------------------------------------------------------
// El banco de registros lee en el flanco de BAJADA de decodificacion y este
// registro captura en el flanco de SUBIDA siguiente, que es el que abre
// ejecucion. Entre los dos flancos hay medio ciclo, y ese medio ciclo es lo que
// permite que una escritura del mismo ciclo ya se vea en la lectura:
//
//   ciclo m+1   ID   posedge: WB del bundle productor escribe el banco
//                    negedge: el banco lee y publica los nueve valores
//   ciclo m+2   EX   posedge: este registro los captura y EX los consume
//
// De ahi sale m >= n+3 y no m >= n+4. Si este registro capturara en el negedge,
// o si el banco leyera en el posedge, la latencia expuesta pasaria a 4 bundles y
// todo el codigo que genere el grupo de CE1108 quedaria mal calendarizado.
// tb_pipeline.sv lo mide sobre la cadena real en vez de darlo por supuesto.
//
// -----------------------------------------------------------------------------
// QUE CRUZA Y QUE NO
// -----------------------------------------------------------------------------
// Los slots S0, S1, S2 y S3 cruzan: sus unidades ejecutan en EX y reciben el
// slot crudo.
//
// El slot S4 NO cruza. La BRU resuelve en decodificacion, asi que cuando el
// bundle llega a EX su salto ya ocurrio. Lo que cruza de la BRU es el resultado:
// el enlace de retorno y su falla.
//
//   El enlace tiene que viajar porque se escribe en WB, no en ID. El ISA fija
//   una latencia uniforme de 3 bundles y el enlace de JAL no es la excepcion
//   (seccion 9.2), asi que aunque el valor este listo en decodificacion se
//   guarda hasta el final. Escribirlo antes seria mas rapido y romperia la
//   uniformidad, que es el unico numero que el compilador tiene que conocer.
//
//   La falla de la BRU tiene que viajar porque el PSW se actualiza al final de
//   EX, junto con las fallas de los otros cuatro slots. Una falla de ID que se
//   reportara en ID llegaria un ciclo antes que las demas y el PSW mezclaria
//   causas de dos bundles distintos.
//
// El contador de programa cruza porque key_vault.sv lo compara contra la region
// segura y ejecuta en EX.
// =============================================================================

`include "cerbero_defs.svh"

module reg_id_ex (
    input  logic clk,
    input  logic rst_n,              // reset sincrono, activo en bajo

    // ---- Desde la etapa de decodificacion ----------------------------------
    input  logic             valid_in,
    input  logic [`XLEN-1:0] pc_in,

    // Slots crudos. S4 no esta: la BRU ya resolvio en ID
    input  logic [31:0]      s0_inst_in,
    input  logic [31:0]      s1_inst_in,
    input  logic [31:0]      s2_inst_in,
    input  logic [15:0]      s3_inst_in,

    // Los nueve valores que el banco publico en el negedge
    input  logic [`NREAD_PORTS-1:0][`XLEN-1:0] rval_in,

    // Enlace de retorno que produjo la BRU en ID
    input  logic                  link_we_in,
    input  logic [`RIDX_W-1:0]    link_idx_in,
    input  logic [`XLEN-1:0]      link_val_in,

    // Falla del slot S4, detectada en ID
    input  logic                  s4_fault_in,
    input  logic [2:0]            s4_cause_in,

    // ---- Hacia la etapa de ejecucion ---------------------------------------
    output logic             valid_out,
    output logic [`XLEN-1:0] pc_out,

    output logic [31:0]      s0_inst_out,
    output logic [31:0]      s1_inst_out,
    output logic [31:0]      s2_inst_out,
    output logic [15:0]      s3_inst_out,

    output logic [`NREAD_PORTS-1:0][`XLEN-1:0] rval_out,

    output logic                  link_we_out,
    output logic [`RIDX_W-1:0]    link_idx_out,
    output logic [`XLEN-1:0]      link_val_out,

    output logic                  s4_fault_out,
    output logic [2:0]            s4_cause_out
);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out    <= 1'b0;
      pc_out       <= {`XLEN{1'b0}};
      s0_inst_out  <= 32'd0;
      s1_inst_out  <= 32'd0;
      s2_inst_out  <= 32'd0;
      s3_inst_out  <= 16'd0;
      rval_out     <= '0;
      link_we_out  <= 1'b0;
      link_idx_out <= {`RIDX_W{1'b0}};
      link_val_out <= {`XLEN{1'b0}};
      s4_fault_out <= 1'b0;
      s4_cause_out <= `CAUSE_NONE;
    end else begin
      valid_out    <= valid_in;
      pc_out       <= pc_in;
      s0_inst_out  <= s0_inst_in;
      s1_inst_out  <= s1_inst_in;
      s2_inst_out  <= s2_inst_in;
      s3_inst_out  <= s3_inst_in;
      rval_out     <= rval_in;
      link_we_out  <= link_we_in;
      link_idx_out <= link_idx_in;
      link_val_out <= link_val_in;
      s4_fault_out <= s4_fault_in;
      s4_cause_out <= s4_cause_in;
    end
  end

endmodule
