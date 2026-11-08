/*
 * Punto de entrada del compilador.
 * Lee las opciones de la linea de comandos y coordina las fases de compilacion.
 */
#include <errno.h>
#include <getopt.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "ast.h"
#include "enlace.h"
#include "diag.h"
#include "nova.tab.h"
#include "semantic.h"
#include "symtab.h"
#include "tac.h"
#include "codegen.h"
#include "bloques.h"
#include "muerto.h"
#include "vivacidad.h"

extern FILE *yyin;
extern char *yytext;
int yyparse(void);
int yylex(void);
void yyrestart(FILE *input_file);
void nova_lexer_reset(void);
void nova_parser_reset(void);


static int write_object(const char *source_path, const char *output_path) {
    size_t length = 0;
    char *source = source_from_file(source_path, &length);
    if (source == NULL) {
        fprintf(stderr, "novac: no se pudo leer '%s'\n", source_path);
        return 3;
    }
    if (length > UINT32_MAX) { free(source); return 3; }
    FILE *out = fopen(output_path, "wb");
    if (out == NULL) { free(source); return 3; }
    unsigned char header[NVO_HEADER_SIZE] = {0};
    memcpy(header, "NVO1", 4);
    header[4] = 1;
    put_u32(header + 8, (uint32_t)length);
    put_u32(header + 12, checksum_bytes((unsigned char *)source, length));
    int ok = fwrite(header, 1, sizeof(header), out) == sizeof(header) &&
             fwrite(source, 1, length, out) == length;
    if (fclose(out) != 0) ok = 0;
    free(source);
    if (!ok) { remove(output_path); return 3; }
    return 0;
}


/* Estado global de la ejecucion actual. */
static int modo_verbose = 0;
static int modo_arbol = 0;
static int modo_lexer = 0;
static int modo_symtab = 0;
static int modo_ir = 0;
static int modo_bloques = 0;
static int modo_asm = 0;
static int modo_ensamblar = 0;
static int modo_paquetes = 0;
static int modo_objeto = 0;        /* -c: solo compilar, generar .nvo */
static int modo_vivacidad = 0;     /* --vivacidad: conjuntos del analisis */
static int nivel_opt = 0;          /* -O0 / -O1: eliminacion de codigo muerto */
static int modo_metricas = 0;      /* --metricas: que costo y que se gano */
static const char *archivo_salida = NULL;
static clock_t reloj_inicio;       /* para medir el tiempo de compilacion */

/* Cuantas instrucciones de tres direcciones tiene la lista. */
static int contar_tac(const TACList *l) {
    int n = 0;
    const TACInst *i;
    if (l == NULL) return 0;
    for (i = l->head; i != NULL; i = i->next) n++;
    return n;
}

/* -I: directorios donde buscar modulos importados. */

/* Mapea cada token a su nombre para la salida del modo de inspeccion. */
static const char *nombre_token(int tipo) {
    switch (tipo) {
        case TK_FUNCTIO: return "TK_FUNCTIO";
        case TK_VARIA: return "TK_VARIA";
        case TK_CONSTANS: return "TK_CONSTANS";
        case TK_PRIVATUM: return "TK_PRIVATUM";
        case TK_IMPORTA: return "TK_IMPORTA";
        case TK_UT: return "TK_UT";
        case TK_REDDE: return "TK_REDDE";
        case TK_SI: return "TK_SI";
        case TK_SIN: return "TK_SIN";
        case TK_ALITER: return "TK_ALITER";
        case TK_DUM: return "TK_DUM";
        case TK_PER: return "TK_PER";
        case TK_RUMPE: return "TK_RUMPE";
        case TK_PERGE: return "TK_PERGE";
        case TK_TIPO_INTEGER: return "TK_TIPO_INTEGER";
        case TK_TIPO_VERITAS: return "TK_TIPO_VERITAS";
        case TK_TIPO_TEXTUS: return "TK_TIPO_TEXTUS";
        case TK_TIPO_NIHIL: return "TK_TIPO_NIHIL";
        case TK_ET: return "TK_ET";
        case TK_AUT: return "TK_AUT";
        case TK_NON: return "TK_NON";
        case TK_VERUM: return "TK_VERUM";
        case TK_FALSUM: return "TK_FALSUM";
        case TK_MAS: return "TK_MAS";
        case TK_MENOS: return "TK_MENOS";
        case TK_POR: return "TK_POR";
        case TK_ENTRE: return "TK_ENTRE";
        case TK_MODULO: return "TK_MODULO";
        case TK_IGUAL: return "TK_IGUAL";
        case TK_DIFERENTE: return "TK_DIFERENTE";
        case TK_MENOR: return "TK_MENOR";
        case TK_MENOR_IGUAL: return "TK_MENOR_IGUAL";
        case TK_MAYOR: return "TK_MAYOR";
        case TK_MAYOR_IGUAL: return "TK_MAYOR_IGUAL";
        case TK_ASIGNA: return "TK_ASIGNA";
        case TK_ASIGNA_MAS: return "TK_ASIGNA_MAS";
        case TK_ASIGNA_MENOS: return "TK_ASIGNA_MENOS";
        case TK_ASIGNA_POR: return "TK_ASIGNA_POR";
        case TK_ASIGNA_ENTRE: return "TK_ASIGNA_ENTRE";
        case TK_ASIGNA_MODULO: return "TK_ASIGNA_MODULO";
        case TK_PAR_IZQ: return "TK_PAR_IZQ";
        case TK_PAR_DER: return "TK_PAR_DER";
        case TK_LLAVE_IZQ: return "TK_LLAVE_IZQ";
        case TK_LLAVE_DER: return "TK_LLAVE_DER";
        case TK_COR_IZQ: return "TK_COR_IZQ";
        case TK_COR_DER: return "TK_COR_DER";
        case TK_PUNTO_COMA: return "TK_PUNTO_COMA";
        case TK_COMA: return "TK_COMA";
        case TK_DOS_PUNTOS: return "TK_DOS_PUNTOS";
        case TK_PUNTO: return "TK_PUNTO";
        case TK_FLECHA: return "TK_FLECHA";
        case TK_ARROBA: return "TK_ARROBA";
        case TK_AMPERSAND: return "TK_AMPERSAND";
        case TK_BARRA: return "TK_BARRA";
        case TK_XOR: return "TK_XOR";
        case TK_NOT: return "TK_NOT";
        case TK_DESP_IZQ: return "TK_DESP_IZQ";
        case TK_DESP_DER: return "TK_DESP_DER";
        case TK_DESP_LOG: return "TK_DESP_LOG";
        case TK_IDENT: return "TK_IDENT";
        case TK_ENTERO: return "TK_ENTERO";
        case TK_CADENA: return "TK_CADENA";
        default: return "?";
    }
}

