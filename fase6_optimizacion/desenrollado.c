#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bloques.h"
#include "desenrollado.h"
#include "vivacidad.h"

#define LIMITE_BUNDLES_IMEM 2048
#define LIMITE_BUNDLES_SALTO 480
#define COSTO_BUNDLE_ESTIMADO 7
#define MAX_FACTOR_HEURISTICO 8
#define COSTO_GUARDA_GRUPOS 3
#define COSTO_INICIALIZACION_GUARDA 2

typedef struct {
    char *nombre;
    char *copia;
} Mapeo;

typedef struct {
    const GrafoFuncion *funcion;
    int cabecera;
    int retorno;
    int extension;
    TACInst *primera;
    TACInst *ultima;
    TACInst *etiqueta_cabecera;
    TACInst *condicion;
    char *nombre_cabecera;
    char *salida;
    char *contador;
    TACInst *comparacion_contador;
    TACInst *actualizacion_contador;
    int paso_constante;
    int puede_agrupar;
    int64_t trip_estimado;
    int trip_estimado_conocido;
    long trip_count;
    int trip_conocido;
} Lazo;

static void *reservar(size_t n) {
    void *p = calloc(1, n);
    if (p == NULL) {
        fprintf(stderr, "novac: sin memoria en loop unrolling\n");
        exit(3);
    }
    return p;
}

static char *duplicar(const char *s) {
    if (s == NULL) return NULL;
    size_t n = strlen(s) + 1;
    char *c = malloc(n);
    if (c == NULL) {
        fprintf(stderr, "novac: sin memoria en loop unrolling\n");
        exit(3);
    }
    memcpy(c, s, n);
    return c;
}

static int instruccion_define(const TACInst *i, const char *nombre) {
    TACEfecto e;
    viv_efecto(i, &e);
    return e.def != NULL && nombre != NULL && strcmp(e.def, nombre) == 0;
}

static TACInst *definicion_antes(TACInst *desde, TACInst *antes,
                                 const char *nombre) {
    TACInst *def = NULL;
    for (TACInst *i = desde; i != NULL && i != antes; i = i->next)
        if (instruccion_define(i, nombre)) def = i;
    return def;
}

static TACInst *inicio_funcion(TACList *tac, TACInst *punto) {
    TACInst *inicio = tac->head;
    for (TACInst *i = tac->head; i != NULL && i != punto; i = i->next)
        if (i->op == TAC_FUNC_BEGIN) inicio = i;
    return inicio;
}

static int direccion_tomada(TACList *tac, TACInst *punto,
                            const char *nombre) {
    TACInst *inicio = inicio_funcion(tac, punto);
    for (TACInst *i = inicio; i != NULL; i = i->next) {
        if (i->op == TAC_ADDR && i->arg1 != NULL &&
            strcmp(i->arg1, nombre) == 0)
            return 1;
        if (i->op == TAC_FUNC_END) break;
    }
    return 0;
}

static int es_comparacion(TACOp op) {
    return op == TAC_LT || op == TAC_LE || op == TAC_GT || op == TAC_GE;
}

static int instruccion_en_bloque(const Bloque *bloque,
                                 const TACInst *objetivo) {
    for (TACInst *i = bloque->primera; i != NULL; i = i->next) {
        if (i == objetivo) return 1;
        if (i == bloque->ultima) break;
    }
    return 0;
}

static int indice_bloque_instruccion(const GrafoFuncion *funcion,
                                     const TACInst *objetivo) {
    for (int b = 0; b < funcion->n_bloques; b++)
        if (instruccion_en_bloque(&funcion->bloques[b], objetivo))
            return b;
    return -1;
}

static int preheader_unico(const Lazo *lazo) {
    const GrafoFuncion *funcion = lazo->funcion;
    const Bloque *cabecera = &funcion->bloques[lazo->cabecera];
    int preheader = -1;

    for (int p = 0; p < cabecera->n_pred; p++) {
        int pred = cabecera->predecesores[p];
        if (pred >= lazo->cabecera && pred <= lazo->retorno) continue;
        if (preheader >= 0) return -1;
        preheader = pred;
    }
    if (preheader < 0) return -1;

    const Bloque *bloque = &funcion->bloques[preheader];
    if (bloque->n_suc != 1 || bloque->sucesores[0] != lazo->cabecera)
        return -1;
    return preheader;
}

static int constante_en_bloque(TACList *tac, TACInst *punto,
                               const char *nombre, int profundidad,
                               const Bloque *bloque, int64_t *valor) {
    if (nombre == NULL || profundidad > 8) return 0;
    TACInst *def = definicion_antes(inicio_funcion(tac, punto), punto, nombre);
    if (def == NULL || !instruccion_en_bloque(bloque, def)) return 0;
    if (def->op == TAC_CONST) {
        *valor = def->valor;
        return 1;
    }
    if (def->op == TAC_ASSIGN)
        return constante_en_bloque(tac, def, def->arg1, profundidad + 1,
                                   bloque, valor);
    return 0;
}

