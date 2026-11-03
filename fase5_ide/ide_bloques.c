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

static void emitir_bloque(JsonW *j, const Bloque *b, int es_entrada) {
    const TACInst *i;
    int k;

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

    jw_clave_arr(j, "codigo");
    for (i = b->primera; i != NULL; i = i->next) {
        char *t = texto_instruccion(i);
        jw_obj_abrir(j);
        jw_cadena(j, "texto", t != NULL ? t : "");
        jw_entero(j, "linea", i->linea);
        jw_entero(j, "columna", i->columna);
        jw_obj_cerrar(j);
        free(t);
        if (i == b->ultima) break;
    }
    jw_arr_cerrar(j);

    jw_obj_cerrar(j);
}

int ide_bloques(const char *ruta, JsonW *j) {
    Nodo *ast = NULL;
    SymbolTable *tabla = NULL;
    TACList *tac = NULL;
    GrafoFlujo *g = NULL;
    int f, k;
    int ok = 0;

    diag_limpiar_captura();
    diag_capturar(1);
    diag_iniciar(ruta);

    if (parse_source(ruta, &ast) == 0 && ast != NULL &&
        link_modules(ast, ruta, NULL, 0) &&
        semantic_analyze(ast, &tabla) && tabla != NULL) {
        tac = tac_generate_from_ast(ast, tabla);
        g = cfg_construir(tac);
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
            jw_obj_abrir(j);
            jw_cadena(j, "nombre", fn->nombre);
            jw_entero(j, "bloques", fn->n_bloques);
            jw_entero(j, "aristas", fn->n_aristas);
            jw_entero(j, "inalcanzables", fn->n_inalcanzables);
            jw_clave_arr(j, "lista");
            for (k = 0; k < fn->n_bloques; k++)
                emitir_bloque(j, &fn->bloques[k], k == 0);
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
        jw_obj_cerrar(j);
        jw_obj_cerrar(j);
    }

    cfg_liberar(g);
    tac_free(tac);
    symtab_destroy(tabla);
    if (ast != NULL) liberar_ast(ast);
    release_modules();
    raiz_ast = NULL;
    return 0;
}
