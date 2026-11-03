/*
 * Sugerencias de codigo.
 *
 * El editor pide completado mientras se escribe, es decir casi siempre sobre
 * un archivo que todavia no compila. Por eso el modulo trabaja en dos capas:
 *
 *   - Una capa lexica, que siempre funciona. Recorre los tokens, reconstruye
 *     que se declaro y donde, y deduce el contexto del cursor a partir de los
 *     tokens que lo preceden. Un archivo a medio escribir tokeniza sin
 *     problema aunque no parsee, asi que esta capa nunca se queda sin
 *     respuesta.
 *
 *   - Una capa semantica, que se usa cuando el archivo si analiza. Aporta el
 *     tipo exacto de cada nombre, la firma de cada funcion y la direccion de
 *     memoria donde vive la variable, que es informacion que el flujo de
 *     tokens no tiene.
 *
 * El contexto decide que categoria se ofrece: despues de ':' o de '->' solo
 * tienen sentido los tipos; al inicio de una sentencia, las palabras
 * reservadas y las plantillas; dentro de una expresion, los nombres visibles.
 * Ofrecer siempre la lista completa seria mas facil de programar y mucho peor
 * de usar.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "diag.h"
#include "enlace.h"
#include "ide.h"
#include "ide_lex.h"
#include "nova.tab.h"
#include "semantic.h"
#include "symtab.h"
#include "tac.h"
#include "codegen.h"

#define MAX_SUGERENCIAS 300
#define MAX_NOMBRE 128
#define MAX_DETALLE 192

typedef struct {
    char nombre[MAX_NOMBRE];
    char clase[24];        /* reservada, tipo, plantilla, variable, ... */
    char detalle[MAX_DETALLE];
    char insertar[320];    /* texto a insertar; vacio significa 'nombre' */
    char documentacion[320];
    int  prioridad;        /* menor se muestra primero */
} Sugerencia;

static Sugerencia sug[MAX_SUGERENCIAS];
static int n_sug;

static char prefijo[MAX_NOMBRE];

static int empieza_con_prefijo(const char *nombre) {
    size_t n = strlen(prefijo);
    if (n == 0) return 1;
    return strncmp(nombre, prefijo, n) == 0;
}

static void agregar(const char *nombre, const char *clase, const char *detalle,
                    const char *insertar, const char *doc, int prioridad) {
    Sugerencia *s;
    int i;

    if (n_sug >= MAX_SUGERENCIAS || nombre == NULL || nombre[0] == '\0') return;
    if (!empieza_con_prefijo(nombre)) return;

    for (i = 0; i < n_sug; i++)
        if (strcmp(sug[i].nombre, nombre) == 0) return;   /* ya sugerido */

    s = &sug[n_sug++];
    snprintf(s->nombre, sizeof(s->nombre), "%s", nombre);
    snprintf(s->clase, sizeof(s->clase), "%s", clase);
    snprintf(s->detalle, sizeof(s->detalle), "%s", detalle != NULL ? detalle : "");
    snprintf(s->insertar, sizeof(s->insertar), "%s", insertar != NULL ? insertar : "");
    snprintf(s->documentacion, sizeof(s->documentacion), "%s", doc != NULL ? doc : "");
    s->prioridad = prioridad;
}

/* ----------------------------------------------------------- vocabulario */

typedef struct { const char *nombre, *detalle, *doc; } Palabra;

