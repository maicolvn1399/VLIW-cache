#ifndef BLOQUES_H
#define BLOQUES_H

/*
 * Bloques basicos y grafo de flujo de control (Iteracion 2).
 *
 * Un bloque basico es una secuencia maxima de instrucciones de tres
 * direcciones donde el flujo entra por la primera y sale por la ultima: no hay
 * saltos hacia adentro salvo al inicio, ni saltos hacia afuera salvo al final.
 * Esa propiedad es lo que permite razonar sobre el programa por partes, y es
 * la base de todo lo que viene despues:
 *
 *   - La eliminacion de codigo muerto necesita saber que bloques son
 *     inalcanzables, y dentro de cada bloque, que definiciones no llegan a
 *     usarse (analisis de liveness sobre el grafo).
 *   - El reordenamiento de instrucciones solo es seguro DENTRO de un bloque,
 *     porque ahi no hay saltos que cambien el orden de ejecucion.
 *   - El desenrollado de lazos necesita reconocer los ciclos del grafo.
 *   - La calendarizacion en bundles VLIW reordena dentro del bloque.
 *
 * El grafo se construye por funcion: cada funcion tiene su propio conjunto de
 * bloques numerados desde 0, y las llamadas no cruzan el grafo (ver la nota
 * sobre TAC_CALL en bloques.c).
 */

#include <stdio.h>
#include "tac.h"

/* Como termina un bloque. Determina sus aristas de salida. */
typedef enum {
    FIN_CAIDA,        /* cae en el bloque siguiente                 */
    FIN_SALTO,        /* goto incondicional                         */
    FIN_CONDICIONAL,  /* ifFalse/ifTrue: dos salidas                */
    FIN_RETORNO,      /* ret / ret valor: sale de la funcion        */
    FIN_TAILCALL,     /* @cauda: vuelve al inicio de la funcion     */
    FIN_HALT          /* halt: termina el programa                  */
} FinBloque;

typedef struct {
    int id;                  /* indice del bloque dentro de su funcion */
    TACInst *primera;        /* instruccion lider */
    TACInst *ultima;
    int n_inst;

    char *etiqueta;          /* etiqueta que lo encabeza, o NULL */
    FinBloque fin;

    int *sucesores;
    int n_suc;
    int *predecesores;
    int n_pred;

    int alcanzable;          /* 1 si hay un camino desde la entrada */
    int profundidad_ciclo;   /* 0 fuera de lazos; 1 o mas dentro */
} Bloque;

typedef struct {
    char *nombre;            /* nombre de la funcion */
    Bloque *bloques;
    int n_bloques;
    int n_aristas;
    int n_inalcanzables;
    TACInst *inicio;         /* TAC_FUNC_BEGIN */
} GrafoFuncion;

typedef struct {
    GrafoFuncion *funciones;
    int n_funciones;
} GrafoFlujo;

/*
 * Construye el grafo de flujo de toda la lista de tres direcciones.
 * Devuelve NULL si la lista esta vacia. El llamador libera con cfg_liberar().
 */
GrafoFlujo *cfg_construir(TACList *tac);

void cfg_liberar(GrafoFlujo *g);

/* Listado legible del grafo: bloques, instrucciones y aristas (--bloques). */
void cfg_imprimir(FILE *out, const GrafoFlujo *g);

/* Nombre corto del tipo de salida de un bloque, para los reportes. */
const char *cfg_fin_nombre(FinBloque f);

#endif /* BLOQUES_H */
