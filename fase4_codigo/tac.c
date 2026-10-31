/*
 * Generacion de codigo intermedio de tres direcciones desde el AST decorado.
 *
 * Nada de este archivo depende de CERBERO: produce el repertorio que el
 * documento promete sobre una maquina abstracta con registros virtuales
 * ilimitados. La traduccion al procesador la hace codegen.c.
 *
 * Decisiones que conviene tener a la vista al leerlo:
 *
 *  - Las comparaciones producen un valor 0 o 1, como dice el repertorio
 *    ("t = a <op> b"). No se fusionan con el salto; esa es una seleccion de
 *    instrucciones que corresponde a codegen.c si algun dia se hace.
 *  - 'et' y 'aut' evaluan en corto circuito, con etiquetas y saltos, porque
 *    es lo que promete el documento.
 *  - Los indices se linealizan aqui: m[i][j] se convierte en la expresion
 *    i*cols + j, y TAC_LOAD/TAC_STORE reciben un solo indice en elementos.
 *  - La verificacion de rango (TAC_CHECK) se emite en cada acceso, porque el
 *    documento dice que esta siempre activa.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tac.h"
#include "diag.h"

/* Codigos de DataType tal como los guarda la decoracion. */
#define T_INTEGER 0
#define T_VERITAS 1
#define T_TEXTUS  2
#define T_NIHIL   3

static int cont_temp = 0;
static int cont_label = 0;
static int cont_cadena = 0;

/* Pila de ciclos, para que rumpe y perge sepan a donde saltar. */
#define MAX_CICLOS 64
typedef struct { char *l_rumpe; char *l_perge; } Ciclo;
static Ciclo ciclos[MAX_CICLOS];
static int n_ciclos = 0;

static SymbolTable *tabla = NULL;
static const char *funcion_actual = NULL;
static bool cauda_actual = false;

/* --- Utilidades ------------------------------------------------------- */

static void sin_memoria(void) {
    fprintf(stderr, "novac: sin memoria en la fase 4\n");
    exit(3);
}

static char *dup_str(const char *s) {
    if (s == NULL) return NULL;
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d == NULL) sin_memoria();
    memcpy(d, s, n);
    return d;
}

void tac_reset_contadores(void) {
    cont_temp = 0;
    cont_label = 0;
    cont_cadena = 0;
    n_ciclos = 0;
}

char *tac_new_temp(void) {
    char *b = malloc(16);
    if (b == NULL) sin_memoria();
    snprintf(b, 16, "t%d", cont_temp++);
    return b;
}

char *tac_new_label(void) {
    char *b = malloc(16);
    if (b == NULL) sin_memoria();
    snprintf(b, 16, "L%d", cont_label++);
    return b;
}

bool tac_es_temporal(const char *nombre) {
    if (nombre == NULL || nombre[0] != 't') return false;
    for (const char *p = nombre + 1; *p; p++)
        if (*p < '0' || *p > '9') return false;
    return nombre[1] != '\0';
}

TACList *tac_create_list(void) {
    TACList *l = calloc(1, sizeof(TACList));
    if (l == NULL) sin_memoria();
    return l;
}

TACInst *tac_append(TACList *list, TACOp op, const char *res,
                    const char *a1, const char *a2) {
    if (list == NULL) return NULL;
    TACInst *i = calloc(1, sizeof(TACInst));
    if (i == NULL) sin_memoria();
    i->op = op;
    i->result = dup_str(res);
    i->arg1 = dup_str(a1);
    i->arg2 = dup_str(a2);

    if (list->tail == NULL) list->head = i;
    else list->tail->next = i;
    list->tail = i;
    return i;
}

void tac_concat(TACList *dest, TACList *src) {
    if (dest == NULL || src == NULL) return;
    if (src->head != NULL) {
        if (dest->tail == NULL) dest->head = src->head;
        else dest->tail->next = src->head;
        dest->tail = src->tail;
    }
    free(src);
}

void tac_free(TACList *list) {
    if (list == NULL) return;
    TACInst *i = list->head;
    while (i != NULL) {
        TACInst *sig = i->next;
        free(i->result);
        free(i->arg1);
        free(i->arg2);
        free(i);
        i = sig;
    }
    TACSimbolo *sm = list->simbolos;
    while (sm != NULL) {
        TACSimbolo *sig = sm->next;
        free(sm->nombre);
        free(sm->funcion);
        free(sm);
        sm = sig;
    }
    TACCadena *c = list->cadenas;
    while (c != NULL) {
        TACCadena *sig = c->next;
        free(c->etiqueta);
        free(c->texto);
        free(c);
        c = sig;
    }
    free(list);
}

/* Registra un literal de cadena y devuelve su etiqueta. */
static char *registrar_cadena(TACList *list, const char *texto) {
    TACCadena *c = calloc(1, sizeof(TACCadena));
    if (c == NULL) sin_memoria();
    char buf[24];
    snprintf(buf, sizeof(buf), "__str%d", cont_cadena++);
    c->etiqueta = dup_str(buf);
    c->texto = dup_str(texto ? texto : "");
    if (list->cadenas_fin == NULL) list->cadenas = c;
    else list->cadenas_fin->next = c;
    list->cadenas_fin = c;
    list->n_cadenas++;
    return dup_str(c->etiqueta);
}

