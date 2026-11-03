/*
 * Correccion automatica de errores.
 *
 * Hay dos fuentes de arreglos y se usan las dos, porque cada una sabe cosas
 * que la otra no:
 *
 *   1. El propio parser. nova.y ya clasifica sus errores: cuando lo unico que
 *      esperaba era un ';' emite E202 justo en el final de la sentencia
 *      anterior, y cuando un '{' no se cierra emite E203 en la llave culpable.
 *      Un arreglo derivado de ahi no es una adivinanza: es el token exacto que
 *      el analizador necesitaba en ese punto.
 *
 *   2. Un balanceo de delimitadores sobre el flujo de tokens. El parser se
 *      detiene en el primer error de cada region, asi que con varios
 *      parentesis o corchetes sin cerrar solo reporta el primero. El balanceo
 *      los ve todos a la vez y ademas distingue el caso contrario, un cierre
 *      que sobra, que no tiene codigo de error propio.
 *
 * Cada arreglo se entrega como una lista de ediciones con posicion exacta. La
 * interfaz aplica uno, vuelve a analizar y repite: corregir un error suele
 * revelar o eliminar otros, asi que aplicarlos todos de una sola vez sobre un
 * analisis viejo es menos confiable.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "diag.h"
#include "ast.h"
#include "enlace.h"
#include "ide.h"
#include "ide_lex.h"
#include "nova.tab.h"
#include "semantic.h"
#include "symtab.h"

#define MAX_ARREGLOS 200
#define MAX_PILA 256

typedef struct {
    char codigo[16];
    char titulo[96];
    char descripcion[320];
    const char *confianza;   /* "alta" o "media" */
    int  linea, columna;
    int  borrar;             /* caracteres a borrar en esa posicion */
    char insertar[64];
} Arreglo;

static Arreglo arreglos[MAX_ARREGLOS];
static int n_arreglos;

static void agregar_arreglo(const char *codigo, const char *titulo,
                            const char *confianza, int linea, int columna,
                            int borrar, const char *insertar,
                            const char *descripcion) {
    Arreglo *a;
    int i;

    if (n_arreglos >= MAX_ARREGLOS) return;

    /* Dos fases pueden proponer el mismo arreglo; se deja uno solo. */
    for (i = 0; i < n_arreglos; i++) {
        if (arreglos[i].linea == linea && arreglos[i].columna == columna &&
            strcmp(arreglos[i].insertar, insertar != NULL ? insertar : "") == 0 &&
            arreglos[i].borrar == borrar)
            return;
    }

    a = &arreglos[n_arreglos++];
    snprintf(a->codigo, sizeof(a->codigo), "%s", codigo);
    snprintf(a->titulo, sizeof(a->titulo), "%s", titulo);
    snprintf(a->descripcion, sizeof(a->descripcion), "%s", descripcion);
    a->confianza = confianza;
    a->linea = linea;
    a->columna = columna;
    a->borrar = borrar;
    snprintf(a->insertar, sizeof(a->insertar), "%s", insertar != NULL ? insertar : "");
}

/* ------------------------------------------------ arreglos desde el parser */

/*
 * Traduce un diagnostico a un arreglo cuando el codigo identifica sin
 * ambiguedad el simbolo que falta. Los codigos que no describen una omision
 * concreta (un tipo incompatible, un nombre no declarado) no producen arreglo:
 * el editor los subraya, pero corregirlos es decision del programador.
 */
/*
 * Se levanta cuando el parser identifico por si mismo el delimitador que
 * falta. En ese caso el balanceo de tokens no aporta: lo que ve son los
 * cierres que quedaron descuadrados aguas abajo del error real, y proponer
 * arreglos para esos desplaza el problema en vez de resolverlo. El parser
 * sabe mas, asi que se le cede el turno; una vez aplicado su arreglo el
 * editor vuelve a analizar y, si todavia falta algun delimitador, ahi si
 * entra el balanceo.
 */
static int parser_resolvio_delimitador;

/*
 * Extrae el simbolo de un mensaje "se esperaba 'X' pero se encontro ...".
 * Solo sirve si se esperaba exactamente uno: con varias alternativas el
 * parser no esta diciendo que falta un simbolo concreto.
 */
