/*
 * Generacion de ensamblador VLIW para CERBERO.
 *
 * Todo lo que este archivo emite esta tomado de la especificacion del ISA:
 * los mnemonicos, el slot al que pertenece cada uno, los codigos de
 * condicion, la convencion de registros y las dos reglas temporales.
 *
 *   Registros (convencion acordada con CE 4301)
 *     R0, R1   scratch reservados, tambien usados por el par Feistel P0
 *     R2 - R5  registros asignables; clobbered por division y Feistel
 *     R6 - R9  argumentos 1 a 4; R6 lleva tambien el valor de retorno
 *     R10, R11 registros asignables
 *     R12, R13 reservados para punteros y temporales del backend
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
 *     [ 4k+L              .. +4T-4  ]  temporales derramados del TAC
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
#include <stdint.h>
#include "codegen.h"
#include "diag.h"
#include "vivacidad.h"

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
#define R_PTR    12    /* scratch reservado para punteros que cruzan CRP */
#define RA      0      /* scratch; no forma parte del pool asignable */
#define RB      1      /* scratch; no forma parte del pool asignable */
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
typedef struct {
    char *s[5];
    int source_line, source_col;
    unsigned int lecturas[5], escrituras[5];
    unsigned char planificable[5], escribe_flags[5];
    unsigned char delay_seguro[5];
    char razon_nop[5][112];
} Bundle;
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
static char *paquete_pendiente[5];
static unsigned int paquete_lecturas = 0;
static unsigned int paquete_escrituras = 0;
static unsigned int paquete_lecturas_slot[5];
static unsigned int paquete_escrituras_slot[5];
static unsigned char paquete_planificable[5];
static unsigned char paquete_escribe_flags[5];
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
#define MAX_FUNCS 256
static char **temps;
static int n_temps = 0;
static size_t cap_temps = 0;
static int *temp_primero;
static int *temp_ultimo;
static int *temp_def_pos;
static int *temp_slot;
static int *temp_reg;
static bool *temp_tiene_constante;
static int *temp_valor_constante;
static bool *temp_solo_indice_fijo;
static size_t *tabla_temps;
static size_t cap_tabla_temps = 0;
static int n_temp_slots = 0;
static bool asignacion_habilitada = true;
static bool medicion_referencia = false;
static bool ejecutable_requiere_imem = false;
static int instrucciones_reordenadas;
static int temporales_asignados_registro;
static int renombradas;
static int temporales_derramados;
static int dependencias_war;
static int dependencias_waw;
static int cargas_temporales_emitidas = 0;
static int stores_temporales_emitidos = 0;

typedef struct {
    const char *funcion;
    int cargas;
    int stores;
} AccesosTemporales;

static AccesosTemporales accesos_base[MAX_FUNCS];
static AccesosTemporales accesos_asignados[MAX_FUNCS];
static int n_accesos_base = 0;
static int n_accesos_asignados = 0;
static GrafoFlujo *asig_cfg = NULL;
static Vivacidad *asig_viv = NULL;
static FILE *asig_salida = NULL;

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
static int tac_posicion_actual = 0;
static TACInst *tac_actual = NULL;

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
    memset(b, 0, sizeof(*b));
    b->source_line = linea_fuente_actual;
    b->source_col  = columna_fuente_actual;
    b->s[0] = dup_o_nulo(s0); b->s[1] = dup_o_nulo(s1);
    b->s[2] = dup_o_nulo(s2); b->s[3] = dup_o_nulo(s3);
    b->s[4] = dup_o_nulo(s4);
}

static unsigned int mascara_registro(int registro) {
    return registro >= 0 && registro < 16
        ? 1u << (unsigned int)registro
        : 0u;
}

static void paquete_descartar(void) {
    for (int s = 0; s < 5; s++) {
        free(paquete_pendiente[s]);
        paquete_pendiente[s] = NULL;
        paquete_lecturas_slot[s] = 0;
        paquete_escrituras_slot[s] = 0;
        paquete_planificable[s] = 0;
        paquete_escribe_flags[s] = 0;
    }
    paquete_lecturas = 0;
    paquete_escrituras = 0;
}

