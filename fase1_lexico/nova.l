%{
/* Lexer principal del lenguaje Nova. Aqui se reconocen tokens, cadenas,
 * comentarios y errores lexicos. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "ast.h"
#include "diag.h"
#include "nova.tab.h"

#define YY_DECL int yylex_crudo(void)

typedef struct { const char *palabra; int token; } Reservada;

Reservada tabla[] = {
    {"functio", TK_FUNCTIO}, {"varia", TK_VARIA}, {"constans", TK_CONSTANS},
    {"privatum", TK_PRIVATUM}, {"importa", TK_IMPORTA}, {"ut", TK_UT}, {"redde", TK_REDDE},
    {"si", TK_SI}, {"sin", TK_SIN}, {"aliter", TK_ALITER}, {"dum", TK_DUM},
    {"per", TK_PER}, {"rumpe", TK_RUMPE}, {"perge", TK_PERGE},
    {"integer", TK_TIPO_INTEGER}, {"veritas", TK_TIPO_VERITAS},
    {"textus", TK_TIPO_TEXTUS}, {"nihil", TK_TIPO_NIHIL},
    {"et", TK_ET}, {"aut", TK_AUT}, {"non", TK_NON},
    {"verum", TK_VERUM}, {"falsum", TK_FALSUM}
};
int cant_reservadas = sizeof(tabla) / sizeof(tabla[0]);

/* Palabras reservadas para versiones futuras: usarlas como identificador es E208. */
static const char *futuras[] = {
    "classis", "structura", "enumeratio", "novum", "dele", "elige", "casus",
    "fac", "tempta", "cape", "nullum", "hoc", "stativum", "publicum",
    "modulus", "ex", "litera", "relatio", "compara", "in", "realis", "naturalis"
};

static int es_futura(const char *lexema) {
    size_t i;
    for (i = 0; i < sizeof(futuras) / sizeof(futuras[0]); i++)
        if (strcmp(lexema, futuras[i]) == 0) return 1;
    return 0;
}

int buscar_reservada(char *lexema) {
    int i;
    for (i = 0; i < cant_reservadas; i++) {
        if (strcmp(lexema, tabla[i].palabra) == 0) return tabla[i].token;
    }

    return TK_IDENT;
}

/* Buffer de cadenas dinamico: crece segun haga falta, asi que una cadena
 * larga nunca se trunca en silencio. */
static char  *buf_cad = NULL;
static size_t cap_cad = 0, len_cad = 0;

static void cad_reiniciar(void) {
    len_cad = 0;
    if (buf_cad == NULL) {
        cap_cad = 256;
        buf_cad = malloc(cap_cad);
        if (buf_cad == NULL) { fprintf(stderr, "Sin memoria\n"); exit(3); }
    }
}

static void cad_poner(char c) {
    if (len_cad + 1 >= cap_cad) {
        char *nuevo = realloc(buf_cad, cap_cad * 2);
        if (nuevo == NULL) { fprintf(stderr, "Sin memoria\n"); exit(3); }
        buf_cad = nuevo;
        cap_cad *= 2;
    }
    buf_cad[len_cad++] = c;
}

static char *cad_terminar(void) {
    char *copia;
    buf_cad[len_cad] = '\0';
    copia = strdup(buf_cad);
    if (copia == NULL) { fprintf(stderr, "Sin memoria\n"); exit(3); }
    return copia;
}

int lin_act = 1, col_act = 1;

int cad_linea, cad_col;
int com_linea, com_col;

int prev_fin_linea = 1, prev_fin_col = 1;
static int ult_fin_linea = 1, ult_fin_col = 1;

/* Un token "malo" es el que se devolvio despues de reportar un error lexico
 * (cadena sin cerrar, numero mal formado). El parser lo consulta para no
 * sumar un E202 de rebote por culpa de ese mismo token. */
int tok_prev_malo = 0;
static int tok_malo = 0;
#define MALO() (tok_malo = 1)

#define MAX_LLAVES 1024
static int llaves_lin[MAX_LLAVES], llaves_col[MAX_LLAVES];
static int llaves_tope = 0;

/* Reinicia estado no generado por Flex antes de analizar el siguiente modulo. */
void nova_lexer_reset(void) {
    lin_act = col_act = 1;
    prev_fin_linea = prev_fin_col = 1;
    ult_fin_linea = ult_fin_col = 1;
    tok_prev_malo = tok_malo = 0;
    llaves_tope = 0;
    BEGIN(0);
}

static void llave_abrir(int lin, int col) {
    if (llaves_tope < MAX_LLAVES) {
        llaves_lin[llaves_tope] = lin;
        llaves_col[llaves_tope] = col;
    }
    llaves_tope++;
}
static void llave_cerrar(void) { if (llaves_tope > 0) llaves_tope--; }

int llave_abierta(int *lin, int *col) {
    if (llaves_tope <= 0 || llaves_tope > MAX_LLAVES) return 0;
    *lin = llaves_lin[llaves_tope - 1];
    *col = llaves_col[llaves_tope - 1];
    return 1;
}

static void avanzar(const char *t, int n) {
    int i;
    yylloc.first_line = lin_act;
    yylloc.first_column = col_act;
    for (i = 0; i < n; i++) {
        if (t[i] == '\n') { lin_act++; col_act = 1; }
        else if (((unsigned char)t[i] & 0xC0) != 0x80) col_act++;
    }
    yylloc.last_line = lin_act;
    yylloc.last_column = col_act;
}
#define YY_USER_ACTION avanzar(yytext, yyleng);

/* Cuenta caracteres visibles para mensajes de error, ignorando bytes de continuacion UTF-8. */
static int largo_utf8(const char *t) {
    int n = 0;
    for (; *t; t++) if (((unsigned char)*t & 0xC0) != 0x80) n++;
    return n;
}

%}

