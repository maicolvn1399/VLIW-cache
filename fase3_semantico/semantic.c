/*
 * Analisis semantico de Nova. Codigos E301-E321 y advertencias W001-W007.
 *
 * Organizacion del archivo:
 *   1. Estado y utilidades
 *   2. Evaluador de expresiones constantes
 *   3. Lectura de tipos y dimensiones del AST
 *   4. Primera pasada: modulos, constantes globales y firmas de funciones
 *   5. Analisis de expresiones
 *   6. Analisis de sentencias
 *   7. Analisis de flujo (E309) y posicion de cola (E315)
 *   8. Segunda pasada y punto de entrada
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "semantic.h"
#include "diag.h"

/* ====================================================================== */
/* 1. Estado y utilidades                                                 */
/* ====================================================================== */

static SymbolTable *st = NULL;
static int loop_depth = 0;
static Symbol *func_actual = NULL;

#define MAX_ARGS 64

/*
 * Resultado de analizar una expresion. No basta con el DataType: los
 * arreglos obligan a arrastrar cuantas dimensiones quedan y, cuando se
 * conocen, sus tamanos, que es lo que permite verificar E307, E308 y E314.
 */
typedef struct {
    DataType tipo;
    int dims;        /* dimensiones que aun quedan por indexar */
    int rows;        /* tamano de la dimension actual, 0 si es abierta */
    int cols;        /* tamano de la siguiente, 0 si no aplica */
    bool abierto;    /* viene de un parametro de dimensiones abiertas */
    bool asignable;  /* es un designador (ident o indice), no un valor */
    Symbol *sym;     /* simbolo de respaldo, si lo hay */
} Info;

static Info info_de(DataType t, int dims) {
    Info i;
    memset(&i, 0, sizeof(i));
    i.tipo = t;
    i.dims = dims;
    return i;
}

static Info info_error(void) { return info_de(TYPE_ERROR, 0); }

/* Un tipo ya marcado como error no vuelve a reportarse: evita que un solo
 * identificador mal escrito genere una cascada de mensajes. */
static bool valido(Info i) { return i.tipo != TYPE_ERROR; }

/*
 * Deja en el nodo lo que la fase 4 necesita para generar codigo: la clase y
 * el tipo del nombre, sus dimensiones y, sobre todo, donde vive. Es el "AST
 * decorado" que promete el documento: sin esto la fase 4 no podria resolver
 * los nombres locales, porque sus ambitos ya se cerraron.
 */
static void decorar_simbolo(Nodo *n, const Symbol *s) {
    if (n == NULL || s == NULL) return;
    Decor *d = nodo_decorar(n);
    d->clase = (int)s->kind;
    d->tipo = (int)(s->kind == SYMBOL_FUNC ? s->return_type : s->type);
    d->dims = (s->kind == SYMBOL_FUNC) ? s->return_dims : s->dimensions;
    d->filas = s->rows;
    d->cols = s->cols;
    d->abierto = s->abierto ? 1 : 0;
    d->global = s->is_global ? 1 : 0;
    d->offset = (int)s->offset;
    d->size_bytes = s->size_bytes;
    d->valor = s->const_value;
    d->tiene_valor = s->has_const_value ? 1 : 0;
    d->marco = s->local_frame_size;
    d->n_params = s->param_count;
    d->privada = s->is_private ? 1 : 0;
    d->es_cauda = s->es_cauda ? 1 : 0;
}

static Nodo *buscar_hijo(Nodo *n, TipoNodo t) {
    if (n == NULL) return NULL;
    for (Nodo *c = n->hijo; c != NULL; c = c->sig)
        if (c->tipo == t) return c;
    return NULL;
}

static int largo_de(const char *s) {
    return (s != NULL && *s != '\0') ? (int)strlen(s) : 1;
}

/* Nombre legible de un tipo con sus dimensiones, para los mensajes. */
static const char *desc(char *buf, size_t n, Info i) {
    return tipo_con_dims(buf, n, i.tipo, i.dims);
}

/* Prototipos usados antes de su definicion. */
static Info analizar_expresion(Nodo *e);
static Info analizar_designador(Nodo *e);
static void analizar_sentencia(Nodo *s);
static void analizar_bloque(Nodo *b, bool nuevo_ambito);

/* ====================================================================== */
/* 2. Evaluador de expresiones constantes                                 */
/* ====================================================================== */

/*
 * Evalua en tiempo de compilacion. Hace falta para los tamanos de arreglo
 * (E318), los indices constantes fuera de rango (E308), la division entre
 * cero constante (E316) y los rangos de ranura y ronda de la boveda (E319).
 * Devuelve false si la expresion no es constante; no reporta nada.
 */
static bool eval_const(Nodo *e, long *out) {
    if (e == NULL) return false;

    switch (e->tipo) {
        case NODO_ENTERO:
            *out = e->valor;
            return true;

        case NODO_BOOLEANO:
            *out = e->valor;
            return true;

        case NODO_IDENT: {
            if (e->modulo != NULL) return false;   /* se resuelve al enlazar */
            Symbol *s = symtab_lookup(st, e->texto);
            if (s == NULL || s->kind != SYMBOL_CONST || !s->has_const_value)
                return false;
            *out = s->const_value;
            return true;
        }

        case NODO_UNARIO: {
            long v;
            if (!eval_const(e->hijo, &v)) return false;
            if (strcmp(e->texto, "-") == 0)   { *out = -v; return true; }
            if (strcmp(e->texto, "~") == 0)   { *out = ~v; return true; }
            if (strcmp(e->texto, "non") == 0) { *out = !v; return true; }
            return false;
        }

        case NODO_BINARIO: {
            long a, b;
            Nodo *izq = e->hijo;
            Nodo *der = izq ? izq->sig : NULL;
            if (!eval_const(izq, &a) || !eval_const(der, &b)) return false;
            const char *op = e->texto;
            if (strcmp(op, "+") == 0)  { *out = a + b;  return true; }
            if (strcmp(op, "-") == 0)  { *out = a - b;  return true; }
            if (strcmp(op, "*") == 0)  { *out = a * b;  return true; }
            if (strcmp(op, "/") == 0)  { if (b == 0) return false; *out = a / b; return true; }
            if (strcmp(op, "%") == 0)  { if (b == 0) return false; *out = a % b; return true; }
            if (strcmp(op, "&") == 0)  { *out = a & b;  return true; }
            if (strcmp(op, "|") == 0)  { *out = a | b;  return true; }
            if (strcmp(op, "^") == 0)  { *out = a ^ b;  return true; }
            if (strcmp(op, "<<") == 0) { *out = (long)((int32_t)a << (b & 31)); return true; }
            if (strcmp(op, ">>") == 0) { *out = (long)((int32_t)a >> (b & 31)); return true; }
            if (strcmp(op, ">>>") == 0) {
                *out = (long)(int32_t)((uint32_t)a >> (b & 31));
                return true;
            }
            if (strcmp(op, "==") == 0) { *out = (a == b); return true; }
            if (strcmp(op, "!=") == 0) { *out = (a != b); return true; }
            if (strcmp(op, "<") == 0)  { *out = (a <  b); return true; }
            if (strcmp(op, "<=") == 0) { *out = (a <= b); return true; }
            if (strcmp(op, ">") == 0)  { *out = (a >  b); return true; }
            if (strcmp(op, ">=") == 0) { *out = (a >= b); return true; }
            if (strcmp(op, "et") == 0) { *out = (a && b); return true; }
            if (strcmp(op, "aut") == 0) { *out = (a || b); return true; }
            return false;
        }

        default:
            return false;
    }
}

