/*
 * Analisis de vivacidad sobre el grafo de flujo de control.
 *
 * El algoritmo es el clasico de flujo de datos hacia atras descrito en
 * vivacidad.h. Aqui estan las tres partes que lo hacen correcto para Nova:
 *
 *   1. La tabla de viv_efecto(): que lee y que escribe cada operacion del TAC.
 *      Es la unica pieza que conoce la semantica del repertorio, y la comparten
 *      este analisis y la eliminacion de codigo muerto.
 *
 *   2. El universo de nombres por funcion, que define el tamano de los
 *      conjuntos. Se recoge de las propias instrucciones, de modo que no hace
 *      falta consultar la tabla de simbolos (cuyos ambitos locales ya se
 *      cerraron) para saber sobre que se esta razonando.
 *
 *   3. Las condiciones conservadoras: los nombres que escapan por & y los
 *      globales nunca se dan por muertos. Una respuesta de mas solo cuesta una
 *      instruccion que no se elimina; una de menos cambia el programa.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vivacidad.h"

/* ------------------------------------------------------------ auxiliares */

static void *reservar(size_t n) {
    void *p = calloc(1, n);
    if (p == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    return p;
}

static char *dup_cadena(const char *s) {
    char *c;
    if (s == NULL) return NULL;
    c = malloc(strlen(s) + 1);
    if (c == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    strcpy(c, s);
    return c;
}

/* Conjuntos como mapas de bits de 32 en 32. */
#define PALABRAS(n) (((n) + 31) / 32)

static int bit_puesto(const unsigned *c, int i) {
    return (c[i / 32] >> (i % 32)) & 1u;
}
static void poner_bit(unsigned *c, int i) {
    c[i / 32] |= 1u << (i % 32);
}
static void quitar_bit(unsigned *c, int i) {
    c[i / 32] &= ~(1u << (i % 32));
}

/* ------------------------------------------- semantica de cada operacion */

/*
 * Que nombres lee y escribe cada instruccion de tres direcciones.
 *
 * Tres casos merecen explicacion porque no se leen del nombre del campo:
 *
 *   TAC_STORE es 'result[arg1] = arg2'. El campo 'result' NO es un destino:
 *   es el arreglo del que se lee la direccion base. La instruccion no define
 *   ningun nombre, lee tres, y escribe memoria, asi que lleva efecto.
 *
 *   TAC_DIV y TAC_MOD llevan efecto aunque sean aritmetica pura: la rutina
 *   __nova_div32 termina el programa con el codigo 136 cuando el divisor es
 *   cero, que es lo que promete el lenguaje. Borrar una division muerta
 *   cambiaria un programa que aborta por uno que no, y eso es observable.
 *
 *   TAC_CALL define 'result' pero su 'arg1' es el nombre de la funcion, no una
 *   variable: no se lee ningun valor de ahi. Los argumentos ya viajaron por sus
 *   TAC_PARAM, que si los leen.
 */
void viv_efecto(const TACInst *i, TACEfecto *e) {
    memset(e, 0, sizeof(*e));
    if (i == NULL) return;

    switch (i->op) {
        /* Aritmetica, bits y comparaciones: puras. */
        case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR:  case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR:
        case TAC_EQ:  case TAC_NE:  case TAC_LT:
        case TAC_LE:  case TAC_GT:  case TAC_GE:
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            e->usos[e->n_usos++] = i->arg2;
            break;

        /* Division y modulo: aritmetica, pero pueden abortar. */
        case TAC_DIV: case TAC_MOD:
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            e->usos[e->n_usos++] = i->arg2;
            e->efecto = 1;
            break;

        case TAC_NEG: case TAC_BITNOT: case TAC_NOT:
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            break;

        case TAC_ASSIGN:
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            break;

        case TAC_CONST:
            e->def = i->result;
            break;

        case TAC_STR:
            /* arg1 es la etiqueta del literal, no una variable. */
            e->def = i->result;
            break;

        case TAC_LOAD:          /* result = arg1[arg2] */
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            e->usos[e->n_usos++] = i->arg2;
            break;

        case TAC_STORE:         /* result[arg1] = arg2: escribe memoria */
            e->usos[e->n_usos++] = i->result;
            e->usos[e->n_usos++] = i->arg1;
            e->usos[e->n_usos++] = i->arg2;
            e->efecto = 1;
            break;

        case TAC_ADDR:          /* result = &arg1 */
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            e->toma_direccion = 1;
            break;

        case TAC_LEN:
            e->def = i->result;
            e->usos[e->n_usos++] = i->arg1;
            break;

        case TAC_CHECK:         /* puede abortar por indice fuera de rango */
            e->usos[e->n_usos++] = i->arg1;
            e->usos[e->n_usos++] = i->arg2;
            e->efecto = 1;
            break;

        /* Control de flujo: el campo 'result' es una etiqueta. */
        case TAC_LABEL:
        case TAC_GOTO:
            e->efecto = 1;
            break;

        case TAC_IF_FALSE:
        case TAC_IF_TRUE:
            e->usos[e->n_usos++] = i->arg1;
            e->efecto = 1;
            break;

        case TAC_FUNC_BEGIN:
        case TAC_FUNC_END:
            e->efecto = 1;
            break;

        case TAC_PARAM:
            e->usos[e->n_usos++] = i->arg1;
            e->efecto = 1;
            break;

        case TAC_CALL:          /* arg1 es el nombre de la funcion */
            e->def = i->result;
            e->efecto = 1;
            break;

        case TAC_TAILCALL:
            e->efecto = 1;
            break;

        case TAC_RET:
            e->efecto = 1;
            break;

        case TAC_RET_VAL:
            e->usos[e->n_usos++] = i->arg1;
            e->efecto = 1;
            break;

        case TAC_AUTHW:
            e->usos[e->n_usos++] = i->arg1;
            e->efecto = 1;
            break;

        case TAC_VAULT_LOGIN:
        case TAC_VAULT_LOGOUT:
            e->efecto = 1;
            break;

        case TAC_KSETW:         /* vault.store #ranura, #palabra, arg2 */
            e->usos[e->n_usos++] = i->arg2;
            e->efecto = 1;
            break;

        case TAC_FEISTEL:
        case TAC_FEISTEL_DECRYPT:
            /* Trabaja en memoria sobre la direccion que recibe. */
            e->usos[e->n_usos++] = i->arg1;
            e->efecto = 1;
            break;

        case TAC_HALT:
            e->efecto = 1;
            break;

        case TAC_NOP:
            break;
    }

    /* Compacta los NULL que hayan quedado entre los usos. */
    {
        int k, n = 0;
        const char *v[3];
        for (k = 0; k < e->n_usos; k++)
            if (e->usos[k] != NULL) v[n++] = e->usos[k];
        for (k = 0; k < n; k++) e->usos[k] = v[k];
        for (k = n; k < 3; k++) e->usos[k] = NULL;
        e->n_usos = n;
    }
    if (e->def != NULL && e->def[0] == '\0') e->def = NULL;
}

/* ------------------------------------------------ universo de nombres */

int viv_indice(const VivacidadFuncion *vf, const char *nombre) {
    int i;
    if (vf == NULL || nombre == NULL) return -1;
    for (i = 0; i < vf->n_nombres; i++)
        if (strcmp(vf->nombres[i], nombre) == 0) return i;
    return -1;
}

static int agregar_nombre(VivacidadFuncion *vf, int *cap, const char *nombre) {
    int i;
    if (nombre == NULL || nombre[0] == '\0') return -1;
    i = viv_indice(vf, nombre);
    if (i >= 0) return i;
    if (vf->n_nombres == *cap) {
        *cap = *cap ? *cap * 2 : 16;
        vf->nombres = realloc(vf->nombres, (size_t)*cap * sizeof(char *));
        if (vf->nombres == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    }
    vf->nombres[vf->n_nombres] = dup_cadena(nombre);
    return vf->n_nombres++;
}

/*
 * Recorre la funcion y recoge todos los nombres que aparecen como lectura o
 * como escritura. Marca de paso cuales escapan por & y cuales no son locales.
 */
static void recoger_nombres(VivacidadFuncion *vf, const TACList *tac) {
    const GrafoFuncion *fn = vf->fn;
    int cap = 0, k, j;

    for (k = 0; k < fn->n_bloques; k++) {
        TACInst *i;
        for (i = fn->bloques[k].primera; i != NULL; i = i->next) {
            TACEfecto e;
            viv_efecto(i, &e);
            agregar_nombre(vf, &cap, e.def);
            for (j = 0; j < e.n_usos; j++) agregar_nombre(vf, &cap, e.usos[j]);
            if (i == fn->bloques[k].ultima) break;
        }
    }

    vf->escapa = reservar((size_t)(vf->n_nombres ? vf->n_nombres : 1));
    vf->global = reservar((size_t)(vf->n_nombres ? vf->n_nombres : 1));

    /* Segunda vuelta: ahora que el universo esta completo, marca los & */
    for (k = 0; k < fn->n_bloques; k++) {
        TACInst *i;
        for (i = fn->bloques[k].primera; i != NULL; i = i->next) {
            TACEfecto e;
            viv_efecto(i, &e);
            if (e.toma_direccion && e.n_usos > 0) {
                int idx = viv_indice(vf, e.usos[0]);
                if (idx >= 0) vf->escapa[idx] = 1;
            }
            if (i == fn->bloques[k].ultima) break;
        }
    }

    /*
     * Un nombre es global si no es temporal y la fase 4 no lo registro como
     * local ni parametro de esta funcion. Los globales de Nova son 'constans',
     * de solo lectura, pero se marcan igual para no darlos nunca por muertos.
     */
    for (k = 0; k < vf->n_nombres; k++) {
        const char *n = vf->nombres[k];
        if (tac_es_temporal(n)) continue;
        if (tac != NULL && tac_buscar_simbolo(tac, fn->nombre, n) != NULL) continue;
        vf->global[k] = 1;
    }
}

int viv_intocable(const VivacidadFuncion *vf, const char *nombre) {
    int i = viv_indice(vf, nombre);
    if (i < 0) return 1;              /* desconocido: por precaucion, intocable */
    return vf->escapa[i] || vf->global[i];
}

/* ------------------------------------------------------ USO y DEF locales */

/*
 * USO[B] y DEF[B] se calculan recorriendo el bloque HACIA ADELANTE:
 *
 *   - un nombre leido que todavia no se escribio en el bloque entra en USO,
 *   - un nombre escrito que todavia no se leyo en el bloque entra en DEF.
 *
 * El orden importa: en 'a = a + 1' la lectura de 'a' ocurre antes que su
 * escritura, asi que 'a' pertenece a USO y no a DEF.
 */
static void calcular_uso_def(VivacidadFuncion *vf) {
    const GrafoFuncion *fn = vf->fn;
    int k, j, w = vf->n_palabras;

    for (k = 0; k < fn->n_bloques; k++) {
        unsigned *uso = &vf->uso[(size_t)k * w];
        unsigned *def = &vf->def[(size_t)k * w];
        TACInst *i;

        for (i = fn->bloques[k].primera; i != NULL; i = i->next) {
            TACEfecto e;
            viv_efecto(i, &e);

            for (j = 0; j < e.n_usos; j++) {
                int idx = viv_indice(vf, e.usos[j]);
                if (idx >= 0 && !bit_puesto(def, idx)) poner_bit(uso, idx);
            }
            if (e.def != NULL) {
                int idx = viv_indice(vf, e.def);
                if (idx >= 0 && !bit_puesto(uso, idx)) poner_bit(def, idx);
            }
            if (i == fn->bloques[k].ultima) break;
        }
    }
}

/* ------------------------------------------------------- el punto fijo */

static void analizar_funcion(VivacidadFuncion *vf, const TACList *tac) {
    const GrafoFuncion *fn = vf->fn;
    int k, s, p, w, cambio;

    recoger_nombres(vf, tac);
    vf->n_palabras = PALABRAS(vf->n_nombres ? vf->n_nombres : 1);
    w = vf->n_palabras;

    if (fn->n_bloques == 0) return;

    vf->uso      = reservar((size_t)fn->n_bloques * w * sizeof(unsigned));
    vf->def      = reservar((size_t)fn->n_bloques * w * sizeof(unsigned));
    vf->vivo_ent = reservar((size_t)fn->n_bloques * w * sizeof(unsigned));
    vf->vivo_sal = reservar((size_t)fn->n_bloques * w * sizeof(unsigned));

    calcular_uso_def(vf);

    /*
     * Iteracion hasta el punto fijo. Se recorren los bloques en orden inverso
     * porque la informacion viaja hacia atras: asi cada pasada aprovecha lo que
     * ya se calculo de los sucesores y hacen falta menos vueltas. El recorrido
     * en cualquier orden converge al mismo resultado; solo cambia el costo.
     */
    vf->iteraciones = 0;
    do {
        cambio = 0;
        vf->iteraciones++;

        for (k = fn->n_bloques - 1; k >= 0; k--) {
            const Bloque *b = &fn->bloques[k];
            unsigned *sal = &vf->vivo_sal[(size_t)k * w];
            unsigned *ent = &vf->vivo_ent[(size_t)k * w];
            const unsigned *uso = &vf->uso[(size_t)k * w];
            const unsigned *def = &vf->def[(size_t)k * w];

            /* VIVO_SAL[B] = union de VIVO_ENT de los sucesores. */
            for (s = 0; s < b->n_suc; s++) {
                const unsigned *se = &vf->vivo_ent[(size_t)b->sucesores[s] * w];
                for (p = 0; p < w; p++) {
                    unsigned antes = sal[p];
                    sal[p] |= se[p];
                    if (sal[p] != antes) cambio = 1;
                }
            }

            /*
             * Condicion de frontera. A la salida de un retorno o de un halt el
             * marco desaparece: no queda vivo ningun local ni temporal. Solo
             * los nombres que escapan o son globales siguen importando, porque
             * su valor puede observarse desde fuera de la funcion.
             */
            if (b->n_suc == 0) {
                int n;
                for (n = 0; n < vf->n_nombres; n++)
                    if ((vf->escapa[n] || vf->global[n]) && !bit_puesto(sal, n)) {
                        poner_bit(sal, n);
                        cambio = 1;
                    }
            }

            /* VIVO_ENT[B] = USO[B] union (VIVO_SAL[B] menos DEF[B]). */
            for (p = 0; p < w; p++) {
                unsigned antes = ent[p];
                ent[p] = uso[p] | (sal[p] & ~def[p]);
                if (ent[p] != antes) cambio = 1;
            }
        }
    } while (cambio && vf->iteraciones < 1000);
}

Vivacidad *viv_analizar(const GrafoFlujo *g, const TACList *tac) {
    Vivacidad *v;
    int f;

    if (g == NULL) return NULL;

    v = reservar(sizeof(Vivacidad));
    v->n_funciones = g->n_funciones;
    v->funciones = reservar((size_t)g->n_funciones * sizeof(VivacidadFuncion));

    for (f = 0; f < g->n_funciones; f++) {
        v->funciones[f].fn = &g->funciones[f];
        analizar_funcion(&v->funciones[f], tac);
    }
    return v;
}

void viv_liberar(Vivacidad *v) {
    int f, k;
    if (v == NULL) return;
    for (f = 0; f < v->n_funciones; f++) {
        VivacidadFuncion *vf = &v->funciones[f];
        for (k = 0; k < vf->n_nombres; k++) free(vf->nombres[k]);
        free(vf->nombres);
        free(vf->uso);
        free(vf->def);
        free(vf->vivo_ent);
        free(vf->vivo_sal);
        free(vf->escapa);
        free(vf->global);
    }
    free(v->funciones);
    free(v);
}

int viv_muertas_en_bloque(const VivacidadFuncion *vf, int b,
                          unsigned char *fuera, int cap, int *sueltos) {
    const Bloque *bl;
    TACInst **orden;
    unsigned *vivo;
    int cuenta = 0, p, w;
    TACInst *i;

    if (sueltos != NULL) *sueltos = 0;
    if (vf == NULL || vf->vivo_sal == NULL) return 0;
    if (b < 0 || b >= vf->fn->n_bloques) return 0;

    bl = &vf->fn->bloques[b];
    w = vf->n_palabras;

    for (i = bl->primera; i != NULL; i = i->next) {
        cuenta++;
        if (i == bl->ultima) break;
    }
    if (cuenta == 0) return 0;
    if (cuenta > cap) return -1;

    memset(fuera, 0, (size_t)cuenta);

    /*
     * Un bloque inalcanzable se va entero: no hay camino que llegue hasta el,
     * asi que ninguna de sus instrucciones se ejecuta nunca.
     */
    if (!bl->alcanzable) {
        memset(fuera, VIV_SOBRA, (size_t)cuenta);
        return cuenta;
    }

    orden = reservar((size_t)cuenta * sizeof(TACInst *));
    cuenta = 0;
    for (i = bl->primera; i != NULL; i = i->next) {
        orden[cuenta++] = i;
        if (i == bl->ultima) break;
    }

    vivo = reservar((size_t)w * sizeof(unsigned));
    memcpy(vivo, &vf->vivo_sal[(size_t)b * w], (size_t)w * sizeof(unsigned));

    /*
     * Hacia atras. Al marcar una instruccion como sobrante NO se avivan sus
     * lecturas: como va a desaparecer, no va a leer nada. Asi una cadena
     * entera de calculos muertos cae en una sola pasada en vez de necesitar
     * una ronda por eslabon.
     */
    for (p = cuenta - 1; p >= 0; p--) {
        TACEfecto e;
        int j, idx, destino_muerto = 0;

        viv_efecto(orden[p], &e);

        if (e.def != NULL) {
            idx = viv_indice(vf, e.def);
            destino_muerto = (idx >= 0 && !bit_puesto(vivo, idx) &&
                              !vf->escapa[idx] && !vf->global[idx]);
        }

        if (destino_muerto && !e.efecto) {
            fuera[p] = VIV_SOBRA;
            continue;
        }
        if (destino_muerto && orden[p]->op == TAC_CALL) {
            fuera[p] = VIV_SIN_USO;
            if (sueltos != NULL) (*sueltos)++;
        }

        if (e.def != NULL) {
            idx = viv_indice(vf, e.def);
            if (idx >= 0) quitar_bit(vivo, idx);
        }
        for (j = 0; j < e.n_usos; j++) {
            idx = viv_indice(vf, e.usos[j]);
            if (idx >= 0) poner_bit(vivo, idx);
        }
    }

    free(vivo);
    free(orden);
    return cuenta;
}

int viv_viva_a_la_salida(const VivacidadFuncion *vf, int b, const char *nombre) {
    int idx;
    if (vf == NULL || vf->vivo_sal == NULL) return 1;
    if (b < 0 || b >= vf->fn->n_bloques) return 1;
    idx = viv_indice(vf, nombre);
    if (idx < 0) return 1;            /* desconocido: por precaucion, viva */
    return bit_puesto(&vf->vivo_sal[(size_t)b * vf->n_palabras], idx);
}

/* ------------------------------------------------------------- listado */

static void imprimir_conjunto(FILE *out, const VivacidadFuncion *vf,
                              const unsigned *c) {
    int n, primero = 1;
    for (n = 0; n < vf->n_nombres; n++) {
        if (!bit_puesto(c, n)) continue;
        fprintf(out, "%s%s", primero ? "" : ", ", vf->nombres[n]);
        primero = 0;
    }
    if (primero) fprintf(out, "-");
}

void viv_imprimir(FILE *out, const Vivacidad *v) {
    int f, k, n;

    fprintf(out, "=== Analisis de vivacidad (liveness) ===\n");
    if (v == NULL) {
        fprintf(out, "(sin codigo intermedio)\n");
        return;
    }

    for (f = 0; f < v->n_funciones; f++) {
        const VivacidadFuncion *vf = &v->funciones[f];
        const GrafoFuncion *fn = vf->fn;
        int w = vf->n_palabras, escapados = 0;

        for (n = 0; n < vf->n_nombres; n++) if (vf->escapa[n]) escapados++;

        fprintf(out, "\nfunctio %s: %d nombre%s, punto fijo en %d pasada%s\n",
                fn->nombre, vf->n_nombres, vf->n_nombres == 1 ? "" : "s",
                vf->iteraciones, vf->iteraciones == 1 ? "" : "s");

        if (escapados > 0) {
            fprintf(out, "  escapan por & (nunca se dan por muertos): ");
            for (n = 0; n < vf->n_nombres; n++)
                if (vf->escapa[n]) fprintf(out, "%s ", vf->nombres[n]);
            fprintf(out, "\n");
        }

        for (k = 0; k < fn->n_bloques; k++) {
            const Bloque *b = &fn->bloques[k];
            TACInst *i;

            fprintf(out, "\n  B%d", b->id);
            if (b->etiqueta != NULL) fprintf(out, " (%s)", b->etiqueta);
            if (!b->alcanzable) fprintf(out, " [INALCANZABLE]");
            fprintf(out, "\n");

            fprintf(out, "      USO:      ");
            imprimir_conjunto(out, vf, &vf->uso[(size_t)k * w]);
            fprintf(out, "\n      DEF:      ");
            imprimir_conjunto(out, vf, &vf->def[(size_t)k * w]);
            fprintf(out, "\n      VIVO_ENT: ");
            imprimir_conjunto(out, vf, &vf->vivo_ent[(size_t)k * w]);
            fprintf(out, "\n      VIVO_SAL: ");
            imprimir_conjunto(out, vf, &vf->vivo_sal[(size_t)k * w]);
            fprintf(out, "\n");

            /*
             * Recorrido hacia atras dentro del bloque: a la derecha de cada
             * instruccion, que estaba vivo justo despues de ejecutarla. Es la
             * informacion con la que trabaja la eliminacion de codigo muerto.
             */
            if (b->alcanzable) {
                TACInst **orden;
                unsigned char *marca;
                int cuenta = 0, p, hay = 0;

                for (i = b->primera; i != NULL; i = i->next) {
                    cuenta++;
                    if (i == b->ultima) break;
                }
                if (cuenta == 0) continue;

                orden = reservar((size_t)cuenta * sizeof(TACInst *));
                marca = reservar((size_t)cuenta);
                cuenta = 0;
                for (i = b->primera; i != NULL; i = i->next) {
                    orden[cuenta++] = i;
                    if (i == b->ultima) break;
                }

                viv_muertas_en_bloque(vf, k, marca, cuenta, NULL);
                for (p = 0; p < cuenta; p++) if (marca[p]) hay = 1;

                /* Se reportan en el orden en que estan escritas. */
                if (hay) {
                    fprintf(out, "      lo que -O1 quitaria de aqui:\n");
                    for (p = 0; p < cuenta; p++) {
                        TACEfecto e;
                        if (!marca[p]) continue;
                        viv_efecto(orden[p], &e);
                        fprintf(out, "    ");
                        tac_print_inst(out, orden[p]);
                        if (marca[p] == VIV_SOBRA)
                            fprintf(out, "        ^^ '%s' no se vuelve a leer\n",
                                    e.def);
                        else
                            fprintf(out, "        ^^ la llamada se queda, pero "
                                         "nadie lee '%s'\n", e.def);
                    }
                }
                free(marca);
                free(orden);
            }
        }
    }
}