static int simbolo_esperado(const char *mensaje, char *out, size_t cap) {
    const char *ini = strstr(mensaje, "se esperaba '");
    const char *fin;
    size_t n;

    if (ini == NULL) return 0;
    if (strstr(mensaje, " o ") != NULL) return 0;

    ini += strlen("se esperaba '");
    fin = strchr(ini, '\'');
    if (fin == NULL) return 0;

    n = (size_t)(fin - ini);
    if (n == 0 || n >= cap) return 0;
    memcpy(out, ini, n);
    out[n] = '\0';
    return 1;
}

static int es_delimitador(const char *s) {
    static const char *const lista[] = {")", "]", "}", "{", "(", "[",
                                        ";", ",", ":", "->", NULL};
    int i;
    for (i = 0; lista[i] != NULL; i++)
        if (strcmp(s, lista[i]) == 0) return 1;
    return 0;
}

static void arreglo_desde_diagnostico(const DiagRegistro *r) {
    if (strcmp(r->codigo, "E201") == 0) {
        char simbolo[16], titulo[96], detalle[DIAG_MAX_MENSAJE + 96];
        if (simbolo_esperado(r->mensaje, simbolo, sizeof(simbolo)) &&
            es_delimitador(simbolo)) {
            snprintf(titulo, sizeof(titulo), "Insertar '%s'", simbolo);
            snprintf(detalle, sizeof(detalle),
                     "En esta posicion el analizador solo admitia '%s'. %s",
                     simbolo, r->mensaje);
            agregar_arreglo("E201", titulo, "alta", r->linea, r->columna,
                            0, simbolo, detalle);
            if (simbolo[0] == ')' || simbolo[0] == ']' || simbolo[0] == '}')
                parser_resolvio_delimitador = 1;
        }
        return;
    }
    if (strcmp(r->codigo, "E202") == 0) {
        agregar_arreglo("E202", "Insertar ';'", "alta", r->linea, r->columna,
                        0, ";",
                        "El parser esperaba el punto y coma que cierra la sentencia "
                        "justo en esta posicion.");
        return;
    }
    if (strcmp(r->codigo, "E203") == 0 && strstr(r->mensaje, "nunca se cierra") != NULL) {
        /* El balanceo de delimitadores propone la posicion del '}'; aqui solo
         * se deja constancia de donde empezo el bloque. */
        return;
    }
    if (strcmp(r->codigo, "E209") == 0) {
        agregar_arreglo("E209", "Insertar '-> integer'", "media", r->linea, r->columna,
                        0, " -> integer",
                        "Falta el tipo de retorno. Se propone 'integer'; cambielo si la "
                        "funcion retorna otra cosa, o 'nihil' si no retorna nada.");
        return;
    }
    if (strcmp(r->codigo, "E204") == 0) {
        agregar_arreglo("E204", "Insertar ': integer'", "media", r->linea, r->columna,
                        0, " : integer",
                        "Falta el tipo de la declaracion. Se propone 'integer'; cambielo "
                        "si corresponde otro tipo.");
        return;
    }
    if (strcmp(r->codigo, "E103") == 0) {
        agregar_arreglo("E103", "Cerrar el comentario de bloque", "alta",
                        r->linea, r->columna, 0, "",
                        "El comentario abierto aqui con '#{' nunca se cierra. Agregue "
                        "'}#' donde deba terminar.");
        return;
    }
    if (strcmp(r->codigo, "E102") == 0) {
        agregar_arreglo("E102", "Cerrar la cadena", "alta", r->linea, r->columna,
                        0, "",
                        "La cadena que abre aqui no tiene su comilla de cierre antes "
                        "del fin de linea.");
        return;
    }
}

/* ---------------------------------------- arreglos desde el balanceo */

typedef struct {
    int tipo;      /* token de apertura */
    int linea;
    int columna;
} Abierto;

static int cierre_de(int apertura) {
    switch (apertura) {
        case TK_PAR_IZQ:   return TK_PAR_DER;
        case TK_COR_IZQ:   return TK_COR_DER;
        case TK_LLAVE_IZQ: return TK_LLAVE_DER;
        default: return 0;
    }
}

static const char *texto_cierre(int apertura) {
    switch (apertura) {
        case TK_PAR_IZQ:   return ")";
        case TK_COR_IZQ:   return "]";
        case TK_LLAVE_IZQ: return "}";
        default: return "";
    }
}

static const char *texto_apertura(int apertura) {
    switch (apertura) {
        case TK_PAR_IZQ:   return "(";
        case TK_COR_IZQ:   return "[";
        case TK_LLAVE_IZQ: return "{";
        default: return "";
    }
}

static int es_apertura(int t) {
    return t == TK_PAR_IZQ || t == TK_COR_IZQ || t == TK_LLAVE_IZQ;
}

