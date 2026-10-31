#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>     /* isatty: el color solo sale si hay terminal */
#include "ast.h"

/* Funciones auxiliares para crear y recorrer el AST. */
Nodo *nodo_nuevo(TipoNodo tipo, char *texto, long valor, int linea, int columna) {
    Nodo *n = malloc(sizeof(Nodo));
    if (n == NULL) {
        fprintf(stderr, "Sin memoria\n");
        exit(3);
    }
    n->tipo = tipo;
    n->texto = texto;
    n->valor = valor;
    n->linea = linea;
    n->columna = columna;
    n->modulo = NULL;
    n->tipo_resuelto = NULL;
    n->dec = NULL;
    n->hijo = NULL;
    n->sig = NULL;
    return n;
}

Decor *nodo_decorar(Nodo *n) {
    if (n == NULL) return NULL;
    if (n->dec == NULL) {
        n->dec = calloc(1, sizeof(Decor));
        if (n->dec == NULL) {
            fprintf(stderr, "Sin memoria\n");
            exit(3);
        }
    }
    return n->dec;
}

Nodo *fijar_modulo(Nodo *n, char *modulo) {
    n->modulo = modulo;
    return n;
}

Nodo *agregar_hijo(Nodo *padre, Nodo *hijo) {
    if (hijo == NULL) return padre;
    padre->hijo = cadena_agregar(padre->hijo, hijo);
    return padre;
}

Nodo *anteponer_hijo(Nodo *padre, Nodo *hijo) {
    if (hijo == NULL) return padre;
    Nodo *ultimo = hijo;
    while (ultimo->sig != NULL) ultimo = ultimo->sig;
    ultimo->sig = padre->hijo;
    padre->hijo = hijo;
    return padre;
}

Nodo *cadena_agregar(Nodo *cadena, Nodo *nuevo) {
    if (cadena == NULL) return nuevo;
    Nodo *ultimo = cadena;
    while (ultimo->sig != NULL) ultimo = ultimo->sig;
    ultimo->sig = nuevo;
    return cadena;
}

Nodo *binario(const char *op, Nodo *izq, Nodo *der, int linea, int columna) {
    Nodo *n = nodo_nuevo(NODO_BINARIO, strdup(op), 0, linea, columna);
    agregar_hijo(n, izq);
    agregar_hijo(n, der);
    return n;
}

Nodo *unario(const char *op, Nodo *operando, int linea, int columna) {
    Nodo *n = nodo_nuevo(NODO_UNARIO, strdup(op), 0, linea, columna);
    agregar_hijo(n, operando);
    return n;
}

Nodo *copiar_ast(const Nodo *n) {
    if (n == NULL) return NULL;
    Nodo *c = nodo_nuevo(n->tipo, n->texto ? strdup(n->texto) : NULL, n->valor,
                         n->linea, n->columna);
    if (n->modulo != NULL) c->modulo = strdup(n->modulo);
    if (n->tipo_resuelto != NULL) c->tipo_resuelto = strdup(n->tipo_resuelto);
    if (n->dec != NULL) { c->dec = malloc(sizeof(Decor)); if (c->dec) *c->dec = *n->dec; }
    Nodo *ultimo = NULL;
    for (const Nodo *h = n->hijo; h != NULL; h = h->sig) {
        Nodo *hc = copiar_ast(h);
        if (ultimo == NULL) c->hijo = hc; else ultimo->sig = hc;
        ultimo = hc;
    }
    return c;
}

Nodo *nodo_asignacion(Nodo *destino, const char *op, Nodo *valor, int linea, int columna) {
    if (op != NULL) valor = binario(op, copiar_ast(destino), valor, linea, columna);
    Nodo *n = nodo_nuevo(NODO_ASIGNACION, strdup("="), 0, linea, columna);
    agregar_hijo(n, destino);
    agregar_hijo(n, valor);
    return n;
}

