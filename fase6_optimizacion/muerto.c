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
#include <limits.h>
#include <stdint.h>
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

static int linea_tiene_efectos(const GrafoFuncion *fn, int linea) {
    for (TACInst *i = fn->inicio; i != NULL; i = i->next) {
        if (i->op == TAC_FUNC_END) break;
        if (i->linea != linea) continue;

        TACEfecto e;
        viv_efecto(i, &e);
        if (e.efecto) return 1;
    }
    return 0;
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
                if (e.def != NULL && !tac_es_temporal(e.def)) {
                    const char *nombre = tac_nombre_fuente(e.def);
                    if (e.efecto)
                        diag_advertencia("W010", orden[p]->linea,
                                         orden[p]->columna, (int)strlen(nombre),
                                         "a '%s': se elimina el almacenamiento; "
                                         "la operacion se conserva", nombre);
                    else if (linea_tiene_efectos(vf->fn, orden[p]->linea))
                        diag_advertencia("W010", orden[p]->linea,
                                         orden[p]->columna, (int)strlen(nombre),
                                         "a '%s': se elimina el almacenamiento; "
                                         "se conservan efectos de esta linea",
                                         nombre);
                    else
                        diag_advertencia("W010", orden[p]->linea,
                                         orden[p]->columna, (int)strlen(nombre),
                                         "a '%s' se le asigna un valor que nunca se "
                                         "lee: la asignacion se elimina", nombre);
                }
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

typedef struct {
    const char *nombre;
    int instruccion;
} ReferenciaDef;

static int comparar_referencias_def(const void *a, const void *b) {
    const ReferenciaDef *ra = a, *rb = b;
    int orden = strcmp(ra->nombre, rb->nombre);
    if (orden != 0) return orden;
    return (ra->instruccion > rb->instruccion) -
           (ra->instruccion < rb->instruccion);
}

static int primera_referencia_def(const ReferenciaDef *defs, int n,
                                  const char *nombre) {
    int bajo = 0, alto = n;
    while (bajo < alto) {
        int medio = bajo + (alto - bajo) / 2;
        if (strcmp(defs[medio].nombre, nombre) < 0) bajo = medio + 1;
        else alto = medio;
    }
    return bajo;
}

static const TACInst *definicion_en_bloque(const Bloque *bloque,
                                           const TACInst *hasta,
                                           const char *nombre) {
    const TACInst *definicion = NULL;
    for (TACInst *i = bloque->primera; i != NULL && i != hasta; i = i->next) {
        TACEfecto e;
        viv_efecto(i, &e);
        if (e.def != NULL && strcmp(e.def, nombre) == 0)
            definicion = i;
        if (i == bloque->ultima) break;
    }
    return definicion;
}

static int valor_constante_en_bloque(const Bloque *bloque,
                                     const TACInst *hasta,
                                     const char *nombre, int profundidad,
                                     int64_t *valor) {
    const TACInst *definicion;
    if (nombre == NULL || profundidad > 8) return 0;
    definicion = definicion_en_bloque(bloque, hasta, nombre);
    if (definicion == NULL) return 0;
    if (definicion->op == TAC_CONST) {
        *valor = definicion->valor;
        return 1;
    }
    if (definicion->op == TAC_ASSIGN)
        return valor_constante_en_bloque(bloque, definicion,
                                         definicion->arg1, profundidad + 1,
                                         valor);
    return 0;
}

static int iteraciones_lazo_constante(TACOp comparacion, int64_t inicio,
                                      int64_t limite, int64_t paso,
                                      int64_t *iteraciones) {
    int64_t magnitud, distancia, n;
    if (inicio < INT32_MIN || inicio > INT32_MAX ||
        limite < INT32_MIN || limite > INT32_MAX ||
        paso < INT32_MIN || paso > INT32_MAX || paso == 0)
        return 0;
    magnitud = paso > 0 ? paso : -paso;
    if (comparacion == TAC_LT && paso > 0) {
        if (inicio >= limite) n = 0;
        else {
            distancia = limite - inicio;
            n = (distancia + magnitud - 1) / magnitud;
        }
    } else if (comparacion == TAC_LE && paso > 0) {
        if (inicio > limite) n = 0;
        else {
            distancia = limite - inicio;
            n = distancia / magnitud + 1;
        }
    } else if (comparacion == TAC_GT && paso < 0) {
        if (inicio <= limite) n = 0;
        else {
            distancia = inicio - limite;
            n = (distancia + magnitud - 1) / magnitud;
        }
    } else if (comparacion == TAC_GE && paso < 0) {
        if (inicio < limite) n = 0;
        else {
            distancia = inicio - limite;
            n = distancia / magnitud + 1;
        }
    } else {
        return 0;
    }
    if (inicio + n * paso < INT32_MIN ||
        inicio + n * paso > INT32_MAX)
        return 0;
    *iteraciones = n;
    return 1;
}

static int bloque_sucesor(const Bloque *bloque, int sucesor) {
    for (int i = 0; i < bloque->n_suc; i++)
        if (bloque->sucesores[i] == sucesor) return 1;
    return 0;
}

static int indice_etiqueta(const GrafoFuncion *fn, const char *nombre) {
    for (int i = 0; i < fn->n_bloques; i++)
        if (fn->bloques[i].etiqueta != NULL &&
            strcmp(fn->bloques[i].etiqueta, nombre) == 0)
            return i;
    return -1;
}

static int lazo_finito_sin_efecto(const GrafoFuncion *fn,
                                  const VivacidadFuncion *vf,
                                  int cabecera, int *cuerpo, int *salida) {
    const Bloque *b = &fn->bloques[cabecera];
    TACInst *condicion = NULL, *comparador = NULL, *actualizacion = NULL;
    TACInst *paso_inst = NULL, *salto_vuelta;
    const char *contador;
    int preheader = -1, bloque_salida = -1, bloque_cuerpo = -1;
    int definiciones_contador = 0;
    int64_t inicio, limite, paso, iteraciones;

    if (b->etiqueta == NULL || b->fin != FIN_CONDICIONAL ||
        b->n_suc != 2 || b->n_pred != 2)
        return 0;
    for (TACInst *i = b->primera; i != NULL; i = i->next) {
        if (i->op == TAC_IF_FALSE) {
            if (condicion != NULL) return 0;
            condicion = i;
        } else if (i->op == TAC_IF_TRUE || i->op == TAC_GOTO ||
                   i->op == TAC_CALL || i->op == TAC_TAILCALL ||
                   i->op == TAC_RET || i->op == TAC_RET_VAL ||
                   i->op == TAC_HALT) {
            return 0;
        }
        if (i == b->ultima) break;
    }
    if (condicion == NULL || condicion != b->ultima ||
        condicion->arg1 == NULL || condicion->result == NULL)
        return 0;
    bloque_salida = indice_etiqueta(fn, condicion->result);
    if (bloque_salida < 0 ||
        !bloque_sucesor(b, bloque_salida))
        return 0;

    for (int i = 0; i < b->n_suc; i++) {
        int candidato = b->sucesores[i];
        if (candidato != bloque_salida) bloque_cuerpo = candidato;
    }
    if (bloque_cuerpo < 0 || bloque_cuerpo == bloque_salida)
        return 0;
    const Bloque *bc = &fn->bloques[bloque_cuerpo];
    if (bc->fin != FIN_SALTO || bc->n_suc != 1 || bc->n_pred != 1 ||
        !bloque_sucesor(bc, cabecera))
        return 0;
    salto_vuelta = bc->ultima;
    if (salto_vuelta == NULL || salto_vuelta->op != TAC_GOTO ||
        salto_vuelta->result == NULL ||
        strcmp(salto_vuelta->result, b->etiqueta) != 0)
        return 0;

    for (int i = 0; i < b->n_pred; i++) {
        int candidato = b->predecesores[i];
        if (candidato != bloque_cuerpo) preheader = candidato;
    }
    if (preheader < 0 || preheader == cabecera ||
        fn->bloques[preheader].profundidad_ciclo != 0 ||
        fn->bloques[preheader].n_suc != 1 ||
        !bloque_sucesor(&fn->bloques[preheader], cabecera))
        return 0;

    TACEfecto efecto_condicion;
    viv_efecto(condicion, &efecto_condicion);
    comparador = (TACInst *)definicion_en_bloque(
        b, condicion, condicion->arg1);
    if (comparador == NULL || comparador->arg1 == NULL ||
        comparador->arg2 == NULL ||
        (comparador->op != TAC_LT && comparador->op != TAC_LE &&
         comparador->op != TAC_GT && comparador->op != TAC_GE))
        return 0;
    contador = comparador->arg1;
    if (viv_intocable(vf, contador) ||
        !valor_constante_en_bloque(&fn->bloques[preheader],
                                   b->primera, contador, 0, &inicio) ||
        !valor_constante_en_bloque(b, comparador,
                                   comparador->arg2, 0, &limite))
        return 0;

    for (TACInst *i = bc->primera; i != NULL; i = i->next) {
        TACEfecto e;
        viv_efecto(i, &e);
        if (e.efecto && i != salto_vuelta) return 0;
        if (e.def != NULL) {
            if (viv_intocable(vf, e.def) ||
                viv_viva_a_la_entrada(vf, bloque_salida, e.def))
                return 0;
            if (strcmp(e.def, contador) == 0) {
                definiciones_contador++;
                actualizacion = i;
            }
            if (strcmp(e.def, comparador->arg2) == 0) return 0;
        }
        if (i == bc->ultima) break;
    }
    for (TACInst *i = b->primera; i != NULL; i = i->next) {
        TACEfecto e;
        viv_efecto(i, &e);
        if (e.efecto && i != condicion &&
            !(i == b->primera && i->op == TAC_LABEL))
            return 0;
        if (e.def != NULL) {
            if (viv_intocable(vf, e.def) ||
                viv_viva_a_la_entrada(vf, bloque_salida, e.def))
                return 0;
            if (strcmp(e.def, contador) == 0) return 0;
            if (strcmp(e.def, comparador->arg2) == 0 &&
                i != definicion_en_bloque(b, comparador,
                                          comparador->arg2))
                return 0;
        }
        if (i == b->ultima) break;
    }
    if (definiciones_contador != 1 || actualizacion == NULL ||
        actualizacion->op != TAC_ASSIGN || actualizacion->arg1 == NULL)
        return 0;
    paso_inst = (TACInst *)definicion_en_bloque(
        bc, actualizacion, actualizacion->arg1);
    if (paso_inst == NULL ||
        (paso_inst->op != TAC_ADD && paso_inst->op != TAC_SUB))
        return 0;
    if (paso_inst->arg1 != NULL &&
        strcmp(paso_inst->arg1, contador) == 0) {
        if (!valor_constante_en_bloque(bc, paso_inst, paso_inst->arg2, 0,
                                       &paso))
            return 0;
        if (paso_inst->op == TAC_SUB) paso = -paso;
    } else if (paso_inst->op == TAC_ADD && paso_inst->arg2 != NULL &&
               strcmp(paso_inst->arg2, contador) == 0) {
        if (!valor_constante_en_bloque(bc, paso_inst, paso_inst->arg1, 0,
                                       &paso))
            return 0;
    } else {
        return 0;
    }
    if (!iteraciones_lazo_constante(comparador->op, inicio, limite, paso,
                                    &iteraciones))
        return 0;

    *cuerpo = bloque_cuerpo;
    *salida = bloque_salida;
    (void)iteraciones;
    (void)efecto_condicion;
    return 1;
}

static int marcar_lazos_finitos_muertos(const GrafoFuncion *fn,
                                        const VivacidadFuncion *vf,
                                        TACInst ***condenadas, int *n_cond,
                                        int *cap_cond) {
    int agregadas = 0;
    for (int h = 0; h < fn->n_bloques; h++) {
        int cuerpo, salida;
        if (!lazo_finito_sin_efecto(fn, vf, h, &cuerpo, &salida))
            continue;
        int bloques[] = {h, cuerpo};
        for (size_t n = 0; n < sizeof(bloques) / sizeof(bloques[0]); n++) {
            const Bloque *b = &fn->bloques[bloques[n]];
            for (TACInst *i = b->primera; i != NULL; i = i->next) {
                if (*n_cond == *cap_cond) {
                    *cap_cond = *cap_cond ? *cap_cond * 2 : 32;
                    *condenadas = realloc(
                        *condenadas, (size_t)*cap_cond * sizeof(TACInst *));
                    if (*condenadas == NULL) {
                        fprintf(stderr, "novac: sin memoria\n");
                        exit(3);
                    }
                }
                (*condenadas)[(*n_cond)++] = i;
                agregadas++;
                if (i == b->ultima) break;
            }
        }
        (void)salida;
    }
    return agregadas;
}

/*
 * Marca desde los efectos hacia sus operandos. Una cadena que solo se
 * alimenta a si misma en un ciclo no tiene raiz y se elimina completa.
 * Para nombres mutables se marcan todas las definiciones de la funcion:
 * es conservador ante ramas y evita necesitar un analisis de reaching-defs.
 */
static int eliminar_ciclos_muertos(const GrafoFuncion *fn,
                                   const VivacidadFuncion *vf,
                                   TACInst ***condenadas, int *n_cond,
                                   int *cap_cond, ReporteMuerto *rep,
                                   int avisar) {
    TACInst **insts;
    ReferenciaDef *defs;
    unsigned char *vivas;
    int *trabajo;
    int n = 0, n_defs = 0, cabeza = 0, cola = 0, eliminadas = 0;

    for (TACInst *i = fn->inicio; i != NULL; i = i->next) {
        n++;
        if (i->op == TAC_FUNC_END) break;
    }
    if (n == 0) return 0;

    insts = reservar((size_t)n * sizeof(TACInst *));
    defs = reservar((size_t)n * sizeof(ReferenciaDef));
    vivas = reservar((size_t)n);
    trabajo = reservar((size_t)n * sizeof(int));

    int p = 0;
    for (TACInst *i = fn->inicio; i != NULL; i = i->next) {
        TACEfecto e;
        insts[p] = i;
        viv_efecto(i, &e);
        if (e.def != NULL)
            defs[n_defs++] = (ReferenciaDef){e.def, p};
        p++;
        if (i->op == TAC_FUNC_END) break;
    }
    qsort(defs, (size_t)n_defs, sizeof(ReferenciaDef),
          comparar_referencias_def);

    for (p = 0; p < n; p++) {
        TACEfecto e;
        viv_efecto(insts[p], &e);
        if (e.efecto || (e.def != NULL && viv_intocable(vf, e.def))) {
            vivas[p] = 1;
            trabajo[cola++] = p;
        }
    }

    while (cabeza < cola) {
        TACEfecto e;
        int j;
        p = trabajo[cabeza++];
        viv_efecto(insts[p], &e);
        for (j = 0; j < e.n_usos; j++) {
            const char *nombre = e.usos[j];
            int d = primera_referencia_def(defs, n_defs, nombre);
            while (d < n_defs && strcmp(defs[d].nombre, nombre) == 0) {
                int indice = defs[d++].instruccion;
                if (!vivas[indice]) {
                    vivas[indice] = 1;
                    trabajo[cola++] = indice;
                }
            }
        }
    }

    for (p = 0; p < n; p++) {
        TACEfecto e;
        if (vivas[p]) continue;
        viv_efecto(insts[p], &e);
        if (e.def == NULL || e.efecto) continue;

        if (avisar && insts[p]->linea > 0 && !tac_es_temporal(e.def)) {
            if (e.efecto)
                diag_advertencia("W010", insts[p]->linea,
                                 insts[p]->columna, (int)strlen(e.def),
                                 "a '%s': se elimina el almacenamiento; "
                                 "la operacion se conserva", e.def);
            else if (linea_tiene_efectos(fn, insts[p]->linea))
                diag_advertencia("W010", insts[p]->linea,
                                 insts[p]->columna, (int)strlen(e.def),
                                 "a '%s': se elimina el almacenamiento; "
                                 "se conservan efectos de esta linea",
                                 e.def);
            else
                diag_advertencia("W010", insts[p]->linea,
                                 insts[p]->columna, (int)strlen(e.def),
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
        (*condenadas)[(*n_cond)++] = insts[p];
        eliminadas++;
    }

    free(trabajo);
    free(vivas);
    free(defs);
    free(insts);
    if (rep != NULL) {
        rep->definiciones_muertas += eliminadas;
        rep->definiciones_sin_raiz += eliminadas;
    }
    return eliminadas;
}

typedef enum {
    PROP_DESCONOCIDO,
    PROP_CONSTANTE,
    PROP_COPIA
} EstadoPropagacion;

typedef struct {
    const char *nombre;
    const char *copia;
    int32_t constante;
    EstadoPropagacion estado;
} ValorPropagado;

typedef struct {
    ValorPropagado *valores;
    int n_valores;
    int capacidad;
} EntornoPropagacion;

typedef struct {
    const char *nombre;
    const char *copia;
    int32_t constante;
    int es_constante;
} ValorResuelto;

static int indice_valor(const EntornoPropagacion *env, const char *nombre) {
    for (int i = 0; i < env->n_valores; i++)
        if (strcmp(env->valores[i].nombre, nombre) == 0) return i;
    return -1;
}

static void invalidar_dependientes(EntornoPropagacion *env,
                                  const char *nombre) {
    unsigned char *invalidos;
    bool cambio;
    if (env->n_valores == 0) return;
    invalidos = reservar((size_t)env->n_valores);
    for (int i = 0; i < env->n_valores; i++) {
        ValorPropagado *v = &env->valores[i];
        if (strcmp(v->nombre, nombre) == 0 ||
            (v->estado == PROP_COPIA && v->copia != NULL &&
             strcmp(v->copia, nombre) == 0))
            invalidos[i] = 1;
    }
    do {
        cambio = false;
        for (int i = 0; i < env->n_valores; i++) {
            ValorPropagado *v = &env->valores[i];
            if (invalidos[i] || v->estado != PROP_COPIA || v->copia == NULL)
                continue;
            for (int j = 0; j < env->n_valores; j++) {
                if (invalidos[j] &&
                    strcmp(v->copia, env->valores[j].nombre) == 0) {
                    invalidos[i] = 1;
                    cambio = true;
                    break;
                }
            }
        }
    } while (cambio);
    for (int i = 0; i < env->n_valores; i++) {
        if (!invalidos[i]) continue;
        env->valores[i].estado = PROP_DESCONOCIDO;
        env->valores[i].copia = NULL;
    }
    free(invalidos);
}

static ValorPropagado *obtener_valor(EntornoPropagacion *env,
                                     const char *nombre) {
    int i = indice_valor(env, nombre);
    if (i >= 0) return &env->valores[i];
    if (env->n_valores == env->capacidad) {
        int nueva = env->capacidad ? env->capacidad * 2 : 16;
        ValorPropagado *p = realloc(env->valores,
                                    (size_t)nueva * sizeof(ValorPropagado));
        if (p == NULL) {
            fprintf(stderr, "novac: sin memoria\n");
            exit(3);
        }
        env->valores = p;
        env->capacidad = nueva;
    }
    ValorPropagado *v = &env->valores[env->n_valores++];
    *v = (ValorPropagado){nombre, NULL, 0, PROP_DESCONOCIDO};
    return v;
}

static void asignar_constante(EntornoPropagacion *env, const char *nombre,
                             int32_t constante) {
    invalidar_dependientes(env, nombre);
    ValorPropagado *v = obtener_valor(env, nombre);
    v->estado = PROP_CONSTANTE;
    v->constante = constante;
    v->copia = NULL;
}

static void asignar_copia(EntornoPropagacion *env, const char *nombre,
                          const char *copia) {
    invalidar_dependientes(env, nombre);
    ValorPropagado *v = obtener_valor(env, nombre);
    v->estado = PROP_COPIA;
    v->copia = copia;
}

static void asignar_desconocido(EntornoPropagacion *env,
                               const char *nombre) {
    invalidar_dependientes(env, nombre);
    ValorPropagado *v = obtener_valor(env, nombre);
    v->estado = PROP_DESCONOCIDO;
    v->copia = NULL;
}

static ValorResuelto resolver_valor(const EntornoPropagacion *env,
                                    const char *nombre) {
    ValorResuelto r = {nombre, NULL, 0, 0};
    for (int pasos = 0; pasos <= env->n_valores; pasos++) {
        int i = indice_valor(env, r.nombre);
        if (i < 0 || env->valores[i].estado == PROP_DESCONOCIDO)
            return r;
        if (env->valores[i].estado == PROP_CONSTANTE) {
            r.constante = env->valores[i].constante;
            r.es_constante = 1;
            return r;
        }
        if (env->valores[i].copia == NULL)
            return (ValorResuelto){nombre, NULL, 0, 0};
        r.nombre = env->valores[i].copia;
    }
    return (ValorResuelto){nombre, NULL, 0, 0};
}

static char *duplicar_nombre(const char *nombre) {
    size_t n = strlen(nombre) + 1;
    char *copia = malloc(n);
    if (copia == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }
    memcpy(copia, nombre, n);
    return copia;
}

static int reemplazar_operando(char **operando, const char *nombre,
                               ReporteMuerto *rep) {
    if (operando == NULL || *operando == NULL || nombre == NULL ||
        strcmp(*operando, nombre) == 0)
        return 0;
    free(*operando);
    *operando = duplicar_nombre(nombre);
    if (rep != NULL) rep->valores_propagados++;
    return 1;
}

static void convertir_a_constante(TACInst *i, int32_t valor) {
    free(i->arg1);
    free(i->arg2);
    i->arg1 = NULL;
    i->arg2 = NULL;
    i->op = TAC_CONST;
    i->valor = valor;
    i->aux = 0;
}

static int32_t desde_bits(uint32_t bits) {
    int32_t valor;
    memcpy(&valor, &bits, sizeof(valor));
    return valor;
}

static bool plegar_constante(TACOp op, int32_t a, int32_t b,
                             int32_t *resultado) {
    uint32_t ua = (uint32_t)a, ub = (uint32_t)b;
    switch (op) {
        case TAC_ADD: *resultado = desde_bits(ua + ub); return true;
        case TAC_SUB: *resultado = desde_bits(ua - ub); return true;
        case TAC_MUL: *resultado = desde_bits(ua * ub); return true;
        case TAC_AND: *resultado = desde_bits(ua & ub); return true;
        case TAC_OR:  *resultado = desde_bits(ua | ub); return true;
        case TAC_XOR: *resultado = desde_bits(ua ^ ub); return true;
        case TAC_SHL:
            if (b < 0 || b >= 32) return false;
            *resultado = desde_bits(ua << (unsigned)b);
            return true;
        case TAC_SHR:
            if (b < 0 || b >= 32) return false;
            if (b == 0 || a >= 0) *resultado = a >> (unsigned)b;
            else *resultado = desde_bits(
                (ua >> (unsigned)b) | (~UINT32_C(0) << (32u - (unsigned)b)));
            return true;
        case TAC_USHR:
            if (b < 0 || b >= 32) return false;
            *resultado = desde_bits(ua >> (unsigned)b);
            return true;
        case TAC_EQ: *resultado = a == b; return true;
        case TAC_NE: *resultado = a != b; return true;
        case TAC_LT: *resultado = a < b; return true;
        case TAC_LE: *resultado = a <= b; return true;
        case TAC_GT: *resultado = a > b; return true;
        case TAC_GE: *resultado = a >= b; return true;
        case TAC_NEG: *resultado = desde_bits(0u - ua); return true;
        case TAC_BITNOT: *resultado = desde_bits(~ua); return true;
        case TAC_NOT: *resultado = (a == 0); return true;
        default: return false;
    }
}

static void reemplazar_resultado_constante(TACInst *i, int32_t valor,
                                           EntornoPropagacion *env) {
    convertir_a_constante(i, valor);
    if (i->result != NULL) asignar_constante(env, i->result, valor);
}

static TACInst *crear_constante_antes(TACList *tac, TACInst *anterior,
                                      TACInst *i, int32_t valor) {
    TACInst *constante = calloc(1, sizeof(TACInst));
    if (constante == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }
    constante->op = TAC_CONST;
    constante->result = tac_new_temp();
    constante->valor = valor;
    constante->linea = i->linea;
    constante->columna = i->columna;
    constante->next = i;
    if (anterior == NULL) tac->head = constante;
    else anterior->next = constante;
    return constante;
}

static bool potencia_dos_positiva(int32_t valor, int *exponente) {
    uint32_t n = (uint32_t)valor;
    if (valor <= 1 || (n & (n - 1)) != 0) return false;
    int k = 0;
    while ((n >>= 1) != 0) k++;
    *exponente = k;
    return true;
}

static bool es_operacion_binaria_pura(TACOp op) {
    switch (op) {
        case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR: case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR:
        case TAC_EQ: case TAC_NE: case TAC_LT:
        case TAC_LE: case TAC_GT: case TAC_GE:
            return true;
        default:
            return false;
    }
}

static bool es_operacion_unaria_pura(TACOp op) {
    return op == TAC_NEG || op == TAC_BITNOT || op == TAC_NOT;
}

static void propagar_copia(char **operando, EntornoPropagacion *env,
                           ReporteMuerto *rep, int *cambios) {
    if (operando == NULL || *operando == NULL) return;
    ValorResuelto valor = resolver_valor(env, *operando);
    if (!valor.es_constante &&
        reemplazar_operando(operando, valor.nombre, rep))
        (*cambios)++;
}

/*
 * Propagacion de constantes/copias y plegado local a cada bloque. El entorno
 * se descarta en etiquetas, saltos, llamadas y escrituras por memoria; no se
 * propagan valores a traves de un punto donde puedan cambiar o converger.
 */
static int propagar_tac(TACList *tac, ReporteMuerto *rep) {
    EntornoPropagacion env = {0};
    TACInst *anterior = NULL, *i = tac->head;
    int cambios = 0;

    while (i != NULL) {
        TACInst *siguiente = i->next;
        if (i->op == TAC_FUNC_BEGIN || i->op == TAC_FUNC_END ||
            i->op == TAC_LABEL)
            env.n_valores = 0;

        if (i->op == TAC_CONST && i->result != NULL) {
            asignar_constante(&env, i->result, (int32_t)i->valor);
        } else if (i->op == TAC_ASSIGN && i->result != NULL &&
                   i->arg1 != NULL) {
            ValorResuelto valor = resolver_valor(&env, i->arg1);
            if (valor.es_constante) {
                reemplazar_resultado_constante(i, valor.constante, &env);
                if (rep != NULL) rep->valores_propagados++;
                cambios++;
            } else {
                if (reemplazar_operando(&i->arg1, valor.nombre, rep))
                    cambios++;
                if (strcmp(i->result, valor.nombre) == 0)
                    asignar_desconocido(&env, i->result);
                else
                    asignar_copia(&env, i->result, valor.nombre);
            }
        } else if (es_operacion_binaria_pura(i->op) &&
                   i->result != NULL && i->arg1 != NULL && i->arg2 != NULL) {
            ValorResuelto a = resolver_valor(&env, i->arg1);
            ValorResuelto b = resolver_valor(&env, i->arg2);
            int32_t resultado;
            if (a.es_constante && b.es_constante &&
                plegar_constante(i->op, a.constante, b.constante, &resultado)) {
                reemplazar_resultado_constante(i, resultado, &env);
                if (rep != NULL) rep->constantes_plegadas++;
                cambios++;
            } else {
                if (!a.es_constante &&
                    reemplazar_operando(&i->arg1, a.nombre, rep))
                    cambios++;
                if (!b.es_constante &&
                    reemplazar_operando(&i->arg2, b.nombre, rep))
                    cambios++;

                int exponente;
                const char *variable = NULL;
                if (i->op == TAC_MUL && !a.es_constante && b.es_constante &&
                    potencia_dos_positiva(b.constante, &exponente))
                    variable = a.nombre;
                else if (i->op == TAC_MUL && a.es_constante && !b.es_constante &&
                         potencia_dos_positiva(a.constante, &exponente))
                    variable = b.nombre;
                if (variable != NULL) {
                    TACInst *constante = crear_constante_antes(
                        tac, anterior, i, exponente);
                    char *variable_copia = duplicar_nombre(variable);
                    free(i->arg1);
                    free(i->arg2);
                    i->op = TAC_SHL;
                    i->arg1 = variable_copia;
                    i->arg2 = duplicar_nombre(constante->result);
                    asignar_constante(&env, constante->result, exponente);
                    if (rep != NULL) rep->reducciones_fuerza++;
                    cambios++;
                }
                asignar_desconocido(&env, i->result);
            }
        } else if (es_operacion_unaria_pura(i->op) &&
                   i->result != NULL && i->arg1 != NULL) {
            ValorResuelto a = resolver_valor(&env, i->arg1);
            int32_t resultado;
            if (a.es_constante &&
                plegar_constante(i->op, a.constante, 0, &resultado)) {
                reemplazar_resultado_constante(i, resultado, &env);
                if (rep != NULL) rep->constantes_plegadas++;
                cambios++;
            } else {
                if (!a.es_constante &&
                    reemplazar_operando(&i->arg1, a.nombre, rep))
                    cambios++;
                asignar_desconocido(&env, i->result);
            }
        } else {
            if (i->op != TAC_CALL && i->op != TAC_TAILCALL &&
                i->op != TAC_STR) {
                propagar_copia(&i->arg1, &env, rep, &cambios);
                propagar_copia(&i->arg2, &env, rep, &cambios);
            }
            TACEfecto efecto;
            viv_efecto(i, &efecto);
            if (efecto.def != NULL)
                asignar_desconocido(&env, efecto.def);
        }

        switch (i->op) {
            case TAC_FUNC_BEGIN: case TAC_FUNC_END: case TAC_LABEL:
            case TAC_GOTO: case TAC_IF_FALSE: case TAC_IF_TRUE:
            case TAC_CALL: case TAC_TAILCALL: case TAC_RET: case TAC_RET_VAL:
            case TAC_STORE: case TAC_ADDR: case TAC_AUTHW:
            case TAC_VAULT_LOGIN: case TAC_VAULT_LOGOUT: case TAC_KSETW:
            case TAC_FEISTEL: case TAC_FEISTEL_DECRYPT: case TAC_HALT:
                env.n_valores = 0;
                break;
            default:
                break;
        }

        anterior = i;
        i = siguiente;
    }
    free(env.valores);
    return cambios;
}

/* ------------------------------------------------------------- interfaz */

int muerto_eliminar(TACList *tac, ReporteMuerto *rep, int avisar, int nivel_opt) {
    int cambio_total = 0;
    (void)nivel_opt;

    if (rep != NULL) memset(rep, 0, sizeof(*rep));
    if (tac == NULL || tac->head == NULL) return 0;
    if (rep != NULL) {
        rep->inst_antes = contar_instrucciones(tac);
    }

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
        int ciclos_eliminados = 0;
        /*
         * El CFG y la vivacidad conservan punteros a las instrucciones que se
         * acaban de barrer. Dejar que esta ronda termine y reconstruirlos antes
         * de marcar ciclos evita recorrer memoria liberada; el punto fijo
         * volvera a ejecutar el marcado de raices sobre la lista actualizada.
         */
        if (n_cond == 0) {
            TACInst **ciclos = NULL;
            int n_ciclos = 0, cap_ciclos = 0;
            for (f = 0; f < v->n_funciones; f++)
                ciclos_eliminados += marcar_lazos_finitos_muertos(
                    v->funciones[f].fn, &v->funciones[f], &ciclos,
                    &n_ciclos, &cap_ciclos);
            if (n_ciclos > 0) {
                barrer(tac, ciclos, n_ciclos);
            } else {
                for (f = 0; f < v->n_funciones; f++) {
                TACInst **ciclos = NULL;
                int n_raices = 0, cap_raices = 0;
                ciclos_eliminados += eliminar_ciclos_muertos(
                    v->funciones[f].fn, &v->funciones[f], &ciclos,
                    &n_raices, &cap_raices, &ronda, avisar);
                if (n_raices > 0) barrer(tac, ciclos, n_raices);
                free(ciclos);
                }
            }
            free(ciclos);
        }
        viv_liberar(v);
        cfg_liberar(g);
        int cambios_prop = propagar_tac(tac, &ronda);

        if (rep != NULL) {
            rep->rondas++;
            rep->bloques_eliminados     += ronda.bloques_eliminados;
            rep->inst_de_bloques        += ronda.inst_de_bloques;
            rep->definiciones_muertas   += ronda.definiciones_muertas;
            rep->resultados_descartados += ronda.resultados_descartados;
            rep->definiciones_sin_raiz += ronda.definiciones_sin_raiz;
            rep->constantes_plegadas       += ronda.constantes_plegadas;
            rep->valores_propagados        += ronda.valores_propagados;
            rep->reducciones_fuerza        += ronda.reducciones_fuerza;
        }

        if (n_cond == 0 && ronda.resultados_descartados == 0 &&
            ciclos_eliminados == 0 && cambios_prop == 0)
            break;
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
    fprintf(out, "  definiciones sin raiz:             %d\n",
            rep->definiciones_sin_raiz);
    fprintf(out, "  constantes plegadas:               %d\n",
            rep->constantes_plegadas);
    fprintf(out, "  valores propagados:                %d\n",
            rep->valores_propagados);
    fprintf(out, "  reducciones de fuerza:             %d\n",
            rep->reducciones_fuerza);
    fprintf(out, "  bucles desplegados antes del DCE:  %d\n",
            rep->bucles_desplegados);
    fprintf(out, "  rondas hasta el punto fijo:        %d\n", rep->rondas);
}
