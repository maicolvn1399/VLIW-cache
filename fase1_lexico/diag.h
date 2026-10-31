#ifndef DIAG_H
#define DIAG_H

/* Helpers para reportar errores de manera uniforme en todas las fases. */
void diag_iniciar(const char *archivo);
/* Cambia el archivo asociado a los diagnosticos sin reiniciar sus contadores. */
void diag_archivo(const char *archivo);

/* Maximo de errores antes de abortar (--max-errors). Por omision 25. */
void diag_max_errores(int n);

/* Registra un error con linea, columna y una marca visual bajo el codigo. */
void diag_error(const char *codigo, int linea, int col, int largo,
                const char *fmt, ...);

/* Registra una advertencia (no impide generar codigo). */
void diag_advertencia(const char *codigo, int linea, int col, int largo,
                      const char *fmt, ...);

/*
 * Control de advertencias desde la linea de comandos.
 *
 * Todas las W0xx estan activas por omision, asi que -Wall las reafirma y
 * deshace cualquier -Wno-... anterior. -w las silencia todas y -Wno-W001
 * silencia una sola. -Werror hace que cada advertencia que si se emita
 * cuente como error y aborte la compilacion, que es lo que promete el
 * documento.
 */
void diag_warn_todas(void);                      /* -Wall */
void diag_warn_ninguna(void);                    /* -w */
int  diag_warn_desactivar(const char *codigo);   /* -Wno-W001; 0 si no existe */
void diag_warn_como_error(void);                 /* -Werror */

/* Cuantos errores se reportaron hasta ahora. */
int diag_errores(void);

/* Cuantas advertencias se reportaron hasta ahora. */
int diag_advertencias(void);

/* Muestra el resumen final si hubo fallos. */
void diag_resumen(void);

#endif