static int calcular_trip_count(TACList *tac, Lazo *lazo, long *cuenta) {
    TACInst *comparacion, *paso, *asignacion, *def_limite;
    const char *contador;
    int64_t inicio, limite, delta, magnitud, distancia, n;
    int preheader, bloque_limite;

    if (lazo->condicion == NULL || lazo->condicion->op != TAC_IF_FALSE)
        return 0;
    preheader = preheader_unico(lazo);
    if (preheader < 0) return 0;

    comparacion = definicion_antes(lazo->primera, lazo->condicion,
                                   lazo->condicion->arg1);
    if (comparacion == NULL || !es_comparacion(comparacion->op) ||
        comparacion->arg1 == NULL || comparacion->arg2 == NULL)
        return 0;
    contador = comparacion->arg1;
    if (comparacion->arg2 == NULL ||
        direccion_tomada(tac, lazo->primera, contador) ||
        direccion_tomada(tac, lazo->primera, comparacion->arg2))
        return 0;
    if (!constante_en_bloque(tac, lazo->etiqueta_cabecera, contador, 0,
                             &lazo->funcion->bloques[preheader], &inicio))
        return 0;

    asignacion = NULL;
    int escrituras_contador = 0;
    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        if (instruccion_define(i, contador)) {
            escrituras_contador++;
            asignacion = i;
        }
        if (i == lazo->ultima) break;
    }
    if (escrituras_contador != 1 || asignacion == NULL ||
        asignacion->op != TAC_ASSIGN || asignacion->arg1 == NULL)
        return 0;

    paso = definicion_antes(lazo->primera, asignacion, asignacion->arg1);
    if (paso == NULL || (paso->op != TAC_ADD && paso->op != TAC_SUB))
        return 0;
    if (indice_bloque_instruccion(lazo->funcion, paso) != lazo->retorno ||
        indice_bloque_instruccion(lazo->funcion, asignacion) != lazo->retorno)
        return 0;
    if (paso->op == TAC_ADD && paso->arg1 != NULL &&
        strcmp(paso->arg1, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg2, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
    } else if (paso->op == TAC_ADD && paso->arg2 != NULL &&
               strcmp(paso->arg2, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg1, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
    } else if (paso->op == TAC_SUB && paso->arg1 != NULL &&
               strcmp(paso->arg1, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg2, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
        if (delta == INT64_MIN) return 0;
        delta = -delta;
    } else {
        return 0;
    }
    def_limite = definicion_antes(inicio_funcion(tac, comparacion),
                                  comparacion, comparacion->arg2);
    if (def_limite == NULL || def_limite->op != TAC_CONST) return 0;
    bloque_limite = indice_bloque_instruccion(lazo->funcion, def_limite);
    if (bloque_limite != preheader && bloque_limite != lazo->cabecera)
        return 0;
    if (!constante_en_bloque(tac, comparacion, comparacion->arg2, 0,
                             &lazo->funcion->bloques[bloque_limite], &limite))
        return 0;
    if (delta == 0 || delta < INT32_MIN || delta > INT32_MAX ||
        inicio < INT32_MIN || inicio > INT32_MAX ||
        limite < INT32_MIN || limite > INT32_MAX)
        return 0;

    /* No asumir constancia si una llamada puede alterar estado observable. */
    int dentro = 0;
    for (TACInst *i = inicio_funcion(tac, lazo->primera); i != NULL; i = i->next) {
        if (i == lazo->primera) dentro = 1;
        if (i->op == TAC_ADDR && i->arg1 != NULL &&
            strcmp(i->arg1, contador) == 0)
            return 0;
        if (dentro && i->op == TAC_CALL) return 0;
        if (i == lazo->ultima) break;
    }
    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        if (instruccion_define(i, comparacion->arg2) &&
            (i != def_limite || i->op != TAC_CONST))
            return 0;
        if (i == lazo->ultima) break;
    }

    magnitud = delta > 0 ? delta : -delta;
    if (comparacion->op == TAC_LT && delta > 0) {
        if (inicio >= limite) n = 0;
        else { distancia = limite - inicio; n = (distancia + magnitud - 1) / magnitud; }
    } else if (comparacion->op == TAC_LE && delta > 0) {
        if (inicio > limite) n = 0;
        else { distancia = limite - inicio; n = distancia / magnitud + 1; }
    } else if (comparacion->op == TAC_GT && delta < 0) {
        if (inicio <= limite) n = 0;
        else { distancia = inicio - limite; n = (distancia + magnitud - 1) / magnitud; }
    } else if (comparacion->op == TAC_GE && delta < 0) {
        if (inicio < limite) n = 0;
        else { distancia = inicio - limite; n = distancia / magnitud + 1; }
    } else {
        return 0;
    }
    if (n < 0 || n > LONG_MAX || n > INT64_MAX / magnitud ||
        inicio + n * delta < INT32_MIN || inicio + n * delta > INT32_MAX)
        return 0;

    lazo->contador = duplicar(contador);
    lazo->actualizacion_contador = asignacion;
    *cuenta = (long)n;
    return 1;
}

static int expresion_pura(TACOp op) {
    switch (op) {
        case TAC_CONST: case TAC_ASSIGN:
        case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR: case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR:
        case TAC_EQ: case TAC_NE: case TAC_LT: case TAC_LE:
        case TAC_GT: case TAC_GE:
        case TAC_NEG: case TAC_BITNOT: case TAC_NOT:
            return 1;
        default:
            return 0;
    }
}

static int constante_de_funcion_simple(TACList *tac, const char *funcion,
                                       int64_t *valor) {
    TACInst *inicio = NULL, *retorno = NULL;

    for (TACInst *i = tac->head; i != NULL; i = i->next)
        if (i->op == TAC_FUNC_BEGIN && i->result != NULL &&
            strcmp(i->result, funcion) == 0) {
            inicio = i;
            break;
        }
    if (inicio == NULL) return 0;

    for (TACInst *i = inicio->next; i != NULL && i->op != TAC_FUNC_END;
         i = i->next) {
        if (i->op == TAC_CONST) continue;
        if (i->op == TAC_RET_VAL && retorno == NULL) {
            retorno = i;
            continue;
        }
        return 0;
    }
    if (retorno == NULL || retorno->arg1 == NULL) return 0;

    TACInst *def = definicion_antes(inicio->next, retorno, retorno->arg1);
    if (def == NULL || def->op != TAC_CONST) return 0;
    *valor = def->valor;
    return 1;
}

static int limite_constante_de_llamada(TACList *tac, TACInst *comparacion,
                                       const char *limite, int64_t *valor) {
    TACInst *def_limite, *llamada;
    if (limite == NULL) return 0;
    def_limite = definicion_antes(inicio_funcion(tac, comparacion),
                                  comparacion, limite);
    if (def_limite == NULL || def_limite->op != TAC_ASSIGN ||
        def_limite->arg1 == NULL)
        return 0;
    llamada = definicion_antes(inicio_funcion(tac, def_limite), def_limite,
                               def_limite->arg1);
    if (llamada == NULL || llamada->op != TAC_CALL || llamada->aux != 0 ||
        llamada->arg1 == NULL)
        return 0;
    return constante_de_funcion_simple(tac, llamada->arg1, valor);
}

static int estimar_trip_count(TACOp op, int64_t inicio, int64_t limite,
                              int64_t delta, int64_t *cuenta) {
    int64_t magnitud = delta > 0 ? delta : -delta;
    int64_t distancia, n;

    if (op == TAC_LT && delta > 0) {
        if (inicio >= limite) n = 0;
        else {
            distancia = limite - inicio;
            n = (distancia + magnitud - 1) / magnitud;
        }
    } else if (op == TAC_LE && delta > 0) {
        if (inicio > limite) n = 0;
        else {
            distancia = limite - inicio;
            n = distancia / magnitud + 1;
        }
    } else if (op == TAC_GT && delta < 0) {
        if (inicio <= limite) n = 0;
        else {
            distancia = inicio - limite;
            n = (distancia + magnitud - 1) / magnitud;
        }
    } else if (op == TAC_GE && delta < 0) {
        if (inicio < limite) n = 0;
        else {
            distancia = inicio - limite;
            n = distancia / magnitud + 1;
        }
    } else {
        return 0;
    }
    if (n < 0 || n > INT64_MAX / magnitud ||
        inicio + n * delta < INT32_MIN || inicio + n * delta > INT32_MAX)
        return 0;
    *cuenta = n;
    return 1;
}

static int analizar_lazo_agrupable(TACList *tac, Lazo *lazo) {
    TACInst *comparacion, *paso, *asignacion = NULL;
    const char *contador, *limite;
    int64_t delta;
    int escrituras_contador = 0;

    if (lazo->condicion == NULL || lazo->condicion->op != TAC_IF_FALSE ||
        preheader_unico(lazo) < 0)
        return 0;
    comparacion = definicion_antes(lazo->primera, lazo->condicion,
                                   lazo->condicion->arg1);
    if (comparacion == NULL || !es_comparacion(comparacion->op) ||
        comparacion->next != lazo->condicion ||
        comparacion->arg1 == NULL || comparacion->arg2 == NULL ||
        comparacion->result == NULL ||
        strcmp(comparacion->result, lazo->condicion->arg1) != 0 ||
        lazo->ultima->op != TAC_GOTO ||
        lazo->ultima->result == NULL ||
        strcmp(lazo->ultima->result, lazo->nombre_cabecera) != 0)
        return 0;

    contador = comparacion->arg1;
    limite = comparacion->arg2;
    if (strcmp(contador, limite) == 0) return 0;
    if (direccion_tomada(tac, lazo->primera, contador) ||
        direccion_tomada(tac, lazo->primera, limite))
        return 0;

    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        if (instruccion_define(i, contador)) {
            escrituras_contador++;
            asignacion = i;
        }
        if (i->op == TAC_CALL || i->op == TAC_TAILCALL) return 0;
        if (i->op == TAC_ADDR && i->arg1 != NULL &&
            (strcmp(i->arg1, contador) == 0 ||
             strcmp(i->arg1, limite) == 0))
            return 0;
        if (i == lazo->ultima) break;
    }
    if (escrituras_contador != 1 || asignacion == NULL ||
        asignacion->op != TAC_ASSIGN || asignacion->arg1 == NULL)
        return 0;

    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        if (i != asignacion && instruccion_define(i, contador)) return 0;
        if (i != lazo->condicion && i->op == TAC_IF_FALSE) return 0;
        if (i != lazo->condicion && i->op == TAC_IF_TRUE) return 0;
        if (i != lazo->ultima && i->op == TAC_GOTO) return 0;
        if (i == lazo->ultima) break;
    }
    for (TACInst *i = lazo->condicion->next; i != NULL; i = i->next) {
        if (instruccion_define(i, limite)) return 0;
        if (i == lazo->ultima) break;
    }

    for (TACInst *i = lazo->etiqueta_cabecera->next;
         i != comparacion; i = i->next) {
        TACEfecto efecto;
        if (i == NULL || !expresion_pura(i->op)) return 0;
        viv_efecto(i, &efecto);
        if (efecto.def == NULL || !tac_es_temporal(efecto.def)) return 0;
        for (int u = 0; u < efecto.n_usos; u++) {
            const char *uso = efecto.usos[u];
            if (uso == NULL) continue;
            if (strcmp(uso, contador) == 0) return 0;
            if (definicion_antes(lazo->etiqueta_cabecera->next, i, uso) != NULL)
                continue;
            for (TACInst *b = lazo->primera; b != NULL; b = b->next) {
                if (instruccion_define(b, uso)) return 0;
                if (b->op == TAC_ADDR && b->arg1 != NULL &&
                    strcmp(b->arg1, uso) == 0)
                    return 0;
                if (b == lazo->ultima) break;
            }
        }
    }

    paso = definicion_antes(lazo->primera, asignacion, asignacion->arg1);
    if (paso == NULL || (paso->op != TAC_ADD && paso->op != TAC_SUB) ||
        indice_bloque_instruccion(lazo->funcion, paso) != lazo->retorno ||
        indice_bloque_instruccion(lazo->funcion, asignacion) != lazo->retorno)
        return 0;
    if (paso->op == TAC_ADD && paso->arg1 != NULL &&
        strcmp(paso->arg1, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg2, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
    } else if (paso->op == TAC_ADD && paso->arg2 != NULL &&
               strcmp(paso->arg2, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg1, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
    } else if (paso->op == TAC_SUB && paso->arg1 != NULL &&
               strcmp(paso->arg1, contador) == 0) {
        if (!constante_en_bloque(tac, paso, paso->arg2, 0,
                                 &lazo->funcion->bloques[lazo->retorno],
                                 &delta))
            return 0;
        if (delta == INT64_MIN) return 0;
        delta = -delta;
    } else {
        return 0;
    }
    if (delta == 0 || delta < INT32_MIN || delta > INT32_MAX)
        return 0;
    if (!((comparacion->op == TAC_LT || comparacion->op == TAC_LE) &&
          delta > 0) &&
        !((comparacion->op == TAC_GT || comparacion->op == TAC_GE) &&
          delta < 0))
        return 0;

    lazo->contador = lazo->contador != NULL
        ? lazo->contador : duplicar(contador);
    lazo->comparacion_contador = comparacion;
    lazo->actualizacion_contador = asignacion;
    lazo->paso_constante = (int)delta;
    lazo->puede_agrupar = 1;

    int preheader = preheader_unico(lazo);
    int64_t inicio, limite_estimado, trip_estimado;
    if (preheader >= 0 &&
        constante_en_bloque(tac, lazo->etiqueta_cabecera, contador, 0,
                            &lazo->funcion->bloques[preheader], &inicio) &&
        limite_constante_de_llamada(tac, comparacion, limite,
                                    &limite_estimado) &&
        inicio >= INT32_MIN && inicio <= INT32_MAX &&
        limite_estimado >= INT32_MIN && limite_estimado <= INT32_MAX &&
        estimar_trip_count(comparacion->op, inicio, limite_estimado, delta,
                           &trip_estimado)) {
        lazo->trip_estimado = trip_estimado;
        lazo->trip_estimado_conocido = 1;
    }
    return 1;
}

static int comparar_lazos(const void *a, const void *b) {
    const Lazo *la = a, *lb = b;
    if (la->extension != lb->extension)
        return la->extension - lb->extension;
    return lb->cabecera - la->cabecera;
}

static int reunir_lazos(TACList *tac, GrafoFlujo *cfg, Lazo **resultado) {
    int total = 0, capacidad = 0;
    Lazo *lazos = NULL;

    for (int f = 0; f < cfg->n_funciones; f++) {
        const GrafoFuncion *fn = &cfg->funciones[f];
        for (int k = 0; k < fn->n_bloques; k++) {
            const Bloque *retorno = &fn->bloques[k];
            if (retorno->ultima == NULL || retorno->ultima->op != TAC_GOTO)
                continue;
            for (int s = 0; s < retorno->n_suc; s++) {
                int h = retorno->sucesores[s];
                if (h > k || fn->bloques[h].etiqueta == NULL ||
                    retorno->ultima->result == NULL ||
                    strcmp(retorno->ultima->result, fn->bloques[h].etiqueta) != 0)
                    continue;

                int retornos_a_cabecera = 0;
                for (int b = 0; b < fn->n_bloques; b++)
                    for (int e = 0; e < fn->bloques[b].n_suc; e++)
                        if (fn->bloques[b].sucesores[e] == h && b >= h)
                            retornos_a_cabecera++;
                if (retornos_a_cabecera != 1) continue;

                const Bloque *cab = &fn->bloques[h];
                TACInst *etiqueta = cab->primera;
                TACInst *cond = cab->ultima;
                if (etiqueta == NULL || etiqueta->op != TAC_LABEL ||
                    cond == NULL || (cond->op != TAC_IF_FALSE &&
                                     cond->op != TAC_IF_TRUE) ||
                    cond->result == NULL)
                    continue;

                int seguro = 1;
                for (int b = h; b <= k; b++)
                    if (fn->bloques[b].etiqueta != NULL &&
                        strcmp(fn->bloques[b].etiqueta, cond->result) == 0) {
                        seguro = 0;
                        break;
                    }
                for (int b = h + 1; b <= k && seguro; b++) {
                    for (int p = 0; p < fn->bloques[b].n_pred; p++) {
                        int pred = fn->bloques[b].predecesores[p];
                        if (pred < h || pred > k) { seguro = 0; break; }
                    }
                }
                if (!seguro) continue;

                if (total == capacidad) {
                    capacidad = capacidad ? capacidad * 2 : 8;
                    lazos = realloc(lazos, (size_t)capacidad * sizeof(Lazo));
                    if (lazos == NULL) {
                        fprintf(stderr, "novac: sin memoria en loop unrolling\n");
                        exit(3);
                    }
                }
                Lazo *lazo = &lazos[total++];
                memset(lazo, 0, sizeof(*lazo));
                lazo->funcion = fn;
                lazo->cabecera = h;
                lazo->retorno = k;
                lazo->extension = k - h;
                lazo->primera = cab->primera;
                lazo->ultima = retorno->ultima;
                lazo->etiqueta_cabecera = etiqueta;
                lazo->condicion = cond;
                lazo->nombre_cabecera = duplicar(etiqueta->result);
                lazo->salida = duplicar(cond->result);
                break;
            }
        }
    }
    if (total > 1)
        qsort(lazos, (size_t)total, sizeof(Lazo), comparar_lazos);
    for (int i = 0; i < total; i++)
        lazos[i].trip_conocido =
            calcular_trip_count(tac, &lazos[i], &lazos[i].trip_count);
    for (int i = 0; i < total; i++)
        analizar_lazo_agrupable(tac, &lazos[i]);
    *resultado = lazos;
    return total;
}

static int contar_region(const Lazo *lazo) {
    int n = 0;
    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        n++;
        if (i == lazo->ultima) break;
    }
    return n;
}

