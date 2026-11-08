/*
 * Diagnosticos para el editor.
 *
 * El analisis que corre aqui es el mismo del compilador: las fases 1 a 3 sobre
 * el archivo que el usuario esta editando, con el enlazador resolviendo los
 * 'importa' igual que en una compilacion normal. Lo unico distinto es que
 * diag.c trabaja en modo captura, de modo que cada error queda como un
 * registro con linea, columna y largo en vez de un texto en stderr. Con eso la
 * interfaz dibuja el subrayado exactamente sobre el fragmento culpable.
 *
 * Se pide ademas la tabla de simbolos. Despues de la fase 3 ya se conocen los
 * tipos y los ambitos; corriendo tambien el layout de la fase 4 se obtiene la
 * direccion de memoria de cada variable, que es lo que el panel de simbolos
 * del IDE muestra junto al nombre.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "codegen.h"
#include "diag.h"
#include "enlace.h"
#include "ide.h"
#include "ide_lex.h"
#include "muerto.h"
#include "semantic.h"
#include "symtab.h"
#include "tac.h"

/* La ruta real en disco y el nombre que el editor conoce pueden diferir: el
 * servidor guarda el buffer sin salvar en un archivo temporal. */
static const char *nombre_visible = NULL;

void ide_diag_nombre_visible(const char *nombre) {
    nombre_visible = nombre;
}

static const char *visible(const char *ruta) {
    return nombre_visible != NULL ? nombre_visible : ruta;
}

/* Emite un diagnostico capturado, enriquecido con el catalogo. */
static void emitir_diagnostico(JsonW *j, const DiagRegistro *r, const char *ruta) {
    const EntradaCatalogo *cat = ide_catalogo_buscar(r->codigo);

    jw_obj_abrir(j);
    jw_cadena(j, "severidad", r->severidad);
    jw_cadena(j, "codigo", r->codigo);
    jw_cadena(j, "fase", ide_catalogo_fase(r->codigo));
    jw_cadena(j, "archivo", visible(ruta));
    jw_entero(j, "linea", r->linea);
    jw_entero(j, "columna", r->columna);
    jw_entero(j, "largo", r->largo);
    jw_cadena(j, "mensaje", r->mensaje);
    if (cat != NULL) {
        jw_cadena(j, "titulo", cat->titulo);
        jw_cadena(j, "explicacion", cat->explicacion);
        jw_cadena(j, "remedio", cat->remedio);
    } else {
        /* Codigo sin entrada en el catalogo: se reporta igual, pero la prueba
         * del catalogo lo detecta como hueco que hay que llenar. */
        jw_nulo(j, "titulo");
        jw_nulo(j, "explicacion");
        jw_nulo(j, "remedio");
    }
    jw_obj_cerrar(j);
}

static const char *texto_clase(SymbolKind k) {
    switch (k) {
        case SYMBOL_VAR:    return "variable";
        case SYMBOL_PARAM:  return "parametro";
        case SYMBOL_CONST:  return "constante";
        case SYMBOL_FUNC:   return "funcion";
        case SYMBOL_MODULE: return "modulo";
    }
    return "desconocido";
}

/*
 * Vuelca el listado de la tabla de simbolos. Para cada nombre se incluye la
 * direccion de memoria: 'DMEM' con la direccion absoluta para globales y para
 * la primera activacion de las locales, 'IMEM' para el primer bundle de una
 * funcion. Esa es la informacion que el profesor pide ver junto a cada
 * variable, y sale del mismo calculo que usa el generador de codigo.
 */