static void paquete_vaciar(void) {
    bool hay_instrucciones = false;
    for (int s = 0; s < 5; s++)
        if (paquete_pendiente[s] != NULL) hay_instrucciones = true;
    if (!hay_instrucciones) return;

    bundle(paquete_pendiente[0], paquete_pendiente[1],
           paquete_pendiente[2], paquete_pendiente[3],
           paquete_pendiente[4]);
    Bundle *b = &prog[n_bundles - 1];
    for (int s = 0; s < 5; s++) {
        b->lecturas[s] = paquete_lecturas_slot[s];
        b->escrituras[s] = paquete_escrituras_slot[s];
        b->planificable[s] = paquete_planificable[s];
        b->escribe_flags[s] = paquete_escribe_flags[s];
    }
    paquete_descartar();
    ciclo++;
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

/*
 * Instantanea del tamano del programa, tomada junto con la de etiquetas y por
 * la misma razon: despues de liberar_todo() ya no hay bundles que contar.
 */
static CodegenEstadisticas estad_copia;

static void guardar_estadisticas(void) {
    memset(&estad_copia, 0, sizeof(estad_copia));
    estad_copia.bundles = n_bundles;
    estad_copia.instrucciones_reordenadas = instrucciones_reordenadas;
    estad_copia.temporales_asignados_registro =
        temporales_asignados_registro;
    estad_copia.renombradas = renombradas;
    estad_copia.temporales_derramados = temporales_derramados;
    estad_copia.dependencias_war = dependencias_war;
    estad_copia.dependencias_waw = dependencias_waw;
    for (int b = 0; b < n_bundles; b++) {
        int usados = 0;
        for (int s = 0; s < 5; s++) {
            if (prog[b].s[s] != NULL) {
                usados++;
            } else if (strstr(prog[b].razon_nop[s], "dependencia WAR") != NULL) {
                estad_copia.nops_war++;
            } else if (strstr(prog[b].razon_nop[s], "dependencia WAW") != NULL) {
                estad_copia.nops_waw++;
            }
        }
        estad_copia.slots_usados += usados;
        if (usados == 0) estad_copia.bundles_vacios++;
    }
}

int codegen_estadisticas(CodegenEstadisticas *out) {
    if (out != NULL) *out = estad_copia;
    return estad_copia.bundles;
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
    if (ciclo < c) paquete_vaciar();
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

    unsigned int lecturas = mascara_registro(u1) | mascara_registro(u2);
    unsigned int escrituras = mascara_registro(rd);
    if (paquete_pendiente[slot] != NULL ||
        (escrituras & (paquete_lecturas | paquete_escrituras)) != 0 ||
        (lecturas & paquete_escrituras) != 0) {
        paquete_vaciar();
    }

    paquete_pendiente[slot] = dup_o_nulo(texto);
    paquete_lecturas |= lecturas;
    paquete_escrituras |= escrituras;
    paquete_lecturas_slot[slot] = lecturas;
    paquete_escrituras_slot[slot] = escrituras;
    paquete_planificable[slot] = 1;
    if (rd >= 0) {
        listo[rd] = ciclo + 3;
        if (rd == cache_reg) cache_limpiar();
    }
}

/* Espera a que no quede nada en vuelo. Se usa antes de cada salto y de cada
 * etiqueta, para que ningun valor a medio camino cruce un borde del flujo. */
static void barrera(void) {
    paquete_vaciar();
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
        emitir(S_ALU0, t, RB, -1, -1);
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
    emitir(S_ALU0, t, -1, a, b);
    paquete_escribe_flags[S_ALU0] = 1;
    listo_flags = ciclo + 3;
}

static void cmp_inm(int a, long v) {
    char t[48];
    snprintf(t, sizeof(t), "cmpi r%d, #%ld", a, v);
    emitir(S_ALU0, t, -1, a, -1);
    paquete_escribe_flags[S_ALU0] = 1;
    listo_flags = ciclo + 3;
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

static void error_memoria_temporales(void) {
    fprintf(stderr, "novac: sin memoria\n");
    exit(3);
}

static void *reallocar_temporales(void *memoria, size_t bytes) {
    void *nuevo = realloc(memoria, bytes);
    if (nuevo == NULL) error_memoria_temporales();
    return nuevo;
}

static uint64_t hash_nombre_temp(const char *nombre) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const unsigned char *p = (const unsigned char *)nombre; *p; p++) {
        hash ^= *p;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static void redimensionar_tabla_temps(size_t capacidad) {
    size_t *nueva = calloc(capacidad, sizeof(*nueva));
    if (nueva == NULL) error_memoria_temporales();

    for (int i = 0; i < n_temps; i++) {
        size_t pos = (size_t)hash_nombre_temp(temps[i]) & (capacidad - 1);
        while (nueva[pos] != 0) pos = (pos + 1) & (capacidad - 1);
        nueva[pos] = (size_t)i + 1;
    }

    free(tabla_temps);
    tabla_temps = nueva;
    cap_tabla_temps = capacidad;
}

static void asegurar_tabla_temps(size_t necesarios) {
    if (cap_tabla_temps == 0) redimensionar_tabla_temps(64);
    while (necesarios >= cap_tabla_temps - cap_tabla_temps / 4) {
        if (cap_tabla_temps > SIZE_MAX / 2)
            error_memoria_temporales();
        redimensionar_tabla_temps(cap_tabla_temps * 2);
    }
}

static void asegurar_capacidad_temps(size_t necesarios) {
    if (necesarios <= cap_temps) return;

    size_t nueva = cap_temps == 0 ? 64 : cap_temps;
    while (nueva < necesarios) {
        if (nueva > (size_t)INT_MAX / 2) {
            nueva = (size_t)INT_MAX;
            break;
        }
        nueva *= 2;
    }
    if (nueva < necesarios ||
        nueva > SIZE_MAX / sizeof(*temps) ||
        nueva > SIZE_MAX / sizeof(*temp_primero) ||
        nueva > SIZE_MAX / sizeof(*temp_tiene_constante))
        error_memoria_temporales();

    temps = reallocar_temporales(temps, nueva * sizeof(*temps));
    temp_primero = reallocar_temporales(temp_primero,
                                        nueva * sizeof(*temp_primero));
    temp_ultimo = reallocar_temporales(temp_ultimo,
                                       nueva * sizeof(*temp_ultimo));
    temp_def_pos = reallocar_temporales(temp_def_pos,
                                        nueva * sizeof(*temp_def_pos));
    temp_slot = reallocar_temporales(temp_slot, nueva * sizeof(*temp_slot));
    temp_reg = reallocar_temporales(temp_reg, nueva * sizeof(*temp_reg));
    temp_tiene_constante = reallocar_temporales(
        temp_tiene_constante, nueva * sizeof(*temp_tiene_constante));
    temp_valor_constante = reallocar_temporales(
        temp_valor_constante, nueva * sizeof(*temp_valor_constante));
    temp_solo_indice_fijo = reallocar_temporales(
        temp_solo_indice_fijo, nueva * sizeof(*temp_solo_indice_fijo));
    cap_temps = nueva;
}

static int indice_temp(const char *nombre) {
    if (nombre == NULL) return -1;
    asegurar_tabla_temps((size_t)n_temps + 1);

    size_t pos = (size_t)hash_nombre_temp(nombre) & (cap_tabla_temps - 1);
    while (tabla_temps[pos] != 0) {
        int indice = (int)(tabla_temps[pos] - 1);
        if (strcmp(temps[indice], nombre) == 0) return indice;
        pos = (pos + 1) & (cap_tabla_temps - 1);
    }

    if (n_temps == INT_MAX) error_memoria_temporales();
    asegurar_capacidad_temps((size_t)n_temps + 1);
    asegurar_tabla_temps((size_t)n_temps + 1);
    pos = (size_t)hash_nombre_temp(nombre) & (cap_tabla_temps - 1);
    while (tabla_temps[pos] != 0)
        pos = (pos + 1) & (cap_tabla_temps - 1);

    int indice = n_temps++;
    temps[indice] = (char *)nombre;
    temp_primero[indice] = INT_MAX;
    temp_ultimo[indice] = -1;
    temp_def_pos[indice] = -1;
    temp_slot[indice] = -1;
    temp_reg[indice] = -1;
    temp_tiene_constante[indice] = false;
    temp_valor_constante[indice] = 0;
    temp_solo_indice_fijo[indice] = true;
    tabla_temps[pos] = (size_t)indice + 1;
    return indice;
}

static bool shift_constante_inmediato(const char *nombre, int *valor) {
    if (nombre == NULL || !tac_es_temporal(nombre)) return false;
    int t = indice_temp(nombre);
    if (t < 0 || !temp_tiene_constante[t] ||
        temp_valor_constante[t] < 0 || temp_valor_constante[t] > 31)
        return false;
    if (valor != NULL) *valor = temp_valor_constante[t];
    return true;
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
        if (indice < 0) return -1;
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

/* Un indice constante y valido en un arreglo local es un desplazamiento fijo
 * respecto de R14; no hace falta calcular la direccion en tiempo de ejecucion. */
static bool store_fijo(const TACInst *i, int *desplazamiento) {
    if (i == NULL || i->op != TAC_STORE || i->result == NULL ||
        i->arg1 == NULL)
        return false;
    const TACSimbolo *s = sim_de(i->result);
    if (s == NULL || s->es_param || s->dims <= 0) return false;
    int t = indice_temp(i->arg1);
    if (t < 0 || !temp_tiene_constante[t]) return false;
    int indice = temp_valor_constante[t];
    int elementos = s->size_bytes / 4;
    if (indice < 0 || indice >= elementos) return false;
    if (desplazamiento != NULL)
        *desplazamiento = desplazamiento_simbolo(s) + 4 * indice;
    return true;
}

static const VivacidadFuncion *funcion_viva_actual(void) {
    if (asig_viv == NULL) return NULL;
    for (int f = 0; f < asig_viv->n_funciones; f++)
        if (strcmp(asig_viv->funciones[f].fn->nombre, func) == 0)
            return &asig_viv->funciones[f];
    return NULL;
}

static int conjunto_contiene(const unsigned *conjunto, int indice) {
    return conjunto != NULL &&
           ((conjunto[indice / 32] >> (indice % 32)) & 1u) != 0;
}

static int bloque_de_posicion(const VivacidadFuncion *vf, int posicion) {
    int inicio = 0;
    for (int b = 0; b < vf->fn->n_bloques; b++) {
        int fin = inicio + vf->fn->bloques[b].n_inst;
        if (posicion >= inicio && posicion < fin) return b;
        inicio = fin;
    }
    return -1;
}

static void asignacion_iniciar(TACList *tac) {
    if (asig_viv != NULL) viv_liberar(asig_viv);
    if (asig_cfg != NULL) cfg_liberar(asig_cfg);
    asig_cfg = cfg_construir(tac);
    asig_viv = viv_analizar(asig_cfg, tac);
}

static void asignacion_terminar(void) {
    viv_liberar(asig_viv);
    cfg_liberar(asig_cfg);
    asig_viv = NULL;
    asig_cfg = NULL;
}

static void registrar_accesos_temporales(AccesosTemporales *tabla, int *n,
                                        const char *nombre) {
    int indice = 0;
    while (indice < *n && strcmp(tabla[indice].funcion, nombre) != 0)
        indice++;
    if (indice == *n) {
        if (*n >= MAX_FUNCS) return;
        tabla[indice].funcion = nombre;
        (*n)++;
    }
    tabla[indice].cargas = cargas_temporales_emitidas;
    tabla[indice].stores = stores_temporales_emitidos;
}

static const AccesosTemporales *buscar_accesos_temporales(
    const AccesosTemporales *tabla, int n, const char *nombre) {
    for (int i = 0; i < n; i++)
        if (strcmp(tabla[i].funcion, nombre) == 0) return &tabla[i];
    return NULL;
}

static unsigned registros_prohibidos_en_intervalo(TACInst *desde,
                                                   int inicio, int fin) {
    unsigned prohibidos = 0;
    int posicion = 0;
    for (TACInst *i = desde; i != NULL && i->op != TAC_FUNC_END;
         i = i->next, posicion++) {
        if (posicion <= inicio || posicion >= fin) continue;
        if (i->op == TAC_CALL || i->op == TAC_DIV || i->op == TAC_MOD)
            return 0x0ffcu;
        if (i->op == TAC_PARAM && i->aux >= 1 && i->aux <= 4)
            prohibidos |= 1u << (R_ARG0 + i->aux - 1);
        if (i->op == TAC_FEISTEL || i->op == TAC_FEISTEL_DECRYPT)
            for (int r = 2; r <= 5; r++) prohibidos |= 1u << r;
    }
    return prohibidos;
}

static int temporales_solapan(int a, int b) {
    return temp_primero[a] <= temp_ultimo[b] &&
           temp_primero[b] <= temp_ultimo[a];
}

static void asignacion_imprimir_funcion(void) {
    if (asig_salida == NULL) return;
    int spills = 0;
    for (int t = 0; t < n_temps; t++) {
        if (temp_reg[t] < 0 && temp_slot[t] >= 0) {
            spills++;
        }
    }
    fprintf(asig_salida, "Funcion %s: %d temporales, %d derramados\n",
            func, n_temps, spills);
    for (int t = 0; t < n_temps; t++) {
        fprintf(asig_salida, "  %s [%d,%d] -> ",
                temps[t], temp_primero[t], temp_ultimo[t]);
        if (temp_tiene_constante[t] && temp_solo_indice_fijo[t]) {
            fputs("constante de indice (sin registro ni slot)\n", asig_salida);
        } else if (temp_reg[t] >= 0) {
            fprintf(asig_salida, "R%d\n", temp_reg[t]);
        } else if (temp_slot[t] >= 0) {
            fprintf(asig_salida, "spill slot %d\n", temp_slot[t]);
        } else {
            fputs("sin ubicacion\n", asig_salida);
        }
    }
}

static bool siguiente_uso_en_ra(const char *nombre) {
    if (tac_actual == NULL || tac_actual->next == NULL) return false;
    TACInst *siguiente = tac_actual->next;
    if (siguiente->op == TAC_STORE && siguiente->arg2 != NULL &&
        strcmp(siguiente->arg2, nombre) == 0 && store_fijo(siguiente, NULL))
        return true;
    if (siguiente->arg1 == NULL ||
        strcmp(siguiente->arg1, nombre) != 0)
        return false;
    switch (siguiente->op) {
        case TAC_ASSIGN: case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR: case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR:
        case TAC_CHECK: case TAC_IF_FALSE: case TAC_IF_TRUE:
        case TAC_PARAM: case TAC_RET_VAL:
            return true;
        default:
            return false;
    }
}

/* Carga el valor del operando en un registro. */
static void cargar(int rd, const char *nombre) {
    if (tac_es_temporal(nombre)) {
        int t = indice_temp(nombre);
        if (t >= 0 && temp_reg[t] >= 0) {
            if (temp_reg[t] != rd) mover(rd, temp_reg[t]);
            return;
        }
    }
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
                   nombre ? tac_nombre_fuente(nombre) : "(nulo)",
                   func ? func : "?");
        hubo_error = true;
        cargar_const(rd, 0);
        return;
    }
    lw(rd, R_SP, d);
    if (tac_es_temporal(nombre)) cargas_temporales_emitidas++;
}

static void guardar(int rfuente, const char *nombre) {
    if (tac_es_temporal(nombre)) {
        int t = indice_temp(nombre);
        if (t >= 0 && temp_reg[t] >= 0) {
            if (temp_ultimo[t] <= tac_posicion_actual) return;
            if (temp_reg[t] != rfuente) mover(temp_reg[t], rfuente);
            cache_reg = temp_reg[t];
            cache_nombre = nombre;
            return;
        }
    }
    int d = disp_de(nombre);
    if (d < 0) {
        diag_error("E410", 0, 1, 1, "la fase 4 no pudo ubicar '%s' en '%s'",
                   nombre ? tac_nombre_fuente(nombre) : "(nulo)",
                   func ? func : "?");
        hubo_error = true;
        return;
    }
    if (tac_es_temporal(nombre)) {
        int t = indice_temp(nombre);
        if (t >= 0 && temp_ultimo[t] <= tac_posicion_actual) return;
        if (t >= 0 && temp_ultimo[t] == tac_posicion_actual + 1 &&
            siguiente_uso_en_ra(nombre)) {
            cache_reg = rfuente;
            cache_nombre = nombre;
            return;
        }
    }
    sw(rfuente, R_SP, d);
    if (tac_es_temporal(nombre)) stores_temporales_emitidos++;
    /* Este registro queda con el valor de este nombre. */
    cache_reg = rfuente;
    cache_nombre = nombre;
}

static int registro_operando(const char *nombre, int scratch) {
    if (tac_es_temporal(nombre)) {
        int t = indice_temp(nombre);
        if (t >= 0 && temp_reg[t] >= 0) return temp_reg[t];
    }
    cargar(scratch, nombre);
    return scratch;
}

static int registro_destino(const char *nombre, int scratch) {
    if (tac_es_temporal(nombre)) {
        int t = indice_temp(nombre);
        if (t >= 0 && temp_reg[t] >= 0) return temp_reg[t];
    }
    return scratch;
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
        diag_error("E410", 0, 1, 1, "arreglo '%s' no ubicado",
                   nombre ? tac_nombre_fuente(nombre) : "?");
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
    int rs1 = registro_operando(i->arg1, RA);
    int rs2 = registro_operando(i->arg2, RB);
    int rd = registro_destino(i->result, RA);
    if (inv) cmp_reg(rs2, rs1); else cmp_reg(rs1, rs2);

    char l_si[32], l_fin[32];
    static int n = 0;
    snprintf(l_si, sizeof(l_si), "__c%d_si", n);
    snprintf(l_fin, sizeof(l_fin), "__c%d_fin", n);
    n++;

    char br[48];
    snprintf(br, sizeof(br), "br.%s %s", c, l_si);
    hasta(listo_flags);
    salto(br, -1);
    cargar_const(rd, 0);
    char j[48];
    snprintf(j, sizeof(j), "br.al %s", l_fin);
    salto(j, -1);
    etiqueta(l_si);
    cargar_const(rd, 1);
    etiqueta(l_fin);
    guardar(rd, i->result);
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
            {
                int t = indice_temp(i->result);
                if (t >= 0 && temp_tiene_constante[t] &&
                    temp_solo_indice_fijo[t])
                    break;
            }
            {
                int rd = registro_destino(i->result, RA);
                cargar_const(rd, i->valor);
                guardar(rd, i->result);
            }
            break;

        case TAC_STR:
            {
                int rd = registro_destino(i->result, RA);
                cargar_etiqueta(rd, i->arg1);
                guardar(rd, i->result);
            }
            break;

        case TAC_ASSIGN:
            {
                int rs = registro_operando(i->arg1, RA);
                int rd = registro_destino(i->result, RA);
                if (rd != rs) mover(rd, rs);
                guardar(rd, i->result);
            }
            break;

        case TAC_ADD: case TAC_SUB: case TAC_MUL:
        case TAC_AND: case TAC_OR:  case TAC_XOR:
        case TAC_SHL: case TAC_SHR: case TAC_USHR: {
            if (i->op == TAC_SHL) {
                int shift;
                if (shift_constante_inmediato(i->arg2, &shift)) {
                    int rs1 = registro_operando(i->arg1, RA);
                    int rd = registro_destino(i->result, RA);
                    alu_inm("slli", rd, rs1, shift);
                    guardar(rd, i->result);
                    break;
                }
            }
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
            int rs1 = registro_operando(i->arg1, RA);
            int rs2 = registro_operando(i->arg2, RB);
            int rd = registro_destino(i->result, RA);
            alu3(op, rd, rs1, rs2);
            guardar(rd, i->result);
            break;
        }

        case TAC_DIV: case TAC_MOD:
            /* CERBERO no tiene division: se resuelve con una subrutina del
             * soporte de ejecucion, que deja el cociente en R6 y el resto
             * en R7. */
            usa_div = true;
            cargar(RA, i->arg1);
            cargar(RB, i->arg2);
            mover(R_ARG0, RA);
            mover(R_ARG0 + 1, RB);
            salto("jal.al __nova_div32", -1);
            for (int r = 0; r < 16; r++) listo[r] = ciclo;
            guardar(i->op == TAC_DIV ? R_ARG0 : R_ARG0 + 1, i->result);
            break;

        case TAC_EQ: case TAC_NE: case TAC_LT:
        case TAC_LE: case TAC_GT: case TAC_GE:
            emitir_comparacion(i);
            break;

        case TAC_NEG:
            {
                int rs = registro_operando(i->arg1, RA);
                int rd = registro_destino(i->result, RA);
                snprintf(buf, sizeof(buf), "neg r%d, r%d", rd, rs);
                emitir(S_ALU0, buf, rd, rs, -1);
                guardar(rd, i->result);
            }
            break;

        case TAC_BITNOT:
            {
                int rs = registro_operando(i->arg1, RA);
                int rd = registro_destino(i->result, RA);
                snprintf(buf, sizeof(buf), "not r%d, r%d", rd, rs);
                emitir(S_ALU0, buf, rd, rs, -1);
                guardar(rd, i->result);
            }
            break;

        case TAC_NOT: {
            /* non a  es  (a == 0) */
            int rs = registro_operando(i->arg1, RA);
            int rd = registro_destino(i->result, RA);
            cmp_inm(rs, 0);
            static int n = 0;
            char l_si[32], l_fin[32];
            snprintf(l_si, sizeof(l_si), "__n%d_si", n);
            snprintf(l_fin, sizeof(l_fin), "__n%d_fin", n);
            n++;
            snprintf(buf, sizeof(buf), "br.eq %s", l_si);
            hasta(listo_flags);
            salto(buf, -1);
            cargar_const(rd, 0);
            snprintf(buf, sizeof(buf), "br.al %s", l_fin);
            salto(buf, -1);
            etiqueta(l_si);
            cargar_const(rd, 1);
            etiqueta(l_fin);
            guardar(rd, i->result);
            break;
        }

        case TAC_LOAD:
            emitir_direccion_elemento(i->arg1, i->arg2);
            {
                int rd = registro_destino(i->result, RA);
                lw(rd, RB, 0);
                guardar(rd, i->result);
            }
            break;

        case TAC_STORE:
            {
                int desplazamiento;
                if (store_fijo(i, &desplazamiento)) {
                    int rdato = registro_operando(i->arg2, RA);
                    sw(rdato, R_SP, desplazamiento);
                    break;
                }
            }
            emitir_direccion_elemento(i->result, i->arg1);
            {
                int rdato = registro_operando(i->arg2, RA);
                sw(rdato, RB, 0);
            }
            break;

        case TAC_ADDR:
            direccion_base(RA, i->arg1);
            guardar(RA, i->result);
            break;

        case TAC_LEN: {
            int rd = registro_destino(i->result, RA);
            const TACSimbolo *s = sim_de(i->arg1);
            if (s != NULL && s->es_param && s->dims > 0) {
                /* El descriptor lleva un tamano por dimension. */
                int d = disp_de(i->arg1);
                lw(rd, R_SP, d + 4 * (1 + i->aux));
            } else if (s != NULL && s->dims > 0) {
                cargar_const(rd, i->aux == 0 ? s->filas : s->cols);
            } else {
                /* textus: la primera palabra del literal es su longitud. */
                cargar(RB, i->arg1);
                lw(rd, RB, 0);
            }
            guardar(rd, i->result);
            break;
        }

        case TAC_CHECK: {
            /* La comparacion sin signo atrapa tambien los indices negativos:
             * como entero sin signo quedan por encima del limite. */
            static int n = 0;
            char l_ok[32];
            snprintf(l_ok, sizeof(l_ok), "__rango%d_ok", n++);
            int rs1 = registro_operando(i->arg1, RA);
            int rs2 = registro_operando(i->arg2, RB);
            cmp_reg(rs1, rs2);
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
            cmp_inm(registro_operando(i->arg1, RA), 0);
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
                cmp_inm(registro_operando(i->arg1, RA), 0);
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
            paquete_escribe_flags[S_CRP] = 1;
            listo_flags = ciclo + 3;
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
            cargar(R_PTR, i->arg1);
            lw(0, R_PTR, 0);
            lw(1, R_PTR, 4);
            snprintf(buf, sizeof(buf), "%s p0, k%ld, #%d",
                     i->op == TAC_FEISTEL ? "f4e" : "f4d",
                     i->valor, i->aux);
            emitir(S_CRP, buf, 0, 0, 1);
            paquete_escrituras |= mascara_registro(1);
            paquete_escrituras_slot[S_CRP] |= mascara_registro(1);
            listo[1] = listo[0];
            sw(0, R_PTR, 0);
            sw(1, R_PTR, 4);
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
    if (cap_tabla_temps != 0)
        memset(tabla_temps, 0, cap_tabla_temps * sizeof(*tabla_temps));
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
            if (t < 0) return;
            if (temp_def_pos[t] < 0) temp_def_pos[t] = posicion;
            temp_tiene_constante[t] = i->op == TAC_CONST;
            if (temp_tiene_constante[t])
                temp_valor_constante[t] = i->valor;
            if (temp_primero[t] > posicion) temp_primero[t] = posicion;
            if (temp_ultimo[t] < posicion) temp_ultimo[t] = posicion;
        }
        const char *ops[2] = {i->arg1, i->arg2};
        for (int k = 0; k < 2; k++) {
            if (ops[k] == NULL || !tac_es_temporal(ops[k])) continue;
            int t = indice_temp(ops[k]);
            if (t < 0) return;
            if (temp_primero[t] > posicion) temp_primero[t] = posicion;
            if (temp_ultimo[t] < posicion) temp_ultimo[t] = posicion;
        }
    }

    for (TACInst *i = desde; i != NULL; i = i->next) {
        if (i->op == TAC_FUNC_END) break;
        const char *ops[2] = {i->arg1, i->arg2};
        for (int k = 0; k < 2; k++) {
            if (ops[k] == NULL || !tac_es_temporal(ops[k])) continue;
            int t = indice_temp(ops[k]);
            if (t < 0) return;
            if (!(i->op == TAC_STORE && k == 0 && store_fijo(i, NULL)) &&
                !(i->op == TAC_SHL && k == 1 &&
                  shift_constante_inmediato(ops[k], NULL)))
                temp_solo_indice_fijo[t] = false;
        }
    }

    /*
     * Extiende cada intervalo hasta los bordes de bloque donde la vivacidad
     * demuestra que el valor cruza el bloque. El intervalo lineal resultante
     * es conservador ante saltos y ciclos.
     */
    const VivacidadFuncion *vf = funcion_viva_actual();
    if (vf != NULL && vf->vivo_ent != NULL && vf->vivo_sal != NULL) {
        int inicio_bloque = 0;
        for (int b = 0; b < vf->fn->n_bloques; b++) {
            const Bloque *bloque = &vf->fn->bloques[b];
            int fin_bloque = inicio_bloque + bloque->n_inst - 1;
            const unsigned *vivo_ent =
                &vf->vivo_ent[(size_t)b * vf->n_palabras];
            const unsigned *vivo_sal =
                &vf->vivo_sal[(size_t)b * vf->n_palabras];
            for (int n = 0; n < vf->n_nombres; n++) {
                if (!tac_es_temporal(vf->nombres[n])) continue;
                int t = indice_temp(vf->nombres[n]);
                if (t < 0) continue;
                if (conjunto_contiene(vivo_ent, n) &&
                    temp_primero[t] > inicio_bloque)
                    temp_primero[t] = inicio_bloque;
                if (conjunto_contiene(vivo_sal, n) &&
                    temp_ultimo[t] < fin_bloque)
                    temp_ultimo[t] = fin_bloque;
            }
            inicio_bloque += bloque->n_inst;
        }
    }

    /* R6-R9 pertenecen al ABI: argumentos y retorno, no temporales asignados. */
    static const int registros[] = {2, 3, 4, 5, 10, 11};
    int *orden = malloc((size_t)(n_temps > 0 ? n_temps : 1) * sizeof(*orden));
    int *reg_primer_ajuste = malloc(
        (size_t)(n_temps > 0 ? n_temps : 1) * sizeof(*reg_primer_ajuste));
    int ultimo_uso_registro[16];
    for (int r = 0; r < 16; r++) ultimo_uso_registro[r] = -1;
    if (reg_primer_ajuste == NULL) error_memoria_temporales();
    if (orden == NULL) error_memoria_temporales();
    int n_orden = 0;
    for (int t = 0; t < n_temps; t++) {
        temp_reg[t] = -1;
        reg_primer_ajuste[t] = -1;
        if (temp_ultimo[t] < 0) continue;
        int p = n_orden;
        while (p > 0 &&
               temp_primero[orden[p - 1]] > temp_primero[t]) {
            orden[p] = orden[p - 1];
            p--;
        }
        orden[p] = t;
        n_orden++;
    }

    for (int oi = 0; asignacion_habilitada && oi < n_orden; oi++) {
        int t = orden[oi];
        if (temp_tiene_constante[t] && temp_solo_indice_fijo[t]) continue;
        unsigned prohibidos =
            registros_prohibidos_en_intervalo(desde, temp_primero[t],
                                               temp_ultimo[t]);
        int mejor_registro = -1;
        int menor_uso = INT_MAX;
        for (size_t r = 0; r < sizeof(registros) / sizeof(registros[0]); r++) {
            int candidato = registros[r];
            bool ocupado_base = (prohibidos & (1u << candidato)) != 0;
            bool ocupado_actual = ocupado_base;
            for (int prev = 0; prev < oi; prev++) {
                int u = orden[prev];
                if (!temporales_solapan(t, u)) continue;
                if (reg_primer_ajuste[u] == candidato) ocupado_base = true;
                if (temp_reg[u] == candidato) ocupado_actual = true;
            }
            if (!ocupado_base && reg_primer_ajuste[t] < 0)
                reg_primer_ajuste[t] = candidato;
            if (!ocupado_actual &&
                ultimo_uso_registro[candidato] < menor_uso) {
                menor_uso = ultimo_uso_registro[candidato];
                mejor_registro = candidato;
            }
        }
        temp_reg[t] = mejor_registro;
        if (mejor_registro >= 0 &&
            temp_ultimo[t] > ultimo_uso_registro[mejor_registro])
            ultimo_uso_registro[mejor_registro] = temp_ultimo[t];
    }

    for (int oi = 0; oi < n_orden; oi++) {
        int t = orden[oi];
        if (temp_reg[t] < 0) continue;
        temporales_asignados_registro++;
        if (temp_reg[t] == reg_primer_ajuste[t] ||
            reg_primer_ajuste[t] < 0 || vf == NULL ||
            temp_def_pos[t] < 0)
            continue;
        int bloque_t = bloque_de_posicion(vf, temp_def_pos[t]);
        if (bloque_t < 0) continue;
        for (int prev = 0; prev < oi; prev++) {
            int u = orden[prev];
            if (reg_primer_ajuste[u] != reg_primer_ajuste[t] ||
                temp_def_pos[u] < 0 ||
                temp_def_pos[u] >= temp_def_pos[t] ||
                temporales_solapan(t, u))
                continue;
            if (bloque_de_posicion(vf, temp_def_pos[u]) == bloque_t) {
                renombradas++;
                break;
            }
        }
    }

    int *slot_ultimo = malloc(
        (size_t)(n_temps > 0 ? n_temps : 1) * sizeof(*slot_ultimo));
    if (slot_ultimo == NULL) error_memoria_temporales();
    for (int s = 0; s < n_temps; s++) slot_ultimo[s] = -1;
    for (int t = 0; t < n_temps; t++) {
        if (temp_reg[t] >= 0 ||
            (temp_tiene_constante[t] && temp_solo_indice_fijo[t])) {
            temp_slot[t] = -1;
            continue;
        }
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

    if (asignacion_habilitada) {
        for (int t = 0; t < n_temps; t++) {
            if (temp_reg[t] < 0 && temp_slot[t] >= 0)
                temporales_derramados++;
        }
    }

    f_base_loc = 4 * k_salida;
    f_base_tmp = f_base_loc + f_marco_loc;
    f_total = f_base_tmp + 4 * n_temp_slots + (f_guarda_r15 ? 4 : 0);
    if (f_total < 4) f_total = 4;
    asignacion_imprimir_funcion();
    free(slot_ultimo);
    free(reg_primer_ajuste);
    free(orden);
}

/*
 * Suelta los textos de la construccion anterior. Hace falta porque la
 * relajacion de saltos vuelve a construir el programa desde cero, y sin esto
 * los slots, las etiquetas y las notas de la pasada previa quedarian
 * colgando.
 */
static void liberar_construccion(void) {
    paquete_descartar();
    for (int b = 0; b < n_bundles; b++)
        for (int s = 0; s < 5; s++) { free(prog[b].s[s]); prog[b].s[s] = NULL; }
    for (int i = 0; i < n_etqs; i++) free(etqs[i].nombre);
    for (int i = 0; i < n_etqs_dato; i++) free(etqs_dato[i].nombre);
    for (int i = 0; i < n_notas; i++) free(notas[i].texto);
    n_bundles = n_etqs = n_etqs_dato = n_notas = 0;
}

typedef struct {
    const char *texto;
    int slot;
    int linea, columna;
    int orden_programado;
    unsigned int lecturas, escrituras;
    bool escribe_flags;
    bool memoria, memoria_fija, memoria_escritura;
    int direccion_memoria, ciclo_programado;
    unsigned int slots_permitidos;
    int pendientes, primero_entrante, primero_saliente;
    int ciclo_minimo, camino_critico;
    bool delay_seguro;
} InstruccionPlan;

typedef enum {
    DEP_RAW     = 1u << 0,
    DEP_WAR     = 1u << 1,
    DEP_WAW     = 1u << 2,
    DEP_MEMORIA = 1u << 3,
    DEP_FLAGS   = 1u << 4,
    DEP_EFECTO  = 1u << 5
} TipoDependencia;

typedef struct {
    int antes, despues, latencia, registro;
    unsigned int tipos;
    int siguiente_salida, siguiente_entrada;
} DependenciaPlan;

static void datos_memoria(const char *texto, bool *fija, bool *escritura,
                          int *direccion) {
    char operacion[8];
    int registro, desplazamiento, base;
    *fija = false;
    *escritura = false;
    *direccion = 0;
    if (sscanf(texto, "%7s r%d, #%d(r%d)", operacion, &registro,
               &desplazamiento, &base) != 4)
        return;
    if (strcmp(operacion, "lw") != 0 && strcmp(operacion, "sw") != 0)
        return;
    *escritura = strcmp(operacion, "sw") == 0;
    if (base == R_SP) {
        *fija = true;
        *direccion = desplazamiento;
    }
}

static void salida_asegurar(Bundle **salida, int *capacidad, int necesario) {
    if (necesario <= *capacidad) return;
    int nueva = *capacidad ? *capacidad * 2 : 256;
    while (nueva < necesario) nueva *= 2;
    Bundle *p = realloc(*salida, (size_t)nueva * sizeof(Bundle));
    if (p == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }
    memset(p + *capacidad, 0,
           (size_t)(nueva - *capacidad) * sizeof(Bundle));
    *salida = p;
    *capacidad = nueva;
}

static void agregar_dependencia(InstruccionPlan *insts,
                                DependenciaPlan **dependencias,
                                int *n_dependencias, int *cap_dependencias,
                                int antes, int despues, int latencia,
                                unsigned int tipos, int registro) {
    if (*n_dependencias == *cap_dependencias) {
        int nueva = *cap_dependencias ? *cap_dependencias * 2 : 128;
        DependenciaPlan *p = realloc(*dependencias,
                                     (size_t)nueva * sizeof(DependenciaPlan));
        if (p == NULL) {
            fprintf(stderr, "novac: sin memoria\n");
            exit(3);
        }
        *dependencias = p;
        *cap_dependencias = nueva;
    }

    int indice = (*n_dependencias)++;
    (*dependencias)[indice] = (DependenciaPlan){
        antes, despues, latencia, registro, tipos,
        insts[antes].primero_saliente, insts[despues].primero_entrante
    };
    if (tipos & DEP_WAR) dependencias_war++;
    if (tipos & DEP_WAW) dependencias_waw++;
    insts[antes].primero_saliente = indice;
    insts[despues].primero_entrante = indice;
    insts[despues].pendientes++;
}

static void considerar_hazard(int latencia, unsigned int tipo, int registro,
                              int *latencia_maxima, unsigned int *tipos,
                              int *registro_dep) {
    if (latencia > *latencia_maxima) *latencia_maxima = latencia;
    *tipos |= tipo;
    if (registro >= 0 && (*registro_dep < 0 || tipo == DEP_RAW))
        *registro_dep = registro;
}

static void construir_grafo_dependencias(InstruccionPlan *insts, int n_insts,
                                         DependenciaPlan **dependencias,
                                         int *n_dependencias) {
    int capacidad = 0;
    *dependencias = NULL;
    *n_dependencias = 0;
    for (int i = 0; i < n_insts; i++) {
        insts[i].pendientes = 0;
        insts[i].primero_entrante = -1;
        insts[i].primero_saliente = -1;
        insts[i].ciclo_minimo = 0;
        insts[i].ciclo_programado = -1;
        insts[i].camino_critico = 1;
        insts[i].delay_seguro = false;
        insts[i].slots_permitidos = 1u << (unsigned int)insts[i].slot;
        if (insts[i].slot == S_ALU0 && !insts[i].escribe_flags)
            insts[i].slots_permitidos |= 1u << S_ALU1;
    }

    for (int i = 0; i < n_insts; i++) {
        for (int j = i + 1; j < n_insts; j++) {
            int latencia = 0, registro = -1;
            unsigned int tipos = 0;

            for (int r = 0; r < 16; r++) {
                unsigned int bit = mascara_registro(r);
                bool escribe_i = (insts[i].escrituras & bit) != 0;
                bool lee_i = (insts[i].lecturas & bit) != 0;
                bool escribe_j = (insts[j].escrituras & bit) != 0;
                bool lee_j = (insts[j].lecturas & bit) != 0;
                if (escribe_i && lee_j)
                    considerar_hazard(3, DEP_RAW, r, &latencia, &tipos,
                                      &registro);
                if (lee_i && escribe_j)
                    considerar_hazard(1, DEP_WAR, r, &latencia, &tipos,
                                      &registro);
                if (escribe_i && escribe_j)
                    considerar_hazard(1, DEP_WAW, r, &latencia, &tipos,
                                      &registro);
            }

            if (insts[i].memoria && insts[j].memoria) {
                bool depende = !insts[i].memoria_fija ||
                    !insts[j].memoria_fija ||
                    (insts[i].direccion_memoria == insts[j].direccion_memoria &&
                     (insts[i].memoria_escritura ||
                      insts[j].memoria_escritura));
                if (depende)
                    considerar_hazard(1, DEP_MEMORIA, -1, &latencia, &tipos,
                                      &registro);
            }
            if (insts[i].escribe_flags && insts[j].escribe_flags)
                considerar_hazard(1, DEP_FLAGS, -1, &latencia, &tipos,
                                  &registro);
            if (insts[i].slot == S_CRP && insts[j].slot == S_CRP)
                considerar_hazard(1, DEP_EFECTO, -1, &latencia, &tipos,
                                  &registro);

            if (latencia > 0)
                agregar_dependencia(insts, dependencias, n_dependencias,
                                    &capacidad, i, j, latencia, tipos, registro);
        }
    }

    for (int i = n_insts - 1; i >= 0; i--) {
        for (int e = insts[i].primero_saliente; e >= 0;
             e = (*dependencias)[e].siguiente_salida) {
            DependenciaPlan *d = &(*dependencias)[e];
            int longitud = d->latencia + insts[d->despues].camino_critico;
            if (longitud > insts[i].camino_critico)
                insts[i].camino_critico = longitud;
        }
        insts[i].delay_seguro =
            insts[i].primero_saliente < 0 && !insts[i].memoria &&
            !insts[i].escribe_flags && insts[i].escrituras != 0;
    }
}

static const char *nombre_dependencia(unsigned int tipos) {
    if (tipos & DEP_RAW) return "RAW";
    if (tipos & DEP_WAR) return "WAR";
    if (tipos & DEP_WAW) return "WAW";
    if (tipos & DEP_MEMORIA) return "memoria";
    if (tipos & DEP_FLAGS) return "banderas";
    if (tipos & DEP_EFECTO) return "efecto";
    return "dependencia";
}

static void explicar_dependencia(char *destino, size_t capacidad,
                                 const InstruccionPlan *insts,
                                 const DependenciaPlan *d) {
    char dependencia[48];
    if ((d->tipos & (DEP_RAW | DEP_WAR | DEP_WAW)) && d->registro >= 0)
        snprintf(dependencia, sizeof(dependencia), "%s R%d",
                 nombre_dependencia(d->tipos), d->registro);
    else
        snprintf(dependencia, sizeof(dependencia), "%s",
                 nombre_dependencia(d->tipos));
    snprintf(destino, capacidad,
             "dependencia %s: op %d '%s' -> op %d '%s' (%d bundles)",
             dependencia, d->antes + 1, insts[d->antes].texto,
             d->despues + 1, insts[d->despues].texto, d->latencia);
}

static int dependencia_que_bloquea(const InstruccionPlan *insts,
                                   const DependenciaPlan *dependencias,
                                   int objetivo, int ciclo) {
    int mejor = -1, mayor_limite = -1, prioridad = -1;
    for (int e = insts[objetivo].primero_entrante; e >= 0;
         e = dependencias[e].siguiente_entrada) {
        const DependenciaPlan *d = &dependencias[e];
        const InstruccionPlan *anterior = &insts[d->antes];
        int limite = anterior->ciclo_programado < 0
            ? INT_MAX : anterior->ciclo_programado + d->latencia;
        int prioridad_actual = anterior->ciclo_programado < 0
            ? anterior->camino_critico : limite;
        if ((anterior->ciclo_programado < 0 || limite > ciclo) &&
            (prioridad_actual > prioridad ||
             (prioridad_actual == prioridad && limite > mayor_limite))) {
            mejor = e;
            prioridad = prioridad_actual;
            mayor_limite = limite;
        }
    }
    return mejor;
}

static void explicar_nop_slot(char *destino, size_t capacidad,
                              const InstruccionPlan *insts,
                              const DependenciaPlan *dependencias,
                              int n_insts, int ciclo, int slot) {
    int objetivo = -1;
    for (int i = 0; i < n_insts; i++) {
        if (insts[i].ciclo_programado >= 0 ||
            !(insts[i].slots_permitidos & (1u << (unsigned int)slot)))
            continue;
        if (objetivo < 0 ||
            insts[i].camino_critico > insts[objetivo].camino_critico)
            objetivo = i;
    }
    if (objetivo < 0) {
        snprintf(destino, capacidad, "sin operacion pendiente compatible con S%d",
                 slot);
        return;
    }
    int dependencia = dependencia_que_bloquea(insts, dependencias,
                                               objetivo, ciclo);
    if (dependencia >= 0) {
        explicar_dependencia(destino, capacidad, insts,
                             &dependencias[dependencia]);
    } else {
        snprintf(destino, capacidad,
                 "conflicto de recursos/puertos antes de op %d '%s'",
                 objetivo + 1, insts[objetivo].texto);
    }
}

static bool puede_ocupar_slot(const Bundle *bundle_actual,
                              const InstruccionPlan *in, int slot) {
    if (bundle_actual->s[slot] != NULL) return false;
    unsigned int lecturas = 0, escrituras = 0;
    for (int s = 0; s < 5; s++) {
        lecturas |= bundle_actual->lecturas[s];
        escrituras |= bundle_actual->escrituras[s];
    }
    return (in->escrituras & (lecturas | escrituras)) == 0 &&
           (in->lecturas & escrituras) == 0;
}

static bool es_operacion_alu_pura(const char *texto) {
    static const char *const mnemonicos[] = {
        "add", "sub", "mul", "and", "or", "xor", "sll", "srl", "sra",
        "rol", "ror", "mov", "not", "neg", "addi", "subi", "andi",
        "ori", "xori", "slli", "srli", "srai", "roli", "movi", "movh",
        NULL
    };
    char mnem[16];
    if (sscanf(texto, "%15s", mnem) != 1) return false;
    for (int i = 0; mnemonicos[i] != NULL; i++)
        if (strcmp(mnem, mnemonicos[i]) == 0) return true;
    return false;
}

static void razon_relleno(Bundle *bundle, const char *motivo) {
    for (int s = 0; s < 5; s++)
        snprintf(bundle->razon_nop[s], sizeof(bundle->razon_nop[s]), "%s",
                 motivo);
}

static int primer_registro_escrito(unsigned int registros) {
    for (int r = 0; r < 16; r++)
        if (registros & mascara_registro(r)) return r;
    return 0;
}

static void calendarizar_tramo(const Bundle *entrada, int desde, int hasta_i,
                              Bundle **salida, int *n_salida, int *cap_salida,
                              int *mapa) {
    int base = *n_salida;
    for (int b = desde; b < hasta_i; b++) mapa[b] = base;

    int cantidad = 0;
    for (int b = desde; b < hasta_i; b++)
        for (int s = 0; s < 5; s++)
            if (entrada[b].s[s] != NULL && entrada[b].planificable[s])
                cantidad++;
    if (cantidad == 0) {
        mapa[hasta_i] = base;
        return;
    }

    InstruccionPlan *insts = calloc((size_t)cantidad, sizeof(InstruccionPlan));
    if (insts == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }
    int n_insts = 0;
    for (int b = desde; b < hasta_i; b++) {
        for (int s = 0; s < 5; s++) {
            if (entrada[b].s[s] == NULL || !entrada[b].planificable[s]) continue;
            insts[n_insts] = (InstruccionPlan){
                .texto = entrada[b].s[s],
                .slot = s,
                .linea = entrada[b].source_line,
                .columna = entrada[b].source_col,
                .orden_programado = -1,
                .lecturas = entrada[b].lecturas[s],
                .escrituras = entrada[b].escrituras[s],
                .escribe_flags = entrada[b].escribe_flags[s] != 0,
                .memoria = s == S_LSU,
                .ciclo_programado = -1
            };
            n_insts++;
            if (s == S_LSU) {
                InstruccionPlan *in = &insts[n_insts - 1];
                datos_memoria(in->texto, &in->memoria_fija,
                              &in->memoria_escritura, &in->direccion_memoria);
            }
        }
    }

    DependenciaPlan *dependencias = NULL;
    int n_dependencias = 0;
    construir_grafo_dependencias(insts, n_insts, &dependencias,
                                 &n_dependencias);

    int ciclo = 0, emitidas = 0, ultimo_ciclo = -1;
    while (emitidas < n_insts) {
        salida_asegurar(salida, cap_salida, base + ciclo + 1);
        Bundle *b = &(*salida)[base + ciclo];

        for (;;) {
            int mejor = -1, mejor_slot = -1;
            for (int i = 0; i < n_insts; i++) {
                InstruccionPlan *in = &insts[i];
                if (nivel_opt < 2 && i != emitidas) continue;
                if (in->ciclo_programado >= 0 || in->pendientes != 0 ||
                    in->ciclo_minimo > ciclo)
                    continue;
                for (int s = 0; s < 5; s++) {
                    if (!(in->slots_permitidos & (1u << (unsigned int)s)) ||
                        !puede_ocupar_slot(b, in, s))
                        continue;
                    if (mejor < 0 ||
                        in->camino_critico > insts[mejor].camino_critico ||
                        (in->camino_critico == insts[mejor].camino_critico &&
                         i < mejor)) {
                        mejor = i;
                        mejor_slot = s;
                    }
                    break;
                }
            }
            if (mejor < 0) break;

            InstruccionPlan *in = &insts[mejor];
            b->s[mejor_slot] = (char *)in->texto;
            b->lecturas[mejor_slot] = in->lecturas;
            b->escrituras[mejor_slot] = in->escrituras;
            b->planificable[mejor_slot] = 1;
            b->escribe_flags[mejor_slot] = in->escribe_flags;
            b->delay_seguro[mejor_slot] =
                in->delay_seguro && es_operacion_alu_pura(in->texto);
            if (b->source_line == 0) {
                b->source_line = in->linea;
                b->source_col = in->columna;
            }

            in->ciclo_programado = ciclo;
            in->orden_programado = emitidas;
            emitidas++;
            ultimo_ciclo = ciclo;
            for (int e = in->primero_saliente; e >= 0;
                 e = dependencias[e].siguiente_salida) {
                DependenciaPlan *d = &dependencias[e];
                InstruccionPlan *sucesora = &insts[d->despues];
                int listo = ciclo + d->latencia;
                if (listo > sucesora->ciclo_minimo)
                    sucesora->ciclo_minimo = listo;
                sucesora->pendientes--;
            }
        }

        for (int s = 0; s < 5; s++) {
            if (b->s[s] == NULL)
                explicar_nop_slot(b->razon_nop[s],
                                  sizeof(b->razon_nop[s]), insts,
                                  dependencias, n_insts, ciclo, s);
        }
        ciclo++;
    }

    if (nivel_opt >= 2) {
        for (int i = 0; i < n_insts; i++)
            if (insts[i].orden_programado != i)
                instrucciones_reordenadas++;
    }

    int largo = ultimo_ciclo + 1;
    int ultimo_productor = -1, listo_productor = largo;
    bool productor_flags = false;
    for (int i = 0; i < n_insts; i++) {
        int listo = insts[i].ciclo_programado +
            ((insts[i].escrituras != 0 || insts[i].escribe_flags) ? 3 : 1);
        if (listo > largo) largo = listo;
        if ((insts[i].escrituras != 0 || insts[i].escribe_flags) &&
            listo > listo_productor) {
            ultimo_productor = i;
            listo_productor = listo;
            productor_flags = insts[i].escribe_flags;
        }
    }
    salida_asegurar(salida, cap_salida, base + largo);
    for (int c = ultimo_ciclo + 1; c < largo; c++) {
        Bundle *b = &(*salida)[base + c];
        char motivo[112];
        if (ultimo_productor >= 0 && productor_flags)
            snprintf(motivo, sizeof(motivo),
                     "dependencia CMP S0 -> salto/bloque siguiente (3 bundles)");
        else if (ultimo_productor >= 0)
            snprintf(motivo, sizeof(motivo),
                     "latencia de escritura de R%d -> salto/bloque siguiente "
                     "(3 bundles)",
                     primer_registro_escrito(
                         insts[ultimo_productor].escrituras));
        else
            snprintf(motivo, sizeof(motivo),
                     "espera de la barrera del bloque basico");
        razon_relleno(b, motivo);
    }

    *n_salida = base + largo;
    mapa[hasta_i] = *n_salida;
    free(dependencias);
    free(insts);
}

static void acortar_tramo(Bundle *salida, int base, int *n_salida) {
    int instrucciones_hasta = 0, latencia_hasta = 0;
    for (int b = base; b < *n_salida; b++) {
        for (int s = 0; s < 5; s++) {
            if (salida[b].s[s] == NULL) continue;
            int fin = b - base + 1;
            if (fin > instrucciones_hasta) instrucciones_hasta = fin;
            if (salida[b].escrituras[s] != 0 ||
                salida[b].escribe_flags[s]) {
                fin = b - base + 3;
                if (fin > latencia_hasta) latencia_hasta = fin;
            }
        }
    }
    int largo = instrucciones_hasta > latencia_hasta
        ? instrucciones_hasta : latencia_hasta;
    *n_salida = base + largo;
}

static bool llenar_delay_seguro(Bundle *salida, int base, int *n_salida,
                               Bundle *delay, const char *salto_texto) {
    int registro_salto = -1;
    char mnem[16];
    if (sscanf(salto_texto, "%15s", mnem) != 1 ||
        strncmp(mnem, "jal", 3) == 0)
        return false;
    bool es_halt = strcmp(mnem, "halt") == 0;
    if (!es_halt) return false;
    if (sscanf(salto_texto, "%15s r%d", mnem, &registro_salto) != 2)
        registro_salto = -1;

    /* En halt solo es observable rellenar con resultados scratch R10/R11. */
    for (int b = *n_salida - 1; b >= base; b--) {
        for (int s = 0; s <= S_ALU1; s++) {
            Bundle *origen = &salida[b];
            unsigned int escritura = origen->escrituras[s];
            if (delay->s[s] != NULL || !origen->delay_seguro[s] ||
                (origen->lecturas[s] & mascara_registro(R_LINK)) != 0 ||
                (escritura &
                 ~(mascara_registro(RA) | mascara_registro(RB))) != 0 ||
                (registro_salto >= 0 &&
                 (escritura & mascara_registro(registro_salto)) != 0))
                continue;

            delay->s[s] = origen->s[s];
            delay->lecturas[s] = origen->lecturas[s];
            delay->escrituras[s] = escritura;
            delay->planificable[s] = 1;
            delay->delay_seguro[s] = 0;
            delay->escribe_flags[s] = origen->escribe_flags[s];
            if (delay->source_line == 0) {
                delay->source_line = origen->source_line;
                delay->source_col = origen->source_col;
            }
            origen->s[s] = NULL;
            origen->lecturas[s] = 0;
            origen->escrituras[s] = 0;
            origen->planificable[s] = 0;
            origen->delay_seguro[s] = 0;
            origen->escribe_flags[s] = 0;
            acortar_tramo(salida, base, n_salida);
            return true;
        }
    }
    return false;
}

static void calendarizar_programa(void) {
    paquete_vaciar();
    int n_originales = n_bundles;
    int *mapa = malloc((size_t)(n_originales + 1) * sizeof(int));
    bool *fronteras = calloc((size_t)(n_originales + 1), sizeof(bool));
    int capacidad_salida = cap_bundles ? cap_bundles : 256;
    Bundle *salida = calloc((size_t)capacidad_salida, sizeof(Bundle));
    if (mapa == NULL || fronteras == NULL || salida == NULL) {
        fprintf(stderr, "novac: sin memoria\n");
        exit(3);
    }

    for (int i = 0; i < n_etqs; i++)
        if (etqs[i].bundle >= 0 && etqs[i].bundle <= n_originales)
            fronteras[etqs[i].bundle] = true;
    int inicio_seguro_original = inicio_seguro;
    if (inicio_seguro_original >= 0 && inicio_seguro_original <= n_originales)
        fronteras[inicio_seguro_original] = true;

    int nuevos = 0, desde = 0, b = 0;
    while (b < n_originales) {
        if (fronteras[b]) {
            calendarizar_tramo(prog, desde, b, &salida, &nuevos,
                               &capacidad_salida, mapa);
            mapa[b] = nuevos;
            desde = b;
            if (b == inicio_seguro_original) {
                while (nuevos < SEC_BASE_BUNDLE) {
                    salida_asegurar(&salida, &capacidad_salida, nuevos + 1);
                    memset(&salida[nuevos++], 0, sizeof(Bundle));
                    razon_relleno(&salida[nuevos - 1],
                                  "NOP de alineacion a la region segura");
                }
                mapa[b] = nuevos;
            }
        }

        if (prog[b].s[S_BRU] != NULL) {
            calendarizar_tramo(prog, desde, b, &salida, &nuevos,
                               &capacidad_salida, mapa);
            Bundle delay_bundle;
            bool delay_lleno = false;
            if (b + 1 < n_originales) {
                delay_bundle = prog[b + 1];
                for (int s = 0; s < 5; s++)
                    snprintf(delay_bundle.razon_nop[s],
                             sizeof(delay_bundle.razon_nop[s]),
                             "NOP de delay slot obligatorio");
                if (!fronteras[b] && !fronteras[b + 1])
                    delay_lleno = llenar_delay_seguro(
                        salida, desde, &nuevos, &delay_bundle, prog[b].s[S_BRU]);
            }
            mapa[b] = nuevos;
            salida_asegurar(&salida, &capacidad_salida, nuevos + 2);
            salida[nuevos] = prog[b];
            for (int s = 0; s < S_BRU; s++) {
                if (salida[nuevos].s[s] == NULL)
                    snprintf(salida[nuevos].razon_nop[s],
                             sizeof(salida[nuevos].razon_nop[s]),
                             "salto en S4: no se mueven operaciones a traves "
                             "de una frontera de control");
            }
            nuevos++;
            mapa[b + 1] = nuevos;
            if (b + 1 < n_originales) {
                if (!delay_lleno)
                    razon_relleno(&delay_bundle,
                                  "NOP de delay slot; no hay operacion "
                                  "independiente segura");
                salida[nuevos++] = delay_bundle;
            }
            b += 2;
            desde = b;
            continue;
        }

        bool opaca = false;
        for (int s = 0; s < 5; s++)
            if (prog[b].s[s] != NULL && !prog[b].planificable[s])
                opaca = true;
        if (opaca) {
            calendarizar_tramo(prog, desde, b, &salida, &nuevos,
                               &capacidad_salida, mapa);
            mapa[b] = nuevos;
            salida_asegurar(&salida, &capacidad_salida, nuevos + 1);
            salida[nuevos++] = prog[b];
            razon_relleno(&salida[nuevos - 1],
                          "operacion opaca; no se reordena en el bloque");
            b++;
            desde = b;
            continue;
        }
        b++;
    }

    calendarizar_tramo(prog, desde, n_originales, &salida, &nuevos,
                       &capacidad_salida, mapa);
    mapa[n_originales] = nuevos;

    for (int i = 0; i < n_etqs; i++)
        if (etqs[i].bundle >= 0 && etqs[i].bundle <= n_originales)
            etqs[i].bundle = mapa[etqs[i].bundle];
    for (int i = 0; i < n_notas; i++)
        if (notas[i].bundle >= 0 && notas[i].bundle <= n_originales)
            notas[i].bundle = mapa[notas[i].bundle];
    for (int i = 0; i < n_sitios; i++)
        if (sitio_bundle[i] >= 0 && sitio_bundle[i] <= n_originales)
            sitio_bundle[i] = mapa[sitio_bundle[i]];
    if (inicio_seguro_original >= 0)
        inicio_seguro = mapa[inicio_seguro_original];

    free(prog);
    prog = salida;
    cap_bundles = capacidad_salida;
    n_bundles = nuevos;
    free(mapa);
    free(fronteras);
}

/* Suelta todo lo que reservo el generador. Se llama al terminar. */
static void liberar_todo(void) {
    liberar_construccion();
    free(temps); temps = NULL;
    free(temp_primero); temp_primero = NULL;
    free(temp_ultimo); temp_ultimo = NULL;
    free(temp_def_pos); temp_def_pos = NULL;
    free(temp_slot); temp_slot = NULL;
    free(temp_reg); temp_reg = NULL;
    free(temp_tiene_constante); temp_tiene_constante = NULL;
    free(temp_valor_constante); temp_valor_constante = NULL;
    free(temp_solo_indice_fijo); temp_solo_indice_fijo = NULL;
    free(tabla_temps); tabla_temps = NULL;
    n_temps = 0;
    cap_temps = 0;
    cap_tabla_temps = 0;
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
    for (TACInst *j = i->next; j != NULL && j->op != TAC_FUNC_END;
         j = j->next) {
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
    instrucciones_reordenadas = 0;
    temporales_asignados_registro = 0;
    renombradas = 0;
    temporales_derramados = 0;
    dependencias_war = 0;
    dependencias_waw = 0;
    asignacion_iniciar(tac);
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
        cargas_temporales_emitidas = 0;
        stores_temporales_emitidos = 0;

        nota("functio %s", func);
        registrar_etiqueta(func);
        emitir_prologo();

        int posicion = 0;
        for (TACInst *j = i->next; j != NULL && j->op != TAC_FUNC_END;
             j = j->next, posicion++) {
            tac_actual = j;
            tac_posicion_actual = posicion;
            linea_fuente_actual = j->linea;
            columna_fuente_actual = j->columna;
            emitir_inst(j);
        }
        tac_actual = NULL;
        if (asignacion_habilitada)
            registrar_accesos_temporales(accesos_asignados,
                                         &n_accesos_asignados, func);
        else
            registrar_accesos_temporales(accesos_base,
                                         &n_accesos_base, func);
        linea_fuente_actual = columna_fuente_actual = 0;
    }
    }

    if (!hubo_error) {
        paquete_vaciar();
        calendarizar_programa();
    }
    asignacion_terminar();
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
    if (!medicion_referencia && inicio_seguro >= 0 &&
        n_bundles - inicio_seguro > SEC_BUNDLES) {
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
    if (!medicion_referencia && n_bundles > IMEM_BUNDLES) {
        if (ejecutable_requiere_imem)
            diag_error("E410", 0, 1, 1,
                       "el ejecutable ocupa %d bundles; el limite de IMEM es %d",
                       n_bundles, IMEM_BUNDLES);
        else
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
    asignacion_habilitada = nivel_opt >= 2;
    lista = tac;
    asignacion_iniciar(tac);
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
            symtab_set_frame_offset(st, s->id, desplazamiento_simbolo(s));
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
            symtab_set_data_address(st, s->id,
                                    (uint32_t)(fns[k].base + desplazamiento_simbolo(s)));
        }
    }

    asignacion_terminar();
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
    guardar_estadisticas();
    liberar_todo();
    return ok;
}

