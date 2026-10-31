#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "symtab.h"

/* --- Utilidades internas ------------------------------------------------ */

static void sin_memoria(void) {
    fprintf(stderr, "novac: sin memoria\n");
    exit(3);
}

static void *xmalloc(size_t n) {
    void *p = calloc(1, n);
    if (p == NULL) sin_memoria();
    return p;
}

static char *xstrdup(const char *s) {
    if (s == NULL) return NULL;
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d == NULL) sin_memoria();
    memcpy(d, s, n);
    return d;
}

/* Redondea hacia arriba al multiplo de palabra: CERBERO accede DMEM por
 * palabras alineadas de 32 bits. */
static int alinear(int bytes) {
    int r = bytes % NOVA_PALABRA;
    return r == 0 ? bytes : bytes + (NOVA_PALABRA - r);
}

/*
 * Bytes que ocupa un simbolo de datos.
 *
 * Un escalar es una palabra. Un arreglo con dimensiones conocidas ocupa
 * todos sus elementos en orden por filas: m[i][j] vive en
 * base + (i*cols + j)*4, que es exactamente lo que promete el documento.
 * Un arreglo con dimensiones abiertas (solo parametros) no reserva los
 * elementos: viaja por referencia y lo que se guarda es el descriptor, o sea
 * la direccion base mas un tamano por dimension.
 */
static int tamano_en_bytes(int dims, int rows, int cols, bool abierto) {
    if (dims == 0) return NOVA_PALABRA;
    if (abierto) return NOVA_PALABRA * (1 + dims);   /* 1D: 8, 2D: 12 */
    if (dims == 1) return alinear(rows * NOVA_PALABRA);
    return alinear(rows * cols * NOVA_PALABRA);
}

const char *data_type_to_string(DataType type) {
    switch (type) {
        case TYPE_INTEGER: return "integer";
        case TYPE_VERITAS: return "veritas";
        case TYPE_TEXTUS:  return "textus";
        case TYPE_NIHIL:   return "nihil";
        case TYPE_ERROR:   return "<error>";
    }
    return "<desconocido>";
}

const char *symbol_kind_to_string(SymbolKind k) {
    switch (k) {
        case SYMBOL_VAR:    return "varia";
        case SYMBOL_PARAM:  return "param";
        case SYMBOL_CONST:  return "constans";
        case SYMBOL_FUNC:   return "functio";
        case SYMBOL_MODULE: return "modulo";
    }
    return "?";
}

const char *tipo_con_dims(char *buf, size_t n, DataType t, int dims) {
    const char *base = data_type_to_string(t);
    if (dims <= 0)      snprintf(buf, n, "%s", base);
    else if (dims == 1) snprintf(buf, n, "%s[]", base);
    else                snprintf(buf, n, "%s[][]", base);
    return buf;
}

/* --- Listado historico (para --sym) ------------------------------------- */

static void registrar_entrada(SymbolTable *st, Symbol *s) {
    Entrada *e = xmalloc(sizeof(Entrada));
    e->name = xstrdup(s->name);
    e->ambito = xstrdup(st->ambito_actual ? st->ambito_actual : "global");
    e->level = st->current_scope ? st->current_scope->level : 0;
    e->kind = s->kind;
    e->type = s->kind == SYMBOL_FUNC ? s->return_type : s->type;
    e->dimensions = s->kind == SYMBOL_FUNC ? s->return_dims : s->dimensions;
    e->rows = s->rows;
    e->cols = s->cols;
    e->abierto = s->abierto;
    e->is_global = s->is_global;
    e->offset = s->offset;
    e->size_bytes = s->size_bytes;
    e->frame_offset = 0;
    e->has_frame_offset = false;
    e->code_address = 0;
    e->has_code_address = false;
    e->has_const_value = s->has_const_value;
    e->const_value = s->const_value;
    e->param_count = s->param_count;
    e->local_frame_size = s->local_frame_size;
    e->is_private = s->is_private;
    e->is_intrinsic = s->is_intrinsic;
    e->is_variadic = s->is_variadic;
    e->line = s->line;
    e->col = s->col;
    e->next = NULL;

    if (st->listado_fin == NULL) st->listado = e;
    else st->listado_fin->next = e;
    st->listado_fin = e;

    /* El simbolo recuerda su fila: los atributos que se completan despues de
     * insertarlo (parametros, intrinseca, anotaciones) se reflejan ahi. */
    ((Symbol *)s)->entrada = e;
}

