#ifndef CODEGEN_H
#define CODEGEN_H

/*
 * Generacion de ensamblador VLIW para CERBERO (Fase 4b).
 *
 * Traduce la lista de tres direcciones a bundles de cinco slots:
 *
 *   <S0: ALU-0> | <S1: ALU-1> | <S2: LSU> | <S3: CRP> | <S4: BRU> ;
 *
 * Respeta las dos reglas temporales del ISA: tres bundles entre quien
 * produce un valor y quien lo consume, y un bundle de delay slot despues de
 * cada salto, que se ejecuta siempre.
 *
 * Esta version emite una instruccion por bundle y no planifica. Empaquetar
 * varias operaciones en un mismo bundle es optimizacion de codigo, que la
 * seccion 9.1 de la guia del proyecto excluye de esta primera version, y no
 * cambia la correccion de lo que sale de aqui.
 *
 * Ojo con la numeracion: la fase 5 de la guia es el calculo de saltos y la
 * resolucion de referencias, que si esta hecha, en construir_programa() y
 * resolver_direcciones() de codegen.c. La fase 6 es la emision binaria.
 */

#include <stdio.h>
#include "tac.h"
#include "symtab.h"

/* Emite el ensamblador completo: cabecera, .data con los literales y el area
 * de salida, .text con las funciones y el soporte de ejecucion que haga
 * falta. Devuelve false si encontro algo que no puede traducir. */
bool codegen_generate_vliw(TACList *tac, SymbolTable *st, FILE *out);

/* Actualiza la tabla con el desplazamiento que usa el ensamblador despues
 * de reservar el marco y la direccion IMEM de cada funcion, usando el
 * programa ya relajado del generador. */
bool codegen_update_symbol_layout(TACList *tac, SymbolTable *st);

/* Muestra cada bundle con su dirección, slots de ensamblador y bytes emitidos. */
bool codegen_print_packages(TACList *tac, SymbolTable *st, FILE *out);

/* Emite el ejecutable binario: encabezado de 32 bytes, los bundles de 128
 * bits y la seccion de datos. Se construye desde la misma lista de bundles
 * que el ensamblador de texto, asi que las dos salidas no pueden divergir. */
bool codegen_emitir_binario(TACList *tac, SymbolTable *st, FILE *out);

#endif /* CODEGEN_H */