bool codegen_print_allocation(TACList *tac, FILE *out) {
    if (tac == NULL || out == NULL) return false;
    lista = tac;
    asig_salida = out;
    asignacion_habilitada = true;
    asignacion_iniciar(tac);
    bool ok = true;
    for (TACInst *i = tac->head; i != NULL; i = i->next) {
        if (i->op != TAC_FUNC_BEGIN || i->result == NULL) continue;
        func = i->result;
        medir_funcion(i->next);
    }
    asignacion_terminar();
    asig_salida = NULL;
    if (!ok) {
        asignacion_habilitada = true;
        return false;
    }

    memset(accesos_base, 0, sizeof(accesos_base));
    memset(accesos_asignados, 0, sizeof(accesos_asignados));
    n_accesos_base = n_accesos_asignados = 0;
    cargas_temporales_emitidas = stores_temporales_emitidos = 0;
    asignacion_habilitada = false;
    medicion_referencia = true;
    ok = construir_programa(tac);
    medicion_referencia = false;
    guardar_estadisticas();
    liberar_todo();
    if (!ok) {
        asignacion_habilitada = true;
        return false;
    }

    cargas_temporales_emitidas = stores_temporales_emitidos = 0;
    asignacion_habilitada = true;
    ok = construir_programa(tac);
    guardar_estadisticas();
    liberar_todo();

    int cargas_ahorradas = 0, stores_ahorrados = 0;
    int cargas_adicionales = 0, stores_adicionales = 0;
    for (int i = 0; i < n_accesos_asignados; i++) {
        const AccesosTemporales *base =
            buscar_accesos_temporales(accesos_base, n_accesos_base,
                                      accesos_asignados[i].funcion);
        int delta_cargas = (base != NULL ? base->cargas : 0) -
                           accesos_asignados[i].cargas;
        int delta_stores = (base != NULL ? base->stores : 0) -
                           accesos_asignados[i].stores;
        if (delta_cargas > 0) cargas_ahorradas += delta_cargas;
        else cargas_adicionales -= delta_cargas;
        if (delta_stores > 0) stores_ahorrados += delta_stores;
        else stores_adicionales -= delta_stores;
    }
    fprintf(out, "Cargas de pila evitadas: %d; stores de pila evitados: %d\n",
            cargas_ahorradas, stores_ahorrados);
    if (cargas_adicionales > 0 || stores_adicionales > 0)
        fprintf(out, "Accesos adicionales: %d cargas; %d stores\n",
                cargas_adicionales, stores_adicionales);
    asignacion_habilitada = true;
    return ok && !ferror(out);
}

