#ifndef JSONW_H
#define JSONW_H

#include <stdio.h>

/*
 * Escritor de JSON minimo para la salida del IDE.
 *
 * No hay biblioteca externa: el proyecto no agrega dependencias y el formato
 * que necesita la interfaz es pequeno (objetos, arreglos, cadenas, enteros y
 * booleanos). El escritor lleva la cuenta de si ya hay un elemento en el nivel
 * actual para poner las comas solo donde corresponde, de modo que quien lo usa
 * nunca tiene que pensar en separadores.
 */

#define JSONW_MAX_NIVEL 32

typedef struct {
    FILE *salida;
    int   nivel;
    int   tiene_item[JSONW_MAX_NIVEL];
} JsonW;

void jw_iniciar(JsonW *j, FILE *salida);

void jw_obj_abrir(JsonW *j);
void jw_obj_cerrar(JsonW *j);
void jw_arr_abrir(JsonW *j);
void jw_arr_cerrar(JsonW *j);

/* Variantes con clave: se usan dentro de un objeto. */
void jw_clave_obj(JsonW *j, const char *clave);
void jw_clave_arr(JsonW *j, const char *clave);

void jw_cadena(JsonW *j, const char *clave, const char *valor);
void jw_entero(JsonW *j, const char *clave, long valor);
void jw_bool(JsonW *j, const char *clave, int valor);
void jw_nulo(JsonW *j, const char *clave);
void jw_real(JsonW *j, const char *clave, double valor);

/* Elementos sueltos dentro de un arreglo (sin clave). */
void jw_item_cadena(JsonW *j, const char *valor);
void jw_item_entero(JsonW *j, long valor);

#endif