/* Copia a la lista del TAC la decoracion de un local o parametro. */
static void registrar_simbolo(TACList *l, const char *nombre, const Decor *d,
                              int es_param, int posicion) {
    if (nombre == NULL || d == NULL) return;
    for (TACSimbolo *x = l->simbolos; x != NULL; x = x->next)
        if (strcmp(x->nombre, nombre) == 0 && funcion_actual != NULL &&
            x->funcion != NULL && strcmp(x->funcion, funcion_actual) == 0)
            return;                      /* ya esta: un bloque interno */

    TACSimbolo *s = calloc(1, sizeof(TACSimbolo));
    if (s == NULL) sin_memoria();
    s->nombre = dup_str(nombre);
    s->funcion = dup_str(funcion_actual ? funcion_actual : "global");
    s->es_param = es_param;
    s->posicion = posicion;
    s->offset = d->offset;
    s->size_bytes = d->size_bytes > 0 ? d->size_bytes : 4;
    s->dims = d->dims;
    s->filas = d->filas;
    s->cols = d->cols;
    s->abierto = d->abierto;
    s->tipo = d->tipo;
    if (l->simbolos_fin == NULL) l->simbolos = s;
    else l->simbolos_fin->next = s;
    l->simbolos_fin = s;
}

const TACSimbolo *tac_buscar_simbolo(const TACList *l, const char *funcion,
                                     const char *nombre) {
    if (l == NULL || nombre == NULL) return NULL;
    for (const TACSimbolo *x = l->simbolos; x != NULL; x = x->next) {
        if (strcmp(x->nombre, nombre) != 0) continue;
        if (funcion != NULL && x->funcion != NULL &&
            strcmp(x->funcion, funcion) != 0) continue;
        return x;
    }
    return NULL;
}

static Nodo *buscar_hijo(Nodo *n, TipoNodo t) {
    if (n == NULL) return NULL;
    for (Nodo *c = n->hijo; c != NULL; c = c->sig)
        if (c->tipo == t) return c;
    return NULL;
}

/*
 * Copia la posicion del nodo a la instruccion y la devuelve, para encadenar
 * sobre tac_append. La fase 4 usa linea y columna para anotar el ensamblador
 * y el listado de bundles: sin la columna no se distinguen dos operaciones de
 * una misma linea, que es justo lo que pasa en 'a = b * c + d'.
 */
static TACInst *con_pos(TACInst *i, const Nodo *n) {
    if (i != NULL && n != NULL) { i->linea = n->linea; i->columna = n->columna; }
    return i;
}

/* Materializa una constante entera en un temporal. */
static char *const_en_temp(TACList *l, long v, int linea, int columna) {
    char *t = tac_new_temp();
    TACInst *i = tac_append(l, TAC_CONST, t, NULL, NULL);
    i->valor = v;
    i->linea = linea;
    i->columna = columna;
    return t;
}

/* La ranura y la ronda de la boveda son campos inmediatos del opcode, asi
 * que tienen que conocerse en compilacion. */
static bool valor_constante(Nodo *e, long *out) {
    if (e == NULL) return false;
    if (e->tipo == NODO_ENTERO) { *out = e->valor; return true; }
    if (e->tipo == NODO_BOOLEANO) { *out = e->valor != 0; return true; }
    if (e->tipo == NODO_IDENT && e->dec != NULL &&
        e->dec->clase == DEC_CONST && e->dec->tiene_valor) {
        *out = e->dec->valor;
        return true;
    }
    return false;
}

static char *generar_expr(Nodo *e, TACList *l);
static void generar_sent(Nodo *s, TACList *l);

/* --- Arreglos --------------------------------------------------------- */

/*
 * Resuelve un NODO_INDICE en el nombre del arreglo base y el indice lineal.
 * Para m[i][j] con m de cols columnas, el indice lineal es i*cols + j, que es
 * exactamente el orden por filas que documenta el lenguaje. Emite ademas la
 * verificacion de rango de cada dimension.
 */
static char *indice_lineal(Nodo *idx_nodo, TACList *l, Nodo **nodo_base) {
    Nodo *base = idx_nodo->hijo;
    Nodo *idx = base ? base->sig : NULL;

    if (base != NULL && base->tipo == NODO_INDICE) {
        /* Acceso de dos dimensiones: el hijo ya resuelve la fila. */
        Nodo *nb = NULL;
        char *fila = indice_lineal(base, l, &nb);
        *nodo_base = nb;

        char *col = generar_expr(idx, l);

        /*
         * El paso de una fila es el tamano de la segunda dimension. Si el
         * arreglo se declaro con dimensiones conocidas es una constante; si
         * es un parametro de dimensiones abiertas hay que leerlo del
         * descriptor, que es justo lo que longitudo consulta.
         */
        int cols = (nb != NULL && nb->dec != NULL) ? nb->dec->cols : 0;
        bool abierto = (nb != NULL && nb->dec != NULL && nb->dec->abierto);
        char *paso;
        if (abierto || cols <= 0) {
            paso = tac_new_temp();
            TACInst *ln = tac_append(l, TAC_LEN, paso,
                                     nb != NULL ? nb->texto : NULL, NULL);
            ln->aux = 1;
            con_pos(ln, idx);
        } else {
            paso = const_en_temp(l, cols, idx->linea, idx->columna);
        }

        /* El paso es tambien el limite de la columna. */
        con_pos(tac_append(l, TAC_CHECK, NULL, col, paso), idx);

        char *t1 = tac_new_temp();
        con_pos(tac_append(l, TAC_MUL, t1, fila, paso), idx);
        char *t2 = tac_new_temp();
        con_pos(tac_append(l, TAC_ADD, t2, t1, col), idx);

        free(fila); free(col); free(paso); free(t1);
        return t2;
    }

    /* Una sola dimension: el hijo es el identificador del arreglo. */
    if (base == NULL || base->tipo != NODO_IDENT) {
        *nodo_base = NULL;
        return generar_expr(idx, l);
    }
    *nodo_base = base;

    char *i0 = generar_expr(idx, l);

    /* Limite de la primera dimension. */
    int filas = base->dec ? base->dec->filas : 0;
    bool abierto = (base->dec != NULL && base->dec->abierto);
    char *lim = NULL;
    if (abierto || filas <= 0) {
        lim = tac_new_temp();
        TACInst *ln = tac_append(l, TAC_LEN, lim, base->texto, NULL);
        ln->aux = 0;
        con_pos(ln, idx);
    } else {
        lim = const_en_temp(l, filas, idx->linea, idx->columna);
    }
    con_pos(tac_append(l, TAC_CHECK, NULL, i0, lim), idx);
    free(lim);
    return i0;
}