/*
 * Fase 1: analisis lexico.
 * Recorre el archivo fuente token por token y muestra la tabla de tokens.
 */
static int correr_lexer(void) {
    printf("%-22s %-20s %6s %5s\n", "LEXEMA", "TOKEN", "LINEA", "COL");
    printf("-------------------------------------------------------------\n");
    int tok, total = 0;
    while ((tok = yylex()) != 0) {
        char lexema[64];
        if (tok == TK_CADENA) snprintf(lexema, sizeof(lexema), "\"%.50s\"", yylval.texto);
        else snprintf(lexema, sizeof(lexema), "%.60s", yytext);
        printf("%-22s %-20s %6d %5d\n", lexema, nombre_token(tok),
               yylloc.first_line, yylloc.first_column);
        total++;
        /* En este modo se llama a yylex() directo, asi que hay que liberar
         * los textos que se asignaron con strdup() en el lexer. */
        if (tok == TK_IDENT || tok == TK_CADENA) {
            free(yylval.texto);
        }
    }
    printf("%-22s %-20s %6d %5d\n", "<EOF>", "TK_EOF", yylloc.first_line, yylloc.first_column);
    printf("-- %d tokens --\n", total + 1);
    if (diag_errores() > 0) {
        diag_resumen();
        return 1;
    }
    printf("\nAnalisis lexico completado sin errores.\n");
    return 0;
}

/*
 * Nombre de salida por omision: el del fuente sin su extension, sin el
 * directorio, y con .nvo si se pidio -c. 'programa.nv' -> 'programa'.
 */
static void nombre_por_omision(const char *fuente, int objeto, char *dest, size_t cap) {
    const char *base = fuente;
    const char *p;
    size_t largo;

    for (p = fuente; *p; p++)
        if (*p == '/' || *p == '\\') base = p + 1;

    largo = strlen(base);
    if (largo > 3 && strcmp(base + largo - 3, ".nv") == 0) largo -= 3;
    if (largo >= cap - 5) largo = cap - 5;

    memcpy(dest, base, largo);
    dest[largo] = '\0';
    if (objeto) strncat(dest, ".nvo", cap - strlen(dest) - 1);
    /* Un fuente llamado solo ".nv" dejaria el nombre vacio. */
    if (dest[0] == '\0') snprintf(dest, cap, "%s", objeto ? "salida.nvo" : "salida");
}

static char *cambiar_extension(const char *path, const char *extension) {
    const char *slash = strrchr(path, '/');
    const char *dot = strrchr(path, '.');
    size_t stem = dot != NULL && (slash == NULL || dot > slash)
        ? (size_t)(dot - path) : strlen(path);
    size_t n = stem + strlen(extension) + 1;
    char *result = malloc(n);
    if (result == NULL) { fprintf(stderr, "novac: sin memoria\n"); exit(3); }
    memcpy(result, path, stem);
    strcpy(result + stem, extension);
    return result;
}

