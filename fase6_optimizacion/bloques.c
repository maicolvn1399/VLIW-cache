/*
 * Construccion de bloques basicos y del grafo de flujo de control.
 *
 * El algoritmo es el clasico de dos pasadas:
 *
 *   1. Marcar los LIDERES. Una instruccion es lider si
 *        a) es la primera de la funcion,
 *        b) lleva una etiqueta (puede ser destino de un salto), o
 *        c) sigue inmediatamente a un salto, a un retorno o a un halt.
 *
 *   2. Cada lider abre un bloque que se extiende hasta la instruccion anterior
 *      al siguiente lider.
 *
 * Despues se tienden las aristas segun como termine cada bloque, y se marca la
 * alcanzabilidad desde el bloque de entrada.
 *
 * Dos decisiones que conviene dejar dichas, porque no son las unicas posibles:
 *
 * TAC_CALL no parte el bloque. El grafo es INTRAprocedural: una llamada
 * devuelve el control a la instruccion siguiente, asi que desde el punto de
 * vista del flujo dentro de la funcion es una instruccion mas. Partir el
 * bloque en cada llamada daria un grafo mas fragmentado sin informacion
 * adicional, y reduciria el tamano de los bloques justo donde la
 * calendarizacion en bundles necesita margen. Lo que si hay que respetar al
 * reordenar es que una llamada tiene efectos; eso es una dependencia, no una
 * arista del grafo.
 *
 * Toda etiqueta abre bloque, aunque nadie salte a ella. Comprobar primero si
 * esta referenciada ahorraria algun bloque, pero el grafo quedaria dependiendo
 * del orden en que se recorre la lista, y un bloque de mas no cuesta nada: el
 * que quede sin predecesores se reporta como inalcanzable, que es informacion
 * util y no un defecto.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bloques.h"

static void *reservar(size_t n) {
    void *p = calloc(1, n);
    if (p == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    return p;
}

static char *dup_o_nulo(const char *s) {
    char *c;
    if (s == NULL) return NULL;
    c = malloc(strlen(s) + 1);
    if (c == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    strcpy(c, s);
    return c;
}

const char *cfg_fin_nombre(FinBloque f) {
    switch (f) {
        case FIN_CAIDA:       return "caida";
        case FIN_SALTO:       return "salto";
        case FIN_CONDICIONAL: return "condicional";
        case FIN_RETORNO:     return "retorno";
        case FIN_TAILCALL:    return "tailcall";
        case FIN_HALT:        return "halt";
    }
    return "?";
}

/* 1 si la instruccion transfiere el control y por tanto cierra un bloque. */
static int transfiere_control(TACOp op) {
    switch (op) {
        case TAC_GOTO: case TAC_IF_FALSE: case TAC_IF_TRUE:
        case TAC_RET:  case TAC_RET_VAL:  case TAC_TAILCALL:
        case TAC_HALT:
            return 1;
        default:
            return 0;
    }
}

static FinBloque clasificar_fin(TACInst *ultima) {
    if (ultima == NULL) return FIN_CAIDA;
    switch (ultima->op) {
        case TAC_GOTO:      return FIN_SALTO;
        case TAC_IF_FALSE:
        case TAC_IF_TRUE:   return FIN_CONDICIONAL;
        case TAC_RET:
        case TAC_RET_VAL:   return FIN_RETORNO;
        case TAC_TAILCALL:  return FIN_TAILCALL;
        case TAC_HALT:      return FIN_HALT;
        default:            return FIN_CAIDA;
    }
}

