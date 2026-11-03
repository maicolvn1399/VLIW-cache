#ifndef IDE_LEX_H
#define IDE_LEX_H

#include <stddef.h>
#include "jsonw.h"

/*
 * Tokenizacion para el IDE.
 *
 * No hay un segundo lexer: esto llama a yylex(), el que genera flex a partir
 * de nova.l, sobre el mismo buffer que ve el compilador. Escribir un
 * tokenizador aparte para el editor habria sido mas rapido, pero cualquier
 * cambio futuro en nova.l lo habria dejado desincronizado, y entonces el
 * editor marcaria cosas distintas de las que marca la compilacion.
 *
 * El resultado es el arreglo de tokens con su posicion de inicio y de fin, que
 * es lo que necesitan el balanceo de delimitadores, el completado y la
 * deteccion de clones.
 */

typedef struct {
    int   tipo;        /* codigo de token de nova.tab.h; 0 es fin de archivo */
    int   linea;       /* 1-based */
    int   columna;     /* 1-based */
    int   fin_linea;
    int   fin_columna; /* una pasada del ultimo caracter */
    char *texto;       /* lexema; para TK_ENTERO, el valor en decimal */
    long  valor;       /* solo TK_ENTERO */
} TokenIDE;

typedef struct {
    TokenIDE *v;
    int n;
    int cap;
} ListaTokens;

/*
 * Tokeniza un buffer en memoria. Devuelve 1 si pudo recorrerlo. Los errores
 * lexicos que encuentre se reportan por diag.c como siempre; si el llamador
 * tiene la captura activa quedan en la lista de diagnosticos, y si no, se
 * imprimen. La lista de tokens se devuelve igual, porque el IDE necesita
 * trabajar sobre codigo a medio escribir.
 */
int ide_tokenizar_buffer(const char *fuente, size_t largo, ListaTokens *out);

/* Tokeniza un archivo del disco. */
int ide_tokenizar_archivo(const char *ruta, ListaTokens *out);

void ide_tokens_liberar(ListaTokens *l);

/*
 * Emite el flujo de tokens como JSON, con la categoria de color de cada uno.
 * Es lo que usa el editor para pintar el codigo.
 */
int ide_tokens_json(const char *ruta, JsonW *j);

/* Categoria de color de un token: reservada, tipo, nombre, numero, ... */
const char *ide_token_categoria(int tipo);

/* Nombre legible de un token, para mensajes ("';'", "un identificador"). */
const char *ide_token_vista(int tipo);

/* 1 si el token puede cerrar una sentencia (identificador, literal, ')' ...). */
int ide_token_termina_sentencia(int tipo);

/* 1 si el token solo puede iniciar una sentencia nueva. */
int ide_token_inicia_sentencia(int tipo);

/* 1 si es palabra reservada del lenguaje. */
int ide_token_es_reservada(int tipo);

#endif