static const Palabra reservadas[] = {
    {"functio",  "declara una funcion",      "functio nombre(p : integer) -> integer { ... }"},
    {"varia",    "declara una variable",     "varia nombre : tipo = valor;"},
    {"constans", "declara una constante",    "constans NOMBRE : tipo = valor; se pliega en compilacion"},
    {"privatum", "no exporta el simbolo",    "privatum functio ... : visible solo dentro del modulo"},
    {"importa",  "importa un modulo",        "importa \"modulo.nv\" ut alias;"},
    {"ut",       "alias de la importacion",  "importa \"modulo.nv\" ut alias;"},
    {"redde",    "retorna un valor",         "redde expresion;"},
    {"si",       "condicional",              "si (condicion) { ... }"},
    {"sin",      "condicion encadenada",     "} sin (otra_condicion) { ... }"},
    {"aliter",   "rama por omision",         "} aliter { ... }"},
    {"dum",      "ciclo mientras",           "dum (condicion) { ... }"},
    {"per",      "ciclo contado",            "per (varia i : integer = 0; i < n; i += 1) { ... }"},
    {"rumpe",    "sale del ciclo",           "rumpe;"},
    {"perge",    "pasa a la siguiente vuelta","perge;"},
    {"et",       "conjuncion logica",        "a et b : ambos deben ser veritas"},
    {"aut",      "disyuncion logica",        "a aut b"},
    {"non",      "negacion logica",          "non a"},
    {"verum",    "literal verdadero",        "valor de tipo veritas"},
    {"falsum",   "literal falso",            "valor de tipo veritas"},
};

static const Palabra tipos[] = {
    {"integer", "entero de 32 bits con signo", "rango -2147483648 a 2147483647"},
    {"veritas", "valor de verdad",             "verum o falsum; es el unico tipo valido en una condicion"},
    {"textus",  "cadena de texto",             "literal entre comillas dobles"},
    {"nihil",   "sin valor",                   "solo como tipo de retorno de una funcion"},
};

/* Firmas de las intrinsecas, iguales a las que registra la fase 3. */
static const Palabra intrinsecas[] = {
    {"scribe",     "scribe(valor, ...) -> nihil",      "imprime uno o mas valores"},
    {"dic",        "dic(valor, ...) -> nihil",         "imprime sin salto de linea final"},
    {"longitudo",  "longitudo(arreglo) -> integer",    "cantidad de elementos de un arreglo o textus"},
    {"ingredere",  "ingredere(clave) -> veritas",      "abre la sesion de la boveda de llaves"},
    {"exi",        "exi() -> nihil",                   "cierra la sesion de la boveda"},
    {"custodi",    "custodi(ranura, k0, k1, k2, k3)",  "instala una llave; la ranura es constante 0..3"},
    {"feistel",    "feistel(bloque, ranura, ronda)",   "cifrado F4E; ranura y ronda constantes 0..3"},
    {"desfeistel", "desfeistel(bloque, ranura, ronda)","descifrado F4D; ranura y ronda constantes 0..3"},
};

typedef struct { const char *nombre, *detalle, *cuerpo; } Plantilla;

static const Plantilla plantillas[] = {
    {"functio", "plantilla de funcion",
     "functio ${1:nombre}(${2:n} : integer) -> integer {\n    ${0}\n    redde 0;\n}"},
    {"principale", "plantilla de funcion principal",
     "functio principale() -> integer {\n    ${0}\n    redde 0;\n}"},
    {"si", "plantilla de condicional",
     "si (${1:condicion}) {\n    ${0}\n}"},
    {"si-aliter", "plantilla de condicional con rama por omision",
     "si (${1:condicion}) {\n    ${2}\n} aliter {\n    ${0}\n}"},
    {"dum", "plantilla de ciclo mientras",
     "dum (${1:condicion}) {\n    ${0}\n}"},
    {"per", "plantilla de ciclo contado",
     "per (varia ${1:i} : integer = 0; ${1:i} < ${2:n}; ${1:i} += 1) {\n    ${0}\n}"},
    {"importa", "plantilla de importacion",
     "importa \"${1:modulo.nv}\" ut ${2:alias};"},
};

/* --------------------------------------------------- contexto del cursor */

typedef enum {
    CTX_TIPO,        /* despues de ':' o de '->' */
    CTX_SENTENCIA,   /* al inicio de una sentencia */
    CTX_EXPRESION,   /* dentro de una expresion */
    CTX_GLOBAL,      /* fuera de toda funcion */
    CTX_CADENA       /* dentro de un literal de texto: no se sugiere nada */
} Contexto;

/*
 * Indice del ultimo token que empieza antes de la posicion del cursor. Si el
 * cursor esta pegado al final de un identificador, ese identificador es el
 * prefijo que se esta escribiendo y no cuenta como token de contexto.
 */
