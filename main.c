/*
 * Punto de entrada del compilador.
 * Lee las opciones de la linea de comandos y coordina las fases de compilacion.
 */
#include <errno.h>
#include <getopt.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "ast.h"
#include "diag.h"
#include "nova.tab.h"
#include "semantic.h"
#include "symtab.h"
#include "tac.h"
#include "codegen.h"

extern FILE *yyin;
extern char *yytext;
int yyparse(void);
int yylex(void);
void yyrestart(FILE *input_file);
void nova_lexer_reset(void);
void nova_parser_reset(void);

#define MAX_MODULES 128
#define MAX_RUTAS 16
#define NVO_HEADER_SIZE 16

typedef struct {
    char *path;
    char *key;
    Nodo *ast;
    int state;
} Module;

static Module modules[MAX_MODULES];
static int module_count;
static const char *module_paths[MAX_RUTAS];
static int module_path_count;

static char *copy_string(const char *s) {
    size_t n = strlen(s) + 1;
    char *r = malloc(n);
    if (r == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memcpy(r, s, n);
    return r;
}

static uint32_t checksum_bytes(const unsigned char *p, size_t n) {
    uint32_t sum = 0;
    for (size_t i = 0; i < n; i++) sum = sum * 31u + p[i];
    return sum;
}

static uint32_t get_u32(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void put_u32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)v;
    p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16);
    p[3] = (unsigned char)(v >> 24);
}

static int has_suffix(const char *s, const char *suffix) {
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

static char *read_file_bytes(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long n = ftell(f);
    if (n < 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)n + 1);
    if (buf == NULL) { fclose(f); fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    size_t got = fread(buf, 1, (size_t)n, f);
    int failed = ferror(f);
    fclose(f);
    if (failed || got != (size_t)n) { free(buf); return NULL; }
    buf[got] = '\0';
    *length = got;
    return buf;
}

/* Los objetos .nvo conservan la fuente validada para que el enlace final
 * vuelva a ejecutar semantica, asignacion y relajacion con el conjunto entero. */
static char *source_from_file(const char *path, size_t *length) {
    char *raw = read_file_bytes(path, length);
    if (raw == NULL) return NULL;
    if (!has_suffix(path, ".nvo")) return raw;
    if (*length < NVO_HEADER_SIZE || memcmp(raw, "NVO1", 4) != 0 ||
        raw[4] != 1 || raw[5] != 0 || raw[6] != 0 || raw[7] != 0 ||
        get_u32((unsigned char *)raw + 8) != *length - NVO_HEADER_SIZE ||
        get_u32((unsigned char *)raw + 12) !=
            checksum_bytes((unsigned char *)raw + NVO_HEADER_SIZE, *length - NVO_HEADER_SIZE)) {
        free(raw);
        errno = EINVAL;
        return NULL;
    }
    size_t source_length = *length - NVO_HEADER_SIZE;
    memmove(raw, raw + NVO_HEADER_SIZE, source_length);
    raw[source_length] = '\0';
    *length = source_length;
    return raw;
}

static int parse_source(const char *path, Nodo **out_ast) {
    size_t length = 0;
    char *source = source_from_file(path, &length);
    if (source == NULL) {
        fprintf(stderr, "novac: no se pudo leer una fuente/objeto valido '%s'\n", path);
        return 3;
    }
    FILE *stream = fmemopen(source, length, "r");
    if (stream == NULL) { free(source); return 3; }
    yyin = stream;
    yyrestart(stream);
    nova_lexer_reset();
    nova_parser_reset();
    diag_archivo(path);
    int rc = yyparse();
    fclose(stream);
    free(source);
    if (rc != 0 || diag_errores() != 0) {
        liberar_ast(raiz_ast);
        raiz_ast = NULL;
        return 1;
    }
    *out_ast = raiz_ast;
    return 0;
}

static int write_object(const char *source_path, const char *output_path) {
    size_t length = 0;
    char *source = source_from_file(source_path, &length);
    if (source == NULL) {
        fprintf(stderr, "novac: no se pudo leer '%s'\n", source_path);
        return 3;
    }
    if (length > UINT32_MAX) { free(source); return 3; }
    FILE *out = fopen(output_path, "wb");
    if (out == NULL) { free(source); return 3; }
    unsigned char header[NVO_HEADER_SIZE] = {0};
    memcpy(header, "NVO1", 4);
    header[4] = 1;
    put_u32(header + 8, (uint32_t)length);
    put_u32(header + 12, checksum_bytes((unsigned char *)source, length));
    int ok = fwrite(header, 1, sizeof(header), out) == sizeof(header) &&
             fwrite(source, 1, length, out) == length;
    if (fclose(out) != 0) ok = 0;
    free(source);
    if (!ok) { remove(output_path); return 3; }
    return 0;
}

static char *canonical_path(const char *path) {
    char resolved[PATH_MAX];
    if (realpath(path, resolved) != NULL) return copy_string(resolved);
    return copy_string(path);
}

static int path_is_file(const char *path) {
    return access(path, R_OK) == 0;
}

static char *path_candidate(const char *dir, const char *name) {
    char buf[PATH_MAX];
    int n = snprintf(buf, sizeof(buf), "%s/%s", dir, name);
    if (n < 0 || (size_t)n >= sizeof(buf)) return NULL;
    return path_is_file(buf) ? canonical_path(buf) : NULL;
}

static char *resolve_import(const char *request, const char *importer_path) {
    char name[PATH_MAX];
    if (strlen(request) >= sizeof(name)) return NULL;
    snprintf(name, sizeof(name), "%s", request);
    int has_ext = has_suffix(name, ".nv") || has_suffix(name, ".nvo");
    char with_ext[PATH_MAX];
    if (has_ext) snprintf(with_ext, sizeof(with_ext), "%s", name);
    else {
        size_t name_length = strlen(name);
        if (name_length + 4 > sizeof(with_ext)) return NULL;
        memcpy(with_ext, name, name_length);
        memcpy(with_ext + name_length, ".nv", 4);
    }

    if (with_ext[0] == '/' && path_is_file(with_ext)) return canonical_path(with_ext);
    char dir[PATH_MAX];
    snprintf(dir, sizeof(dir), "%s", importer_path);
    char *slash = strrchr(dir, '/');
    if (slash != NULL) *slash = '\0'; else snprintf(dir, sizeof(dir), ".");
    char *found = path_candidate(dir, with_ext);
    if (found == NULL && has_suffix(with_ext, ".nv")) {
        with_ext[strlen(with_ext) - 3] = '\0';
        strncat(with_ext, ".nvo", sizeof(with_ext) - strlen(with_ext) - 1);
        found = path_candidate(dir, with_ext);
    }
    if (found != NULL) return found;
    for (int i = 0; i < module_path_count; i++) {
        found = path_candidate(module_paths[i], with_ext);
        if (found != NULL) return found;
    }
    return NULL;
}

static Nodo *child_of(Nodo *n, TipoNodo kind) {
    for (Nodo *c = n ? n->hijo : NULL; c != NULL; c = c->sig)
        if (c->tipo == kind) return c;
    return NULL;
}

static void module_key_for(const char *path, char *out, size_t cap) {
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    size_t n = strlen(base);
    if (n > 3 && strcmp(base + n - 3, ".nv") == 0) n -= 3;
    else if (n > 4 && strcmp(base + n - 4, ".nvo") == 0) n -= 4;
    uint32_t hash = 2166136261u;
    for (const unsigned char *p = (const unsigned char *)path; *p; p++)
        hash = (hash ^ *p) * 16777619u;
    size_t used = (size_t)snprintf(out, cap, "m_");
    for (size_t i = 0; i < n && used + 10 < cap; i++) {
        char ch = base[i];
        out[used++] = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                       (ch >= '0' && ch <= '9') || ch == '_') ? ch : '_';
    }
    snprintf(out + used, cap - used, "_%08x", hash);
}

