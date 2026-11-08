/*
 * Eliminacion de codigo muerto sobre el codigo de tres direcciones.
 *
 * El procedimiento de cada ronda es siempre el mismo:
 *
 *      construir el grafo  ->  calcular vivacidad  ->  marcar  ->  barrer
 *
 * y la ronda se repite mientras algo haya cambiado. Reconstruir el grafo en
 * cada vuelta cuesta un poco mas, pero garantiza que la vivacidad se calcula
 * siempre sobre el programa que quedo y no sobre el anterior; con programas de
 * este tamano la diferencia no se nota y la alternativa -- actualizar el grafo
 * a mano tras cada borrado -- es justo donde se cuelan los errores.
 *
 * Marcar y barrer van separados a proposito: mientras se decide que sobra, el
 * grafo apunta a instrucciones de la lista, asi que no se puede desenlazar
 * nada. Primero se anotan las condenadas, despues se recorre la lista una sola
 * vez y se sacan.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "diag.h"
#include "muerto.h"
#include "vivacidad.h"

static void *reservar(size_t n) {
    void *p = calloc(1, n);
    if (p == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    return p;
}

static int contar_instrucciones(const TACList *tac) {
    int n = 0;
    const TACInst *i;
    for (i = tac->head; i != NULL; i = i->next) n++;
    return n;
}

/* ------------------------------------------------------------ el marcado */

/*
 * Decide, para una funcion, que instrucciones sobran.
 *
 * 'condenadas' se llena con los punteros a eliminar, en el orden en que estan
 * en la lista (los bloques estan numerados en ese mismo orden, asi que basta
 * recorrerlos de 0 a n).
 */
static void marcar_funcion(const VivacidadFuncion *vf, TACInst ***condenadas,
                           int *n_cond, int *cap_cond, ReporteMuerto *rep,
                           int avisar) {
    const GrafoFuncion *fn = vf->fn;
    int k;

    for (k = 0; k < fn->n_bloques; k++) {
        const Bloque *b = &fn->bloques[k];
        TACInst **orden;
        unsigned char *fuera;
        int cuenta = 0, p, sueltos = 0;
        TACInst *i;

        /* Las instrucciones del bloque, en orden. */
        for (i = b->primera; i != NULL; i = i->next) {
            cuenta++;
            if (i == b->ultima) break;
        }
        if (cuenta == 0) continue;

        orden = reservar((size_t)cuenta * sizeof(TACInst *));
        fuera = reservar((size_t)cuenta);
        cuenta = 0;
        for (i = b->primera; i != NULL; i = i->next) {
            orden[cuenta++] = i;
            if (i == b->ultima) break;
        }

        /* Quien decide que sobra es el analisis de vivacidad, no este modulo. */
        if (viv_muertas_en_bloque(vf, k, fuera, cuenta, &sueltos) < 0) {
            free(fuera);
            free(orden);
            continue;
        }

        (void)sueltos;
        if (!b->alcanzable) {
            rep->bloques_eliminados++;
            rep->inst_de_bloques += cuenta;
        } else {
            for (p = 0; p < cuenta; p++) {
                if (fuera[p] == VIV_SOBRA) {
                    rep->definiciones_muertas++;
                } else if (fuera[p] == VIV_SIN_USO &&
                           orden[p]->result != NULL) {
                    /*
                     * La llamada se queda -- puede imprimir, escribir memoria
                     * o tocar la boveda -- pero si nadie lee lo que devuelve
                     * se borra el destino, y la fase 4 se ahorra guardar el
                     * valor de retorno.
                     */
                    free(orden[p]->result);
                    orden[p]->result = NULL;
                    rep->resultados_descartados++;
                }
            }
        }

        /*
         * Las condenadas se recorren hacia adelante para dos cosas: pasarlas a
         * la lista en el orden en que estan (lo necesita el barrido) y avisar
         * en el orden en que se leen.
         *
         * Solo se avisa de los nombres que el programador escribio. Las
         * temporales que caen con ellos son consecuencia del propio TAC -- un
         * 'varia x = a*b' muerto arrastra dos o tres -- y listarlas llenaria la
         * salida de nombres que no estan en el fuente. Tampoco se avisa de los
         * bloques inalcanzables, que ya los reporta W003 en la fase 3.
         */
        for (p = 0; p < cuenta; p++) {
            if (fuera[p] != VIV_SOBRA) continue;

            if (avisar && b->alcanzable && orden[p]->linea > 0) {
                TACEfecto e;
                viv_efecto(orden[p], &e);
                if (e.def != NULL && !tac_es_temporal(e.def))
                    diag_advertencia("W010", orden[p]->linea,
                                     orden[p]->columna, (int)strlen(e.def),
                                     "a '%s' se le asigna un valor que nunca se "
                                     "lee: la asignacion se elimina", e.def);
            }

            if (*n_cond == *cap_cond) {
                *cap_cond = *cap_cond ? *cap_cond * 2 : 64;
                *condenadas = realloc(*condenadas,
                                      (size_t)*cap_cond * sizeof(TACInst *));
                if (*condenadas == NULL) {
                    fprintf(stderr, "novac: sin memoria\n");
                    exit(3);
                }
            }
            (*condenadas)[(*n_cond)++] = orden[p];
        }

        free(fuera);
        free(orden);
    }
}