static void agregar_arista(Bloque *b, int destino) {
    int i;
    for (i = 0; i < b->n_suc; i++)
        if (b->sucesores[i] == destino) return;     /* ya existe */
    b->sucesores = realloc(b->sucesores, (size_t)(b->n_suc + 1) * sizeof(int));
    if (b->sucesores == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    b->sucesores[b->n_suc++] = destino;
}

static void agregar_predecesor(Bloque *b, int origen) {
    int i;
    for (i = 0; i < b->n_pred; i++)
        if (b->predecesores[i] == origen) return;
    b->predecesores = realloc(b->predecesores, (size_t)(b->n_pred + 1) * sizeof(int));
    if (b->predecesores == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    b->predecesores[b->n_pred++] = origen;
}

/* Indice del bloque que empieza con esa etiqueta, o -1. */
static int bloque_de_etiqueta(const GrafoFuncion *f, const char *etq) {
    int i;
    if (etq == NULL) return -1;
    for (i = 0; i < f->n_bloques; i++)
        if (f->bloques[i].etiqueta != NULL &&
            strcmp(f->bloques[i].etiqueta, etq) == 0)
            return i;
    return -1;
}

/* ------------------------------------------------ una funcion a la vez */

/*
 * Recorre el cuerpo de una funcion y arma sus bloques. 'cuerpo' apunta a la
 * instruccion siguiente al TAC_FUNC_BEGIN; el recorrido termina en el
 * TAC_FUNC_END correspondiente.
 */
static void construir_funcion(GrafoFuncion *f, TACInst *cuerpo) {
    TACInst *i;
    int n = 0, k;

    /* --- Pasada 1: contar lideres --- */
    int primero = 1;
    int siguiente_es_lider = 0;
    for (i = cuerpo; i != NULL && i->op != TAC_FUNC_END; i = i->next) {
        int lider = primero || siguiente_es_lider || i->op == TAC_LABEL;
        if (lider) n++;
        primero = 0;
        siguiente_es_lider = transfiere_control(i->op);
    }

    if (n == 0) { f->n_bloques = 0; f->bloques = NULL; return; }

    f->bloques = reservar((size_t)n * sizeof(Bloque));
    f->n_bloques = n;

    /* --- Pasada 2: delimitar cada bloque --- */
    primero = 1;
    siguiente_es_lider = 0;
    k = -1;
    for (i = cuerpo; i != NULL && i->op != TAC_FUNC_END; i = i->next) {
        int lider = primero || siguiente_es_lider || i->op == TAC_LABEL;
        if (lider) {
            k++;
            f->bloques[k].id = k;
            f->bloques[k].primera = i;
            f->bloques[k].n_inst = 0;
            f->bloques[k].etiqueta =
                (i->op == TAC_LABEL) ? dup_o_nulo(i->result) : NULL;
        }
        f->bloques[k].ultima = i;
        f->bloques[k].n_inst++;
        primero = 0;
        siguiente_es_lider = transfiere_control(i->op);
    }

    for (k = 0; k < f->n_bloques; k++)
        f->bloques[k].fin = clasificar_fin(f->bloques[k].ultima);

    /* --- Aristas --- */
    for (k = 0; k < f->n_bloques; k++) {
        Bloque *b = &f->bloques[k];
        TACInst *u = b->ultima;

        switch (b->fin) {
            case FIN_SALTO: {
                int d = bloque_de_etiqueta(f, u->result);
                if (d >= 0) agregar_arista(b, d);
                break;
            }
            case FIN_CONDICIONAL: {
                /* Dos salidas: el destino del salto y la caida. */
                int d = bloque_de_etiqueta(f, u->result);
                if (d >= 0) agregar_arista(b, d);
                if (k + 1 < f->n_bloques) agregar_arista(b, k + 1);
                break;
            }
            case FIN_TAILCALL:
                /* @cauda reasigna los parametros y vuelve al inicio del
                 * cuerpo: es una arista de regreso al primer bloque. */
                agregar_arista(b, 0);
                break;
            case FIN_RETORNO:
            case FIN_HALT:
                /* Sin sucesores: es una salida de la funcion. */
                break;
            case FIN_CAIDA:
                if (k + 1 < f->n_bloques) agregar_arista(b, k + 1);
                break;
        }
    }

    /* Predecesores, derivados de los sucesores. */
    for (k = 0; k < f->n_bloques; k++) {
        int s;
        for (s = 0; s < f->bloques[k].n_suc; s++)
            agregar_predecesor(&f->bloques[f->bloques[k].sucesores[s]], k);
    }

    for (k = 0; k < f->n_bloques; k++) f->n_aristas += f->bloques[k].n_suc;

    /* --- Alcanzabilidad: recorrido en profundidad desde el bloque 0 --- */
    {
        int *pila = reservar((size_t)f->n_bloques * sizeof(int));
        int tope = 0;
        pila[tope++] = 0;
        f->bloques[0].alcanzable = 1;
        while (tope > 0) {
            int b = pila[--tope], s;
            for (s = 0; s < f->bloques[b].n_suc; s++) {
                int d = f->bloques[b].sucesores[s];
                if (!f->bloques[d].alcanzable) {
                    f->bloques[d].alcanzable = 1;
                    pila[tope++] = d;
                }
            }
        }
        free(pila);
    }
    for (k = 0; k < f->n_bloques; k++)
        if (!f->bloques[k].alcanzable) f->n_inalcanzables++;

    /*
     * Profundidad de ciclo.
     *
     * Una arista de un bloque hacia otro de indice menor o igual es una arista
     * de REGRESO: el flujo vuelve atras, de modo que lo que queda entre el
     * destino y el origen es el cuerpo de un lazo. Marcar esos bloques alcanza
     * para lo que necesitan las iteraciones siguientes: saber que codigo esta
     * dentro de un lazo, que es donde el desenrollado y la calendarizacion
     * rinden. Un analisis de dominadores daria los lazos naturales con mas
     * precision, pero aqui el codigo lo genera el propio compilador y los
     * lazos salen siempre bien anidados.
     */
    for (k = 0; k < f->n_bloques; k++) {
        int s;
        for (s = 0; s < f->bloques[k].n_suc; s++) {
            int d = f->bloques[k].sucesores[s], j;
            if (d > k) continue;                   /* no es arista de regreso */
            for (j = d; j <= k; j++) f->bloques[j].profundidad_ciclo++;
        }
    }
}

/* ------------------------------------------------------------ interfaz */

GrafoFlujo *cfg_construir(TACList *tac) {
    GrafoFlujo *g;
    TACInst *i;
    int n = 0, k = 0;

    if (tac == NULL || tac->head == NULL) return NULL;

    for (i = tac->head; i != NULL; i = i->next)
        if (i->op == TAC_FUNC_BEGIN) n++;
    if (n == 0) return NULL;

    g = reservar(sizeof(GrafoFlujo));
    g->funciones = reservar((size_t)n * sizeof(GrafoFuncion));
    g->n_funciones = n;

    for (i = tac->head; i != NULL; i = i->next) {
        if (i->op != TAC_FUNC_BEGIN) continue;
        g->funciones[k].nombre = dup_o_nulo(i->result);
        g->funciones[k].inicio = i;
        construir_funcion(&g->funciones[k], i->next);
        k++;
    }
    return g;
}

void cfg_liberar(GrafoFlujo *g) {
    int f, k;
    if (g == NULL) return;
    for (f = 0; f < g->n_funciones; f++) {
        for (k = 0; k < g->funciones[f].n_bloques; k++) {
            free(g->funciones[f].bloques[k].etiqueta);
            free(g->funciones[f].bloques[k].sucesores);
            free(g->funciones[f].bloques[k].predecesores);
        }
        free(g->funciones[f].bloques);
        free(g->funciones[f].nombre);
    }
    free(g->funciones);
    free(g);
}

/* ------------------------------------------------------------- listado */

static void imprimir_lista(FILE *out, const char *etq, const int *v, int n) {
    int i;
    fprintf(out, "%s", etq);
    if (n == 0) { fprintf(out, "-"); return; }
    for (i = 0; i < n; i++) fprintf(out, "%sB%d", i ? ", " : "", v[i]);
}

void cfg_imprimir(FILE *out, const GrafoFlujo *g) {
    int f, k;

    fprintf(out, "=== Bloques basicos y grafo de flujo de control ===\n");
    if (g == NULL) {
        fprintf(out, "(sin codigo intermedio)\n");
        return;
    }

    for (f = 0; f < g->n_funciones; f++) {
        const GrafoFuncion *fn = &g->funciones[f];

        fprintf(out, "\nfunctio %s: %d bloque%s, %d arista%s",
                fn->nombre, fn->n_bloques, fn->n_bloques == 1 ? "" : "s",
                fn->n_aristas, fn->n_aristas == 1 ? "" : "s");
        if (fn->n_inalcanzables > 0)
            fprintf(out, ", %d inalcanzable%s", fn->n_inalcanzables,
                    fn->n_inalcanzables == 1 ? "" : "s");
        fprintf(out, "\n");

        for (k = 0; k < fn->n_bloques; k++) {
            const Bloque *b = &fn->bloques[k];
            TACInst *i;

            fprintf(out, "\n  B%d", b->id);
            if (b->etiqueta != NULL) fprintf(out, " (%s)", b->etiqueta);
            if (k == 0) fprintf(out, " [entrada]");
            if (!b->alcanzable) fprintf(out, " [INALCANZABLE]");
            if (b->profundidad_ciclo > 0)
                fprintf(out, " [en lazo, nivel %d]", b->profundidad_ciclo);
            fprintf(out, "\n      ");
            imprimir_lista(out, "predecesores: ", b->predecesores, b->n_pred);
            fprintf(out, "\n      ");
            imprimir_lista(out, "sucesores:    ", b->sucesores, b->n_suc);
            fprintf(out, "   (termina en %s)\n", cfg_fin_nombre(b->fin));

            for (i = b->primera; i != NULL; i = i->next) {
                /* El mismo formateador que usa --ir: una sola rendicion de
                 * cada instruccion para todas las vistas. */
                fprintf(out, "    ");
                tac_print_inst(out, i);
                if (i == b->ultima) break;
            }
        }
    }

    {
        int tb = 0, ta = 0, ti = 0;
        for (f = 0; f < g->n_funciones; f++) {
            tb += g->funciones[f].n_bloques;
            ta += g->funciones[f].n_aristas;
            ti += g->funciones[f].n_inalcanzables;
        }
        fprintf(out, "\n%d funcion%s, %d bloques, %d aristas",
                g->n_funciones, g->n_funciones == 1 ? "" : "es", tb, ta);
        if (ti > 0) fprintf(out, ", %d bloques inalcanzables", ti);
        fprintf(out, ".\n");
    }
}