static int find_module_path(const char *path) {
    for (int i = 0; i < module_count; i++)
        if (strcmp(modules[i].path, path) == 0) return i;
    return -1;
}

static int load_module(const char *path);

static int load_imports_for_module(int index) {
    Module *m = &modules[index];
    Nodo *imports = child_of(m->ast, NODO_IMPORTS);
    for (Nodo *imp = imports ? imports->hijo : NULL; imp != NULL; imp = imp->sig) {
        if (imp->tipo != NODO_IMPORT) continue;
        if (child_of(imp, NODO_ALIAS) == NULL) {
            const char *base = strrchr(imp->texto ? imp->texto : "", '/');
            base = base ? base + 1 : (imp->texto ? imp->texto : "");
            size_t n = strlen(base);
            if (n > 3 && strcmp(base + n - 3, ".nv") == 0) n -= 3;
            else if (n > 4 && strcmp(base + n - 4, ".nvo") == 0) n -= 4;
            int valid = n > 0 && ((base[0] >= 'a' && base[0] <= 'z') ||
                       (base[0] >= 'A' && base[0] <= 'Z') || base[0] == '_');
            for (size_t j = 1; valid && j < n; j++)
                valid = (base[j] >= 'a' && base[j] <= 'z') ||
                        (base[j] >= 'A' && base[j] <= 'Z') ||
                        (base[j] >= '0' && base[j] <= '9') || base[j] == '_';
            if (!valid) {
                diag_archivo(m->path);
                diag_error("E409", imp->linea, imp->columna, 1,
                           "'%s' no da un nombre de modulo valido: usa 'ut <alias>'",
                           imp->texto ? imp->texto : "");
                continue;
            }
        }
        char *target = resolve_import(imp->texto ? imp->texto : "", m->path);
        if (target == NULL) {
            diag_archivo(m->path);
            diag_error("E404", imp->linea, imp->columna, 1,
                       "no se encontro el modulo importado '%s'", imp->texto ? imp->texto : "");
            continue;
        }
        int target_index = load_module(target);
        free(target);
        if (target_index < 0) return 0;
    }
    return diag_errores() == 0;
}