static int es_cierre(int t) {
    return t == TK_PAR_DER || t == TK_COR_DER || t == TK_LLAVE_DER;
}

static const char *texto_de_cierre(int t) {
    switch (t) {
        case TK_PAR_DER:   return ")";
        case TK_COR_DER:   return "]";
        case TK_LLAVE_DER: return "}";
        default: return "";
    }
}

/*
 * Sangria de cada linea, medida como la columna de su primer token menos uno.
 * Una linea sin tokens (vacia o solo comentario) vale -1 y no participa en las
 * comparaciones.
 *
 * La sangria es la unica pista que queda sobre la intencion del programador
 * cuando falta una llave: el texto ya no dice donde terminaba el bloque, pero
 * la forma en que esta escrito si.
 */
#define MAX_LINEAS 20000
static int sangria[MAX_LINEAS];
static int ultima_linea;

static void medir_sangria(const ListaTokens *tk) {
    int i;
    for (i = 0; i < MAX_LINEAS; i++) sangria[i] = -1;
    ultima_linea = 0;
    for (i = 0; i < tk->n; i++) {
        int l = tk->v[i].linea;
        if (l < 1 || l >= MAX_LINEAS) continue;
        if (sangria[l] < 0) sangria[l] = tk->v[i].columna - 1;
        if (tk->v[i].fin_linea > ultima_linea) ultima_linea = tk->v[i].fin_linea;
    }
}

static int sangria_de(int linea) {
    if (linea < 1 || linea >= MAX_LINEAS) return -1;
    return sangria[linea];
}

/*
 * Donde conviene insertar la llave que cierra el bloque abierto en
 * 'inicio_linea'.
 *
 * Insertarla al final del archivo siempre produce un programa balanceado, pero
 * casi nunca es lo que el programador queria: si olvido cerrar un 'si', el
 * resto de la funcion termina dentro de la condicion y el programa compila
 * haciendo otra cosa. La regla que se aplica, en orden:
 *
 *   1. La primera linea posterior cuya sangria sea menor o igual que la de la
 *      linea donde abrio el bloque. Es el corte que el programador dibujo con
 *      la sangria: ahi dejo de escribir dentro del bloque.
 *   2. Si no hay ninguna, la primera construccion de nivel superior
 *      ('functio', 'constans', 'importa') que empiece en la columna 1.
 *   3. Si tampoco, el final del archivo, que es el caso del ultimo bloque.
 *
 * El '}' se inserta con la misma sangria del 'si' o del 'functio' que cierra,
 * para que el texto resultante quede alineado.
 */
static void punto_de_cierre(const ListaTokens *tk, int inicio_linea,
                            int *linea, int *columna, int *sangria_cierre) {
    int l, i;
    int ind = sangria_de(inicio_linea);

    *sangria_cierre = ind < 0 ? 0 : ind;

    if (ind >= 0) {
        for (l = inicio_linea + 1; l <= ultima_linea; l++) {
            int s = sangria_de(l);
            if (s < 0) continue;              /* linea en blanco */
            if (s <= ind) { *linea = l; *columna = 1; return; }
        }
    }

    for (i = 0; i < tk->n; i++) {
        if (tk->v[i].columna != 1 || tk->v[i].linea <= inicio_linea) continue;
        if (tk->v[i].tipo != TK_FUNCTIO && tk->v[i].tipo != TK_CONSTANS &&
            tk->v[i].tipo != TK_PRIVATUM && tk->v[i].tipo != TK_IMPORTA)
            continue;
        *linea = tk->v[i].linea;
        *columna = 1;
        return;
    }

    *linea = (ultima_linea > 0 ? ultima_linea : inicio_linea) + 1;
    *columna = 1;
}

/* Propone el '}' que le falta al bloque abierto en 'inicio'. */
static void proponer_llave(const ListaTokens *tk, const Abierto *inicio) {
    int linea = 0, columna = 1, ind = 0, k;
    char titulo[96], detalle[320], texto[72];

    punto_de_cierre(tk, inicio->linea, &linea, &columna, &ind);

    if (ind > 60) ind = 60;
    for (k = 0; k < ind; k++) texto[k] = ' ';
    texto[ind] = '}';
    texto[ind + 1] = '\n';
    texto[ind + 2] = '\0';

    snprintf(titulo, sizeof(titulo), "Insertar '}' que falta");
    snprintf(detalle, sizeof(detalle),
             "El bloque que abre en la linea %d, columna %d nunca se cierra. "
             "Por la sangria del codigo, el cierre corresponde antes de la "
             "linea %d.", inicio->linea, inicio->columna, linea);
    agregar_arreglo("E203", titulo, "media", linea, columna, 0, texto, detalle);
}

