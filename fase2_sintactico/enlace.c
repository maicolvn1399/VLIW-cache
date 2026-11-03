/*
 * Lectura de fuentes, fases 1 y 2, y enlace de modulos.
 *
 * El contenido de esta unidad se extrajo de main.c sin cambiar su
 * comportamiento. La razon del movimiento esta explicada en enlace.h: el
 * compilador y el IDE deben compartir exactamente el mismo analisis.
 */
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "ast.h"
#include "diag.h"
#include "enlace.h"

int yyparse(void);
void yyrestart(FILE *input_file);
void nova_lexer_reset(void);
void nova_parser_reset(void);
extern FILE *yyin;

typedef struct {
    char *path;
    char *key;
    Nodo *ast;
    int state;
} Module;

static Module modules[NOVA_MAX_MODULOS];
static int module_count;
static const char *module_paths[NOVA_MAX_RUTAS];
static int module_path_count;

int nova_agregar_ruta_modulos(const char *dir) {
    if (module_path_count >= NOVA_MAX_RUTAS) return 0;
    module_paths[module_path_count++] = dir;
    return 1;
}

char *copy_string(const char *s) {
    size_t n = strlen(s) + 1;
    char *r = malloc(n);
    if (r == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memcpy(r, s, n);
    return r;
}

uint32_t checksum_bytes(const unsigned char *p, size_t n) {
    uint32_t sum = 0;
    for (size_t i = 0; i < n; i++) sum = sum * 31u + p[i];
    return sum;
}

uint32_t get_u32(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

void put_u32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)v;
    p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16);
    p[3] = (unsigned char)(v >> 24);
}

int has_suffix(const char *s, const char *suffix) {
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

char *read_file_bytes(const char *path, size_t *length) {
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
char *source_from_file(const char *path, size_t *length) {
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

int parse_buffer(const char *fuente, size_t largo, const char *nombre,
                 Nodo **out_ast) {
    FILE *stream = fmemopen((void *)fuente, largo, "r");
    if (stream == NULL) return 3;
    yyin = stream;
    yyrestart(stream);
    nova_lexer_reset();
    nova_parser_reset();
    diag_archivo(nombre);
    int rc = yyparse();
    fclose(stream);
    if (rc != 0 || diag_errores() != 0) {
        liberar_ast(raiz_ast);
        raiz_ast = NULL;
        return 1;
    }
    *out_ast = raiz_ast;
    return 0;
}

int parse_source(const char *path, Nodo **out_ast) {
    size_t length = 0;
    char *source = source_from_file(path, &length);
    if (source == NULL) {
        fprintf(stderr, "novac: no se pudo leer una fuente/objeto valido '%s'\n", path);
        return 3;
    }
    int rc = parse_buffer(source, length, path, out_ast);
    free(source);
    return rc;
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

Nodo *child_of(Nodo *n, TipoNodo kind) {
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
    if (module_count >= NOVA_MAX_MODULOS) {
        diag_error("E404", 0, 1, 1, "se excedio el maximo de %d modulos", NOVA_MAX_MODULOS);
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

int link_modules(Nodo *root, const char *root_path,
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

void release_modules(void) {
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