static int contar_tac(const TACList *tac) {
    int n = 0;
    for (const TACInst *i = tac->head; i != NULL; i = i->next) n++;
    return n;
}

static int factor_heuristico(const Lazo *lazo, int tamano) {
    if (lazo->trip_conocido && lazo->trip_count <= 8)
        return (int)lazo->trip_count;
    if (lazo->trip_estimado_conocido) {
        if (tamano > 24) return 0;
        if (lazo->trip_estimado == 0) return 0;
        if (lazo->trip_estimado <= 8) return 5;
        if (lazo->trip_estimado >= 64) return MAX_FACTOR_HEURISTICO;
        return 4;
    }
    if (lazo->puede_agrupar && tamano <= 24)
        return 2;
    if (tamano <= 8) return 2;
    if (tamano <= 24) return 2;
    return 0;
}

static int mapear_nombre(Mapeo *mapa, int n, const char *nombre,
                         const char **copia) {
    if (nombre == NULL) return 0;
    for (int i = 0; i < n; i++)
        if (strcmp(mapa[i].nombre, nombre) == 0) {
            *copia = mapa[i].copia;
            return 1;
        }
    return 0;
}

static void agregar_mapeo(Mapeo **mapa, int *n, int *capacidad,
                          const char *nombre, char *copia) {
    if (*n == *capacidad) {
        *capacidad = *capacidad ? *capacidad * 2 : 16;
        *mapa = realloc(*mapa, (size_t)*capacidad * sizeof(Mapeo));
        if (*mapa == NULL) {
            fprintf(stderr, "novac: sin memoria en loop unrolling\n");
            exit(3);
        }
    }
    (*mapa)[*n].nombre = duplicar(nombre);
    (*mapa)[*n].copia = copia;
    (*n)++;
}

