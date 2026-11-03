#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "diag.h"
#include "ide.h"
#include "ide_lex.h"
#include "nova.tab.h"

extern FILE *yyin;
extern char *yytext;
int yylex(void);
void yyrestart(FILE *input_file);
void nova_lexer_reset(void);

static void agregar(ListaTokens *l, const TokenIDE *t) {
    if (l->n >= l->cap) {
        int nueva = l->cap ? l->cap * 2 : 256;
        TokenIDE *v = realloc(l->v, (size_t)nueva * sizeof(TokenIDE));
        if (v == NULL) { fprintf(stderr, "novaide: sin memoria\n"); exit(3); }
        l->v = v;
        l->cap = nueva;
    }
    l->v[l->n++] = *t;
}

static char *dup_texto(const char *s) {
    char *c;
    if (s == NULL) s = "";
    c = malloc(strlen(s) + 1);
    if (c == NULL) { fprintf(stderr, "novaide: sin memoria\n"); exit(3); }
    strcpy(c, s);
    return c;
}

int ide_tokenizar_buffer(const char *fuente, size_t largo, ListaTokens *out) {
    FILE *flujo;
    int tok;

    out->v = NULL;
    out->n = 0;
    out->cap = 0;

    flujo = fmemopen((void *)fuente, largo, "r");
    if (flujo == NULL) return 0;

    yyin = flujo;
    yyrestart(flujo);
    nova_lexer_reset();

    while ((tok = yylex()) != 0) {
        TokenIDE t;
        t.tipo = tok;
        t.linea = yylloc.first_line;
        t.columna = yylloc.first_column;
        t.fin_linea = yylloc.last_line;
        t.fin_columna = yylloc.last_column;
        t.valor = 0;

        /*
         * El lexer entrega el lexema de identificadores y cadenas por yylval
         * con strdup(); al llamarlo directo (sin el parser) ese texto es
         * nuestro y hay que liberarlo. Para el resto sirve yytext.
         */
        if (tok == TK_IDENT || tok == TK_CADENA) {
            t.texto = dup_texto(yylval.texto);
            free(yylval.texto);
            yylval.texto = NULL;
        } else if (tok == TK_ENTERO) {
            char buf[32];
            t.valor = yylval.entero;
            snprintf(buf, sizeof(buf), "%ld", yylval.entero);
            t.texto = dup_texto(buf);
        } else {
            t.texto = dup_texto(yytext);
        }
        agregar(out, &t);

        /* Cota de seguridad: un archivo gigante no debe colgar el editor. */
        if (out->n > 400000) break;
    }

    fclose(flujo);
    return 1;
}

int ide_tokenizar_archivo(const char *ruta, ListaTokens *out) {
    size_t largo = 0;
    char *fuente = ide_leer_archivo(ruta, &largo);
    int ok;
    if (fuente == NULL) {
        out->v = NULL; out->n = 0; out->cap = 0;
        return 0;
    }
    ok = ide_tokenizar_buffer(fuente, largo, out);
    free(fuente);
    return ok;
}

void ide_tokens_liberar(ListaTokens *l) {
    int i;
    for (i = 0; i < l->n; i++) free(l->v[i].texto);
    free(l->v);
    l->v = NULL;
    l->n = l->cap = 0;
}

/*
 * Categoria de color de un token. La usa el editor para pintar el codigo.
 *
 * El coloreado tambien sale del lexer real: si se escribiera un tokenizador
 * en JavaScript para esto, el editor acabaria pintando como identificador
 * algo que el compilador trata como palabra reservada en cuanto el lenguaje
 * cambie. Aqui no puede pasar, porque es exactamente el mismo yylex().
 */
const char *ide_token_categoria(int tipo) {
    if (ide_token_es_reservada(tipo)) {
        switch (tipo) {
            case TK_TIPO_INTEGER: case TK_TIPO_VERITAS:
            case TK_TIPO_TEXTUS:  case TK_TIPO_NIHIL:
                return "tipo";
            case TK_VERUM: case TK_FALSUM:
                return "literal";
            default:
                return "reservada";
        }
    }
    switch (tipo) {
        case TK_IDENT:  return "nombre";
        case TK_ENTERO: return "numero";
        case TK_CADENA: return "cadena";
        case TK_PAR_IZQ: case TK_PAR_DER: case TK_LLAVE_IZQ: case TK_LLAVE_DER:
        case TK_COR_IZQ: case TK_COR_DER: case TK_PUNTO_COMA: case TK_COMA:
        case TK_DOS_PUNTOS: case TK_PUNTO:
            return "puntuacion";
        default:
            return "operador";
    }
}