bool codegen_generate_vliw(TACList *tac, SymbolTable *st, FILE *out) {
    (void)st;
    if (tac == NULL || out == NULL) return false;
    asignacion_habilitada = nivel_opt >= 2;
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
    guardar_estadisticas();
    liberar_todo();
    return ok;
}

bool codegen_measure_vliw(TACList *tac, CodegenEstadisticas *out) {
    char *texto = NULL;
    size_t largo = 0;
    FILE *memoria = open_memstream(&texto, &largo);
    if (memoria == NULL) return false;

    bool referencia_anterior = medicion_referencia;
    medicion_referencia = true;
    bool ok = codegen_generate_vliw(tac, NULL, memoria);
    if (fclose(memoria) != 0) ok = false;
    medicion_referencia = referencia_anterior;
    free(texto);

    if (ok && out != NULL) codegen_estadisticas(out);
    return ok;
}

typedef struct {
    bool valido;
    int registro;
    uint32_t valor;
} SimEscrituraRegistro;

typedef struct {
    int z;
    int n;
    int c;
    int v;
} SimBanderas;

typedef struct {
    uint32_t registros[16];
    uint32_t memoria[16384];
    SimEscrituraRegistro pendientes[3][4];
    SimBanderas banderas;
    SimBanderas banderas_pendientes[3];
    bool banderas_validas[3];
} SimEstado;