static void balancear(const ListaTokens *tk) {
    Abierto pila[MAX_PILA];
    int tope = 0;
    int i;
    char titulo[96], detalle[320];

    medir_sangria(tk);

    for (i = 0; i < tk->n; i++) {
        int t = tk->v[i].tipo;

        if (es_apertura(t)) {
            if (tope < MAX_PILA) {
                pila[tope].tipo = t;
                pila[tope].linea = tk->v[i].linea;
                pila[tope].columna = tk->v[i].columna;
            }
            tope++;
            continue;
        }

        if (!es_cierre(t)) continue;

        /*
         * Cierre a destiempo. Si este '}' esta escrito con menos sangria que
         * la linea donde abrio el bloque mas interno, el programador lo puso
         * para cerrar un bloque de afuera: el de adentro quedo sin cerrar.
         * El conteo de llaves por si solo no distingue este caso (sigue
         * cuadrando una apertura con un cierre), y es justo el error mas comun
         * al olvidar una llave dentro de una funcion.
         */
        if (t == TK_LLAVE_DER && tope > 0 && tope <= MAX_PILA) {
            int s_cierre = sangria_de(tk->v[i].linea);
            while (tope > 0 && s_cierre >= 0 &&
                   pila[tope - 1].tipo == TK_LLAVE_IZQ &&
                   sangria_de(pila[tope - 1].linea) > s_cierre) {
                proponer_llave(tk, &pila[tope - 1]);
                tope--;
            }
        }

        if (tope == 0) {
            /* Un cierre sin apertura: sobra. Borrarlo es el unico arreglo
             * que no inventa estructura. */
            snprintf(titulo, sizeof(titulo), "Borrar '%s' sobrante", texto_de_cierre(t));
            snprintf(detalle, sizeof(detalle),
                     "Este '%s' cierra algo que nunca se abrio.", texto_de_cierre(t));
            agregar_arreglo("E201", titulo, "media", tk->v[i].linea, tk->v[i].columna,
                            1, "", detalle);
            continue;
        }

        tope--;
        if (tope < MAX_PILA && cierre_de(pila[tope].tipo) != t) {
            /* Cierre que no corresponde a la apertura mas reciente. Se propone
             * el que si corresponde, en vez de borrar: el programador
             * normalmente se equivoco de simbolo, no de intencion. */
            snprintf(titulo, sizeof(titulo), "Cambiar '%s' por '%s'",
                     texto_de_cierre(t), texto_cierre(pila[tope].tipo));
            snprintf(detalle, sizeof(detalle),
                     "El '%s' abierto en la linea %d se cierra con '%s', no con '%s'.",
                     texto_apertura(pila[tope].tipo), pila[tope].linea,
                     texto_cierre(pila[tope].tipo), texto_de_cierre(t));
            agregar_arreglo("E201", titulo, "media", tk->v[i].linea, tk->v[i].columna,
                            1, texto_cierre(pila[tope].tipo), detalle);
        }
    }

    /* Lo que quedo en la pila nunca se cerro. Se recorre de adentro hacia
     * afuera, que es el orden en que hay que insertar los cierres. */
    while (tope > 0) {
        tope--;
        if (tope >= MAX_PILA) continue;

        if (pila[tope].tipo == TK_LLAVE_IZQ) {
            proponer_llave(tk, &pila[tope]);
        } else {
            /* Un parentesis o corchete no cruza lineas en la practica: se
             * cierra al final de su propia linea. */
            int j, fin_linea = pila[tope].linea, fin_col = pila[tope].columna + 1;
            for (j = 0; j < tk->n; j++) {
                if (tk->v[j].linea == pila[tope].linea &&
                    tk->v[j].fin_columna > fin_col) {
                    fin_col = tk->v[j].fin_columna;
                    fin_linea = tk->v[j].fin_linea;
                }
            }
            snprintf(titulo, sizeof(titulo), "Insertar '%s' que falta",
                     texto_cierre(pila[tope].tipo));
            snprintf(detalle, sizeof(detalle),
                     "El '%s' de la linea %d, columna %d nunca se cierra.",
                     texto_apertura(pila[tope].tipo), pila[tope].linea,
                     pila[tope].columna);
            agregar_arreglo("E201", titulo, "media", fin_linea, fin_col, 0,
                            texto_cierre(pila[tope].tipo), detalle);
        }
    }
}