static void liberar_mapeos(Mapeo *mapa, int n) {
    for (int i = 0; i < n; i++) {
        free(mapa[i].nombre);
        free(mapa[i].copia);
    }
    free(mapa);
}

static TACInst *copiar_instruccion(const TACInst *origen, Mapeo *temps,
                                   int n_temps, Mapeo *etiquetas, int n_etiquetas) {
    TACInst *copia = reservar(sizeof(TACInst));
    *copia = *origen;
    copia->result = duplicar(origen->result);
    copia->arg1 = duplicar(origen->arg1);
    copia->arg2 = duplicar(origen->arg2);
    copia->next = NULL;

    const char *nuevo;
    if (origen->op == TAC_LABEL || origen->op == TAC_GOTO ||
        origen->op == TAC_IF_FALSE || origen->op == TAC_IF_TRUE) {
        if (mapear_nombre(etiquetas, n_etiquetas, origen->result, &nuevo)) {
            free(copia->result);
            copia->result = duplicar(nuevo);
        }
    } else if (instruccion_define(origen, origen->result) &&
               mapear_nombre(temps, n_temps, origen->result, &nuevo)) {
        free(copia->result);
        copia->result = duplicar(nuevo);
    }

    TACEfecto efecto;
    viv_efecto(origen, &efecto);
    for (int u = 0; u < efecto.n_usos; u++) {
        if (efecto.usos[u] == NULL ||
            !mapear_nombre(temps, n_temps, efecto.usos[u], &nuevo))
            continue;
        if (origen->result == efecto.usos[u]) {
            free(copia->result);
            copia->result = duplicar(nuevo);
        } else if (origen->arg1 == efecto.usos[u]) {
            free(copia->arg1);
            copia->arg1 = duplicar(nuevo);
        } else if (origen->arg2 == efecto.usos[u]) {
            free(copia->arg2);
            copia->arg2 = duplicar(nuevo);
        }
    }
    return copia;
}