void symtab_set_ambito(SymbolTable *st, const char *nombre) {
    st->ambito_actual = nombre;
}

/* --- Intrinsecas --------------------------------------------------------
 * scribe, dic, longitudo y las intrinsecas de la boveda no son
 * palabras reservadas: son identificadores predefinidos del ambito global.
 * Se registran con su firma real para que las verificaciones E304, E305 y
 * E319 funcionen igual que con cualquier funcion del usuario.
 */
static void marcar_intrinseca(Symbol *f) {
    f->is_intrinsic = true;
    if (f->entrada != NULL) f->entrada->is_intrinsic = true;
}

static void register_intrinsics(SymbolTable *st) {
    Symbol *f;

    /* longitudo(a) -> integer. El argumento es un arreglo o un textus, lo
     * que no se expresa con un tipo fijo: se verifica aparte (E319). */
    f = symtab_insert_func(st, "longitudo", TYPE_INTEGER, 0, false, 0, 0);
    marcar_intrinseca(f);
    f->param_count = 1;
    f->entrada->param_count = 1;

    /* scribe(e1, e2, ...) -> nihil  y  dic(e1, e2, ...) -> nihil
     * Son las dos unicas construcciones variadicas del lenguaje. */
    f = symtab_insert_func(st, "scribe", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);
    f->is_variadic = true;
    f->entrada->is_variadic = true;

    f = symtab_insert_func(st, "dic", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);
    f->is_variadic = true;
    f->entrada->is_variadic = true;

    /* ingredere(clave: integer) -> veritas */
    f = symtab_insert_func(st, "ingredere", TYPE_VERITAS, 0, false, 0, 0);
    marcar_intrinseca(f);
    symtab_add_param(f, "clave", TYPE_INTEGER, 0, false, 0, 0);

    /* exi() -> nihil */
    f = symtab_insert_func(st, "exi", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);

    /* custodi(ranura, k0, k1, k2, k3) -> nihil */
    f = symtab_insert_func(st, "custodi", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);
    symtab_add_param(f, "ranura", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "k0", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "k1", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "k2", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "k3", TYPE_INTEGER, 0, false, 0, 0);

    /* feistel(bloque: integer[], ranura: integer, ronda: integer) -> nihil */
    f = symtab_insert_func(st, "feistel", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);
    symtab_add_param(f, "bloque", TYPE_INTEGER, 1, true, 0, 0);
    symtab_add_param(f, "ranura", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "ronda", TYPE_INTEGER, 0, false, 0, 0);

    /* desfeistel(bloque: integer[], ranura: integer, ronda: integer) -> nihil */
    f = symtab_insert_func(st, "desfeistel", TYPE_NIHIL, 0, false, 0, 0);
    marcar_intrinseca(f);
    symtab_add_param(f, "bloque", TYPE_INTEGER, 1, true, 0, 0);
    symtab_add_param(f, "ranura", TYPE_INTEGER, 0, false, 0, 0);
    symtab_add_param(f, "ronda", TYPE_INTEGER, 0, false, 0, 0);
}

/* --- Ciclo de vida ------------------------------------------------------ */

SymbolTable *symtab_create(void) {
    SymbolTable *st = xmalloc(sizeof(SymbolTable));
    st->current_scope = NULL;
    st->global_memory_offset = CERBERO_GLOBAL_BASE;
    st->local_memory_offset = 0;
    st->max_local_offset = 0;
    st->globales_desbordadas = false;
    st->ambito_actual = "global";
    st->listado = NULL;
    st->listado_fin = NULL;

    symtab_push_scope(st);      /* ambito global, nivel 0 */
    register_intrinsics(st);
    return st;
}

