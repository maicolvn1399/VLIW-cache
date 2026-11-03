/*
 * Deteccion de clones de codigo entre archivos.
 *
 * El analisis es por flujo de tokens, que es lo estandar en la literatura de
 * deteccion de clones (CCFinder, CP-Miner) y lo que corresponde aqui: ya
 * existe el lexer del lenguaje, los tokens eliminan por construccion el ruido
 * de espacios, saltos de linea, sangria y comentarios, y el metodo sigue
 * funcionando sobre archivos que todavia no compilan.
 *
 * La unidad de comparacion es la funcion, no el archivo completo ni una
 * ventana de lineas: es la unidad que el programador copia y pega. Aparte se
 * comparan los archivos enteros, para el caso de un archivo duplicado con otro
 * nombre.
 *
 * De cada unidad se derivan dos secuencias:
 *
 *   cruda:        clase de token + lexema exacto de identificadores y
 *                 literales.
 *   normalizada:  clase de token, con todo identificador y todo literal
 *                 reemplazado por un marcador unico de su categoria.
 *
 * Con esas dos secuencias salen los tres tipos:
 *
 *   Tipo I    Secuencias crudas iguales. El codigo es el mismo; solo cambian
 *             el formato, los comentarios y el archivo donde vive.
 *
 *   Tipo II   Secuencias normalizadas iguales. La estructura es identica y lo
 *             unico que cambia son los nombres de variables y los literales.
 *             Se comprueba ademas que el renombrado sea consistente, es decir
 *             que exista una biyeccion entre los identificadores de una y los
 *             de la otra: si 'a' se vuelve 'x' en un lugar y 'y' en otro, el
 *             renombrado no es sistematico y se reporta como tal.
 *
 *   Tipo III  Ni iguales ni renombradas, pero con una similitud alta sobre la
 *             secuencia normalizada. Es el caso de la copia a la que se le
 *             agregaron o quitaron sentencias o variables. La similitud se
 *             mide con la subsecuencia comun mas larga:
 *
 *                 similitud = 2 * |LCS(a, b)| / (|a| + |b|)
 *
 *             que vale 1 cuando las secuencias coinciden y baja conforme hay
 *             que insertar o borrar tokens para pasar de una a la otra.
 *
 * Las unidades por debajo de --min-tokens no se comparan: dos funciones de
 * tres lineas casi siempre coinciden sin que eso signifique nada.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "diag.h"
#include "ide.h"
#include "ide_lex.h"
#include "nova.tab.h"

#define MAX_UNIDADES 2048
#define MAX_PARES 4000
#define LCS_MAX_TOKENS 4000   /* cota del DP para no colgar el editor */

/*
 * Marcadores para la secuencia normalizada. Se eligen fuera del rango de
 * codigos que genera bison para que no choquen con ningun token real.
 */
#define NORM_IDENT   100001
#define NORM_ENTERO  100002
#define NORM_CADENA  100003

/*
 * Histograma de clases de token, para descartar pares sin compararlos.
 *
 * La subsecuencia comun mas larga nunca puede ser mayor que la interseccion de
 * los multiconjuntos de tokens de las dos unidades, asi que ese valor es una
 * cota superior de la similitud. Si la cota ya queda por debajo del umbral, el
 * par no puede ser un clon y el calculo caro se evita. Al ser una cota
 * superior el filtro no descarta ningun clon verdadero.
 */
#define HIST_CUBOS 97

typedef struct {
    int   archivo;            /* indice de la ruta de origen */
    char  nombre[128];        /* nombre de la funcion, o "<archivo completo>" */
    int   linea_inicio;
    int   linea_fin;
    int   es_archivo;         /* 1 si la unidad es el archivo entero */
    int  *crudo;              /* clase de token */
    int  *norm;               /* clase normalizada: todo nombre y literal igual */
    int  *param;              /* codificacion parametrizada (ver abajo) */
    char **lex;               /* lexema si el token es identificador, si no NULL */
    int   n;
    int   hist[HIST_CUBOS];
    unsigned long h_crudo;
    unsigned long h_norm;
} Unidad;

static Unidad unidades[MAX_UNIDADES];
static int n_unidades;

static void *reservar(size_t n) {
    void *p = malloc(n);
    if (p == NULL) { fprintf(stderr, "novaide: sin memoria\n"); exit(3); }
    return p;
}

static unsigned long fnv_inicio(void) { return 2166136261UL; }

static unsigned long fnv_entero(unsigned long h, long v) {
    int i;
    for (i = 0; i < 8; i++) {
        h ^= (unsigned long)((v >> (i * 8)) & 0xFF);
        h *= 16777619UL;
    }
    return h;
}