static TACInst *copiar_region(TACInst *primera, TACInst *ultima,
                              TACInst **copia_ultima) {
    Mapeo *temps = NULL, *etiquetas = NULL;
    int n_temps = 0, cap_temps = 0, n_etiquetas = 0, cap_etiquetas = 0;
    TACInst *primera_copia = NULL, *ultima_copia = NULL;

    for (TACInst *i = primera; i != NULL; i = i->next) {
        if (i->op == TAC_LABEL)
            agregar_mapeo(&etiquetas, &n_etiquetas, &cap_etiquetas,
                          i->result, tac_new_label());
        TACEfecto efecto;
        viv_efecto(i, &efecto);
        int ya_mapeado = 0;
        for (int t = 0; t < n_temps; t++)
            if (efecto.def != NULL &&
                strcmp(temps[t].nombre, efecto.def) == 0) ya_mapeado = 1;
        if (efecto.def != NULL && tac_es_temporal(efecto.def) && !ya_mapeado)
            agregar_mapeo(&temps, &n_temps, &cap_temps,
                          efecto.def, tac_new_temp());
        if (i == ultima) break;
    }

    for (TACInst *i = primera; i != NULL; i = i->next) {
        TACInst *copia = copiar_instruccion(i, temps, n_temps,
                                            etiquetas, n_etiquetas);
        if (primera_copia == NULL) primera_copia = copia;
        else ultima_copia->next = copia;
        ultima_copia = copia;
        if (i == ultima) break;
    }

    liberar_mapeos(temps, n_temps);
    liberar_mapeos(etiquetas, n_etiquetas);
    if (copia_ultima != NULL) *copia_ultima = ultima_copia;
    return primera_copia;
}

static TACInst *nueva_instruccion(TACOp op, const char *result,
                                  const char *arg1, const char *arg2) {
    TACInst *i = reservar(sizeof(TACInst));
    i->op = op;
    i->result = duplicar(result);
    i->arg1 = duplicar(arg1);
    i->arg2 = duplicar(arg2);
    return i;
}

static void anexar_instruccion(TACInst **primera, TACInst **ultima,
                               TACInst *i) {
    if (*primera == NULL) *primera = i;
    else (*ultima)->next = i;
    *ultima = i;
}

static int es_transferencia(TACOp op) {
    return op == TAC_GOTO || op == TAC_IF_FALSE || op == TAC_IF_TRUE ||
           op == TAC_RET || op == TAC_RET_VAL || op == TAC_TAILCALL ||
           op == TAC_HALT;
}

static int ubicar_preheader(TACList *tac, const Lazo *lazo,
                            TACInst **ultima_preheader,
                            TACInst **anterior_preheader) {
    int preheader = preheader_unico(lazo);
    if (preheader < 0) return 0;

    *ultima_preheader = lazo->funcion->bloques[preheader].ultima;
    if (*ultima_preheader == NULL) return 0;
    if ((*ultima_preheader)->op == TAC_GOTO) {
        if ((*ultima_preheader)->result == NULL ||
            strcmp((*ultima_preheader)->result, lazo->nombre_cabecera) != 0)
            return 0;
    } else if (es_transferencia((*ultima_preheader)->op) ||
               (*ultima_preheader)->next != lazo->etiqueta_cabecera) {
        return 0;
    }
    *anterior_preheader = NULL;
    int encontrado = 0;
    for (TACInst *i = tac->head; i != NULL; i = i->next) {
        if (i == *ultima_preheader) {
            encontrado = 1;
            break;
        }
        *anterior_preheader = i;
    }
    return encontrado;
}

static void insertar_en_preheader(TACList *tac, TACInst *ultima_preheader,
                                  TACInst *anterior_preheader,
                                  TACInst *instrucciones,
                                  TACInst *ultima_instruccion) {
    if (es_transferencia(ultima_preheader->op)) {
        ultima_instruccion->next = ultima_preheader;
        if (anterior_preheader == NULL) tac->head = instrucciones;
        else anterior_preheader->next = instrucciones;
    } else {
        ultima_instruccion->next = ultima_preheader->next;
        ultima_preheader->next = instrucciones;
        if (tac->tail == ultima_preheader) tac->tail = ultima_instruccion;
    }
}

static int contar_antes(TACInst *primera, TACInst *hasta) {
    int n = 0;
    for (TACInst *i = primera; i != NULL && i != hasta; i = i->next) n++;
    return n;
}

static void enlazar(TACList *tac, TACInst *despues, TACInst *copias);

static int ganancia_grupos(int factor) {
    int guarda_original = 2;
    return (factor - 1) * guarda_original - COSTO_GUARDA_GRUPOS;
}