static int token_antes(const ListaTokens *tk, int linea, int columna,
                       int *idx_prefijo, int *largo_prefijo) {
    int i, ultimo = -1;

    *idx_prefijo = -1;
    *largo_prefijo = 0;

    for (i = 0; i < tk->n; i++) {
        const TokenIDE *t = &tk->v[i];
        if (t->linea > linea || (t->linea == linea && t->columna >= columna)) break;
        ultimo = i;
    }
    if (ultimo < 0) return -1;

    {
        const TokenIDE *t = &tk->v[ultimo];
        /*
         * El cursor cuenta como "dentro de la palabra" tanto si esta pegado a
         * su final como si cayo en medio: al escribir 'res|ultado' el usuario
         * espera que se complete sobre 'res', no sobre la palabra entera.
         */
        int dentro = (t->linea == linea && t->fin_linea == linea &&
                      columna > t->columna && columna <= t->fin_columna);
        if (dentro && (t->tipo == TK_IDENT || ide_token_es_reservada(t->tipo))) {
            *idx_prefijo = ultimo;
            *largo_prefijo = columna - t->columna;
            return ultimo - 1;
        }
    }
    return ultimo;
}

static Contexto deducir_contexto(const ListaTokens *tk, int antes, int profundidad) {
    int t;

    if (antes < 0) return CTX_GLOBAL;
    t = tk->v[antes].tipo;

    if (t == TK_DOS_PUNTOS || t == TK_FLECHA) return CTX_TIPO;

    if (profundidad == 0) return CTX_GLOBAL;

    /* Una sentencia nueva arranca despues de ';', de '{' o de '}'. */
    if (t == TK_PUNTO_COMA || t == TK_LLAVE_IZQ || t == TK_LLAVE_DER)
        return CTX_SENTENCIA;

    return CTX_EXPRESION;
}

/* ------------------------------------------------ declaraciones visibles */

typedef struct {
    char nombre[MAX_NOMBRE];
    char clase[24];
    char ambito[MAX_NOMBRE];   /* "" si es global */
    int  linea;
} Declaracion;

#define MAX_DECLS 2000
static Declaracion decls[MAX_DECLS];
static int n_decls;

static void decl_agregar(const char *nombre, const char *clase,
                         const char *ambito, int linea) {
    Declaracion *d;
    if (n_decls >= MAX_DECLS || nombre == NULL || nombre[0] == '\0') return;
    d = &decls[n_decls++];
    snprintf(d->nombre, sizeof(d->nombre), "%s", nombre);
    snprintf(d->clase, sizeof(d->clase), "%s", clase);
    snprintf(d->ambito, sizeof(d->ambito), "%s", ambito != NULL ? ambito : "");
    d->linea = linea;
}

/*
 * Recorre los tokens anotando cada declaracion con la funcion que la contiene,
 * y de paso averigua en que funcion cae el cursor y a que profundidad de
 * llaves. Es un recorrido lineal, sin construir arbol: tiene que funcionar
 * sobre codigo que todavia no cierra sus bloques.
 */