static unsigned long fnv_texto(unsigned long h, const char *s) {
    if (s == NULL) return h;
    for (; *s; s++) { h ^= (unsigned char)*s; h *= 16777619UL; }
    return h;
}

static int es_normalizable(int tipo) {
    return tipo == TK_IDENT || tipo == TK_ENTERO || tipo == TK_CADENA;
}

static int clase_normalizada(int tipo) {
    switch (tipo) {
        case TK_IDENT:  return NORM_IDENT;
        case TK_ENTERO: return NORM_ENTERO;
        case TK_CADENA: return NORM_CADENA;
        default: return tipo;
    }
}

/* Construye una unidad a partir del rango [desde, hasta) de la lista. */
static void unidad_nueva(const ListaTokens *tk, int desde, int hasta,
                         int archivo, const char *nombre, int es_archivo) {
    Unidad *u;
    int i, n = hasta - desde;

    if (n <= 0 || n_unidades >= MAX_UNIDADES) return;

    u = &unidades[n_unidades++];
    u->archivo = archivo;
    snprintf(u->nombre, sizeof(u->nombre), "%s", nombre);
    u->linea_inicio = tk->v[desde].linea;
    u->linea_fin = tk->v[hasta - 1].fin_linea;
    u->es_archivo = es_archivo;
    u->n = n;
    u->crudo = reservar((size_t)n * sizeof(int));
    u->norm  = reservar((size_t)n * sizeof(int));
    u->param = reservar((size_t)n * sizeof(int));
    u->lex   = reservar((size_t)n * sizeof(char *));
    u->h_crudo = fnv_inicio();
    u->h_norm  = fnv_inicio();
    memset(u->hist, 0, sizeof(u->hist));

    for (i = 0; i < n; i++) {
        const TokenIDE *t = &tk->v[desde + i];
        u->crudo[i] = t->tipo;
        u->norm[i] = clase_normalizada(t->tipo);
        u->lex[i] = es_normalizable(t->tipo) ? t->texto : NULL;

        u->h_crudo = fnv_entero(u->h_crudo, t->tipo);
        if (es_normalizable(t->tipo)) u->h_crudo = fnv_texto(u->h_crudo, t->texto);
        u->h_norm = fnv_entero(u->h_norm, u->norm[i]);
        u->hist[((unsigned)u->norm[i]) % HIST_CUBOS]++;
    }

    /*
     * Codificacion parametrizada (Baker).
     *
     * Borrar los nombres por completo, como hace 'norm', es lo correcto para
     * decidir el Tipo II, donde las secuencias tienen que ser identicas. Para
     * la similitud del Tipo III resulta demasiado grosero: en Nova casi toda
     * sentencia se reduce a la misma plantilla de clases de token, de modo que
     * dos funciones que no tienen nada que ver terminan pareciendose solo por
     * compartir el esqueleto del lenguaje.
     *
     * Lo que si distingue a una copia de una coincidencia estructural es el
     * PATRON DE REUSO de los nombres: cuando una variable se vuelve a usar y a
     * que distancia. Ese patron sobrevive al renombrado -llamarle 'acumulado'
     * en vez de 'suma' no cambia donde aparece- pero cambia por completo entre
     * dos funciones distintas. Por eso cada identificador se codifica como la
     * distancia hasta su aparicion anterior dentro de la unidad, y 0 si es la
     * primera vez que aparece.
     */
    for (i = 0; i < n; i++) {
        if (u->norm[i] != NORM_IDENT) { u->param[i] = u->norm[i]; continue; }
        {
            int k, distancia = 0;
            for (k = i - 1; k >= 0; k--) {
                if (u->norm[k] != NORM_IDENT) continue;
                if (u->lex[k] != NULL && u->lex[i] != NULL &&
                    strcmp(u->lex[k], u->lex[i]) == 0) {
                    distancia = i - k;
                    break;
                }
            }
            /* Se acota la distancia para que dos reusos lejanos cuenten como
             * el mismo caso y no como dos valores distintos por un token. */
            if (distancia > 32) distancia = 32;
            u->param[i] = 200000 + distancia;
        }
    }
}

/*
 * Parte un archivo en funciones. Se busca 'functio' seguido de un nombre, y la
 * unidad llega hasta la llave que cierra el cuerpo. Si el cuerpo no cierra
 * (codigo a medio escribir), la unidad llega hasta el siguiente 'functio' o
 * hasta el final.
 */
