`timescale 1ns/1ps

// =============================================================================
// load_align.sv - Extraccion del carril de una carga.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Toma la palabra de 32 bits que entrega la memoria de datos y saca de ella el
// byte, la media palabra o la palabra que pidio la instruccion, extendiendo el
// signo si corresponde.
//
// -----------------------------------------------------------------------------
// POR QUE ES UN MODULO APARTE
// -----------------------------------------------------------------------------
// La LSU es la unica unidad funcional que trabaja en DOS etapas: calcula la
// direccion en EX y extrae el carril en MEM, porque el dato de la memoria no
// existe hasta MEM. Un modulo combinacional no puede estar en dos ciclos a la
// vez, asi que la mitad que vive en MEM tiene que ser instanciable por separado.
//
// Las dos alternativas eran peores. Dejarlo dentro de lsu.sv y poner una
// segunda instancia de la LSU completa en MEM desperdicia todo el calculo de
// direccion y arrastra una decena de salidas sin usar. Copiar la logica en el
// datapath crea dos implementaciones de la misma tabla de tamanos y signos,
// capaces de divergir en el primer cambio.
//
// Asi hay una sola copia: lsu.sv la instancia para su propia salida, de modo
// que tb_lsu.sv la sigue cubriendo con sus 245 casos, y el datapath la instancia
// otra vez en la etapa de memoria con los datos que le llegan por la frontera
// EX/MEM.
//
// -----------------------------------------------------------------------------
// SELECCIONAR Y NO DESPLAZAR
// -----------------------------------------------------------------------------
// El carril se elige con un multiplexor en vez de correr la palabra entera
// hacia la derecha: el multiplexor es de cuatro a uno sobre ocho bits, y el
// desplazador seria de 32 bits con la mitad de la salida descartada. Es la
// misma decision que toma la escritura, donde el dato se replica en los cuatro
// carriles y la mascara elige.
//
// La alineacion NO se comprueba aqui. Eso es MISALIGN y lo levanta la LSU en
// EX, que es quien puede anular el acceso antes de que llegue a la memoria.
// Cuando el acceso llega hasta aca ya se sabe que estaba alineado, y por eso la
// media palabra solo mira el bit 1 de la direccion.
// =============================================================================

`include "cerbero_defs.svh"

module load_align (
    // Slot S2 crudo: de el salen el tamano del acceso y si extiende con signo.
    //
    // Solo se usan los bits del opcode, [31:27]. El resto del slot viaja por la
    // frontera EX/MEM de todas formas, asi que recibirlo completo evita que el
    // datapath tenga que recortarlo y mantiene la convencion del proyecto: las
    // unidades reciben el slot crudo.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] slot,
    /* verilator lint_on UNUSEDSIGNAL */

    // Dos bits bajos de la direccion efectiva, que eligen el carril
    input  logic [1:0]  addr_lo,

    // La carga escribe de verdad. Con esto en cero la salida es cero, para no
    // propagar un dato que nadie va a guardar.
    input  logic        rd_write_en,

    // Palabra completa que entrega la memoria
    input  logic [31:0] mem_read_data,

    // Dato ya extraido y extendido, listo para el banco de registros
    output logic [31:0] rd_load_data
);

  // ---------------------------------------------------------------------------
  // Campos del opcode
  //
  // El opcode de la LSU esta estructurado: bits 2:1 son el tamano y el bit 0
  // dice si la extension es con ceros. Los recortes se hacen con asignaciones
  // continuas y no dentro de un always_comb, porque Icarus no infiere
  // sensibilidad sobre recortes constantes dentro de un proceso.
  // ---------------------------------------------------------------------------

  // Del opcode solo se usan los bits 2:1 (tamano) y el 0 (extension). El bit 4
  // es el postincremento y el 3 dice si es almacenamiento: ninguno de los dos
  // cambia como se extrae un carril. Se recorta con los macros en vez de con
  // numeros a mano para no duplicar la estructura del opcode.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [4:0] opcode;
  /* verilator lint_on UNUSEDSIGNAL */
  assign opcode = slot[`F_OPC];

  logic [1:0] tam;
  logic       is_unsigned;

  assign tam         = opcode[`LSU_FLD_TAM];
  assign is_unsigned = opcode[`LSU_BIT_U];

  // ---------------------------------------------------------------------------
  // Carriles
  // ---------------------------------------------------------------------------

  logic [7:0]  byte_lane0, byte_lane1, byte_lane2, byte_lane3;
  logic [15:0] half_lane0, half_lane1;

  assign byte_lane0 = mem_read_data[7:0];
  assign byte_lane1 = mem_read_data[15:8];
  assign byte_lane2 = mem_read_data[23:16];
  assign byte_lane3 = mem_read_data[31:24];
  assign half_lane0 = mem_read_data[15:0];
  assign half_lane1 = mem_read_data[31:16];

  logic [7:0]  raw_byte;
  logic [15:0] raw_half;

  always_comb begin
    case (addr_lo)
      2'b00  : raw_byte = byte_lane0;
      2'b01  : raw_byte = byte_lane1;
      2'b10  : raw_byte = byte_lane2;
      default: raw_byte = byte_lane3;
    endcase
  end

  // La media palabra solo tiene dos carriles posibles, y el bit 0 de la
  // direccion ya quedo descartado por la comprobacion de alineacion.
  assign raw_half = addr_lo[1] ? half_lane1 : half_lane0;

  // ---------------------------------------------------------------------------
  // Extension
  // ---------------------------------------------------------------------------

  logic [31:0] byte_ext;
  logic [31:0] half_ext;

  assign byte_ext = is_unsigned ? {24'd0, raw_byte}
                                : {{24{raw_byte[7]}},  raw_byte};
  assign half_ext = is_unsigned ? {16'd0, raw_half}
                                : {{16{raw_half[15]}}, raw_half};

  always_comb begin
    rd_load_data = 32'd0;

    if (rd_write_en) begin
      case (tam)
        `LSU_TAM_B : rd_load_data = byte_ext;
        `LSU_TAM_H : rd_load_data = half_ext;
        `LSU_TAM_W : rd_load_data = mem_read_data;
        default    : rd_load_data = 32'd0;
      endcase
    end
  end

endmodule