%option noyywrap
%option yylineno
%option noinput nounput

%x COMENTARIO
%x CADENA

%%

[ \t\r\n]+   { }

"#{"                 { BEGIN(COMENTARIO); com_linea = yylloc.first_line; com_col = yylloc.first_column; }
<COMENTARIO>"}#"     { BEGIN(INITIAL); }
<COMENTARIO>\n       { }
<COMENTARIO>.        { }
<COMENTARIO><<EOF>>  { diag_error("E103", com_linea, com_col, 2, "comentario de bloque sin cerrar; falta '}#'"); BEGIN(INITIAL); }

"#"[^{\n][^\n]*      { }
"#"                  { }

    /* Cadenas. Los escapes validos son \n, \t, \\, y \\". */
\"                   { BEGIN(CADENA); cad_reiniciar(); cad_linea = yylloc.first_line; cad_col = yylloc.first_column; }
<CADENA>\"           { BEGIN(INITIAL); yylval.texto = cad_terminar();
                       yylloc.first_line = cad_linea; yylloc.first_column = cad_col; return TK_CADENA; }
<CADENA>\\n          { cad_poner('\n'); }
<CADENA>\\t          { cad_poner('\t'); }
<CADENA>\\\\         { cad_poner('\\'); }
<CADENA>\\\"         { cad_poner('"'); }
<CADENA>\\.          { diag_error("E104", yylloc.first_line, yylloc.first_column, 2, "secuencia de escape desconocida '%s'", yytext); }
<CADENA>\n           { diag_error("E102", cad_linea, cad_col, 1, "cadena sin comilla de cierre antes del fin de linea"); MALO(); yylval.texto = cad_terminar();
                       yylloc.last_line = yylloc.first_line; yylloc.last_column = yylloc.first_column;
                       yylloc.first_line = cad_linea; yylloc.first_column = cad_col; BEGIN(INITIAL); return TK_CADENA; }
<CADENA><<EOF>>      { diag_error("E102", cad_linea, cad_col, 1, "cadena sin comilla de cierre antes del fin de linea"); MALO(); yylval.texto = cad_terminar();
                       yylloc.first_line = cad_linea; yylloc.first_column = cad_col; yylloc.last_line = lin_act; yylloc.last_column = col_act; BEGIN(INITIAL); return TK_CADENA; }
<CADENA>.            { cad_poner(yytext[0]); }

    /* Identificadores y palabras reservadas. */
[A-Za-z_][A-Za-z0-9_]*  {
    int tok = buscar_reservada(yytext);
    if (tok == TK_IDENT) {
        if (yyleng > 255)
            diag_error("E107", yylloc.first_line, yylloc.first_column, yyleng,
                       "identificador de mas de 255 caracteres");
        else if (es_futura(yytext))
            diag_error("E208", yylloc.first_line, yylloc.first_column, yyleng,
                       "'%s' esta reservada para versiones futuras", yytext);
        yylval.texto = strdup(yytext);
    }
    return tok;
}

    /* Enteros decimales y hexadecimales. */
