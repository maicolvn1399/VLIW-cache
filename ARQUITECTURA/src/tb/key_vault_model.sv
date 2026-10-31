`timescale 1ns/1ps

// =============================================================================
// key_vault_model.sv - Modelo de la boveda de llaves para probar crypto_unit.
//
// Solo para simulacion. NO replica la boveda real, que vive en otra rama y es
// de otra persona: replicarla seria inventar una segunda fuente de verdad.
//
// Lo que si hace, y por eso existe en vez de que el testbench maneje la
// subllave a mano: guarda las cuatro llaves de cuatro palabras y resuelve la
// seleccion (kv, ronda) tomando esos campos del slot, igual que la boveda
// real. Asi el testbench instala una llave una vez y despues emite rondas sin
// decidir cual subllave corresponde a cada una. Si el testbench alimentara la
// subllave a mano podria equivocarse y enmascarar un error de indice.
//
// Los campos kv y ronda los decodifica la boveda, no crypto_unit. Que el
// modelo los extraiga del slot deja eso explicito.
// =============================================================================

module key_vault_model (
    input  logic [15:0] slot,

    // El testbench decide si concede el permiso.
    input  logic        grant_in,

    // Compuerta de la subllave. En 1 el modelo se comporta como la boveda
    // real, que entrega cero cuando no concede. En 0 presenta la subllave de
    // todas formas.
    //
    // El valor 0 existe solo para una prueba: que crypto_unit no dependa de
    // que la boveda le esconda la llave. El aislamiento tiene que sostenerse
    // tambien si la subllave esta presente en la entrada.
    input  logic        gate_subkey,

    output logic [31:0] subkey,
    output logic        grant
);

  // [llave][palabra]. La palabra se indexa por el campo de ronda.
  logic [31:0] keys [0:3][0:3];

  logic [1:0] kv_field;
  logic [1:0] round_field;

  assign kv_field    = slot[9:8];
  assign round_field = slot[7:6];

  assign grant  = grant_in;
  assign subkey = (grant || !gate_subkey) ? keys[kv_field][round_field] : 32'd0;

  // ---------------------------------------------------------------------------
  // Utilidades para el testbench. Tareas y no funciones, porque la llamada
  // jerarquica a tareas es la que Icarus soporta sin sorpresas.
  // ---------------------------------------------------------------------------

  task automatic clear_all();
    for (int k = 0; k < 4; k = k + 1) begin
      for (int w = 0; w < 4; w = w + 1) begin
        keys[k][w] = 32'd0;
      end
    end
  endtask

  task automatic set_word(input logic [1:0] kv,
                          input logic [1:0] widx,
                          input logic [31:0] value);
    keys[kv][widx] = value;
  endtask

  // Instala las cuatro palabras de una llave de una sola vez.
  task automatic set_key(input logic [1:0] kv,
                         input logic [31:0] w0,
                         input logic [31:0] w1,
                         input logic [31:0] w2,
                         input logic [31:0] w3);
    keys[kv][0] = w0;
    keys[kv][1] = w1;
    keys[kv][2] = w2;
    keys[kv][3] = w3;
  endtask

endmodule