static int expandir_lazo_agrupado(TACList *tac, Lazo *lazo, int factor) {
    int64_t desplazamiento =
        (int64_t)(factor - 1) * lazo->paso_constante;
    int64_t limite_seguro;
    TACInst *copia_resto, *ultima_resto, *cuerpo_ultima;
    TACInst *copias_cuerpo = NULL, *cola_cuerpo = NULL;
    TACInst *guardas = NULL, *cola_guardas = NULL;
    char *nombre_desplazamiento, *nombre_extremo, *nombre_seguro;
    char *nombre_prueba_segura, *nombre_guardia;
    char *nombre_cabecera_resto;
    TACInst *anterior_retorno = NULL, *instruccion_and;
    TACInst *ultima_preheader = NULL, *anterior_preheader = NULL;
    TACInst *constantes = NULL, *cola_constantes = NULL;
    int n_cuerpo;

    if (!lazo->puede_agrupar || factor < 2 ||
        desplazamiento < INT32_MIN || desplazamiento > INT32_MAX)
        return 0;
    if (!ubicar_preheader(tac, lazo, &ultima_preheader,
                          &anterior_preheader))
        return 0;
    if (lazo->paso_constante > 0)
        limite_seguro = (int64_t)INT32_MAX - desplazamiento;
    else
        limite_seguro = (int64_t)INT32_MIN - desplazamiento;
    if (limite_seguro < INT32_MIN || limite_seguro > INT32_MAX)
        return 0;

    n_cuerpo = contar_antes(lazo->condicion->next, lazo->ultima);
    if (n_cuerpo <= 0) return 0;
    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        if (i->next == lazo->ultima) {
            anterior_retorno = i;
            break;
        }
        if (i == lazo->ultima) break;
    }
    if (anterior_retorno == NULL) return 0;
    cuerpo_ultima = anterior_retorno;

    copia_resto = copiar_region(lazo->primera, lazo->ultima, &ultima_resto);
    if (copia_resto == NULL || copia_resto->op != TAC_LABEL ||
        ultima_resto == NULL)
        return 0;
    nombre_cabecera_resto = duplicar(copia_resto->result);

    nombre_desplazamiento = tac_new_temp();
    nombre_extremo = tac_new_temp();
    nombre_seguro = tac_new_temp();
    nombre_prueba_segura = tac_new_temp();
    nombre_guardia = tac_new_temp();

    TACInst *const_desplazamiento =
        nueva_instruccion(TAC_CONST, nombre_desplazamiento, NULL, NULL);
    const_desplazamiento->valor = (long)desplazamiento;
    anexar_instruccion(&constantes, &cola_constantes, const_desplazamiento);
    anexar_instruccion(&guardas, &cola_guardas,
        nueva_instruccion(TAC_ADD, nombre_extremo, lazo->contador,
                          nombre_desplazamiento));

    TACInst *const_seguro =
        nueva_instruccion(TAC_CONST, nombre_seguro, NULL, NULL);
    const_seguro->valor = (long)limite_seguro;
    anexar_instruccion(&constantes, &cola_constantes, const_seguro);
    anexar_instruccion(&guardas, &cola_guardas,
        nueva_instruccion(lazo->paso_constante > 0 ? TAC_LE : TAC_GE,
                          nombre_prueba_segura, lazo->contador, nombre_seguro));

    insertar_en_preheader(tac, ultima_preheader, anterior_preheader,
                          constantes, cola_constantes);

    free(lazo->comparacion_contador->arg1);
    lazo->comparacion_contador->arg1 = duplicar(nombre_extremo);
    instruccion_and = nueva_instruccion(TAC_AND, nombre_guardia,
                                        nombre_prueba_segura,
                                        lazo->comparacion_contador->result);
    free(lazo->condicion->arg1);
    lazo->condicion->arg1 = duplicar(nombre_guardia);
    free(lazo->condicion->result);
    lazo->condicion->result = duplicar(nombre_cabecera_resto);

    cola_guardas->next = lazo->etiqueta_cabecera->next;
    lazo->comparacion_contador->next = instruccion_and;
    instruccion_and->next = lazo->condicion;
    lazo->etiqueta_cabecera->next = guardas;

    for (int iteracion = 1; iteracion < factor; iteracion++) {
        TACInst *ultima_copia;
        TACInst *copia = copiar_region(lazo->condicion->next,
                                       cuerpo_ultima, &ultima_copia);
        if (copia == NULL || ultima_copia == NULL) return 0;
        if (copias_cuerpo == NULL) copias_cuerpo = copia;
        else cola_cuerpo->next = copia;
        cola_cuerpo = ultima_copia;
    }
    if (copias_cuerpo != NULL) {
        cola_cuerpo->next = lazo->ultima;
        if (anterior_retorno == lazo->condicion)
            lazo->condicion->next = copias_cuerpo;
        else
            anterior_retorno->next = copias_cuerpo;
    }

    TACInst *despues = lazo->ultima->next;
    lazo->ultima->next = copia_resto;
    enlazar(tac, despues, copia_resto);

    free(nombre_desplazamiento);
    free(nombre_extremo);
    free(nombre_seguro);
    free(nombre_prueba_segura);
    free(nombre_guardia);
    free(nombre_cabecera_resto);
    return 1;
}

static int en_condicion_cabecera(const TACInst *i, const Lazo *lazo) {
    for (TACInst *c = lazo->etiqueta_cabecera->next;
         c != NULL; c = c->next) {
        if (c == i) return 1;
        if (c == lazo->condicion) break;
    }
    return 0;
}

static int condicion_total_segura(TACList *tac, const Lazo *lazo) {
    for (TACInst *i = lazo->etiqueta_cabecera->next; i != NULL; i = i->next) {
        if (i == lazo->condicion) break;
        TACEfecto e;
        viv_efecto(i, &e);
        if (e.def == NULL || !tac_es_temporal(e.def))
            return 0;
        switch (i->op) {
            case TAC_CONST: case TAC_ASSIGN:
            case TAC_ADD: case TAC_SUB: case TAC_MUL:
            case TAC_AND: case TAC_OR: case TAC_XOR:
            case TAC_SHL: case TAC_SHR: case TAC_USHR:
            case TAC_EQ: case TAC_NE: case TAC_LT: case TAC_LE:
            case TAC_GT: case TAC_GE:
            case TAC_NEG: case TAC_BITNOT: case TAC_NOT:
                break;
            default:
                return 0;
        }
        for (TACInst *f = inicio_funcion(tac, lazo->primera);
             f != NULL; f = f->next) {
            TACEfecto uso;
            viv_efecto(f, &uso);
            for (int u = 0; u < uso.n_usos; u++)
                if (uso.usos[u] != NULL &&
                    strcmp(uso.usos[u], e.def) == 0 &&
                    !en_condicion_cabecera(f, lazo))
                    return 0;
            if (f->op == TAC_FUNC_END) break;
        }
    }
    return 1;
}

