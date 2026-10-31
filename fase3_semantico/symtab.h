#ifndef SYMTAB_H
#define SYMTAB_H

/*
 * Tabla de simbolos de Nova (Fase 3).
 *
 * Es una pila de ambitos con busqueda hacia los ambitos exteriores. Cada
 * simbolo guarda, ademas de su tipo, la informacion que la fase 4 necesita
 * para generar codigo de CERBERO: la direccion que le corresponde en DMEM
 * si es global, o el desplazamiento respecto de R14 (SP) si es local, y el
 * tamano en bytes que ocupa.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

/* --- Mapa de datos de CERBERO (especificacion del ISA, CE 4301) ---------
 * 0x0000-0x3FFF  globales      (16 KB, los asigna este compilador)
 * 0x4000-0xBFFF  buffers de E/S
 * 0xC000-0xEFFF  heap reservado
 * 0xF000-0xFFFF  pila, crece hacia abajo desde 0xFFFC
 */
#define CERBERO_GLOBAL_BASE   0x0000
#define CERBERO_GLOBAL_FIN    0x4000   /* primera direccion fuera del segmento */
#define CERBERO_PILA_TOPE     0xFFFC
#define CERBERO_PILA_BYTES    0x1000   /* 4 KB disponibles para marcos */
#define NOVA_PALABRA          4        /* una palabra de CERBERO: 32 bits */

/* Tipos de datos de Nova. TYPE_ERROR es el tipo de propagacion: una vez que
 * aparece, los chequeos que lo reciben se callan para no encadenar errores. */
typedef enum {
    TYPE_INTEGER,
    TYPE_VERITAS,
    TYPE_TEXTUS,
    TYPE_NIHIL,
    TYPE_ERROR
} DataType;

/* Categoria del simbolo. SYMBOL_MODULE representa el nombre (o alias) de un
 * modulo importado, para que 'modulo.nombre' no se reporte como no declarado. */
typedef enum {
    SYMBOL_VAR,
    SYMBOL_PARAM,
    SYMBOL_CONST,
    SYMBOL_FUNC,
    SYMBOL_MODULE
} SymbolKind;

/* Un parametro formal. 'abierto' marca las dimensiones abiertas (integer[],
 * integer[][]), que solo se permiten en parametros: el tamano concreto viaja
 * en el descriptor y se consulta con longitudo. */
typedef struct Parameter {
    char *name;
    DataType type;
    int dimensions;          /* 0 escalar, 1 arreglo 1D, 2 arreglo 2D */
    bool abierto;
    int rows;
    int cols;
    struct Parameter *next;
} Parameter;

typedef struct Symbol {
    char *name;
    SymbolKind kind;
    DataType type;

    /* Arreglos: hasta dos dimensiones. filas/cols valen 0 si son abiertas. */
    int dimensions;
    int rows;
    int cols;
    bool abierto;

    /* Asignacion de memoria para CERBERO */
    bool is_global;
    int32_t offset;          /* direccion DMEM si global, offset de R14 si local */
    int size_bytes;

    /* Constantes */
    int32_t const_value;
    bool has_const_value;

    /* Funciones */
    bool is_private;         /* privatum: no se exporta */
    bool is_intrinsic;
    bool is_variadic;        /* solo scribe y dic */
    bool es_cauda;           /* @cauda */
    bool es_obsoleta;        /* @obsoletum */
    char *msg_obsoleta;
    DataType return_type;
    int return_dims;
    Parameter *params;
    Parameter *params_fin;   /* para agregar en orden sin recorrer */
    int param_count;
    int local_frame_size;    /* bytes del marco local, ya calculado */

    /* Diagnostico */
    bool is_used;            /* se leyo al menos una vez (W001) */
    bool is_assigned;
    int line;
    int col;

    struct Entrada *entrada; /* fila del listado, para mantenerla al dia */

    struct Symbol *next;     /* siguiente simbolo del mismo ambito */
} Symbol;

struct Entrada;

typedef struct Scope {
    int level;               /* 0 global, 1+ anidados */
    Symbol *symbols;
    int offset_guardado;     /* local_memory_offset al abrir, para reciclarlo */
    struct Scope *parent;
} Scope;

/* Fila del listado historico: sobrevive al cierre de los ambitos para poder
 * imprimir la tabla completa con --sym al final de la compilacion. */