static void sim_programar_registro(SimEstado *e, uint64_t ciclo,
                                   int registro, uint32_t valor) {
    int indice = (int)((ciclo + 3) % 3);
    for (int i = 0; i < 4; i++) {
        if (!e->pendientes[indice][i].valido) {
            e->pendientes[indice][i].valido = true;
            e->pendientes[indice][i].registro = registro;
            e->pendientes[indice][i].valor = valor;
            return;
        }
    }
}

static void sim_programar_banderas(SimEstado *e, uint64_t ciclo,
                                   SimBanderas banderas) {
    int indice = (int)((ciclo + 3) % 3);
    e->banderas_pendientes[indice] = banderas;
    e->banderas_validas[indice] = true;
}

static void sim_actualizar(SimEstado *e, uint64_t ciclo) {
    int indice = (int)(ciclo % 3);
    for (int i = 0; i < 4; i++) {
        if (!e->pendientes[indice][i].valido) continue;
        e->registros[e->pendientes[indice][i].registro] =
            e->pendientes[indice][i].valor;
        e->pendientes[indice][i].valido = false;
    }
    if (e->banderas_validas[indice]) {
        e->banderas = e->banderas_pendientes[indice];
        e->banderas_validas[indice] = false;
    }
}

static uint32_t sim_inmediato(long valor) {
    uint32_t v = (uint32_t)valor & 0x7ffffu;
    if ((v & 0x40000u) != 0) v |= 0xfff80000u;
    return v;
}

