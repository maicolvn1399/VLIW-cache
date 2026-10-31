#ifndef SEMANTIC_H
#define SEMANTIC_H

#include <stdbool.h>
#include "ast.h"
#include "symtab.h"

/*
 * Analisis semantico de Nova (Fase 3).
 *
 * Recorre el AST en dos pasadas. La primera recolecta las firmas globales
 * (modulos importados, constantes y funciones) para que el orden de
 * declaracion no importe entre funciones. La segunda verifica los cuerpos:
 * ambitos, tipos, dimensiones de arreglos, flujo de control y las reglas de
 * las intrinsecas.
 *
 * Devuelve true si no se reporto ningun error. La tabla de simbolos queda
 * en *out_symtab (con el listado completo para --sym) y el llamador es el
 * responsable de liberarla con symtab_destroy().
 */
bool semantic_analyze(Nodo *root, SymbolTable **out_symtab);

#endif /* SEMANTIC_H */