static void emitir_simbolos(JsonW *j, const SymbolTable *tabla) {
    char tipo[64];
    const Entrada *e;

    jw_clave_arr(j, "simbolos");
    for (e = tabla->listado; e != NULL; e = e->next) {
        jw_obj_abrir(j);
        jw_cadena(j, "nombre", e->name != NULL ? e->name : "");
        jw_cadena(j, "ambito", e->ambito != NULL ? e->ambito : "global");
        jw_cadena(j, "clase", texto_clase(e->kind));
        jw_cadena(j, "tipo", tipo_con_dims(tipo, sizeof(tipo), e->type, e->dimensions));
        jw_entero(j, "nivel", e->level);
        jw_entero(j, "linea", e->line);
        jw_entero(j, "columna", e->col);
        jw_bool(j, "global", e->is_global);
        jw_entero(j, "bytes", e->size_bytes);

        if (e->is_intrinsic) {
            /* Una intrinseca la resuelve el generador de codigo: no ocupa una
             * direccion propia en la imagen de Nova. */
            jw_cadena(j, "region", "intrinseca");
            jw_nulo(j, "direccion");
        } else if (e->has_data_address) {
            jw_cadena(j, "region", "DMEM");
            jw_entero(j, "direccion", (long)e->data_address);
        } else if (e->has_code_address) {
            jw_cadena(j, "region", "IMEM");
            jw_entero(j, "direccion", (long)e->code_address);
        } else if (e->is_global && e->kind != SYMBOL_FUNC && e->kind != SYMBOL_MODULE) {
            jw_cadena(j, "region", "DMEM");
            jw_entero(j, "direccion", (long)e->offset);
        } else {
            jw_nulo(j, "region");
            jw_nulo(j, "direccion");
        }

        /* Para una local, el desplazamiento respecto de R14 es lo que de
         * verdad codifica la instruccion; la direccion absoluta vale solo
         * para la primera activacion. */
        if (e->has_frame_offset) jw_entero(j, "desplazamiento_r14", e->frame_offset);
        else jw_nulo(j, "desplazamiento_r14");

        if (e->kind == SYMBOL_FUNC) {
            jw_entero(j, "parametros", e->param_count);
            if (e->has_frame_total) jw_entero(j, "marco", e->frame_total);
            else jw_entero(j, "marco", e->local_frame_size);
            jw_bool(j, "intrinseca", e->is_intrinsic);
            jw_bool(j, "privada", e->is_private);
        }
        if (e->has_const_value) jw_entero(j, "valor", (long)e->const_value);
        jw_obj_cerrar(j);
    }
    jw_arr_cerrar(j);
}

/* Igual que el trabajo 'tokens', pero anidado dentro de esta respuesta. */
static void emitir_tokens_inline(JsonW *j, const char *ruta) {
    ListaTokens tk;
    int i;

    jw_clave_arr(j, "tokens");
    if (ide_tokenizar_archivo(ruta, &tk)) {
        for (i = 0; i < tk.n; i++) {
            jw_obj_abrir(j);
            jw_cadena(j, "categoria", ide_token_categoria(tk.v[i].tipo));
            jw_entero(j, "linea", tk.v[i].linea);
            jw_entero(j, "columna", tk.v[i].columna);
            jw_entero(j, "fin_linea", tk.v[i].fin_linea);
            jw_entero(j, "fin_columna", tk.v[i].fin_columna);
            jw_obj_cerrar(j);
        }
        ide_tokens_liberar(&tk);
    }
    jw_arr_cerrar(j);
}

