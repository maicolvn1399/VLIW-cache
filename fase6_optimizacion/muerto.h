#ifndef MUERTO_H
#define MUERTO_H

/*
 * Eliminacion de codigo muerto -- Iteracion 3.
 *
 * Se apoya en las dos piezas anteriores y quita tres cosas distintas:
 *
 *   1. BLOQUES INALCANZABLES. Si no hay camino desde la entrada de la funcion
 *      hasta un bloque, ninguna ejecucion pasa por ahi. Lo dice directamente la
 *      marca de alcanzabilidad del grafo (recorrido en profundidad desde B0).
 *
 *   2. DEFINICIONES MUERTAS. Una instruccion que calcula un valor en un nombre
 *      que ya no esta vivo justo despues de ella no sirve para nada. Lo dice el
 *      analisis de vivacidad, recorrido hacia atras dentro de cada bloque.
 *
 *   3. RESULTADOS DE LLAMADA SIN USAR. La llamada se queda -- tiene efectos --
 *      pero si nadie lee lo que devuelve se borra el destino, y con eso el
 *      almacenamiento del valor de retorno.
 *
 * Las tres se repiten hasta el PUNTO FIJO, porque cada una habilita a las
 * otras: borrar 'x = a + b' puede dejar muerta la definicion de 'a', y borrar
 * un bloque puede dejar sin usos a una variable que solo se leia ahi. Entre
 * ronda y ronda el grafo se reconstruye, de modo que la vivacidad siempre se
 * calcula sobre el programa que de verdad quedo.
 *
 * Lo que NO se toca, y por que:
 *
 *   - Las escrituras a memoria (TAC_STORE). Para borrar una habria que probar
 *     que el arreglo entero esta muerto y que nadie tiene su direccion; es
 *     analisis de alias, y esta fuera de esta iteracion.
 *   - Las divisiones (TAC_DIV, TAC_MOD), porque abortan con codigo 136 si el
 *     divisor es cero.
 *   - Las verificaciones de rango (TAC_CHECK), por la misma razon.
 *   - Los nombres que escapan por & y los globales.
 *   - Los bloques vacios que solo llevan etiqueta: son destino de saltos. El
 *     enhebrado de saltos es otra optimizacion.
 */

#include "bloques.h"
#include "tac.h"

/* Que se quito, para el reporte de metricas. */
typedef struct {
    int rondas;                 /* pasadas hasta el punto fijo */
    int inst_antes;
    int inst_despues;
    int bloques_eliminados;
    int inst_de_bloques;        /* instrucciones dentro de esos bloques */
    int definiciones_muertas;
    int resultados_descartados; /* destinos de llamada sin usar */
} ReporteMuerto;

/*
 * Optimiza la lista en el sitio. Devuelve 1 si cambio algo.
 * 'avisar' distinto de cero emite la advertencia W010 por cada definicion
 * muerta que venga de una linea del fuente.
 */
int muerto_eliminar(TACList *tac, ReporteMuerto *rep, int avisar);

/* Resumen de una linea para el modo verboso y para las metricas. */
void muerto_imprimir(FILE *out, const ReporteMuerto *rep);

#endif /* MUERTO_H */