static void liberar_params(Parameter *p) {
    while (p != NULL) {
        Parameter *sig = p->next;
        free(p->name);
        free(p);
        p = sig;
    }
}

void symtab_destroy(SymbolTable *st) {
    if (st == NULL) return;
    while (st->current_scope != NULL) symtab_pop_scope(st);

    Entrada *e = st->listado;
    while (e != NULL) {
        Entrada *sig = e->next;
        free(e->name);
        free(e->ambito);
        free(e);
        e = sig;
    }
    free(st);
}

/* --- Ambitos ------------------------------------------------------------ */

void symtab_push_scope(SymbolTable *st) {
    Scope *s = xmalloc(sizeof(Scope));
    s->level = st->current_scope ? st->current_scope->level + 1 : 0;
    s->symbols = NULL;
    s->offset_guardado = st->local_memory_offset;
    s->parent = st->current_scope;
    st->current_scope = s;
}

void symtab_pop_scope(SymbolTable *st) {
    if (st->current_scope == NULL) return;

    Scope *viejo = st->current_scope;
    st->current_scope = viejo->parent;

    /* El espacio de este ambito se recicla: dos bloques hermanos pueden
     * reutilizar las mismas posiciones del marco, porque no viven a la vez.
     * max_local_offset conserva la marca de agua, que es lo que se reserva. */
    if (st->local_memory_offset > st->max_local_offset)
        st->max_local_offset = st->local_memory_offset;
    st->local_memory_offset = viejo->offset_guardado;

    Symbol *s = viejo->symbols;
    while (s != NULL) {
        Symbol *sig = s->next;
        liberar_params(s->params);
        free(s->msg_obsoleta);
        free(s->name);
        free(s);
        s = sig;
    }
    free(viejo);
}

int symtab_level(const SymbolTable *st) {
    return st->current_scope ? st->current_scope->level : -1;
}

Symbol *symtab_simbolos_ambito(const SymbolTable *st) {
    return st->current_scope ? st->current_scope->symbols : NULL;
}

/* --- Busquedas ---------------------------------------------------------- */

Symbol *symtab_lookup_current_scope(SymbolTable *st, const char *name) {
    if (st->current_scope == NULL) return NULL;
    for (Symbol *s = st->current_scope->symbols; s != NULL; s = s->next)
        if (strcmp(s->name, name) == 0) return s;
    return NULL;
}

Symbol *symtab_lookup(SymbolTable *st, const char *name) {
    for (Scope *sc = st->current_scope; sc != NULL; sc = sc->parent)
        for (Symbol *s = sc->symbols; s != NULL; s = s->next)
            if (strcmp(s->name, name) == 0) return s;
    return NULL;
}

/* Solo los ambitos exteriores: es lo que necesita W002 para saber si una
 * declaracion esta ocultando otra. */
Symbol *symtab_lookup_exterior(SymbolTable *st, const char *name) {
    if (st->current_scope == NULL) return NULL;
    for (Scope *sc = st->current_scope->parent; sc != NULL; sc = sc->parent)
        for (Symbol *s = sc->symbols; s != NULL; s = s->next)
            if (strcmp(s->name, name) == 0) return s;
    return NULL;
}

/* --- Inserciones -------------------------------------------------------- */

static Symbol *nuevo_simbolo(SymbolTable *st, const char *name, int line, int col) {
    Symbol *s = xmalloc(sizeof(Symbol));
    s->name = xstrdup(name);
    s->line = line;
    s->col = col;
    s->next = st->current_scope->symbols;
    st->current_scope->symbols = s;
    return s;
}

/* Reserva memoria para una variable, un parametro o un arreglo. Las globales
 * reciben una direccion absoluta dentro de 0x0000-0x3FFF; las locales, un
 * desplazamiento negativo respecto de R14, porque la pila de CERBERO crece
 * hacia direcciones menores desde 0xFFFC. */
