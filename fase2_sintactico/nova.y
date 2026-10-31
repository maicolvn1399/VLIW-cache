%{
/* Parser de Nova para la fase 2.
 * Aqui se define la gramatica y se construye el AST. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "diag.h"

extern char *yytext;
extern FILE *yyin;
extern int prev_fin_linea, prev_fin_col;
extern int tok_prev_malo;
int llave_abierta(int *lin, int *col);
int yylex(void);
void yyerror(const char *msg);
static void err_esperaba(const char *que);
/* Tras un E203 (falta un '}'), el resto del archivo ya no tiene estructura
 * confiable: los errores sintacticos siguientes serian ruido en cascada. */
static int sint_suprimido = 0;
static int cierra_sentencia(int tok);

int errores_sintacticos = 0;
Nodo *raiz_ast = NULL;

void nova_parser_reset(void) {
    sint_suprimido = 0;
    errores_sintacticos = 0;
    raiz_ast = NULL;
}
%}

%union {
    long entero;
    char *texto;
    struct Nodo *nodo;
}

/* Cada regla guarda su posicion para marcar mejor la linea del nodo. */
%locations

/* Los errores de Bison se muestran de forma mas legible. */
%define parse.error verbose

/* Si hay un error, liberamos los nodos parciales que quedaron en la pila. */
%destructor { liberar_ast($$); } <nodo>

/* La raiz se deja para que main() pueda imprimir el AST final. */
%destructor { /* no liberar: main() todavia necesita raiz_ast */ } programa

/* Si queda texto suelto por un error, tambien se libera. */
%destructor { free($$); } <texto>

/* ---- Tokens con valor semantico ---- */
%token <texto> TK_IDENT TK_CADENA
%token <entero> TK_ENTERO

/* ---- Palabras reservadas ---- */
%token TK_FUNCTIO TK_VARIA TK_CONSTANS TK_PRIVATUM TK_IMPORTA TK_UT TK_REDDE
%token TK_SI TK_SIN TK_ALITER TK_DUM TK_PER TK_RUMPE TK_PERGE
%token TK_TIPO_INTEGER TK_TIPO_VERITAS TK_TIPO_TEXTUS TK_TIPO_NIHIL
%token TK_VERUM TK_FALSUM

/* ---- Delimitadores y simbolos especiales ---- */
%token TK_PAR_IZQ TK_PAR_DER TK_LLAVE_IZQ TK_LLAVE_DER
%token TK_COR_IZQ TK_COR_DER TK_PUNTO_COMA TK_COMA
%token TK_DOS_PUNTOS TK_PUNTO TK_FLECHA TK_ARROBA
%token TK_ASIGNA TK_ASIGNA_MAS TK_ASIGNA_MENOS TK_ASIGNA_POR TK_ASIGNA_ENTRE TK_ASIGNA_MODULO

/* ---- Operadores con precedencia ---- */
%left TK_AUT
%left TK_ET
%left TK_BARRA
%left TK_XOR
%left TK_AMPERSAND
%left TK_IGUAL TK_DIFERENTE
%left TK_MENOR TK_MENOR_IGUAL TK_MAYOR TK_MAYOR_IGUAL
%left TK_DESP_IZQ TK_DESP_DER TK_DESP_LOG
%left TK_MAS TK_MENOS
%left TK_POR TK_ENTRE TK_MODULO
%precedence TK_NON TK_NOT UMENOS

%type <nodo> programa importaciones_opt importacion
%type <nodo> declaraciones_globales_opt declaracion_global
%type <nodo> anotaciones anotacion privatum_opt
%type <nodo> decl_func parametros_opt parametros parametro
%type <nodo> decl_const decl_var
%type <nodo> tipo tipo_param dims dims_param
%type <nodo> bloque sentencias_opt sentencia
%type <nodo> inicializador lista_valores lista_inicializadores
%type <nodo> sent_asignacion asignacion designador
%type <nodo> sent_si cola_si
%type <nodo> sent_dum sent_per per_init
%type <nodo> sent_redde sent_rumpe sent_perge
%type <nodo> sent_llamada llamada_expr lista_argumentos argumentos
%type <nodo> expresion referencia nombre_ref

%start programa

%%