static int ensamblar_archivo(const char *source, const char *output,
                             const char *program, int verbose) {
    char executable[PATH_MAX], script[PATH_MAX];
    if (realpath(program, executable) == NULL) {
        fprintf(stderr, "novac: no se pudo resolver la ruta del ejecutable '%s'\n", program);
        return 3;
    }
    char *slash = strrchr(executable, '/');
    if (slash == NULL) {
        fprintf(stderr, "novac: no se pudo determinar la carpeta de instalacion\n");
        return 3;
    }
    *slash = '\0';
    int n = snprintf(script, sizeof(script),
                     "%s/ARQUITECTURA/tools/cerbero_asm.py", executable);
    if (n < 0 || (size_t)n >= sizeof(script)) {
        fprintf(stderr, "novac: la ruta del ensamblador CERBERO es demasiado larga\n");
        return 3;
    }
    if (access(script, R_OK) != 0) {
        n = snprintf(script, sizeof(script), "%s/../tools/cerbero_asm.py", executable);
    }
    if (n < 0 || (size_t)n >= sizeof(script) || access(script, R_OK) != 0) {
        fprintf(stderr, "novac: no se encontro el ensamblador CERBERO junto a novac\n");
        return 3;
    }
    size_t output_n = strlen(output);
    char *data_output = malloc(output_n + sizeof(".dmem.hex"));
    char *listing_output = malloc(output_n + sizeof(".lst"));
    if (data_output == NULL || listing_output == NULL) {
        free(data_output);
        free(listing_output);
        fprintf(stderr, "novac: sin memoria\n");
        return 3;
    }
    snprintf(data_output, output_n + sizeof(".dmem.hex"), "%s.dmem.hex", output);
    snprintf(listing_output, output_n + sizeof(".lst"), "%s.lst", output);
    if (verbose)
        fprintf(stderr, "ensamblando '%s' con el ensamblador CERBERO\n", source);

    pid_t child = fork();
    if (child < 0) {
        perror("novac: no se pudo iniciar el ensamblador");
        free(data_output);
        free(listing_output);
        return 3;
    }
    if (child == 0) {
        execlp("python3", "python3", script, source, "-o", output,
               "--datos", data_output, "--listado", listing_output, (char *)NULL);
        perror("novac: no se pudo ejecutar python3");
        _exit(127);
    }
    int status;
    while (waitpid(child, &status, 0) < 0) {
        if (errno == EINTR) continue;
        perror("novac: error esperando al ensamblador");
        free(data_output);
        free(listing_output);
        return 3;
    }
    free(data_output);
    free(listing_output);
    if (!WIFEXITED(status)) {
        fprintf(stderr, "novac: el ensamblador termino de forma anormal\n");
        return 1;
    }
    int result = WEXITSTATUS(status);
    return result == 0 ? 0 : result == 127 ? 3 : 1;
}

/*
 * Ayuda del programa. Explica las banderas disponibles y que parte del
 * compilador se ejecuta en cada caso.
 */
static void print_usage(const char *prog) {
    fprintf(stderr,
        "Uso: %s [opciones] <archivo_fuente|ensamblador.s> [-o <salida>]\n"
        "\n"
        "Sin banderas de volcado produce el ejecutable binario de CERBERO. Si no\n"
        "se da -o, el nombre es el del fuente sin extension (con .nvo si hay -c).\n"
        "\n"
        "  -o <archivo>      Nombre de salida binaria\n"
        "  -c                Empaqueta fuente validada en un objeto .nvo\n"
        "  -I <directorio>   Directorio de busqueda para importa\n"
        "  -v                Modo detallado: imprime cada fase\n"
        "  -Wall             Activa todas las advertencias (lo estan por omision)\n"
        "  -Werror           Trata las advertencias como errores\n"
        "  -w                Silencia todas las advertencias\n"
        "  -Wno-W00n         Silencia una advertencia concreta\n"
        "  --max-errors <n>  Maximo de errores antes de abortar (por omision: 25)\n"
        "  --tokens          Solo Fase 1: tabla de tokens\n"
        "  -t                Imprime el arbol sintactico (AST)\n"
        "  --sym, -m         Imprime la tabla de simbolos (Fase 3)\n"
        "  --ir              Codigo de tres direcciones (Fase 4)\n"
        "  --bloques         Bloques basicos y grafo de flujo de control\n"
        "  --vivacidad       Analisis de vivacidad: USO, DEF, VIVO_ENT, VIVO_SAL\n"
        "  -O0, -O1          Nivel de optimizacion (0 por omision)\n"
        "  --optimizar       Equivale a -O1\n"
        "  --metricas        Que costo optimizar y que se gano\n"
        "  -s                Genera binario y ensamblador .asm; tambien lo muestra\n"
        "  -x                Ensambla un archivo .s a imagen binaria .hex\n"
        "  -p                Muestra paquetes con slots y codificacion hexadecimal\n"
        "  --version         Version\n"
        "  -h, --help        Esta ayuda\n"
        "\n"
        "Codigos de salida: 0 exito, 1 errores de compilacion, 2 error de uso,\n"
        "3 error de entrada o salida.\n",
        prog);
}