/* --- Expresiones ------------------------------------------------------ */

static TACOp op_binario(const char *o) {
    if (strcmp(o, "+") == 0)   return TAC_ADD;
    if (strcmp(o, "-") == 0)   return TAC_SUB;
    if (strcmp(o, "*") == 0)   return TAC_MUL;
    if (strcmp(o, "/") == 0)   return TAC_DIV;
    if (strcmp(o, "%") == 0)   return TAC_MOD;
    if (strcmp(o, "&") == 0)   return TAC_AND;
    if (strcmp(o, "|") == 0)   return TAC_OR;
    if (strcmp(o, "^") == 0)   return TAC_XOR;
    if (strcmp(o, "<<") == 0)  return TAC_SHL;
    if (strcmp(o, ">>") == 0)  return TAC_SHR;
    if (strcmp(o, ">>>") == 0) return TAC_USHR;
    if (strcmp(o, "==") == 0)  return TAC_EQ;
    if (strcmp(o, "!=") == 0)  return TAC_NE;
    if (strcmp(o, "<") == 0)   return TAC_LT;
    if (strcmp(o, "<=") == 0)  return TAC_LE;
    if (strcmp(o, ">") == 0)   return TAC_GT;
    if (strcmp(o, ">=") == 0)  return TAC_GE;
    return TAC_NOP;
}

/* 'et' y 'aut' en corto circuito: el segundo operando solo se evalua si hace
 * falta, y el resultado queda en un temporal con 0 o 1. */
static char *generar_logico(Nodo *e, TACList *l) {
    bool es_et = (strcmp(e->texto, "et") == 0);
    Nodo *ni = e->hijo;
    Nodo *nd = ni ? ni->sig : NULL;

    char *res = tac_new_temp();
    char *l_corto = tac_new_label();
    char *l_fin = tac_new_label();

    char *a = generar_expr(ni, l);
    con_pos(tac_append(l, TAC_ASSIGN, res, a, NULL), e);
    free(a);
    /* En 'et' se corta si es falso; en 'aut' se corta si es verdadero. */
    con_pos(tac_append(l, es_et ? TAC_IF_FALSE : TAC_IF_TRUE, l_corto, res, NULL), e);

    char *b = generar_expr(nd, l);
    con_pos(tac_append(l, TAC_ASSIGN, res, b, NULL), e);
    free(b);

    con_pos(tac_append(l, TAC_GOTO, l_fin, NULL, NULL), e);
    con_pos(tac_append(l, TAC_LABEL, l_corto, NULL, NULL), e);
    TACInst *k = tac_append(l, TAC_CONST, res, NULL, NULL);
    k->valor = es_et ? 0 : 1;
    con_pos(k, e);
    con_pos(tac_append(l, TAC_LABEL, l_fin, NULL, NULL), e);

    free(l_corto);
    free(l_fin);
    return res;
}

/* Emite los 'param' de un argumento. Un arreglo viaja por referencia: se
 * pasan su direccion base y los tamanos de sus dimensiones. */
static int emitir_param(Nodo *arg, TACList *l, int pos) {
    if (arg != NULL && arg->dec != NULL && arg->dec->dims > 0 &&
        arg->tipo == NODO_IDENT) {
        char *base = tac_new_temp();
        con_pos(tac_append(l, TAC_ADDR, base, arg->texto, NULL), arg);
        tac_append(l, TAC_PARAM, NULL, base, NULL)->aux = pos++;
        free(base);

        for (int d = 0; d < arg->dec->dims; d++) {
            char *t;
            if (arg->dec->abierto) {
                t = tac_new_temp();
                TACInst *ln = tac_append(l, TAC_LEN, t, arg->texto, NULL);
                ln->aux = d;
                con_pos(ln, arg);
            } else {
                long v = (d == 0) ? arg->dec->filas : arg->dec->cols;
                t = const_en_temp(l, v, arg->linea, arg->columna);
            }
            tac_append(l, TAC_PARAM, NULL, t, NULL)->aux = pos++;
            free(t);
        }
        return pos;
    }

    char *v = generar_expr(arg, l);
    tac_append(l, TAC_PARAM, NULL, v, NULL)->aux = pos++;
    free(v);
    return pos;
}

/* Intrinsecas de la boveda: no son llamadas normales, se traducen a las
 * instrucciones del slot criptografico. */
