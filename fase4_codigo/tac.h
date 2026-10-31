#ifndef TAC_H
#define TAC_H

/*
 * Codigo intermedio de tres direcciones (Fase 4a).
 *
 * Es el repertorio que promete el documento, sobre una maquina abstracta con
 * registros virtuales ilimitados. Aqui se separa todo lo que no depende del
 * procesador de lo que si: esta lista es independiente de CERBERO, y es
 * codegen.c quien la traduce a bundles.
 *
 * Cada instruccion tiene a lo sumo un destino y dos operandos, mas un entero
 * auxiliar que lleva lo que no es un nombre (la posicion de un argumento, el
 * numero de dimension de longitudo, la palabra de una llave).
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "ast.h"
#include "symtab.h"

typedef enum {
    TAC_NOP,

    /* Aritmetica y bits:  result = arg1 op arg2 */
    TAC_ADD, TAC_SUB, TAC_MUL, TAC_DIV, TAC_MOD,
    TAC_AND, TAC_OR, TAC_XOR,
    TAC_SHL,        /* <<   desplazamiento a la izquierda          */
    TAC_SHR,        /* >>   desplazamiento aritmetico (con signo)   */
    TAC_USHR,       /* >>>  desplazamiento logico (relleno de ceros)*/

    /* Comparaciones: result = arg1 op arg2, con result en 0 o 1 */
    TAC_EQ, TAC_NE, TAC_LT, TAC_LE, TAC_GT, TAC_GE,

    /* Unarias: result = op arg1 */
    TAC_NEG,        /* -a            */
    TAC_BITNOT,     /* ~a            */
    TAC_NOT,        /* non a         */

    /* Movimiento de datos */
    TAC_ASSIGN,     /* result = arg1            */
    TAC_CONST,      /* result = #valor          */
    TAC_STR,        /* result = direccion del literal de cadena arg1 */

    /* Arreglos. El indice ya viene linealizado por filas. */
    TAC_LOAD,       /* result = arg1[arg2]      */
    TAC_STORE,      /* result[arg1] = arg2      */
    TAC_ADDR,       /* result = &arg1           */
    TAC_LEN,        /* result = longitudo arg1, dimension aux */
    TAC_CHECK,      /* check arg1 contra el limite arg2 */

    /* Control de flujo */
    TAC_LABEL,      /* result:                  */
    TAC_GOTO,       /* goto result              */
    TAC_IF_FALSE,   /* ifFalse arg1 goto result */
    TAC_IF_TRUE,    /* ifTrue  arg1 goto result */

    /* Funciones */
    TAC_FUNC_BEGIN, /* comienza la funcion result */
    TAC_FUNC_END,   /* termina la funcion result  */
    TAC_PARAM,      /* param arg1 en la posicion aux (en palabras) */
    TAC_CALL,       /* result = call arg1, aux palabras de argumento */
    TAC_TAILCALL,   /* @cauda: reasigna los parametros y vuelve al inicio */
    TAC_RET,        /* ret                      */
    TAC_RET_VAL,    /* ret arg1                 */

    /* Boveda y unidad criptografica */
    TAC_AUTHW,      /* authw palabra aux con el valor arg1 */
    TAC_VAULT_LOGIN,
    TAC_VAULT_LOGOUT,
    TAC_KSETW,      /* ksetw ranura arg1, palabra aux, valor arg2 */
    TAC_FEISTEL,    /* feistel sobre arg1 con la ranura arg2 y la ronda aux */
    TAC_FEISTEL_DECRYPT, /* feistel inverso sobre arg1 */

    TAC_HALT
} TACOp;

typedef struct TACInst {
    TACOp op;
    char *result;
    char *arg1;
    char *arg2;
    long valor;            /* TAC_CONST */
    int aux;               /* posicion, dimension, palabra, cantidad */
    int linea;             /* para los diagnosticos de la fase 4 */
    int columna;           /* y para anotar el ensamblador y el listado */
    struct TACInst *next;
} TACInst;

/*
 * Donde vive cada nombre, copiado de la decoracion que dejo la fase 3. Hace
 * falta porque los ambitos locales de la tabla de simbolos se cierran al
 * terminar el analisis semantico: esta lista es lo que sobrevive hasta la
 * generacion de codigo.
 */
typedef struct TACSimbolo {
    char *nombre;
    char *funcion;        /* a que funcion pertenece */
    int es_param;
    int posicion;         /* palabra de argumento donde llega, 1..n */
    int offset;           /* desplazamiento que calculo la fase 3 (negativo) */
    int size_bytes;
    int dims, filas, cols, abierto;
    int tipo;
    struct TACSimbolo *next;
} TACSimbolo;

/* Literal de cadena con la direccion que le asigna el compilador. */
typedef struct TACCadena {
    char *etiqueta;
    char *texto;
    struct TACCadena *next;
} TACCadena;

typedef struct TACList {
    TACInst *head;
    TACInst *tail;
    TACCadena *cadenas;    /* literales a emitir en .data */
    TACCadena *cadenas_fin;
    int n_cadenas;
    TACSimbolo *simbolos;  /* locales y parametros de todas las funciones */
    TACSimbolo *simbolos_fin;
} TACList;

/* --- Construccion --- */
TACList *tac_create_list(void);
TACInst *tac_append(TACList *list, TACOp op, const char *res,
                    const char *a1, const char *a2);
void tac_concat(TACList *dest, TACList *src);
void tac_free(TACList *list);

char *tac_new_temp(void);
char *tac_new_label(void);
void tac_reset_contadores(void);

/* --- Generacion desde el AST --- */
TACList *tac_generate_from_ast(Nodo *root, SymbolTable *st);

/* --- Salida legible (--ir) --- */
void tac_print(FILE *out, TACList *list);

/* --- Consultas que necesita codegen.c --- */
bool tac_es_temporal(const char *nombre);
/* Busca un local o parametro por funcion y nombre. */
const TACSimbolo *tac_buscar_simbolo(const TACList *l, const char *funcion,
                                     const char *nombre);
const char *tac_op_nombre(TACOp op);

#endif /* TAC_H */
