#ifndef DESENROLLADO_H
#define DESENROLLADO_H

#include "tac.h"

/*
 * Expande lazos reconocidos por las aristas de retorno del CFG. 'factor' es
 * cero para la heuristica, o el factor solicitado por --unroll=N.
 * Devuelve el numero de lazos transformados.
 */
int unroll_aplicar(TACList *tac, int factor);

#endif