static char *generar_intrinseca(Nodo *e, TACList *l, const char *nombre) {
    Nodo *args = buscar_hijo(e, NODO_ARGUMENTOS);
    Nodo *a1 = args ? args->hijo : NULL;
    Nodo *a2 = a1 ? a1->sig : NULL;
    Nodo *a3 = a2 ? a2->sig : NULL;

    if (strcmp(nombre, "longitudo") == 0) {
        char *t = tac_new_temp();
        if (a1 != NULL && a1->tipo == NODO_IDENT) {
            TACInst *i = tac_append(l, TAC_LEN, t, a1->texto, NULL);
            i->aux = 0;
            con_pos(i, e);
        } else if (a1 != NULL && a1->tipo == NODO_INDICE) {
            /* longitudo(m[0]) es el tamano de la segunda dimension. */
            Nodo *b = a1->hijo;
            const char *nb = (b && b->tipo == NODO_IDENT) ? b->texto : NULL;
            TACInst *i = tac_append(l, TAC_LEN, t, nb, NULL);
            i->aux = 1;
            con_pos(i, e);
        } else {
            char *v = generar_expr(a1, l);
            TACInst *i = tac_append(l, TAC_LEN, t, v, NULL);
            i->aux = 0;
            con_pos(i, e);
            free(v);
        }
        return t;
    }

    if (strcmp(nombre, "ingredere") == 0) {
        /* El registro de desafio son 128 bits: cuatro authw y luego login.
         * La clave que recibe Nova ocupa la primera palabra; las otras tres
         * van en cero, que es la convencion acordada con CE 4301. */
        char *clave = generar_expr(a1, l);
        tac_append(l, TAC_AUTHW, NULL, clave, NULL)->aux = 0;
        char *cero = const_en_temp(l, 0, e->linea, e->columna);
        for (int w = 1; w < 4; w++)
            tac_append(l, TAC_AUTHW, NULL, cero, NULL)->aux = w;
        free(cero);
        free(clave);
        con_pos(tac_append(l, TAC_VAULT_LOGIN, NULL, NULL, NULL), e);
        /* Devuelve verum si AUTH quedo en 1. */
        char *t = tac_new_temp();
        char *l_si = tac_new_label();
        char *l_fin = tac_new_label();
        con_pos(tac_append(l, TAC_IF_TRUE, l_si, "__auth", NULL), e);
        TACInst *k0 = tac_append(l, TAC_CONST, t, NULL, NULL);
        k0->valor = 0;
        tac_append(l, TAC_GOTO, l_fin, NULL, NULL);
        tac_append(l, TAC_LABEL, l_si, NULL, NULL);
        TACInst *k1 = tac_append(l, TAC_CONST, t, NULL, NULL);
        k1->valor = 1;
        tac_append(l, TAC_LABEL, l_fin, NULL, NULL);
        free(l_si);
        free(l_fin);
        return t;
    }

    if (strcmp(nombre, "exi") == 0) {
        con_pos(tac_append(l, TAC_VAULT_LOGOUT, NULL, NULL, NULL), e);
        return NULL;
    }

    if (strcmp(nombre, "custodi") == 0) {
        long ranura = 0;
        if (!valor_constante(a1, &ranura)) {
            diag_error("E319", a1 ? a1->linea : e->linea,
                       a1 ? a1->columna : e->columna, 1,
                       "la ranura de 'custodi' debe ser una constante: es un "
                       "campo inmediato de la instruccion ksetw");
            return NULL;
        }
        Nodo *k = a2;
        for (int w = 0; w < 4 && k != NULL; w++, k = k->sig) {
            char *v = generar_expr(k, l);
            TACInst *i = tac_append(l, TAC_KSETW, NULL, NULL, v);
            i->valor = ranura;
            i->aux = w;
            con_pos(i, e);
            free(v);
        }
        return NULL;
    }

    if (strcmp(nombre, "feistel") == 0 || strcmp(nombre, "desfeistel") == 0) {
        /* Una ronda sobre el par (L,R); la ronda se codifica directamente
         * como inmediato en F4E o F4D. */
        long ranura = 0, ronda = 0;
        if (!valor_constante(a2, &ranura) || !valor_constante(a3, &ronda)) {
            diag_error("E319", e->linea, e->columna, 1,
                       "la ranura y la ronda de 'feistel' deben ser constantes: "
                       "son campos inmediatos de la instruccion f4e");
            return NULL;
        }
        char *bloque = NULL;
        if (a1 != NULL && a1->tipo == NODO_IDENT) {
            bloque = tac_new_temp();
            con_pos(tac_append(l, TAC_ADDR, bloque, a1->texto, NULL), e);
        } else {
            bloque = generar_expr(a1, l);
        }
        TACOp op = strcmp(nombre, "feistel") == 0
            ? TAC_FEISTEL : TAC_FEISTEL_DECRYPT;
        TACInst *i = tac_append(l, op, NULL, bloque, NULL);
        i->valor = ranura;
        i->aux = (int)ronda;
        con_pos(i, e);
        free(bloque);
        return NULL;
    }

    return NULL;  /* scribe y dic se manejan como llamadas normales */
}

