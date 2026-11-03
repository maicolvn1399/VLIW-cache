#ifndef IDE_H
#define IDE_H

#include "jsonw.h"

/*
 * Nucleo del IDE de Nova.
 *
 * Todo el trabajo que requiere entender el lenguaje vive aqui, en C, enlazado
 * contra las mismas fases que usa el compilador. La interfaz grafica solo pide
 * trabajos y dibuja el resultado: no reimplementa ni el lexer ni el parser ni
 * las reglas semanticas, de modo que lo que marca el editor y lo que reporta
 * 'novac' no se pueden separar.
 *
 * El binario 'novaide' atiende un trabajo por ejecucion y contesta JSON por
 * stdout. Correr un proceso por peticion evita arrastrar el estado global del
 * lexer y del parser entre analisis, que es la fuente de errores mas comun al
 * reutilizar un compilador dentro de un servicio.
 */

/* ---------------------------------------------------------------- catalogo */

/*
 * Descripcion legible de cada codigo de diagnostico. El mensaje que emite el
 * compilador dice que paso; el catalogo agrega por que pasa y como se arregla,
 * que es lo que el editor muestra al pasar el puntero sobre el subrayado.
 */
typedef struct {
    const char *codigo;
    const char *titulo;      /* etiqueta corta para la lista de problemas */
    const char *explicacion; /* por que el compilador rechaza esto */
    const char *remedio;     /* que hacer para resolverlo */
} EntradaCatalogo;

const EntradaCatalogo *ide_catalogo_buscar(const char *codigo);
/* Fase a la que pertenece un codigo: "lexico", "sintactico", ... */
const char *ide_catalogo_fase(const char *codigo);

/* ------------------------------------------------------------ diagnosticos */

/*
 * Analiza un archivo y escribe los diagnosticos como JSON. Corre las fases
 * lexica, sintactica y semantica; no genera codigo, porque el editor necesita
 * respuesta inmediata mientras se escribe.
 */
int ide_diagnosticar(const char *ruta, int con_tokens, JsonW *j);

/*
 * Nombre que el editor conoce para el archivo. El servidor escribe el buffer
 * sin salvar en un temporal, asi que la ruta en disco no es la que el usuario
 * ve; esto hace que los diagnosticos salgan con el nombre correcto.
 */
void ide_diag_nombre_visible(const char *nombre);

/* ------------------------------------------------------------ autocompletar */

int ide_completar(const char *ruta, int linea, int columna, JsonW *j);

/* ------------------------------------------------- correccion de errores */

int ide_arreglar(const char *ruta, JsonW *j);

/* ------------------------------------------------- grafo de flujo (Iter. 2) */

/*
 * Bloques basicos y aristas del grafo de flujo de control. El analisis lo
 * hace fase6_optimizacion/bloques.c; aqui solo se serializa.
 */
int ide_bloques(const char *ruta, JsonW *j);

/* ------------------------------------------------------- deteccion de clones */

#define IDE_MAX_ARCHIVOS 64

int ide_clones(const char **rutas, int n_rutas, int min_tokens,
               double umbral_tipo3, JsonW *j);

/* ------------------------------------------------------------------ utiles */

/* Lee un archivo completo a memoria. El llamador libera con free(). */
char *ide_leer_archivo(const char *ruta, size_t *largo);

#endif
