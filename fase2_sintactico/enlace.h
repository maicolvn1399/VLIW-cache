#ifndef ENLACE_H
#define ENLACE_H

#include <stddef.h>
#include <stdint.h>
#include "ast.h"

/*
 * Lectura de fuentes, ejecucion de las fases 1 y 2, y enlace de modulos.
 *
 * Esta logica vivia dentro de main.c en el Proyecto I, lo que la ataba al
 * ejecutable del compilador: cualquier otra herramienta que necesitara el
 * mismo analisis tenia que reimplementarlo y, con ello, arriesgarse a divergir
 * del compilador. Al quedar en su propia unidad la comparten 'novac' y
 * 'novaide', de modo que el editor marca exactamente los mismos errores que
 * reporta la compilacion, sin una segunda implementacion que mantener.
 *
 * Ninguna funcion cambio de comportamiento al moverse: son las mismas que
 * ejecutaba el Proyecto I.
 */

#define NOVA_MAX_MODULOS 128
#define NOVA_MAX_RUTAS 16
#define NVO_HEADER_SIZE 16

/* ------------------------------------------------- utilidades de archivo */

char *copy_string(const char *s);
uint32_t checksum_bytes(const unsigned char *p, size_t n);
uint32_t get_u32(const unsigned char *p);
void put_u32(unsigned char *p, uint32_t v);
int has_suffix(const char *s, const char *suffix);

/* Lee el archivo completo; deja el largo en *length. El llamador libera. */
char *read_file_bytes(const char *path, size_t *length);

/*
 * Igual que read_file_bytes para un .nv. Para un .nvo valida encabezado,
 * version y checksum, y devuelve la fuente que el objeto guarda dentro.
 */
char *source_from_file(const char *path, size_t *length);

/* ------------------------------------------------------- fases 1 y 2 */

/*
 * Corre el lexer y el parser sobre un archivo y deja el AST en *out_ast.
 * Devuelve 0 si todo salio bien, 1 si hubo errores de compilacion y 3 si no
 * se pudo leer la fuente.
 */
int parse_source(const char *path, Nodo **out_ast);

/*
 * Igual que parse_source, pero sobre un buffer en memoria. 'nombre' es el que
 * se reporta en los diagnosticos.
 *
 * Lo usa el IDE para analizar una variante del texto sin tocar el disco: al
 * completar, el identificador a medio escribir suele romper el analisis, y
 * volver a analizar sin el permite recuperar los tipos y las direcciones.
 */
int parse_buffer(const char *fuente, size_t largo, const char *nombre,
                 Nodo **out_ast);

/* ------------------------------------------------------ enlace de modulos */

/* Agrega un directorio de busqueda para 'importa' (opcion -I). */
int nova_agregar_ruta_modulos(const char *dir);

/*
 * Resuelve los 'importa' a partir del modulo raiz, reescribe los nombres de
 * cada modulo con un prefijo unico y junta todas las declaraciones globales
 * bajo la raiz. Devuelve 1 si el enlace quedo sin errores.
 */
int link_modules(Nodo *root, const char *root_path,
                 char **extra_paths, int extra_count);

/* Libera los modulos cargados por el enlace. */
void release_modules(void);

/* Primer hijo de 'n' de la clase pedida, o NULL. Util para recorrer el AST. */
Nodo *child_of(Nodo *n, TipoNodo kind);

#endif