static void quitar_condicion_cabecera(TACList *tac, const Lazo *lazo) {
    TACInst *i = lazo->etiqueta_cabecera->next;
    TACInst *despues = lazo->condicion->next;
    lazo->etiqueta_cabecera->next = despues;
    while (i != despues) {
        TACInst *sig = i->next;
        if (tac->tail == i) tac->tail = lazo->etiqueta_cabecera;
        free(i->result);
        free(i->arg1);
        free(i->arg2);
        free(i);
        i = sig;
    }
}

static int contador_se_lee_despues(TACInst *ultima, const char *contador) {
    for (TACInst *i = ultima->next; i != NULL; i = i->next) {
        TACEfecto e;
        viv_efecto(i, &e);
        for (int u = 0; u < e.n_usos; u++)
            if (e.usos[u] != NULL && strcmp(e.usos[u], contador) == 0)
                return 1;
        if (i->op == TAC_FUNC_END) break;
    }
    return 0;
}

static void parchear_retorno(TACInst *primera, TACInst *ultima,
                             const char *cabecera, const char *destino) {
    for (TACInst *i = primera; i != NULL; i = i->next) {
        if (i->op == TAC_GOTO && i->result != NULL &&
            strcmp(i->result, cabecera) == 0) {
            free(i->result);
            i->result = duplicar(destino);
        }
        if (i == ultima) break;
    }
}

static void retorno_a_caida(TACInst *retorno) {
    if (retorno == NULL || retorno->op != TAC_GOTO) return;
    free(retorno->result);
    retorno->result = NULL;
    retorno->op = TAC_NOP;
}

static void enlazar(TACList *tac, TACInst *despues, TACInst *copias) {
    if (copias == NULL) return;
    TACInst *ultima = copias;
    while (ultima->next != NULL) ultima = ultima->next;
    ultima->next = despues;
    if (despues == NULL) tac->tail = ultima;
}

static void quitar_nops(TACList *tac) {
    TACInst *anterior = NULL;
    TACInst *i = tac->head;

    while (i != NULL) {
        TACInst *siguiente = i->next;
        if (i->op == TAC_NOP) {
            if (anterior == NULL) tac->head = siguiente;
            else anterior->next = siguiente;
            if (tac->tail == i) tac->tail = anterior;
            free(i->result);
            free(i->arg1);
            free(i->arg2);
            free(i);
        } else {
            anterior = i;
        }
        i = siguiente;
    }
}

static void quitar_etiquetas_no_referenciadas(TACList *tac) {
    TACInst *anterior = NULL;
    TACInst *i = tac->head;

    while (i != NULL) {
        TACInst *siguiente = i->next;
        bool referenciada = false;
        if (i->op == TAC_LABEL) {
            for (TACInst *j = tac->head; j != NULL; j = j->next) {
                if ((j->op == TAC_GOTO || j->op == TAC_IF_FALSE ||
                     j->op == TAC_IF_TRUE) &&
                    j->result != NULL && i->result != NULL &&
                    strcmp(j->result, i->result) == 0) {
                    referenciada = true;
                    break;
                }
            }
        }

        if (i->op == TAC_LABEL && !referenciada) {
            if (anterior == NULL) tac->head = siguiente;
            else anterior->next = siguiente;
            if (tac->tail == i) tac->tail = anterior;
            free(i->result);
            free(i->arg1);
            free(i->arg2);
            free(i);
        } else {
            anterior = i;
        }
        i = siguiente;
    }
}

static int expandir_lazo(TACList *tac, const Lazo *lazo, int factor,
                         int total_estatico) {
    int n_region = contar_region(lazo);
    TACInst **originales = reservar((size_t)n_region * sizeof(TACInst *));
    int n_originales = 0;
    for (TACInst *i = lazo->primera; i != NULL; i = i->next) {
        originales[n_originales++] = i;
        if (i == lazo->ultima) break;
    }

    TACInst *despues = lazo->ultima->next;
    TACInst *lista_copias = NULL, *cola_copias = NULL;
    char **cabeceras_copia = reservar((size_t)(factor > 1 ? factor - 1 : 1) *
                                      sizeof(char *));
    for (int i = 0; i < factor - 1; i++)
        cabeceras_copia[i] = tac_new_label();

    for (int iteracion = 1; iteracion < factor; iteracion++) {
        Mapeo *temps = NULL, *etiquetas = NULL;
        int n_temps = 0, cap_temps = 0, n_etiquetas = 0, cap_etiquetas = 0;
        for (int i = 0; i < n_originales; i++) {
            TACInst *inst = originales[i];
            if (total_estatico && en_condicion_cabecera(inst, lazo))
                continue;
            if (inst->op == TAC_LABEL) {
                char *label = strcmp(inst->result, lazo->nombre_cabecera) == 0
                    ? duplicar(cabeceras_copia[iteracion - 1]) : tac_new_label();
                agregar_mapeo(&etiquetas, &n_etiquetas, &cap_etiquetas,
                              inst->result, label);
            }
            TACEfecto efecto;
            viv_efecto(inst, &efecto);
            int ya_mapeado = 0;
            for (int t = 0; t < n_temps; t++)
                if (efecto.def != NULL &&
                    strcmp(temps[t].nombre, efecto.def) == 0) ya_mapeado = 1;
            if (efecto.def != NULL && tac_es_temporal(efecto.def) && !ya_mapeado)
                agregar_mapeo(&temps, &n_temps, &cap_temps,
                              efecto.def, tac_new_temp());
        }

        TACInst *copia_primera = NULL, *copia_ultima = NULL;
        for (int i = 0; i < n_originales; i++) {
            TACInst *origen = originales[i];
            if (total_estatico && en_condicion_cabecera(origen, lazo))
                continue;
            TACInst *copia = copiar_instruccion(origen, temps, n_temps,
                                                etiquetas, n_etiquetas);
            if (total_estatico && iteracion + 1 == factor &&
                origen == lazo->actualizacion_contador &&
                !contador_se_lee_despues(lazo->ultima, lazo->contador)) {
                copia->linea = 0;
                copia->columna = 0;
            }
            if (copia_primera == NULL) copia_primera = copia;
            else copia_ultima->next = copia;
            copia_ultima = copia;
        }
        const char *destino;
        if (iteracion + 1 < factor)
            destino = cabeceras_copia[iteracion];
        else if (total_estatico)
            destino = lazo->salida;
        else
            destino = lazo->nombre_cabecera;
        parchear_retorno(copia_primera, copia_ultima,
                         cabeceras_copia[iteracion - 1], destino);
        if (total_estatico || iteracion + 1 < factor)
            retorno_a_caida(copia_ultima);
        if (lista_copias == NULL) lista_copias = copia_primera;
        else cola_copias->next = copia_primera;
        cola_copias = copia_ultima;
        liberar_mapeos(temps, n_temps);
        liberar_mapeos(etiquetas, n_etiquetas);
    }

    if (factor == 1) {
        if (total_estatico)
            parchear_retorno(lazo->primera, lazo->ultima,
                             lazo->nombre_cabecera, lazo->salida);
    } else {
        parchear_retorno(lazo->primera, lazo->ultima,
                         lazo->nombre_cabecera, cabeceras_copia[0]);
    }

    if (total_estatico || factor > 1)
        retorno_a_caida(lazo->ultima);

    if (total_estatico && factor == 1 && lazo->actualizacion_contador != NULL &&
        !contador_se_lee_despues(lazo->ultima, lazo->contador)) {
        lazo->actualizacion_contador->linea = 0;
        lazo->actualizacion_contador->columna = 0;
    }
    if (total_estatico) quitar_condicion_cabecera(tac, lazo);
    if (lista_copias != NULL) lazo->ultima->next = lista_copias;
    enlazar(tac, despues, lista_copias);
    if (lista_copias == NULL && despues == NULL) tac->tail = lazo->ultima;
    for (int i = 0; i < factor - 1; i++) free(cabeceras_copia[i]);
    free(cabeceras_copia);
    free(originales);
    return 1;
}