static const char *nombre_nodo(TipoNodo t) {
    switch (t) {
        case NODO_PROGRAMA: return "Programa";
        case NODO_IMPORTS: return "Imports";
        case NODO_IMPORT: return "Import";
        case NODO_ALIAS: return "Alias";
        case NODO_GLOBALES: return "Globales";
        case NODO_FUNCION: return "Funcion";
        case NODO_PARAMETROS: return "Parametros";
        case NODO_PARAMETRO: return "Parametro";
        case NODO_ANOTACION: return "Anotacion";
        case NODO_PRIVATUM: return "Privatum";
        case NODO_CONSTANTE: return "Constante";
        case NODO_VARIABLE: return "Variable";
        case NODO_TIPO: return "Tipo";
        case NODO_DIMENSION: return "Dimension";
        case NODO_DIM_ABIERTA: return "DimensionAbierta";
        case NODO_LISTA_VALORES: return "ListaValores";
        case NODO_BLOQUE: return "Bloque";
        case NODO_ASIGNACION: return "Asignacion";
        case NODO_SI: return "Si";
        case NODO_DUM: return "Dum";
        case NODO_PER: return "Per";
        case NODO_REDDE: return "Redde";
        case NODO_RUMPE: return "Rumpe";
        case NODO_PERGE: return "Perge";
        case NODO_LLAMADA: return "Llamada";
        case NODO_ARGUMENTOS: return "Argumentos";
        case NODO_BINARIO: return "Binario";
        case NODO_UNARIO: return "Unario";
        case NODO_IDENT: return "Ident";
        case NODO_INDICE: return "Indice";
        case NODO_ENTERO: return "Entero";
        case NODO_CADENA: return "Cadena";
        case NODO_BOOLEANO: return "Booleano";
    }
    return "?";
}

static void imprimir_texto(FILE *out, const char *s) {
    fputc('"', out);
    for (; *s; s++) {
        if (*s == '\n') fprintf(out, "\\n");
        else if (*s == '\t') fprintf(out, "\\t");
        else if (*s == '"') fprintf(out, "\\\"");
        else if (*s == '\\') fprintf(out, "\\\\");
        else fputc(*s, out);
    }
    fputc('"', out);
}

/*
 * Color por clase de nodo. Son los mismos grupos que usa tools/arbol_svg.py,
 * para que el arbol de la terminal y el SVG se lean igual. Solo se emite
 * cuando la salida es una terminal: con -o, o redirigido a un archivo o a una
 * tuberia, el texto sale limpio y arbol_svg.py lo puede analizar.
 */
static const char *color_nodo(TipoNodo t) {
    switch (t) {
        case NODO_PROGRAMA:                         return "\033[1;38;5;33m";
        case NODO_IMPORTS: case NODO_IMPORT:
        case NODO_ALIAS:   case NODO_GLOBALES:      return "\033[38;5;99m";
        case NODO_FUNCION:                          return "\033[1;38;5;27m";
        case NODO_PARAMETROS: case NODO_PARAMETRO:  return "\033[38;5;38m";
        case NODO_BLOQUE:                           return "\033[38;5;34m";
        case NODO_VARIABLE:                         return "\033[38;5;36m";
        case NODO_CONSTANTE:                        return "\033[38;5;172m";
        case NODO_TIPO: case NODO_DIMENSION:
        case NODO_DIM_ABIERTA:                      return "\033[38;5;134m";
        case NODO_ASIGNACION:                       return "\033[38;5;166m";
        case NODO_SI:  case NODO_DUM: case NODO_PER:
        case NODO_REDDE: case NODO_RUMPE:
        case NODO_PERGE:                            return "\033[38;5;168m";
        case NODO_LLAMADA: case NODO_ARGUMENTOS:    return "\033[38;5;37m";
        case NODO_BINARIO: case NODO_UNARIO:        return "\033[38;5;214m";
        case NODO_ENTERO:  case NODO_BOOLEANO:      return "\033[38;5;178m";
        case NODO_CADENA:                           return "\033[38;5;161m";
        default:                                    return "\033[38;5;245m";
    }
}