/* ====================================================================== */
/* 3. Lectura de tipos y dimensiones del AST                              */
/* ====================================================================== */

static DataType dtype_de(const char *nombre) {
    if (nombre == NULL) return TYPE_ERROR;
    if (strcmp(nombre, "integer") == 0) return TYPE_INTEGER;
    if (strcmp(nombre, "veritas") == 0) return TYPE_VERITAS;
    if (strcmp(nombre, "textus") == 0)  return TYPE_TEXTUS;
    if (strcmp(nombre, "nihil") == 0)   return TYPE_NIHIL;
    return TYPE_ERROR;
}

/*
 * Lee las dimensiones colgadas de un NODO_TIPO. Los tamanos deben ser
 * expresiones constantes enteras positivas (E318). Las dimensiones abiertas
 * (NODO_DIM_ABIERTA) solo llegan desde parametros, porque la gramatica no
 * las admite en otra parte.
 */
static void leer_dims(Nodo *tipo_nodo, int *dims, int *rows, int *cols, bool *abierto) {
    *dims = 0; *rows = 0; *cols = 0; *abierto = false;
    if (tipo_nodo == NULL) return;

    int n = 0;
    int tam[2] = {0, 0};
    for (Nodo *d = tipo_nodo->hijo; d != NULL && n < 2; d = d->sig) {
        if (d->tipo == NODO_DIM_ABIERTA) {
            *abierto = true;
            tam[n] = 0;
            n++;
        } else if (d->tipo == NODO_DIMENSION) {
            long v = 0;
            if (!eval_const(d->hijo, &v)) {
                diag_error("E318", d->hijo ? d->hijo->linea : d->linea,
                           d->hijo ? d->hijo->columna : d->columna, 1,
                           "el tamano de un arreglo debe ser una expresion constante entera");
                tam[n] = 1;
            } else if (v <= 0) {
                diag_error("E318", d->hijo->linea, d->hijo->columna, 1,
                           "el tamano de un arreglo debe ser positivo, no %ld", v);
                tam[n] = 1;
            } else if (v > 65535) {
                diag_error("E318", d->hijo->linea, d->hijo->columna, 1,
                           "el tamano de un arreglo (%ld) no cabe en la memoria de datos", v);
                tam[n] = 1;
            } else {
                tam[n] = (int)v;
            }
            n++;
        }
    }
    *dims = n;
    *rows = tam[0];
    *cols = tam[1];
}

/* ====================================================================== */
/* 4. Primera pasada                                                      */
/* ====================================================================== */

/* Nombre del modulo que corresponde a una ruta de importacion:
 * "lib/matriz.nv" -> "matriz". */
static void nombre_modulo(const char *ruta, char *buf, size_t n) {
    const char *base = ruta;
    for (const char *p = ruta; *p; p++)
        if (*p == '/' || *p == '\\') base = p + 1;

    size_t largo = strlen(base);
    if (largo > 3 && strcmp(base + largo - 3, ".nv") == 0) largo -= 3;
    if (largo >= n) largo = n - 1;
    memcpy(buf, base, largo);
    buf[largo] = '\0';
}

static bool identificador_valido(const char *s) {
    if (s == NULL || *s == '\0') return false;
    if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || *s == '_'))
        return false;
    for (const char *p = s + 1; *p; p++)
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '_'))
            return false;
    return true;
}

/* Registra los espacios de nombres importados. El enlazador integra las
 * declaraciones antes del analisis semantico y deja las llamadas resueltas. */
static void registrar_imports(Nodo *imports) {
    if (imports == NULL) return;

    for (Nodo *imp = imports->hijo; imp != NULL; imp = imp->sig) {
        if (imp->tipo != NODO_IMPORT) continue;

        Nodo *alias = buscar_hijo(imp, NODO_ALIAS);
        char nombre[128];
        if (alias != NULL) {
            snprintf(nombre, sizeof(nombre), "%s", alias->texto);
        } else {
            nombre_modulo(imp->texto ? imp->texto : "", nombre, sizeof(nombre));
            if (!identificador_valido(nombre)) {
                diag_error("E409", imp->linea, imp->columna,
                           largo_de(imp->texto),
                           "'%s' no da un nombre de modulo valido: usa 'ut <alias>'",
                           imp->texto ? imp->texto : "");
                continue;
            }
        }

        Symbol *previo = symtab_lookup_current_scope(st, nombre);
        if (previo != NULL && previo->kind == SYMBOL_MODULE) {
            diag_error("E402", imp->linea, imp->columna, largo_de(nombre),
                       "el espacio de nombres '%s' ya fue importado", nombre);
            continue;
        }
        if (previo != NULL) {
            diag_error("E302", imp->linea, imp->columna, largo_de(nombre),
                       "'%s' ya esta declarado en este ambito", nombre);
            continue;
        }
        symtab_insert_module(st, nombre, imp->linea, imp->columna);
    }
}

/* Constantes globales. Se registran antes que las funciones porque un
 * parametro puede usar una constante como tamano: integer[N][N]. */
static void declarar_constante(Nodo *node, bool global) {
    const char *name = node->texto;
    Nodo *tn = buscar_hijo(node, NODO_TIPO);
    DataType tipo = dtype_de(tn ? tn->texto : NULL);

    int dims, rows, cols;
    bool abierto;
    leer_dims(tn, &dims, &rows, &cols, &abierto);

    if (tipo == TYPE_NIHIL) {
        diag_error("E321", node->linea, node->columna, largo_de(name),
                   "'nihil' solo puede usarse como tipo de retorno");
        tipo = TYPE_ERROR;
    }
    if (dims > 0) {
        diag_error("E314", node->linea, node->columna, largo_de(name),
                   "una 'constans' no puede ser un arreglo");
        dims = 0;
    }

    if (symtab_lookup_current_scope(st, name) != NULL) {
        diag_error("E302", node->linea, node->columna, largo_de(name),
                   "'%s' ya esta declarado en este ambito", name);
        return;
    }
    if (!global) {
        Symbol *ext = symtab_lookup_exterior(st, name);
        if (ext != NULL && ext->kind != SYMBOL_FUNC && ext->kind != SYMBOL_MODULE)
            diag_advertencia("W002", node->linea, node->columna, largo_de(name),
                             "'%s' oculta la declaracion de la linea %d",
                             name, ext->line);
    }

    /* El inicializador es el hijo que sigue al tipo. */
    Nodo *init = (tn != NULL) ? tn->sig : NULL;
    long valor = 0;
    bool tiene_valor = false;

    if (init != NULL) {
        Info i = analizar_expresion(init);
        if (valido(i) && tipo != TYPE_ERROR && (i.tipo != tipo || i.dims != 0)) {
            char a[32], b[32];
            diag_error("E303", init->linea, init->columna, 1,
                       "no se puede inicializar una 'constans' de tipo '%s' con '%s'",
                       tipo_con_dims(b, sizeof(b), tipo, 0), desc(a, sizeof(a), i));
        } else if (tipo == TYPE_INTEGER || tipo == TYPE_VERITAS) {
            if (eval_const(init, &valor)) {
                tiene_valor = true;
            } else if (valido(i)) {
                diag_error("E303", init->linea, init->columna, 1,
                           "el valor de una 'constans' debe poder calcularse en compilacion");
            }
        }
    }

    Symbol *cs = symtab_insert_const(st, name, tipo, (int32_t)valor, tiene_valor,
                                     node->linea, node->columna);
    decorar_simbolo(node, cs);
}

