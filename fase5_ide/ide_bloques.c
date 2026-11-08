/*
 * El grafo de flujo de control, para el IDE.
 *
 * Entrega los bloques basicos con sus instrucciones y sus aristas. El trabajo
 * de analisis esta en fase6_optimizacion/bloques.c -- el mismo que usa
 * 'novac --bloques'-- y aqui solo se serializa: la interfaz dibuja lo que el
 * compilador calculo, no una version propia.
 *
 * Va como trabajo aparte y no dentro de 'diagnosticar' porque construir el
 * grafo obliga a correr la fase 4 completa, y el editor pide diagnosticos en
 * cada pausa de tecleo. El flujo se consulta solo cuando el usuario abre esa
 * vista.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "bloques.h"
#include "codegen.h"
#include "diag.h"
#include "enlace.h"
#include "ide.h"
#include "semantic.h"
#include "symtab.h"
#include "tac.h"
#include "vivacidad.h"

/* Texto de una instruccion, con el mismo formateador que usa --ir. */
static char *texto_instruccion(const TACInst *i) {
    char *buf = NULL;
    size_t n = 0;
    FILE *m = open_memstream(&buf, &n);
    if (m == NULL) return NULL;
    tac_print_inst(m, i);
    fclose(m);
    /* tac_print_inst termina en salto de linea y sangra; se recorta. */
    if (buf != NULL) {
        size_t k = strlen(buf);
        while (k > 0 && (buf[k - 1] == '\n' || buf[k - 1] == ' ')) buf[--k] = '\0';
        {
            char *p = buf;
            while (*p == ' ') p++;
            if (p != buf) memmove(buf, p, strlen(p) + 1);
        }
    }
    return buf;
}

/* Los nombres de un conjunto del analisis, como arreglo de cadenas. */
static void emitir_conjunto(JsonW *j, const char *clave,
                            const VivacidadFuncion *vf, const unsigned *c) {
    int n;
    jw_clave_arr(j, clave);
    if (vf != NULL && c != NULL)
        for (n = 0; n < vf->n_nombres; n++)
            if ((c[n / 32] >> (n % 32)) & 1u)
                jw_item_cadena(j, vf->nombres[n]);
    jw_arr_cerrar(j);
}

/*
 * Un bloque, con lo que el analisis de vivacidad encontro en el.
 *
 * El grafo que se manda es el del codigo SIN optimizar, con las instrucciones
 * sobrantes marcadas. Asi el editor muestra el codigo muerto en su sitio -- se
 * ve por que sobra -- en vez de un programa del que ya desaparecio.
 */
static void emitir_bloque(JsonW *j, const Bloque *b, int es_entrada,
                          const VivacidadFuncion *vf, int idx_bloque,
                          int *n_sobran) {
    const TACInst *i;
    unsigned char *marca = NULL;
    int k, p = 0;

    if (vf != NULL && b->n_inst > 0) {
        marca = calloc((size_t)b->n_inst, 1);
        if (marca != NULL)
            viv_muertas_en_bloque(vf, idx_bloque, marca, b->n_inst, NULL);
    }

    jw_obj_abrir(j);
    jw_entero(j, "id", b->id);
    if (b->etiqueta != NULL) jw_cadena(j, "etiqueta", b->etiqueta);
    else jw_nulo(j, "etiqueta");
    jw_cadena(j, "fin", cfg_fin_nombre(b->fin));
    jw_entero(j, "instrucciones", b->n_inst);
    jw_bool(j, "entrada", es_entrada);
    jw_bool(j, "alcanzable", b->alcanzable != 0);
    jw_entero(j, "profundidad_ciclo", b->profundidad_ciclo);
    jw_entero(j, "linea", b->primera != NULL ? b->primera->linea : 0);

    jw_clave_arr(j, "sucesores");
    for (k = 0; k < b->n_suc; k++) jw_item_entero(j, b->sucesores[k]);
    jw_arr_cerrar(j);

    jw_clave_arr(j, "predecesores");
    for (k = 0; k < b->n_pred; k++) jw_item_entero(j, b->predecesores[k]);
    jw_arr_cerrar(j);

    if (vf != NULL) {
        int w = vf->n_palabras;
        emitir_conjunto(j, "uso",      vf, &vf->uso[(size_t)idx_bloque * w]);
        emitir_conjunto(j, "def",      vf, &vf->def[(size_t)idx_bloque * w]);
        emitir_conjunto(j, "vivo_ent", vf, &vf->vivo_ent[(size_t)idx_bloque * w]);
        emitir_conjunto(j, "vivo_sal", vf, &vf->vivo_sal[(size_t)idx_bloque * w]);
    }

    jw_clave_arr(j, "codigo");
    for (i = b->primera; i != NULL; i = i->next) {
        char *t = texto_instruccion(i);
        int m = (marca != NULL && p < b->n_inst) ? marca[p] : 0;
        jw_obj_abrir(j);
        jw_cadena(j, "texto", t != NULL ? t : "");
        jw_entero(j, "linea", i->linea);
        jw_entero(j, "columna", i->columna);
        /*
         * 0 se queda, 1 la quita -O1, 2 la llamada se queda pero su resultado
         * no se usa. La interfaz las pinta distinto.
         */
        jw_entero(j, "muerta", m);
        jw_obj_cerrar(j);
        if (m == VIV_SOBRA && n_sobran != NULL) (*n_sobran)++;
        free(t);
        p++;
        if (i == b->ultima) break;
    }
    jw_arr_cerrar(j);

    jw_obj_cerrar(j);
    free(marca);
}