/*
 * Las opciones largas se registran aqui para poder interpretar banderas como
 * --tokens, --help o --version sin tener que hacer parsing manual extra.
 */
static const struct option opciones_largas[] = {
    {"tokens",  no_argument, NULL, 'l'},
    {"sym",     no_argument, NULL, 'm'},
    {"ir",      no_argument, NULL, 1001},
    {"bloques", no_argument, NULL, 1004},
    {"vivacidad", no_argument, NULL, 1005},
    {"metricas",  no_argument, NULL, 1006},
    {"optimizar", no_argument, NULL, 1007},
    {"version", no_argument, NULL, 1002},
    {"max-errors", required_argument, NULL, 1003},
    {"help",    no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0}
};

int main(int argc, char **argv) {
    int opt;
    reloj_inicio = clock();
    /*
     * Se leen todas las banderas antes de abrir la fase real de compilacion.
     * Esto permite decidir si se ejecuta solo la fase 1, la fase 2 o un
     * modo de diagnostico simple.
     */
    while ((opt = getopt_long(argc, argv, "o:I:W:O:vtsmclhwxp", opciones_largas, NULL)) != -1) {
        switch (opt) {
            case 'h': print_usage(argv[0]); return 0;
            case 1003: {
                char *fin = NULL;
                long n;
                errno = 0;
                n = strtol(optarg, &fin, 10);
                if (errno != 0 || fin == optarg || *fin != '\0' || n < 1 || n > 1000000) {
                    fprintf(stderr, "novac: valor invalido para --max-errors: '%s' (se espera un entero positivo)\n", optarg);
                    return 2;
                }
                diag_max_errores((int)n);
                break;
            }
            case 1002: printf("novac (Nova) 0.5 - fases 1 a 6: lexico, sintactico, semantico,\n       ensamblador, calculo de saltos y binario CERBERO\n"); return 0;
            case 1001: modo_ir = 1; break;
            case 1004: modo_bloques = 1; break;
            case 1005: modo_vivacidad = 1; break;
            case 1006: modo_metricas = 1; break;
            case 1007: nivel_opt = 1; break;
            case 'O':
                /* -O0 y -O1. getopt entrega lo que sigue a -O. */
                if (strcmp(optarg, "0") == 0) nivel_opt = 0;
                else if (strcmp(optarg, "1") == 0) nivel_opt = 1;
                else {
                    fprintf(stderr, "novac: nivel de optimizacion desconocido: "
                                    "'-O%s' (se espera -O0 o -O1)\n", optarg);
                    return 2;
                }
                break;
            case 'o': archivo_salida = optarg; break;
            case 'v': modo_verbose = 1; break;
            case 't': modo_arbol = 1; break;
            case 'l': modo_lexer = 1; break;
            case 'm': modo_symtab = 1; break;
            case 's': modo_asm = 1; break;
            case 'x': modo_ensamblar = 1; break;
            case 'p': modo_paquetes = 1; break;
            case 'c': modo_objeto = 1; break;
            case 'w': diag_warn_ninguna(); break;
            case 'I':
                if (!nova_agregar_ruta_modulos(optarg)) {
                    fprintf(stderr, "novac: demasiados directorios -I (maximo %d)\n", NOVA_MAX_RUTAS);
                    return 2;
                }
                break;
            case 'W':
                /* -Wall, -Werror, -Wno-W00n. getopt entrega lo que sigue a -W. */
                if (strcmp(optarg, "all") == 0) diag_warn_todas();
                else if (strcmp(optarg, "error") == 0) diag_warn_como_error();
                else if (strncmp(optarg, "no-", 3) == 0) {
                    if (!diag_warn_desactivar(optarg + 3)) {
                        fprintf(stderr, "novac: '-W%s' no nombra una advertencia conocida (se esperaba W001..W032)\n", optarg);
                        return 2;
                    }
                } else {
                    fprintf(stderr, "novac: opcion de advertencias desconocida: '-W%s'\n", optarg);
                    return 2;
                }
                break;
            default: print_usage(argv[0]); return 2;
        }
    }

    if (optind >= argc) {
        print_usage(argv[0]);
        return 2;
    }
    const char *archivo_fuente = argv[optind];

    int extra_count = argc - optind - 1;
    if (modo_ensamblar) {
        if (extra_count > 0 || modo_objeto || modo_lexer || modo_arbol ||
            modo_symtab || modo_ir || modo_bloques || modo_vivacidad ||
            modo_asm || modo_paquetes) {
            fprintf(stderr, "novac: -x recibe un solo .s y no se combina con opciones de inspeccion o -c\n");
            return 2;
        }
        char default_output[PATH_MAX];
        const char *output = archivo_salida;
        if (output == NULL) {
            char *derived = cambiar_extension(argv[optind], ".hex");
            if (strlen(derived) >= sizeof(default_output)) {
                free(derived);
                fprintf(stderr, "novac: nombre de salida demasiado largo\n");
                return 2;
            }
            snprintf(default_output, sizeof(default_output), "%s", derived);
            free(derived);
            output = default_output;
        }
        return ensamblar_archivo(argv[optind], output, argv[0], modo_verbose);
    }
    if (modo_objeto && extra_count > 0) {
        fprintf(stderr, "novac: -c recibe un solo modulo fuente por invocacion\n");
        return 2;
    }
    if ((modo_lexer || modo_arbol || modo_symtab || modo_ir || modo_bloques ||
         modo_vivacidad || modo_asm || modo_paquetes) && extra_count > 0) {
        fprintf(stderr, "novac: las opciones de inspeccion reciben un solo archivo\n");
        return 2;
    }
    char **extra_paths = extra_count ? &argv[optind + 1] : NULL;
    diag_iniciar(archivo_fuente);

    /*
     * Si la bandera --tokens/-l esta activa, se ejecuta solo la Fase 1.
     * En cualquier otro caso, el programa entra a la Fase 2 y construye el AST.
     */
    // Modo Léxico
    if (modo_lexer) {
        if (modo_verbose) fprintf(stderr, "== Fase 1: Analisis Lexico -- %s ==\n", archivo_fuente);
        yyin = fopen(archivo_fuente, "r");
        if (yyin == NULL) {
            fprintf(stderr, "novac: no se pudo abrir '%s'\n", archivo_fuente);
            return 3;
        }
        nova_lexer_reset();
        int rc = correr_lexer();
        fclose(yyin);
        return rc;
    }

    /*
     * Fases 1 y 2. El lexer no se corre por separado: bison lo llama con
     * yylex() a medida que necesita el siguiente token, asi que las dos fases
     * van entrelazadas. Para ver solo la fase 1 esta --tokens.
     */
    if (modo_verbose) {
        fprintf(stderr, "== Fase 1: Analisis Lexico -- %s ==\n", archivo_fuente);
        fprintf(stderr, "   (a demanda del parser; --tokens la corre sola)\n");
        fprintf(stderr, "== Fase 2: Analisis Sintactico -- %s ==\n", archivo_fuente);
    }
    int rc = parse_source(archivo_fuente, &raiz_ast);

    if (rc != 0 || diag_errores() > 0) {
        /* Con recuperacion de errores yyparse puede devolver 0 aunque haya
         * errores: el arbol parcial no sirve, se libera. */
        liberar_ast(raiz_ast);
        release_modules();
        diag_resumen();
        return rc == 3 ? 3 : 1;
    }

    if (modo_verbose) fprintf(stderr, "Fase 2 completada sin errores.\n");

    /*
     * Una vez que la fase 2 termina sin errores, se puede pedir la impresion
     * del AST en pantalla o en un archivo de salida.
     */
    // Imprimir AST si se solicitó (-t)
    if (modo_arbol) {
        FILE *salida = stdout;
        if (archivo_salida != NULL) {
            salida = fopen(archivo_salida, "w");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
        }
        fprintf(salida, "=== Arbol sintactico (AST) ===\n");
        imprimir_ast(salida, raiz_ast);
        if (archivo_salida != NULL && salida != stdout) fclose(salida);
    }

    /*
     * Fase 3: analisis semantico. Construye la tabla de simbolos, verifica
     * tipos, ambitos y flujo, y deja en cada simbolo la direccion de memoria
     * que la fase 4 necesita para generar codigo de CERBERO.
     */
    if (modo_verbose) fprintf(stderr, "== Fase 3: Analisis Semantico -- %s ==\n", archivo_fuente);

    if (!modo_arbol && (modo_objeto || modo_symtab || modo_ir || modo_bloques ||
                        modo_vivacidad || modo_asm || modo_paquetes ||
                        (!modo_arbol && !modo_symtab && !modo_ir && !modo_bloques &&
                         !modo_vivacidad && !modo_asm && !modo_paquetes))) {
        if (!link_modules(raiz_ast, archivo_fuente, extra_paths, extra_count)) {
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return diag_errores() ? 1 : 3;
        }
    }

    SymbolTable *tabla = NULL;
    bool sem_ok = semantic_analyze(raiz_ast, &tabla);

    if (!sem_ok) {
        symtab_destroy(tabla);
        liberar_ast(raiz_ast);
        release_modules();
        diag_resumen();
        return 1;
    }

    if (modo_verbose) fprintf(stderr, "Fase 3 completada sin errores.\n");

    /* Para mostrar los desplazamientos usados realmente por el ensamblador,
     * se mide el marco de cada funcion con el layout de fase 4. */
    if (modo_symtab) {
        TACList *layout_tac = tac_generate_from_ast(raiz_ast, tabla);
        bool layout_ok;
        /*
         * El layout se mide sobre el MISMO codigo que se va a generar. Si se
         * esta compilando con -O1 hay que optimizar tambien esta copia: quitar
         * instrucciones acorta los rangos de vida de los temporales y puede
         * cambiar el marco, y con el las direcciones que imprime --sym. Sin
         * esto, la tabla de simbolos describiria un programa distinto del que
         * sale en el binario.
         *
         * Se pasa avisar=0 porque las advertencias W010 ya salen de la pasada
         * real; aqui se duplicarian.
         */
        if (nivel_opt > 0) muerto_eliminar(layout_tac, NULL, 0);
        layout_ok = codegen_update_symbol_layout(layout_tac, tabla);
        tac_free(layout_tac);
        if (!layout_ok) {
            if (diag_errores() == 0)
                fprintf(stderr, "novac: no se pudo calcular el layout de codigo para --sym\n");
            symtab_destroy(tabla);
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return diag_errores() ? 1 : 3;
        }

        FILE *salida = stdout;
        if (archivo_salida != NULL) {
            salida = fopen(archivo_salida, modo_arbol ? "a" : "w");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
        }
        symtab_dump(salida, tabla);

        /*
         * Los puntos de salto, debajo de la tabla de simbolos.
         *
         * La Fase 3 de la guia pide registrar las etiquetas de condicionales y
         * ciclos con su direccion en memoria. El calculo lo hace la resolucion
         * de saltos de la fase 5, y su resultado ya salia como comentario
         * dentro del .asm; aqui se muestra tambien junto a los simbolos, que es
         * donde se la busca al revisar el compilador.
         */
        {
            const CodegenEtiqueta *etqs = NULL;
            int n = codegen_etiquetas(&etqs);
            fprintf(salida, "\n=== Puntos de salto y etiquetas resueltas ===\n");
            fprintf(salida, "%-30s %-12s %-6s %s\n",
                    "ETIQUETA", "DIRECCION", "BUNDLE", "UBICACION");
            fprintf(salida, "--------------------------------------------"
                            "----------------------------\n");
            for (int k = 0; k < n; k++) {
                if (etqs[k].es_dato)
                    fprintf(salida, "%-30s 0x%04X       %-6s %s\n",
                            etqs[k].nombre, etqs[k].direccion, "-",
                            "DMEM (dato)");
                else
                    fprintf(salida, "%-30s 0x%04X       %-6d %s\n",
                            etqs[k].nombre, etqs[k].direccion, etqs[k].bundle,
                            "IMEM (codigo)");
            }
            fprintf(salida, "%d etiqueta%s en total.\n", n, n == 1 ? "" : "s");
        }
        if (archivo_salida != NULL && salida != stdout) fclose(salida);
    }

    if (modo_objeto) {
        char nombre[256];
        const char *destino = archivo_salida;
        if (destino == NULL) {
            nombre_por_omision(archivo_fuente, 1, nombre, sizeof(nombre));
            destino = nombre;
        }
        int object_rc = write_object(archivo_fuente, destino);
        if (object_rc == 0 && modo_verbose)
            fprintf(stderr, "objeto NOVA escrito en '%s'\n", destino);
        symtab_destroy(tabla);
        liberar_ast(raiz_ast);
        release_modules();
        return object_rc;
    }

    /*
     * El resumen de advertencias va al final de todo, no aqui: la fase 6 todavia
     * puede agregar las suyas (W010, asignaciones muertas) y el conteo tiene que
     * incluirlas.
     *
     * Fase 4: codigo intermedio y ensamblador de CERBERO. El AST ya viene
     * decorado por la fase 3 con la direccion de cada nombre.
     */
    /*
     * Si no se pidio ningun volcado, la salida por omision es el ejecutable
     * binario, como dice el documento. --ir y -s son volcados de texto que
     * reemplazan al binario para poder revisar la fase por partes.
     */
    int modo_binario = (!modo_ir && !modo_bloques && !modo_vivacidad &&
                        !modo_arbol && !modo_symtab && !modo_paquetes);

    if (modo_ir || modo_bloques || modo_vivacidad || modo_asm || modo_paquetes ||
        modo_binario) {
        if (modo_verbose) fprintf(stderr, "== Fase 4: Generacion de codigo -- %s ==\n", archivo_fuente);

        TACList *tac = tac_generate_from_ast(raiz_ast, tabla);
        bool gen_ok = true;
        ReporteMuerto rep_muerto;
        double ms_opt = 0.0;

        memset(&rep_muerto, 0, sizeof(rep_muerto));

        /*
         * Fase 6: optimizacion sobre el codigo intermedio.
         *
         * Va aqui, entre la generacion del TAC y todo lo demas, para que las
         * vistas posteriores -- --ir, --bloques, --vivacidad, el ensamblador y
         * el binario -- muestren exactamente el codigo que se va a ejecutar. Si
         * se optimizara despues del volcado, el listado y el programa dirian
         * cosas distintas.
         */
        if (nivel_opt > 0) {
            clock_t t0 = clock();
            if (modo_verbose)
                fprintf(stderr, "== Fase 6: Optimizacion (-O%d) -- %s ==\n",
                        nivel_opt, archivo_fuente);
            muerto_eliminar(tac, &rep_muerto, 1);
            ms_opt = 1000.0 * (double)(clock() - t0) / CLOCKS_PER_SEC;
        }

        if (modo_ir) {
            FILE *salida = stdout;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida, "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            tac_print(salida, tac);
            if (salida != stdout) fclose(salida);
        }
        if (modo_bloques) {
            /*
             * Bloques basicos y grafo de flujo. Se construye sobre la misma
             * lista de tres direcciones que alimenta a la fase 4, no sobre una
             * copia: lo que se dibuja aqui es exactamente el codigo que se va
             * a traducir.
             */
            FILE *salida = stdout;
            GrafoFlujo *g;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida, modo_ir ? "a" : "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            g = cfg_construir(tac);
            cfg_imprimir(salida, g);
            cfg_liberar(g);
            if (salida != stdout) fclose(salida);
        }
        if (modo_vivacidad) {
            /*
             * Analisis de vivacidad sobre ese mismo grafo. Se reconstruye aqui
             * en vez de guardarlo del bloque anterior porque --bloques y
             * --vivacidad son independientes: cada una se puede pedir sola.
             */
            FILE *salida = stdout;
            GrafoFlujo *g;
            Vivacidad *v;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida,
                               (modo_ir || modo_bloques) ? "a" : "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            g = cfg_construir(tac);
            v = viv_analizar(g, tac);
            viv_imprimir(salida, v);
            viv_liberar(v);
            cfg_liberar(g);
            if (salida != stdout) fclose(salida);
        }
        if (modo_asm) {
            char *texto_asm = NULL;
            size_t largo_asm = 0;
            FILE *memoria = open_memstream(&texto_asm, &largo_asm);
            if (memoria == NULL) {
                fprintf(stderr, "novac: no se pudo crear el buffer de ensamblador\n");
                tac_free(tac);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
            gen_ok = codegen_generate_vliw(tac, tabla, memoria);
            if (fclose(memoria) != 0) gen_ok = false;
            char default_asm[PATH_MAX];
            char *derived_asm = NULL;
            const char *asm_path;
            if (archivo_salida != NULL) {
                derived_asm = cambiar_extension(archivo_salida, ".asm");
                asm_path = derived_asm;
            } else {
                nombre_por_omision(archivo_fuente, 0, default_asm, sizeof(default_asm));
                size_t used = strlen(default_asm);
                if (used + sizeof(".asm") > sizeof(default_asm)) {
                    free(texto_asm);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
                memcpy(default_asm + used, ".asm", sizeof(".asm"));
                asm_path = default_asm;
            }
            FILE *asm_file = fopen(asm_path, "w");
            if (asm_file == NULL) {
                fprintf(stderr, "novac: no se pudo escribir el ensamblador '%s'\n", asm_path);
                gen_ok = false;
            } else {
                if (fwrite(texto_asm, 1, largo_asm, asm_file) != largo_asm) gen_ok = false;
                if (fclose(asm_file) != 0) gen_ok = false;
            }
            if (fwrite(texto_asm, 1, largo_asm, stdout) != largo_asm) gen_ok = false;
            if (modo_verbose && gen_ok)
                fprintf(stderr, "ensamblador escrito en '%s'\n", asm_path);
            free(derived_asm);
            free(texto_asm);
        }
        if (modo_paquetes) {
            FILE *salida = stdout;
            if (archivo_salida != NULL) {
                salida = fopen(archivo_salida, "w");
                if (salida == NULL) {
                    fprintf(stderr, "novac: no se pudo escribir el listado '%s'\n", archivo_salida);
                    tac_free(tac);
                    symtab_destroy(tabla);
                    liberar_ast(raiz_ast);
                    release_modules();
                    return 3;
                }
            }
            if (!codegen_print_packages(tac, tabla, salida)) gen_ok = false;
            if (salida != stdout && fclose(salida) != 0) gen_ok = false;
        }
        if (modo_binario) {
            /* El binario nunca va a pantalla: siempre a un archivo. */
            char nombre[256];
            const char *destino = archivo_salida;
            if (destino == NULL) {
                nombre_por_omision(archivo_fuente, 0, nombre, sizeof(nombre));
                destino = nombre;
            }
            FILE *salida = fopen(destino, "wb");
            if (salida == NULL) {
                fprintf(stderr, "novac: no se pudo escribir '%s'\n", destino);
                tac_free(tac);
                symtab_destroy(tabla);
                liberar_ast(raiz_ast);
                release_modules();
                return 3;
            }
            if (!codegen_emitir_binario(tac, tabla, salida)) gen_ok = false;
            if (fclose(salida) != 0) gen_ok = false;
            if (!gen_ok || diag_errores() > 0) remove(destino);
            else if (modo_verbose) fprintf(stderr, "ejecutable escrito en '%s'\n", destino);
        }

        if (modo_metricas) {
            /*
             * Metricas de compilacion. Las de ejecucion no se pueden medir
             * aqui: las entregan los contadores del procesador al correr el
             * binario sobre el RTL (ARQUITECTURA/tools/tabla_metricas.py).
             * Lo que se mide aqui es lo que cuesta optimizar y cuanto codigo
             * se quito; el intercambio entre las dos cosas es justamente el
             * punto: el compilador tarda mas para que el programa tarde menos.
             */
            GrafoFlujo *g = cfg_construir(tac);
            int bloques = 0, inalcanzables = 0, aristas = 0, f;

            for (f = 0; g != NULL && f < g->n_funciones; f++) {
                bloques       += g->funciones[f].n_bloques;
                aristas       += g->funciones[f].n_aristas;
                inalcanzables += g->funciones[f].n_inalcanzables;
            }

            printf("=== Metricas de compilacion ===\n");
            printf("  nivel de optimizacion:             -O%d\n", nivel_opt);
            printf("  tiempo total de compilacion:       %.2f ms\n",
                   1000.0 * (double)(clock() - reloj_inicio) / CLOCKS_PER_SEC);
            if (nivel_opt > 0)
                printf("  del cual, la fase 6:               %.2f ms\n", ms_opt);
            printf("  instrucciones de tres direcciones: %d\n",
                   nivel_opt > 0 ? rep_muerto.inst_despues
                                 : contar_tac(tac));
            if (nivel_opt > 0) {
                int quitadas = rep_muerto.inst_antes - rep_muerto.inst_despues;
                printf("    antes de optimizar:              %d\n",
                       rep_muerto.inst_antes);
                printf("    eliminadas:                      %d (%.1f%%)\n",
                       quitadas,
                       rep_muerto.inst_antes > 0
                           ? 100.0 * quitadas / rep_muerto.inst_antes : 0.0);
                printf("      en bloques inalcanzables:      %d (en %d bloque%s)\n",
                       rep_muerto.inst_de_bloques,
                       rep_muerto.bloques_eliminados,
                       rep_muerto.bloques_eliminados == 1 ? "" : "s");
                printf("      definiciones muertas:          %d\n",
                       rep_muerto.definiciones_muertas);
                printf("      resultados de llamada sueltos: %d\n",
                       rep_muerto.resultados_descartados);
                printf("    rondas hasta el punto fijo:      %d\n",
                       rep_muerto.rondas);
            }
            printf("  bloques basicos:                   %d\n", bloques);
            printf("  aristas del grafo:                 %d\n", aristas);
            printf("  bloques inalcanzables que quedan:  %d\n", inalcanzables);
            cfg_liberar(g);

            {
                /*
                 * Tamano del codigo que de verdad se emite. Cada bundle es un
                 * ciclo de emision, asi que menos bundles es menos tiempo de
                 * ejecucion; la ocupacion dice cuanto del ancho VLIW se esta
                 * aprovechando, y es lo que ataca la Iteracion 4.
                 */
                CodegenEstadisticas ce;
                if (codegen_estadisticas(&ce) > 0) {
                    printf("  bundles emitidos:                  %d  (%d bytes de IMEM)\n",
                           ce.bundles, ce.bundles * 16);
                    printf("    slots con trabajo:               %d de %d\n",
                           ce.slots_usados, ce.bundles * 5);
                    printf("    ocupacion media:                 %.2f de 5 ranuras\n",
                           ce.bundles > 0
                               ? (double)ce.slots_usados / ce.bundles : 0.0);
                    printf("    bundles totalmente vacios:       %d (%.1f%%)\n",
                           ce.bundles_vacios,
                           ce.bundles > 0
                               ? 100.0 * ce.bundles_vacios / ce.bundles : 0.0);
                }
            }
        }

        tac_free(tac);

        if (!gen_ok || diag_errores() > 0) {
            symtab_destroy(tabla);
            liberar_ast(raiz_ast);
            release_modules();
            diag_resumen();
            return 1;
        }
        if (modo_verbose) fprintf(stderr, "Fase 4 completada sin errores.\n");
    }

    /* Las advertencias se resumen aunque la compilacion haya salido bien. */
    if (diag_advertencias() > 0) diag_resumen();

    symtab_destroy(tabla);
    liberar_ast(raiz_ast);
    release_modules();
    return 0;
}