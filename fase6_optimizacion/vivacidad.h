#ifndef VIVACIDAD_H
#define VIVACIDAD_H

/*
 * Analisis de vivacidad (liveness) sobre el grafo de flujo -- Iteracion 3.
 *
 * Una variable esta VIVA en un punto del programa si el valor que tiene en ese
 * punto puede llegar a leerse antes de que alguien lo sobrescriba. Si no esta
 * viva, el valor es basura y la instruccion que lo calculo sobra.
 *
 * Es un analisis HACIA ATRAS: lo que decide si un valor sirve no es lo que pasa
 * antes de calcularlo sino lo que pasa despues. Por eso la informacion viaja
 * desde los usos hacia las definiciones, en contra de las aristas del grafo.
 *
 * Por cada bloque basico se calculan cuatro conjuntos de nombres:
 *
 *   USO[B]   nombres que B lee ANTES de escribirlos (usos expuestos hacia
 *            arriba: su valor tiene que venir de afuera del bloque).
 *   DEF[B]   nombres que B escribe antes de leerlos (los mata: lo que valieran
 *            al entrar ya no importa).
 *   VIVO_SAL[B] = union de VIVO_ENT[S] para cada sucesor S de B.
 *   VIVO_ENT[B] = USO[B] union (VIVO_SAL[B] menos DEF[B]).
 *
 * Las dos ultimas son mutuamente recursivas, asi que se resuelven iterando: se
 * parte de todos los conjuntos vacios y se recorre el grafo una y otra vez
 * hasta que ninguna pasada cambia nada. Ese PUNTO FIJO existe y se alcanza
 * porque los conjuntos solo crecen y el universo de nombres es finito; el
 * recorrido en orden inverso hace que converja en pocas pasadas (el campo
 * 'iteraciones' reporta cuantas hicieron falta de verdad).
 *
 * Condicion de frontera: a la salida de un bloque que retorna o que termina el
 * programa no queda vivo ningun local ni ningun temporal, porque el marco de la
 * funcion deja de existir. Lo unico que sobrevive son los nombres que escapan
 * (ver 'escapa' mas abajo).
 *
 * Que se considera lectura y que escritura esta en viv_efecto(), que es la
 * unica tabla que conoce la semantica de cada operacion del TAC. La comparten
 * este analisis y la eliminacion de codigo muerto, para que las dos vean
 * exactamente el mismo programa.
 */

#include <stdio.h>
#include "bloques.h"
#include "tac.h"

/*
 * Lo que una instruccion lee, lo que escribe, y si se puede borrar.
 *
 * 'efecto' marca las instrucciones que NO se pueden eliminar aunque su destino
 * este muerto, porque hacen algo mas que calcular un valor: escriben memoria,
 * llaman, saltan, abortan o tocan la boveda.
 */
typedef struct {
    const char *def;        /* nombre que escribe, o NULL */
    const char *usos[3];    /* nombres que lee */
    int n_usos;
    int efecto;             /* 1 si no es seguro borrarla */
    int toma_direccion;     /* 1 si es un &x: usos[0] escapa */
} TACEfecto;

void viv_efecto(const TACInst *i, TACEfecto *e);

/* Resultado del analisis para una funcion. */
typedef struct {
    const GrafoFuncion *fn;

    char **nombres;         /* universo de nombres de la funcion */
    int n_nombres;
    int n_palabras;         /* palabras de 32 bits por conjunto */

    unsigned *uso;          /* [bloque][palabra] */
    unsigned *def;
    unsigned *vivo_ent;
    unsigned *vivo_sal;

    unsigned char *escapa;  /* [nombre]: se tomo su direccion con & */
    unsigned char *global;  /* [nombre]: no es local ni parametro */

    int iteraciones;        /* pasadas hasta el punto fijo */
} VivacidadFuncion;

typedef struct {
    VivacidadFuncion *funciones;
    int n_funciones;
} Vivacidad;

/*
 * Calcula la vivacidad de todo el grafo. 'tac' se usa para distinguir los
 * locales y parametros de cada funcion de los nombres globales.
 * Devuelve NULL si el grafo es NULL. El llamador libera con viv_liberar().
 */
Vivacidad *viv_analizar(const GrafoFlujo *g, const TACList *tac);

void viv_liberar(Vivacidad *v);

/* Listado legible del analisis (--vivacidad). */
void viv_imprimir(FILE *out, const Vivacidad *v);

/* --- Consultas --- */

/* Indice del nombre dentro del universo de la funcion, o -1. */
int viv_indice(const VivacidadFuncion *vf, const char *nombre);

/* 1 si el nombre esta vivo a la salida del bloque b. */
int viv_viva_a_la_salida(const VivacidadFuncion *vf, int b, const char *nombre);

/* 1 si el nombre nunca puede considerarse muerto (escapa o es global). */
int viv_intocable(const VivacidadFuncion *vf, const char *nombre);

/*
 * Recorre el bloque 'b' hacia atras desde VIVO_SAL y marca que instrucciones
 * calculan un valor que no se vuelve a leer.
 *
 * 'fuera' recibe un byte por instruccion, en el orden en que estan:
 *
 *     VIV_VIVA     0   se queda tal cual
 *     VIV_SOBRA    1   la instruccion entera sobra
 *     VIV_SIN_USO  2   es una llamada cuyo resultado no se lee: la llamada se
 *                      queda, el destino se descarta
 *
 * 'sueltos' recibe, si no es NULL, cuantas instrucciones quedaron en
 * VIV_SIN_USO.
 *
 * Devuelve cuantas instrucciones tiene el bloque, o -1 si no caben en 'cap'.
 *
 * Es la unica implementacion de este recorrido: la usan la eliminacion de
 * codigo muerto, el listado de --vivacidad y la vista del IDE, de modo que las
 * tres marcan exactamente lo mismo.
 */
#define VIV_VIVA    0
#define VIV_SOBRA   1
#define VIV_SIN_USO 2

int viv_muertas_en_bloque(const VivacidadFuncion *vf, int b,
                          unsigned char *fuera, int cap, int *sueltos);

#endif /* VIVACIDAD_H */