int ide_bloques(const char *ruta, JsonW *j) {
    Nodo *ast = NULL;
    SymbolTable *tabla = NULL;
    TACList *tac = NULL;
    GrafoFlujo *g = NULL;
    Vivacidad *viv = NULL;
    int f, k;
    int ok = 0;
    int sobran = 0;

    diag_limpiar_captura();
    diag_capturar(1);
    diag_iniciar(ruta);

    if (parse_source(ruta, &ast) == 0 && ast != NULL &&
        link_modules(ast, ruta, NULL, 0) &&
        semantic_analyze(ast, &tabla) && tabla != NULL) {
        tac = tac_generate_from_ast(ast, tabla);
        g = cfg_construir(tac);
        if (g != NULL) viv = viv_analizar(g, tac);
        ok = (g != NULL);
    }
    diag_capturar(0);

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "bloques");
    jw_cadena(j, "archivo", ruta);
    jw_bool(j, "ok", ok);

    if (!ok) {
        /*
         * Sin un analisis limpio no hay codigo intermedio y por tanto no hay
         * grafo. Se dice por que, para que la vista pueda explicarlo en vez
         * de quedarse vacia.
         */
        jw_cadena(j, "motivo",
                  "El grafo de flujo se construye sobre el codigo intermedio, "
                  "que solo se genera si el programa analiza sin errores.");
        jw_clave_arr(j, "funciones");
        jw_arr_cerrar(j);
        jw_obj_cerrar(j);
    } else {
        int tb = 0, ta = 0, ti = 0;

        jw_clave_arr(j, "funciones");
        for (f = 0; f < g->n_funciones; f++) {
            const GrafoFuncion *fn = &g->funciones[f];
            const VivacidadFuncion *vf =
                (viv != NULL && f < viv->n_funciones) ? &viv->funciones[f] : NULL;
            jw_obj_abrir(j);
            jw_cadena(j, "nombre", fn->nombre);
            jw_entero(j, "bloques", fn->n_bloques);
            jw_entero(j, "aristas", fn->n_aristas);
            jw_entero(j, "inalcanzables", fn->n_inalcanzables);
            if (vf != NULL) {
                jw_entero(j, "nombres_analizados", vf->n_nombres);
                jw_entero(j, "iteraciones", vf->iteraciones);
            }
            jw_clave_arr(j, "lista");
            for (k = 0; k < fn->n_bloques; k++)
                emitir_bloque(j, &fn->bloques[k], k == 0, vf, k, &sobran);
            jw_arr_cerrar(j);
            jw_obj_cerrar(j);

            tb += fn->n_bloques;
            ta += fn->n_aristas;
            ti += fn->n_inalcanzables;
        }
        jw_arr_cerrar(j);

        jw_clave_obj(j, "resumen");
        jw_entero(j, "funciones", g->n_funciones);
        jw_entero(j, "bloques", tb);
        jw_entero(j, "aristas", ta);
        jw_entero(j, "inalcanzables", ti);
        /* Cuantas instrucciones de tres direcciones quitaria -O1. */
        jw_entero(j, "sobran", sobran);
        jw_obj_cerrar(j);
        jw_obj_cerrar(j);
    }

    viv_liberar(viv);
    cfg_liberar(g);
    tac_free(tac);
    symtab_destroy(tabla);
    if (ast != NULL) liberar_ast(ast);
    release_modules();
    raiz_ast = NULL;
    return 0;
}