static void asignar_memoria(SymbolTable *st, Symbol *s) {
    s->size_bytes = tamano_en_bytes(s->dimensions, s->rows, s->cols, s->abierto);

    if (st->current_scope->level == 0) {
        s->is_global = true;
        s->offset = (int32_t)st->global_memory_offset;
        st->global_memory_offset += s->size_bytes;
        if (st->global_memory_offset > CERBERO_GLOBAL_FIN)
            st->globales_desbordadas = true;
    } else {
        s->is_global = false;
        st->local_memory_offset += s->size_bytes;
        s->offset = -(int32_t)st->local_memory_offset;
        if (st->local_memory_offset > st->max_local_offset)
            st->max_local_offset = st->local_memory_offset;
    }
}

Symbol *symtab_insert_var(SymbolTable *st, const char *name, DataType type,
                          int dims, int rows, int cols, int line, int col) {
    Symbol *s = nuevo_simbolo(st, name, line, col);
    s->kind = SYMBOL_VAR;
    s->type = type;
    s->dimensions = dims;
    s->rows = rows;
    s->cols = cols;
    s->abierto = false;
    asignar_memoria(st, s);
    registrar_entrada(st, s);
    return s;
}

Symbol *symtab_insert_param(SymbolTable *st, const Parameter *p, int line, int col) {
    Symbol *s = nuevo_simbolo(st, p->name, line, col);
    s->kind = SYMBOL_PARAM;
    s->type = p->type;
    s->dimensions = p->dimensions;
    s->rows = p->rows;
    s->cols = p->cols;
    s->abierto = p->abierto;
    s->is_assigned = true;      /* llega con valor: no es "sin inicializar" */
    asignar_memoria(st, s);
    registrar_entrada(st, s);
    return s;
}

Symbol *symtab_insert_const(SymbolTable *st, const char *name, DataType type,
                            int32_t val, bool tiene_valor, int line, int col) {
    Symbol *s = nuevo_simbolo(st, name, line, col);
    s->kind = SYMBOL_CONST;
    s->type = type;
    s->const_value = val;
    s->has_const_value = tiene_valor;
    s->is_assigned = true;
    s->size_bytes = NOVA_PALABRA;
    /* Una constans no ocupa memoria de datos: su valor se incrusta como
     * inmediato en las instrucciones, asi que no consume DMEM ni marco. */
    s->is_global = (st->current_scope->level == 0);
    s->offset = 0;
    registrar_entrada(st, s);
    return s;
}

Symbol *symtab_insert_func(SymbolTable *st, const char *name, DataType return_type,
                           int return_dims, bool is_private, int line, int col) {
    Symbol *s = nuevo_simbolo(st, name, line, col);
    s->kind = SYMBOL_FUNC;
    s->type = return_type;
    s->return_type = return_type;
    s->return_dims = return_dims;
    s->is_private = is_private;
    s->is_global = true;
    registrar_entrada(st, s);
    return s;
}

Symbol *symtab_insert_module(SymbolTable *st, const char *name, int line, int col) {
    Symbol *s = nuevo_simbolo(st, name, line, col);
    s->kind = SYMBOL_MODULE;
    s->type = TYPE_NIHIL;
    s->is_global = true;
    s->is_used = true;          /* no se advierte por un import sin usar */
    registrar_entrada(st, s);
    return s;
}

void symtab_add_param(Symbol *f, const char *name, DataType type,
                      int dims, bool abierto, int rows, int cols) {
    Parameter *p = xmalloc(sizeof(Parameter));
    p->name = xstrdup(name);
    p->type = type;
    p->dimensions = dims;
    p->abierto = abierto;
    p->rows = rows;
    p->cols = cols;
    p->next = NULL;

    if (f->params_fin == NULL) f->params = p;
    else f->params_fin->next = p;
    f->params_fin = p;
    f->param_count++;
    if (f->entrada != NULL) f->entrada->param_count = f->param_count;
}