static int sim_buscar_etiqueta(const char *nombre) {
    for (int i = 0; i < n_etqs; i++)
        if (strcmp(etqs[i].nombre, nombre) == 0) return etqs[i].bundle;
    return -1;
}

static void sim_comparar(SimBanderas *b, uint32_t a, uint32_t c) {
    uint32_t diferencia = a - c;
    b->z = diferencia == 0;
    b->n = (int)(diferencia >> 31);
    b->c = a < c;
    b->v = (int)(((a ^ c) & (a ^ diferencia)) >> 31);
}

static bool sim_condicion(const char *condicion, const SimBanderas *b) {
    if (strcmp(condicion, "al") == 0) return true;
    if (strcmp(condicion, "eq") == 0) return b->z != 0;
    if (strcmp(condicion, "ne") == 0) return b->z == 0;
    if (strcmp(condicion, "lt") == 0) return (b->n ^ b->v) != 0;
    if (strcmp(condicion, "ge") == 0) return (b->n ^ b->v) == 0;
    if (strcmp(condicion, "ltu") == 0) return b->c != 0;
    if (strcmp(condicion, "geu") == 0) return b->c == 0;
    return false;
}

static bool sim_ejecutar_alu(SimEstado *e, const char *texto, uint64_t ciclo,
                            char *motivo, size_t cap_motivo) {
    char op[32], etiqueta_destino[96];
    int rd, rs1, rs2;
    long inmediato;
    uint32_t a, b, resultado = 0;
    bool escribe = false;

    if (sscanf(texto, "%31s r%d, #&%95s", op, &rd, etiqueta_destino) == 3 &&
        strcmp(op, "movi") == 0) {
        int destino = sim_buscar_etiqueta(etiqueta_destino);
        if (rd < 0 || rd >= 16 || destino < 0) goto instruccion_desconocida;
        sim_programar_registro(e, ciclo, rd, (uint32_t)destino * 16u);
        return true;
    }

    if (sscanf(texto, "%31s r%d, r%d, r%d", op, &rd, &rs1, &rs2) == 4) {
        if (rd < 0 || rd >= 16 || rs1 < 0 || rs1 >= 16 ||
            rs2 < 0 || rs2 >= 16) goto instruccion_desconocida;
        a = e->registros[rs1];
        b = e->registros[rs2];
        if (strcmp(op, "add") == 0) resultado = a + b;
        else if (strcmp(op, "sub") == 0) resultado = a - b;
        else if (strcmp(op, "mul") == 0) resultado = a * b;
        else if (strcmp(op, "and") == 0) resultado = a & b;
        else if (strcmp(op, "or") == 0) resultado = a | b;
        else if (strcmp(op, "xor") == 0) resultado = a ^ b;
        else if (strcmp(op, "sll") == 0) resultado = a << (b & 31u);
        else if (strcmp(op, "srl") == 0) resultado = a >> (b & 31u);
        else if (strcmp(op, "sra") == 0) resultado = (uint32_t)((int32_t)a >> (b & 31u));
        else goto instruccion_desconocida;
        escribe = true;
    } else if (sscanf(texto, "%31s r%d, r%d, #%ld", op, &rd, &rs1,
                      &inmediato) == 4) {
        if (rd < 0 || rd >= 16 || rs1 < 0 || rs1 >= 16)
            goto instruccion_desconocida;
        a = e->registros[rs1];
        b = sim_inmediato(inmediato);
        if (strcmp(op, "addi") == 0) resultado = a + b;
        else if (strcmp(op, "subi") == 0) resultado = a - b;
        else if (strcmp(op, "andi") == 0) resultado = a & b;
        else if (strcmp(op, "ori") == 0) resultado = a | b;
        else if (strcmp(op, "xori") == 0) resultado = a ^ b;
        else if (strcmp(op, "slli") == 0) resultado = a << ((uint32_t)inmediato & 31u);
        else if (strcmp(op, "srli") == 0) resultado = a >> ((uint32_t)inmediato & 31u);
        else if (strcmp(op, "srai") == 0)
            resultado = (uint32_t)((int32_t)a >> ((uint32_t)inmediato & 31u));
        else if (strcmp(op, "roli") == 0) {
            unsigned int n = (unsigned int)inmediato & 31u;
            resultado = n == 0 ? a : (a << n) | (a >> (32u - n));
        } else goto instruccion_desconocida;
        escribe = true;
    } else if (sscanf(texto, "%31s r%d, r%d", op, &rd, &rs1) == 3) {
        if (rd < 0 || rd >= 16 || rs1 < 0 || rs1 >= 16)
            goto instruccion_desconocida;
        if (strcmp(op, "cmp") == 0 || strcmp(op, "test") == 0) {
            SimBanderas nuevas = {0};
            a = e->registros[rd];
            b = e->registros[rs1];
            if (strcmp(op, "cmp") == 0) sim_comparar(&nuevas, a, b);
            else {
                uint32_t v = a & b;
                nuevas.z = v == 0;
                nuevas.n = (int)(v >> 31);
            }
            sim_programar_banderas(e, ciclo, nuevas);
            return true;
        }
        a = e->registros[rs1];
        if (strcmp(op, "mov") == 0) resultado = a;
        else if (strcmp(op, "neg") == 0) resultado = 0u - a;
        else if (strcmp(op, "not") == 0) resultado = ~a;
        else goto instruccion_desconocida;
        escribe = true;
    } else if (sscanf(texto, "%31s r%d, #%ld", op, &rd, &inmediato) == 3) {
        if (rd < 0 || rd >= 16) goto instruccion_desconocida;
        if (strcmp(op, "movi") == 0) {
            resultado = sim_inmediato(inmediato);
        } else if (strcmp(op, "movh") == 0) {
            resultado = (e->registros[rd] & 0xffffu) |
                        (((uint32_t)inmediato & 0xffffu) << 16);
        } else if (strcmp(op, "cmpi") == 0 || strcmp(op, "testi") == 0) {
            a = e->registros[rd];
            b = sim_inmediato(inmediato);
            SimBanderas nuevas = {0};
            if (strcmp(op, "cmpi") == 0) {
                sim_comparar(&nuevas, a, b);
            } else {
                uint32_t v = a & b;
                nuevas.z = v == 0;
                nuevas.n = (int)(v >> 31);
            }
            sim_programar_banderas(e, ciclo, nuevas);
            return true;
        } else goto instruccion_desconocida;
        escribe = true;
    } else {
        goto instruccion_desconocida;
    }

    if (escribe) sim_programar_registro(e, ciclo, rd, resultado);
    return true;

instruccion_desconocida:
    snprintf(motivo, cap_motivo, "instruccion ALU no soportada: %.80s", texto);
    return false;
}

