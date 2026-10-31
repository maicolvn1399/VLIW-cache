#ifndef AST_H
#define AST_H

#include <stdio.h>

/* Estructura basica del AST usado por la fase sintactica. */
typedef enum {
    NODO_PROGRAMA, NODO_IMPORTS, NODO_IMPORT, NODO_ALIAS, NODO_GLOBALES,
    NODO_FUNCION, NODO_PARAMETROS, NODO_PARAMETRO,
    NODO_ANOTACION, NODO_PRIVATUM,
    NODO_CONSTANTE, NODO_VARIABLE,
    NODO_TIPO, NODO_DIMENSION, NODO_DIM_ABIERTA,
    NODO_LISTA_VALORES, NODO_BLOQUE,
    NODO_ASIGNACION, NODO_SI, NODO_DUM, NODO_PER,
    NODO_REDDE, NODO_RUMPE, NODO_PERGE,
    NODO_LLAMADA, NODO_ARGUMENTOS,
    NODO_BINARIO, NODO_UNARIO, NODO_IDENT, NODO_INDICE,
    NODO_ENTERO, NODO_CADENA, NODO_BOOLEANO
} TipoNodo;

/*
 * Decoracion que la fase 3 deja en los nodos que la fase 4 necesita resolver:
 * donde vive cada nombre y de que tamano es. Se usan enteros simples para que
 * ast.h no dependa de symtab.h. Los codigos de clase coinciden con SymbolKind.
 */
#define DEC_VAR    0
#define DEC_PARAM  1
#define DEC_CONST  2
#define DEC_FUNC   3
#define DEC_MODULO 4

typedef struct Decor {
    int clase;
    int tipo;            /* DataType como entero */
    int dims, filas, cols, abierto;
    int global;
    int offset;          /* direccion DMEM si global, desplazamiento de R14 si local */
    int size_bytes;
    long valor;          /* valor de una constans plegada */
    int tiene_valor;
    int marco;           /* solo funciones: bytes del marco local */
    int n_params;        /* solo funciones: cantidad de parametros */
    int privada;
    int es_cauda;        /* solo funciones: marcada con @cauda */
} Decor;

typedef struct Nodo {
    TipoNodo tipo;
    char *texto;
    long valor;
    int linea;
    int columna;

    char *modulo;
    char *tipo_resuelto;
    Decor *dec;          /* decoracion de la fase 3; NULL si no aplica */

    struct Nodo *hijo;
    struct Nodo *sig;
} Nodo;

extern Nodo *raiz_ast;

Nodo *nodo_nuevo(TipoNodo tipo, char *texto, long valor, int linea, int columna);
Nodo *fijar_modulo(Nodo *n, char *modulo);
/* Crea la decoracion del nodo si no existe y la devuelve. */
Decor *nodo_decorar(Nodo *n);
Nodo *agregar_hijo(Nodo *padre, Nodo *hijo);
Nodo *anteponer_hijo(Nodo *padre, Nodo *hijo);
Nodo *cadena_agregar(Nodo *cadena, Nodo *nuevo);
Nodo *copiar_ast(const Nodo *n);
Nodo *nodo_asignacion(Nodo *destino, const char *op, Nodo *valor, int linea, int columna);
Nodo *binario(const char *op, Nodo *izq, Nodo *der, int linea, int columna);
Nodo *unario(const char *op, Nodo *operando, int linea, int columna);

void imprimir_ast(FILE *out, Nodo *raiz);
void liberar_ast(Nodo *raiz);

#endif