static void partir_en_funciones(const ListaTokens *tk, int archivo) {
    int i;

    for (i = 0; i < tk->n; i++) {
        int nombre_idx, k, hondo, inicio, fin;

        if (tk->v[i].tipo != TK_FUNCTIO) continue;
        if (i + 1 >= tk->n || tk->v[i + 1].tipo != TK_IDENT) continue;

        nombre_idx = i + 1;
        inicio = i;
        fin = tk->n;
        hondo = 0;

        for (k = i + 1; k < tk->n; k++) {
            if (tk->v[k].tipo == TK_LLAVE_IZQ) { hondo++; continue; }
            if (tk->v[k].tipo == TK_LLAVE_DER) {
                hondo--;
                if (hondo == 0) { fin = k + 1; break; }
                continue;
            }
            if (hondo == 0 && tk->v[k].tipo == TK_FUNCTIO) { fin = k; break; }
        }

        unidad_nueva(tk, inicio, fin, archivo, tk->v[nombre_idx].texto, 0);
        i = fin - 1;
    }
}

/* --------------------------------------------------------- comparaciones */

static int iguales_crudo(const Unidad *a, const Unidad *b) {
    int i;
    if (a->n != b->n || a->h_crudo != b->h_crudo) return 0;
    for (i = 0; i < a->n; i++) {
        if (a->crudo[i] != b->crudo[i]) return 0;
        if (a->lex[i] == NULL) {
            if (b->lex[i] != NULL) return 0;
        } else {
            if (b->lex[i] == NULL || strcmp(a->lex[i], b->lex[i]) != 0) return 0;
        }
    }
    return 1;
}

static int iguales_norm(const Unidad *a, const Unidad *b) {
    int i;
    if (a->n != b->n || a->h_norm != b->h_norm) return 0;
    for (i = 0; i < a->n; i++)
        if (a->norm[i] != b->norm[i]) return 0;
    return 1;
}

/*
 * Comprueba que el renombrado sea consistente: que cada identificador de 'a'
 * corresponda siempre al mismo de 'b' y viceversa. Es la condicion de
 * 'parameterized match' de Baker, y es lo que distingue una copia renombrada
 * de forma sistematica de dos funciones que solo comparten la forma.
 *
 * Las tablas son lineales porque una funcion tiene decenas de nombres
 * distintos, no miles.
 */
#define MAX_MAPEO 512

static int renombrado_consistente(const Unidad *a, const Unidad *b, int *distintos) {
    const char *de[MAX_MAPEO], *a_[MAX_MAPEO];
    int n_mapeo = 0;
    int i, k;

    *distintos = 0;

    for (i = 0; i < a->n; i++) {
        const char *x, *y;
        if (a->norm[i] != NORM_IDENT) continue;
        x = a->lex[i];
        y = b->lex[i];
        if (x == NULL || y == NULL) return 0;

        for (k = 0; k < n_mapeo; k++) {
            if (strcmp(de[k], x) == 0) {
                if (strcmp(a_[k], y) != 0) return 0;   /* 'x' va a dos destinos */
                break;
            }
            if (strcmp(a_[k], y) == 0) return 0;       /* dos origenes al mismo destino */
        }
        if (k == n_mapeo) {
            if (n_mapeo >= MAX_MAPEO) return 0;
            de[n_mapeo] = x;
            a_[n_mapeo] = y;
            n_mapeo++;
            if (strcmp(x, y) != 0) (*distintos)++;
        }
    }
    return 1;
}

/*
 * Cota superior barata de la similitud: la interseccion de los histogramas.
 * La subsecuencia comun no puede usar mas ejemplares de una clase de token que
 * los que tiene la unidad mas pobre en esa clase, asi que este valor acota por
 * arriba cualquier LCS posible. Sirve para no entrar al DP en pares que no
 * pueden llegar al umbral.
 */
static double cota_similitud(const Unidad *a, const Unidad *b) {
    int i, comun = 0;
    for (i = 0; i < HIST_CUBOS; i++)
        comun += a->hist[i] < b->hist[i] ? a->hist[i] : b->hist[i];
    if (a->n + b->n == 0) return 0.0;
    return (2.0 * comun) / (double)(a->n + b->n);
}

/*
 * Similitud por subsecuencia comun mas larga sobre la codificacion
 * parametrizada, y de paso la racha comun contigua mas larga.
 *
 * La LCS mide cuanto se conserva de una secuencia en la otra permitiendo
 * inserciones y borrados, que es exactamente la copia con sentencias
 * agregadas o quitadas del Tipo III. La racha contigua se calcula en el mismo
 * recorrido y sirve de segundo requisito: dos funciones distintas pueden
 * acumular una LCS alta a base de coincidencias sueltas, pero no comparten un
 * tramo largo de codigo seguido. Exigir las dos cosas separa la copia real de
 * la coincidencia estructural.
 *
 * El DP usa dos filas, asi que la memoria es lineal aunque el tiempo siga
 * siendo del orden del producto de los largos.
 */