/* Regla principal: el programa puede tener imports y declaraciones globales. */
programa
    : importaciones_opt declaraciones_globales_opt
        {
            raiz_ast = nodo_nuevo(NODO_PROGRAMA, NULL, 0, 1, 1);
            agregar_hijo(raiz_ast, agregar_hijo(nodo_nuevo(NODO_IMPORTS, NULL, 0, 1, 1), $1));
            agregar_hijo(raiz_ast, agregar_hijo(nodo_nuevo(NODO_GLOBALES, NULL, 0, 1, 1), $2));
            $$ = raiz_ast;
        }
    ;

/* Importaciones */
importaciones_opt
    : %empty                       { $$ = NULL; }
    | importaciones_opt importacion     { $$ = cadena_agregar($1, $2); }
    ;

importacion
    : TK_IMPORTA TK_CADENA TK_PUNTO_COMA
        { $$ = nodo_nuevo(NODO_IMPORT, $2, 0, @$.first_line, @$.first_column); }
    | TK_IMPORTA TK_CADENA TK_UT TK_IDENT TK_PUNTO_COMA
        {
            $$ = nodo_nuevo(NODO_IMPORT, $2, 0, @$.first_line, @$.first_column);
            agregar_hijo($$, nodo_nuevo(NODO_ALIAS, $4, 0, @$.first_line, @$.first_column));
        }
    ;

/* Declaraciones globales */
declaraciones_globales_opt
    : %empty                                   { $$ = NULL; }
    | declaraciones_globales_opt declaracion_global { $$ = cadena_agregar($1, $2); }
    ;

/* Las anotaciones solo preceden a funciones. 'varia' no es valida fuera de
 * una funcion (E320), pero se reconoce para dar un error claro y seguir.
 * 'error' es la recuperacion en modo panico: descarta tokens hasta el inicio
 * de la siguiente declaracion global. */
declaracion_global
    : anotaciones privatum_opt decl_func
        { $$ = $3; agregar_hijo($$, $1); agregar_hijo($$, $2); }
    | privatum_opt decl_func
        { $$ = $2; agregar_hijo($$, $1); }
    | privatum_opt decl_const
        { $$ = $2; agregar_hijo($$, $1); }
    | decl_var
        {
            diag_error("E320", @1.first_line, @1.first_column, 5,
                       "declaracion global que no es 'constans': fuera de las funciones solo se admiten 'constans' y 'functio'");
            liberar_ast($1);
            $$ = NULL;
        }
    | error
        { $$ = NULL; }
    ;

privatum_opt
    : %empty   { $$ = NULL; }
    | TK_PRIVATUM   { $$ = nodo_nuevo(NODO_PRIVATUM, NULL, 0, @$.first_line, @$.first_column); }
    ;

anotaciones
    : anotacion                 { $$ = $1; }
    | anotaciones anotacion     { $$ = cadena_agregar($1, $2); }
    ;

anotacion
    : TK_ARROBA TK_IDENT
        { $$ = nodo_nuevo(NODO_ANOTACION, $2, 0, @$.first_line, @$.first_column); }
    | TK_ARROBA TK_IDENT TK_PAR_IZQ TK_CADENA TK_PAR_DER
        {
            $$ = nodo_nuevo(NODO_ANOTACION, $2, 0, @$.first_line, @$.first_column);
            agregar_hijo($$, nodo_nuevo(NODO_CADENA, $4, 0, @$.first_line, @$.first_column));
        }
    ;

decl_func
    : TK_FUNCTIO TK_IDENT TK_PAR_IZQ parametros_opt TK_PAR_DER TK_FLECHA tipo bloque
        {
            $$ = nodo_nuevo(NODO_FUNCION, $2, 0, @2.first_line, @2.first_column);
            agregar_hijo($$, agregar_hijo(nodo_nuevo(NODO_PARAMETROS, NULL, 0, @$.first_line, @$.first_column), $4));
            agregar_hijo($$, $7);
            agregar_hijo($$, $8);
        }
    ;

parametros_opt
    : %empty   { $$ = NULL; }
    | parametros    { $$ = $1; }
    ;

parametros
    : parametro                      { $$ = $1; }
    | parametros TK_COMA parametro   { $$ = cadena_agregar($1, $3); }
    ;

parametro
    : TK_IDENT TK_DOS_PUNTOS tipo_param
        { $$ = nodo_nuevo(NODO_PARAMETRO, $1, 0, @$.first_line, @$.first_column); agregar_hijo($$, $3); }
    ;

