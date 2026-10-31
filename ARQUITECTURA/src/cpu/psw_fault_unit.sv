`timescale 1ns/1ps

// =============================================================================
// psw_fault_unit.sv - Registro de estado del programa y resolucion de fallas.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Mantiene el PSW que fija isa.md 1.2 y aplica la politica de "anular y marcar":
// toda condicion anomala anula la operacion de su slot y queda registrada aqui.
// El pipeline nunca se detiene ni se vacia, asi que este modulo no tiene ninguna
// salida de control; solo guarda estado y lo publica.
//
//   bit  0  Z          banderas de ALU-0, las unicas que escriben banderas
//   bit  1  N
//   bit  2  C
//   bit  3  V
//   bit  4  AUTH       espejo de la boveda
//   bit  5  AUTHFAIL   espejo de la boveda
//   bit  6  EXC        ocurrio una falla
//   bits 9:7 CAUSE     causa de la falla
//   bits 31:10         reservados, se leen como cero
//
// -----------------------------------------------------------------------------
// AUTH Y AUTHFAIL SON ESPEJOS, NO REGISTROS DE ESTE MODULO
// -----------------------------------------------------------------------------
// key_vault.sv ya mantiene su propio estado de sesion y lo publica en sus
// salidas auth y authfail, rotuladas "hacia PSW". Aqui se cablean directo al
// bit que les toca.
//
// Que sean espejos y no copias es deliberado. La boveda implementa la regla de
// auto-logout completa (falla propia, falla en otro slot del mismo bundle, o PC
// fuera de [SEC_BASE, SEC_LIMIT]) y la tiene verificada en tb_key_vault. Si
// este modulo guardara su propio bit AUTH y lo apagara por su cuenta, habria dos
// registros que deben coincidir siempre y ninguna garantia de que lo hagan: la
// boveda podria seguir entregando subllaves con el PSW diciendo que la sesion
// esta cerrada, o al contrario. Con un solo registro el problema no existe.
//
// De ahi que "cualquier falla limpia AUTH de inmediato", que pide isa.md 1.2,
// no aparezca en este archivo: lo cumple la boveda por su entrada fault_any, y
// este modulo lo refleja sin hacer nada.
//
// -----------------------------------------------------------------------------
// WCONF SE DETECTA AQUI Y NO EN LA ETAPA ID
// -----------------------------------------------------------------------------
// WCONF es "dos slots escriben el mismo registro", y eso depende de si cada
// slot ESCRIBE de verdad. En la etapa de decodificacion todavia no se sabe: S4
// escribe el enlace solo si el salto se toma, S2 no escribe si la direccion
// sale desalineada o fuera de rango, y S3 no escribe el par si la boveda no da
// permiso. Las tres cosas se resuelven en EX.
//
// Por eso la deteccion mira los habilitadores de escritura REALES, los mismos
// siete que recibe el banco de registros, ya filtrados por las fallas de cada
// unidad. Un detector en ID solo podria suponer que todo slot con opcode de
// escritura va a escribir, y reportaria WCONF en bundles que nunca chocan. Un
// falso positivo en el PSW es peor que no reportar nada, porque el programa lo
// consulta con MFPSW y actua sobre el.
//
// Dos puertos del MISMO slot no son WCONF. El slot S2 escribe dos veces en
// LW.INC, el destino y el registro base, y el ISA ya define quien gana cuando
// coinciden: el dato cargado, que es el puerto de menor numero. Lo mismo para
// las dos mitades del par en S3, que ademas nunca pueden ser el mismo registro
// porque son {par,0} y {par,1}. WCONF es una condicion ENTRE slots, asi que las
// comparaciones intra-slot no estan.
//
// -----------------------------------------------------------------------------
// EXC Y CAUSE SE MARCAN UNA SOLA VEZ
// -----------------------------------------------------------------------------
// isa.md 1.2 dice que "EXC se marca solo una vez" y que el PSW no es escribible
// directamente: la unica instruccion que lo toca es MFPSW, que lo lee. En
// consecuencia los dos campos son pegajosos y solo el reset los limpia, y la
// causa que queda es la de la PRIMERA falla.
//
// Guardar la primera y no la ultima es lo que sirve para depurar. Una falla
// suele arrastrar otras (un load anulado deja un registro con el valor viejo y
// el bundle siguiente opera con basura), asi que la ultima causa casi siempre
// es una consecuencia y la primera es la causa raiz. Si el programa necesita
// distinguir varias fallas, el patron es consultar MFPSW despues de cada tramo
// corto, que es lo que la politica sin traps permite.
//
// Dentro de un mismo bundle, en cambio, si hay prioridad: prevalece la causa
// del slot de indice menor, S0 > S1 > S2 > S3 > S4, que es el mismo orden que
// resuelve los conflictos de escritura.
// =============================================================================

`include "cerbero_defs.svh"