static int load_module(const char *input_path) {
    char *path = canonical_path(input_path);
    int existing = find_module_path(path);
    if (existing >= 0) { free(path); return existing; }
    if (module_count >= MAX_MODULES) {
        diag_error("E404", 0, 1, 1, "se excedio el maximo de %d modulos", MAX_MODULES);
        free(path);
        return -1;
    }
    int index = module_count++;
    Module *m = &modules[index];
    m->path = path;
    m->key = malloc(128);
    if (m->key == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    module_key_for(path, m->key, 128);
    m->ast = NULL;
    m->state = 1;

    int rc = parse_source(path, &m->ast);
    if (rc != 0) return -1;
    if (!load_imports_for_module(index)) return -1;
    m->state = 2;
    return index;
}

static int find_import_target(Module *owner, Nodo *imp) {
    char *path = resolve_import(imp->texto ? imp->texto : "", owner->path);
    if (path == NULL) return -1;
    int index = find_module_path(path);
    free(path);
    return index;
}

static int alias_matches(Module *owner, Nodo *imp, const char *alias) {
    Nodo *a = child_of(imp, NODO_ALIAS);
    if (a != NULL) return a->texto != NULL && strcmp(a->texto, alias) == 0;
    const char *base = strrchr(imp->texto ? imp->texto : "", '/');
    base = base ? base + 1 : (imp->texto ? imp->texto : "");
    size_t n = strlen(base);
    if (n > 3 && strcmp(base + n - 3, ".nv") == 0) n -= 3;
    else if (n > 4 && strcmp(base + n - 4, ".nvo") == 0) n -= 4;
    (void)owner;
    return strlen(alias) == n && strncmp(base, alias, n) == 0;
}

static int find_import_by_alias(Module *owner, const char *alias) {
    Nodo *imports = child_of(owner->ast, NODO_IMPORTS);
    for (Nodo *imp = imports ? imports->hijo : NULL; imp != NULL; imp = imp->sig) {
        if (imp->tipo == NODO_IMPORT && alias_matches(owner, imp, alias))
            return find_import_target(owner, imp);
    }
    return -1;
}

static int module_has_global(Module *m, const char *name, TipoNodo kind,
                             int *is_private) {
    Nodo *globals = child_of(m->ast, NODO_GLOBALES);
    for (Nodo *g = globals ? globals->hijo : NULL; g != NULL; g = g->sig) {
        if (g->tipo != kind || g->texto == NULL || strcmp(g->texto, name) != 0) continue;
        *is_private = child_of(g, NODO_PRIVATUM) != NULL;
        return 1;
    }
    return 0;
}

static char *qualified_name(const char *key, const char *name) {
    size_t n = strlen(key) + strlen(name) + 2;
    char *r = malloc(n);
    if (r == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    snprintf(r, n, "%s$%s", key, name);
    return r;
}

typedef struct LocalName {
    const char *name;
    struct LocalName *next;
} LocalName;

typedef struct {
    Module *owner;
    LocalName *scopes[128];
    int depth;
    int failed;
} RewriteContext;

static int local_visible(RewriteContext *ctx, const char *name) {
    for (int i = ctx->depth - 1; i >= 0; i--)
        for (LocalName *l = ctx->scopes[i]; l != NULL; l = l->next)
            if (strcmp(l->name, name) == 0) return 1;
    return 0;
}

static void scope_push(RewriteContext *ctx) {
    if (ctx->depth < 128) ctx->scopes[ctx->depth++] = NULL;
    else ctx->failed = 1;
}

static void scope_add(RewriteContext *ctx, const char *name) {
    if (ctx->depth == 0 || name == NULL) return;
    LocalName *l = malloc(sizeof(*l));
    if (l == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    l->name = name;
    l->next = ctx->scopes[ctx->depth - 1];
    ctx->scopes[ctx->depth - 1] = l;
}

static void scope_pop(RewriteContext *ctx) {
    if (ctx->depth == 0) return;
    LocalName *l = ctx->scopes[--ctx->depth];
    while (l != NULL) { LocalName *next = l->next; free(l); l = next; }
}

static int is_intrinsic_name(const char *name) {
    static const char *const names[] = {
        "longitudo", "ingredere", "exi", "custodi", "feistel", "desfeistel",
        "scribe", "dic", NULL
    };
    for (int i = 0; names[i] != NULL; i++) if (strcmp(names[i], name) == 0) return 1;
    return 0;
}

static void rewrite_nodes(Nodo *n, RewriteContext *ctx);

static void rewrite_qualified(Nodo *n, RewriteContext *ctx, TipoNodo kind) {
    int target = find_import_by_alias(ctx->owner, n->modulo);
    int is_private = 0;
    if (target < 0 || !module_has_global(&modules[target], n->texto, kind, &is_private)) {
        diag_archivo(ctx->owner->path);
        diag_error("E401", n->linea, n->columna, 1,
                   "el simbolo '%s.%s' no existe en un modulo importado",
                   n->modulo ? n->modulo : "", n->texto ? n->texto : "");
        ctx->failed = 1;
        return;
    }
    if (is_private && target != (int)(ctx->owner - modules)) {
        diag_archivo(ctx->owner->path);
        diag_error("E403", n->linea, n->columna, 1,
                   "el simbolo '%s.%s' es privatum", n->modulo, n->texto);
        ctx->failed = 1;
        return;
    }
    char *full = qualified_name(modules[target].key, n->texto);
    free(n->texto);
    n->texto = full;
    free(n->modulo);
    n->modulo = NULL;
}

static void rewrite_function(Module *owner, Nodo *function) {
    RewriteContext ctx = {.owner = owner, .depth = 0, .failed = 0};
    scope_push(&ctx);
    Nodo *params = child_of(function, NODO_PARAMETROS);
    for (Nodo *p = params ? params->hijo : NULL; p != NULL; p = p->sig)
        if (p->tipo == NODO_PARAMETRO) scope_add(&ctx, p->texto);
    Nodo *body = child_of(function, NODO_BLOQUE);
    rewrite_nodes(body, &ctx);
    while (ctx.depth > 0) scope_pop(&ctx);
}

static void rewrite_nodes(Nodo *n, RewriteContext *ctx) {
    for (; n != NULL; n = n->sig) {
        if (n->tipo == NODO_BLOQUE) {
            scope_push(ctx);
            rewrite_nodes(n->hijo, ctx);
            scope_pop(ctx);
            continue;
        }
        if (n->tipo == NODO_VARIABLE) {
            rewrite_nodes(n->hijo, ctx);
            scope_add(ctx, n->texto);
            continue;
        }
        if (n->tipo == NODO_LLAMADA) {
            if (n->modulo != NULL) {
                rewrite_qualified(n, ctx, NODO_FUNCION);
            } else if (ctx->owner != NULL && ctx->owner->key != NULL &&
                       !is_intrinsic_name(n->texto)) {
                int priv = 0;
                if (module_has_global(ctx->owner, n->texto, NODO_FUNCION, &priv)) {
                    char *full = qualified_name(ctx->owner->key, n->texto);
                    free(n->texto);
                    n->texto = full;
                }
            }
            rewrite_nodes(n->hijo, ctx);
            continue;
        }
        if (n->tipo == NODO_IDENT) {
            if (n->modulo != NULL) {
                rewrite_qualified(n, ctx, NODO_CONSTANTE);
            } else if (ctx->owner != NULL && ctx->owner->key != NULL &&
                       !local_visible(ctx, n->texto)) {
                int priv = 0;
                if (module_has_global(ctx->owner, n->texto, NODO_CONSTANTE, &priv)) {
                    char *full = qualified_name(ctx->owner->key, n->texto);
                    free(n->texto);
                    n->texto = full;
                }
            }
        }
        rewrite_nodes(n->hijo, ctx);
    }
}

static void rewrite_module(Module *m, int root_module) {
    Nodo *globals = child_of(m->ast, NODO_GLOBALES);
    for (Nodo *g = globals ? globals->hijo : NULL; g != NULL; g = g->sig) {
        if (root_module) {
            if (g->tipo == NODO_FUNCION) rewrite_function(m, g);
            else if (g->tipo == NODO_CONSTANTE) {
                RewriteContext ctx = {.owner = m, .depth = 0, .failed = 0};
                rewrite_nodes(g->hijo, &ctx);
            }
            continue;
        }
        if (g->tipo == NODO_FUNCION) {
            rewrite_function(m, g);
        } else if (g->tipo == NODO_CONSTANTE) {
            RewriteContext ctx = {.owner = m, .depth = 0, .failed = 0};
            rewrite_nodes(g->hijo, &ctx);
        }
    }
}

static int link_modules(Nodo *root, const char *root_path,
                        char **extra_paths, int extra_count) {
    module_count = 1;
    modules[0].path = canonical_path(root_path);
    modules[0].key = NULL;
    modules[0].ast = root;
    modules[0].state = 2;

    for (int i = 0; i < extra_count; i++) {
        if (load_module(extra_paths[i]) < 0) {
            raiz_ast = root;
            return 0;
        }
    }
    if (!load_imports_for_module(0)) {
        raiz_ast = root;
        return 0;
    }

    /* Reescribe referencias cuando todas las declaraciones aun conservan su
     * nombre de origen, luego aplica el prefijo unico por modulo. */
    rewrite_module(&modules[0], 1);
    for (int i = 1; i < module_count; i++) rewrite_module(&modules[i], 0);
    for (int i = 1; i < module_count; i++) {
        Nodo *globals = child_of(modules[i].ast, NODO_GLOBALES);
        for (Nodo *g = globals ? globals->hijo : NULL; g != NULL; g = g->sig) {
            if (g->tipo != NODO_FUNCION && g->tipo != NODO_CONSTANTE) continue;
            char *full = qualified_name(modules[i].key, g->texto);
            free(g->texto);
            g->texto = full;
        }
    }

    Nodo *root_globals = child_of(root, NODO_GLOBALES);
    for (int i = 1; i < module_count; i++) {
        Nodo *globals = child_of(modules[i].ast, NODO_GLOBALES);
        if (globals == NULL || globals->hijo == NULL) continue;
        Nodo *items = globals->hijo;
        globals->hijo = NULL;
        root_globals->hijo = cadena_agregar(root_globals->hijo, items);
    }
    raiz_ast = root;
    return diag_errores() == 0;
}

static void release_modules(void) {
    for (int i = 1; i < module_count; i++) {
        liberar_ast(modules[i].ast);
        free(modules[i].path);
        free(modules[i].key);
        modules[i] = (Module){0};
    }
    if (module_count > 0) {
        free(modules[0].path);
        modules[0] = (Module){0};
    }
    module_count = 0;
}

/* Estado global de la ejecucion actual. */
static int modo_verbose = 0;
static int modo_arbol = 0;
static int modo_lexer = 0;
static int modo_symtab = 0;
static int modo_ir = 0;
static int modo_asm = 0;
static int modo_ensamblar = 0;
static int modo_paquetes = 0;
static int modo_objeto = 0;        /* -c: solo compilar, generar .nvo */
static const char *archivo_salida = NULL;

/* -I: directorios donde buscar modulos importados. */
static const char *rutas_modulos[MAX_RUTAS];
static int n_rutas = 0;

/* Mapea cada token a su nombre para la salida del modo de inspeccion. */
static const char *nombre_token(int tipo) {
    switch (tipo) {
        case TK_FUNCTIO: return "TK_FUNCTIO";
        case TK_VARIA: return "TK_VARIA";
        case TK_CONSTANS: return "TK_CONSTANS";
        case TK_PRIVATUM: return "TK_PRIVATUM";
        case TK_IMPORTA: return "TK_IMPORTA";
        case TK_UT: return "TK_UT";
        case TK_REDDE: return "TK_REDDE";
        case TK_SI: return "TK_SI";
        case TK_SIN: return "TK_SIN";
        case TK_ALITER: return "TK_ALITER";
        case TK_DUM: return "TK_DUM";
        case TK_PER: return "TK_PER";
        case TK_RUMPE: return "TK_RUMPE";
        case TK_PERGE: return "TK_PERGE";
        case TK_TIPO_INTEGER: return "TK_TIPO_INTEGER";
        case TK_TIPO_VERITAS: return "TK_TIPO_VERITAS";
        case TK_TIPO_TEXTUS: return "TK_TIPO_TEXTUS";
        case TK_TIPO_NIHIL: return "TK_TIPO_NIHIL";
        case TK_ET: return "TK_ET";
        case TK_AUT: return "TK_AUT";
        case TK_NON: return "TK_NON";
        case TK_VERUM: return "TK_VERUM";
        case TK_FALSUM: return "TK_FALSUM";
        case TK_MAS: return "TK_MAS";
        case TK_MENOS: return "TK_MENOS";
        case TK_POR: return "TK_POR";
        case TK_ENTRE: return "TK_ENTRE";
        case TK_MODULO: return "TK_MODULO";
        case TK_IGUAL: return "TK_IGUAL";
        case TK_DIFERENTE: return "TK_DIFERENTE";
        case TK_MENOR: return "TK_MENOR";
        case TK_MENOR_IGUAL: return "TK_MENOR_IGUAL";
        case TK_MAYOR: return "TK_MAYOR";
        case TK_MAYOR_IGUAL: return "TK_MAYOR_IGUAL";
        case TK_ASIGNA: return "TK_ASIGNA";
        case TK_ASIGNA_MAS: return "TK_ASIGNA_MAS";
        case TK_ASIGNA_MENOS: return "TK_ASIGNA_MENOS";
        case TK_ASIGNA_POR: return "TK_ASIGNA_POR";
        case TK_ASIGNA_ENTRE: return "TK_ASIGNA_ENTRE";
        case TK_ASIGNA_MODULO: return "TK_ASIGNA_MODULO";
        case TK_PAR_IZQ: return "TK_PAR_IZQ";
        case TK_PAR_DER: return "TK_PAR_DER";
        case TK_LLAVE_IZQ: return "TK_LLAVE_IZQ";
        case TK_LLAVE_DER: return "TK_LLAVE_DER";
        case TK_COR_IZQ: return "TK_COR_IZQ";
        case TK_COR_DER: return "TK_COR_DER";
        case TK_PUNTO_COMA: return "TK_PUNTO_COMA";
        case TK_COMA: return "TK_COMA";
        case TK_DOS_PUNTOS: return "TK_DOS_PUNTOS";
        case TK_PUNTO: return "TK_PUNTO";
        case TK_FLECHA: return "TK_FLECHA";
        case TK_ARROBA: return "TK_ARROBA";
        case TK_AMPERSAND: return "TK_AMPERSAND";
        case TK_BARRA: return "TK_BARRA";
        case TK_XOR: return "TK_XOR";
        case TK_NOT: return "TK_NOT";
        case TK_DESP_IZQ: return "TK_DESP_IZQ";
        case TK_DESP_DER: return "TK_DESP_DER";
        case TK_DESP_LOG: return "TK_DESP_LOG";
        case TK_IDENT: return "TK_IDENT";
        case TK_ENTERO: return "TK_ENTERO";
        case TK_CADENA: return "TK_CADENA";
        default: return "?";
    }
}

/*
 * Fase 1: analisis lexico.
 * Recorre el archivo fuente token por token y muestra la tabla de tokens.
 */
static int correr_lexer(void) {
    printf("%-22s %-20s %6s %5s\n", "LEXEMA", "TOKEN", "LINEA", "COL");
    printf("-------------------------------------------------------------\n");
    int tok, total = 0;
    while ((tok = yylex()) != 0) {
        char lexema[64];
        if (tok == TK_CADENA) snprintf(lexema, sizeof(lexema), "\"%.50s\"", yylval.texto);
        else snprintf(lexema, sizeof(lexema), "%.60s", yytext);
        printf("%-22s %-20s %6d %5d\n", lexema, nombre_token(tok),
               yylloc.first_line, yylloc.first_column);
        total++;
        /* En este modo se llama a yylex() directo, asi que hay que liberar
         * los textos que se asignaron con strdup() en el lexer. */
        if (tok == TK_IDENT || tok == TK_CADENA) {
            free(yylval.texto);
        }
    }
    printf("%-22s %-20s %6d %5d\n", "<EOF>", "TK_EOF", yylloc.first_line, yylloc.first_column);
    printf("-- %d tokens --\n", total + 1);
    if (diag_errores() > 0) {
        diag_resumen();
        return 1;
    }
    printf("\nAnalisis lexico completado sin errores.\n");
    return 0;
}

/*
 * Nombre de salida por omision: el del fuente sin su extension, sin el
 * directorio, y con .nvo si se pidio -c. 'programa.nv' -> 'programa'.
 */
static void nombre_por_omision(const char *fuente, int objeto, char *dest, size_t cap) {
    const char *base = fuente;
    const char *p;
    size_t largo;

    for (p = fuente; *p; p++)
        if (*p == '/' || *p == '\\') base = p + 1;

    largo = strlen(base);
    if (largo > 3 && strcmp(base + largo - 3, ".nv") == 0) largo -= 3;
    if (largo >= cap - 5) largo = cap - 5;

    memcpy(dest, base, largo);
    dest[largo] = '\0';
    if (objeto) strncat(dest, ".nvo", cap - strlen(dest) - 1);
    /* Un fuente llamado solo ".nv" dejaria el nombre vacio. */
    if (dest[0] == '\0') snprintf(dest, cap, "%s", objeto ? "salida.nvo" : "salida");
}

static char *cambiar_extension(const char *path, const char *extension) {
    const char *slash = strrchr(path, '/');
    const char *dot = strrchr(path, '.');
    size_t stem = dot != NULL && (slash == NULL || dot > slash)
        ? (size_t)(dot - path) : strlen(path);
    size_t n = stem + strlen(extension) + 1;
    char *result = malloc(n);
    if (result == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memcpy(result, path, stem);
    strcpy(result + stem, extension);
    return result;
}

static int ensamblar_archivo(const char *source, const char *output,
                             const char *program, int verbose) {
    char executable[PATH_MAX], script[PATH_MAX];
    if (realpath(program, executable) == NULL) {
        fprintf(stderr, "novac: no se pudo resolver la ruta del ejecutable '%s'\n", program);
        return 3;
    }
    char *slash = strrchr(executable, '/');
    if (slash == NULL) {
        fprintf(stderr, "novac: no se pudo determinar la carpeta de instalacion\n");
        return 3;
    }
    *slash = '\0';
    int n = snprintf(script, sizeof(script),
                     "%s/ARQUITECTURA/tools/cerbero_asm.py", executable);
    if (n < 0 || (size_t)n >= sizeof(script)) {
        fprintf(stderr, "novac: la ruta del ensamblador CERBERO es demasiado larga\n");
        return 3;
    }
    if (access(script, R_OK) != 0) {
        n = snprintf(script, sizeof(script), "%s/../tools/cerbero_asm.py", executable);
    }
    if (n < 0 || (size_t)n >= sizeof(script) || access(script, R_OK) != 0) {
        fprintf(stderr, "novac: no se encontro el ensamblador CERBERO junto a novac\n");
        return 3;
    }
    size_t output_n = strlen(output);
    char *data_output = malloc(output_n + sizeof(".dmem.hex"));
    char *listing_output = malloc(output_n + sizeof(".lst"));
    if (data_output == NULL || listing_output == NULL) {
        free(data_output);
        free(listing_output);
        fprintf(stderr, "novac: sin memoria\n");
        return 3;
    }
    snprintf(data_output, output_n + sizeof(".dmem.hex"), "%s.dmem.hex", output);
    snprintf(listing_output, output_n + sizeof(".lst"), "%s.lst", output);
    if (verbose)
        fprintf(stderr, "ensamblando '%s' con el ensamblador CERBERO\n", source);

    pid_t child = fork();
    if (child < 0) {
        perror("novac: no se pudo iniciar el ensamblador");
        free(data_output);
        free(listing_output);
        return 3;
    }
    if (child == 0) {
        execlp("python3", "python3", script, source, "-o", output,
               "--datos", data_output, "--listado", listing_output, (char *)NULL);
        perror("novac: no se pudo ejecutar python3");
        _exit(127);
    }
    int status;
    while (waitpid(child, &status, 0) < 0) {
        if (errno == EINTR) continue;
        perror("novac: error esperando al ensamblador");
        free(data_output);
        free(listing_output);
        return 3;
    }
    free(data_output);
    free(listing_output);
    if (!WIFEXITED(status)) {
        fprintf(stderr, "novac: el ensamblador termino de forma anormal\n");
        return 1;
    }
    int result = WEXITSTATUS(status);
    return result == 0 ? 0 : result == 127 ? 3 : 1;
}

/*
 * Ayuda del programa. Explica las banderas disponibles y que parte del
 * compilador se ejecuta en cada caso.
 */
static void print_usage(const char *prog) {
    fprintf(stderr,
        "Uso: %s [opciones] <archivo_fuente|ensamblador.s> [-o <salida>]\n"
        "\n"
        "Sin banderas de volcado produce el ejecutable binario de CERBERO. Si no\n"
        "se da -o, el nombre es el del fuente sin extension (con .nvo si hay -c).\n"
        "\n"
        "  -o <archivo>      Nombre de salida binaria\n"
        "  -c                Empaqueta fuente validada en un objeto .nvo\n"
        "  -I <directorio>   Directorio de busqueda para importa\n"
        "  -v                Modo detallado: imprime cada fase\n"
        "  -Wall             Activa todas las advertencias (lo estan por omision)\n"
        "  -Werror           Trata las advertencias como errores\n"
        "  -w                Silencia todas las advertencias\n"
        "  -Wno-W00n         Silencia una advertencia concreta\n"
        "  --max-errors <n>  Maximo de errores antes de abortar (por omision: 25)\n"
        "  --tokens          Solo Fase 1: tabla de tokens\n"
        "  -t                Imprime el arbol sintactico (AST)\n"
        "  --sym, -m         Imprime la tabla de simbolos (Fase 3)\n"
        "  --ir              Codigo de tres direcciones (Fase 4)\n"
        "  -s                Genera binario y ensamblador .asm; tambien lo muestra\n"
        "  -x                Ensambla un archivo .s a imagen binaria .hex\n"
        "  -p                Muestra paquetes con slots y codificacion hexadecimal\n"
        "  --version         Version\n"
        "  -h, --help        Esta ayuda\n"
        "\n"
        "Codigos de salida: 0 exito, 1 errores de compilacion, 2 error de uso,\n"
        "3 error de entrada o salida.\n",
        prog);
}

/*
 * Las opciones largas se registran aqui para poder interpretar banderas como
 * --tokens, --help o --version sin tener que hacer parsing manual extra.
 */
static const struct option opciones_largas[] = {
    {"tokens",  no_argument, NULL, 'l'},
    {"sym",     no_argument, NULL, 'm'},
    {"ir",      no_argument, NULL, 1001},
    {"version", no_argument, NULL, 1002},
    {"max-errors", required_argument, NULL, 1003},
    {"help",    no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0}
};

int main(int argc, char **argv) {
    int opt;
    /*
     * Se leen todas las banderas antes de abrir la fase real de compilacion.
     * Esto permite decidir si se ejecuta solo la fase 1, la fase 2 o un
     * modo de diagnostico simple.
     */
    while ((opt = getopt_long(argc, argv, "o:I:W:vtsmclhwxp", opciones_largas, NULL)) != -1) {
        switch (opt) {
            case 'h': print_usage(argv[0]); return 0;
            case 1003: {
                char *fin = NULL;
                long n;
                errno = 0;
                n = strtol(optarg, &fin, 10);
                if (errno != 0 || fin == optarg || *fin != '\0' || n < 1 || n > 1000000) {
                    fprintf(stderr, "novac: valor invalido para --max-errors: '%s' (se espera un entero positivo)\n", optarg);
                    return 2;
                }
                diag_max_errores((int)n);
                break;
            }
            case 1002: printf("novac (Nova) 0.5 - fases 1 a 6: lexico, sintactico, semantico,\n       ensamblador, calculo de saltos y binario CERBERO\n"); return 0;
            case 1001: modo_ir = 1; break;
            case 'o': archivo_salida = optarg; break;
            case 'v': modo_verbose = 1; break;
            case 't': modo_arbol = 1; break;
            case 'l': modo_lexer = 1; break;
            case 'm': modo_symtab = 1; break;
            case 's': modo_asm = 1; break;
            case 'x': modo_ensamblar = 1; break;
            case 'p': modo_paquetes = 1; break;
            case 'c': modo_objeto = 1; break;
            case 'w': diag_warn_ninguna(); break;
            case 'I':
                if (n_rutas >= MAX_RUTAS) {
                    fprintf(stderr, "novac: demasiados directorios -I (maximo %d)\n", MAX_RUTAS);
                    return 2;
                }
                rutas_modulos[n_rutas++] = optarg;
                module_paths[module_path_count++] = optarg;
                break;
            case 'W':
                /* -Wall, -Werror, -Wno-W00n. getopt entrega lo que sigue a -W. */
                if (strcmp(optarg, "all") == 0) diag_warn_todas();
                else if (strcmp(optarg, "error") == 0) diag_warn_como_error();
                else if (strncmp(optarg, "no-", 3) == 0) {
                    if (!diag_warn_desactivar(optarg + 3)) {
                        fprintf(stderr, "novac: '-W%s' no nombra una advertencia conocida (se esperaba W001..W032)\n", optarg);
                        return 2;
                    }
                } else {
                    fprintf(stderr, "novac: opcion de advertencias desconocida: '-W%s'\n", optarg);
                    return 2;
                }
                break;
            default: print_usage(argv[0]); return 2;
        }
    }

    if (optind >= argc) {
        print_usage(argv[0]);
        return 2;
    }
    const char *archivo_fuente = argv[optind];

    int extra_count = argc - optind - 1;
    if (modo_ensamblar) {
        if (extra_count > 0 || modo_objeto || modo_lexer || modo_arbol ||
            modo_symtab || modo_ir || modo_asm || modo_paquetes) {
            fprintf(stderr, "novac: -x recibe un solo .s y no se combina con opciones de inspeccion o -c\n");
            return 2;
        }
        char default_output[PATH_MAX];
        const char *output = archivo_salida;
        if (output == NULL) {
            char *derived = cambiar_extension(argv[optind], ".hex");
            if (strlen(derived) >= sizeof(default_output)) {
                free(derived);
                fprintf(stderr, "novac: nombre de salida demasiado largo\n");
                return 2;
            }
            snprintf(default_output, sizeof(default_output), "%s", derived);
            free(derived);
            output = default_output;
        }
        return ensamblar_archivo(argv[optind], output, argv[0], modo_verbose);
    }
    if (modo_objeto && extra_count > 0) {
        fprintf(stderr, "novac: -c recibe un solo modulo fuente por invocacion\n");
        return 2;
    }
    if ((modo_lexer || modo_arbol || modo_symtab || modo_ir || modo_asm || modo_paquetes) && extra_count > 0) {
        fprintf(stderr, "novac: las opciones de inspeccion reciben un solo archivo\n");
        return 2;
    }
    char **extra_paths = extra_count ? &argv[optind + 1] : NULL;
    diag_iniciar(archivo_fuente);

    /*
     * Si la bandera --tokens/-l esta activa, se ejecuta solo la Fase 1.
     * En cualquier otro caso, el programa entra a la Fase 2 y construye el AST.
     */
    // Modo Léxico
    if (modo_lexer) {
        if (modo_verbose) fprintf(stderr, "== Fase 1: Analisis Lexico -- %s ==\n", archivo_fuente);
        yyin = fopen(archivo_fuente, "r");
        if (yyin == NULL) {
            fprintf(stderr, "novac: no se pudo abrir '%s'\n", archivo_fuente);
            return 3;
        }
        nova_lexer_reset();
        int rc = correr_lexer();
        fclose(yyin);
        return rc;
    }

    /*
     * Fases 1 y 2. El lexer no se corre por separado: bison lo llama con
     * yylex() a medida que necesita el siguiente token, asi que las dos fases
     * van entrelazadas. Para ver solo la fase 1 esta --tokens.
     */
    if (modo_verbose) {
        fprintf(stderr, "== Fase 1: Analisis Lexico -- %s ==\n", archivo_fuente);
        fprintf(stderr, "   (a demanda del parser; --tokens la corre sola)\n");
        fprintf(stderr, "== Fase 2: Analisis Sintactico -- %s ==\n", archivo_fuente);
    }
    int rc = parse_source(archivo_fuente, &raiz_ast);

    if (rc != 0 || diag_errores() > 0) {
        /* Con recuperacion de errores yyparse puede devolver 0 aunque haya
         * errores: el arbol parcial no sirve, se libera. */
        liberar_ast(raiz_ast);
        release_modules();
        diag_resumen();
        return rc == 3 ? 3 : 1;
    }

    if (modo_verbose) fprintf(stderr, "Fase 2 completada sin errores.\n");

    /*
     * Una vez que la fase 2 termina sin errores, se puede pedir la impresion
     * del AST en pantalla o en un archivo de salida.
     */
    // Imprimir AST si se solicitó (-t)
    if (modo_arbol) {
        FILE *salida = stdout;
        if (archivo_salida != NULL) {
            salida = fopen(archivo_salida, "w");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
        }
        fprintf(salida, "=== Arbol sintactico (AST) ===\n");
        imprimir_ast(salida, raiz_ast);
        if (archivo_salida != NULL && salida != stdout) fclose(salida);
    }

    /*
     * Fase 3: analisis semantico. Construye la tabla de simbolos, verifica
     * tipos, ambitos y flujo, y deja en cada simbolo la direccion de memoria
     * que la fase 4 necesita para generar codigo de CERBERO.
     */
    if (modo_verbose) fprintf(stderr, "== Fase 3: Analisis Semantico -- %s ==\n", archivo_fuente);

    if (!modo_arbol && (modo_objeto || modo_symtab || modo_ir || modo_asm || modo_paquetes ||
                        (!modo_arbol && !modo_symtab && !modo_ir && !modo_asm && !modo_paquetes))) {
        if (!link_modules(raiz_ast, archivo_fuente, extra_paths, extra_count)) {
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return diag_errores() ? 1 : 3;
        }
    }

    SymbolTable *tabla = NULL;
    bool sem_ok = semantic_analyze(raiz_ast, &tabla);

    if (!sem_ok) {
        symtab_destroy(tabla);
        liberar_ast(raiz_ast);
        release_modules();
        diag_resumen();
        return 1;
    }

    if (modo_verbose) fprintf(stderr, "Fase 3 completada sin errores.\n");

    /* Para mostrar los desplazamientos usados realmente por el ensamblador,
     * se mide el marco de cada funcion con el layout de fase 4. */
    if (modo_symtab) {
        TACList *layout_tac = tac_generate_from_ast(raiz_ast, tabla);
        bool layout_ok = codegen_update_symbol_layout(layout_tac, tabla);
        tac_free(layout_tac);
        if (!layout_ok) {
            if (diag_errores() == 0)
                fprintf(stderr, "novac: no se pudo calcular el layout de codigo para --sym\n");
            symtab_destroy(tabla);
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return diag_errores() ? 1 : 3;
        }

        FILE *salida = stdout;
        if (archivo_salida != NULL) {
            salida = fopen(archivo_salida, modo_arbol ? "a" : "w");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
        }
        symtab_dump(salida, tabla);
        if (archivo_salida != NULL && salida != stdout) fclose(salida);
    }

    if (modo_objeto) {
        char nombre[256];
        const char *destino = archivo_salida;
        if (destino == NULL) {
            nombre_por_omision(archivo_fuente, 1, nombre, sizeof(nombre));
            destino = nombre;
        }
        int object_rc = write_object(archivo_fuente, destino);
        if (object_rc == 0 && modo_verbose)
            fprintf(stderr, "objeto NOVA escrito en '%s'\n", destino);
        symtab_destroy(tabla);
        liberar_ast(raiz_ast);
        release_modules();
        return object_rc;
    }

    /* Las advertencias se resumen aunque la compilacion haya salido bien. */
    if (diag_advertencias() > 0) diag_resumen();

    /*
     * Fase 4: codigo intermedio y ensamblador de CERBERO. El AST ya viene
     * decorado por la fase 3 con la direccion de cada nombre.
     */
    /*
     * Si no se pidio ningun volcado, la salida por omision es el ejecutable
     * binario, como dice el documento. --ir y -s son volcados de texto que
     * reemplazan al binario para poder revisar la fase por partes.
     */
    int modo_binario = (!modo_ir && !modo_arbol && !modo_symtab && !modo_paquetes);

    if (modo_ir || modo_asm || modo_paquetes || modo_binario) {
        if (modo_verbose) fprintf(stderr, "== Fase 4: Generacion de codigo -- %s ==\n", archivo_fuente);

        TACList *tac = tac_generate_from_ast(raiz_ast, tabla);
        bool gen_ok = true;

        if (modo_ir) {
            FILE *salida = stdout;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida, "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            tac_print(salida, tac);
            if (salida != stdout) fclose(salida);
        }
        if (modo_asm) {
            char *texto_asm = NULL;
            size_t largo_asm = 0;
            FILE *memoria = open_memstream(&texto_asm, &largo_asm);
            if (memoria == NULL) {
                fprintf(stderr, "novac: no se pudo crear el buffer de ensamblador\n");
                tac_free(tac);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
            gen_ok = codegen_generate_vliw(tac, tabla, memoria);
            if (fclose(memoria) != 0) gen_ok = false;
            char default_asm[PATH_MAX];
            char *derived_asm = NULL;
            const char *asm_path;
            if (archivo_salida != NULL) {
                derived_asm = cambiar_extension(archivo_salida, ".asm");
                asm_path = derived_asm;
            } else {
                nombre_por_omision(archivo_fuente, 0, default_asm, sizeof(default_asm));
                size_t used = strlen(default_asm);
                if (used + sizeof(".asm") > sizeof(default_asm)) {
                    free(texto_asm);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
                memcpy(default_asm + used, ".asm", sizeof(".asm"));
                asm_path = default_asm;
            }
            FILE *asm_file = fopen(asm_path, "w");
            if (asm_file == NULL) {
                fprintf(stderr, "novac: no se pudo escribir el ensamblador '%s'\n", asm_path);
                gen_ok = false;
            } else {
                if (fwrite(texto_asm, 1, largo_asm, asm_file) != largo_asm) gen_ok = false;
                if (fclose(asm_file) != 0) gen_ok = false;
            }
            if (fwrite(texto_asm, 1, largo_asm, stdout) != largo_asm) gen_ok = false;
            if (modo_verbose && gen_ok)
                fprintf(stderr, "ensamblador escrito en '%s'\n", asm_path);
            free(derived_asm);
            free(texto_asm);
        }
        if (modo_paquetes) {
            FILE *salida = stdout;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida, "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir el listado '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            if (!codegen_print_packages(tac, tabla, salida)) gen_ok = false;
            if (salida != stdout && fclose(salida) != 0) gen_ok = false;
        }
        if (modo_binario) {
            /* El binario nunca va a pantalla: siempre a un archivo. */
            char nombre[256];
            const char *destino = archivo_salida;
            if (destino == NULL) {
                nombre_por_omision(archivo_fuente, 0, nombre, sizeof(nombre));
                destino = nombre;
            }
            FILE *salida = fopen(destino, "wb");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", destino);
                tac_free(tac);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
            if (!codegen_emitir_binario(tac, tabla, salida)) gen_ok = false;
            if (fclose(salida) != 0) gen_ok = false;
            if (!gen_ok || diag_errores() > 0) remove(destino);
            else if (modo_verbose) fprintf(stderr, "ejecutable escrito en '%s'\n", destino);
        }

        tac_free(tac);

        if (!gen_ok || diag_errores() > 0) {
            symtab_destroy(tabla);
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return 1;
        }
        if (modo_verbose) fprintf(stderr, "Fase 4 completada sin errores.\n");
    }

    symtab_destroy(tabla);
    liberar_ast(raiz_ast);
    release_modules();
    return 0;
}