static bool sim_ejecutar_lsu(SimEstado *e, const char *texto, uint64_t ciclo,
                            char *motivo, size_t cap_motivo) {
    char op[32];
    int registro, base;
    long desplazamiento;
    uint32_t direccion;
    if (sscanf(texto, "%31s r%d, #%ld(r%d)", op, &registro,
               &desplazamiento, &base) != 4 ||
        registro < 0 || registro >= 16 || base < 0 || base >= 16) {
        snprintf(motivo, cap_motivo, "instruccion LSU no soportada: %.80s", texto);
        return false;
    }
    direccion = e->registros[base] + (uint32_t)desplazamiento;
    if (strcmp(op, "lw") != 0 && strcmp(op, "sw") != 0) {
        snprintf(motivo, cap_motivo, "instruccion LSU no soportada: %.80s", texto);
        return false;
    }
    if ((direccion & 3u) != 0 || direccion > 65532u) {
        snprintf(motivo, cap_motivo, "direccion de memoria invalida: 0x%08x",
                 direccion);
        return false;
    }
    if (strcmp(op, "lw") == 0)
        sim_programar_registro(e, ciclo, registro, e->memoria[direccion >> 2]);
    else
        e->memoria[direccion >> 2] = e->registros[registro];
    return true;
}

static bool sim_ejecutar_salto(SimEstado *e, const char *texto, uint64_t ciclo,
                               int pc, int *destino, bool *tomado,
                               bool *detener, char *motivo,
                               size_t cap_motivo) {
    char op[32], argumento[96];
    const char *condicion;
    *tomado = false;
    *detener = false;
    if (sscanf(texto, "%31s %95s", op, argumento) < 1) return true;
    if (strcmp(op, "halt") == 0) {
        *detener = true;
        return true;
    }
    if (strcmp(op, "br.auth") == 0) {
        snprintf(motivo, cap_motivo, "saltos AUTH requieren soporte de boveda");
        return false;
    }
    if (strncmp(op, "br.", 3) != 0 && strncmp(op, "jal.", 4) != 0 &&
        strncmp(op, "jr.", 3) != 0 && strncmp(op, "jalr.", 5) != 0) {
        snprintf(motivo, cap_motivo, "instruccion BRU no soportada: %.80s", texto);
        return false;
    }
    condicion = strchr(op, '.');
    if (condicion == NULL || !sim_condicion(condicion + 1, &e->banderas)) {
        if (condicion != NULL &&
            strcmp(condicion + 1, "al") != 0 &&
            strcmp(condicion + 1, "eq") != 0 &&
            strcmp(condicion + 1, "ne") != 0 &&
            strcmp(condicion + 1, "lt") != 0 &&
            strcmp(condicion + 1, "ge") != 0 &&
            strcmp(condicion + 1, "ltu") != 0 &&
            strcmp(condicion + 1, "geu") != 0) {
            snprintf(motivo, cap_motivo, "condicion BRU no soportada: %.80s", texto);
            return false;
        }
        return true;
    }

    if (strncmp(op, "jr.", 3) == 0 || strncmp(op, "jalr.", 5) == 0) {
        int registro;
        if (sscanf(argumento, "r%d", &registro) != 1 ||
            registro < 0 || registro >= 16) {
            snprintf(motivo, cap_motivo, "registro de salto invalido: %.80s", texto);
            return false;
        }
        uint32_t dir = e->registros[registro];
        if ((dir & 15u) != 0 || dir / 16u >= (uint32_t)n_bundles) {
            snprintf(motivo, cap_motivo, "destino de salto invalido: 0x%08x", dir);
            return false;
        }
        *destino = (int)(dir / 16u);
        if (strncmp(op, "jalr.", 5) == 0)
            sim_programar_registro(e, ciclo, 15, (uint32_t)(pc + 2) * 16u);
        *tomado = true;
        return true;
    }

    int destino_etiqueta = sim_buscar_etiqueta(argumento);
    if (destino_etiqueta < 0 || destino_etiqueta >= n_bundles) {
        snprintf(motivo, cap_motivo, "etiqueta de salto desconocida: %.80s", argumento);
        return false;
    }
    *destino = destino_etiqueta;
    if (strncmp(op, "jal.", 4) == 0)
        sim_programar_registro(e, ciclo, 15, (uint32_t)(pc + 2) * 16u);
    *tomado = true;
    return true;
}

