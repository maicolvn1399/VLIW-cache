#ifndef MUERTO_H
#define MUERTO_H

/*
 * DCE y propagacion local -- T2 del plan de optimizaciones.
 *
 * Se apoya en el CFG y la vivacidad para quitar cuatro cosas distintas:
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
 *   4. DEFINICIONES SIN RAIZ. Un marcado desde las instrucciones con efectos
 *      elimina calculos que solo se alimentan entre si, incluso si forman un
 *      ciclo de dependencias entre iteraciones de un lazo.
 *
 * El DCE se repite hasta el PUNTO FIJO, porque cada pasada habilita a las
 * otras: borrar 'x = a + b' puede dejar muerta la definicion de 'a', y borrar
 * un bloque puede dejar sin usos a una variable que solo se leia ahi. Entre
 * ronda y ronda el grafo se reconstruye, de modo que la vivacidad siempre se
 * calcula sobre el programa que de verdad quedo. La propagacion y el plegado
 * se limitan a bloques basicos para no cruzar uniones ni efectos de memoria.
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
    int definiciones_sin_raiz;
    int constantes_plegadas;
    int valores_propagados;
    int reducciones_fuerza;
    int bucles_desplegados;     /* lazos realmente transformados antes del DCE */
} ReporteMuerto;

/*
 * Optimiza la lista en el sitio. Devuelve 1 si cambio algo.
 * 'avisar' distinto de cero emite la advertencia W010 por cada definicion
 * muerta que venga de una linea del fuente.
 */
int muerto_eliminar(TACList *tac, ReporteMuerto *rep, int avisar, int nivel_opt);

/* Resumen de una linea para el modo verboso y para las metricas. */
void muerto_imprimir(FILE *out, const ReporteMuerto *rep);

#endif /* MUERTO_H */
