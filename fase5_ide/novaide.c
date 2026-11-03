/*
 * novaide: nucleo del IDE de Nova.
 *
 * Atiende un trabajo por ejecucion y contesta JSON por la salida estandar.
 * La interfaz grafica lo invoca para cada cosa que necesita saber del
 * lenguaje: que errores tiene el archivo, que puede escribirse en la posicion
 * del cursor, que correcciones automaticas aplican, y que funciones estan
 * clonadas entre varios archivos.
 *
 * Un proceso por peticion es deliberado. El lexer y el parser generados por
 * flex y bison llevan estado global, y reiniciarlo entre analisis dentro de un
 * mismo proceso es una fuente conocida de resultados que dependen del orden de
 * las peticiones. Arrancar un proceso cuesta menos de un milisegundo y a
 * cambio cada analisis parte siempre del mismo estado, igual que una
 * compilacion recien lanzada.
 *
 * Ejemplos:
 *   novaide diagnosticar programa.nv
 *   novaide completar programa.nv --linea 7 --columna 12
 *   novaide arreglar programa.nv
 *   novaide clones a.nv b.nv c.nv
 *   novaide catalogo
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ide.h"
#include "ide_lex.h"
#include "jsonw.h"

int ide_catalogo_total(void);
const EntradaCatalogo *ide_catalogo_indice(int i);

static void uso(void) {
    fprintf(stderr,
        "Uso: novaide <trabajo> [argumentos]\n"
        "\n"
        "Trabajos:\n"
        "  diagnosticar <archivo>            Errores, advertencias y tabla de simbolos\n"
        "  completar <archivo> --linea N --columna M\n"
        "                                    Sugerencias de codigo en esa posicion\n"
        "  arreglar <archivo>                Correcciones automaticas propuestas\n"
        "  bloques <archivo>                 Bloques basicos y grafo de flujo\n"
        "  clones <archivo>...               Clones Tipo I, II y III entre archivos\n"
        "  tokens <archivo>                  Flujo de tokens con su categoria de color\n"
        "  catalogo                          Catalogo de diagnosticos del lenguaje\n"
        "\n"
        "Opciones comunes:\n"
        "  --como <nombre>     Nombre a reportar en vez de la ruta real\n"
        "  --con-tokens        Agrega el flujo de tokens a 'diagnosticar'\n"
        "  --min-tokens <n>    Tamano minimo de funcion para 'clones' (por omision 20)\n"
        "  --umbral <0..1>     Similitud minima de un clon Tipo III (por omision 0.80)\n"
        "\n"
        "La respuesta siempre es un objeto JSON en la salida estandar.\n");
}

static void error_json(const char *mensaje) {
    JsonW j;
    jw_iniciar(&j, stdout);
    jw_obj_abrir(&j);
    jw_cadena(&j, "error", mensaje);
    jw_obj_cerrar(&j);
    fputc('\n', stdout);
}

static int entero_de(const char *s, int por_omision) {
    char *fin = NULL;
    long v;
    if (s == NULL) return por_omision;
    v = strtol(s, &fin, 10);
    if (fin == s || *fin != '\0') return por_omision;
    return (int)v;
}

static void emitir_catalogo(JsonW *j) {
    int i, n = ide_catalogo_total();
    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "catalogo");
    jw_entero(j, "total", n);
    jw_clave_arr(j, "entradas");
    for (i = 0; i < n; i++) {
        const EntradaCatalogo *e = ide_catalogo_indice(i);
        if (e == NULL) continue;
        jw_obj_abrir(j);
        jw_cadena(j, "codigo", e->codigo);
        jw_cadena(j, "fase", ide_catalogo_fase(e->codigo));
        jw_cadena(j, "titulo", e->titulo);
        jw_cadena(j, "explicacion", e->explicacion);
        jw_cadena(j, "remedio", e->remedio);
        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
    jw_obj_cerrar(j);
}

int main(int argc, char **argv) {
    JsonW j;
    const char *trabajo;
    const char *como = NULL;
    const char *rutas[IDE_MAX_ARCHIVOS];
    int n_rutas = 0;
    int linea = 1, columna = 1;
    int min_tokens = 20;
    int con_tokens = 0;
    double umbral = 0.80;
    int i, rc;

    if (argc < 2) { uso(); return 2; }
    trabajo = argv[1];

    if (strcmp(trabajo, "-h") == 0 || strcmp(trabajo, "--help") == 0) {
        uso();
        return 0;
    }

    for (i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--linea") == 0 && i + 1 < argc) {
            linea = entero_de(argv[++i], 1);
        } else if (strcmp(argv[i], "--columna") == 0 && i + 1 < argc) {
            columna = entero_de(argv[++i], 1);
        } else if (strcmp(argv[i], "--con-tokens") == 0) {
            con_tokens = 1;
        } else if (strcmp(argv[i], "--como") == 0 && i + 1 < argc) {
            como = argv[++i];
        } else if (strcmp(argv[i], "--min-tokens") == 0 && i + 1 < argc) {
            min_tokens = entero_de(argv[++i], 20);
        } else if (strcmp(argv[i], "--umbral") == 0 && i + 1 < argc) {
            umbral = atof(argv[++i]);
        } else if (argv[i][0] == '-' && argv[i][1] == '-') {
            error_json("opcion desconocida");
            return 2;
        } else if (n_rutas < IDE_MAX_ARCHIVOS) {
            rutas[n_rutas++] = argv[i];
        } else {
            error_json("demasiados archivos");
            return 2;
        }
    }

    jw_iniciar(&j, stdout);

    if (strcmp(trabajo, "catalogo") == 0) {
        emitir_catalogo(&j);
        fputc('\n', stdout);
        return 0;
    }

    if (n_rutas == 0) {
        error_json("falta el archivo a analizar");
        return 2;
    }

    if (como != NULL) ide_diag_nombre_visible(como);

    if (strcmp(trabajo, "diagnosticar") == 0) {
        rc = ide_diagnosticar(rutas[0], con_tokens, &j);
    } else if (strcmp(trabajo, "completar") == 0) {
        rc = ide_completar(rutas[0], linea, columna, &j);
    } else if (strcmp(trabajo, "arreglar") == 0) {
        rc = ide_arreglar(rutas[0], &j);
    } else if (strcmp(trabajo, "bloques") == 0) {
        rc = ide_bloques(rutas[0], &j);
    } else if (strcmp(trabajo, "tokens") == 0) {
        rc = ide_tokens_json(rutas[0], &j);
    } else if (strcmp(trabajo, "clones") == 0) {
        rc = ide_clones(rutas, n_rutas, min_tokens, umbral, &j);
    } else {
        error_json("trabajo desconocido");
        return 2;
    }

    fputc('\n', stdout);
    return rc;
}
