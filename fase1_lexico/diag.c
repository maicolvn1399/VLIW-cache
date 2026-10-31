#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "diag.h"

#define MAX_ERRORES_DEFECTO 25

static const char *archivo_fuente = "";
static int total_errores = 0;
static int total_advertencias = 0;
static int max_errores = MAX_ERRORES_DEFECTO;

/* E1xx..E4xx corresponden a errores lexicos, sintacticos, semanticos y de enlace. */
static int por_fase[5] = {0, 0, 0, 0, 0};

/*
 * Advertencias: un bit por codigo W0xx, todas encendidas al arrancar.
 * El bit 0 es W001, el bit 1 es W002, y asi. 32 bits alcanzan de sobra para
 * las nueve que define el documento y deja espacio para las que se agreguen.
 */
#define MAX_WARN 32
static unsigned warn_activas = 0xFFFFFFFFu;
static int warn_es_error = 0;

/* Devuelve el indice de bit de un codigo "W003", o -1 si no tiene esa forma. */
static int indice_warn(const char *codigo) {
    int n;
    if (codigo == NULL || (codigo[0] != 'W' && codigo[0] != 'w')) return -1;
    n = atoi(codigo + 1);
    if (n < 1 || n > MAX_WARN) return -1;
    return n - 1;
}

void diag_warn_todas(void) {
    warn_activas = 0xFFFFFFFFu;
}

void diag_warn_ninguna(void) {
    warn_activas = 0u;
}

int diag_warn_desactivar(const char *codigo) {
    int i = indice_warn(codigo);
    if (i < 0) return 0;
    warn_activas &= ~(1u << i);
    return 1;
}

void diag_warn_como_error(void) {
    warn_es_error = 1;
}

void diag_iniciar(const char *archivo) {
    archivo_fuente = archivo;
    total_errores = 0;
    total_advertencias = 0;
    memset(por_fase, 0, sizeof(por_fase));
}

void diag_archivo(const char *archivo) {
    archivo_fuente = archivo;
}

void diag_max_errores(int n) {
    if (n > 0) max_errores = n;
}

int diag_errores(void) {
    return total_errores;
}

int diag_advertencias(void) {
    return total_advertencias;
}

static int digitos(int n) {
    int d = 1;
    while (n >= 10) { n /= 10; d++; }
    return d;
}

static int leer_linea(int n, char *buf, size_t cap) {
    FILE *f = fopen(archivo_fuente, "r");
    if (f == NULL) return 0;
    int actual = 1, c, encontrada = 0;
    size_t len = 0;
    while ((c = fgetc(f)) != EOF) {
        if (c == '\n') {
            if (actual == n) { encontrada = 1; break; }
            actual++;
        } else if (actual == n && c != '\r' && len + 1 < cap) {
            buf[len++] = (char)c;
        }
    }
    if (c == EOF && actual == n && len > 0) encontrada = 1;
    buf[len] = '\0';
    fclose(f);
    return encontrada;
}

static void imprimir_diag(const char *severidad, const char *codigo, int linea,
                          int col, int largo, const char *fmt, va_list ap) {
    if (linea > 0 && col > 0)
        fprintf(stderr, "%s:%d:%d: %s[%s]: ", archivo_fuente, linea, col, severidad, codigo);
    else
        fprintf(stderr, "%s: %s[%s]: ", archivo_fuente, severidad, codigo);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);

    char texto[1024];
    if (linea <= 0 || col <= 0 || !leer_linea(linea, texto, sizeof(texto))) return;

    int ancho = digitos(linea);
    fprintf(stderr, "%d | %s\n", linea, texto);
    fprintf(stderr, "%*s | ", ancho, "");

    /* Ignora los bytes continuos de UTF-8 al alinear la marca. */
    int pendientes = col - 1;
    const unsigned char *p = (const unsigned char *)texto;
    for (; *p && pendientes > 0; p++) {
        if ((*p & 0xC0) == 0x80) continue;
        fputc(*p == '\t' ? '\t' : ' ', stderr);
        pendientes--;
    }
    while (pendientes-- > 0) fputc(' ', stderr);

    if (largo < 1) largo = 1;
    while (largo-- > 0) fputc('^', stderr);
    fputc('\n', stderr);
}

void diag_error(const char *codigo, int linea, int col, int largo,
                const char *fmt, ...) {
    va_list ap;
    total_errores++;
    if (codigo != NULL && codigo[0] == 'E' && codigo[1] >= '1' && codigo[1] <= '4')
        por_fase[codigo[1] - '0']++;

    va_start(ap, fmt);
    imprimir_diag("error", codigo, linea, col, largo, fmt, ap);
    va_end(ap);

    if (total_errores >= max_errores) {
        fprintf(stderr, "\nse alcanzo el maximo de %d errores (--max-errors)\n", max_errores);
        diag_resumen();
        exit(1);
    }
}

void diag_advertencia(const char *codigo, int linea, int col, int largo,
                      const char *fmt, ...) {
    va_list ap;
    int i = indice_warn(codigo);

    /* Silenciada con -w o con -Wno-W00n: no se imprime ni se cuenta. */
    if (i >= 0 && !(warn_activas & (1u << i))) return;

    total_advertencias++;
    va_start(ap, fmt);
    imprimir_diag(warn_es_error ? "error" : "advertencia",
                  codigo, linea, col, largo, fmt, ap);
    va_end(ap);

    /*
     * Con -Werror la advertencia cuenta como error. Se le asigna la fase 3
     * porque todas las W0xx las emite el analisis semantico, que es donde el
     * documento las ubica.
     */
    if (warn_es_error) {
        total_errores++;
        por_fase[3]++;
        if (total_errores >= max_errores) {
            fprintf(stderr, "\nse alcanzo el maximo de %d errores (--max-errors)\n", max_errores);
            diag_resumen();
            exit(1);
        }
    }
}

void diag_resumen(void) {
    static const char *nombres[5] = {"", "lexicos", "sintacticos", "semanticos", "de enlace"};
    char detalle[160] = "";
    int i;

    /* Sin errores no hay nada que abortar, pero si hubo advertencias conviene
     * decir cuantas: el programa compila y aun asi hay algo que revisar. */
    if (total_errores <= 0) {
        if (total_advertencias > 0)
            fprintf(stderr, "\ncompilacion terminada: %d advertencia%s.\n",
                    total_advertencias, total_advertencias == 1 ? "" : "s");
        return;
    }

    for (i = 1; i <= 4; i++) {
        char una[48];
        if (por_fase[i] == 0) continue;
        snprintf(una, sizeof(una), "%s%d %s", detalle[0] ? ", " : "", por_fase[i], nombres[i]);
        strncat(detalle, una, sizeof(detalle) - strlen(detalle) - 1);
    }

    fprintf(stderr, "\ncompilacion abortada: %d error%s", total_errores,
            total_errores == 1 ? "" : "es");
    if (detalle[0]) fprintf(stderr, " (%s)", detalle);
    /* Con -Werror las advertencias ya estan contadas arriba como errores, asi
     * que repetirlas aparte haria parecer que son el doble. */
    if (total_advertencias > 0 && !warn_es_error)
        fprintf(stderr, ", %d advertencia%s", total_advertencias,
                total_advertencias == 1 ? "" : "s");
    if (total_advertencias > 0 && warn_es_error)
        fprintf(stderr, " (%d por -Werror)", total_advertencias);
    fprintf(stderr, ".\n");
}