static double similitud_lcs(const Unidad *a, const Unidad *b, int *racha_max) {
    int *prev, *act, *prev_r, *act_r;
    int i, k;
    int n = a->n, m = b->n;
    double r;

    *racha_max = 0;
    if (n == 0 || m == 0) return 0.0;
    if (n > LCS_MAX_TOKENS) n = LCS_MAX_TOKENS;
    if (m > LCS_MAX_TOKENS) m = LCS_MAX_TOKENS;

    prev   = calloc((size_t)m + 1, sizeof(int));
    act    = calloc((size_t)m + 1, sizeof(int));
    prev_r = calloc((size_t)m + 1, sizeof(int));
    act_r  = calloc((size_t)m + 1, sizeof(int));
    if (prev == NULL || act == NULL || prev_r == NULL || act_r == NULL) {
        free(prev); free(act); free(prev_r); free(act_r);
        return 0.0;
    }

    for (i = 1; i <= n; i++) {
        for (k = 1; k <= m; k++) {
            if (a->param[i - 1] == b->param[k - 1]) {
                act[k] = prev[k - 1] + 1;
                act_r[k] = prev_r[k - 1] + 1;
                if (act_r[k] > *racha_max) *racha_max = act_r[k];
            } else {
                act[k] = act[k - 1] > prev[k] ? act[k - 1] : prev[k];
                act_r[k] = 0;
            }
        }
        memcpy(prev, act, ((size_t)m + 1) * sizeof(int));
        memcpy(prev_r, act_r, ((size_t)m + 1) * sizeof(int));
    }

    r = (2.0 * prev[m]) / (double)(n + m);
    free(prev); free(act); free(prev_r); free(act_r);
    return r;
}

/* ------------------------------------------------------------------ salida */

typedef struct {
    int a, b;
    const char *tipo;
    const char *renombrado;
    double similitud;
    int racha;                /* tramo contiguo comun mas largo */
    int identificadores_cambiados;
} Par;

static Par pares[MAX_PARES];
static int n_pares;

static void liberar_unidades(void) {
    int i;
    for (i = 0; i < n_unidades; i++) {
        free(unidades[i].crudo);
        free(unidades[i].norm);
        free(unidades[i].param);
        free(unidades[i].lex);
    }
    n_unidades = 0;
}