0[xX][0-9A-Fa-f]+[G-Zg-z_][A-Za-z0-9_]* {
    diag_error("E105", yylloc.first_line, yylloc.first_column, yyleng, "literal hexadecimal seguido de identificador sin separador");
    MALO();
    yylval.entero = 0;
    return TK_ENTERO;
}
0[xX][0-9A-Fa-f]+ {
    unsigned long valor = strtoul(yytext, NULL, 16);
    if (valor > 0xFFFFFFFFUL) diag_error("E106", yylloc.first_line, yylloc.first_column, yyleng, "el literal no cabe en un integer de 32 bits");
    /* integer es de 32 bits con signo: 0xDEADBEEF vale -559038737, igual
     * que el mismo patron de bits escrito en decimal. */
    yylval.entero = (long)(int)valor;
    return TK_ENTERO;
}
0[xX]           { diag_error("E105", yylloc.first_line, yylloc.first_column, 2, "literal numerico mal formado: '0x'"); }
[0-9]+[A-Za-z_][A-Za-z0-9_]* {
    diag_error("E105", yylloc.first_line, yylloc.first_column, yyleng, "literal entero seguido de identificador sin separador");
    MALO();
    yylval.entero = 0;
    return TK_ENTERO;
}
[0-9]+          {
    unsigned long valor = strtoul(yytext, NULL, 10);
    if (valor > 2147483647UL) diag_error("E106", yylloc.first_line, yylloc.first_column, yyleng, "el literal no cabe en un integer de 32 bits");
    yylval.entero = (long)valor;
    return TK_ENTERO;
}

    /* Operadores y delimitadores del lenguaje. */
">>>"  { return TK_DESP_LOG; }
">>"   { return TK_DESP_DER; }
">="   { return TK_MAYOR_IGUAL; }
">"    { return TK_MAYOR; }
"<<"   { return TK_DESP_IZQ; }
"<="   { return TK_MENOR_IGUAL; }
"<"    { return TK_MENOR; }
"=="   { return TK_IGUAL; }
"!="   { return TK_DIFERENTE; }
"->"   { return TK_FLECHA; }
"+="   { return TK_ASIGNA_MAS; }
"-="   { return TK_ASIGNA_MENOS; }
"*="   { return TK_ASIGNA_POR; }
"/="   { return TK_ASIGNA_ENTRE; }
"%="   { return TK_ASIGNA_MODULO; }
"="    { return TK_ASIGNA; }
"+"    { return TK_MAS; }
"-"    { return TK_MENOS; }
"*"    { return TK_POR; }
"/"    { return TK_ENTRE; }
"%"    { return TK_MODULO; }
"("    { return TK_PAR_IZQ; }
")"    { return TK_PAR_DER; }
"{"    { llave_abrir(yylloc.first_line, yylloc.first_column); return TK_LLAVE_IZQ; }
"}"    { llave_cerrar(); return TK_LLAVE_DER; }
"["    { return TK_COR_IZQ; }
"]"    { return TK_COR_DER; }
";"    { return TK_PUNTO_COMA; }
","    { return TK_COMA; }
":"    { return TK_DOS_PUNTOS; }
"."    { return TK_PUNTO; }
"@"    { return TK_ARROBA; }
"&"    { return TK_AMPERSAND; }
"|"    { return TK_BARRA; }
"^"    { return TK_XOR; }
"~"    { return TK_NOT; }

    /* Cualquier otro caracter es invalido fuera de una cadena. */
[\x80-\xFF]+  { diag_error("E101", yylloc.first_line, yylloc.first_column, largo_utf8(yytext), "caracter no valido '%s' fuera de una cadena", yytext); }
.      { diag_error("E101", yylloc.first_line, yylloc.first_column, 1, "caracter no valido '%s' fuera de una cadena", yytext); }

<<EOF>> { yylloc.first_line = yylloc.last_line = lin_act;
          yylloc.first_column = yylloc.last_column = col_act;
          return 0; }

%%

int yylex(void) {
    int t;
    prev_fin_linea = ult_fin_linea;
    prev_fin_col = ult_fin_col;
    tok_prev_malo = tok_malo;
    tok_malo = 0;
    t = yylex_crudo();
    ult_fin_linea = yylloc.last_line;
    ult_fin_col = yylloc.last_column;
    return t;
}