/* Firma de una funcion: tipo de retorno, anotaciones, privatum y parametros. */
static void declarar_funcion(Nodo *node) {
    const char *name = node->texto;

    Nodo *tn = buscar_hijo(node, NODO_TIPO);
    DataType ret = dtype_de(tn ? tn->texto : NULL);
    int rdims, rrows, rcols;
    bool rabierto;
    leer_dims(tn, &rdims, &rrows, &rcols, &rabierto);

    if (rdims > 0) {
        diag_error("E314", tn->linea, tn->columna, largo_de(tn->texto),
                   "una funcion no puede retornar un arreglo");
        rdims = 0;
    }

    bool privada = buscar_hijo(node, NODO_PRIVATUM) != NULL;

    if (symtab_lookup_current_scope(st, name) != NULL) {
        diag_error("E302", node->linea, node->columna, largo_de(name),
                   "'%s' ya esta declarado en este ambito: Nova no admite sobrecarga",
                   name);
        return;
    }

    Symbol *f = symtab_insert_func(st, name, ret, rdims, privada,
                                   node->linea, node->columna);

    /* Anotaciones. Una desconocida no detiene nada: W004 y se descarta. */
    for (Nodo *a = node->hijo; a != NULL; a = a->sig) {
        if (a->tipo != NODO_ANOTACION) continue;
        if (strcmp(a->texto, "cauda") == 0) {
            f->es_cauda = true;
        } else if (strcmp(a->texto, "obsoletum") == 0) {
            f->es_obsoleta = true;
            Nodo *msg = buscar_hijo(a, NODO_CADENA);
            if (msg != NULL && msg->texto != NULL) {
                free(f->msg_obsoleta);
                f->msg_obsoleta = malloc(strlen(msg->texto) + 1);
                if (f->msg_obsoleta != NULL) strcpy(f->msg_obsoleta, msg->texto);
            }
        } else {
            diag_advertencia("W004", a->linea, a->columna, largo_de(a->texto),
                             "anotacion desconocida '@%s': se descarta", a->texto);
        }
    }

    /* Parametros. Se guardan en la firma; se insertan como simbolos cuando
     * la segunda pasada entra al cuerpo. */
    Nodo *ps = buscar_hijo(node, NODO_PARAMETROS);
    if (ps == NULL) return;

    for (Nodo *p = ps->hijo; p != NULL; p = p->sig) {
        if (p->tipo != NODO_PARAMETRO) continue;

        Nodo *ptn = buscar_hijo(p, NODO_TIPO);
        DataType pt = dtype_de(ptn ? ptn->texto : NULL);
        int pd, pr, pc;
        bool pab;
        leer_dims(ptn, &pd, &pr, &pc, &pab);

        if (pt == TYPE_NIHIL) {
            diag_error("E321", p->linea, p->columna, largo_de(p->texto),
                       "un parametro no puede ser de tipo 'nihil'");
            pt = TYPE_ERROR;
        }

        bool repetido = false;
        for (Parameter *q = f->params; q != NULL; q = q->next)
            if (strcmp(q->name, p->texto) == 0) repetido = true;
        if (repetido) {
            diag_error("E302", p->linea, p->columna, largo_de(p->texto),
                       "el parametro '%s' esta repetido", p->texto);
            continue;
        }

        symtab_add_param(f, p->texto, pt, pd, pab, pr, pc);
    }
}

static void primera_pasada(Nodo *raiz) {
    if (raiz == NULL) return;

    registrar_imports(buscar_hijo(raiz, NODO_IMPORTS));

    Nodo *globales = buscar_hijo(raiz, NODO_GLOBALES);
    if (globales == NULL) return;

    /* Dos barridos: primero las constantes, luego las firmas, para que un
     * parametro pueda declararse como integer[N] usando una constante. */
    for (Nodo *g = globales->hijo; g != NULL; g = g->sig)
        if (g->tipo == NODO_CONSTANTE) declarar_constante(g, true);

    for (Nodo *g = globales->hijo; g != NULL; g = g->sig)
        if (g->tipo == NODO_FUNCION) declarar_funcion(g);
}

/* ====================================================================== */
/* 5. Analisis de expresiones                                             */
/* ====================================================================== */

static Info info_de_simbolo(Symbol *s) {
    Info i = info_de(s->type, s->dimensions);
    i.rows = s->rows;
    i.cols = s->cols;
    i.abierto = s->abierto;
    i.asignable = (s->kind == SYMBOL_VAR || s->kind == SYMBOL_PARAM);
    i.sym = s;
    return i;
}

/* Un identificador suelto. 'leer' distingue la lectura de la escritura, que
 * es lo que hace util a W001. */
static Info analizar_ident(Nodo *e, bool leer) {
    if (e->modulo != NULL) {
        Symbol *m = symtab_lookup(st, e->modulo);
        if (m == NULL || m->kind != SYMBOL_MODULE) {
            diag_error("E301", e->linea, e->columna, largo_de(e->modulo),
                       "el modulo '%s' no fue importado", e->modulo);
        }
        /* El tipo real vive en el otro modulo: lo verifica el enlazador. */
        return info_error();
    }

    Symbol *s = symtab_lookup(st, e->texto);
    if (s == NULL) {
        diag_error("E301", e->linea, e->columna, largo_de(e->texto),
                   "'%s' no esta declarado en este ambito", e->texto);
        return info_error();
    }
    if (s->kind == SYMBOL_FUNC) {
        diag_error("E303", e->linea, e->columna, largo_de(e->texto),
                   "'%s' es una funcion: falta la lista de argumentos", e->texto);
        return info_error();
    }
    if (s->kind == SYMBOL_MODULE) {
        diag_error("E303", e->linea, e->columna, largo_de(e->texto),
                   "'%s' es un modulo, no un valor", e->texto);
        return info_error();
    }

    if (leer) s->is_used = true;
    decorar_simbolo(e, s);
    return info_de_simbolo(s);
}