int ide_tokens_json(const char *ruta, JsonW *j) {
    ListaTokens tk;
    int i;

    if (!ide_tokenizar_archivo(ruta, &tk)) {
        jw_obj_abrir(j);
        jw_cadena(j, "trabajo", "tokens");
        jw_cadena(j, "error", "no se pudo leer el archivo");
        jw_obj_cerrar(j);
        return 3;
    }

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "tokens");
    jw_cadena(j, "archivo", ruta);
    jw_entero(j, "total", tk.n);
    jw_clave_arr(j, "tokens");
    for (i = 0; i < tk.n; i++) {
        jw_obj_abrir(j);
        jw_cadena(j, "categoria", ide_token_categoria(tk.v[i].tipo));
        jw_entero(j, "linea", tk.v[i].linea);
        jw_entero(j, "columna", tk.v[i].columna);
        jw_entero(j, "fin_linea", tk.v[i].fin_linea);
        jw_entero(j, "fin_columna", tk.v[i].fin_columna);
        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
    jw_obj_cerrar(j);

    ide_tokens_liberar(&tk);
    return 0;
}

const char *ide_token_vista(int tipo) {
    switch (tipo) {
        case TK_FUNCTIO: return "functio";
        case TK_VARIA: return "varia";
        case TK_CONSTANS: return "constans";
        case TK_PRIVATUM: return "privatum";
        case TK_IMPORTA: return "importa";
        case TK_UT: return "ut";
        case TK_REDDE: return "redde";
        case TK_SI: return "si";
        case TK_SIN: return "sin";
        case TK_ALITER: return "aliter";
        case TK_DUM: return "dum";
        case TK_PER: return "per";
        case TK_RUMPE: return "rumpe";
        case TK_PERGE: return "perge";
        case TK_TIPO_INTEGER: return "integer";
        case TK_TIPO_VERITAS: return "veritas";
        case TK_TIPO_TEXTUS: return "textus";
        case TK_TIPO_NIHIL: return "nihil";
        case TK_ET: return "et";
        case TK_AUT: return "aut";
        case TK_NON: return "non";
        case TK_VERUM: return "verum";
        case TK_FALSUM: return "falsum";
        case TK_IDENT: return "un identificador";
        case TK_ENTERO: return "un entero";
        case TK_CADENA: return "una cadena";
        case TK_PAR_IZQ: return "(";
        case TK_PAR_DER: return ")";
        case TK_LLAVE_IZQ: return "{";
        case TK_LLAVE_DER: return "}";
        case TK_COR_IZQ: return "[";
        case TK_COR_DER: return "]";
        case TK_PUNTO_COMA: return ";";
        case TK_COMA: return ",";
        case TK_DOS_PUNTOS: return ":";
        case TK_PUNTO: return ".";
        case TK_FLECHA: return "->";
        case TK_ASIGNA: return "=";
        default: return "";
    }
}

int ide_token_es_reservada(int tipo) {
    switch (tipo) {
        case TK_FUNCTIO: case TK_VARIA: case TK_CONSTANS: case TK_PRIVATUM:
        case TK_IMPORTA: case TK_UT: case TK_REDDE: case TK_SI: case TK_SIN:
        case TK_ALITER: case TK_DUM: case TK_PER: case TK_RUMPE: case TK_PERGE:
        case TK_TIPO_INTEGER: case TK_TIPO_VERITAS: case TK_TIPO_TEXTUS:
        case TK_TIPO_NIHIL: case TK_ET: case TK_AUT: case TK_NON:
        case TK_VERUM: case TK_FALSUM:
            return 1;
        default:
            return 0;
    }
}

/*
 * Un token que puede ser el ultimo de una sentencia. La lista sale de la
 * gramatica: una sentencia de Nova termina en una expresion, y una expresion
 * termina en un valor, en un cierre de parentesis o de corchete.
 */
int ide_token_termina_sentencia(int tipo) {
    switch (tipo) {
        case TK_IDENT: case TK_ENTERO: case TK_CADENA:
        case TK_VERUM: case TK_FALSUM:
        case TK_PAR_DER: case TK_COR_DER:
        case TK_RUMPE: case TK_PERGE:
        case TK_TIPO_INTEGER: case TK_TIPO_VERITAS: case TK_TIPO_TEXTUS:
            return 1;
        default:
            return 0;
    }
}

/*
 * Un token que solo puede abrir una sentencia nueva. Si una linea termina en
 * algo que cierra sentencia y la siguiente empieza con uno de estos sin que
 * haya un ';' entre medio, falta el punto y coma.
 */
int ide_token_inicia_sentencia(int tipo) {
    switch (tipo) {
        case TK_VARIA: case TK_CONSTANS: case TK_REDDE: case TK_SI:
        case TK_DUM: case TK_PER: case TK_RUMPE: case TK_PERGE:
        case TK_FUNCTIO: case TK_IMPORTA: case TK_PRIVATUM:
            return 1;
        default:
            return 0;
    }
}