static void recolectar(const ListaTokens *tk, int linea_cursor, int columna_cursor,
                       char *funcion_cursor, size_t cap_funcion,
                       int *profundidad_cursor) {
    char funcion[MAX_NOMBRE] = "";
    int profundidad = 0;
    int nivel_funcion = -1;
    int i;
    int antes_del_cursor;

    funcion_cursor[0] = '\0';
    *profundidad_cursor = 0;

    for (i = 0; i < tk->n; i++) {
        const TokenIDE *t = &tk->v[i];

        antes_del_cursor = (t->linea < linea_cursor) ||
                           (t->linea == linea_cursor && t->columna < columna_cursor);

        if (t->tipo == TK_LLAVE_IZQ) profundidad++;
        else if (t->tipo == TK_LLAVE_DER) {
            profundidad--;
            if (profundidad <= nivel_funcion) { funcion[0] = '\0'; nivel_funcion = -1; }
            if (profundidad < 0) profundidad = 0;
        }

        if (antes_del_cursor) {
            snprintf(funcion_cursor, cap_funcion, "%s", funcion);
            *profundidad_cursor = profundidad;
        }

        if (t->tipo == TK_FUNCTIO && i + 1 < tk->n && tk->v[i + 1].tipo == TK_IDENT) {
            snprintf(funcion, sizeof(funcion), "%s", tk->v[i + 1].texto);
            nivel_funcion = profundidad;
            decl_agregar(tk->v[i + 1].texto, "funcion", "", tk->v[i + 1].linea);

            /* Parametros: pares 'nombre :' dentro de los parentesis de la firma. */
            {
                int k = i + 2, hondo = 0;
                for (; k < tk->n; k++) {
                    if (tk->v[k].tipo == TK_PAR_IZQ) { hondo++; continue; }
                    if (tk->v[k].tipo == TK_PAR_DER) { if (--hondo <= 0) break; continue; }
                    if (hondo == 1 && tk->v[k].tipo == TK_IDENT &&
                        k + 1 < tk->n && tk->v[k + 1].tipo == TK_DOS_PUNTOS)
                        decl_agregar(tk->v[k].texto, "parametro", funcion, tk->v[k].linea);
                }
            }
            continue;
        }

        if ((t->tipo == TK_VARIA || t->tipo == TK_CONSTANS) &&
            i + 1 < tk->n && tk->v[i + 1].tipo == TK_IDENT) {
            decl_agregar(tk->v[i + 1].texto,
                         t->tipo == TK_VARIA ? "variable" : "constante",
                         funcion, tk->v[i + 1].linea);
            continue;
        }

        if (t->tipo == TK_IMPORTA) {
            /* 'importa "ruta" ut alias' : el alias es un nombre usable. */
            int k;
            for (k = i + 1; k < tk->n && k < i + 5; k++)
                if (tk->v[k].tipo == TK_UT && k + 1 < tk->n &&
                    tk->v[k + 1].tipo == TK_IDENT) {
                    decl_agregar(tk->v[k + 1].texto, "modulo", "", tk->v[k + 1].linea);
                    break;
                }
        }
    }
}

/* --------------------------------------------- enriquecer con la fase 3 */

/*
 * Si el archivo analiza, la tabla de simbolos tiene el tipo de cada nombre y
 * la direccion que le asigno la fase 4. Se devuelve el detalle que
 * corresponde a 'nombre' dentro de 'ambito', o NULL si no aparece.
 */
static const Entrada *buscar_entrada(const SymbolTable *tabla, const char *nombre,
                                     const char *ambito) {
    const Entrada *e, *global = NULL;
    if (tabla == NULL) return NULL;
    for (e = tabla->listado; e != NULL; e = e->next) {
        if (e->name == NULL || strcmp(e->name, nombre) != 0) continue;
        if (ambito != NULL && ambito[0] != '\0' && e->ambito != NULL &&
            strcmp(e->ambito, ambito) == 0)
            return e;
        if (e->level == 0) global = e;
    }
    return global;
}

static void detalle_de_entrada(const Entrada *e, char *buf, size_t cap,
                               char *doc, size_t cap_doc) {
    char tipo[64];

    if (e == NULL) { buf[0] = '\0'; doc[0] = '\0'; return; }

    tipo_con_dims(tipo, sizeof(tipo), e->type, e->dimensions);

    if (e->kind == SYMBOL_FUNC)
        snprintf(buf, cap, "%s(%d parametro%s) -> %s", e->name,
                 e->param_count, e->param_count == 1 ? "" : "s", tipo);
    else
        snprintf(buf, cap, "%s : %s", e->name, tipo);

    /* La direccion de memoria es parte del contrato con CERBERO; verla en el
     * completado ahorra abrir la tabla de simbolos. */
    if (e->is_intrinsic)
        snprintf(doc, cap_doc, "intrinseca del lenguaje");
    else if (e->has_data_address)
        snprintf(doc, cap_doc, "DMEM @0x%04X", e->data_address);
    else if (e->has_code_address)
        snprintf(doc, cap_doc, "IMEM @0x%04X", e->code_address);
    else if (e->is_global && e->kind != SYMBOL_FUNC && e->kind != SYMBOL_MODULE)
        snprintf(doc, cap_doc, "DMEM @0x%04X", (unsigned)e->offset);
    else
        doc[0] = '\0';

    if (e->has_frame_offset && doc[0] != '\0') {
        char extra[64];
        snprintf(extra, sizeof(extra), " = r14%+d", e->frame_offset);
        strncat(doc, extra, cap_doc - strlen(doc) - 1);
    }
}