int ide_clones(const char **rutas, int n_rutas, int min_tokens,
               double umbral_tipo3, JsonW *j) {
    ListaTokens tk[IDE_MAX_ARCHIVOS];
    int tk_ok[IDE_MAX_ARCHIVOS];
    int f, a, b, i;
    int n_tipo1 = 0, n_tipo2 = 0, n_tipo3 = 0;

    n_unidades = 0;
    n_pares = 0;

    if (min_tokens < 1) min_tokens = 1;
    if (umbral_tipo3 <= 0.0 || umbral_tipo3 > 1.0) umbral_tipo3 = 0.80;

    /* Los errores lexicos de los archivos no son asunto de este trabajo. */
    diag_limpiar_captura();
    diag_capturar(1);

    for (f = 0; f < n_rutas; f++) {
        diag_iniciar(rutas[f]);
        tk_ok[f] = ide_tokenizar_archivo(rutas[f], &tk[f]);
        if (!tk_ok[f]) continue;
        partir_en_funciones(&tk[f], f);
        /* El archivo completo como una unidad mas: detecta el duplicado que
         * solo cambia de nombre de archivo. */
        if (tk[f].n > 0)
            unidad_nueva(&tk[f], 0, tk[f].n, f, "<archivo completo>", 1);
    }
    diag_capturar(0);

    for (a = 0; a < n_unidades; a++) {
        for (b = a + 1; b < n_unidades; b++) {
            Unidad *ua = &unidades[a], *ub = &unidades[b];
            int distintos = 0, racha = 0;
            double sim;

            /* Una unidad no se compara consigo misma ni con el archivo que la
             * contiene: eso siempre daria un clon trivial. */
            if (ua->es_archivo != ub->es_archivo) continue;
            if (ua->archivo == ub->archivo && ua->es_archivo) continue;
            if (ua->n < min_tokens || ub->n < min_tokens) continue;
            if (n_pares >= MAX_PARES) break;

            if (iguales_crudo(ua, ub)) {
                pares[n_pares].a = a; pares[n_pares].b = b;
                pares[n_pares].tipo = "I";
                pares[n_pares].renombrado = "ninguno";
                pares[n_pares].similitud = 1.0;
                pares[n_pares].racha = ua->n;
                pares[n_pares].identificadores_cambiados = 0;
                n_pares++; n_tipo1++;
                continue;
            }

            if (iguales_norm(ua, ub)) {
                int consistente = renombrado_consistente(ua, ub, &distintos);
                pares[n_pares].a = a; pares[n_pares].b = b;
                pares[n_pares].tipo = "II";
                pares[n_pares].renombrado = consistente ? "consistente" : "inconsistente";
                pares[n_pares].similitud = 1.0;
                pares[n_pares].racha = ua->n;
                pares[n_pares].identificadores_cambiados = distintos;
                n_pares++; n_tipo2++;
                continue;
            }

            /* Filtro barato antes del DP: si la cota ya no alcanza, no hay
             * clon posible y no hace falta calcular nada mas. */
            if (cota_similitud(ua, ub) < umbral_tipo3) continue;

            sim = similitud_lcs(ua, ub, &racha);
            {
                /*
                 * Ademas de la similitud se exige un tramo contiguo
                 * significativo: al menos 10 tokens y una cuarta parte de la
                 * unidad mas corta. Sin esa condicion, dos funciones que solo
                 * comparten el esqueleto del lenguaje acumulan una LCS alta a
                 * base de coincidencias de un token y se reportarian como
                 * clones.
                 */
                int menor = ua->n < ub->n ? ua->n : ub->n;
                int minimo = menor / 4;
                if (minimo < 10) minimo = 10;
                if (sim < umbral_tipo3 || racha < minimo) continue;
            }

            pares[n_pares].a = a; pares[n_pares].b = b;
            pares[n_pares].tipo = "III";
            pares[n_pares].renombrado = "parcial";
            pares[n_pares].similitud = sim;
            pares[n_pares].racha = racha;
            pares[n_pares].identificadores_cambiados = 0;
            n_pares++; n_tipo3++;
        }
    }

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "clones");
    jw_clave_arr(j, "archivos");
    for (f = 0; f < n_rutas; f++) jw_item_cadena(j, rutas[f]);
    jw_arr_cerrar(j);

    jw_clave_obj(j, "parametros");
    jw_entero(j, "min_tokens", min_tokens);
    jw_real(j, "umbral_tipo3", umbral_tipo3);
    jw_cadena(j, "similitud_tipo3", "LCS sobre codificacion parametrizada (Baker), mas racha contigua minima");
    jw_cadena(j, "granularidad", "funcion y archivo completo");
    jw_obj_cerrar(j);

    jw_clave_obj(j, "resumen");
    jw_entero(j, "unidades", n_unidades);
    jw_entero(j, "tipo_I", n_tipo1);
    jw_entero(j, "tipo_II", n_tipo2);
    jw_entero(j, "tipo_III", n_tipo3);
    jw_entero(j, "total", n_pares);
    jw_obj_cerrar(j);

    jw_clave_arr(j, "clones");
    for (i = 0; i < n_pares; i++) {
        const Unidad *ua = &unidades[pares[i].a];
        const Unidad *ub = &unidades[pares[i].b];

        jw_obj_abrir(j);
        jw_cadena(j, "tipo", pares[i].tipo);
        jw_real(j, "similitud", pares[i].similitud);
        jw_entero(j, "racha_contigua", pares[i].racha);
        jw_cadena(j, "renombrado", pares[i].renombrado);
        jw_entero(j, "identificadores_cambiados", pares[i].identificadores_cambiados);
        jw_bool(j, "entre_archivos", ua->archivo != ub->archivo);
        jw_bool(j, "archivo_completo", ua->es_archivo);

        jw_clave_obj(j, "a");
        jw_cadena(j, "archivo", rutas[ua->archivo]);
        jw_cadena(j, "unidad", ua->nombre);
        jw_entero(j, "linea_inicio", ua->linea_inicio);
        jw_entero(j, "linea_fin", ua->linea_fin);
        jw_entero(j, "tokens", ua->n);
        jw_obj_cerrar(j);

        jw_clave_obj(j, "b");
        jw_cadena(j, "archivo", rutas[ub->archivo]);
        jw_cadena(j, "unidad", ub->nombre);
        jw_entero(j, "linea_inicio", ub->linea_inicio);
        jw_entero(j, "linea_fin", ub->linea_fin);
        jw_entero(j, "tokens", ub->n);
        jw_obj_cerrar(j);

        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
    jw_obj_cerrar(j);

    liberar_unidades();
    for (f = 0; f < n_rutas; f++) if (tk_ok[f]) ide_tokens_liberar(&tk[f]);
    return 0;
}