static char *generar_llamada(Nodo *e, TACList *l) {
    const char *nombre = e->texto ? e->texto : "";

    /* Las intrinsecas de la boveda y longitudo no son llamadas de verdad. */
    if (e->modulo == NULL &&
        (strcmp(nombre, "longitudo") == 0 || strcmp(nombre, "ingredere") == 0 ||
         strcmp(nombre, "exi") == 0 || strcmp(nombre, "custodi") == 0 ||
         strcmp(nombre, "feistel") == 0 ||
         strcmp(nombre, "desfeistel") == 0)) {
        return generar_intrinseca(e, l, nombre);
    }

    Nodo *args = buscar_hijo(e, NODO_ARGUMENTOS);

    /* scribe y dic son variadicas: cada argumento se traduce, segun su tipo,
     * a una llamada monomorfica del soporte de ejecucion. Se resuelve antes
     * del camino generico para no evaluar los argumentos dos veces. */
    if (e->modulo == NULL &&
        (strcmp(nombre, "scribe") == 0 || strcmp(nombre, "dic") == 0)) {
        for (Nodo *a = args ? args->hijo : NULL; a != NULL; a = a->sig) {
            /* Un literal de cadena no lleva decoracion: su tipo es el nodo. */
            bool es_txt = (a->tipo == NODO_CADENA) ||
                          (a->dec != NULL && a->dec->tipo == T_TEXTUS);
            const char *rut = es_txt ? "__scribe_txt" : "__scribe_int";
            char *v = generar_expr(a, l);
            tac_append(l, TAC_PARAM, NULL, v, NULL)->aux = 1;
            TACInst *c = tac_append(l, TAC_CALL, NULL, rut, NULL);
            c->aux = 1;
            con_pos(c, e);
            free(v);
        }
        if (strcmp(nombre, "dic") == 0) {
            TACInst *c = tac_append(l, TAC_CALL, NULL, "__dic_fin", NULL);
            c->aux = 0;
            con_pos(c, e);
        }
        return NULL;
    }

    int pos = 1;
    for (Nodo *a = args ? args->hijo : NULL; a != NULL; a = a->sig)
        pos = emitir_param(a, l, pos);
    int palabras = pos - 1;

    /* Nombre decorado del modulo, como pide el documento: modulo$simbolo. */
    char destino[160];
    if (e->modulo != NULL) snprintf(destino, sizeof(destino), "%s$%s", e->modulo, nombre);
    else snprintf(destino, sizeof(destino), "%s", nombre);

    /* El temporal de retorno se reserva para llamadas con valor; la fase
     * semantica ya verifico la firma tras integrar los modulos. */
    /*
     * @cauda: una llamada recursiva en posicion de cola no apila un marco
     * nuevo. Los argumentos ya quedaron en los registros y en el area de
     * salida; la fase 4 solo tiene que reasignar los parametros y volver al
     * inicio del cuerpo. La fase 3 ya verifico con E315 que en una funcion
     * @cauda toda llamada recursiva esta en posicion de cola.
     */
    if (cauda_actual && e->modulo == NULL && funcion_actual != NULL &&
        strcmp(nombre, funcion_actual) == 0) {
        TACInst *tc = tac_append(l, TAC_TAILCALL, NULL, destino, NULL);
        tc->aux = palabras;
        con_pos(tc, e);
        return NULL;
    }

    int tipo_ret = e->dec ? e->dec->tipo : T_NIHIL;
    char *res = (e->modulo != NULL || tipo_ret != T_NIHIL) ? tac_new_temp() : NULL;
    TACInst *c = tac_append(l, TAC_CALL, res, destino, NULL);
    c->aux = palabras;
    con_pos(c, e);
    return res;
}

static char *generar_expr(Nodo *e, TACList *l) {
    if (e == NULL) return NULL;

    switch (e->tipo) {
        case NODO_ENTERO:
            return const_en_temp(l, e->valor, e->linea, e->columna);

        case NODO_BOOLEANO:
            return const_en_temp(l, e->valor != 0 ? 1 : 0, e->linea, e->columna);

        case NODO_CADENA: {
            char *etq = registrar_cadena(l, e->texto);
            char *t = tac_new_temp();
            con_pos(tac_append(l, TAC_STR, t, etq, NULL), e);
            free(etq);
            return t;
        }

        case NODO_IDENT: {
            /* Una constans se pliega: su valor es inmediato. */
            if (e->dec != NULL && e->dec->clase == DEC_CONST && e->dec->tiene_valor)
                return const_en_temp(l, e->dec->valor, e->linea, e->columna);
            if (e->modulo != NULL) {
                char buf[160];
                snprintf(buf, sizeof(buf), "%s$%s", e->modulo, e->texto);
                return dup_str(buf);
            }
            return dup_str(e->texto);
        }

        case NODO_INDICE: {
            Nodo *base = NULL;
            char *idx = indice_lineal(e, l, &base);
            char *t = tac_new_temp();
            con_pos(tac_append(l, TAC_LOAD, t, base ? base->texto : NULL, idx), e);
            free(idx);
            return t;
        }

        case NODO_BINARIO: {
            const char *o = e->texto ? e->texto : "+";
            if (strcmp(o, "et") == 0 || strcmp(o, "aut") == 0)
                return generar_logico(e, l);

            TACOp op = op_binario(o);
            if (op == TAC_NOP) {
                diag_error("E303", e->linea, e->columna, 1,
                           "operador '%s' sin traduccion en la fase 4", o);
                return const_en_temp(l, 0, e->linea, e->columna);
            }
            Nodo *ni = e->hijo;
            Nodo *nd = ni ? ni->sig : NULL;
            char *a = generar_expr(ni, l);
            char *b = generar_expr(nd, l);
            char *t = tac_new_temp();
            con_pos(tac_append(l, op, t, a, b), e);
            free(a);
            free(b);
            return t;
        }

        case NODO_UNARIO: {
            const char *o = e->texto ? e->texto : "-";
            char *a = generar_expr(e->hijo, l);
            char *t = tac_new_temp();
            TACOp op = TAC_NEG;
            if (strcmp(o, "~") == 0) op = TAC_BITNOT;
            else if (strcmp(o, "non") == 0) op = TAC_NOT;
            con_pos(tac_append(l, op, t, a, NULL), e);
            free(a);
            return t;
        }

        case NODO_LLAMADA:
            return generar_llamada(e, l);

        default:
            return NULL;
    }
}