void symtab_set_frame_size(Symbol *f, int bytes) {
    f->local_frame_size = bytes;
    if (f->entrada != NULL) f->entrada->local_frame_size = bytes;
}

void symtab_set_frame_offset(SymbolTable *st, const char *function,
                             const char *name, int offset) {
    if (st == NULL || function == NULL || name == NULL) return;
    for (Entrada *e = st->listado; e != NULL; e = e->next) {
        if (!e->is_global && e->kind != SYMBOL_FUNC &&
            e->ambito != NULL && strcmp(e->ambito, function) == 0 &&
            e->name != NULL && strcmp(e->name, name) == 0) {
            e->frame_offset = offset;
            e->has_frame_offset = true;
        }
    }
}

void symtab_set_frame_total(SymbolTable *st, const char *function, int bytes) {
    if (st == NULL || function == NULL) return;
    for (Entrada *e = st->listado; e != NULL; e = e->next) {
        if (e->kind == SYMBOL_FUNC && strcmp(e->name, function) == 0) {
            e->frame_total = bytes;
            e->has_frame_total = true;
            return;
        }
    }
}

void symtab_set_data_address(SymbolTable *st, const char *function,
                             const char *name, uint32_t address) {
    if (st == NULL || function == NULL || name == NULL) return;
    for (Entrada *e = st->listado; e != NULL; e = e->next) {
        if (!e->is_global && e->kind != SYMBOL_FUNC &&
            e->ambito != NULL && strcmp(e->ambito, function) == 0 &&
            e->name != NULL && strcmp(e->name, name) == 0) {
            e->data_address = address;
            e->has_data_address = true;
        }
    }
}

void symtab_set_function_address(SymbolTable *st, const char *function,
                                 uint32_t address) {
    if (st == NULL || function == NULL) return;
    for (Entrada *e = st->listado; e != NULL; e = e->next) {
        if (e->kind == SYMBOL_FUNC && !e->is_intrinsic &&
            e->name != NULL && strcmp(e->name, function) == 0) {
            e->code_address = address;
            e->has_code_address = true;
        }
    }
}

/* --- Marco de la funcion activa ---------------------------------------- */

void symtab_reset_frame(SymbolTable *st) {
    st->local_memory_offset = 0;
    st->max_local_offset = 0;
}

int symtab_frame_size(const SymbolTable *st) {
    int n = st->max_local_offset > st->local_memory_offset
            ? st->max_local_offset : st->local_memory_offset;
    return alinear(n);
}

/* --- Volcado (--sym) ---------------------------------------------------- */

/* Tipo con los tamanos concretos cuando se conocen: integer[2][3]. Las
 * dimensiones abiertas se muestran vacias, que es como se declaran. */
static const char *tipo_detallado(char *buf, size_t n, const Entrada *e) {
    const char *base = data_type_to_string(e->type);
    if (e->dimensions <= 0)      snprintf(buf, n, "%s", base);
    else if (e->abierto || e->rows <= 0)
        snprintf(buf, n, e->dimensions == 1 ? "%s[]" : "%s[][]", base);
    else if (e->dimensions == 1) snprintf(buf, n, "%s[%d]", base, e->rows);
    else                         snprintf(buf, n, "%s[%d][%d]", base, e->rows, e->cols);
    return buf;
}