/* ------------------------------------------------------------- el barrido */

/*
 * Saca de la lista las instrucciones condenadas. Las dos listas estan en el
 * mismo orden, asi que un solo recorrido con un indice que avanza basta.
 */
static void barrer(TACList *tac, TACInst **condenadas, int n_cond) {
    TACInst *anterior = NULL, *i = tac->head;
    int c = 0;

    while (i != NULL) {
        TACInst *sig = i->next;

        if (c < n_cond && condenadas[c] == i) {
            c++;
            if (anterior == NULL) tac->head = sig;
            else anterior->next = sig;
            if (tac->tail == i) tac->tail = anterior;
            free(i->result);
            free(i->arg1);
            free(i->arg2);
            free(i);
        } else {
            anterior = i;
        }
        i = sig;
    }
}

/* ------------------------------------------------------------- interfaz */

int muerto_eliminar(TACList *tac, ReporteMuerto *rep, int avisar) {
    int cambio_total = 0;

    if (rep != NULL) memset(rep, 0, sizeof(*rep));
    if (tac == NULL || tac->head == NULL) return 0;
    if (rep != NULL) rep->inst_antes = contar_instrucciones(tac);

    for (;;) {
        GrafoFlujo *g;
        Vivacidad *v;
        TACInst **condenadas = NULL;
        int n_cond = 0, cap_cond = 0, f;
        ReporteMuerto ronda;

        memset(&ronda, 0, sizeof(ronda));

        g = cfg_construir(tac);
        if (g == NULL) break;
        v = viv_analizar(g, tac);

        for (f = 0; f < v->n_funciones; f++)
            marcar_funcion(&v->funciones[f], &condenadas, &n_cond, &cap_cond,
                           &ronda, avisar);

        if (n_cond > 0) barrer(tac, condenadas, n_cond);

        free(condenadas);
        viv_liberar(v);
        cfg_liberar(g);

        if (rep != NULL) {
            rep->rondas++;
            rep->bloques_eliminados     += ronda.bloques_eliminados;
            rep->inst_de_bloques        += ronda.inst_de_bloques;
            rep->definiciones_muertas   += ronda.definiciones_muertas;
            rep->resultados_descartados += ronda.resultados_descartados;
        }

        if (n_cond == 0 && ronda.resultados_descartados == 0) break;
        cambio_total = 1;

        /*
         * Las advertencias solo tienen sentido la primera vez: en las rondas
         * siguientes lo que se elimina ya es consecuencia de lo eliminado
         * antes, no algo que el programador escribiera de mas.
         */
        avisar = 0;

        if (rep != NULL && rep->rondas > 50) break;   /* red de seguridad */
    }

    if (rep != NULL) rep->inst_despues = contar_instrucciones(tac);
    return cambio_total;
}

void muerto_imprimir(FILE *out, const ReporteMuerto *rep) {
    int quitadas;
    if (out == NULL || rep == NULL) return;

    quitadas = rep->inst_antes - rep->inst_despues;
    fprintf(out, "=== Eliminacion de codigo muerto ===\n");
    fprintf(out, "  instrucciones de tres direcciones: %d -> %d",
            rep->inst_antes, rep->inst_despues);
    if (rep->inst_antes > 0)
        fprintf(out, "  (%d menos, %.1f%%)", quitadas,
                100.0 * quitadas / rep->inst_antes);
    fprintf(out, "\n");
    fprintf(out, "  bloques inalcanzables eliminados:  %d  (%d instrucciones)\n",
            rep->bloques_eliminados, rep->inst_de_bloques);
    fprintf(out, "  definiciones muertas eliminadas:   %d\n",
            rep->definiciones_muertas);
    fprintf(out, "  resultados de llamada descartados: %d\n",
            rep->resultados_descartados);
    fprintf(out, "  rondas hasta el punto fijo:        %d\n", rep->rondas);
}