decl_const
    : TK_CONSTANS TK_IDENT TK_DOS_PUNTOS tipo TK_ASIGNA expresion fin_sent
        {
            $$ = nodo_nuevo(NODO_CONSTANTE, $2, 0, @2.first_line, @2.first_column);
            agregar_hijo($$, $4);
            agregar_hijo($$, $6);
        }
    ;

/* Las declaraciones guardan la posicion del IDENT ($2), no la de la palabra
 * reservada, para que la marca de los diagnosticos semanticos (E302, E309,
 * W001, W002) caiga sobre el nombre y no sobre 'functio' o 'varia'. */

/* Tipos y dimensiones */
tipo
    : TK_TIPO_INTEGER dims   { $$ = nodo_nuevo(NODO_TIPO, strdup("integer"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_VERITAS dims   { $$ = nodo_nuevo(NODO_TIPO, strdup("veritas"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_TEXTUS dims    { $$ = nodo_nuevo(NODO_TIPO, strdup("textus"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_NIHIL dims     { $$ = nodo_nuevo(NODO_TIPO, strdup("nihil"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    ;

dims
    : %empty                                            { $$ = NULL; }
    | TK_COR_IZQ expresion TK_COR_DER
        { $$ = agregar_hijo(nodo_nuevo(NODO_DIMENSION, NULL, 0, @1.first_line, @1.first_column), $2); }
    | TK_COR_IZQ expresion TK_COR_DER TK_COR_IZQ expresion TK_COR_DER
        { $$ = cadena_agregar(agregar_hijo(nodo_nuevo(NODO_DIMENSION, NULL, 0, @1.first_line, @1.first_column), $2),
                              agregar_hijo(nodo_nuevo(NODO_DIMENSION, NULL, 0, @4.first_line, @4.first_column), $5)); }
    ;

tipo_param
    : TK_TIPO_INTEGER dims_param   { $$ = nodo_nuevo(NODO_TIPO, strdup("integer"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_VERITAS dims_param   { $$ = nodo_nuevo(NODO_TIPO, strdup("veritas"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_TEXTUS dims_param    { $$ = nodo_nuevo(NODO_TIPO, strdup("textus"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    | TK_TIPO_NIHIL dims_param     { $$ = nodo_nuevo(NODO_TIPO, strdup("nihil"), 0, @$.first_line, @$.first_column); agregar_hijo($$, $2); }
    ;

/* Un parametro es o totalmente dimensionado (dims) o totalmente abierto:
 * no se pueden mezclar, y el maximo es de dos dimensiones. */
dims_param
    : dims
    | TK_COR_IZQ TK_COR_DER
        { $$ = nodo_nuevo(NODO_DIM_ABIERTA, NULL, 0, @1.first_line, @1.first_column); }
    | TK_COR_IZQ TK_COR_DER TK_COR_IZQ TK_COR_DER
        { $$ = cadena_agregar(nodo_nuevo(NODO_DIM_ABIERTA, NULL, 0, @1.first_line, @1.first_column),
                              nodo_nuevo(NODO_DIM_ABIERTA, NULL, 0, @3.first_line, @3.first_column)); }
    ;

/* Bloques y sentencias */
bloque
    : TK_LLAVE_IZQ sentencias_opt TK_LLAVE_DER
        { $$ = agregar_hijo(nodo_nuevo(NODO_BLOQUE, NULL, 0, @$.first_line, @$.first_column), $2); }
    ;

sentencias_opt
    : %empty                  { $$ = NULL; }
    | sentencias_opt sentencia     { $$ = cadena_agregar($1, $2); }
    ;

sentencia
    : decl_var          { $$ = $1; }
    | decl_const         { $$ = $1; }
    | sent_asignacion     { $$ = $1; }
    | sent_si              { $$ = $1; }
    | sent_dum              { $$ = $1; }
    | sent_per               { $$ = $1; }
    | sent_redde              { $$ = $1; }
    | sent_rumpe               { $$ = $1; }
    | sent_perge                { $$ = $1; }
    | sent_llamada                { $$ = $1; }
    | bloque                       { $$ = $1; }
    | error TK_PUNTO_COMA          { $$ = NULL; yyerrok; }
    | error                        { $$ = NULL; }
    ;

/* Fin de sentencia. Si falta el ';' y lo que sigue empieza otra sentencia (o
 * cierra el bloque), se inserta virtualmente: se reporta E202 y el analisis
 * continua sin descartar nada (correccion a nivel de frase). */
fin_sent
    : TK_PUNTO_COMA
    | %empty
        {
            if (cierra_sentencia(yychar)) {
                if (!tok_prev_malo && !sint_suprimido)
                    diag_error("E202", prev_fin_linea, prev_fin_col, 1,
                               "falta ';' al final de la sentencia");
            } else {
                err_esperaba("';'");
                YYERROR;
            }
        }
    ;

/* El ')' que cierra la condicion de si/sin/dum/per se corrige igual. */
cierra_par
    : TK_PAR_DER
    | %empty
        {
            if (yychar == TK_LLAVE_IZQ) {
                if (!sint_suprimido)
                    diag_error("E201", yylloc.first_line, yylloc.first_column, 1,
                               "se esperaba ')' pero se encontro '{'");
            } else {
                err_esperaba("')'");
                YYERROR;
            }
        }
    ;

decl_var
    : TK_VARIA TK_IDENT TK_DOS_PUNTOS tipo fin_sent
        { $$ = nodo_nuevo(NODO_VARIABLE, $2, 0, @2.first_line, @2.first_column); agregar_hijo($$, $4); }
    | TK_VARIA TK_IDENT TK_DOS_PUNTOS tipo TK_ASIGNA inicializador fin_sent
        { $$ = nodo_nuevo(NODO_VARIABLE, $2, 0, @2.first_line, @2.first_column); agregar_hijo($$, $4); agregar_hijo($$, $6); }
    ;

inicializador
    : expresion      { $$ = $1; }
    | lista_valores  { $$ = $1; }
    ;

lista_valores
    : TK_LLAVE_IZQ TK_LLAVE_DER
        { $$ = nodo_nuevo(NODO_LISTA_VALORES, NULL, 0, @$.first_line, @$.first_column); }
    | TK_LLAVE_IZQ lista_inicializadores TK_LLAVE_DER
        { $$ = agregar_hijo(nodo_nuevo(NODO_LISTA_VALORES, NULL, 0, @$.first_line, @$.first_column), $2); }
    ;

lista_inicializadores
    : inicializador                               { $$ = $1; }
    | lista_inicializadores TK_COMA inicializador { $$ = cadena_agregar($1, $3); }
    ;

sent_asignacion
    : asignacion fin_sent { $$ = $1; }
    ;

/* Las asignaciones compuestas se expanden a la forma simple. */
asignacion
    : designador TK_ASIGNA expresion
        { $$ = nodo_asignacion($1, NULL, $3, @$.first_line, @$.first_column); }
    | designador TK_ASIGNA_MAS expresion
        { $$ = nodo_asignacion($1, "+", $3, @$.first_line, @$.first_column); }
    | designador TK_ASIGNA_MENOS expresion
        { $$ = nodo_asignacion($1, "-", $3, @$.first_line, @$.first_column); }
    | designador TK_ASIGNA_POR expresion
        { $$ = nodo_asignacion($1, "*", $3, @$.first_line, @$.first_column); }
    | designador TK_ASIGNA_ENTRE expresion
        { $$ = nodo_asignacion($1, "/", $3, @$.first_line, @$.first_column); }
    | designador TK_ASIGNA_MODULO expresion
        { $$ = nodo_asignacion($1, "%", $3, @$.first_line, @$.first_column); }
    ;

/* Maximo dos indices, igual que el maximo de dimensiones. */
designador
    : TK_IDENT
        { $$ = nodo_nuevo(NODO_IDENT, $1, 0, @$.first_line, @$.first_column); }
    | TK_IDENT TK_COR_IZQ expresion TK_COR_DER
        {
            Nodo *base = nodo_nuevo(NODO_IDENT, $1, 0, @1.first_line, @1.first_column);
            $$ = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @$.first_line, @$.first_column), base);
            agregar_hijo($$, $3);
        }
    | TK_IDENT TK_COR_IZQ expresion TK_COR_DER TK_COR_IZQ expresion TK_COR_DER
        {
            Nodo *base = nodo_nuevo(NODO_IDENT, $1, 0, @1.first_line, @1.first_column);
            Nodo *fila = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @1.first_line, @1.first_column), base);
            agregar_hijo(fila, $3);
            $$ = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @$.first_line, @$.first_column), fila);
            agregar_hijo($$, $6);
        }
    ;

/* 'sin' se convierte en una cadena de ifs anidados. */
sent_si
    : TK_SI TK_PAR_IZQ expresion cierra_par bloque cola_si
        {
            $$ = nodo_nuevo(NODO_SI, NULL, 0, @$.first_line, @$.first_column);
            agregar_hijo($$, $3);
            agregar_hijo($$, $5);
            agregar_hijo($$, $6);
        }
    ;

cola_si
    : %empty   { $$ = NULL; }
    | TK_ALITER bloque
        { $$ = $2; }
    | TK_SIN TK_PAR_IZQ expresion cierra_par bloque cola_si
        {
            Nodo *interno = nodo_nuevo(NODO_SI, NULL, 0, @1.first_line, @1.first_column);
            agregar_hijo(interno, $3);
            agregar_hijo(interno, $5);
            agregar_hijo(interno, $6);
            $$ = agregar_hijo(nodo_nuevo(NODO_BLOQUE, NULL, 0, @1.first_line, @1.first_column), interno);
        }
    ;

sent_dum
    : TK_DUM TK_PAR_IZQ expresion cierra_par bloque
        { $$ = nodo_nuevo(NODO_DUM, NULL, 0, @$.first_line, @$.first_column); agregar_hijo($$, $3); agregar_hijo($$, $5); }
    ;

sent_per
    : TK_PER TK_PAR_IZQ per_init TK_PUNTO_COMA expresion TK_PUNTO_COMA asignacion cierra_par bloque
        {
            $$ = nodo_nuevo(NODO_PER, NULL, 0, @$.first_line, @$.first_column);
            agregar_hijo($$, $3);
            agregar_hijo($$, $5);
            agregar_hijo($$, $7);
            agregar_hijo($$, $9);
        }
    ;

per_init
    : TK_VARIA TK_IDENT TK_DOS_PUNTOS tipo TK_ASIGNA expresion
        { $$ = nodo_nuevo(NODO_VARIABLE, $2, 0, @2.first_line, @2.first_column); agregar_hijo($$, $4); agregar_hijo($$, $6); }
    | asignacion
        { $$ = $1; }
    ;

sent_redde
    : TK_REDDE TK_PUNTO_COMA
        { $$ = nodo_nuevo(NODO_REDDE, NULL, 0, @$.first_line, @$.first_column); }
    | TK_REDDE expresion fin_sent
        { $$ = agregar_hijo(nodo_nuevo(NODO_REDDE, NULL, 0, @$.first_line, @$.first_column), $2); }
    ;

sent_rumpe
    : TK_RUMPE fin_sent  { $$ = nodo_nuevo(NODO_RUMPE, NULL, 0, @$.first_line, @$.first_column); }
    ;

sent_perge
    : TK_PERGE fin_sent  { $$ = nodo_nuevo(NODO_PERGE, NULL, 0, @$.first_line, @$.first_column); }
    ;

sent_llamada
    : llamada_expr fin_sent { $$ = $1; }
    ;

llamada_expr
    : TK_IDENT TK_PAR_IZQ lista_argumentos TK_PAR_DER
        { $$ = nodo_nuevo(NODO_LLAMADA, $1, 0, @$.first_line, @$.first_column); agregar_hijo($$, $3); }
    | TK_IDENT TK_PUNTO TK_IDENT TK_PAR_IZQ lista_argumentos TK_PAR_DER
        {
            $$ = fijar_modulo(nodo_nuevo(NODO_LLAMADA, $3, 0, @$.first_line, @$.first_column), $1);
            agregar_hijo($$, $5);
        }
    ;

lista_argumentos
    : %empty  { $$ = NULL; }
    | argumentos   { $$ = $1; }
    ;

argumentos
    : expresion
        {
            $$ = nodo_nuevo(NODO_ARGUMENTOS, NULL, 0, @$.first_line, @$.first_column);
            agregar_hijo($$, $1);
        }
    | argumentos TK_COMA expresion
        {
            $$ = $1;
            agregar_hijo($$, $3);
        }
    ;

/* Expresiones. La precedencia la resuelve Bison con las reglas %left/%right. */
expresion
    : expresion TK_AUT expresion         { $$ = binario("aut", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_ET expresion          { $$ = binario("et", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_BARRA expresion       { $$ = binario("|", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_XOR expresion         { $$ = binario("^", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_AMPERSAND expresion   { $$ = binario("&", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_IGUAL expresion       { $$ = binario("==", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_DIFERENTE expresion   { $$ = binario("!=", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MENOR expresion       { $$ = binario("<", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MENOR_IGUAL expresion { $$ = binario("<=", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MAYOR expresion       { $$ = binario(">", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MAYOR_IGUAL expresion { $$ = binario(">=", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_DESP_IZQ expresion    { $$ = binario("<<", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_DESP_DER expresion    { $$ = binario(">>", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_DESP_LOG expresion    { $$ = binario(">>>", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MAS expresion         { $$ = binario("+", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MENOS expresion       { $$ = binario("-", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_POR expresion         { $$ = binario("*", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_ENTRE expresion       { $$ = binario("/", $1, $3, @$.first_line, @$.first_column); }
    | expresion TK_MODULO expresion      { $$ = binario("%", $1, $3, @$.first_line, @$.first_column); }
    | TK_MENOS expresion %prec UMENOS    { $$ = unario("-", $2, @$.first_line, @$.first_column); }
    | TK_NON expresion                   { $$ = unario("non", $2, @$.first_line, @$.first_column); }
    | TK_NOT expresion                   { $$ = unario("~", $2, @$.first_line, @$.first_column); }
    | TK_PAR_IZQ expresion TK_PAR_DER    { $$ = $2; }
    | referencia                          { $$ = $1; }
    | TK_ENTERO                            { $$ = nodo_nuevo(NODO_ENTERO, NULL, $1, @$.first_line, @$.first_column); }
    | TK_CADENA                             { $$ = nodo_nuevo(NODO_CADENA, $1, 0, @$.first_line, @$.first_column); }
    | TK_VERUM                               { $$ = nodo_nuevo(NODO_BOOLEANO, strdup("verum"), 1, @$.first_line, @$.first_column); }
    | TK_FALSUM                               { $$ = nodo_nuevo(NODO_BOOLEANO, strdup("falsum"), 0, @$.first_line, @$.first_column); }
    ;

/* Maximo dos indices. Una llamada no se puede indexar: las funciones no
 * retornan arreglos, asi que f(x)[0] no tendria sentido. */
referencia
    : nombre_ref
        { $$ = $1; }
    | nombre_ref TK_COR_IZQ expresion TK_COR_DER
        { $$ = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @$.first_line, @$.first_column), $1); agregar_hijo($$, $3); }
    | nombre_ref TK_COR_IZQ expresion TK_COR_DER TK_COR_IZQ expresion TK_COR_DER
        {
            Nodo *fila = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @1.first_line, @1.first_column), $1);
            agregar_hijo(fila, $3);
            $$ = agregar_hijo(nodo_nuevo(NODO_INDICE, NULL, 0, @$.first_line, @$.first_column), fila);
            agregar_hijo($$, $6);
        }
    | llamada_expr
        { $$ = $1; }
    ;

nombre_ref
    : TK_IDENT
        { $$ = nodo_nuevo(NODO_IDENT, $1, 0, @$.first_line, @$.first_column); }
    | TK_IDENT TK_PUNTO TK_IDENT
        { $$ = fijar_modulo(nodo_nuevo(NODO_IDENT, $3, 0, @$.first_line, @$.first_column), $1); }
    ;

%%

/* Diagnosticos sintacticos. Convertimos el error tecnico de Bison en
 * mensajes mas claros con codigo E2xx. */
typedef struct { const char *nombre; const char *texto; } NombreTok;

static const NombreTok nombres_tok[] = {
    {"TK_FUNCTIO","functio"}, {"TK_VARIA","varia"}, {"TK_CONSTANS","constans"},
    {"TK_PRIVATUM","privatum"}, {"TK_IMPORTA","importa"}, {"TK_UT","ut"},
    {"TK_REDDE","redde"}, {"TK_SI","si"}, {"TK_SIN","sin"}, {"TK_ALITER","aliter"},
    {"TK_DUM","dum"}, {"TK_PER","per"}, {"TK_RUMPE","rumpe"}, {"TK_PERGE","perge"},
    {"TK_TIPO_INTEGER","integer"}, {"TK_TIPO_VERITAS","veritas"},
    {"TK_TIPO_TEXTUS","textus"}, {"TK_TIPO_NIHIL","nihil"},
    {"TK_ET","et"}, {"TK_AUT","aut"}, {"TK_NON","non"},
    {"TK_VERUM","verum"}, {"TK_FALSUM","falsum"},
    {"TK_MAS","+"}, {"TK_MENOS","-"}, {"TK_POR","*"}, {"TK_ENTRE","/"}, {"TK_MODULO","%"},
    {"TK_IGUAL","=="}, {"TK_DIFERENTE","!="}, {"TK_MENOR","<"}, {"TK_MENOR_IGUAL","<="},
    {"TK_MAYOR",">"}, {"TK_MAYOR_IGUAL",">="},
    {"TK_ASIGNA","="}, {"TK_ASIGNA_MAS","+="}, {"TK_ASIGNA_MENOS","-="},
    {"TK_ASIGNA_POR","*="}, {"TK_ASIGNA_ENTRE","/="}, {"TK_ASIGNA_MODULO","%="},
    {"TK_PAR_IZQ","("}, {"TK_PAR_DER",")"}, {"TK_LLAVE_IZQ","{"}, {"TK_LLAVE_DER","}"},
    {"TK_COR_IZQ","["}, {"TK_COR_DER","]"}, {"TK_PUNTO_COMA",";"}, {"TK_COMA",","},
    {"TK_DOS_PUNTOS",":"}, {"TK_PUNTO","."}, {"TK_FLECHA","->"}, {"TK_ARROBA","@"},
    {"TK_AMPERSAND","&"}, {"TK_BARRA","|"}, {"TK_XOR","^"}, {"TK_NOT","~"},
    {"TK_DESP_IZQ","<<"}, {"TK_DESP_DER",">>"}, {"TK_DESP_LOG",">>>"}
};

static const char *texto_tok(const char *nombre) {
    size_t i;
    for (i = 0; i < sizeof(nombres_tok) / sizeof(nombres_tok[0]); i++)
        if (strcmp(nombres_tok[i].nombre, nombre) == 0) return nombres_tok[i].texto;
    return NULL;
}

/* Traduce el nombre de un token a texto legible para el error. */
static void mostrar_tok(const char *nombre, int es_el_encontrado, char *out, size_t cap) {
    const char *t;
    if (strcmp(nombre, "$end") == 0 || strcmp(nombre, "end of file") == 0)
        snprintf(out, cap, "fin de archivo");
    else if (strcmp(nombre, "TK_IDENT") == 0)
        { if (es_el_encontrado) snprintf(out, cap, "'%s'", yytext); else snprintf(out, cap, "un identificador"); }
    else if (strcmp(nombre, "TK_ENTERO") == 0)
        { if (es_el_encontrado) snprintf(out, cap, "'%s'", yytext); else snprintf(out, cap, "un numero"); }
    else if (strcmp(nombre, "TK_CADENA") == 0)
        snprintf(out, cap, "una cadena");
    else if ((t = texto_tok(nombre)) != NULL)
        snprintf(out, cap, "'%s'", t);
    else
        snprintf(out, cap, "'%s'", nombre);
}

/* Tokens que pueden venir despues de una sentencia completa: el inicio de otra
 * sentencia, el cierre del bloque o el inicio de otra declaracion global. Si
 * falta un ';' y el siguiente token es uno de estos, el ';' se inserta. */
static int cierra_sentencia(int tok) {
    switch (tok) {
        case TK_IDENT: case TK_VARIA: case TK_CONSTANS: case TK_SI: case TK_DUM:
        case TK_PER: case TK_REDDE: case TK_RUMPE: case TK_PERGE:
        case TK_LLAVE_IZQ: case TK_LLAVE_DER:
        case TK_FUNCTIO: case TK_ARROBA: case TK_PRIVATUM:
        case 0:  /* fin de archivo */
            return 1;
        default:
            return 0;
    }
}

/* Error "se esperaba X pero se encontro Y" sobre el token de anticipacion. */
static void err_esperaba(const char *que) {
    char vista[96];
    int largo = 1;
    const char *nombre = (yychar > 0) ? yytname[YYTRANSLATE(yychar)] : "$end";

    if (sint_suprimido) return;
    mostrar_tok(nombre, 1, vista, sizeof(vista));
    if (yylloc.last_line == yylloc.first_line && yylloc.last_column > yylloc.first_column)
        largo = yylloc.last_column - yylloc.first_column;
    diag_error("E201", yylloc.first_line, yylloc.first_column, largo,
               "se esperaba %s pero se encontro %s", que, vista);
}

#define MAX_ESP 8

void yyerror(const char *msg) {
    char inesp[64] = "", esp[MAX_ESP][64];
    char vista[96], lista[512] = "", texto[700];
    int nesp = 0, i;
    const char *p;

    /* Leemos el token inesperado y lo que Bison esperaba. */
    p = strstr(msg, "unexpected ");
    if (p != NULL) {
        size_t n;
        p += strlen("unexpected ");
        n = strcspn(p, ",");
        if (n > sizeof(inesp) - 1) n = sizeof(inesp) - 1;
        memcpy(inesp, p, n); inesp[n] = '\0';
    }
    p = strstr(msg, "expecting ");
    if (p != NULL) {
        p += strlen("expecting ");
        while (*p != '\0' && nesp < MAX_ESP) {
            const char *sep = strstr(p, " or ");
            size_t n = sep ? (size_t)(sep - p) : strlen(p);
            if (n > sizeof(esp[0]) - 1) n = sizeof(esp[0]) - 1;
            memcpy(esp[nesp], p, n); esp[nesp][n] = '\0';
            nesp++;
            if (sep == NULL) break;
            p = sep + 4;
        }
    }

    {
        int es_eof = (strcmp(inesp, "$end") == 0 || strcmp(inesp, "end of file") == 0);
        int ll0, lc0;
        int linea = yylloc.first_line, col = yylloc.first_column, largo = 1;
        const char *codigo = "E201";

        if (yylloc.last_line == yylloc.first_line && yylloc.last_column > yylloc.first_column)
            largo = yylloc.last_column - yylloc.first_column;

        mostrar_tok(inesp, 1, vista, sizeof(vista));
        for (i = 0; i < nesp; i++) {
            char una[96];
            mostrar_tok(esp[i], 0, una, sizeof(una));
            if (i > 0) strncat(lista, " o ", sizeof(lista) - strlen(lista) - 1);
            strncat(lista, una, sizeof(lista) - strlen(lista) - 1);
        }

        if (!strcmp(inesp, "TK_SIN") || !strcmp(inesp, "TK_ALITER")) {
            codigo = "E205";
            snprintf(texto, sizeof(texto), "%s sin un 'si' correspondiente", vista);
        } else if (!strcmp(inesp, "TK_FUNCTIO") && llave_abierta(&ll0, &lc0)) {
            /* 'functio' no puede ir dentro de otra funcion: casi seguro falta un '}' */
            codigo = "E203";
            linea = ll0; col = lc0; largo = 1;
            snprintf(texto, sizeof(texto), "'{' abierto en la linea %d nunca se cierra", ll0);
            if (!sint_suprimido) { diag_error(codigo, linea, col, largo, "%s", texto); }
            sint_suprimido = 1;
            return;
        } else if (!strcmp(inesp, "TK_IMPORTA")) {
            codigo = "E206";
            snprintf(texto, sizeof(texto), "las importaciones deben ir antes de cualquier declaracion");
        } else if (es_eof) {
            int ll, lc;
            linea = prev_fin_linea; col = prev_fin_col; largo = 1;
            if (llave_abierta(&ll, &lc)) {
                codigo = "E203";
                linea = ll; col = lc;
                snprintf(texto, sizeof(texto), "'{' abierto en la linea %d nunca se cierra", ll);
            } else {
                snprintf(texto, sizeof(texto), "fin de archivo inesperado%s%s",
                         nesp ? ": se esperaba " : "", nesp ? lista : "");
            }
        } else if (nesp == 1 && !strcmp(esp[0], "TK_PUNTO_COMA")) {
            codigo = "E202"; linea = prev_fin_linea; col = prev_fin_col; largo = 1;
            snprintf(texto, sizeof(texto), "falta ';' al final de la sentencia");
        } else if (nesp == 1 && !strcmp(esp[0], "TK_DOS_PUNTOS")) {
            codigo = "E204";
            snprintf(texto, sizeof(texto), "falta ': tipo' en la declaracion");
        } else if (nesp == 1 && !strcmp(esp[0], "TK_FLECHA")) {
            codigo = "E209";
            snprintf(texto, sizeof(texto), "falta '-> tipo' en la declaracion de la funcion");
        } else if (nesp == 1 && !strcmp(esp[0], "TK_LLAVE_IZQ")) {
            codigo = "E207";
            snprintf(texto, sizeof(texto), "el cuerpo debe ir entre llaves");
        } else if (nesp > 0) {
            snprintf(texto, sizeof(texto), "se esperaba %s pero se encontro %s", lista, vista);
        } else {
            snprintf(texto, sizeof(texto), "token inesperado %s", vista);
        }

        if (!sint_suprimido) diag_error(codigo, linea, col, largo, "%s", texto);
    }
}