/*
 * Un acceso indexado. Las dimensiones se consumen de izquierda a derecha:
 * si m es integer[F][C], entonces m[i] es integer[] de largo C y m[i][j] es
 * un integer. El limite que acota a i es F, el que acota a j es C.
 */
static Info analizar_indice(Nodo *e, bool leer) {
    Nodo *base = e->hijo;
    Nodo *idx = base ? base->sig : NULL;

    Info b;
    if (base == NULL) return info_error();
    if (base->tipo == NODO_INDICE)      b = analizar_indice(base, leer);
    else if (base->tipo == NODO_IDENT)  b = analizar_ident(base, true);
    else                                b = analizar_expresion(base);

    Info ix = analizar_expresion(idx);
    if (valido(ix) && (ix.tipo != TYPE_INTEGER || ix.dims != 0)) {
        char a[32];
        diag_error("E307", idx->linea, idx->columna, 1,
                   "el indice debe ser 'integer', no '%s'", desc(a, sizeof(a), ix));
    }

    if (!valido(b)) return info_error();

    if (b.dims == 0) {
        const char *n = b.sym ? b.sym->name : "la expresion";
        diag_error("E314", e->linea, e->columna, largo_de(b.sym ? b.sym->name : NULL),
                   "'%s' no es un arreglo: no se puede indexar", n);
        return info_error();
    }

    /* E308: con indice constante y tamano conocido se detecta al compilar. */
    long k;
    if (!b.abierto && b.rows > 0 && valido(ix) && eval_const(idx, &k)) {
        if (k < 0 || k >= b.rows) {
            diag_error("E308", idx->linea, idx->columna, 1,
                       "el indice constante %ld esta fuera del rango 0..%d",
                       k, b.rows - 1);
        }
    }

    Info r = info_de(b.tipo, b.dims - 1);
    r.rows = (b.dims == 2) ? b.cols : 0;
    r.cols = 0;
    r.abierto = b.abierto;
    r.asignable = b.asignable;
    r.sym = b.sym;

    /* La fase 4 necesita saber cuantas dimensiones quedan y el paso de la
     * fila para linealizar el indice: m[i][j] esta en i*cols + j. */
    Decor *d = nodo_decorar(e);
    d->clase = DEC_VAR;
    d->tipo = (int)r.tipo;
    d->dims = r.dims;
    d->filas = b.rows;
    d->cols = b.cols;
    d->abierto = b.abierto ? 1 : 0;
    return r;
}

/* --- Llamadas ---------------------------------------------------------- */

/* longitudo, scribe y dic no se verifican con la lista de parametros: la
 * primera acepta cualquier arreglo o un textus, y las otras dos son las
 * unicas construcciones variadicas del lenguaje. */
static Info verificar_longitudo(Nodo *n, Info *args, Nodo **nodos, int nargs) {
    (void)nodos;
    if (nargs != 1) {
        diag_error("E304", n->linea, n->columna, largo_de(n->texto),
                   "longitudo espera 1 argumento, se dieron %d", nargs);
        return info_de(TYPE_INTEGER, 0);
    }
    if (valido(args[0]) && args[0].dims == 0 && args[0].tipo != TYPE_TEXTUS) {
        char a[32];
        diag_error("E319", nodos[0]->linea, nodos[0]->columna, 1,
                   "longitudo espera un arreglo o un 'textus', no '%s'",
                   desc(a, sizeof(a), args[0]));
    }
    return info_de(TYPE_INTEGER, 0);
}

static Info verificar_variadica(Nodo *n, Symbol *f, Info *args, Nodo **nodos, int nargs) {
    if (nargs < 1) {
        diag_error("E304", n->linea, n->columna, largo_de(n->texto),
                   "%s espera al menos 1 argumento", f->name);
        return info_de(TYPE_NIHIL, 0);
    }
    for (int i = 0; i < nargs; i++) {
        if (!valido(args[i])) continue;
        if (args[i].dims != 0) {
            char a[32];
            diag_error("E319", nodos[i]->linea, nodos[i]->columna, 1,
                       "%s no acepta arreglos ('%s'): hay que recorrerlos",
                       f->name, desc(a, sizeof(a), args[i]));
        } else if (args[i].tipo == TYPE_NIHIL) {
            diag_error("E321", nodos[i]->linea, nodos[i]->columna, 1,
                       "no se puede imprimir un valor 'nihil'");
        }
    }
    return info_de(TYPE_NIHIL, 0);
}

/* ranura y ronda de la boveda van de 0 a 3. Si son constantes se verifica
 * aqui (E319); si no, queda la verificacion de ejecucion. */
static void verificar_rango_boveda(Symbol *f, Nodo **nodos, int nargs) {
    int indices[2] = {-1, -1};
    const char *nombres[2] = {NULL, NULL};

    if (strcmp(f->name, "custodi") == 0) {
        indices[0] = 0; nombres[0] = "ranura";
    } else if (strcmp(f->name, "feistel") == 0 ||
               strcmp(f->name, "desfeistel") == 0) {
        indices[0] = 1; nombres[0] = "ranura";
        indices[1] = 2; nombres[1] = "ronda";
    } else {
        return;
    }

    for (int k = 0; k < 2; k++) {
        int i = indices[k];
        if (i < 0 || i >= nargs) continue;
        long v;
        if (eval_const(nodos[i], &v) && (v < 0 || v > 3)) {
            diag_error("E319", nodos[i]->linea, nodos[i]->columna, 1,
                       "%s debe estar entre 0 y 3, no %ld", nombres[k], v);
        }
    }
}