module psw_fault_unit (
    input  logic clk,
    input  logic rst_n,          // reset sincrono, activo en bajo

    // ---- Banderas, exclusivas de ALU-0 -------------------------------------
    // flags viene de alu.sv con el orden {V, C, N, Z}, el mismo de flags_o
    input  logic       flags_we,
    input  logic [3:0] flags,

    // ---- Espejo del estado de la boveda ------------------------------------
    input  logic       auth,
    input  logic       authfail,

    // ---- Fallas que publica cada unidad funcional --------------------------
    input  logic       s0_fault,
    input  logic [2:0] s0_cause,
    input  logic       s1_fault,
    input  logic [2:0] s1_cause,
    input  logic       s2_fault,
    input  logic [2:0] s2_cause,
    input  logic       s3_fault,
    input  logic [2:0] s3_cause,
    input  logic       s4_fault,
    input  logic [2:0] s4_cause,

    // ---- Habilitadores de escritura reales, los mismos del banco ----------
    input  logic [`NWRITE_PORTS-1:0]                write_enable,
    input  logic [`NWRITE_PORTS-1:0][`RIDX_W-1:0]   write_index,

    // ---- Salidas -----------------------------------------------------------
    output logic [`XLEN-1:0] psw,
    output logic             wconf_any     // diagnostico, no es parte del PSW
);

  // ---------------------------------------------------------------------------
  // Escrituras por slot
  //
  // Se nombran aparte porque las comparaciones de abajo se leen mucho mejor
  // asi, y porque deja a la vista cuales puertos pertenecen al mismo slot.
  // ---------------------------------------------------------------------------

  logic w0, w1, w2a, w2b, w3a, w3b, w4;
  logic [`RIDX_W-1:0] r0, r1, r2a, r2b, r3a, r3b, r4;

  assign w0  = write_enable[`WP_S0];        assign r0  = write_index[`WP_S0];
  assign w1  = write_enable[`WP_S1];        assign r1  = write_index[`WP_S1];
  assign w2a = write_enable[`WP_S2_RD];     assign r2a = write_index[`WP_S2_RD];
  assign w2b = write_enable[`WP_S2_BASE];   assign r2b = write_index[`WP_S2_BASE];
  assign w3a = write_enable[`WP_S3_L];      assign r3a = write_index[`WP_S3_L];
  assign w3b = write_enable[`WP_S3_R];      assign r3b = write_index[`WP_S3_R];
  assign w4  = write_enable[`WP_S4_LINK];   assign r4  = write_index[`WP_S4_LINK];

  // ---------------------------------------------------------------------------
  // Deteccion de conflicto
  //
  // Un slot "pierde" si alguno de los registros que escribe coincide con el de
  // un slot de indice MENOR. S0 nunca pierde: es la prioridad maxima.
  // ---------------------------------------------------------------------------

  logic wconf_s0, wconf_s1, wconf_s2, wconf_s3, wconf_s4;

  assign wconf_s0 = 1'b0;

  assign wconf_s1 = w1 && w0 && (r1 == r0);

  assign wconf_s2 = (w2a && ((w0 && r2a == r0) || (w1 && r2a == r1))) ||
                    (w2b && ((w0 && r2b == r0) || (w1 && r2b == r1)));

  assign wconf_s3 = (w3a && ((w0  && r3a == r0 ) || (w1  && r3a == r1 ) ||
                             (w2a && r3a == r2a) || (w2b && r3a == r2b))) ||
                    (w3b && ((w0  && r3b == r0 ) || (w1  && r3b == r1 ) ||
                             (w2a && r3b == r2a) || (w2b && r3b == r2b)));

  assign wconf_s4 = w4 && ((w0  && r4 == r0 ) || (w1  && r4 == r1 ) ||
                           (w2a && r4 == r2a) || (w2b && r4 == r2b) ||
                           (w3a && r4 == r3a) || (w3b && r4 == r3b));

  assign wconf_any = wconf_s1 || wconf_s2 || wconf_s3 || wconf_s4;

  // ---------------------------------------------------------------------------
  // Causa efectiva de cada slot
  //
  // Una unidad que fallo no escribe, asi que no puede estar perdiendo un
  // conflicto al mismo tiempo: los dos terminos son excluyentes en la practica.
  // Aun asi la falla propia va primero, porque es la condicion mas especifica.
  // ---------------------------------------------------------------------------

  logic       v0, v1, v2, v3, v4;
  logic [2:0] c0, c1, c2, c3, c4;

  assign v0 = s0_fault || wconf_s0;
  assign v1 = s1_fault || wconf_s1;
  assign v2 = s2_fault || wconf_s2;
  assign v3 = s3_fault || wconf_s3;
  assign v4 = s4_fault || wconf_s4;

  assign c0 = s0_fault ? s0_cause : (wconf_s0 ? `CAUSE_WCONF : `CAUSE_NONE);
  assign c1 = s1_fault ? s1_cause : (wconf_s1 ? `CAUSE_WCONF : `CAUSE_NONE);
  assign c2 = s2_fault ? s2_cause : (wconf_s2 ? `CAUSE_WCONF : `CAUSE_NONE);
  assign c3 = s3_fault ? s3_cause : (wconf_s3 ? `CAUSE_WCONF : `CAUSE_NONE);
  assign c4 = s4_fault ? s4_cause : (wconf_s4 ? `CAUSE_WCONF : `CAUSE_NONE);

  // ---------------------------------------------------------------------------
  // Prioridad S0 > S1 > S2 > S3 > S4
  // ---------------------------------------------------------------------------

  logic       hay_falla;
  logic [2:0] causa_ganadora;

  assign hay_falla = v0 || v1 || v2 || v3 || v4;

  assign causa_ganadora = v0 ? c0 :
                          v1 ? c1 :
                          v2 ? c2 :
                          v3 ? c3 :
                          v4 ? c4 : `CAUSE_NONE;

  // ---------------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------------

  logic       z_q, n_q, c_q, v_q;
  logic       exc_q;
  logic [2:0] cause_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      z_q     <= 1'b0;
      n_q     <= 1'b0;
      c_q     <= 1'b0;
      v_q     <= 1'b0;
      exc_q   <= 1'b0;
      cause_q <= `CAUSE_NONE;
    end else begin
      // Banderas: solo cuando ALU-0 lo pide. El orden de flags es {V, C, N, Z}
      if (flags_we) begin
        v_q <= flags[3];
        c_q <= flags[2];
        n_q <= flags[1];
        z_q <= flags[0];
      end

      // EXC y CAUSE: la primera falla manda y despues quedan congelados
      if (hay_falla && !exc_q) begin
        exc_q   <= 1'b1;
        cause_q <= causa_ganadora;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Ensamblado
  // ---------------------------------------------------------------------------

  assign psw = { {(`XLEN-10){1'b0}},   // 31:10 reservados
                 cause_q,              //  9:7
                 exc_q,                //    6
                 authfail,             //    5
                 auth,                 //    4
                 v_q,                  //    3
                 c_q,                  //    2
                 n_q,                  //    1
                 z_q };                //    0

endmodule
