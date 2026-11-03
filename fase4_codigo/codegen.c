/*
 * Generacion de ensamblador VLIW para CERBERO.
 *
 * Todo lo que este archivo emite esta tomado de la especificacion del ISA:
 * los mnemonicos, el slot al que pertenece cada uno, los codigos de
 * condicion, la convencion de registros y las dos reglas temporales.
 *
 *   Registros (convencion acordada con CE 4301)
 *     R0, R1   par criptografico P0 (L y R de Feistel4)
 *     R2 - R5  pares P1 y P2, sin uso en esta version
 *     R6 - R9  argumentos 1 a 4; R6 lleva tambien el valor de retorno
 *     R10, R11 temporales del generador
 *     R12, R13 punteros, reservados por el llamado
 *     R14      puntero de pila, crece hacia abajo desde 0xFFFC
 *     R15      registro de enlace, lo escribe JAL
 *
 *   Reglas temporales
 *     - Tres bundles entre quien produce un valor y quien lo consume. El
 *       emisor lo lleva en una tabla y rellena con bundles vacios solo
 *       cuando hace falta, no a ciegas.
 *     - Un bundle de delay slot despues de cada salto, que se ejecuta
 *       siempre.
 *
 *   Marco de pila, de la direccion que apunta R14 hacia arriba
 *     [ 0                 .. 4k-4   ]  argumentos salientes a partir del 5
 *     [ 4k                .. +L-4   ]  parametros y locales (los ubico la fase 3)
 *     [ 4k+L              .. +4T-4  ]  temporales del TAC
 *     [ total-4                     ]  R15 guardado, si la funcion llama
 *
 *   Como R14 no se mueve dentro del cuerpo, todos los desplazamientos son
 *   constantes y los argumentos por pila quedan donde el llamado los espera.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <limits.h>
#include "codegen.h"
#include "diag.h"

/* --- Mapa que reserva el compilador dentro del segmento de globales ----
 * 0x0000-0x1FFF  variables globales (Nova no tiene globales mutables)
 * 0x2000-0x2FFF  literales de cadena
 * 0x3000         __out_n, cantidad de palabras escritas
 * 0x3004-0x3FFC  __out_buf, zona de salida que leen las herramientas de CE 4301
 */
/*
 * Region segura de IMEM. El controlador de boveda solo mantiene AUTH encendido
 * mientras el PC esta dentro de [SEC_BASE, SEC_LIMIT], y un LOGIN fuera de ese
 * rango no abre sesion y tampoco reporta falla: el programa cifraria con la
 * llave equivocada. Por eso toda funcion que toque la boveda se emite aqui.
 */
#define SEC_BASE_BUNDLE  (0x7000 / 16)      /* 1792 */
#define SEC_BUNDLES      (0x1000 / 16)      /* 256  */
/* IMEM de CERBERO: 32 KiB, o sea 2048 bundles de 16 bytes. */
#define IMEM_BUNDLES     (0x8000 / 16)      /* 2048 */

#define DIR_CADENAS   0x2000
#define DIR_OUT_N     0x3000
#define DIR_OUT_BUF   0x3004

#define R_ARG0   6     /* R6 */
#define R_RET    6
#define RA      10     /* temporal A */
#define RB      11     /* temporal B */
#define R_SP    14
#define R_LINK  15

#define S_ALU0 0
#define S_ALU1 1
#define S_LSU  2
#define S_CRP  3
#define S_BRU  4

#define IMM19_MAX  262143L
#define IMM19_MIN (-262144L)

/* Codigos de salida de los tres errores de ejecucion que define el documento.
 * No hay consola donde imprimir el mensaje, asi que lo que distingue cada
 * caso es el codigo que queda en R6 al detenerse. */
#define SAL_RANGO   134
#define SAL_DIV0    136
#define SAL_BOVEDA  137

/* --- Programa en memoria ------------------------------------------------
 * El generador no escribe directamente: arma la lista de bundles y la tabla
 * de etiquetas, y despues hay dos emisores sobre la misma lista, el de texto
 * y el binario. Asi no pueden divergir.
 */
typedef struct { char *s[5]; int source_line, source_col; } Bundle;
typedef struct { char *nombre; int bundle; int orden; } Etiq;
typedef struct { char *nombre; int direccion; } EtiqDato;

static Bundle *prog = NULL;
static int n_bundles = 0, cap_bundles = 0;
static Etiq *etqs = NULL;
static int n_etqs = 0, cap_etqs = 0;
static EtiqDato *etqs_dato = NULL;
static int n_etqs_dato = 0, cap_etqs_dato = 0;

/*
 * Imagen de la seccion de datos, con su direccion base. 'datos_init' marca
 * donde termina lo que de verdad trae un valor (los literales de cadena); de
 * ahi hasta 'datos_largo' todo es cero, asi que el ejecutable no lo carga:
 * solo le dice al cargador cuantos bytes tiene que limpiar.
 */
static unsigned char *datos = NULL;
static int datos_base = 0, datos_largo = 0, datos_cap = 0;
static int datos_init = 0;

/* Comentarios que se intercalan en la salida de texto, por bundle. */
typedef struct { int bundle; char *texto; int orden; } Nota;
static Nota *notas = NULL;
static int n_notas = 0, cap_notas = 0;
static int orden_global = 0;   /* para emitir notas y etiquetas como se registraron */

/* --- Estado del emisor ------------------------------------------------- */

static FILE *sal = NULL;
static long ciclo = 0;
static long listo[16];
static long listo_flags = 0;
static bool hubo_error = false;
static int linea_fuente_actual = 0, columna_fuente_actual = 0;

/* Estado de la funcion que se esta emitiendo */
static const char *func = NULL;
static int f_total = 0;        /* bytes del marco */
static int f_base_loc = 0;     /* 4k: donde empiezan parametros y locales */
static int f_marco_loc = 0;    /* L */
static int f_base_tmp = 0;     /* 4k + L */
static bool f_guarda_r15 = false;
static bool f_es_principale = false;
static bool etiqueta_cuerpo_emitida = false;

/* Temporales de la funcion, para asignarles una posicion en el marco */
#define MAX_TEMPS 512
static char *temps[MAX_TEMPS];
static int n_temps = 0;
static int temp_primero[MAX_TEMPS];
static int temp_ultimo[MAX_TEMPS];
static int temp_slot[MAX_TEMPS];
static int n_temp_slots = 0;

static TACList *lista = NULL;

/* Donde empieza el bloque seguro, o -1 si el programa no usa la boveda. */
static int inicio_seguro = -1;


/*
 * Relajacion de saltos.
 *
 * El desplazamiento del formato tipo C son 10 bits contados en bundles, o sea
 * 512 hacia cada lado. Emitiendo una instruccion por bundle, un programa de
 * tamano moderado pasa de ahi, y entonces una llamada a una funcion lejana no
 * cabe en el salto corto. Para esos casos el ISA tiene el tipo J, que salta a
 * la direccion que trae un registro:
 *
 *      movi r11, #&destino      ; direccion de la etiqueta, en bytes
 *      jalr.al r11              ; o jr.al r11 si era un salto y no una llamada
 *
 * Que sitios la necesitan no se sabe hasta conocer las posiciones finales, y
 * la forma larga ocupa mas bundles, asi que mueve las posiciones. Por eso el
 * programa se construye, se miran los saltos que quedaron fuera de rango, se
 * marcan y se vuelve a construir, hasta que ninguno se desborda. Cada llamada
 * a salto() es un sitio con numero propio, estable entre pasadas porque el
 * generador es determinista.
 */
static unsigned char *sitio_largo = NULL;   /* 1 si este sitio usa la forma larga */
static int *sitio_bundle = NULL;            /* en que bundle quedo el salto */
static int n_sitios = 0, cap_sitios = 0;

/*
 * Reuso del ultimo valor dejado en un registro. El TAC usa cada temporal una
 * sola vez y justo despues de calcularlo, asi que sin esto el generador
 * guarda en memoria y recarga la misma palabra en el bundle siguiente. No es
 * una optimizacion del programa: es seleccion de instrucciones, y se invalida
 * en cada etiqueta, salto y llamada, donde no se puede suponer nada.
 */
static int cache_reg = -1;
static const char *cache_nombre = NULL;

static void cache_limpiar(void) {
    cache_reg = -1;
    cache_nombre = NULL;
}

/* Soporte de ejecucion que hay que emitir al final */
static bool usa_div = false, usa_scribe_int = false;
static bool usa_scribe_txt = false, usa_dic = false;

/*
 * Que rutinas del soporte hace falta emitir. Se decide recorriendo el TAC
 * antes de emitir nada, porque el soporte va en el bloque no seguro y las
 * funciones que lo necesitan pueden estar en el seguro, que se emite despues.
 */
static void medir_soporte(TACList *tac) {
    for (TACInst *i = tac->head; i != NULL; i = i->next) {
        if (i->op == TAC_DIV || i->op == TAC_MOD) usa_div = true;
        if (i->op != TAC_CALL || i->arg1 == NULL) continue;
        if (strcmp(i->arg1, "__scribe_int") == 0) usa_scribe_int = true;
        else if (strcmp(i->arg1, "__scribe_txt") == 0) { usa_scribe_txt = true; usa_scribe_int = true; }
        else if (strcmp(i->arg1, "__dic_fin") == 0)    { usa_dic = true; usa_scribe_int = true; }
    }
}

/* --- Emision de bundles ------------------------------------------------ */

static char *dup_o_nulo(const char *s) {
    if (s == NULL) return NULL;
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memcpy(d, s, n);
    return d;
}