/* --- Sentencias ------------------------------------------------------- */

/* Inicializacion de un arreglo con lista de valores: se escribe elemento por
 * elemento, en orden por filas. */
static int generar_lista(Nodo *lista, TACList *l, const char *nombre, int pos) {
    for (Nodo *x = lista->hijo; x != NULL; x = x->sig) {
        if (x->tipo == NODO_LISTA_VALORES) {
            pos = generar_lista(x, l, nombre, pos);
        } else {
            char *v = generar_expr(x, l);
            char *idx = const_en_temp(l, pos, x->linea, x->columna);
            con_pos(tac_append(l, TAC_STORE, (char *)nombre, idx, v), x);
            free(v);
            free(idx);
            pos++;
        }
    }
    return pos;
}

static void generar_bloque(Nodo *b, TACList *l) {
    if (b == NULL) return;
    if (b->tipo != NODO_BLOQUE) { generar_sent(b, l); return; }
    for (Nodo *s = b->hijo; s != NULL; s = s->sig) generar_sent(s, l);
}

static void generar_sent(Nodo *s, TACList *l) {
    if (s == NULL) return;

    switch (s->tipo) {
        case NODO_VARIABLE: {
            Nodo *tn = buscar_hijo(s, NODO_TIPO);
            Nodo *init = tn ? tn->sig : NULL;
            if (init == NULL) break;
            if (init->tipo == NODO_LISTA_VALORES) {
                generar_lista(init, l, s->texto, 0);
            } else {
                char *v = generar_expr(init, l);
                if (v != NULL) {
                    con_pos(tac_append(l, TAC_ASSIGN, s->texto, v, NULL), s);
                    free(v);
                }
            }
            break;
        }

        case NODO_CONSTANTE:
            /* Una constans local no ocupa memoria: su valor se pliega en los
             * usos, igual que una global. No hay nada que emitir. */
            break;

        case NODO_ASIGNACION: {
            Nodo *dest = s->hijo;
            Nodo *val = dest ? dest->sig : NULL;
            if (dest == NULL || val == NULL) break;

            if (dest->tipo == NODO_INDICE) {
                Nodo *base = NULL;
                char *idx = indice_lineal(dest, l, &base);
                char *v = generar_expr(val, l);
                con_pos(tac_append(l, TAC_STORE, base ? base->texto : NULL, idx, v), s);
                free(idx);
                free(v);
            } else {
                char *v = generar_expr(val, l);
                if (v != NULL) {
                    con_pos(tac_append(l, TAC_ASSIGN, dest->texto, v, NULL), s);
                    free(v);
                }
            }
            break;
        }

        case NODO_SI: {
            Nodo *cond = s->hijo;
            Nodo *entonces = cond ? cond->sig : NULL;
            Nodo *sino = entonces ? entonces->sig : NULL;

            char *c = generar_expr(cond, l);
            char *l_sino = tac_new_label();
            char *l_fin = sino ? tac_new_label() : NULL;

            con_pos(tac_append(l, TAC_IF_FALSE, l_sino, c, NULL), s);
            free(c);

            generar_bloque(entonces, l);
            if (sino != NULL) tac_append(l, TAC_GOTO, l_fin, NULL, NULL);

            tac_append(l, TAC_LABEL, l_sino, NULL, NULL);
            if (sino != NULL) {
                generar_bloque(sino, l);
                tac_append(l, TAC_LABEL, l_fin, NULL, NULL);
                free(l_fin);
            }
            free(l_sino);
            break;
        }

        case NODO_DUM: {
            Nodo *cond = s->hijo;
            Nodo *cuerpo = cond ? cond->sig : NULL;

            char *l_ini = tac_new_label();
            char *l_fin = tac_new_label();

            tac_append(l, TAC_LABEL, l_ini, NULL, NULL);
            char *c = generar_expr(cond, l);
            con_pos(tac_append(l, TAC_IF_FALSE, l_fin, c, NULL), s);
            free(c);

            if (n_ciclos < MAX_CICLOS) {
                ciclos[n_ciclos].l_rumpe = l_fin;
                ciclos[n_ciclos].l_perge = l_ini;
                n_ciclos++;
            }
            generar_bloque(cuerpo, l);
            if (n_ciclos > 0) n_ciclos--;

            tac_append(l, TAC_GOTO, l_ini, NULL, NULL);
            tac_append(l, TAC_LABEL, l_fin, NULL, NULL);
            free(l_ini);
            free(l_fin);
            break;
        }

        case NODO_PER: {
            /* Hijos: inicializacion, condicion, paso, cuerpo. */
            Nodo *init = s->hijo;
            Nodo *cond = init ? init->sig : NULL;
            Nodo *paso = cond ? cond->sig : NULL;
            Nodo *cuerpo = paso ? paso->sig : NULL;

            char *l_ini = tac_new_label();
            char *l_paso = tac_new_label();
            char *l_fin = tac_new_label();

            if (init != NULL) generar_sent(init, l);

            tac_append(l, TAC_LABEL, l_ini, NULL, NULL);
            char *c = generar_expr(cond, l);
            con_pos(tac_append(l, TAC_IF_FALSE, l_fin, c, NULL), s);
            free(c);

            /* perge salta al paso, no al principio: el contador debe avanzar. */
            if (n_ciclos < MAX_CICLOS) {
                ciclos[n_ciclos].l_rumpe = l_fin;
                ciclos[n_ciclos].l_perge = l_paso;
                n_ciclos++;
            }
            generar_bloque(cuerpo, l);
            if (n_ciclos > 0) n_ciclos--;

            tac_append(l, TAC_LABEL, l_paso, NULL, NULL);
            if (paso != NULL) generar_sent(paso, l);
            tac_append(l, TAC_GOTO, l_ini, NULL, NULL);
            tac_append(l, TAC_LABEL, l_fin, NULL, NULL);

            free(l_ini);
            free(l_paso);
            free(l_fin);
            break;
        }

        case NODO_RUMPE:
            if (n_ciclos > 0)
                con_pos(tac_append(l, TAC_GOTO, ciclos[n_ciclos - 1].l_rumpe, NULL, NULL), s);
            break;

        case NODO_PERGE:
            if (n_ciclos > 0)
                con_pos(tac_append(l, TAC_GOTO, ciclos[n_ciclos - 1].l_perge, NULL, NULL), s);
            break;

        case NODO_REDDE: {
            Nodo *expr = s->hijo;
            if (expr != NULL) {
                char *v = generar_expr(expr, l);
                /*
                 * 'redde f(...)' con f la propia funcion @cauda es la llamada
                 * de cola tipica: generar_llamada ya dejo un TAC_TAILCALL,
                 * que vuelve al inicio del cuerpo, asi que no hay valor que
                 * retornar aqui. El retorno real lo hace el redde que si
                 * termina la recursion, y su valor llega al llamador original
                 * porque el marco nunca se volvio a apilar.
                 */
                if (v == NULL && l->tail != NULL && l->tail->op == TAC_TAILCALL)
                    break;
                con_pos(tac_append(l, TAC_RET_VAL, NULL, v, NULL), s);
                free(v);
            } else {
                con_pos(tac_append(l, TAC_RET, NULL, NULL, NULL), s);
            }
            break;
        }

        case NODO_LLAMADA: {
            char *r = generar_llamada(s, l);
            free(r);   /* el valor se descarta: ya se advirtio con W005 */
            break;
        }

        case NODO_BLOQUE:
            generar_bloque(s, l);
            break;

        default:
            break;
    }
}