/*
 * Punto y coma faltante detectado sobre los tokens.
 *
 * El parser ya reporta el primero de cada region, pero se detiene ahi. Este
 * recorrido encuentra el resto: una sentencia que termina y otra que empieza
 * en la linea siguiente sin un ';' en medio.
 */
static void puntos_y_coma(const ListaTokens *tk) {
    int i;
    for (i = 0; i + 1 < tk->n; i++) {
        const TokenIDE *a = &tk->v[i];
        const TokenIDE *b = &tk->v[i + 1];
        char detalle[320];

        if (!ide_token_termina_sentencia(a->tipo)) continue;
        if (b->linea == a->fin_linea) continue;          /* misma linea: sigue la expresion */
        if (!ide_token_inicia_sentencia(b->tipo) && b->tipo != TK_IDENT) continue;

        /*
         * Un identificador en la linea siguiente solo delata un ';' faltante
         * si de verdad arranca una sentencia, es decir si despues viene una
         * asignacion o una llamada. Sin esa comprobacion, una expresion
         * partida en dos lineas daria un falso positivo.
         */
        if (b->tipo == TK_IDENT) {
            int sig = (i + 2 < tk->n) ? tk->v[i + 2].tipo : 0;
            if (sig != TK_ASIGNA && sig != TK_PAR_IZQ && sig != TK_COR_IZQ &&
                sig != TK_ASIGNA_MAS && sig != TK_ASIGNA_MENOS &&
                sig != TK_ASIGNA_POR && sig != TK_ASIGNA_ENTRE &&
                sig != TK_ASIGNA_MODULO)
                continue;
        }

        snprintf(detalle, sizeof(detalle),
                 "La sentencia que termina en la linea %d no cierra con ';', y en la "
                 "linea %d empieza otra.", a->fin_linea, b->linea);
        agregar_arreglo("E202", "Insertar ';'", "alta", a->fin_linea, a->fin_columna,
                        0, ";", detalle);
    }
}

/* ------------------------------------------------------------------ salida */

int ide_arreglar(const char *ruta, JsonW *j) {
    ListaTokens tk;
    Nodo *ast = NULL;
    int i, n;

    n_arreglos = 0;
    parser_resolvio_delimitador = 0;

    /*
     * Primero el analisis real, para quedarse con los diagnosticos que el
     * parser clasifico. La captura evita que salgan por stderr y, sobre todo,
     * que el proceso aborte al llegar al maximo de errores.
     */
    diag_limpiar_captura();
    diag_capturar(1);
    diag_iniciar(ruta);
    parse_source(ruta, &ast);

    n = diag_capturados();
    for (i = 0; i < n; i++) {
        const DiagRegistro *r = diag_capturado(i);
        if (r != NULL && strcmp(r->severidad, "error") == 0)
            arreglo_desde_diagnostico(r);
    }

    if (ast != NULL) { liberar_ast(ast); raiz_ast = NULL; }
    release_modules();

    /* Luego el recorrido sobre tokens, que ve el archivo completo. */
    if (ide_tokenizar_archivo(ruta, &tk)) {
        if (!parser_resolvio_delimitador) balancear(&tk);
        puntos_y_coma(&tk);
        ide_tokens_liberar(&tk);
    }

    diag_capturar(0);

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "arreglar");
    jw_cadena(j, "archivo", ruta);
    jw_entero(j, "total", n_arreglos);
    jw_clave_arr(j, "correcciones");
    for (i = 0; i < n_arreglos; i++) {
        const Arreglo *a = &arreglos[i];
        jw_obj_abrir(j);
        jw_cadena(j, "codigo", a->codigo);
        jw_cadena(j, "titulo", a->titulo);
        jw_cadena(j, "descripcion", a->descripcion);
        jw_cadena(j, "confianza", a->confianza);
        jw_cadena(j, "fase", ide_catalogo_fase(a->codigo));
        jw_clave_arr(j, "ediciones");
        jw_obj_abrir(j);
        jw_entero(j, "linea", a->linea);
        jw_entero(j, "columna", a->columna);
        jw_entero(j, "borrar", a->borrar);
        jw_cadena(j, "insertar", a->insertar);
        jw_obj_cerrar(j);
        jw_arr_cerrar(j);
        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
    jw_obj_cerrar(j);
    return 0;
}