static bool sim_ejecutar(SimEstado *e, CodegenSimulacion *out) {
    const uint64_t limite = 10000000;
    uint64_t ciclo = 0;
    int pc = 0, destino_pendiente = -1;

    for (int b = 0; b < n_bundles; b++) {
        if (prog[b].s[S_CRP] != NULL) {
            snprintf(out->motivo, sizeof(out->motivo),
                     "slot CRP no soportado: %.80s", prog[b].s[S_CRP]);
            return true;
        }
    }

    while (ciclo < limite) {
        if (pc < 0 || pc >= n_bundles) {
            snprintf(out->motivo, sizeof(out->motivo),
                     "el flujo salio de la IMEM en el bundle %d", pc);
            return true;
        }
        sim_actualizar(e, ciclo);
        const Bundle *b = &prog[pc];
        int destino = -1;
        bool salto_tomado = false, detener = false;

        if (b->s[S_ALU0] != NULL &&
            !sim_ejecutar_alu(e, b->s[S_ALU0], ciclo,
                              out->motivo, sizeof(out->motivo))) return true;
        if (b->s[S_ALU1] != NULL &&
            !sim_ejecutar_alu(e, b->s[S_ALU1], ciclo,
                              out->motivo, sizeof(out->motivo))) return true;
        if (b->s[S_LSU] != NULL &&
            !sim_ejecutar_lsu(e, b->s[S_LSU], ciclo,
                              out->motivo, sizeof(out->motivo))) return true;
        if (b->s[S_BRU] != NULL &&
            !sim_ejecutar_salto(e, b->s[S_BRU], ciclo, pc, &destino,
                                &salto_tomado, &detener,
                                out->motivo, sizeof(out->motivo))) return true;

        if (detener) {
            out->bundles_ejecutados++;
            out->instrucciones++;
            out->soportado = true;
            out->ciclos = out->bundles_ejecutados + 1;
            return true;
        }

        for (int s = 0; s < 5; s++)
            if (b->s[s] != NULL) out->instrucciones++;
        out->bundles_ejecutados++;

        if (destino_pendiente >= 0) {
            pc = destino_pendiente;
            destino_pendiente = -1;
        } else {
            pc++;
            if (salto_tomado) destino_pendiente = destino;
        }
        ciclo++;
    }

    snprintf(out->motivo, sizeof(out->motivo),
             "se excedio el limite de %llu bundles ejecutados",
             (unsigned long long)limite);
    return true;
}

bool codegen_simular_vliw(TACList *tac, CodegenSimulacion *out) {
    SimEstado estado;
    if (tac == NULL || out == NULL) return false;
    memset(out, 0, sizeof(*out));
    memset(&estado, 0, sizeof(estado));
    asignacion_habilitada = nivel_opt >= 2;
    sal = NULL;
    bool ok = construir_programa(tac);
    if (!ok) {
        guardar_estadisticas();
        liberar_todo();
        return false;
    }
    if (buscar_etiqueta("__inicio") < 0) {
        snprintf(out->motivo, sizeof(out->motivo),
                 "el programa no tiene funcion principale");
        guardar_estadisticas();
        liberar_todo();
        return true;
    }
    for (int i = 0; i < datos_largo; i++) {
        unsigned int direccion = (unsigned int)datos_base + (unsigned int)i;
        if (direccion < sizeof(estado.memoria))
            ((unsigned char *)estado.memoria)[direccion] = datos[i];
    }
    ok = sim_ejecutar(&estado, out);
    guardar_estadisticas();
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
    asignacion_habilitada = nivel_opt >= 2;
    sal = NULL;
    bool ok = construir_programa(tac);
    if (!ok) {
        guardar_estadisticas();
    liberar_todo();
        return false;
    }
    if (buscar_etiqueta("__inicio") < 0) {
        diag_error("E405", 1, 1, 1,
                   "no hay 'principale': no se pueden mostrar paquetes ejecutables");
        guardar_estadisticas();
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
    guardar_estadisticas();
    liberar_todo();
    return ok;
}

bool codegen_print_calendar(TACList *tac, SymbolTable *st, FILE *out) {
    (void)st;
    if (tac == NULL || out == NULL) return false;
    asignacion_habilitada = nivel_opt >= 2;
    sal = NULL;
    bool ok = construir_programa(tac);
    if (!ok) {
        guardar_estadisticas();
        liberar_todo();
        return false;
    }
    if (buscar_etiqueta("__inicio") < 0) {
        diag_error("E405", 1, 1, 1,
                   "no hay 'principale': no se puede mostrar un calendario "
                   "ejecutable");
        guardar_estadisticas();
        liberar_todo();
        return false;
    }

    fprintf(out, "Calendario estatico: %d bundles\n", n_bundles);
    for (int b = 0; b < n_bundles; b++) {
        fprintf(out, "%04d", b);
        if (prog[b].source_line > 0)
            fprintf(out, " L%d:C%d", prog[b].source_line, prog[b].source_col);
        for (int s = 0; s < 5; s++)
            fprintf(out, " | S%d=%s", s,
                    prog[b].s[s] != NULL ? prog[b].s[s] : "NOP");
        fputc('\n', out);
        for (int s = 0; s < 5; s++) {
            if (prog[b].s[s] != NULL) continue;
            fprintf(out, "     NOP S%d: %s\n", s,
                    prog[b].razon_nop[s][0] != '\0'
                        ? prog[b].razon_nop[s]
                        : "sin operacion asignada a este slot");
        }
    }
    ok = !hubo_error && diag_errores() == 0 && !ferror(out);
    guardar_estadisticas();
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
    asignacion_habilitada = nivel_opt >= 2;
    sal = NULL;
    ejecutable_requiere_imem = true;
    bool ok = construir_programa(tac);
    ejecutable_requiere_imem = false;
    if (n_bundles > IMEM_BUNDLES) {
        guardar_estadisticas();
        liberar_todo();
        return false;
    }

    int entrada = buscar_etiqueta("__inicio");
    if (entrada < 0) {
        diag_error("E405", 1, 1, 1,
                   "no hay 'principale': un modulo de biblioteca no puede ser "
                   "el punto de entrada de un ejecutable");
        guardar_estadisticas();
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
    guardar_estadisticas();
    liberar_todo();
    return limpio;
}
