#include <stdio.h>
#include <stdlib.h>
#include "ide.h"

/*
 * Lee un archivo completo a memoria y lo termina en '\0'. El IDE trabaja
 * siempre sobre el buffer, no sobre el descriptor, porque varias etapas
 * (tokenizar, contar columnas, extraer el prefijo bajo el cursor) lo recorren
 * mas de una vez.
 */
char *ide_leer_archivo(const char *ruta, size_t *largo) {
    FILE *f = fopen(ruta, "rb");
    char *buf;
    long n;
    size_t leidos;

    if (f == NULL) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    n = ftell(f);
    if (n < 0) { fclose(f); return NULL; }
    rewind(f);

    buf = malloc((size_t)n + 1);
    if (buf == NULL) { fclose(f); return NULL; }
    leidos = fread(buf, 1, (size_t)n, f);
    fclose(f);
    buf[leidos] = '\0';
    if (largo != NULL) *largo = leidos;
    return buf;
}