typedef struct Entrada {
    char *name;
    char *ambito;
    int level;
    SymbolKind kind;
    DataType type;
    int dimensions;
    int rows;
    int cols;
    bool abierto;
    bool is_global;
    int32_t offset;
    int size_bytes;
    int frame_offset;
    bool has_frame_offset;
    uint32_t data_address;      /* direccion absoluta en DMEM, primera llamada */
    bool has_data_address;
    uint32_t code_address;
    bool has_code_address;
    bool has_const_value;
    int32_t const_value;
    int param_count;
    int local_frame_size;
    int frame_total;            /* marco completo que resta el prologo */
    bool has_frame_total;
    bool is_private;
    bool is_intrinsic;
    bool is_variadic;
    int line;
    int col;
    struct Entrada *next;
} Entrada;

typedef struct SymbolTable {
    Scope *current_scope;
    int global_memory_offset;  /* siguiente direccion libre de DMEM */
    int local_memory_offset;   /* bytes usados por el ambito activo */
    int max_local_offset;      /* marca de agua del marco de la funcion */
    bool globales_desbordadas;

    const char *ambito_actual; /* nombre de funcion, para el listado */
    Entrada *listado;
    Entrada *listado_fin;
} SymbolTable;

/* --- Ciclo de vida --- */
SymbolTable *symtab_create(void);
void symtab_destroy(SymbolTable *st);

/* --- Ambitos --- */
void symtab_push_scope(SymbolTable *st);
void symtab_pop_scope(SymbolTable *st);
int symtab_level(const SymbolTable *st);
Symbol *symtab_simbolos_ambito(const SymbolTable *st);

/* --- Busquedas --- */
Symbol *symtab_lookup(SymbolTable *st, const char *name);
Symbol *symtab_lookup_current_scope(SymbolTable *st, const char *name);
Symbol *symtab_lookup_exterior(SymbolTable *st, const char *name);

/* --- Inserciones --- */
Symbol *symtab_insert_var(SymbolTable *st, const char *name, DataType type,
                          int dims, int rows, int cols, int line, int col);
Symbol *symtab_insert_param(SymbolTable *st, const Parameter *p, int line, int col);
Symbol *symtab_insert_const(SymbolTable *st, const char *name, DataType type,
                            int32_t val, bool tiene_valor, int line, int col);
Symbol *symtab_insert_func(SymbolTable *st, const char *name, DataType return_type,
                           int return_dims, bool is_private, int line, int col);
Symbol *symtab_insert_module(SymbolTable *st, const char *name, int line, int col);

void symtab_add_param(Symbol *f, const char *name, DataType type,
                      int dims, bool abierto, int rows, int cols);

/* Fija el tamano del marco de una funcion y lo refleja en el listado. */
void symtab_set_frame_size(Symbol *f, int bytes);
void symtab_set_frame_offset(SymbolTable *st, const char *function,
                             const char *name, int offset);
void symtab_set_function_address(SymbolTable *st, const char *function,
                                uint32_t address);

/*
 * Direccion absoluta en DMEM de una local o un parametro.
 *
 * Una local vive en R14 + desplazamiento, y R14 cambia en cada llamada, asi
 * que no hay una sola direccion. La que se guarda aqui es la de la PRIMERA
 * activacion: el valor que toma R14 siguiendo la cadena de llamadas mas corta
 * desde 'principale'. Es exacta para esa llamada y es la que se puede
 * comprobar contra un volcado de memoria del procesador.
 */
/* El marco completo de una funcion, que solo se conoce en la fase 4: incluye
 * las locales, los temporales y el R15 guardado. */
void symtab_set_frame_total(SymbolTable *st, const char *function, int bytes);

void symtab_set_data_address(SymbolTable *st, const char *function,
                             const char *name, uint32_t address);

/* --- Marco de la funcion activa --- */
void symtab_reset_frame(SymbolTable *st);
int symtab_frame_size(const SymbolTable *st);
void symtab_set_ambito(SymbolTable *st, const char *nombre);

/* --- Utilidades --- */
const char *data_type_to_string(DataType type);
const char *symbol_kind_to_string(SymbolKind k);
/* Escribe "integer", "integer[]" o "integer[][]" en buf. */
const char *tipo_con_dims(char *buf, size_t n, DataType t, int dims);

void symtab_dump(FILE *out, const SymbolTable *st);

#endif /* SYMTAB_H */
