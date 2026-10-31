`timescale 1ns/1ps

// =============================================================================
// crypto_unit.sv - Unidad Feistel4, slot S3 del bundle (tipo F).
//
// Ejecuta UNA ronda de la red Feistel4 sobre un par de registros alineado.
// Un bloque completo se cifra encadenando cuatro instrucciones con indice de
// ronda 0 a 3, y se descifra con los indices en orden inverso. El
// encadenamiento lo hace el programa; la unidad solo ve una ronda.
//
// Combinacional a proposito: la tabla de unidades funcionales del ISA describe
// esta unidad como "una ronda completa, combinacional". El reparto por etapas
// vive en el datapath, que es quien debe respetar la latencia de 3 bundles.
//
// La unidad NO detecta fallas. key_vault.sv ya las detecta para las
// instrucciones de ronda: bits reservados distintos de cero, falta de
// autenticacion y ranura de llave sin inicializar. Aca solo se consume la
// senal de permiso que la boveda produce. Duplicar esa logica crearia dos
// copias capaces de divergir.
// =============================================================================

`include "cerbero_defs.svh"

module crypto_unit (
    // Slot S3 crudo, bits 31:16 del bundle.
    //
    // La unidad solo mira el opcode y el campo de par. Los campos de llave y
    // de ronda los decodifica key_vault.sv, que es quien selecciona la
    // subllave, y los bits reservados los verifica la misma boveda. De ahi
    // que slot[9:0] quede sin usar en este modulo.
    //
    // La exencion de lint es deliberada y no un descuido: decodificar aqui
    // esos campos crearia una segunda copia de la seleccion de subllave,
    // capaz de divergir de la de la boveda.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [15:0] slot,
    /* verilator lint_on UNUSEDSIGNAL */

    // Permiso y subllave, ambos desde key_vault
    input  logic        grant,
    input  logic [31:0] subkey,

    // Mitades leidas del banco de registros
    input  logic [31:0] l_val,
    input  logic [31:0] r_val,

    // Indices del par, para que el datapath lea y escriba
    output logic [3:0]  l_idx,
    output logic [3:0]  r_idx,

    // Resultado de la ronda
    output logic        wr_en,
    output logic [31:0] l_new,
    output logic [31:0] r_new
);

  // ---------------------------------------------------------------------------
  // Sentido de la ronda
  //
  // La boveda garantiza que, con el permiso en alto, el opcode es F4E o F4D:
  // su senal de permiso ya exige que la instruccion sea una ronda valida. Por
  // eso alcanza con distinguir el descifrado; cualquier otra cosa que llegue
  // con permiso es cifrado.
  // ---------------------------------------------------------------------------

  localparam logic [2:0] OP_F4D = `CRP_F4D;

  logic is_decrypt;
  assign is_decrypt = (slot[`S3_OPC] == OP_F4D);

  // ---------------------------------------------------------------------------
  // Funcion de ronda
  //
  //   ROL(x, r) = (x << r) | (x >> (32 - r))
  //   F(x, k)   = (ROL(x, 5) + k) ^ ROL(x, 13)
  //
  // La suma es modular en 2^32, sin acarreo de salida: el sumador de 32 bits
  // trunca solo.
  //
  // Las dos rotaciones son por cantidades CONSTANTES, asi que se escriben como
  // concatenaciones de rangos y no con operadores de desplazamiento. Queda
  // explicito que son permutaciones fijas de cables, sin desplazador de
  // barril, y no hay ninguna duda sobre el relleno.
  //
  //   ROL(x,5)  -> los 27 bits bajos suben a la parte alta, los 5 altos bajan
  //   ROL(x,13) -> los 19 bits bajos suben a la parte alta, los 13 altos bajan
  // ---------------------------------------------------------------------------

  logic [31:0] f_in;
  logic [31:0] rot5;
  logic [31:0] rot13;
  logic [31:0] f_out;

  assign rot5  = {f_in[26:0], f_in[31:27]};
  assign rot13 = {f_in[18:0], f_in[31:19]};
  assign f_out = (rot5 + subkey) ^ rot13;

  // ---------------------------------------------------------------------------
  // La ronda, en los dos sentidos
  //
  //   cifrado      L_nuevo = R              R_nuevo = L ^ F(R, k)
  //   descifrado   R_nuevo = L              L_nuevo = R ^ F(L, k)
  //
  // La estructura es la misma con las mitades intercambiadas: una salida es
  // copia directa de la otra entrada, y la otra es el XOR con la funcion. Por
  // eso las dos comparten el mismo sumador y los mismos rotadores, y lo unico
  // que cambia es de donde sale el operando de la funcion y hacia donde va
  // cada resultado.
  //
  // Son inversas exactas: aplicando el descifrado con la misma subllave sobre
  // la salida del cifrado, el termino de la funcion se cancela consigo mismo
  // en el XOR y la otra mitad vuelve copiada.
  // ---------------------------------------------------------------------------

  logic [31:0] round_l;
  logic [31:0] round_r;

  assign f_in   = is_decrypt ? l_val : r_val;
  assign round_l = is_decrypt ? (r_val ^ f_out) : r_val;
  assign round_r = is_decrypt ? l_val : (l_val ^ f_out);

  // ---------------------------------------------------------------------------
  // Gobierno por el permiso de la boveda
  //
  // Una ronda reescribe las dos mitades o ninguna: no existe el caso de
  // escribir media. El permiso viene de la boveda, que es quien decide si la
  // operacion procede.
  //
  // Las salidas de datos tambien se apagan sin permiso, y no es redundante
  // con el habilitador de escritura. Si el resultado siguiera saliendo, con
  // las dos mitades en cero las rotaciones darian cero, la funcion de ronda
  // quedaria igual a la subllave y el XOR con la mitad opuesta la dejaria
  // intacta: la subllave apareceria literal en una salida. El aislamiento que
  // exige el modelo de seguridad del ISA no debe depender de que la boveda
  // esconda la llave; se sostiene aca.
  // ---------------------------------------------------------------------------

  assign wr_en = grant;
  assign l_new = grant ? round_l : 32'd0;
  assign r_new = grant ? round_r : 32'd0;

  // ---------------------------------------------------------------------------
  // Decodificacion del par
  //
  // Pn = R(2n) : R(2n+1), con la mitad L en el registro par y la R en el
  // impar. Multiplicar por dos es correr un lugar, asi que el indice sale de
  // concatenar el campo del par con el bit que elige mitad: cero para la
  // izquierda, uno para la derecha. No hace falta ningun sumador.
  //
  // Los indices salen siempre, tambien sin permiso, porque el datapath los
  // necesita para leer los operandos antes de saber si la operacion procede.
  //
  // El par 7 son el puntero de pila y el registro de enlace. Es un encoding
  // legal y la unidad no lo trata distinto.
  // ---------------------------------------------------------------------------

  logic [2:0] pair_field;
  assign pair_field = slot[`S3_PAR];

  assign l_idx = {pair_field, 1'b0};
  assign r_idx = {pair_field, 1'b1};

endmodule