static Info analizar_llamada(Nodo *n) {
    Nodo *lista = buscar_hijo(n, NODO_ARGUMENTOS);

    /* Los argumentos se analizan siempre, aunque la firma no calce: los
     * errores que tengan dentro deben reportarse igual. */
    Info args[MAX_ARGS];
    Nodo *nodos[MAX_ARGS];
    int nargs = 0;
    if (lista != NULL) {
        for (Nodo *a = lista->hijo; a != NULL; a = a->sig) {
            Info i = analizar_expresion(a);
            if (nargs < MAX_ARGS) {
                args[nargs] = i;
                nodos[nargs] = a;
            }
            nargs++;
        }
    }
    int comparables = nargs < MAX_ARGS ? nargs : MAX_ARGS;

    /* Una llamada calificada que sobreviva a la fase de enlace indica una
     * unidad de analisis aislada, por ejemplo el AST de una biblioteca. */
    if (n->modulo != NULL) {
        Symbol *m = symtab_lookup(st, n->modulo);
        if (m == NULL || m->kind != SYMBOL_MODULE) {
            diag_error("E301", n->linea, n->columna, largo_de(n->modulo),
                       "el modulo '%s' no fue importado", n->modulo);
        }
        return info_error();
    }

    Symbol *f = symtab_lookup(st, n->texto);
    if (f == NULL) {
        diag_error("E301", n->linea, n->columna, largo_de(n->texto),
                   "la funcion '%s' no esta declarada", n->texto);
        return info_error();
    }
    if (f->kind != SYMBOL_FUNC) {
        diag_error("E313", n->linea, n->columna, largo_de(n->texto),
                   "'%s' es %s, no una funcion",
                   n->texto, symbol_kind_to_string(f->kind));
        return info_error();
    }
    f->is_used = true;

    if (f->es_obsoleta) {
        diag_advertencia("W006", n->linea, n->columna, largo_de(n->texto),
                         "'%s' esta marcada @obsoletum%s%s", n->texto,
                         f->msg_obsoleta ? ": " : "",
                         f->msg_obsoleta ? f->msg_obsoleta : "");
    }

    if (f->is_intrinsic) {
        if (strcmp(f->name, "longitudo") == 0)
            return verificar_longitudo(n, args, nodos, comparables);
        if (f->is_variadic)
            return verificar_variadica(n, f, args, nodos, comparables);
    }

    if (nargs != f->param_count) {
        diag_error("E304", n->linea, n->columna, largo_de(n->texto),
                   "'%s' espera %d argumento%s, se dieron %d",
                   n->texto, f->param_count,
                   f->param_count == 1 ? "" : "s", nargs);
    } else {
        int i = 0;
        for (Parameter *p = f->params; p != NULL && i < comparables; p = p->next, i++) {
            if (!valido(args[i])) continue;

            if (args[i].dims != p->dimensions) {
                char a[32], b[32];
                diag_error("E314", nodos[i]->linea, nodos[i]->columna, 1,
                           "el parametro '%s' es '%s' y se paso '%s'",
                           p->name, tipo_con_dims(b, sizeof(b), p->type, p->dimensions),
                           desc(a, sizeof(a), args[i]));
            } else if (args[i].tipo != p->type) {
                char a[32], b[32];
                diag_error("E305", nodos[i]->linea, nodos[i]->columna, 1,
                           "el parametro '%s' es '%s' y se paso '%s'",
                           p->name, tipo_con_dims(b, sizeof(b), p->type, p->dimensions),
                           desc(a, sizeof(a), args[i]));
            }
        }
    }

    if (f->is_intrinsic) verificar_rango_boveda(f, nodos, comparables);

    decorar_simbolo(n, f);
    return info_de(f->return_type, f->return_dims);
}

/* --- Operadores -------------------------------------------------------- */

static bool es_aritmetico(const char *op) {
    static const char *ops[] = {"+","-","*","/","%","&","|","^","<<",">>",">>>",NULL};
    for (int i = 0; ops[i]; i++) if (strcmp(op, ops[i]) == 0) return true;
    return false;
}

static bool es_relacional(const char *op) {
    static const char *ops[] = {"<","<=",">",">=",NULL};
    for (int i = 0; ops[i]; i++) if (strcmp(op, ops[i]) == 0) return true;
    return false;
}

static Info analizar_binario(Nodo *e) {
    Nodo *ni = e->hijo;
    Nodo *nd = ni ? ni->sig : NULL;
    Info a = analizar_expresion(ni);
    Info b = analizar_expresion(nd);
    const char *op = e->texto;

    /* Los arreglos no admiten ningun operador: para copiarlos hay que
     * recorrerlos. Se reporta aqui para no confundirlo con un error de tipo. */
    if ((valido(a) && a.dims > 0) || (valido(b) && b.dims > 0)) {
        diag_error("E303", e->linea, e->columna, largo_de(op),
                   "los arreglos no admiten el operador '%s'", op);
        return info_error();
    }
    if (!valido(a) || !valido(b)) return info_error();

    if (es_aritmetico(op)) {
        if (a.tipo != TYPE_INTEGER || b.tipo != TYPE_INTEGER) {
            char x[32], y[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'%s' opera sobre 'integer'; se recibio '%s' y '%s'",
                       op, desc(x, sizeof(x), a), desc(y, sizeof(y), b));
            return info_error();
        }
        /* E316: division o modulo entre una constante que vale cero. */
        if (strcmp(op, "/") == 0 || strcmp(op, "%") == 0) {
            long v;
            if (eval_const(nd, &v) && v == 0) {
                diag_error("E316", nd->linea, nd->columna, 1,
                           "division entre la constante cero");
                return info_error();
            }
        }
        return info_de(TYPE_INTEGER, 0);
    }

    if (strcmp(op, "==") == 0 || strcmp(op, "!=") == 0) {
        if (a.tipo != b.tipo) {
            char x[32], y[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'%s' exige el mismo tipo en ambos lados; se recibio '%s' y '%s'",
                       op, desc(x, sizeof(x), a), desc(y, sizeof(y), b));
            return info_error();
        }
        if (a.tipo == TYPE_NIHIL) {
            diag_error("E321", e->linea, e->columna, largo_de(op),
                       "no se puede comparar un valor 'nihil'");
            return info_error();
        }
        return info_de(TYPE_VERITAS, 0);
    }

    if (es_relacional(op)) {
        if (a.tipo != TYPE_INTEGER || b.tipo != TYPE_INTEGER) {
            char x[32], y[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'%s' opera sobre 'integer'; se recibio '%s' y '%s'",
                       op, desc(x, sizeof(x), a), desc(y, sizeof(y), b));
            return info_error();
        }
        return info_de(TYPE_VERITAS, 0);
    }

    if (strcmp(op, "et") == 0 || strcmp(op, "aut") == 0) {
        if (a.tipo != TYPE_VERITAS || b.tipo != TYPE_VERITAS) {
            char x[32], y[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'%s' opera sobre 'veritas'; se recibio '%s' y '%s'",
                       op, desc(x, sizeof(x), a), desc(y, sizeof(y), b));
            return info_error();
        }
        return info_de(TYPE_VERITAS, 0);
    }

    return info_error();
}