void symtab_dump(FILE *out, const SymbolTable *st) {
    fprintf(out, "=== Tabla de simbolos ===\n");
    fprintf(out, "%-14s %-9s %-12s %-16s %3s  %-34s %6s  %s\n",
            "NOMBRE", "CLASE", "AMBITO", "TIPO", "NIV", "DIRECCION/PUNTERO",
            "BYTES", "ORIGEN");
    for (int i = 0; i < 124; i++) fputc('-', out);
    fputc('\n', out);
    fprintf(out, "DMEM @0xNNNN es la direccion de memoria donde se guarda la variable.\n");
    fprintf(out, "En una local esa es la direccion de la primera llamada a su funcion: vive en\n");
    fprintf(out, "R14 + desplazamiento, y en una llamada anidada el marco baja un marco mas.\n");

    char tbuf[40], dir[48], org[48];
    for (const Entrada *e = st->listado; e != NULL; e = e->next) {
        tipo_detallado(tbuf, sizeof(tbuf), e);

        if (e->kind == SYMBOL_FUNC && e->is_intrinsic)
            snprintf(dir, sizeof(dir), "%s", "intrinseca");
        else if (e->kind == SYMBOL_FUNC && e->has_code_address)
            snprintf(dir, sizeof(dir), "IMEM @0x%04X", e->code_address);
        else if (e->kind == SYMBOL_FUNC)
            snprintf(dir, sizeof(dir), "%s", "<sin codigo>");
        else if (e->kind == SYMBOL_MODULE)
            snprintf(dir, sizeof(dir), "%s", "<enlace>");
        else if (e->kind == SYMBOL_CONST)
            e->has_const_value ? snprintf(dir, sizeof(dir), "= %d", (int)e->const_value)
                               : snprintf(dir, sizeof(dir), "%s", "<inmediato>");
        else if (e->is_global)
            snprintf(dir, sizeof(dir), "DMEM @0x%04X", (unsigned)e->offset);
        else if (e->has_data_address && e->has_frame_offset)
            snprintf(dir, sizeof(dir), "DMEM @0x%04X  = r14%+d",
                     (unsigned)e->data_address, e->frame_offset);
        else if (e->has_frame_offset)
            /* La funcion no se alcanza desde principale, asi que nunca se le
             * arma un marco y no hay direccion que dar. */
            snprintf(dir, sizeof(dir), "r14%+d  <sin llamar>", e->frame_offset);
        else
            snprintf(dir, sizeof(dir), "R14 @%+d", (int)e->offset);

        if (e->kind == SYMBOL_FUNC && e->is_variadic)
            snprintf(org, sizeof(org), "%s", "predefinida, variadica");
        else if (e->kind == SYMBOL_FUNC && e->is_intrinsic)
            snprintf(org, sizeof(org), "predefinida, %d arg%s", e->param_count,
                     e->param_count == 1 ? "" : "s");
        else if (e->kind == SYMBOL_FUNC)
            /* El marco que se reporta es el completo, el que resta el prologo:
             * es el que hace cuadrar la aritmetica de las direcciones. */
            snprintf(org, sizeof(org), "linea %d, %d param%s, marco %d B%s",
                     e->line, e->param_count, e->param_count == 1 ? "" : "s",
                     e->has_frame_total ? e->frame_total : e->local_frame_size,
                     e->is_private ? ", privatum" : "");
        else if (e->line > 0)
            snprintf(org, sizeof(org), "linea %d:%d", e->line, e->col);
        else
            snprintf(org, sizeof(org), "%s", "predefinido");

        int bytes = (e->kind == SYMBOL_VAR || e->kind == SYMBOL_PARAM)
                    ? e->size_bytes : 0;

        fprintf(out, "%-14.14s %-9s %-12.12s %-16s %3d  %-34s %6d  %s\n",
                e->name, symbol_kind_to_string(e->kind), e->ambito, tbuf,
                e->level, dir, bytes, org);
    }

    for (int i = 0; i < 124; i++) fputc('-', out);
    fputc('\n', out);
    fprintf(out, "datos globales: %d de %d bytes (0x%04X-0x%04X); "
                 "pila: %d bytes desde 0x%04X hacia abajo\n",
            st->global_memory_offset - CERBERO_GLOBAL_BASE,
            CERBERO_GLOBAL_FIN - CERBERO_GLOBAL_BASE,
            (unsigned)CERBERO_GLOBAL_BASE, (unsigned)(CERBERO_GLOBAL_FIN - 1),
            CERBERO_PILA_BYTES, (unsigned)CERBERO_PILA_TOPE);
}
