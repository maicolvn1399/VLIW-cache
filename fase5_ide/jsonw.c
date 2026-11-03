#include <stdio.h>
#include <string.h>
#include "jsonw.h"

void jw_iniciar(JsonW *j, FILE *salida) {
    j->salida = salida;
    j->nivel = 0;
    j->tiene_item[0] = 0;
}

/*
 * Antes de cada valor nuevo se decide si hace falta una coma. El primer
 * elemento de un nivel no la lleva; a partir del segundo, si.
 */
static void separar(JsonW *j) {
    if (j->nivel >= 0 && j->tiene_item[j->nivel]) fputc(',', j->salida);
    if (j->nivel >= 0) j->tiene_item[j->nivel] = 1;
}

static void entrar(JsonW *j) {
    if (j->nivel + 1 < JSONW_MAX_NIVEL) {
        j->nivel++;
        j->tiene_item[j->nivel] = 0;
    }
}

static void salir(JsonW *j) {
    if (j->nivel > 0) j->nivel--;
}

/*
 * Escape conforme a JSON. Los caracteres de control por debajo de 0x20 van
 * como \u00XX. Los bytes altos (UTF-8) se copian tal cual: el documento se
 * declara UTF-8 y los acentos del espanol deben llegar intactos a la interfaz.
 */
static void escribir_cadena(FILE *f, const char *s) {
    fputc('"', f);
    if (s != NULL) {
        for (; *s; s++) {
            unsigned char c = (unsigned char)*s;
            switch (c) {
                case '"':  fputs("\\\"", f); break;
                case '\\': fputs("\\\\", f); break;
                case '\n': fputs("\\n", f);  break;
                case '\r': fputs("\\r", f);  break;
                case '\t': fputs("\\t", f);  break;
                case '\b': fputs("\\b", f);  break;
                case '\f': fputs("\\f", f);  break;
                default:
                    if (c < 0x20) fprintf(f, "\\u%04x", c);
                    else fputc(c, f);
            }
        }
    }
    fputc('"', f);
}

static void clave(JsonW *j, const char *c) {
    separar(j);
    if (c != NULL) {
        escribir_cadena(j->salida, c);
        fputc(':', j->salida);
    }
}

void jw_obj_abrir(JsonW *j)  { separar(j); fputc('{', j->salida); entrar(j); }
void jw_obj_cerrar(JsonW *j) { salir(j); fputc('}', j->salida); }
void jw_arr_abrir(JsonW *j)  { separar(j); fputc('[', j->salida); entrar(j); }
void jw_arr_cerrar(JsonW *j) { salir(j); fputc(']', j->salida); }

void jw_clave_obj(JsonW *j, const char *c) { clave(j, c); fputc('{', j->salida); entrar(j); }
void jw_clave_arr(JsonW *j, const char *c) { clave(j, c); fputc('[', j->salida); entrar(j); }

void jw_cadena(JsonW *j, const char *c, const char *valor) {
    clave(j, c);
    escribir_cadena(j->salida, valor);
}

void jw_entero(JsonW *j, const char *c, long valor) {
    clave(j, c);
    fprintf(j->salida, "%ld", valor);
}

void jw_bool(JsonW *j, const char *c, int valor) {
    clave(j, c);
    fputs(valor ? "true" : "false", j->salida);
}

void jw_nulo(JsonW *j, const char *c) {
    clave(j, c);
    fputs("null", j->salida);
}

void jw_real(JsonW *j, const char *c, double valor) {
    clave(j, c);
    fprintf(j->salida, "%.4f", valor);
}

void jw_item_cadena(JsonW *j, const char *valor) {
    separar(j);
    escribir_cadena(j->salida, valor);
}

void jw_item_entero(JsonW *j, long valor) {
    separar(j);
    fprintf(j->salida, "%ld", valor);
}