/*
 * Prefijo de los conectores. Crece en el montón porque el arbol puede ser muy
 * profundo: una expresion de 400 terminos anida 400 niveles, y un arreglo fijo
 * se quedaria corto justo en la prueba de robustez.
 */
static char *pre = NULL;
static size_t pre_cap = 0;

static bool pre_cabe(size_t n) {
    if (n + 1 <= pre_cap) return true;
    size_t nuevo = pre_cap ? pre_cap : 256;
    while (nuevo < n + 1) nuevo *= 2;
    char *p = realloc(pre, nuevo);
    if (p == NULL) return false;
    pre = p;
    pre_cap = nuevo;
    return true;
}

/*
 * Cada nivel ocupa cuatro columnas en pantalla, pero no cuatro bytes: la barra
 * vertical es un caracter UTF-8 de tres bytes. El prefijo se mide en bytes y
 * se avanza con el largo real de cada tramo.
 */
#define PRE_VACIO "    "
#define PRE_BARRA "│   "
#define PRE_MAX_PASO (sizeof(PRE_BARRA) - 1)

static void imprimir_rec(FILE *out, Nodo *n, size_t largo, bool color) {
    const char *gris = color ? "\033[38;5;240m" : "";
    const char *tenue = color ? "\033[38;5;243m" : "";
    const char *fin = color ? "\033[0m" : "";

    for (; n != NULL; n = n->sig) {
        bool ultimo = (n->sig == NULL);

        if (largo > 0) {
            pre[largo] = '\0';
            fprintf(out, "%s%s%s", gris, pre, fin);
        }
        fprintf(out, "%s%s%s", gris, ultimo ? "└── " : "├── ", fin);

        fprintf(out, "%s%s", color ? color_nodo(n->tipo) : "", nombre_nodo(n->tipo));
        if (n->tipo == NODO_ENTERO) {
            fprintf(out, " %ld", n->valor);
        } else if (n->tipo == NODO_CADENA || n->tipo == NODO_IMPORT) {
            fputc(' ', out);
            imprimir_texto(out, n->texto);
        } else if (n->texto != NULL) {
            fprintf(out, " %s", n->texto);
        }
        fprintf(out, "%s", fin);
        if (n->modulo != NULL) {
            fprintf(out, "  %s[modulo: %s]%s", tenue, n->modulo, fin);
        }
        if (n->tipo_resuelto != NULL) {
            fprintf(out, "  %s[tipo: %s]%s", tenue, n->tipo_resuelto, fin);
        }
        fprintf(out, "  %s(linea %d, columna %d)%s\n",
                tenue, n->linea, n->columna, fin);

        if (n->hijo != NULL && pre_cabe(largo + PRE_MAX_PASO)) {
            /* La barra sigue bajando mientras queden hermanos por imprimir. */
            const char *tramo = ultimo ? PRE_VACIO : PRE_BARRA;
            size_t paso = strlen(tramo);
            memcpy(pre + largo, tramo, paso);
            imprimir_rec(out, n->hijo, largo + paso, color);
        }
    }
}

void imprimir_ast(FILE *out, Nodo *raiz) {
    bool color = isatty(fileno(out)) && getenv("NO_COLOR") == NULL;
    const char *term = getenv("TERM");
    if (term != NULL && strcmp(term, "dumb") == 0) color = false;

    if (!pre_cabe(PRE_MAX_PASO)) return;
    imprimir_rec(out, raiz, 0, color);

    free(pre);
    pre = NULL;
    pre_cap = 0;
}

void liberar_ast(Nodo *n) {
    while (n != NULL) {
        Nodo *sig = n->sig;
        liberar_ast(n->hijo);
        free(n->texto);
        free(n->modulo);
        free(n->tipo_resuelto);
        free(n->dec);
        free(n);
        n = sig;
    }
}