int unroll_aplicar(TACList *tac, int factor) {
    GrafoFlujo *cfg;
    Lazo *lazos = NULL;
    int n_lazos, transformados = 0;

    if (tac == NULL || tac->head == NULL || factor == 1) return 0;
    cfg = cfg_construir(tac);
    if (cfg == NULL) return 0;
    n_lazos = reunir_lazos(tac, cfg, &lazos);

    for (int l = 0; l < n_lazos; l++) {
        Lazo *lazo = &lazos[l];
        int tamano = contar_region(lazo);
        int elegido = factor > 0 ? factor : factor_heuristico(lazo, tamano);
        int total_estatico = 0;
        int usar_grupos = 0;
        int cuerpo = lazo->puede_agrupar
            ? contar_antes(lazo->condicion->next, lazo->ultima) : 0;
        if (elegido <= 0) continue;

        if (factor == 0 && lazo->trip_conocido && lazo->trip_count <= 8)
            total_estatico = 1;
        else if (lazo->trip_conocido && lazo->trip_count <= elegido)
            total_estatico = 1;
        if (total_estatico) elegido = (int)lazo->trip_count;
        if (elegido < 1) continue;

        usar_grupos = !total_estatico && lazo->puede_agrupar &&
                      elegido > 1 && ganancia_grupos(elegido) > 0;
        int64_t salto_estimado = usar_grupos
            ? ((int64_t)elegido * cuerpo + 1) * COSTO_BUNDLE_ESTIMADO
            : (int64_t)elegido * tamano * COSTO_BUNDLE_ESTIMADO;
        if (elegido > 1 && salto_estimado > LIMITE_BUNDLES_SALTO) {
            if (factor > 0) continue;
            while (elegido > 1) {
                elegido--;
                usar_grupos = !total_estatico && lazo->puede_agrupar &&
                              elegido > 1 &&
                              ganancia_grupos(elegido) > 0;
                salto_estimado = usar_grupos
                    ? ((int64_t)elegido * cuerpo + 1) *
                          COSTO_BUNDLE_ESTIMADO
                    : (int64_t)elegido * tamano * COSTO_BUNDLE_ESTIMADO;
                if (salto_estimado <= LIMITE_BUNDLES_SALTO) break;
            }
            total_estatico = 0;
        }
        if (total_estatico && !condicion_total_segura(tac, lazo)) {
            total_estatico = 0;
            if (elegido == 1) continue;
        }

        usar_grupos = !total_estatico && lazo->puede_agrupar &&
                      elegido > 1 && ganancia_grupos(elegido) > 0;
        int64_t base = contar_tac(tac);
        int64_t nuevos = usar_grupos
            ? base + (int64_t)(elegido - 1) * cuerpo + tamano +
                      COSTO_GUARDA_GRUPOS + COSTO_INICIALIZACION_GUARDA
            : base + (int64_t)(elegido - 1) * tamano;
        if (nuevos * COSTO_BUNDLE_ESTIMADO > LIMITE_BUNDLES_IMEM) {
            if (factor == 0) {
                while (elegido > 1) {
                    elegido--;
                    usar_grupos = !total_estatico && lazo->puede_agrupar &&
                                  elegido > 1 &&
                                  ganancia_grupos(elegido) > 0;
                    nuevos = usar_grupos
                        ? base + (int64_t)(elegido - 1) * cuerpo + tamano +
                              COSTO_GUARDA_GRUPOS +
                              COSTO_INICIALIZACION_GUARDA
                        : base + (int64_t)(elegido - 1) * tamano;
                    if (nuevos * COSTO_BUNDLE_ESTIMADO <=
                        LIMITE_BUNDLES_IMEM)
                        break;
                }
                if (nuevos * COSTO_BUNDLE_ESTIMADO >
                    LIMITE_BUNDLES_IMEM)
                    continue;
                total_estatico = 0;
            } else {
                continue;
            }
        }
        if (elegido == 1 && !total_estatico) continue;
        if (usar_grupos)
            transformados += expandir_lazo_agrupado(tac, lazo, elegido);
        else
            transformados += expandir_lazo(tac, lazo, elegido, total_estatico);
    }

    quitar_nops(tac);
    quitar_etiquetas_no_referenciadas(tac);
    for (int i = 0; i < n_lazos; i++) {
        free(lazos[i].nombre_cabecera);
        free(lazos[i].salida);
        free(lazos[i].contador);
    }
    free(lazos);
    cfg_liberar(cfg);
    return transformados;
}