/* --------------------------------------------------- analisis con reintento */

/* Offset absoluto de una posicion (linea, columna) dentro del buffer. */
static long offset_de(const char *fuente, int linea, int columna) {
    long off = 0;
    int l = 1;
    while (fuente[off] != '\0' && l < linea) {
        if (fuente[off] == '\n') l++;
        off++;
    }
    return off + (columna - 1);
}

/* Corre fase 3 y el layout de fase 4 sobre un AST ya enlazado. */
static int completar_tabla(Nodo *ast, const char *ruta, SymbolTable **tabla) {
    if (!link_modules(ast, ruta, NULL, 0)) return 0;
    if (!semantic_analyze(ast, tabla) || *tabla == NULL) return 0;
    {
        /*
         * El layout de la fase 4 es lo que convierte los desplazamientos en
         * direcciones de DMEM e IMEM, y es lo que hace que el globo del
         * completado pueda decir donde vive cada variable.
         */
        TACList *layout = tac_generate_from_ast(ast, *tabla);
        codegen_update_symbol_layout(layout, *tabla);
        tac_free(layout);
    }
    return 1;
}

/*
 * Consigue la tabla de simbolos para enriquecer las sugerencias.
 *
 * El caso normal al completar es justamente el peor para el analizador: el
 * identificador a medio escribir casi siempre rompe la sintaxis, y entonces no
 * hay tabla, ni tipos, ni direcciones. Escribir 'res' despues de un ';' deja
 * una sentencia incompleta y el archivo no parsea, aunque el resto este
 * perfecto.
 *
 * Por eso hay un segundo intento: si el analisis directo falla, se vuelve a
 * analizar el mismo texto con el prefijo borrado. Quitar las letras que el
 * usuario lleva escritas suele devolver el archivo a un estado valido -- que
 * es el estado en el que estaba un segundo antes-- y de ahi salen los tipos.
 * Es una reparacion local y acotada: no se inventa codigo, solo se deshace lo
 * que todavia no termina de escribirse.
 */
static int analizar_para_tipos(const char *ruta, const ListaTokens *tk,
                               int idx_prefijo, int largo_prefijo,
                               Nodo **out_ast, SymbolTable **out_tabla) {
    char *fuente = NULL;
    size_t largo = 0;
    long corte;

    *out_ast = NULL;
    *out_tabla = NULL;

    /* Primer intento: el archivo tal cual. */
    if (parse_source(ruta, out_ast) == 0 && *out_ast != NULL) {
        if (completar_tabla(*out_ast, ruta, out_tabla)) return 1;
        return 0;   /* parseo pero no analiza: la tabla parcial sirve igual */
    }

    /* El parser ya libero el arbol parcial. */
    *out_ast = NULL;
    raiz_ast = NULL;
    release_modules();

    if (idx_prefijo < 0 || largo_prefijo <= 0) return 0;

    /* Segundo intento: el mismo texto sin el prefijo a medio escribir. */
    fuente = ide_leer_archivo(ruta, &largo);
    if (fuente == NULL) return 0;

    corte = offset_de(fuente, tk->v[idx_prefijo].linea, tk->v[idx_prefijo].columna);
    if (corte < 0 || (size_t)corte + (size_t)largo_prefijo > largo) {
        free(fuente);
        return 0;
    }
    memmove(fuente + corte, fuente + corte + largo_prefijo,
            largo - (size_t)corte - (size_t)largo_prefijo + 1);
    largo -= (size_t)largo_prefijo;

    /*
     * Los contadores de diag.c son acumulativos, asi que hay que ponerlos en
     * cero: si no, parse_buffer ve los errores del intento anterior y declara
     * fallido un analisis que salio bien.
     */
    diag_iniciar(ruta);
    diag_limpiar_captura();

    if (parse_buffer(fuente, largo, ruta, out_ast) == 0 && *out_ast != NULL)
        completar_tabla(*out_ast, ruta, out_tabla);

    free(fuente);
    return *out_tabla != NULL;
}