/* --- Funciones -------------------------------------------------------- */

/* Recorre el cuerpo anotando cada 'varia' que declara, con el
 * desplazamiento que ya calculo la fase 3. */
static void recolectar_locales(Nodo *n, TACList *l) {
    for (Nodo *c = n; c != NULL; c = c->sig) {
        if (c->tipo == NODO_VARIABLE && c->dec != NULL)
            registrar_simbolo(l, c->texto, c->dec, 0, 0);
        recolectar_locales(c->hijo, l);
    }
}

static void generar_funcion(Nodo *f, TACList *l) {
    const char *nombre = f->texto ? f->texto : "anonima";
    funcion_actual = nombre;
    cauda_actual = (f->dec != NULL && f->dec->es_cauda);
    con_pos(tac_append(l, TAC_FUNC_BEGIN, nombre, NULL, NULL), f);

    /* Primero los parametros, en orden y con su posicion de argumento:
     * un escalar ocupa una palabra, un arreglo su descriptor. */
    Nodo *ps = buscar_hijo(f, NODO_PARAMETROS);
    int pos = 1;
    for (Nodo *p = ps ? ps->hijo : NULL; p != NULL; p = p->sig) {
        if (p->tipo != NODO_PARAMETRO || p->dec == NULL) continue;
        registrar_simbolo(l, p->texto, p->dec, 1, pos);
        pos += (p->dec->size_bytes > 0 ? p->dec->size_bytes : 4) / 4;
    }

    Nodo *cuerpo = buscar_hijo(f, NODO_BLOQUE);
    recolectar_locales(cuerpo ? cuerpo->hijo : NULL, l);
    generar_bloque(cuerpo, l);

    /* Retorno implicito, solo si el cuerpo no termina ya en uno. La fase 3
     * garantiza que una funcion con tipo no se cae por el final. */
    if (l->tail == NULL || (l->tail->op != TAC_RET && l->tail->op != TAC_RET_VAL))
        con_pos(tac_append(l, TAC_RET, NULL, NULL, NULL), f);
    con_pos(tac_append(l, TAC_FUNC_END, nombre, NULL, NULL), f);
    funcion_actual = NULL;
    cauda_actual = false;
}

TACList *tac_generate_from_ast(Nodo *root, SymbolTable *st) {
    tabla = st;
    tac_reset_contadores();

    TACList *l = tac_create_list();
    if (root == NULL) return l;

    Nodo *globales = NULL;
    for (Nodo *c = root->hijo; c != NULL; c = c->sig)
        if (c->tipo == NODO_GLOBALES) globales = c;
    if (globales == NULL) return l;

    for (Nodo *g = globales->hijo; g != NULL; g = g->sig)
        if (g->tipo == NODO_FUNCION) generar_funcion(g, l);

    return l;
}