static void bundle(const char *s0, const char *s1, const char *s2,
                   const char *s3, const char *s4) {
    if (n_bundles == cap_bundles) {
        cap_bundles = cap_bundles ? cap_bundles * 2 : 256;
        prog = realloc(prog, (size_t)cap_bundles * sizeof(Bundle));
        if (prog == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    }
    Bundle *b = &prog[n_bundles++];
    b->source_line = linea_fuente_actual;
    b->source_col  = columna_fuente_actual;
    b->s[0] = dup_o_nulo(s0); b->s[1] = dup_o_nulo(s1);
    b->s[2] = dup_o_nulo(s2); b->s[3] = dup_o_nulo(s3);
    b->s[4] = dup_o_nulo(s4);
}

static void registrar_etiqueta(const char *nombre) {
    if (n_etqs == cap_etqs) {
        cap_etqs = cap_etqs ? cap_etqs * 2 : 128;
        etqs = realloc(etqs, (size_t)cap_etqs * sizeof(Etiq));
        if (etqs == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    }
    etqs[n_etqs].nombre = dup_o_nulo(nombre);
    etqs[n_etqs].bundle = n_bundles;
    etqs[n_etqs].orden = orden_global++;
    n_etqs++;
}

static void nota(const char *fmt, ...) {
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n_notas == cap_notas) {
        cap_notas = cap_notas ? cap_notas * 2 : 64;
        notas = realloc(notas, (size_t)cap_notas * sizeof(Nota));
        if (notas == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    }
    notas[n_notas].bundle = n_bundles;
    notas[n_notas].texto = dup_o_nulo(buf);
    notas[n_notas].orden = orden_global++;
    n_notas++;
}

/*
 * Copia de la tabla de etiquetas que sobrevive a liberar_todo().
 *
 * construir_programa() resuelve cada etiqueta a su bundle y liberar_todo()
 * borra esas estructuras enseguida, asi que sin esta copia la informacion se
 * pierde apenas termina la fase 4. Se toma antes de liberar para que --sym y
 * el IDE puedan mostrar los puntos de salto con su direccion.
 */
static CodegenEtiqueta *etq_copia = NULL;
static int n_etq_copia = 0;

static void liberar_copia_etiquetas(void) {
    for (int i = 0; i < n_etq_copia; i++) free((char *)etq_copia[i].nombre);
    free(etq_copia);
    etq_copia = NULL;
    n_etq_copia = 0;
}

static void guardar_etiquetas(void) {
    liberar_copia_etiquetas();
    int total = n_etqs + n_etqs_dato;
    if (total <= 0) return;

    etq_copia = malloc((size_t)total * sizeof(CodegenEtiqueta));
    if (etq_copia == NULL) return;          /* sin memoria: se queda sin tabla */

    for (int i = 0; i < n_etqs_dato; i++) {
        etq_copia[n_etq_copia].nombre    = dup_o_nulo(etqs_dato[i].nombre);
        etq_copia[n_etq_copia].direccion = (uint32_t)etqs_dato[i].direccion;
        etq_copia[n_etq_copia].bundle    = -1;
        etq_copia[n_etq_copia].es_dato   = 1;
        n_etq_copia++;
    }
    for (int i = 0; i < n_etqs; i++) {
        etq_copia[n_etq_copia].nombre    = dup_o_nulo(etqs[i].nombre);
        etq_copia[n_etq_copia].direccion = (uint32_t)etqs[i].bundle * 16u;
        etq_copia[n_etq_copia].bundle    = etqs[i].bundle;
        etq_copia[n_etq_copia].es_dato   = 0;
        n_etq_copia++;
    }
}

int codegen_etiquetas(const CodegenEtiqueta **out) {
    if (out != NULL) *out = etq_copia;
    return n_etq_copia;
}

static int buscar_etiqueta(const char *nombre) {
    for (int i = 0; i < n_etqs; i++)
        if (strcmp(etqs[i].nombre, nombre) == 0) return etqs[i].bundle;
    return -1;
}

static int buscar_etiqueta_dato(const char *nombre) {
    for (int i = 0; i < n_etqs_dato; i++)
        if (strcmp(etqs_dato[i].nombre, nombre) == 0) return etqs_dato[i].direccion;
    return -1;
}

static void vacio(void) { bundle(NULL, NULL, NULL, NULL, NULL); }

/* Rellena con bundles vacios hasta alcanzar el ciclo pedido. */
static void hasta(long c) {
    while (ciclo < c) { vacio(); ciclo++; }
}

/*
 * Emite una instruccion en su slot, esperando a que sus operandos esten
 * disponibles. rd es el registro que escribe (-1 si ninguno) y u1, u2 los
 * que lee.
 */
static void emitir(int slot, const char *texto, int rd, int u1, int u2) {
    long req = ciclo;
    if (u1 >= 0 && listo[u1] > req) req = listo[u1];
    if (u2 >= 0 && listo[u2] > req) req = listo[u2];
    hasta(req);

    const char *c[5] = {NULL, NULL, NULL, NULL, NULL};
    c[slot] = texto;
    bundle(c[0], c[1], c[2], c[3], c[4]);
    if (rd >= 0) {
        listo[rd] = ciclo + 3;
        if (rd == cache_reg) cache_limpiar();
    }
    ciclo++;
}

/* Espera a que no quede nada en vuelo. Se usa antes de cada salto y de cada
 * etiqueta, para que ningun valor a medio camino cruce un borde del flujo. */
static void barrera(void) {
    long m = ciclo;
    for (int i = 0; i < 16; i++) if (listo[i] > m) m = listo[i];
    if (listo_flags > m) m = listo_flags;
    hasta(m);
}

static void etiqueta(const char *nombre) {
    barrera();
    cache_limpiar();
    registrar_etiqueta(nombre);
    /* Tras una union de caminos no se puede suponer nada en vuelo. */
    for (int i = 0; i < 16; i++) listo[i] = ciclo;
    listo_flags = ciclo;
}

static void sitios_asegurar(int n) {
    if (n <= cap_sitios) return;
    int nuevo = cap_sitios ? cap_sitios * 2 : 256;
    while (nuevo < n) nuevo *= 2;
    sitio_largo = realloc(sitio_largo, (size_t)nuevo);
    sitio_bundle = realloc(sitio_bundle, (size_t)nuevo * sizeof(int));
    if (sitio_largo == NULL || sitio_bundle == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }
    memset(sitio_largo + cap_sitios, 0, (size_t)(nuevo - cap_sitios));
    cap_sitios = nuevo;
}

/*
 * Si el texto es un salto incondicional a una etiqueta, deja el nombre en
 * 'etq' y devuelve 1 para jal.al y 0 para br.al. Devuelve -1 para cualquier
 * otra cosa: condicionales, jr, jalr y halt no tienen forma larga.
 */
static int salto_incondicional(const char *texto, char *etq, size_t cap) {
    char fmt_jal[32], fmt_br[32];
    snprintf(fmt_jal, sizeof(fmt_jal), "jal.al %%%zus", cap - 1);
    snprintf(fmt_br, sizeof(fmt_br), "br.al %%%zus", cap - 1);
    if (sscanf(texto, fmt_jal, etq) == 1) return 1;
    if (sscanf(texto, fmt_br, etq) == 1) return 0;
    return -1;
}

/* Salto: ocupa el slot S4 y arrastra su delay slot, que siempre se ejecuta. */
static void salto(const char *texto, int usa_reg) {
    barrera();
    cache_limpiar();
    (void)usa_reg;

    int sitio = n_sitios++;
    sitios_asegurar(n_sitios);

    char etq[64], largo[96];
    int es_jal = salto_incondicional(texto, etq, sizeof(etq));

    if (es_jal >= 0 && sitio_largo[sitio]) {
        /* Forma larga: la direccion de la etiqueta a un registro, y tipo J. */
        char t[96];
        snprintf(t, sizeof(t), "movi r%d, #&%s", RB, etq);
        bundle(t, NULL, NULL, NULL, NULL);
        ciclo++;
        listo[RB] = ciclo + 2;
        barrera();                  /* paga la latencia antes de usar r11 */
        snprintf(largo, sizeof(largo), "%s r%d", es_jal ? "jalr.al" : "jr.al", RB);
        texto = largo;
    }

    sitio_bundle[sitio] = n_bundles;    /* el bundle que llevara el salto */
    bundle(NULL, NULL, NULL, NULL, texto);
    ciclo++;
    vacio();            /* delay slot */
    ciclo++;
}

/* Comparacion: solo S0 escribe banderas. */
static void cmp_reg(int a, int b) {
    char t[48];
    snprintf(t, sizeof(t), "cmp r%d, r%d", a, b);
    long req = ciclo;
    if (listo[a] > req) req = listo[a];
    if (listo[b] > req) req = listo[b];
    hasta(req);
    bundle(t, NULL, NULL, NULL, NULL);
    ciclo++;
    listo_flags = ciclo + 2;
}

static void cmp_inm(int a, long v) {
    char t[48];
    snprintf(t, sizeof(t), "cmpi r%d, #%ld", a, v);
    long req = ciclo;
    if (listo[a] > req) req = listo[a];
    hasta(req);
    bundle(t, NULL, NULL, NULL, NULL);
    ciclo++;
    listo_flags = ciclo + 2;
}

/* Operaciones de uso frecuente, con su dependencia ya declarada. */
static void alu3(const char *op, int rd, int rs1, int rs2) {
    char t[64];
    snprintf(t, sizeof(t), "%s r%d, r%d, r%d", op, rd, rs1, rs2);
    emitir(S_ALU0, t, rd, rs1, rs2);
}

static void alu_inm(const char *op, int rd, int rs1, long v) {
    char t[64];
    snprintf(t, sizeof(t), "%s r%d, r%d, #%ld", op, rd, rs1, v);
    emitir(S_ALU0, t, rd, rs1, -1);
}

static void mover(int rd, int rs) {
    char t[32];
    snprintf(t, sizeof(t), "mov r%d, r%d", rd, rs);
    emitir(S_ALU0, t, rd, rs, -1);
}

/* Carga de una constante. imm19 es con signo; si no cabe hay que construir
 * el valor con MOVI y luego MOVH, en ese orden obligatorio. */
static void cargar_const(int rd, long v) {
    char t[64];
    if (v >= IMM19_MIN && v <= IMM19_MAX) {
        snprintf(t, sizeof(t), "movi r%d, #%ld", rd, v);
        emitir(S_ALU0, t, rd, -1, -1);
        return;
    }
    /*
     * Constante de 32 bits en dos instrucciones. MOVH no es del tipo I: es del
     * tipo U, reemplaza los 16 bits altos de rd y conserva los 16 bajos
     * (alu.sv: movh_w = {imm16, op_a_i[15:0]}). Por eso el corte es 16 y 16,
     * no 19 y 13, y por eso el orden obligatorio es MOVI y despues MOVH.
     *
     * La mitad baja va por MOVI, que extiende el signo de sus 19 bits; da lo
     * mismo que extienda, porque MOVH sobrescribe justo esa parte despues.
     */
    unsigned long u = (unsigned long)v & 0xFFFFFFFFUL;
    long lo = (long)(u & 0xFFFFUL);
    long hi = (long)((u >> 16) & 0xFFFFUL);
    snprintf(t, sizeof(t), "movi r%d, #%ld", rd, lo);
    emitir(S_ALU0, t, rd, -1, -1);
    snprintf(t, sizeof(t), "movh r%d, #%ld", rd, hi);
    emitir(S_ALU0, t, rd, rd, -1);
}

/*
 * Direccion de un literal de cadena. Se resuelve aqui a su valor numerico, no
 * se deja el nombre de la etiqueta: el ensamblador de CERBERO solo acepta
 * numeros en los inmediatos, y las direcciones de la seccion de datos ya se
 * conocen porque las asigno construir_datos().
 */
static void cargar_etiqueta(int rd, const char *etq) {
    int dir = buscar_etiqueta_dato(etq);
    if (dir < 0) {
        diag_error("E410", 0, 1, 1, "literal de cadena '%s' no ubicado", etq);
        hubo_error = true;
        dir = 0;
    }
    cargar_const(rd, dir);
}

static void lw(int rd, int rbase, int disp) {
    char t[64];
    snprintf(t, sizeof(t), "lw r%d, #%d(r%d)", rd, disp, rbase);
    emitir(S_LSU, t, rd, rbase, -1);
}

static void sw(int rdato, int rbase, int disp) {
    char t[64];
    snprintf(t, sizeof(t), "sw r%d, #%d(r%d)", rdato, disp, rbase);
    emitir(S_LSU, t, -1, rdato, rbase);
}

static void mover(int rd, int rs);

/* --- Resolucion de operandos ------------------------------------------ */

static int indice_temp(const char *nombre) {
    for (int i = 0; i < n_temps; i++)
        if (strcmp(temps[i], nombre) == 0) return i;
    if (n_temps < MAX_TEMPS) {
        int indice = n_temps++;
        temps[indice] = (char *)nombre;
        temp_primero[indice] = INT_MAX;
        temp_ultimo[indice] = -1;
        temp_slot[indice] = -1;
        return indice;
    }
    return 0;
}

static int desplazamiento_simbolo(const TACSimbolo *simbolo) {
    if (simbolo == NULL) return -1;
    return f_base_loc + f_marco_loc + simbolo->offset;
}

/* Desplazamiento del operando respecto de R14, o -1 si no es un dato. */
static int disp_de(const char *nombre) {
    if (nombre == NULL) return -1;
    if (tac_es_temporal(nombre)) {
        int indice = indice_temp(nombre);
        if (temp_slot[indice] < 0) return -1;
        return f_base_tmp + 4 * temp_slot[indice];
    }
    const TACSimbolo *s = tac_buscar_simbolo(lista, func, nombre);
    if (s == NULL) return -1;
    return desplazamiento_simbolo(s);
}

static const TACSimbolo *sim_de(const char *nombre) {
    return tac_buscar_simbolo(lista, func, nombre);
}

/* Carga el valor del operando en un registro. */
static void cargar(int rd, const char *nombre) {
    /* Si el valor ya esta en un registro, no hace falta volver a leerlo. */
    if (cache_nombre != NULL && nombre != NULL &&
        strcmp(cache_nombre, nombre) == 0) {
        if (cache_reg == rd) return;
        mover(rd, cache_reg);
        return;
    }
    int d = disp_de(nombre);
    if (d < 0) {
        diag_error("E410", 0, 1, 1, "la fase 4 no pudo ubicar '%s' en '%s'",
                   nombre ? nombre : "(nulo)", func ? func : "?");
        hubo_error = true;
        cargar_const(rd, 0);
        return;
    }
    lw(rd, R_SP, d);
}

static void guardar(int rfuente, const char *nombre) {
    int d = disp_de(nombre);
    if (d < 0) {
        diag_error("E410", 0, 1, 1, "la fase 4 no pudo ubicar '%s' en '%s'",
                   nombre ? nombre : "(nulo)", func ? func : "?");
        hubo_error = true;
        return;
    }
    sw(rfuente, R_SP, d);
    /* Este registro queda con el valor de este nombre. */
    cache_reg = rfuente;
    cache_nombre = nombre;
}

/*
 * Deja en rd la direccion base de un arreglo. Si es local, su espacio esta
 * en el marco y la direccion es R14 mas el desplazamiento. Si es un
 * parametro, lo que hay en su hueco es el descriptor, cuya primera palabra
 * es la direccion base: el arreglo viaja por referencia.
 */
static void direccion_base(int rd, const char *nombre) {
    const TACSimbolo *s = sim_de(nombre);
    int d = disp_de(nombre);
    if (d < 0) {
        diag_error("E410", 0, 1, 1, "arreglo '%s' no ubicado", nombre ? nombre : "?");
        hubo_error = true;
        cargar_const(rd, 0);
        return;
    }
    if (s != NULL && s->es_param && s->dims > 0) lw(rd, R_SP, d);
    else alu_inm("addi", rd, R_SP, d);
}

/* --- Traduccion de cada operacion del TAC ----------------------------- */

static const char *cond_de(TACOp op, bool *invertir_operandos) {
    *invertir_operandos = false;
    switch (op) {
        case TAC_EQ: return "eq";
        case TAC_NE: return "ne";
        case TAC_LT: return "lt";
        case TAC_GE: return "ge";
        /* El ISA no tiene LE ni GT: se obtienen intercambiando operandos. */
        case TAC_LE: *invertir_operandos = true; return "ge";
        case TAC_GT: *invertir_operandos = true; return "lt";
        default: return "al";
    }
}

/* Materializa una comparacion en 0 o 1. */
static void emitir_comparacion(TACInst *i) {
    bool inv;
    const char *c = cond_de(i->op, &inv);
    cargar(RA, i->arg1);
    cargar(RB, i->arg2);
    if (inv) cmp_reg(RB, RA); else cmp_reg(RA, RB);

    char l_si[32], l_fin[32];
    static int n = 0;
    snprintf(l_si, sizeof(l_si), "__c%d_si", n);
    snprintf(l_fin, sizeof(l_fin), "__c%d_fin", n);
    n++;

    char br[48];
    snprintf(br, sizeof(br), "br.%s %s", c, l_si);
    hasta(listo_flags);
    salto(br, -1);
    cargar_const(RA, 0);
    char j[48];
    snprintf(j, sizeof(j), "br.al %s", l_fin);
    salto(j, -1);
    etiqueta(l_si);
    cargar_const(RA, 1);
    etiqueta(l_fin);
    guardar(RA, i->result);
}

/* Acceso indexado: direccion = base + indice*4. */
static void emitir_direccion_elemento(const char *base, const char *idx) {
    cargar(RA, idx);
    alu_inm("slli", RA, RA, 2);
    direccion_base(RB, base);
    alu3("add", RB, RB, RA);
}

static void emitir_prologo(void);
static void emitir_epilogo(void);
static void copiar_params_a_marco(bool desde_area_salida);

/*
 * Las operaciones de la boveda exigen AUTH = 1. El ISA anula el slot y
 * registra DENIED, pero el documento promete un error de ejecucion con
 * codigo 137, asi que se comprueba antes de cada una.
 */
static void guardia_boveda(void) {
    static int n = 0;
    char l_ok[32], buf[64];
    snprintf(l_ok, sizeof(l_ok), "__auth%d_ok", n++);
    barrera();
    snprintf(buf, sizeof(buf), "br.auth %s", l_ok);
    salto(buf, -1);
    cargar_const(R_RET, SAL_BOVEDA);
    barrera();
    salto("halt", -1);
    etiqueta(l_ok);
}

static void emitir_inst(TACInst *i) {
    char buf[96];

    switch (i->op) {
        case TAC_NOP:
            break;

        case TAC_CONST:
            cargar_const(RA, i->valor);
            guardar(RA, i->result);
            break;

        case TAC_STR:
            cargar_etiqueta(RA, i->arg1);
            guardar(RA, i->result);
            break;

        case TAC_ASSIGN:
            cargar(RA, i->arg1);
            guardar(RA, i->result);
            break;

        case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR:  case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR: {
            const char *op = "add";
            switch (i->op) {
                case TAC_ADD: op = "add"; break;
                case TAC_SUB: op = "sub"; break;
                case TAC_MUL: op = "mul"; break;
                case TAC_AND: op = "and"; break;
                case TAC_OR:  op = "or";  break;
                case TAC_XOR: op = "xor"; break;
                case TAC_SHL: op = "sll"; break;
                case TAC_SHR: op = "sra"; break;   /* >>  aritmetico */
                case TAC_USHR: op = "srl"; break;  /* >>> logico     */
                default: break;
            }
            cargar(RA, i->arg1);
            cargar(RB, i->arg2);
            alu3(op, RA, RA, RB);
            guardar(RA, i->result);
            break;
        }

        case TAC_DIV: case TAC_MOD:
            /* CERBERO no tiene division: se resuelve con una subrutina del
             * soporte de ejecucion, que deja el cociente en R6 y el resto
             * en R7. */
            usa_div = true;
            cargar(R_ARG0, i->arg1);
            cargar(R_ARG0 + 1, i->arg2);
            salto("jal.al __nova_div32", -1);
            for (int r = 0; r < 16; r++) listo[r] = ciclo;
            guardar(i->op == TAC_DIV ? R_ARG0 : R_ARG0 + 1, i->result);
            break;

        case TAC_EQ: case TAC_NE: case TAC_LT:
        case TAC_LE: case TAC_GT: case TAC_GE:
            emitir_comparacion(i);
            break;

        case TAC_NEG:
            cargar(RA, i->arg1);
            snprintf(buf, sizeof(buf), "neg r%d, r%d", RA, RA);
            emitir(S_ALU0, buf, RA, RA, -1);
            guardar(RA, i->result);
            break;

        case TAC_BITNOT:
            cargar(RA, i->arg1);
            snprintf(buf, sizeof(buf), "not r%d, r%d", RA, RA);
            emitir(S_ALU0, buf, RA, RA, -1);
            guardar(RA, i->result);
            break;

        case TAC_NOT: {
            /* non a  es  (a == 0) */
            cargar(RA, i->arg1);
            cmp_inm(RA, 0);
            static int n = 0;
            char l_si[32], l_fin[32];
            snprintf(l_si, sizeof(l_si), "__n%d_si", n);
            snprintf(l_fin, sizeof(l_fin), "__n%d_fin", n);
            n++;
            snprintf(buf, sizeof(buf), "br.eq %s", l_si);
            hasta(listo_flags);
            salto(buf, -1);
            cargar_const(RA, 0);
            snprintf(buf, sizeof(buf), "br.al %s", l_fin);
            salto(buf, -1);
            etiqueta(l_si);
            cargar_const(RA, 1);
            etiqueta(l_fin);
            guardar(RA, i->result);
            break;
        }

        case TAC_LOAD:
            emitir_direccion_elemento(i->arg1, i->arg2);
            lw(RA, RB, 0);
            guardar(RA, i->result);
            break;

        case TAC_STORE:
            emitir_direccion_elemento(i->result, i->arg1);
            cargar(RA, i->arg2);
            sw(RA, RB, 0);
            break;

        case TAC_ADDR:
            direccion_base(RA, i->arg1);
            guardar(RA, i->result);
            break;

        case TAC_LEN: {
            const TACSimbolo *s = sim_de(i->arg1);
            if (s != NULL && s->es_param && s->dims > 0) {
                /* El descriptor lleva un tamano por dimension. */
                int d = disp_de(i->arg1);
                lw(RA, R_SP, d + 4 * (1 + i->aux));
            } else if (s != NULL && s->dims > 0) {
                cargar_const(RA, i->aux == 0 ? s->filas : s->cols);
            } else {
                /* textus: la primera palabra del literal es su longitud. */
                cargar(RB, i->arg1);
                lw(RA, RB, 0);
            }
            guardar(RA, i->result);
            break;
        }

        case TAC_CHECK: {
            /* La comparacion sin signo atrapa tambien los indices negativos:
             * como entero sin signo quedan por encima del limite. */
            static int n = 0;
            char l_ok[32];
            snprintf(l_ok, sizeof(l_ok), "__rango%d_ok", n++);
            cargar(RA, i->arg1);
            cargar(RB, i->arg2);
            cmp_reg(RA, RB);
            snprintf(buf, sizeof(buf), "br.ltu %s", l_ok);
            hasta(listo_flags);
            salto(buf, -1);
            /* Fuera de rango: el documento define el codigo de salida 134. */
            cargar_const(R_RET, SAL_RANGO);
            barrera();
            salto("halt", -1);
            etiqueta(l_ok);
            break;
        }

        case TAC_LABEL:
            etiqueta(i->result);
            break;

        case TAC_GOTO:
            snprintf(buf, sizeof(buf), "br.al %s", i->result);
            salto(buf, -1);
            break;

        case TAC_IF_FALSE:
            cargar(RA, i->arg1);
            cmp_inm(RA, 0);
            snprintf(buf, sizeof(buf), "br.eq %s", i->result);
            hasta(listo_flags);
            salto(buf, -1);
            break;

        case TAC_IF_TRUE:
            if (i->arg1 != NULL && strcmp(i->arg1, "__auth") == 0) {
                /* La bandera AUTH de la boveda tiene su propia condicion. */
                hasta(listo_flags);
                snprintf(buf, sizeof(buf), "br.auth %s", i->result);
                salto(buf, -1);
            } else {
                cargar(RA, i->arg1);
                cmp_inm(RA, 0);
                snprintf(buf, sizeof(buf), "br.ne %s", i->result);
                hasta(listo_flags);
                salto(buf, -1);
            }
            break;

        case TAC_PARAM:
            if (i->aux <= 4) {
                cargar(R_ARG0 + (i->aux - 1), i->arg1);
            } else {
                /* Los argumentos a partir del quinto van al area de salida
                 * del marco, que es donde el llamado los espera. */
                cargar(RA, i->arg1);
                sw(RA, R_SP, 4 * (i->aux - 5));
            }
            break;

        case TAC_CALL: {
            if (i->arg1 != NULL) {
                if (strcmp(i->arg1, "__scribe_int") == 0) usa_scribe_int = true;
                else if (strcmp(i->arg1, "__scribe_txt") == 0) {
                    usa_scribe_txt = true;
                    usa_scribe_int = true;
                } else if (strcmp(i->arg1, "__dic_fin") == 0) {
                    usa_dic = true;
                    usa_scribe_int = true;
                }
            }
            snprintf(buf, sizeof(buf), "jal.al %s", i->arg1 ? i->arg1 : "?");
            salto(buf, -1);
            /* Tras la llamada no se puede suponer nada de los registros. */
            for (int r = 0; r < 16; r++) listo[r] = ciclo;
            listo_flags = ciclo;
            if (i->result != NULL) guardar(R_RET, i->result);
            break;
        }

        case TAC_TAILCALL:
            /*
             * @cauda: los argumentos ya estan en R6-R9 y en el area de
             * salida. Se reasignan sobre los parametros y se vuelve al
             * inicio del cuerpo, sin apilar un marco nuevo ni gastar R15.
             */
            copiar_params_a_marco(true);
            barrera();
            snprintf(buf, sizeof(buf), "br.al __%s_cuerpo", func);
            salto(buf, -1);
            break;

        case TAC_RET_VAL:
            cargar(R_RET, i->arg1);
            emitir_epilogo();
            break;

        case TAC_RET:
            emitir_epilogo();
            break;

        case TAC_AUTHW:
            cargar(RA, i->arg1);
            snprintf(buf, sizeof(buf), "authw #%d, r%d", i->aux, RA);
            emitir(S_CRP, buf, -1, RA, -1);
            break;

        case TAC_VAULT_LOGIN:
            emitir(S_CRP, "login", -1, -1, -1);
            listo_flags = ciclo + 2;
            break;

        case TAC_VAULT_LOGOUT:
            emitir(S_CRP, "logout", -1, -1, -1);
            break;

        case TAC_KSETW:
            guardia_boveda();
            cargar(RA, i->arg2);
            snprintf(buf, sizeof(buf), "ksetw k%ld, #%d, r%d", i->valor, i->aux, RA);
            emitir(S_CRP, buf, -1, RA, -1);
            break;

        case TAC_FEISTEL:
        case TAC_FEISTEL_DECRYPT:
            guardia_boveda();
            /* Las rondas operan sobre el par P0 = R0:R1, con L en el par y R
             * en el impar. Se cargan, se ejecuta la ronda y se devuelven al
             * arreglo, porque la instruccion reescribe los mismos registros. */
            cargar(RB, i->arg1);
            lw(0, RB, 0);
            lw(1, RB, 4);
            snprintf(buf, sizeof(buf), "%s p0, k%ld, #%d",
                     i->op == TAC_FEISTEL ? "f4e" : "f4d",
                     i->valor, i->aux);
            emitir(S_CRP, buf, 0, 0, 1);
            listo[1] = listo[0];
            sw(0, RB, 0);
            sw(1, RB, 4);
            break;

        case TAC_HALT:
            salto("halt", -1);
            break;

        case TAC_FUNC_BEGIN:
        case TAC_FUNC_END:
            break;   /* los maneja el recorrido por funciones */

        default:
            diag_error("E410", i->linea, 1, 1,
                       "la fase 4 no sabe traducir la operacion %d del TAC", i->op);
            hubo_error = true;
            break;
    }
}

/* --- Prologo y epilogo ------------------------------------------------- */

/*
 * Copia los parametros a su hueco del marco. Los cuatro primeros llegan en
 * R6-R9; del quinto en adelante llegan por pila, y de donde se leen depende
 * de quien llama:
 *
 *   - En el prologo vienen del marco del llamador, que esta por encima del
 *     nuestro: en #(total + 4*(pos-5))(r14).
 *   - En la vuelta de @cauda los acabamos de escribir nosotros mismos, en
 *     nuestra propia area de argumentos salientes: en #(4*(pos-5))(r14).
 *
 * El area de salida y los huecos de los parametros no se solapan, asi que la
 * copia es segura en los dos casos.
 */
static void copiar_params_a_marco(bool desde_area_salida) {
    for (const TACSimbolo *s = lista->simbolos; s != NULL; s = s->next) {
        if (!s->es_param) continue;
        if (s->funcion == NULL || strcmp(s->funcion, func) != 0) continue;
        int palabras = s->size_bytes / 4;
        if (palabras < 1) palabras = 1;
        int destino = f_base_loc + f_marco_loc + s->offset;
        for (int w = 0; w < palabras; w++) {
            int pos = s->posicion + w;
            if (pos <= 4) {
                sw(R_ARG0 + (pos - 1), R_SP, destino + 4 * w);
            } else {
                int origen = desde_area_salida ? 4 * (pos - 5)
                                               : f_total + 4 * (pos - 5);
                lw(RA, R_SP, origen);
                sw(RA, R_SP, destino + 4 * w);
            }
        }
    }
}

static void emitir_prologo(void) {
    if (f_guarda_r15) nota("marco de %d bytes, guarda R15 en #%d(r14)",
                           f_total, f_total - 4);
    else              nota("marco de %d bytes", f_total);

    alu_inm("subi", R_SP, R_SP, f_total);
    if (f_guarda_r15) sw(R_LINK, R_SP, f_total - 4);

    /* Los parametros llegan en R6-R9 y por pila a partir del quinto. Se
     * copian a su hueco del marco para dejar libres los registros. */
    copiar_params_a_marco(false);

    /* Punto al que vuelve la recursion de cola: ya con el marco armado, pero
     * antes de la primera sentencia del cuerpo. */
    etiqueta_cuerpo_emitida = true;
    char etq[160];
    snprintf(etq, sizeof(etq), "__%s_cuerpo", func);
    barrera();
    registrar_etiqueta(etq);
}

static void emitir_epilogo(void) {
    if (f_es_principale) {
        /* principale es el punto de entrada: su retorno termina el programa.
         * El valor queda en R6 como codigo de salida. */
        salto("halt", -1);
        return;
    }
    if (f_guarda_r15) lw(R_LINK, R_SP, f_total - 4);
    alu_inm("addi", R_SP, R_SP, f_total);
    barrera();
    salto("jr.al r15", R_LINK);
}

/* --- Soporte de ejecucion --------------------------------------------- */

/*
 * Division con signo de Nova.
 *
 * Se llama __nova_div32 y no __div32 a proposito: CERBERO entrega su propia
 * __div32 en tools/programas/div32.s, y las dos rutinas tienen contratos
 * distintos. La de ellos trabaja sin signo, destruye R1 a R5 y con divisor
 * cero devuelve cociente en unos sin fallar. La de Nova trabaja con signo,
 * porque 'integer' lo tiene, y termina con el codigo 136 si el divisor es
 * cero, porque es lo que promete el lenguaje. Con nombres distintos las dos
 * pueden convivir en el mismo programa enlazado.
 */
static void emitir_div32(void) {
    nota("__nova_div32(R6 = a, R7 = b) -> R6 = a/b, R7 = a%%b, con signo");
    registrar_etiqueta("__nova_div32");
    ciclo = 0;
    for (int i = 0; i < 16; i++) listo[i] = 0;
    cache_limpiar();

    /* Divisor en cero: el documento define el codigo de salida 136. */
    cmp_inm(7, 0);
    hasta(listo_flags);
    salto("br.ne __dv_ok", -1);
    cargar_const(R_RET, SAL_DIV0);
    barrera();
    salto("halt", -1);
    etiqueta("__dv_ok");

    alu_inm("subi", R_SP, R_SP, 8);
    /* [0] signo del cociente, [4] signo del resto */
    cargar_const(RA, 0);
    sw(RA, R_SP, 0);
    sw(RA, R_SP, 4);

    cmp_inm(6, 0);
    hasta(listo_flags);
    salto("br.ge __dv_a_pos", -1);
    cargar_const(RA, 0);
    alu3("sub", 6, RA, 6);
    cargar_const(RA, 1);
    sw(RA, R_SP, 0);
    sw(RA, R_SP, 4);
    etiqueta("__dv_a_pos");

    cmp_inm(7, 0);
    hasta(listo_flags);
    salto("br.ge __dv_b_pos", -1);
    cargar_const(RA, 0);
    alu3("sub", 7, RA, 7);
    lw(RA, R_SP, 0);
    alu_inm("xori", RA, RA, 1);
    sw(RA, R_SP, 0);
    etiqueta("__dv_b_pos");

    cargar_const(8, 0);     /* cociente */
    cargar_const(9, 0);     /* resto    */
    cargar_const(10, 31);   /* contador */
    etiqueta("__dv_bucle");
    alu3("srl", RB, 6, 10);
    alu_inm("andi", RB, RB, 1);
    alu_inm("slli", 9, 9, 1);
    alu3("or", 9, 9, RB);
    cmp_reg(9, 7);
    hasta(listo_flags);
    salto("br.ltu __dv_sigue", -1);
    alu3("sub", 9, 9, 7);
    cargar_const(RB, 1);
    alu3("sll", RB, RB, 10);
    alu3("or", 8, 8, RB);
    etiqueta("__dv_sigue");
    alu_inm("subi", 10, 10, 1);
    cmp_inm(10, 0);
    hasta(listo_flags);
    salto("br.ge __dv_bucle", -1);

    /* Signos */
    mover(6, 8);
    mover(7, 9);
    lw(RA, R_SP, 0);
    cmp_inm(RA, 0);
    hasta(listo_flags);
    salto("br.eq __dv_c_pos", -1);
    cargar_const(RB, 0);
    alu3("sub", 6, RB, 6);
    etiqueta("__dv_c_pos");
    lw(RA, R_SP, 4);
    cmp_inm(RA, 0);
    hasta(listo_flags);
    salto("br.eq __dv_r_pos", -1);
    cargar_const(RB, 0);
    alu3("sub", 7, RB, 7);
    etiqueta("__dv_r_pos");

    alu_inm("addi", R_SP, R_SP, 8);
    barrera();
    salto("jr.al r15", R_LINK);
}

static void emitir_scribe_int(void) {
    nota("__scribe_int(R6 = valor): el ISA no define puertos de E/S, los "
         "resultados se dejan en memoria para las herramientas de CE 4301");
    registrar_etiqueta("__scribe_int");
    ciclo = 0;
    for (int i = 0; i < 16; i++) listo[i] = 0;
    cache_limpiar();

    cargar_const(RA, DIR_OUT_N);
    lw(RB, RA, 0);
    alu_inm("slli", RB, RB, 2);
    alu_inm("addi", RB, RB, 4);
    alu3("add", RB, RA, RB);
    sw(6, RB, 0);
    lw(RB, RA, 0);
    alu_inm("addi", RB, RB, 1);
    sw(RB, RA, 0);
    barrera();
    salto("jr.al r15", R_LINK);
}

static void emitir_scribe_txt(void) {
    nota("__scribe_txt(R6 = direccion): escribe la longitud y las palabras");
    registrar_etiqueta("__scribe_txt");
    ciclo = 0;
    for (int i = 0; i < 16; i++) listo[i] = 0;
    cache_limpiar();

    alu_inm("subi", R_SP, R_SP, 4);
    sw(R_LINK, R_SP, 0);
    lw(7, 6, 0);              /* longitud en bytes */
    mover(9, 6);              /* puntero */
    mover(6, 7);
    salto("jal.al __scribe_int", -1);
    for (int i = 0; i < 16; i++) listo[i] = ciclo;
    alu_inm("addi", 9, 9, 4);
    alu_inm("addi", 8, 7, 3);
    alu_inm("srli", 8, 8, 2);  /* palabras de datos */

    etiqueta("__txt_bucle");
    cmp_inm(8, 0);
    hasta(listo_flags);
    salto("br.eq __txt_fin", -1);
    lw(6, 9, 0);
    salto("jal.al __scribe_int", -1);
    for (int i = 0; i < 16; i++) listo[i] = ciclo;
    alu_inm("addi", 9, 9, 4);
    alu_inm("subi", 8, 8, 1);
    salto("br.al __txt_bucle", -1);
    etiqueta("__txt_fin");

    lw(R_LINK, R_SP, 0);
    alu_inm("addi", R_SP, R_SP, 4);
    barrera();
    salto("jr.al r15", R_LINK);
}

static void emitir_dic_fin(void) {
    nota("__dic_fin(): marca el fin de linea de 'dic' con 0x0A");
    registrar_etiqueta("__dic_fin");
    ciclo = 0;
    for (int i = 0; i < 16; i++) listo[i] = 0;
    cache_limpiar();
    cargar_const(6, 10);
    barrera();
    /* Salto y no llamada: el retorno de __scribe_int vuelve a nuestro llamador. */
    salto("br.al __scribe_int", -1);
}

/* --- Seccion de datos ------------------------------------------------- */

/*
 * La seccion de datos se arma como imagen de bytes, con su direccion base.
 * El emisor de texto la vuelca como directivas y el binario la copia tal
 * cual, asi que las dos salidas describen la misma memoria.
 */
static void datos_asegurar(int hasta_byte) {
    if (hasta_byte <= datos_cap) return;
    int nuevo_cap = datos_cap ? datos_cap : 256;
    while (nuevo_cap < hasta_byte) nuevo_cap *= 2;
    datos = realloc(datos, (size_t)nuevo_cap);
    if (datos == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memset(datos + datos_cap, 0, (size_t)(nuevo_cap - datos_cap));
    datos_cap = nuevo_cap;
}

static void datos_palabra(int32_t v) {
    datos_asegurar(datos_largo + 4);
    datos[datos_largo + 0] = (unsigned char)(v & 0xFF);
    datos[datos_largo + 1] = (unsigned char)((v >> 8) & 0xFF);
    datos[datos_largo + 2] = (unsigned char)((v >> 16) & 0xFF);
    datos[datos_largo + 3] = (unsigned char)((v >> 24) & 0xFF);
    datos_largo += 4;
}

static void datos_bytes(const char *b, int n) {
    datos_asegurar(datos_largo + n);
    memcpy(datos + datos_largo, b, (size_t)n);
    datos_largo += n;
}

static void datos_alinear(int a) {
    while (datos_largo % a) { datos_asegurar(datos_largo + 1); datos_largo++; }
}

static void registrar_etiqueta_dato(const char *nombre, int direccion) {
    if (n_etqs_dato == cap_etqs_dato) {
        cap_etqs_dato = cap_etqs_dato ? cap_etqs_dato * 2 : 32;
        etqs_dato = realloc(etqs_dato, (size_t)cap_etqs_dato * sizeof(EtiqDato));
        if (etqs_dato == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    }
    etqs_dato[n_etqs_dato].nombre = dup_o_nulo(nombre);
    etqs_dato[n_etqs_dato].direccion = direccion;
    n_etqs_dato++;
}

static void construir_datos(TACList *tac) {
    datos_base = DIR_CADENAS;
    datos_largo = 0;

    for (TACCadena *c = tac->cadenas; c != NULL; c = c->next) {
        datos_alinear(4);
        registrar_etiqueta_dato(c->etiqueta, datos_base + datos_largo);
        int n = (int)strlen(c->texto);
        datos_palabra(n);
        datos_bytes(c->texto, n);
    }

    /* Aqui termina lo inicializado: lo que sigue son huecos y buffers. */
    datos_alinear(4);
    datos_init = datos_largo;

    /* Hasta la zona de salida, que empieza en una direccion fija. */
    int hasta = DIR_OUT_N - datos_base;
    datos_asegurar(hasta);
    if (datos_largo < hasta) datos_largo = hasta;
    registrar_etiqueta_dato("__out_n", DIR_OUT_N);
    datos_palabra(0);
    registrar_etiqueta_dato("__out_buf", DIR_OUT_BUF);
    int buf = 0x4000 - DIR_OUT_BUF;
    datos_asegurar(datos_largo + buf);
    datos_largo += buf;
}

/* --- Emisor de texto --------------------------------------------------- */

static void imprimir_datos_texto(TACList *tac) {
    fprintf(sal, ".data\n");
    fprintf(sal, "    // 0x0000-0x1FFF variables globales (Nova no tiene globales mutables)\n");
    fprintf(sal, "    .org 0x%04X\n", DIR_CADENAS);
    fprintf(sal, "    // Literales de cadena: una palabra de longitud y luego los bytes.\n");
    /*
     * Los bytes salen uno por uno con .byte y el relleno con .space: son las
     * directivas que tiene el ensamblador de CERBERO. No hay .ascii ni .align.
     */
    for (TACCadena *c = tac->cadenas; c != NULL; c = c->next) {
        size_t n = strlen(c->texto);
        fprintf(sal, "%s:\n", c->etiqueta);
        fprintf(sal, "    .word %zu\n", n);
        for (size_t k = 0; k < n; k++) {
            if (k % 12 == 0) fprintf(sal, "%s    .byte ", k ? "\n" : "");
            else             fprintf(sal, ", ");
            fprintf(sal, "0x%02X", (unsigned char)c->texto[k]);
        }
        if (n) fprintf(sal, "\n");
        size_t sobra = n % 4;
        if (sobra) fprintf(sal, "    .space %zu   // alineacion a palabra\n", 4 - sobra);
    }
    fprintf(sal, "\n    .org 0x%04X\n", DIR_OUT_N);
    fprintf(sal, "__out_n:\n    .word 0\n");
    fprintf(sal, "__out_buf:\n    .space %d\n\n", 0x4000 - DIR_OUT_BUF);
}

/*
 * Tabla de simbolos del ensamblador: cada etiqueta con su direccion ya
 * resuelta. Es el requisito 6.2 de la guia del proyecto, y es tambien la
 * forma de leer el resultado de la fase 5 de la guia, el calculo de saltos y
 * la resolucion de referencias: aqui se ve que cada nombre quedo
 * convertido en una direccion numerica. Va como comentario, asi que no
 * cambia nada de lo que el ensamblador de CERBERO codifica.
 */
static void imprimir_tabla_etiquetas(void) {
    fprintf(sal, "\n// =====================================================\n");
    fprintf(sal, "// Tabla de simbolos: etiquetas y direcciones resueltas\n");
    fprintf(sal, "// =====================================================\n");

    fprintf(sal, "//   %-28s %-10s %s\n", "ETIQUETA", "DIRECCION", "UBICACION");
    for (int i = 0; i < n_etqs_dato; i++)
        fprintf(sal, "//   %-28s 0x%04X     DMEM (datos)\n",
                etqs_dato[i].nombre, (unsigned)etqs_dato[i].direccion);
    for (int i = 0; i < n_etqs; i++)
        fprintf(sal, "//   %-28s 0x%04X     IMEM bundle %d\n",
                etqs[i].nombre, (unsigned)(etqs[i].bundle * 16), etqs[i].bundle);
    fprintf(sal, "//   %d etiquetas de codigo, %d de datos\n", n_etqs, n_etqs_dato);
}

static void imprimir_codigo_texto(void) {
    int ie = 0, in = 0;
    int ultima_linea = 0, ultima_columna = 0;
    for (int b = 0; b <= n_bundles; b++) {
        /*
         * El bloque seguro se marca con las directivas que el ensamblador de
         * CERBERO verifica. El .org evita tener que escribir los bundles de
         * relleno: la herramienta los completa sola.
         */
        if (inicio_seguro >= 0 && b == inicio_seguro)
            fprintf(sal, "\n    .org 0x%04X\n    .secure\n", b * 16);
        /* Notas y etiquetas salen en el orden en que se registraron. */
        for (;;) {
            bool hay_n = (in < n_notas && notas[in].bundle == b);
            bool hay_e = (ie < n_etqs && etqs[ie].bundle == b);
            if (!hay_n && !hay_e) break;
            if (hay_n && (!hay_e || notas[in].orden < etqs[ie].orden))
                fprintf(sal, "    // %s\n", notas[in++].texto);
            else
                fprintf(sal, "%s:\n", etqs[ie++].nombre);
            /* Tras una etiqueta o una nota conviene repetir la posicion: el
             * lector acaba de perder el hilo del fuente. */
            ultima_linea = -1;
        }
        if (b == n_bundles) {
            if (inicio_seguro >= 0) fprintf(sal, "    .endsecure\n");
            break;
        }
        const Bundle *x = &prog[b];
        /*
         * La posicion se anota solo cuando cambia. Anotarla en cada bundle
         * repetia la misma linea delante de los bundles de relleno y dejaba
         * mas comentarios que instrucciones en el listado.
         */
        if (x->source_line > 0 &&
            (x->source_line != ultima_linea || x->source_col != ultima_columna)) {
            if (x->source_col > 0)
                fprintf(sal, "    // Nova fuente: linea %d, columna %d\n",
                        x->source_line, x->source_col);
            else
                fprintf(sal, "    // Nova fuente: linea %d\n", x->source_line);
        }
        ultima_linea = x->source_line;
        ultima_columna = x->source_col;
        /*
         * La direccion del bundle va como comentario al final de la linea.
         * El ensamblador de CERBERO corta todo lo que sigue a '//', asi que
         * no entra en la codificacion; es el requisito 6.2 de la guia, que
         * pide numeros de linea y direcciones en el archivo de ensamblador.
         */
        fprintf(sal, "    %-26s | %-10s | %-22s | %-18s | %-16s ;  // 0x%04X\n",
                x->s[0] ? x->s[0] : "-", x->s[1] ? x->s[1] : "-",
                x->s[2] ? x->s[2] : "-", x->s[3] ? x->s[3] : "-",
                x->s[4] ? x->s[4] : "-", (unsigned)(b * 16));
    }
}

/* --- Recorrido por funciones ------------------------------------------ */

/* Mide el marco de la funcion recorriendo su tramo del TAC. */
static void medir_funcion(TACInst *desde) {
    f_marco_loc = 0;
    f_guarda_r15 = false;
    n_temps = 0;
    n_temp_slots = 0;
    int k_salida = 0;

    for (const TACSimbolo *s = lista->simbolos; s != NULL; s = s->next) {
        if (s->funcion == NULL || strcmp(s->funcion, func) != 0) continue;
        if (-s->offset > f_marco_loc) f_marco_loc = -s->offset;
    }

    int posicion = 0;
    for (TACInst *i = desde; i != NULL; i = i->next, posicion++) {
        if (i->op == TAC_FUNC_END) break;
        if (i->op == TAC_CALL || i->op == TAC_DIV || i->op == TAC_MOD)
            f_guarda_r15 = true;
        if (i->op == TAC_PARAM && i->aux > 4 && i->aux - 4 > k_salida)
            k_salida = i->aux - 4;
        /* Registra los temporales en el orden en que aparecen. */
        if (i->result != NULL && tac_es_temporal(i->result)) {
            int t = indice_temp(i->result);
            if (temp_primero[t] > posicion) temp_primero[t] = posicion;
            if (temp_ultimo[t] < posicion) temp_ultimo[t] = posicion;
        }
        const char *ops[2] = {i->arg1, i->arg2};
        for (int k = 0; k < 2; k++) {
            if (ops[k] == NULL || !tac_es_temporal(ops[k])) continue;
            int t = indice_temp(ops[k]);
            if (temp_primero[t] > posicion) temp_primero[t] = posicion;
            if (temp_ultimo[t] < posicion) temp_ultimo[t] = posicion;
        }
    }

    int slot_ultimo[MAX_TEMPS];
    for (int t = 0; t < n_temps; t++) {
        int slot = -1;
        for (int s = 0; s < n_temp_slots; s++) {
            if (slot_ultimo[s] < temp_primero[t]) {
                slot = s;
                break;
            }
        }
        if (slot < 0) slot = n_temp_slots++;
        temp_slot[t] = slot;
        slot_ultimo[slot] = temp_ultimo[t];
    }

    f_base_loc = 4 * k_salida;
    f_base_tmp = f_base_loc + f_marco_loc;
    f_total = f_base_tmp + 4 * n_temp_slots + (f_guarda_r15 ? 4 : 0);
    if (f_total < 4) f_total = 4;
}

/*
 * Suelta los textos de la construccion anterior. Hace falta porque la
 * relajacion de saltos vuelve a construir el programa desde cero, y sin esto
 * los slots, las etiquetas y las notas de la pasada previa quedarian
 * colgando.
 */
static void liberar_construccion(void) {
    for (int b = 0; b < n_bundles; b++)
        for (int s = 0; s < 5; s++) { free(prog[b].s[s]); prog[b].s[s] = NULL; }
    for (int i = 0; i < n_etqs; i++) free(etqs[i].nombre);
    for (int i = 0; i < n_etqs_dato; i++) free(etqs_dato[i].nombre);
    for (int i = 0; i < n_notas; i++) free(notas[i].texto);
    n_bundles = n_etqs = n_etqs_dato = n_notas = 0;
}

/* Suelta todo lo que reservo el generador. Se llama al terminar. */
static void liberar_todo(void) {
    liberar_construccion();
    free(prog);       prog = NULL;       cap_bundles = 0;
    free(etqs);       etqs = NULL;       cap_etqs = 0;
    free(etqs_dato);  etqs_dato = NULL;  cap_etqs_dato = 0;
    free(notas);      notas = NULL;      cap_notas = 0;
    free(datos);      datos = NULL;      datos_cap = 0;
    datos_largo = datos_init = 0;
    free(sitio_largo);  sitio_largo = NULL;
    free(sitio_bundle); sitio_bundle = NULL;
    cap_sitios = n_sitios = 0;
}

/*
 * Una funcion es "segura" si su cuerpo toca la boveda. El criterio es el
 * cuerpo entero y no cada instruccion por separado porque salir de la region
 * cierra la sesion por hardware: el camino que va del LOGIN a la ultima ronda
 * tiene que quedar completo adentro.
 */
static bool funcion_usa_boveda(TACInst *i) {
    for (TACInst *j = i->next; j != NULL && j->op != TAC_FUNC_END; j = j->next) {
        switch (j->op) {
            case TAC_AUTHW: case TAC_VAULT_LOGIN: case TAC_VAULT_LOGOUT:
            case TAC_KSETW: case TAC_FEISTEL: case TAC_FEISTEL_DECRYPT:
                return true;
            default: break;
        }
    }
    return false;
}

/* Arma el programa en memoria una vez. No escribe nada. */
static bool construir_una_vez(TACList *tac) {
    liberar_construccion();
    lista = tac;
    hubo_error = false;
    usa_div = usa_scribe_int = usa_scribe_txt = usa_dic = false;
    n_bundles = n_etqs = n_etqs_dato = n_notas = 0;
    linea_fuente_actual = columna_fuente_actual = 0;
    orden_global = 0;
    n_sitios = 0;
    inicio_seguro = -1;
    datos_largo = datos_init = 0;

    construir_datos(tac);
    medir_soporte(tac);

    /* Un archivo sin principale es un modulo de biblioteca: no lleva codigo
     * de arranque, solo sus funciones para que el enlazador las use. */
    bool hay_principale = false;
    for (TACInst *i = tac->head; i != NULL; i = i->next)
        if (i->op == TAC_FUNC_BEGIN && i->result != NULL &&
            strcmp(i->result, "principale") == 0) hay_principale = true;

    if (hay_principale) {
        ciclo = 0;
        for (int i = 0; i < 16; i++) listo[i] = 0;
        listo_flags = 0;
        cache_limpiar();
        func = "__inicio";
        nota("Arranque: la pila empieza en 0xFFFC y se entra a principale");
        registrar_etiqueta("__inicio");
        cargar_const(R_SP, 0xFFFC);
        barrera();
        salto("jal.al principale", -1);
        salto("halt", -1);
    } else {
        nota("Modulo de biblioteca: no tiene principale, no lleva arranque");
    }

    /*
     * Primero las funciones normales, despues el soporte, y al final las que
     * tocan la boveda, alineadas al comienzo de la region segura.
     */
    bool hay_seguras = false;
    for (TACInst *i = tac->head; i != NULL; i = i->next)
        if (i->op == TAC_FUNC_BEGIN && funcion_usa_boveda(i)) hay_seguras = true;

    for (int tanda = 0; tanda < 2; tanda++) {
    if (tanda == 1) {
        if (usa_div) emitir_div32();
        if (usa_scribe_int) emitir_scribe_int();
        if (usa_scribe_txt) emitir_scribe_txt();
        if (usa_dic) emitir_dic_fin();
        if (!hay_seguras) break;
        if (n_bundles > SEC_BASE_BUNDLE) {
            diag_error("E410", 0, 1, 1,
                       "el codigo no criptografico ocupa %d bundles y la region "
                       "segura empieza en el %d", n_bundles, SEC_BASE_BUNDLE);
            hubo_error = true;
        }
        while (n_bundles < SEC_BASE_BUNDLE) vacio();
        inicio_seguro = n_bundles;
        nota("Region segura: de 0x7000 a 0x7FFF. La boveda solo autentica aqui.");
    }
    for (TACInst *i = tac->head; i != NULL; i = i->next) {
        if (i->op != TAC_FUNC_BEGIN) continue;
        if (funcion_usa_boveda(i) != (tanda == 1)) continue;

        func = i->result;
        f_es_principale = (strcmp(func, "principale") == 0);
        medir_funcion(i->next);

        ciclo = 0;
        linea_fuente_actual = columna_fuente_actual = 0;
        for (int r = 0; r < 16; r++) listo[r] = 0;
        listo_flags = 0;
        cache_limpiar();

        nota("functio %s", func);
        registrar_etiqueta(func);
        emitir_prologo();

        for (TACInst *j = i->next; j != NULL && j->op != TAC_FUNC_END; j = j->next) {
            linea_fuente_actual = j->linea;
            columna_fuente_actual = j->columna;
            emitir_inst(j);
        }
        linea_fuente_actual = columna_fuente_actual = 0;
    }
    }

    return !hubo_error;
}

/*
 * Marca los saltos incondicionales que quedaron fuera del alcance del tipo C.
 * Devuelve cuantos marco de nuevo; cero quiere decir que ya convergio.
 */
static int marcar_desbordados(void) {
    int nuevos = 0;
    for (int i = 0; i < n_sitios; i++) {
        if (sitio_largo[i]) continue;
        int b = sitio_bundle[i];
        if (b < 0 || b >= n_bundles || prog[b].s[4] == NULL) continue;

        char mn[32], etq[64];
        if (sscanf(prog[b].s[4], "%31s %63s", mn, etq) != 2) continue;
        if (strcmp(mn, "br.al") != 0 && strcmp(mn, "jal.al") != 0) continue;

        int d = buscar_etiqueta(etq);
        if (d < 0) continue;                 /* externo: lo resuelve el enlazador */
        long desp = (long)d - (long)b - 1;
        if (desp < -512 || desp > 511) { sitio_largo[i] = 1; nuevos++; }
    }
    return nuevos;
}

/*
 * Una vez que la relajacion convergio, las posiciones son definitivas, asi que
 * '#&etiqueta' se puede sustituir por la direccion en bytes. Hace falta porque
 * el ensamblador de CERBERO solo acepta numeros en los inmediatos. Lo que no
 * se puede resolver es un simbolo de otro modulo: eso lo deja el enlazador, y
 * quien lo encuentre reporta E401.
 */
static void resolver_direcciones(void) {
    for (int b = 0; b < n_bundles; b++) {
        for (int k = 0; k < 5; k++) {
            char *t = prog[b].s[k];
            if (t == NULL) continue;
            char *amp = strchr(t, '&');
            if (amp == NULL) continue;
            int destino = buscar_etiqueta(amp + 1);
            if (destino < 0) continue;      /* externo: lo resuelve el enlazador */
            char nuevo[96];
            size_t pre = (size_t)(amp - t);
            if (pre >= sizeof(nuevo)) continue;
            memcpy(nuevo, t, pre);
            snprintf(nuevo + pre, sizeof(nuevo) - pre, "%d", destino * 16);
            free(prog[b].s[k]);
            prog[b].s[k] = dup_o_nulo(nuevo);
        }
    }
}

/* Arma el programa y relaja los saltos que no alcanzan, hasta que converja. */
static bool construir_programa(TACList *tac) {
    if (sitio_largo != NULL) memset(sitio_largo, 0, (size_t)cap_sitios);
    n_sitios = 0;

    bool ok = construir_una_vez(tac);
    for (int pasada = 0; ok && pasada < 8; pasada++) {
        if (marcar_desbordados() == 0) break;
        ok = construir_una_vez(tac);
    }
    resolver_direcciones();

    /* El aviso va aqui y no en cada pasada: la relajacion construye varias
     * veces y si no se repetiria una vez por pasada. */
    if (inicio_seguro >= 0 && n_bundles - inicio_seguro > SEC_BUNDLES) {
        diag_advertencia("W008", 0, 1, 1,
                         "el codigo que usa la boveda ocupa %d bundles y la region "
                         "segura tiene %d: parte quedaria afuera y la sesion se cerraria",
                         n_bundles - inicio_seguro, SEC_BUNDLES);
    }

    /*
     * IMEM es de 2048 bundles. Pasado ese limite el programa compila pero no
     * se puede cargar: novac_image.py lo rechaza al armar la imagen. Conviene
     * decirlo aqui, que es donde se ve el tamano, y no al final de la cadena.
     */
    if (n_bundles > IMEM_BUNDLES) {
        diag_advertencia("W009", 0, 1, 1,
                         "el programa ocupa %d bundles y la IMEM de CERBERO tiene "
                         "%d: no se podra cargar en el procesador",
                         n_bundles, IMEM_BUNDLES);
    }

    return ok;
}

/*
 * Direccion absoluta de cada variable local, para la tabla de simbolos.
 *
 * Una local no tiene una direccion fija: vive en R14 + su desplazamiento, y
 * R14 cambia en cada llamada. Lo que si esta determinado en compilacion es la
 * direccion de la PRIMERA activacion de cada funcion, porque la pila arranca
 * en 0xFFFC y el tamano de cada marco se conoce.
 *
 * Se calcula propagando desde principale por el grafo de llamadas:
 *
 *     base(principale) = 0xFFFC - marco(principale)
 *     base(F)          = base(quien la llama) - marco(F)
 *
 * Cuando una funcion se llama desde varios sitios se toma la direccion mas
 * alta, que es la del camino mas corto desde principale: la primera vez que
 * se entra a esa funcion. En una funcion recursiva, la segunda llamada queda
 * un marco mas abajo, la tercera dos, y asi.
 */
#define MAX_FUNCS 256

typedef struct {
    const char *nombre;
    TACInst *cuerpo;     /* primera instruccion, para volver a medirla */
    int   marco;         /* bytes que reserva su prologo */
    long  base;          /* direccion del marco en la primera activacion */
    bool  alcanzada;
} InfoFunc;

static InfoFunc fns[MAX_FUNCS];
static int n_fns = 0;

static int fn_indice(const char *nombre) {
    for (int i = 0; i < n_fns; i++)
        if (strcmp(fns[i].nombre, nombre) == 0) return i;
    return -1;
}

/*
 * Propaga la base del marco desde principale. Es un recorrido en anchura: se
 * visita cada funcion a la profundidad minima a la que se la puede alcanzar,
 * asi que la direccion que queda es la de su primera activacion.
 */
static void propagar_bases(TACList *tac) {
    int raiz = fn_indice("principale");
    if (raiz < 0) return;

    fns[raiz].base = (long)CERBERO_PILA_TOPE - fns[raiz].marco;
    fns[raiz].alcanzada = true;

    int cola[MAX_FUNCS], n_cola = 0, cabeza = 0;
    cola[n_cola++] = raiz;

    while (cabeza < n_cola) {
        int c = cola[cabeza++];
        /* Las llamadas que hace esta funcion, leidas del codigo intermedio. */
        bool dentro = false;
        for (TACInst *i = tac->head; i != NULL; i = i->next) {
            if (i->op == TAC_FUNC_BEGIN && i->result != NULL) {
                dentro = (strcmp(i->result, fns[c].nombre) == 0);
                continue;
            }
            if (!dentro || i->op != TAC_CALL || i->arg1 == NULL) continue;
            int d = fn_indice(i->arg1);
            if (d < 0 || fns[d].alcanzada) continue;   /* soporte, o ya visitada */
            fns[d].base = fns[c].base - fns[d].marco;
            fns[d].alcanzada = true;
            if (n_cola < MAX_FUNCS) cola[n_cola++] = d;
        }
    }
}

bool codegen_update_symbol_layout(TACList *tac, SymbolTable *st) {
    if (tac == NULL || st == NULL) return false;
    lista = tac;
    n_fns = 0;
    for (TACInst *i = tac->head; i != NULL; i = i->next) {
        if (i->op != TAC_FUNC_BEGIN || i->result == NULL) continue;
        func = i->result;
        medir_funcion(i->next);

        /* El marco completo, que es lo que resta el prologo: no solo las
         * locales, tambien los temporales y el R15 guardado. */
        if (n_fns < MAX_FUNCS) {
            fns[n_fns].nombre    = i->result;
            fns[n_fns].cuerpo    = i->next;
            fns[n_fns].marco     = f_total;
            fns[n_fns].base      = 0;
            fns[n_fns].alcanzada = false;
            n_fns++;
        }
        symtab_set_frame_total(st, i->result, f_total);

        for (const TACSimbolo *s = tac->simbolos; s != NULL; s = s->next) {
            if (s->funcion == NULL || strcmp(s->funcion, func) != 0) continue;
            symtab_set_frame_offset(st, func, s->nombre,
                                    desplazamiento_simbolo(s));
        }
    }

    /* Con los marcos medidos se puede ubicar cada uno en la pila. */
    propagar_bases(tac);
    for (int k = 0; k < n_fns; k++) {
        if (!fns[k].alcanzada) continue;       /* nunca se llama desde principale */
        /* desplazamiento_simbolo() lee el reparto del marco que deja
         * medir_funcion(), asi que hay que volver a medir esta funcion. */
        func = fns[k].nombre;
        medir_funcion(fns[k].cuerpo);
        for (const TACSimbolo *s = tac->simbolos; s != NULL; s = s->next) {
            if (s->funcion == NULL || strcmp(s->funcion, fns[k].nombre) != 0) continue;
            symtab_set_data_address(st, fns[k].nombre, s->nombre,
                                    (uint32_t)(fns[k].base + desplazamiento_simbolo(s)));
        }
    }

    bool ok = construir_programa(tac);
    if (ok) {
        for (TACInst *i = tac->head; i != NULL; i = i->next) {
            if (i->op != TAC_FUNC_BEGIN || i->result == NULL) continue;
            int bundle = buscar_etiqueta(i->result);
            if (bundle >= 0)
                symtab_set_function_address(st, i->result,
                                            (uint32_t)bundle * 16u);
        }
        /* Antes de liberar: la tabla de saltos resueltos se guarda aparte. */
        guardar_etiquetas();
    }
    liberar_todo();
    return ok;
}

bool codegen_generate_vliw(TACList *tac, SymbolTable *st, FILE *out) {
    (void)st;
    if (tac == NULL || out == NULL) return false;
    sal = out;
    bool ok = construir_programa(tac);

    fprintf(out, "// =====================================================\n");
    fprintf(out, "// Ensamblador VLIW para CERBERO, generado por novac\n");
    fprintf(out, "// Bundle de 128 bits, cinco slots:\n");
    fprintf(out, "//   <S0:ALU-0> | <S1:ALU-1> | <S2:LSU> | <S3:CRP> | <S4:BRU> ;\n");
    fprintf(out, "// Tres bundles de productor a consumidor; un delay slot\n");
    fprintf(out, "// despues de cada salto, que siempre se ejecuta.\n");
    fprintf(out, "// =====================================================\n\n");

    imprimir_datos_texto(tac);

    fprintf(out, ".text\n");
    fprintf(out, "    .org 0x0000\n");
    imprimir_codigo_texto();
    imprimir_tabla_etiquetas();
    fprintf(out, "\n// fin del programa\n");
    liberar_todo();
    return ok;
}

/* ====================================================================== */
/* Emision binaria                                                        */
/* ====================================================================== */

/*
 * Codificacion de un bundle de 128 bits, segun la seccion de formatos del
 * ISA de CERBERO:
 *
 *   127:96  S0 (ALU-0, 32 bits, la unica que escribe banderas)
 *    95:64  S1 (ALU-1, 32 bits)
 *    63:32  S2 (LSU,   32 bits)
 *    31:16  S3 (CRP,   16 bits)
 *    15:0   S4 (BRU,   16 bits)
 *
 * S0 queda en los bits mas significativos para que un volcado hexadecimal se
 * lea en el mismo orden en que se escriben los slots en el ensamblador. El
 * opcode 0 es NOP en los cinco espacios, asi que un bundle de 128 ceros es un
 * bundle vacio valido.
 *
 * Formatos de 32 bits:
 *   Tipo A   opcode[31:27] rd[26:23] rs1[22:19] rs2[18:15] reservado[14:0]
 *   Tipo I   opcode[31:27] rd[26:23] rs1[22:19] imm19[18:0]
 *   Tipo M   opcode[31:27] rd/rs[26:23] rbase[22:19] imm19[18:0]
 *
 * Formatos de 16 bits:
 *   Tipo F   opcode[15:13] par[12:10] kv[9:8] ronda[7:6] reservado[5:0]
 *   Tipo V   opcode[15:13] campo1[12:11] campo2[10:9] rs[8:5] reservado[4:0]
 *   Tipo AC  opcode[15:13] i[12] subop[11:9] rd[8:5] rs2/imm5[4:0]
 *   Tipo C   opcode[15:13] cond[12:10] desp[9:0]
 *   Tipo J   opcode[15:13] cond[12:10] rsv[9] rs[8:5] reservado[4:0]
 */

typedef struct { const char *mn; unsigned op; int tipo; } OpALU;
/* tipo: 0 = A con rd,rs1,rs2 | 1 = A con rd,rs1 | 2 = A con rs1,rs2 (cmp)
 *       3 = I con rd,rs1,imm | 4 = I con rd,imm (movi/movh) | 5 = I con rs1,imm (cmpi) */
static const OpALU tabla_alu[] = {
    {"nop",  0x00, 1}, {"add",  0x01, 0}, {"sub",  0x02, 0}, {"mul",  0x03, 0},
    {"and",  0x04, 0}, {"or",   0x05, 0}, {"xor",  0x06, 0}, {"sll",  0x07, 0},
    {"srl",  0x08, 0}, {"sra",  0x09, 0}, {"rol",  0x0A, 0}, {"ror",  0x0B, 0},
    {"mov",  0x0C, 1}, {"not",  0x0D, 1}, {"cmp",  0x0E, 2}, {"test", 0x0F, 2},
    {"neg",  0x10, 1}, {"addi", 0x11, 3}, {"subi", 0x12, 3}, {"andi", 0x14, 3},
    {"ori",  0x15, 3}, {"xori", 0x16, 3}, {"slli", 0x17, 3}, {"srli", 0x18, 3},
    {"srai", 0x19, 3}, {"roli", 0x1A, 3}, {"movi", 0x1C, 4}, {"movh", 0x1D, 6},
    {"cmpi", 0x1E, 5}, {"testi",0x1F, 5},
    {NULL, 0, 0}
};

/* LSU: bit4 = postincremento, bit3 = store, bits2:1 = tamano, bit0 = ceros. */
typedef struct { const char *mn; unsigned op; } OpLSU;
static const OpLSU tabla_lsu[] = {
    {"nop", 0x00}, {"lw", 0x06}, {"sw", 0x0E},
    {"lw.inc", 0x16}, {"sw.inc", 0x1E}, {NULL, 0}
};

static int cond_num(const char *c) {
    if (strcmp(c, "al") == 0)   return 0;
    if (strcmp(c, "eq") == 0)   return 1;
    if (strcmp(c, "ne") == 0)   return 2;
    if (strcmp(c, "lt") == 0)   return 3;
    if (strcmp(c, "ge") == 0)   return 4;
    if (strcmp(c, "ltu") == 0)  return 5;
    if (strcmp(c, "geu") == 0)  return 6;
    if (strcmp(c, "auth") == 0) return 7;
    return -1;
}

static void err_cod(const char *texto, const char *motivo) {
    diag_error("E410", 0, 1, 1, "no se pudo codificar '%s': %s", texto, motivo);
    hubo_error = true;
}

/* Corta la instruccion en palabras separadas por espacios y comas. */
static int trozos(const char *texto, char partes[8][48]) {
    int n = 0;
    const char *p = texto;
    while (*p && n < 8) {
        while (*p == ' ' || *p == ',') p++;
        if (!*p) break;
        int k = 0;
        while (*p && *p != ' ' && *p != ',' && k < 47) partes[n][k++] = *p++;
        partes[n][k] = '\0';
        n++;
    }
    return n;
}

static int reg_num(const char *t, bool *ok) {
    *ok = false;
    if (t[0] != 'r' && t[0] != 'R') return 0;
    char *fin = NULL;
    long v = strtol(t + 1, &fin, 10);
    if (fin == NULL || *fin != '\0' || v < 0 || v > 15) return 0;
    *ok = true;
    return (int)v;
}

/* Un inmediato: numero, o etiqueta de dato que se resuelve a su direccion. */
/*
 * Ranura de la boveda, escrita k0..k3. El ensamblador de CERBERO exige esta
 * forma y rechaza un numero suelto, porque el campo kv es de dos bits y las
 * ranuras son exactamente cuatro.
 */
static int llave_num(const char *t, bool *ok) {
    *ok = false;
    if (t[0] != 'k' && t[0] != 'K') return 0;
    char *fin = NULL;
    long v = strtol(t + 1, &fin, 10);
    if (fin == NULL || *fin != '\0' || v < 0 || v > 3) return 0;
    *ok = true;
    return (int)v;
}

static long inmediato(const char *t, bool *ok) {
    *ok = true;
    const char *p = (t[0] == '#') ? t + 1 : t;

    /* '&etiqueta' es la direccion en bytes de una etiqueta de codigo: la usa
     * la forma larga de los saltos, que carga el destino en un registro. */
    if (p[0] == '&') {
        int b = buscar_etiqueta(p + 1);
        if (b < 0) {
            diag_error("E401", 0, 1, 1,
                       "'%s' no esta en este modulo: lo resuelve el enlazador", p + 1);
            hubo_error = true;
            return 0;
        }
        return (long)b * 16;
    }

    int d = buscar_etiqueta_dato(p);
    if (d >= 0) return d;
    char *fin = NULL;
    long v = strtol(p, &fin, 0);
    if (fin == NULL || *fin != '\0') { *ok = false; return 0; }
    return v;
}

static uint32_t cod_alu(const char *texto) {
    char p[8][48];
    int n = trozos(texto, p);
    if (n == 0) return 0;
    const OpALU *e = NULL;
    for (int i = 0; tabla_alu[i].mn; i++)
        if (strcmp(tabla_alu[i].mn, p[0]) == 0) { e = &tabla_alu[i]; break; }
    if (e == NULL) { err_cod(texto, "mnemonico de ALU desconocido"); return 0; }

    bool ok1 = false, ok2 = false, ok3 = false;
    uint32_t w = (uint32_t)e->op << 27;
    switch (e->tipo) {
        case 0: {   /* rd, rs1, rs2 */
            int rd = reg_num(p[1], &ok1), a = reg_num(p[2], &ok2), b = reg_num(p[3], &ok3);
            if (!(ok1 && ok2 && ok3)) { err_cod(texto, "se esperaban tres registros"); return 0; }
            w |= (uint32_t)rd << 23 | (uint32_t)a << 19 | (uint32_t)b << 15;
            return w;
        }
        case 1: {   /* rd, rs1 */
            if (n == 1) return w;            /* nop */
            int rd = reg_num(p[1], &ok1), a = reg_num(p[2], &ok2);
            if (!(ok1 && ok2)) { err_cod(texto, "se esperaban dos registros"); return 0; }
            w |= (uint32_t)rd << 23 | (uint32_t)a << 19;
            return w;
        }
        case 2: {   /* rs1, rs2 */
            int a = reg_num(p[1], &ok1), b = reg_num(p[2], &ok2);
            if (!(ok1 && ok2)) { err_cod(texto, "se esperaban dos registros"); return 0; }
            w |= (uint32_t)a << 19 | (uint32_t)b << 15;
            return w;
        }
        case 3: {   /* rd, rs1, #imm */
            int rd = reg_num(p[1], &ok1), a = reg_num(p[2], &ok2);
            long v = inmediato(p[3], &ok3);
            if (!(ok1 && ok2 && ok3)) { err_cod(texto, "se esperaba rd, rs1, #inmediato"); return 0; }
            if (v < IMM19_MIN || v > IMM19_MAX) { err_cod(texto, "el inmediato no cabe en 19 bits"); return 0; }
            w |= (uint32_t)rd << 23 | (uint32_t)a << 19 | ((uint32_t)v & 0x7FFFF);
            return w;
        }
        case 4: {   /* rd, #imm : movi, tipo I con inmediato de 19 bits */
            int rd = reg_num(p[1], &ok1);
            long v = inmediato(p[2], &ok2);
            if (!(ok1 && ok2)) { err_cod(texto, "se esperaba rd, #inmediato"); return 0; }
            if (v < IMM19_MIN || v > IMM19_MAX) { err_cod(texto, "el inmediato no cabe en 19 bits"); return 0; }
            w |= (uint32_t)rd << 23 | ((uint32_t)v & 0x7FFFF);
            return w;
        }
        case 6: {   /* rd, #imm : movh, tipo U con inmediato de 16 bits */
            int rd = reg_num(p[1], &ok1);
            long v = inmediato(p[2], &ok2);
            if (!(ok1 && ok2)) { err_cod(texto, "se esperaba rd, #inmediato"); return 0; }
            /*
             * Tipo U: el inmediato de 16 bits ocupa [18:3], y los campos rs1
             * [22:19] y cond [2:0] son reservados y van en cero. Se acepta
             * tanto la forma con signo como la forma sin signo, porque lo que
             * se escribe es un patron de bits.
             */
            if (v < -32768 || v > 65535) { err_cod(texto, "el inmediato de movh no cabe en 16 bits"); return 0; }
            w |= (uint32_t)rd << 23 | (((uint32_t)v & 0xFFFF) << 3);
            return w;
        }
        case 5: {   /* rs1, #imm */
            int a = reg_num(p[1], &ok1);
            long v = inmediato(p[2], &ok2);
            if (!(ok1 && ok2)) { err_cod(texto, "se esperaba rs1, #inmediato"); return 0; }
            if (v < IMM19_MIN || v > IMM19_MAX) { err_cod(texto, "el inmediato no cabe en 19 bits"); return 0; }
            w |= (uint32_t)a << 19 | ((uint32_t)v & 0x7FFFF);
            return w;
        }
        default: return 0;
    }
}

static uint32_t cod_lsu(const char *texto) {
    char p[8][48];
    int n = trozos(texto, p);
    if (n == 0) return 0;
    const OpLSU *e = NULL;
    for (int i = 0; tabla_lsu[i].mn; i++)
        if (strcmp(tabla_lsu[i].mn, p[0]) == 0) { e = &tabla_lsu[i]; break; }
    if (e == NULL) { err_cod(texto, "mnemonico de LSU desconocido"); return 0; }
    if (n == 1) return 0;

    bool ok1 = false;
    int rdato = reg_num(p[1], &ok1);
    if (!ok1) { err_cod(texto, "se esperaba un registro de dato"); return 0; }

    /* El operando de memoria viene como #desp(rbase). */
    const char *m = p[2];
    if (m[0] == '#') m++;
    char *par = strchr((char *)m, '(');
    if (par == NULL) { err_cod(texto, "se esperaba #desp(rbase)"); return 0; }
    char desp[32];
    size_t largo = (size_t)(par - m);
    if (largo >= sizeof(desp)) largo = sizeof(desp) - 1;
    memcpy(desp, m, largo);
    desp[largo] = '\0';
    char base[48];
    const char *cierra = strchr(par + 1, ')');
    size_t lbase = (cierra != NULL) ? (size_t)(cierra - (par + 1)) : strlen(par + 1);
    if (lbase >= sizeof(base)) lbase = sizeof(base) - 1;
    memcpy(base, par + 1, lbase);
    base[lbase] = '\0';

    bool ok2 = false, ok3 = false;
    int rbase = reg_num(base, &ok2);
    long v = inmediato(desp, &ok3);
    if (!(ok2 && ok3)) { err_cod(texto, "operando de memoria mal formado"); return 0; }
    if (v < IMM19_MIN || v > IMM19_MAX) { err_cod(texto, "el desplazamiento no cabe en 19 bits"); return 0; }

    return (uint32_t)e->op << 27 | (uint32_t)rdato << 23 |
           (uint32_t)rbase << 19 | ((uint32_t)v & 0x7FFFF);
}

static uint16_t cod_crp(const char *texto) {
    char p[8][48];
    int n = trozos(texto, p);
    if (n == 0) return 0;

    if (strcmp(p[0], "nop") == 0) return 0;

    if (strcmp(p[0], "f4e") == 0 || strcmp(p[0], "f4d") == 0) {
        /* f4e par, kv, #ronda */
        unsigned op = (strcmp(p[0], "f4e") == 0) ? 1u : 2u;
        if (n < 4) { err_cod(texto, "se esperaba par, kv, #ronda"); return 0; }
        if (p[1][0] != 'p' && p[1][0] != 'P') { err_cod(texto, "se esperaba un par P0-P7"); return 0; }
        long par = strtol(p[1] + 1, NULL, 10);
        bool ok1 = false, ok2 = false;
        long kv = llave_num(p[2], &ok1);
        long ronda = inmediato(p[3], &ok2);
        if (!ok1) { err_cod(texto, "se esperaba una llave k0..k3"); return 0; }
        if (!ok2) { err_cod(texto, "la ronda debe ser constante"); return 0; }
        if (par < 0 || par > 7 || ronda < 0 || ronda > 3) {
            err_cod(texto, "par 0-7 y ronda 0-3");
            return 0;
        }
        return (uint16_t)(op << 13 | (unsigned)par << 10 |
                          (unsigned)kv << 8 | (unsigned)ronda << 6);
    }

    if (strcmp(p[0], "ksetw") == 0) {
        /* ksetw kN, #widx, rs : kv en [12:11], widx en [10:9], rs en [8:5] */
        if (n < 4) { err_cod(texto, "se esperaba kN, #widx, rs"); return 0; }
        bool ok1 = false, ok2 = false, ok3 = false;
        long kv = llave_num(p[1], &ok1);
        long widx = inmediato(p[2], &ok2);
        int rs = reg_num(p[3], &ok3);
        if (!ok1) { err_cod(texto, "se esperaba una llave k0..k3"); return 0; }
        if (!(ok2 && ok3)) { err_cod(texto, "operandos de ksetw"); return 0; }
        if (widx < 0 || widx > 3) { err_cod(texto, "widx va de 0 a 3"); return 0; }
        return (uint16_t)(3u << 13 | (unsigned)kv << 11 |
                          (unsigned)widx << 9 | (unsigned)rs << 5);
    }

    if (strcmp(p[0], "authw") == 0) {
        /*
         * authw #widx, rs : widx en [10:9], rs en [8:5].
         *
         * El campo [12:11] es reservado y tiene que ir en cero: el ISA lo fijo
         * asi en la v1.1 y key_vault.sv levanta ILLOP si no lo esta.
         */
        if (n < 3) { err_cod(texto, "se esperaba #widx, rs"); return 0; }
        bool ok1 = false, ok2 = false;
        long widx = inmediato(p[1], &ok1);
        int rs = reg_num(p[2], &ok2);
        if (!(ok1 && ok2)) { err_cod(texto, "operandos de authw"); return 0; }
        if (widx < 0 || widx > 3) { err_cod(texto, "widx va de 0 a 3"); return 0; }
        return (uint16_t)(4u << 13 | (unsigned)widx << 9 | (unsigned)rs << 5);
    }

    /* VCTL: subfn en [12:11], kv en [10:9] cuando aplica. */
    if (strcmp(p[0], "login") == 0)  return (uint16_t)(5u << 13 | 0u << 11);
    if (strcmp(p[0], "logout") == 0) return (uint16_t)(5u << 13 | 1u << 11);
    if (strcmp(p[0], "pwset") == 0)  return (uint16_t)(5u << 13 | 2u << 11);
    if (strcmp(p[0], "kclr") == 0) {
        bool ok1 = false;
        long kv = (n >= 2) ? llave_num(p[1], &ok1) : 0;
        if (!ok1) { err_cod(texto, "kclr necesita una llave k0..k3"); return 0; }
        return (uint16_t)(5u << 13 | 3u << 11 | (unsigned)kv << 9);
    }

    err_cod(texto, "mnemonico del slot criptografico desconocido");
    return 0;
}

static uint16_t cod_bru(const char *texto, int bundle_actual) {
    char p[8][48];
    int n = trozos(texto, p);
    if (n == 0) return 0;

    if (strcmp(p[0], "nop") == 0) return 0;
    if (strcmp(p[0], "halt") == 0) return (uint16_t)(5u << 13);

    /* El mnemonico trae la condicion: br.eq, jal.al, jr.al ... */
    char base[48], cond[48];
    const char *punto = strchr(p[0], '.');
    if (punto == NULL) {
        memcpy(base, p[0], sizeof(base));
        base[sizeof(base) - 1] = '\0';
        memcpy(cond, "al", 3);
    } else {
        size_t k = (size_t)(punto - p[0]);
        if (k >= sizeof(base)) k = sizeof(base) - 1;
        memcpy(base, p[0], k);
        base[k] = '\0';
        size_t c2 = strlen(punto + 1);
        if (c2 >= sizeof(cond)) c2 = sizeof(cond) - 1;
        memcpy(cond, punto + 1, c2);
        cond[c2] = '\0';
    }
    int c = cond_num(cond);
    if (c < 0) { err_cod(texto, "codigo de condicion desconocido"); return 0; }

    if (strcmp(base, "br") == 0 || strcmp(base, "jal") == 0) {
        /* Tipo C: destino = PC + 16 * (1 + desp), contado en bundles. */
        unsigned op = (strcmp(base, "br") == 0) ? 1u : 2u;
        if (n < 2) { err_cod(texto, "falta la etiqueta de destino"); return 0; }
        int destino = buscar_etiqueta(p[1]);
        if (destino < 0) {
            diag_error("E401", 0, 1, 1,
                       "'%s' no esta en este modulo: lo resuelve el enlazador", p[1]);
            hubo_error = true;
            return 0;
        }
        long desp = (long)destino - (long)bundle_actual - 1;
        if (desp < -512 || desp > 511) {
            err_cod(texto, "el salto excede los 512 bundles del tipo C");
            return 0;
        }
        return (uint16_t)(op << 13 | (unsigned)c << 10 | ((unsigned)desp & 0x3FF));
    }

    if (strcmp(base, "jr") == 0 || strcmp(base, "jalr") == 0) {
        /* Tipo J: el registro va en [8:5], como en todos los formatos cortos. */
        unsigned op = (strcmp(base, "jr") == 0) ? 3u : 4u;
        bool ok = false;
        int rs = (n >= 2) ? reg_num(p[1], &ok) : 0;
        if (!ok) { err_cod(texto, "se esperaba un registro"); return 0; }
        return (uint16_t)(op << 13 | (unsigned)c << 10 | (unsigned)rs << 5);
    }

    err_cod(texto, "mnemonico del BRU desconocido");
    return 0;
}

/* Codifica un bundle en 16 bytes, little-endian por palabras. */
static void codificar_bundle(int b, unsigned char *dest) {
    const Bundle *x = &prog[b];
    uint32_t s0 = x->s[0] ? cod_alu(x->s[0]) : 0;
    uint32_t s1 = x->s[1] ? cod_alu(x->s[1]) : 0;
    uint32_t s2 = x->s[2] ? cod_lsu(x->s[2]) : 0;
    uint16_t s3 = x->s[3] ? cod_crp(x->s[3]) : 0;
    uint16_t s4 = x->s[4] ? cod_bru(x->s[4], b) : 0;

    /* S3 y S4 comparten la palabra baja: S3 en 31:16 y S4 en 15:0. */
    uint32_t bajo = ((uint32_t)s3 << 16) | (uint32_t)s4;
    const uint32_t palabras[4] = { bajo, s2, s1, s0 };
    for (int w = 0; w < 4; w++) {
        uint32_t v = palabras[w];
        dest[w * 4 + 0] = (unsigned char)(v & 0xFF);
        dest[w * 4 + 1] = (unsigned char)((v >> 8) & 0xFF);
        dest[w * 4 + 2] = (unsigned char)((v >> 16) & 0xFF);
        dest[w * 4 + 3] = (unsigned char)((v >> 24) & 0xFF);
    }
}

bool codegen_print_packages(TACList *tac, SymbolTable *st, FILE *out) {
    (void)st;
    if (tac == NULL || out == NULL) return false;
    sal = NULL;
    bool ok = construir_programa(tac);
    if (!ok) {
        liberar_todo();
        return false;
    }
    if (buscar_etiqueta("__inicio") < 0) {
        diag_error("E405", 0, 1, 1,
                   "no hay 'principale': no se pueden mostrar paquetes ejecutables");
        liberar_todo();
        return false;
    }

    fprintf(out, "Direccion  Linea  Col  S0                       S1         S2                     S3              S4             Bytes\n");
    unsigned char bytes[16];
    for (int b = 0; b < n_bundles; b++) {
        codificar_bundle(b, bytes);
        /* El prologo y el arranque no vienen de ninguna linea del fuente. */
        char lin[8], col[8];
        if (prog[b].source_line > 0) snprintf(lin, sizeof(lin), "%d", prog[b].source_line);
        else                         snprintf(lin, sizeof(lin), "-");
        if (prog[b].source_col > 0)  snprintf(col, sizeof(col), "%d", prog[b].source_col);
        else                         snprintf(col, sizeof(col), "-");
        fprintf(out, "0x%04X     %-5s  %-3s  %-26s | %-10s | %-22s | %-16s | %-16s ",
                b * 16,
                lin,
                col,
                prog[b].s[0] ? prog[b].s[0] : "-",
                prog[b].s[1] ? prog[b].s[1] : "-",
                prog[b].s[2] ? prog[b].s[2] : "-",
                prog[b].s[3] ? prog[b].s[3] : "-",
                prog[b].s[4] ? prog[b].s[4] : "-");
        for (int i = 0; i < (int)sizeof(bytes); i++) fprintf(out, "%02X", bytes[i]);
        fputc('\n', out);
    }
    ok = !hubo_error && diag_errores() == 0 && !ferror(out);
    liberar_todo();
    return ok;
}

static void poner32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

bool codegen_emitir_binario(TACList *tac, SymbolTable *st, FILE *out) {
    (void)st;
    if (tac == NULL || out == NULL) return false;
    sal = NULL;
    bool ok = construir_programa(tac);

    int entrada = buscar_etiqueta("__inicio");
    if (entrada < 0) {
        diag_error("E405", 0, 1, 1,
                   "no hay 'principale': un modulo de biblioteca no puede ser "
                   "el punto de entrada de un ejecutable");
        liberar_todo();
        return false;
    }

    /* Codigo */
    unsigned char *codigo = malloc((size_t)n_bundles * 16 + 16);
    if (codigo == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    for (int b = 0; b < n_bundles; b++) codificar_bundle(b, codigo + (size_t)b * 16);

    /* Suma de verificacion sobre lo que de verdad va en el archivo. */
    uint32_t suma = 0;
    for (long k = 0; k < (long)n_bundles * 16; k++) suma = suma * 31u + codigo[k];
    for (int k = 0; k < datos_init; k++) suma = suma * 31u + datos[k];

    /*
     * Encabezado de 48 bytes. Ni el documento de Nova ni el del ISA definian
     * un formato de archivo, asi que este es el que propone el compilador y
     * hay que acordarlo con el cargador de CE 4301:
     *
     *    0  "NOVA"            magia
     *    4  u16 version, u16 reservado
     *    8  u32 n_bundles     bundles de 16 bytes que siguen al encabezado
     *   12  u32 codigo_org    direccion de IMEM donde se carga el codigo
     *   16  u32 entrada       direccion de la primera instruccion
     *   20  u32 datos_org     direccion de DMEM donde empieza la seccion de datos
     *   24  u32 datos_init    bytes inicializados que trae el archivo
     *   28  u32 datos_cero    bytes que el cargador pone en cero a continuacion
     *   32  u32 pila_tope     valor inicial de R14
     *   36  u32 suma          verificacion de codigo + datos inicializados
     *   40  u32 reservado[2]  para el enlazador
     */
    unsigned char cab[48];
    memset(cab, 0, sizeof(cab));
    memcpy(cab, "NOVA", 4);
    cab[4] = 1; cab[5] = 0;                            /* version */
    poner32(cab + 8,  (uint32_t)n_bundles);
    poner32(cab + 12, 0x0000);                         /* .org del codigo en IMEM */
    poner32(cab + 16, (uint32_t)entrada * 16u);        /* punto de entrada */
    poner32(cab + 20, (uint32_t)datos_base);
    poner32(cab + 24, (uint32_t)datos_init);
    poner32(cab + 28, (uint32_t)(datos_largo - datos_init));
    poner32(cab + 32, (uint32_t)CERBERO_PILA_TOPE);
    poner32(cab + 36, suma);

    if (fwrite(cab, 1, sizeof(cab), out) != sizeof(cab)) ok = false;
    if (fwrite(codigo, 1, (size_t)n_bundles * 16, out) != (size_t)n_bundles * 16) ok = false;
    if (datos_init > 0 &&
        fwrite(datos, 1, (size_t)datos_init, out) != (size_t)datos_init) ok = false;

    free(codigo);
    bool limpio = ok && !hubo_error;
    liberar_todo();
    return limpio;
}