int ide_diagnosticar(const char *ruta, int con_tokens, JsonW *j) {
    Nodo *ast = NULL;
    SymbolTable *tabla = NULL;
    int i, n;
    int parse_rc;
    int enlace_ok = 1;
    int sem_ok = 0;

    diag_limpiar_captura();
    diag_capturar(1);
    diag_iniciar(ruta);

    parse_rc = parse_source(ruta, &ast);

    /*
     * El analisis avanza tan lejos como pueda. Si la fase 2 fallo no hay AST
     * utilizable y se reporta solo lo lexico y sintactico; si paso, se enlaza
     * y se corre la fase 3 para obtener tambien los errores de tipos.
     */
    if (parse_rc == 0 && ast != NULL) {
        enlace_ok = link_modules(ast, ruta, NULL, 0);
        if (enlace_ok) {
            sem_ok = semantic_analyze(ast, &tabla) ? 1 : 0;

            /*
             * El layout de la fase 4 es lo que convierte los desplazamientos
             * en direcciones absolutas. Se corre solo si la fase 3 quedo
             * limpia: sobre un arbol con errores de tipos no tiene sentido.
             */
            if (sem_ok && tabla != NULL) {
                TACList *layout = tac_generate_from_ast(ast, tabla);
                codegen_update_symbol_layout(layout, tabla);
                /*
                 * Fase 6, solo por sus advertencias. Se corre DESPUES del
                 * layout para que las direcciones que muestra el editor sigan
                 * siendo las de -O0, que es como compila por omision; esta
                 * copia se descarta enseguida, asi que optimizarla no afecta a
                 * nada mas.
                 *
                 * Sale casi gratis: el codigo intermedio ya esta generado y el
                 * grafo mas la vivacidad cuestan menos que el propio layout,
                 * que arma el programa entero con relajacion de saltos.
                 *
                 * El resultado es que una asignacion muerta se subraya mientras
                 * se escribe, igual que un error de tipos, en vez de aparecer
                 * recien al compilar con -O1.
                 */
                muerto_eliminar(layout, NULL, 1);
                tac_free(layout);
            }
        }
    }

    diag_capturar(0);

    jw_obj_abrir(j);
    jw_cadena(j, "trabajo", "diagnosticar");
    jw_cadena(j, "archivo", visible(ruta));
    jw_bool(j, "ok", parse_rc == 0 && enlace_ok && sem_ok);

    n = diag_capturados();
    jw_clave_arr(j, "diagnosticos");
    for (i = 0; i < n; i++) {
        const DiagRegistro *r = diag_capturado(i);
        if (r != NULL) emitir_diagnostico(j, r, ruta);
    }
    jw_arr_cerrar(j);

    /*
     * Clase del archivo.
     *
     * El compilador exige 'principale' para armar un ejecutable y, si falta,
     * emite E405. El editor no puede dar ese error, porque no sabe si lo que
     * se esta escribiendo es el programa o un modulo de biblioteca: ambos son
     * archivos .nv validos y un modulo se compila con -c precisamente sin
     * punto de entrada. Marcarlo como error haria que todo modulo apareciera
     * roto en el editor. En vez de eso se informa que clase de archivo es, y
     * la interfaz lo muestra como dato, no como falla.
     */
    jw_clave_obj(j, "punto_entrada");
    {
        int tiene = 0;
        if (tabla != NULL) {
            const Entrada *e;
            for (e = tabla->listado; e != NULL; e = e->next)
                if (e->kind == SYMBOL_FUNC && !e->is_intrinsic && e->name != NULL &&
                    strcmp(e->name, "principale") == 0) { tiene = 1; break; }
        }
        jw_bool(j, "tiene_principale", tiene);
        jw_cadena(j, "clase", tiene ? "ejecutable" : "modulo");
        jw_cadena(j, "nota", tiene
            ? "Tiene 'principale': se puede compilar a un ejecutable de CERBERO."
            : "Sin 'principale'. Es un modulo de biblioteca: se empaqueta con -c, "
              "o agregue 'functio principale() -> integer' para hacerlo ejecutable.");
    }
    jw_obj_cerrar(j);

    jw_clave_obj(j, "resumen");
    {
        int errores = 0, advertencias = 0;
        for (i = 0; i < n; i++) {
            const DiagRegistro *r = diag_capturado(i);
            if (r == NULL) continue;
            if (strcmp(r->severidad, "error") == 0) errores++;
            else advertencias++;
        }
        jw_entero(j, "errores", errores);
        jw_entero(j, "advertencias", advertencias);
    }
    jw_obj_cerrar(j);

    if (sem_ok && tabla != NULL) emitir_simbolos(j, tabla);
    else { jw_clave_arr(j, "simbolos"); jw_arr_cerrar(j); }

    /*
     * Puntos de salto. Son los que genera el compilador para condicionales y
     * ciclos, con la direccion que les asigno la resolucion de saltos. Van
     * aparte de los simbolos porque no son nombres del programa fuente sino
     * del codigo generado, pero la guia los pide registrados igual.
     */
    jw_clave_arr(j, "etiquetas");
    if (sem_ok) {
        const CodegenEtiqueta *etqs = NULL;
        int n = codegen_etiquetas(&etqs);
        for (i = 0; i < n; i++) {
            jw_obj_abrir(j);
            jw_cadena(j, "nombre", etqs[i].nombre);
            jw_entero(j, "direccion", (long)etqs[i].direccion);
            jw_cadena(j, "region", etqs[i].es_dato ? "DMEM" : "IMEM");
            if (etqs[i].es_dato) jw_nulo(j, "bundle");
            else jw_entero(j, "bundle", etqs[i].bundle);
            jw_obj_cerrar(j);
        }
    }
    jw_arr_cerrar(j);

    /*
     * El editor pinta el codigo con estos tokens, de modo que el coloreado
     * tampoco depende de una segunda implementacion del lexer. Van en la
     * misma respuesta que los diagnosticos para no gastar otra peticion por
     * cada pausa al escribir.
     */
    if (con_tokens) emitir_tokens_inline(j, ruta);

    jw_obj_cerrar(j);

    symtab_destroy(tabla);
    if (ast != NULL) liberar_ast(ast);
    release_modules();
    raiz_ast = NULL;
    return 0;
}