/* --- Salida legible --------------------------------------------------- */

const char *tac_op_nombre(TACOp op) {
    switch (op) {
        case TAC_NOP: return "nop";
        case TAC_ADD: return "+";   case TAC_SUB: return "-";
        case TAC_MUL: return "*";   case TAC_DIV: return "/";
        case TAC_MOD: return "%";
        case TAC_AND: return "&";   case TAC_OR: return "|";
        case TAC_XOR: return "^";
        case TAC_SHL: return "<<";  case TAC_SHR: return ">>";
        case TAC_USHR: return ">>>";
        case TAC_EQ: return "==";   case TAC_NE: return "!=";
        case TAC_LT: return "<";    case TAC_LE: return "<=";
        case TAC_GT: return ">";    case TAC_GE: return ">=";
        case TAC_NEG: return "-";   case TAC_BITNOT: return "~";
        case TAC_NOT: return "non";
        default: return "?";
    }
}

static bool es_binaria(TACOp op) {
    return (op >= TAC_ADD && op <= TAC_GE);
}

void tac_print(FILE *out, TACList *list) {
    if (list == NULL || out == NULL) return;

    fprintf(out, "=== Codigo intermedio de tres direcciones ===\n");
    for (TACInst *i = list->head; i != NULL; i = i->next) {
        if (es_binaria(i->op)) {
            fprintf(out, "    %s = %s %s %s\n", i->result, i->arg1,
                    tac_op_nombre(i->op), i->arg2);
            continue;
        }
        switch (i->op) {
            case TAC_NEG: case TAC_BITNOT: case TAC_NOT:
                fprintf(out, "    %s = %s %s\n", i->result,
                        tac_op_nombre(i->op), i->arg1); break;
            case TAC_ASSIGN:
                fprintf(out, "    %s = %s\n", i->result, i->arg1); break;
            case TAC_CONST:
                fprintf(out, "    %s = #%ld\n", i->result, i->valor); break;
            case TAC_STR:
                fprintf(out, "    %s = &%s\n", i->result, i->arg1); break;
            case TAC_LOAD:
                fprintf(out, "    %s = %s[%s]\n", i->result, i->arg1, i->arg2); break;
            case TAC_STORE:
                fprintf(out, "    %s[%s] = %s\n", i->result, i->arg1, i->arg2); break;
            case TAC_ADDR:
                fprintf(out, "    %s = &%s\n", i->result, i->arg1); break;
            case TAC_LEN:
                fprintf(out, "    %s = longitudo %s, dim %d\n", i->result, i->arg1, i->aux); break;
            case TAC_CHECK:
                fprintf(out, "    check %s, %s\n", i->arg1, i->arg2); break;
            case TAC_LABEL:
                fprintf(out, "%s:\n", i->result); break;
            case TAC_GOTO:
                fprintf(out, "    goto %s\n", i->result); break;
            case TAC_IF_FALSE:
                fprintf(out, "    ifFalse %s goto %s\n", i->arg1, i->result); break;
            case TAC_IF_TRUE:
                fprintf(out, "    ifTrue %s goto %s\n", i->arg1, i->result); break;
            case TAC_FUNC_BEGIN:
                fprintf(out, "\nfunctio %s:\n", i->result); break;
            case TAC_FUNC_END:
                fprintf(out, "fin %s\n", i->result); break;
            case TAC_PARAM:
                fprintf(out, "    param %s  (posicion %d)\n", i->arg1, i->aux); break;
            case TAC_CALL:
                if (i->result) fprintf(out, "    %s = call %s, %d\n", i->result, i->arg1, i->aux);
                else           fprintf(out, "    call %s, %d\n", i->arg1, i->aux);
                break;
            case TAC_TAILCALL:
                fprintf(out, "    tailcall %s, %d  (@cauda)\n", i->arg1, i->aux); break;
            case TAC_RET:
                fprintf(out, "    ret\n"); break;
            case TAC_RET_VAL:
                fprintf(out, "    ret %s\n", i->arg1); break;
            case TAC_AUTHW:
                fprintf(out, "    authw #%d, %s\n", i->aux, i->arg1); break;
            case TAC_VAULT_LOGIN:
                fprintf(out, "    vault.login\n"); break;
            case TAC_VAULT_LOGOUT:
                fprintf(out, "    vault.logout\n"); break;
            case TAC_KSETW:
                fprintf(out, "    vault.store #%ld, #%d, %s\n", i->valor, i->aux, i->arg2); break;
            case TAC_FEISTEL:
                fprintf(out, "    feistel %s, #%ld, #%d\n", i->arg1, i->valor, i->aux); break;
            case TAC_FEISTEL_DECRYPT:
                fprintf(out, "    desfeistel %s, #%ld, #%d\n", i->arg1, i->valor, i->aux); break;
            case TAC_HALT:
                fprintf(out, "    halt\n"); break;
            default:
                fprintf(out, "    nop\n"); break;
        }
    }
    if (list->n_cadenas > 0) {
        fprintf(out, "\n=== Literales de cadena ===\n");
        for (TACCadena *c = list->cadenas; c != NULL; c = c->next)
            fprintf(out, "  %-10s \"%s\"\n", c->etiqueta, c->texto);
    }
    (void)tabla;
}