static Info analizar_unario(Nodo *e) {
    Info a = analizar_expresion(e->hijo);
    const char *op = e->texto;

    if (valido(a) && a.dims > 0) {
        diag_error("E303", e->linea, e->columna, largo_de(op),
                   "los arreglos no admiten el operador '%s'", op);
        return info_error();
    }
    if (!valido(a)) return info_error();

    if (strcmp(op, "non") == 0) {
        if (a.tipo != TYPE_VERITAS) {
            char x[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'non' opera sobre 'veritas', no sobre '%s'", desc(x, sizeof(x), a));
            return info_error();
        }
        return info_de(TYPE_VERITAS, 0);
    }
    if (strcmp(op, "-") == 0 || strcmp(op, "~") == 0) {
        if (a.tipo != TYPE_INTEGER) {
            char x[32];
            diag_error("E303", e->linea, e->columna, largo_de(op),
                       "'%s' opera sobre 'integer', no sobre '%s'",
                       op, desc(x, sizeof(x), a));
            return info_error();
        }
        return info_de(TYPE_INTEGER, 0);
    }
    return info_error();
}

static Info analizar_expresion(Nodo *e) {
    if (e == NULL) return info_error();

    switch (e->tipo) {
        case NODO_ENTERO:   return info_de(TYPE_INTEGER, 0);
        case NODO_CADENA:   return info_de(TYPE_TEXTUS, 0);
        case NODO_BOOLEANO: return info_de(TYPE_VERITAS, 0);
        case NODO_IDENT:    return analizar_ident(e, true);
        case NODO_INDICE:   return analizar_indice(e, true);
        case NODO_BINARIO:  return analizar_binario(e);
        case NODO_UNARIO:   return analizar_unario(e);
        case NODO_LLAMADA:  return analizar_llamada(e);

        case NODO_LISTA_VALORES:
            diag_error("E303", e->linea, e->columna, 1,
                       "una lista de valores solo puede aparecer como inicializador");
            return info_error();

        default:
            return info_error();
    }
}

/* El lado izquierdo de una asignacion: no cuenta como lectura. */
static Info analizar_designador(Nodo *e) {
    if (e == NULL) return info_error();
    if (e->tipo == NODO_IDENT)  return analizar_ident(e, false);
    if (e->tipo == NODO_INDICE) return analizar_indice(e, true);
    return analizar_expresion(e);
}

/* ====================================================================== */
/* 6. Analisis de sentencias                                              */
/* ====================================================================== */

/* Lista de valores constantes. Sus dimensiones deben coincidir exactamente
 * con el tipo declarado (E317). La lista vacia {} es el relleno con ceros. */
static void verificar_lista(Nodo *lista, DataType t, int dims, int rows, int cols) {
    if (lista->hijo == NULL) return;    /* {} : todos los elementos en cero */

    if (dims == 0) {
        diag_error("E303", lista->linea, lista->columna, 1,
                   "un escalar no se inicializa con una lista de valores");
        return;
    }

    int n = 0;
    for (Nodo *x = lista->hijo; x != NULL; x = x->sig) n++;
    int esperados = rows;

    if (esperados > 0 && n != esperados) {
        diag_error("E317", lista->linea, lista->columna, 1,
                   "la lista tiene %d elemento%s y el arreglo declara %d",
                   n, n == 1 ? "" : "s", esperados);
    }

    for (Nodo *x = lista->hijo; x != NULL; x = x->sig) {
        if (dims == 2) {
            if (x->tipo != NODO_LISTA_VALORES) {
                diag_error("E317", x->linea, x->columna, 1,
                           "cada fila de un arreglo de dos dimensiones debe ser una lista");
                continue;
            }
            verificar_lista(x, t, 1, cols, 0);
        } else {
            if (x->tipo == NODO_LISTA_VALORES) {
                diag_error("E317", x->linea, x->columna, 1,
                           "sobra un nivel de llaves: el arreglo es de una dimension");
                continue;
            }
            Info i = analizar_expresion(x);
            if (valido(i) && (i.tipo != t || i.dims != 0)) {
                char a[32], b[32];
                diag_error("E303", x->linea, x->columna, 1,
                           "el arreglo es de '%s' y el valor es '%s'",
                           tipo_con_dims(b, sizeof(b), t, 0), desc(a, sizeof(a), i));
            }
            long v;
            if (!eval_const(x, &v) && valido(i) && t != TYPE_TEXTUS) {
                diag_error("E317", x->linea, x->columna, 1,
                           "los valores de la lista de inicializacion deben ser constantes");
            }
        }
    }
}

static void declarar_variable(Nodo *stmt) {
    const char *name = stmt->texto;
    Nodo *tn = buscar_hijo(stmt, NODO_TIPO);
    DataType tipo = dtype_de(tn ? tn->texto : NULL);

    int dims, rows, cols;
    bool abierto;
    leer_dims(tn, &dims, &rows, &cols, &abierto);

    if (tipo == TYPE_NIHIL) {
        diag_error("E321", stmt->linea, stmt->columna, largo_de(name),
                   "'nihil' solo puede usarse como tipo de retorno");
        tipo = TYPE_ERROR;
    }

    if (symtab_lookup_current_scope(st, name) != NULL) {
        diag_error("E302", stmt->linea, stmt->columna, largo_de(name),
                   "'%s' ya esta declarado en este ambito", name);
        return;
    }

    Symbol *ext = symtab_lookup_exterior(st, name);
    if (ext != NULL && ext->kind != SYMBOL_FUNC && ext->kind != SYMBOL_MODULE)
        diag_advertencia("W002", stmt->linea, stmt->columna, largo_de(name),
                         "'%s' oculta la declaracion de la linea %d", name, ext->line);

    Symbol *s = symtab_insert_var(st, name, tipo, dims, rows, cols,
                                  stmt->linea, stmt->columna);
    decorar_simbolo(stmt, s);

    Nodo *init = (tn != NULL) ? tn->sig : NULL;
    if (init == NULL) return;        /* sin inicializador: valor por defecto */

    s->is_assigned = true;
    if (init->tipo == NODO_LISTA_VALORES) {
        verificar_lista(init, tipo, dims, rows, cols);
        return;
    }

    Info i = analizar_expresion(init);
    if (!valido(i) || tipo == TYPE_ERROR) return;

    if (dims > 0) {
        char a[32];
        diag_error("E314", init->linea, init->columna, 1,
                   "un arreglo se inicializa con una lista de valores, no con '%s'",
                   desc(a, sizeof(a), i));
    } else if (i.tipo != tipo || i.dims != 0) {
        char a[32], b[32];
        diag_error("E303", init->linea, init->columna, 1,
                   "no se puede asignar '%s' a una variable de tipo '%s'",
                   desc(a, sizeof(a), i), tipo_con_dims(b, sizeof(b), tipo, 0));
    }
}

static void analizar_asignacion(Nodo *stmt) {
    Nodo *dest = stmt->hijo;
    Nodo *val = dest ? dest->sig : NULL;

    Info d = analizar_designador(dest);
    Info v = analizar_expresion(val);

    if (!valido(d)) return;

    if (d.sym != NULL && d.sym->kind == SYMBOL_CONST) {
        diag_error("E311", dest->linea, dest->columna, largo_de(d.sym->name),
                   "'%s' es una 'constans': no se le puede asignar", d.sym->name);
        return;
    }
    if (!d.asignable) {
        diag_error("E303", dest->linea, dest->columna, 1,
                   "el lado izquierdo de una asignacion debe ser una variable");
        return;
    }
    if (d.dims > 0) {
        diag_error("E314", dest->linea, dest->columna, 1,
                   "no se puede asignar un arreglo completo: hay que recorrerlo");
        return;
    }
    if (!valido(v)) return;

    if (v.tipo != d.tipo || v.dims != 0) {
        char a[32], b[32];
        diag_error("E303", stmt->linea, stmt->columna, 1,
                   "no se puede asignar '%s' a una variable de tipo '%s'",
                   desc(a, sizeof(a), v), desc(b, sizeof(b), d));
        return;
    }
    if (d.sym != NULL) d.sym->is_assigned = true;
}

static void verificar_condicion(Nodo *cond, const char *palabra) {
    Info c = analizar_expresion(cond);
    if (valido(c) && (c.tipo != TYPE_VERITAS || c.dims != 0)) {
        char a[32];
        diag_error("E306", cond->linea, cond->columna, 1,
                   "la condicion de '%s' debe ser 'veritas', no '%s'",
                   palabra, desc(a, sizeof(a), c));
    }
}

/* Advierte sobre las declaraciones del ambito que esta por cerrarse. */
static void revisar_no_usados(void) {
    if (symtab_level(st) <= 0) return;    /* las globales se exportan */
    for (Symbol *s = symtab_simbolos_ambito(st); s != NULL; s = s->next) {
        if (s->is_used) continue;
        if (s->kind == SYMBOL_VAR)
            diag_advertencia("W001", s->line, s->col, largo_de(s->name),
                             "la variable '%s' se declara y nunca se usa", s->name);
        else if (s->kind == SYMBOL_CONST)
            diag_advertencia("W001", s->line, s->col, largo_de(s->name),
                             "la constante '%s' se declara y nunca se usa", s->name);
    }
}

static void analizar_sentencia(Nodo *s) {
    if (s == NULL) return;

    switch (s->tipo) {
        case NODO_VARIABLE:
            declarar_variable(s);
            break;

        case NODO_CONSTANTE:
            declarar_constante(s, false);
            break;

        case NODO_ASIGNACION:
            analizar_asignacion(s);
            break;

        case NODO_BLOQUE:
            analizar_bloque(s, true);
            break;

        case NODO_SI: {
            Nodo *cond = s->hijo;
            Nodo *entonces = cond ? cond->sig : NULL;
            Nodo *sino = entonces ? entonces->sig : NULL;
            verificar_condicion(cond, "si");
            analizar_bloque(entonces, true);
            if (sino != NULL) analizar_bloque(sino, true);
            break;
        }

        case NODO_DUM: {
            Nodo *cond = s->hijo;
            Nodo *cuerpo = cond ? cond->sig : NULL;
            verificar_condicion(cond, "dum");
            loop_depth++;
            analizar_bloque(cuerpo, true);
            loop_depth--;
            break;
        }

        case NODO_PER: {
            /* Los hijos son, en orden: inicializacion, condicion, paso y
             * cuerpo. La variable del ciclo vive solo dentro del per. */
            Nodo *init = s->hijo;
            Nodo *cond = init ? init->sig : NULL;
            Nodo *paso = cond ? cond->sig : NULL;
            Nodo *cuerpo = paso ? paso->sig : NULL;

            symtab_push_scope(st);
            if (init != NULL) analizar_sentencia(init);
            verificar_condicion(cond, "per");
            if (paso != NULL) analizar_sentencia(paso);

            loop_depth++;
            analizar_bloque(cuerpo, true);
            loop_depth--;

            revisar_no_usados();
            symtab_pop_scope(st);
            break;
        }

        case NODO_REDDE: {
            Nodo *expr = s->hijo;
            DataType esperado = func_actual ? func_actual->return_type : TYPE_NIHIL;

            if (expr != NULL) {
                Info i = analizar_expresion(expr);
                if (esperado == TYPE_NIHIL) {
                    diag_error("E312", s->linea, s->columna, 5,
                               "una funcion 'nihil' no retorna ningun valor");
                } else if (valido(i) && (i.tipo != esperado || i.dims != 0)) {
                    char a[32], b[32];
                    diag_error("E312", expr->linea, expr->columna, 1,
                               "se retorna '%s' y la funcion declara '%s'",
                               desc(a, sizeof(a), i),
                               tipo_con_dims(b, sizeof(b), esperado, 0));
                }
            } else if (esperado != TYPE_NIHIL) {
                char b[32];
                diag_error("E312", s->linea, s->columna, 5,
                           "falta el valor de retorno: la funcion declara '%s'",
                           tipo_con_dims(b, sizeof(b), esperado, 0));
            }
            break;
        }

        case NODO_RUMPE:
        case NODO_PERGE:
            if (loop_depth <= 0) {
                const char *p = (s->tipo == NODO_RUMPE) ? "rumpe" : "perge";
                diag_error("E310", s->linea, s->columna, largo_de(p),
                           "'%s' solo puede usarse dentro de un ciclo", p);
            }
            break;

        case NODO_LLAMADA: {
            Info i = analizar_llamada(s);
            if (valido(i) && i.tipo != TYPE_NIHIL) {
                char a[32];
                diag_advertencia("W005", s->linea, s->columna, largo_de(s->texto),
                                 "se descarta el valor '%s' que retorna '%s'",
                                 desc(a, sizeof(a), i), s->texto ? s->texto : "");
            }
            break;
        }

        default:
            break;
    }
}

/* Una sentencia que corta el flujo: lo que venga despues es inalcanzable. */
static bool corta_flujo(const Nodo *s) {
    return s != NULL && (s->tipo == NODO_REDDE ||
                         s->tipo == NODO_RUMPE ||
                         s->tipo == NODO_PERGE);
}

static void analizar_bloque(Nodo *b, bool nuevo_ambito) {
    if (b == NULL) return;
    if (b->tipo != NODO_BLOQUE) { analizar_sentencia(b); return; }

    if (nuevo_ambito) symtab_push_scope(st);

    bool inalcanzable = false;
    bool ya_avisado = false;
    for (Nodo *s = b->hijo; s != NULL; s = s->sig) {
        if (inalcanzable && !ya_avisado) {
            diag_advertencia("W003", s->linea, s->columna, 1,
                             "codigo inalcanzable: el flujo ya salio de este bloque");
            ya_avisado = true;
        }
        analizar_sentencia(s);
        if (corta_flujo(s)) inalcanzable = true;
    }

    if (nuevo_ambito) {
        revisar_no_usados();
        symtab_pop_scope(st);
    }
}

/* ====================================================================== */
/* 7. Analisis de flujo (E309) y posicion de cola (E315)                  */
/* ====================================================================== */

/* Busca un rumpe que pertenezca a este ciclo, sin entrar a los anidados. */
static bool tiene_rumpe(const Nodo *n) {
    for (const Nodo *s = n; s != NULL; s = s->sig) {
        if (s->tipo == NODO_RUMPE) return true;
        if (s->tipo == NODO_DUM || s->tipo == NODO_PER) continue;
        if (tiene_rumpe(s->hijo)) return true;
    }
    return false;
}

/*
 * Verdadero si toda ruta de ejecucion de esta sentencia termina en redde.
 * Es la verificacion que exige E309. Un dum (verum) sin rumpe tampoco cae,
 * asi que cuenta como ruta cerrada.
 */
static bool siempre_retorna(const Nodo *n) {
    if (n == NULL) return false;

    switch (n->tipo) {
        case NODO_REDDE:
            return true;

        case NODO_BLOQUE:
            for (const Nodo *s = n->hijo; s != NULL; s = s->sig)
                if (siempre_retorna(s)) return true;
            return false;

        case NODO_SI: {
            const Nodo *cond = n->hijo;
            const Nodo *entonces = cond ? cond->sig : NULL;
            const Nodo *sino = entonces ? entonces->sig : NULL;
            if (sino == NULL) return false;      /* sin aliter puede no entrar */
            return siempre_retorna(entonces) && siempre_retorna(sino);
        }

        case NODO_DUM: {
            const Nodo *cond = n->hijo;
            const Nodo *cuerpo = cond ? cond->sig : NULL;
            bool infinito = (cond != NULL && cond->tipo == NODO_BOOLEANO &&
                             cond->valor != 0);
            return infinito && cuerpo != NULL && !tiene_rumpe(cuerpo->hijo);
        }

        default:
            return false;
    }
}

/* --- @cauda (E315) ----------------------------------------------------- */

static void cauda_sentencia(Nodo *s, bool cola);

/* Recorre una expresion buscando llamadas recursivas. Solo son validas si
 * estan en posicion de cola, o sea si su resultado es lo ultimo que hace la
 * funcion y no entra en ningun calculo posterior. */
static void cauda_expresion(Nodo *e, bool es_cola) {
    if (e == NULL) return;

    if (e->tipo == NODO_LLAMADA && e->modulo == NULL && e->texto != NULL &&
        func_actual != NULL && strcmp(e->texto, func_actual->name) == 0) {
        if (!es_cola) {
            diag_error("E315", e->linea, e->columna, largo_de(e->texto),
                       "@cauda: la llamada recursiva a '%s' no esta en posicion de cola",
                       e->texto);
        }
        /* Los argumentos nunca son posicion de cola. */
        for (Nodo *h = e->hijo; h != NULL; h = h->sig) cauda_expresion(h, false);
        return;
    }

    for (Nodo *h = e->hijo; h != NULL; h = h->sig) cauda_expresion(h, false);
}

/* Verdadero si despues de esta sentencia solo queda uno o mas 'redde;'
 * vacios: el flujo sale de la funcion ahi mismo, asi que lo que la rodea ya
 * no importa y la sentencia sigue estando en posicion de cola. */
static bool sale_aqui(const Nodo *sig) {
    bool hay_redde = false;
    for (const Nodo *s = sig; s != NULL; s = s->sig) {
        if (s->tipo == NODO_REDDE && s->hijo == NULL) { hay_redde = true; continue; }
        return false;
    }
    return hay_redde;
}

static void cauda_bloque(Nodo *b, bool cola) {
    if (b == NULL || b->tipo != NODO_BLOQUE) return;
    for (Nodo *s = b->hijo; s != NULL; s = s->sig) {
        bool es_cola = sale_aqui(s->sig) || (cola && s->sig == NULL);
        cauda_sentencia(s, es_cola);
    }
}

static void cauda_sentencia(Nodo *s, bool cola) {
    if (s == NULL) return;

    switch (s->tipo) {
        case NODO_REDDE:
            /* 'redde f(...)' siempre es posicion de cola. */
            cauda_expresion(s->hijo, true);
            break;

        case NODO_BLOQUE:
            cauda_bloque(s, cola);
            break;

        case NODO_SI: {
            Nodo *cond = s->hijo;
            Nodo *entonces = cond ? cond->sig : NULL;
            Nodo *sino = entonces ? entonces->sig : NULL;
            cauda_expresion(cond, false);
            cauda_bloque(entonces, cola);
            cauda_bloque(sino, cola);
            break;
        }

        case NODO_LLAMADA:
            /* Como sentencia solo es cola en una funcion nihil. */
            cauda_expresion(s, cola && func_actual != NULL &&
                                func_actual->return_type == TYPE_NIHIL);
            break;

        default:
            for (Nodo *h = s->hijo; h != NULL; h = h->sig) cauda_expresion(h, false);
            break;
    }
}

/* ====================================================================== */
/* 8. Segunda pasada y punto de entrada                                   */
/* ====================================================================== */

static void analizar_funcion(Nodo *node) {
    Symbol *f = symtab_lookup(st, node->texto);
    if (f == NULL || f->kind != SYMBOL_FUNC) return;   /* no se registro: E302 */

    func_actual = f;
    loop_depth = 0;
    symtab_set_ambito(st, f->name);
    symtab_reset_frame(st);
    symtab_push_scope(st);

    /* Los parametros son los primeros simbolos del ambito de la funcion.
     * Se recorren junto a los nodos del AST para conservar linea y columna. */
    Nodo *ps = buscar_hijo(node, NODO_PARAMETROS);
    Nodo *pn = ps ? ps->hijo : NULL;
    for (Parameter *p = f->params; p != NULL; p = p->next) {
        while (pn != NULL && pn->tipo != NODO_PARAMETRO) pn = pn->sig;
        int ln = pn ? pn->linea : node->linea;
        int cl = pn ? pn->columna : node->columna;
        Symbol *psym = symtab_insert_param(st, p, ln, cl);
        decorar_simbolo(pn, psym);
        if (pn != NULL) pn = pn->sig;
    }

    Nodo *cuerpo = buscar_hijo(node, NODO_BLOQUE);
    analizar_bloque(cuerpo, false);

    if (f->return_type != TYPE_NIHIL && !siempre_retorna(cuerpo)) {
        diag_error("E309", node->linea, node->columna, largo_de(f->name),
                   "'%s' declara '%s' y hay rutas que terminan sin 'redde'",
                   f->name, data_type_to_string(f->return_type));
    }

    if (f->es_cauda) cauda_bloque(cuerpo, true);

    revisar_no_usados();
    symtab_set_frame_size(f, symtab_frame_size(st));
    if (f->local_frame_size > CERBERO_PILA_BYTES) {
        diag_advertencia("W007", node->linea, node->columna, largo_de(f->name),
                         "el marco de '%s' usa %d bytes y la pila de CERBERO tiene %d",
                         f->name, f->local_frame_size, CERBERO_PILA_BYTES);
    }

    decorar_simbolo(node, f);
    symtab_pop_scope(st);
    symtab_set_ambito(st, "global");
    func_actual = NULL;
}

static void segunda_pasada(Nodo *raiz) {
    Nodo *globales = buscar_hijo(raiz, NODO_GLOBALES);
    if (globales == NULL) return;
    for (Nodo *g = globales->hijo; g != NULL; g = g->sig)
        if (g->tipo == NODO_FUNCION) analizar_funcion(g);
}

bool semantic_analyze(Nodo *root, SymbolTable **out_symtab) {
    int errores_antes = diag_errores();

    st = symtab_create();
    loop_depth = 0;
    func_actual = NULL;

    primera_pasada(root);
    segunda_pasada(root);

    /* El segmento de datos globales de CERBERO son 16 KB fijos: si el
     * programa no cabe, la fase 4 no tendria donde ubicar las variables. */
    if (st->globales_desbordadas) {
        diag_advertencia("W007", 1, 1, 1,
                         "los datos globales necesitan %d bytes y el segmento de "
                         "CERBERO tiene %d (0x0000-0x3FFF)",
                         st->global_memory_offset - CERBERO_GLOBAL_BASE,
                         CERBERO_GLOBAL_FIN - CERBERO_GLOBAL_BASE);
    }

    if (out_symtab != NULL) *out_symtab = st;
    SymbolTable *mia = st;
    st = NULL;
    if (out_symtab == NULL) symtab_destroy(mia);

    return diag_errores() == errores_antes;
}