/* ------------------------------------------------------------------ salida */

static int comparar(const void *a, const void *b) {
    const Sugerencia *x = a, *y = b;
    if (x->prioridad != y->prioridad) return x->prioridad - y->prioridad;
    return strcmp(x->nombre, y->nombre);
}

int ide_completar(const char *ruta, int linea, int columna, JsonW *j) {
    ListaTokens tk;
    SymbolTable *tabla = NULL;
    Nodo *ast = NULL;
    char funcion[MAX_NOMBRE] = "";
    int profundidad = 0;
    int antes, idx_prefijo, largo_prefijo;
    Contexto ctx;
    size_t i;
    int k;

    n_sug = 0;
    n_decls = 0;
    prefijo[0] = '\0';

    diag_limpiar_captura();
    diag_capturar(1);
    diag_iniciar(ruta);

    if (!ide_tokenizar_archivo(ruta, &tk)) {
        diag_capturar(0);
        jw_obj_abrir(j);
        jw_cadena(j, "trabajo", "completar");
        jw_cadena(j, "error", "no se pudo leer el archivo");
        jw_obj_cerrar(j);
        return 3;
    }

    antes = token_antes(&tk, linea, columna, &idx_prefijo, &largo_prefijo);
    if (idx_prefijo >= 0) {
        const char *texto = tk.v[idx_prefijo].texto;
        int n = largo_prefijo;
        if (n < 0) n = 0;
        if ((size_t)n > sizeof(prefijo) - 1) n = (int)sizeof(prefijo) - 1;
        if (n > (int)strlen(texto)) n = (int)strlen(texto);
        memcpy(prefijo, texto, (size_t)n);
        prefijo[n] = '\0';
    }

    recolectar(&tk, linea, columna, funcion, sizeof(funcion), &profundidad);
    ctx = deducir_contexto(&tk, antes, profundidad);

    /* Analisis completo, para poder agregar tipos y direcciones. */
    analizar_para_tipos(ruta, &tk, idx_prefijo, largo_prefijo, &ast, &tabla);

    diag_capturar(0);

    /* --- segun el contexto --- */

    if (ctx == CTX_TIPO) {
        for (i = 0; i < sizeof(tipos) / sizeof(tipos[0]); i++)
            agregar(tipos[i].nombre, "tipo", tipos[i].detalle, NULL, tipos[i].doc, 0);
    } else {
        if (ctx == CTX_GLOBAL) {
            /* Fuera de las funciones Nova solo admite 'constans' y 'functio'. */
            agregar("functio", "reservada", "declara una funcion", NULL,
                    "functio nombre(p : integer) -> integer { ... }", 0);
            agregar("constans", "reservada", "declara una constante", NULL,
                    "constans NOMBRE : tipo = valor;", 0);
            agregar("privatum", "reservada", "no exporta el simbolo", NULL,
                    "privatum functio ...", 1);
            agregar("importa", "reservada", "importa un modulo", NULL,
                    "importa \"modulo.nv\" ut alias;", 1);
            for (i = 0; i < sizeof(plantillas) / sizeof(plantillas[0]); i++) {
                if (strncmp(plantillas[i].nombre, "functio", 7) != 0 &&
                    strcmp(plantillas[i].nombre, "principale") != 0 &&
                    strcmp(plantillas[i].nombre, "importa") != 0)
                    continue;
                agregar(plantillas[i].nombre, "plantilla", plantillas[i].detalle,
                        plantillas[i].cuerpo, "", 2);
            }
        } else {
            if (ctx == CTX_SENTENCIA) {
                for (i = 0; i < sizeof(plantillas) / sizeof(plantillas[0]); i++)
                    agregar(plantillas[i].nombre, "plantilla", plantillas[i].detalle,
                            plantillas[i].cuerpo, "", 0);
                for (i = 0; i < sizeof(reservadas) / sizeof(reservadas[0]); i++)
                    agregar(reservadas[i].nombre, "reservada", reservadas[i].detalle,
                            NULL, reservadas[i].doc, 1);
            } else {
                /* En una expresion solo caben los operadores logicos y los
                 * literales de verdad, no las palabras que abren sentencias. */
                agregar("non", "reservada", "negacion logica", NULL, "non a", 1);
                agregar("et", "reservada", "conjuncion logica", NULL, "a et b", 1);
                agregar("aut", "reservada", "disyuncion logica", NULL, "a aut b", 1);
                agregar("verum", "reservada", "literal verdadero", NULL,
                        "valor de tipo veritas", 1);
                agregar("falsum", "reservada", "literal falso", NULL,
                        "valor de tipo veritas", 1);
            }

            /* Nombres declarados: primero los del ambito actual. */
            for (k = 0; k < n_decls; k++) {
                char detalle[MAX_DETALLE] = "", doc[MAX_DETALLE] = "";
                const Entrada *e;
                int propio;

                propio = (decls[k].ambito[0] != '\0' &&
                          strcmp(decls[k].ambito, funcion) == 0);
                if (decls[k].ambito[0] != '\0' && !propio) continue;  /* otra funcion */

                e = buscar_entrada(tabla, decls[k].nombre, funcion);
                if (e != NULL) detalle_de_entrada(e, detalle, sizeof(detalle),
                                                  doc, sizeof(doc));
                if (detalle[0] == '\0')
                    snprintf(detalle, sizeof(detalle), "%s (linea %d)",
                             decls[k].clase, decls[k].linea);

                agregar(decls[k].nombre, decls[k].clase, detalle, NULL, doc,
                        propio ? 3 : 4);
            }

            /* Intrinsecas al final: son muchas y se usan menos que lo propio. */
            for (i = 0; i < sizeof(intrinsecas) / sizeof(intrinsecas[0]); i++)
                agregar(intrinsecas[i].nombre, "intrinseca", intrinsecas[i].detalle,
                        NULL, intrinsecas[i].doc, 5);
        }
    }

    qsort(sug, (size_t)n_sug, sizeof(sug[0]), comparar);

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "completar");
    jw_cadena(j, "archivo", ruta);
    jw_entero(j, "linea", linea);
    jw_entero(j, "columna", columna);
    jw_cadena(j, "prefijo", prefijo);
    jw_cadena(j, "contexto",
              ctx == CTX_TIPO ? "tipo" :
              ctx == CTX_SENTENCIA ? "sentencia" :
              ctx == CTX_EXPRESION ? "expresion" :
              ctx == CTX_CADENA ? "cadena" : "global");
    jw_cadena(j, "funcion", funcion);
    jw_bool(j, "con_tipos", tabla != NULL);
    jw_entero(j, "total", n_sug);
    jw_clave_arr(j, "sugerencias");
    for (k = 0; k < n_sug; k++) {
        jw_obj_abrir(j);
        jw_cadena(j, "nombre", sug[k].nombre);
        jw_cadena(j, "clase", sug[k].clase);
        jw_cadena(j, "detalle", sug[k].detalle);
        jw_cadena(j, "insertar", sug[k].insertar[0] ? sug[k].insertar : sug[k].nombre);
        jw_bool(j, "es_plantilla", sug[k].insertar[0] != '\0');
        jw_cadena(j, "documentacion", sug[k].documentacion);
        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
    jw_obj_cerrar(j);

    ide_tokens_liberar(&tk);
    symtab_destroy(tabla);
    if (ast != NULL) liberar_ast(ast);
    release_modules();
    raiz_ast = NULL;
    return 0;
}
