#!/bin/sh
# Depuracion del compilador de Nova, una fase a la vez.
#
#   sh tools/depurar.sh              # todo, en orden
#   sh tools/depurar.sh build        # compilacion limpia y sin advertencias
#   sh tools/depurar.sh fase1        # analisis lexico
#   sh tools/depurar.sh fase2        # analisis sintactico
#   sh tools/depurar.sh fase3        # analisis semantico
#   sh tools/depurar.sh fase4        # codigo intermedio y ensamblador
#   sh tools/depurar.sh cerbero      # contraste con el ensamblador de CE4301
#   sh tools/depurar.sh cobertura    # tokens y codigos de error ejercitados
#   sh tools/depurar.sh memoria      # sanitizers y valgrind
#   sh tools/depurar.sh robustez     # el compilador no debe caerse con nada
#   sh tools/depurar.sh opciones     # banderas y codigos de salida
#
# Cada objetivo imprime lo que verifica y termina en 0 si todo paso.

set -u
NOVAC=./novac

# Todo lo que los objetivos generan -- fuentes de prueba, ensamblador,
# ejecutables y volcados -- va a un directorio temporal que se borra solo al
# terminar, para no dejar nada en la raiz del proyecto.
TMP=${TMPDIR:-/tmp}/nova_depurar_$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' 0 2 15
FALLOS=0
SECCION=""

titulo() { SECCION="$1"; printf '\n========== %s ==========\n' "$1"; }
ok()     { printf '  ok    %s\n' "$1"; }
falla()  { printf '  FALLA %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
nota()   { printf '        %s\n' "$1"; }

existe_novac() {
    [ -x "$NOVAC" ] || { echo "no existe $NOVAC: corra 'make' primero"; exit 2; }
}

# ---------------------------------------------------------------- build
d_build() {
    titulo "Compilacion"
    make clean >/dev/null 2>&1
    salida=$(make 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        falla "make devolvio $rc"
        echo "$salida" | tail -20 | sed 's/^/        /'
        return
    fi
    ok "make termina sin errores"

    n=$(echo "$salida" | grep -ci 'warning' || true)
    if [ "$n" -eq 0 ]; then ok "0 advertencias de gcc con -Wall -Wextra"
    else
        falla "$n advertencias de gcc"
        echo "$salida" | grep -i 'warning' | head -10 | sed 's/^/        /'
    fi

    # Las dependencias de encabezados deben existir: si faltan, cambiar un .h
    # no recompila y quedan objetos contra estructuras distintas.
    if [ -f fase3_semantico/symtab.d ]; then ok "se generaron los .d (dependencias de encabezados)"
    else falla "no hay archivos .d: el Makefile no esta generando dependencias"; fi
}

# ---------------------------------------------------------------- fase 1
d_fase1() {
    titulo "Fase 1: analisis lexico"
    existe_novac

    # La tabla de tokens debe salir con lexema, token, linea y columna.
    salida=$($NOVAC --tokens test/factorial.nv 2>&1)
    case "$salida" in
        *LEXEMA*TOKEN*LINEA*COL*) ok "--tokens imprime la tabla con encabezado" ;;
        *) falla "--tokens no imprimio el encabezado esperado" ;;
    esac

    # El conteo que reporta debe coincidir con las filas impresas.
    declarados=$(echo "$salida" | sed -n 's/^-- \([0-9]*\) tokens --$/\1/p')
    filas=$(echo "$salida" | grep -c '[[:space:]]TK_[A-Z_]')
    if [ "$declarados" = "$filas" ]; then ok "el total declarado ($declarados) coincide con las filas"
    else falla "declara $declarados tokens pero imprimio $filas filas"; fi

    # Cada error lexico debe dispararse con su codigo.
    for f in test/errores/E1*.nv; do
        [ -f "$f" ] || continue
        nombre=$(basename "$f" .nv); codigo=${nombre%%_*}
        obtenidos=$($NOVAC --tokens "$f" 2>&1 | grep -o "error\[E[0-9]*\]" | sed 's/.*\[\(.*\)\]/\1/' | sort -u | tr '\n' ' ')
        case " $obtenidos " in
            *" $codigo "*) ok "$codigo se reporta en modo --tokens" ;;
            *) falla "$codigo no aparecio ($nombre dio [$obtenidos])" ;;
        esac
    done

    # Varios errores lexicos en una sola corrida: no debe abortar en el primero.
    n=$($NOVAC --tokens test/lexico/multi_lexicos.nv 2>&1 | grep -c 'error\[')
    if [ "$n" -eq 5 ]; then ok "reporta los 5 errores lexicos de una sola pasada"
    else falla "esperaba 5 errores lexicos y dio $n"; fi

    # Un hexadecimal con letras no es un identificador pegado a un numero.
    printf 'constans A : integer = 0xDEADBEEF;\n' > "$TMP/hex.nv"
    salida=$($NOVAC -t "$TMP/hex.nv" 2>&1); rm -f "$TMP/hex.nv"
    case "$salida" in
        *"Entero -559038737"*) ok "0xDEADBEEF vale -559038737 (integer de 32 bits con signo)" ;;
        *"Entero 3735928559"*) falla "0xDEADBEEF da 3735928559: falta el casteo a int de 32 bits en nova.l" ;;
        *) falla "0xDEADBEEF no se reconocio"; echo "$salida" | sed 's/^/        /' ;;
    esac
}

# ---------------------------------------------------------------- fase 2
d_fase2() {
    titulo "Fase 2: analisis sintactico"
    existe_novac

    # La gramatica debe quedar sin conflictos. Es lo primero que se revisa en
    # una defensa: un conflicto significa que Bison desempato por omision.
    salida=$(bison -Wall --report=all -d -o fase2_sintactico/nova.tab.c \
                   fase2_sintactico/nova.y 2>&1)
    n=$(echo "$salida" | grep -ci 'conflict' || true)
    if [ "$n" -eq 0 ]; then ok "0 conflictos shift/reduce y reduce/reduce"
    else
        falla "bison reporta conflictos"
        echo "$salida" | grep -i conflict | sed 's/^/        /'
        nota "el detalle queda en fase2_sintactico/nova.output"
    fi

    n=$(echo "$salida" | grep -ci 'useless\|nunca se reduce\|never reduced' || true)
    if [ "$n" -eq 0 ]; then ok "no hay reglas ni no terminales inutiles"
    else falla "bison reporta reglas inutiles"; echo "$salida" | sed 's/^/        /'; fi

    # El AST de cada ejemplo debe construirse completo.
    for f in test/ejemplos/*.nv test/factorial.nv; do
        [ -f "$f" ] || continue
        salida=$($NOVAC -t "$f" 2>&1); rc=$?
        case "$salida" in
            *"Programa"*"Globales"*"Funcion"*)
                [ $rc -eq 0 ] && ok "AST de $(basename "$f")" \
                              || falla "AST de $(basename "$f") con rc=$rc" ;;
            *) falla "el AST de $(basename "$f") no tiene la forma esperada" ;;
        esac
    done

    # Errores sintacticos, uno por codigo.
    for f in test/errores/E2*.nv; do
        [ -f "$f" ] || continue
        nombre=$(basename "$f" .nv); codigo=${nombre%%_*}
        obtenidos=$($NOVAC "$f" 2>&1 | grep -o "error\[E[0-9]*\]" | sed 's/.*\[\(.*\)\]/\1/' | sort -u | tr '\n' ' ')
        case " $obtenidos " in
            *" $codigo "*) ok "$codigo se reporta" ;;
            *) falla "$codigo no aparecio ($nombre dio [$obtenidos])" ;;
        esac
    done

    # El extractor de producciones no debe dejar ni una linea de C: es con lo
    # que se compara la gramatica del documento.
    if command -v python3 >/dev/null 2>&1; then
        prod=$(python3 tools/producciones.py 2>&1)
        if [ $? -ne 0 ]; then
            falla "tools/producciones.py devolvio error"
            echo "$prod" | tail -5 | sed 's/^/        /'
        else
            n=$(echo "$prod" | grep -cE 'nodo_nuevo|agregar_hijo|diag_error|yyerror' || true)
            if [ "$n" -eq 0 ]; then ok "producciones.py extrae la gramatica sin codigo C"
            else falla "quedaron $n lineas de C en las producciones extraidas"; fi
        fi
    else
        nota "python3 no esta disponible; se omite el extractor"
    fi

    # Recuperacion de errores: varios errores sintacticos en una corrida.
    n=$($NOVAC test/errores/multi_mezcla.nv 2>&1 | grep -c 'error\[')
    if [ "$n" -ge 4 ]; then ok "la recuperacion en modo panico reporta $n errores de una vez"
    else falla "solo reporto $n errores: la recuperacion no esta avanzando"; fi
}

# ---------------------------------------------------------------- fase 3
d_fase3() {
    titulo "Fase 3: analisis semantico"
    existe_novac

    # Ningun programa valido debe producir errores ni advertencias. W009 queda
    # fuera: no es un reparo a la fase 3 sino el tamano del codigo frente a la
    # IMEM de CERBERO, y hay programas de referencia que no caben. El reporte de
    # ocupacion esta en el bloque 15 de tools/verificar.sh.
    for f in test/factorial.nv test/ejemplos/*.nv; do
        [ -f "$f" ] || continue
        salida=$($NOVAC -Wno-W009 --sym "$f" 2>&1); rc=$?
        ne=$(echo "$salida" | grep -c 'error\[')
        na=$(echo "$salida" | grep -c 'advertencia\[')
        if [ $rc -eq 0 ] && [ "$ne" -eq 0 ] && [ "$na" -eq 0 ]; then
            ok "$(basename "$f") limpio"
        else
            falla "$(basename "$f"): rc=$rc, $ne errores, $na advertencias"
            echo "$salida" | grep 'error\[\|advertencia\[' | head -5 | sed 's/^/        /'
        fi
    done

    # La tabla de simbolos debe traer encabezado, direcciones y el resumen.
    salida=$($NOVAC --sym test/ejemplos/traza.nv 2>&1)
    case "$salida" in
        *"=== Tabla de simbolos ==="*) ok "--sym imprime la tabla" ;;
        *) falla "--sym no imprimio la tabla" ;;
    esac
    case "$salida" in
        *"DMEM @0x"*"= r14"*)
            ok "las locales traen su direccion de memoria y su offset de R14" ;;
        *) falla "falta la direccion de memoria de las locales en la tabla" ;;
    esac
    case "$salida" in
        *"marco "*"B"*) ok "cada funcion reporta el tamano de su marco" ;;
        *) falla "falta el tamano del marco en la tabla" ;;
    esac
    case "$salida" in
        *"datos globales:"*"pila:"*) ok "el resumen de memoria de CERBERO sale completo" ;;
        *) falla "falta el resumen de memoria" ;;
    esac
    # integer[N][N] con N=3 debe resolverse a 36 bytes, no a 4.
    case "$salida" in
        *"integer[3][3]"*) ok "integer[N][N] se resolvio con la constante plegada" ;;
        *) falla "integer[N][N] no se resolvio: revise el plegado de constantes" ;;
    esac

    # Un error por codigo.
    for f in test/errores/E3*.nv test/errores/E4*.nv; do
        [ -f "$f" ] || continue
        nombre=$(basename "$f" .nv); codigo=${nombre%%_*}
        obtenidos=$($NOVAC "$f" 2>&1 | grep -o "error\[E[0-9]*\]" | sed 's/.*\[\(.*\)\]/\1/' | sort -u | tr '\n' ' ')
        case " $obtenidos " in
            *" $codigo "*) ok "$codigo se reporta" ;;
            *) falla "$codigo no aparecio ($nombre dio [$obtenidos])" ;;
        esac
    done

    # Una advertencia por codigo, y el programa debe seguir compilando.
    for f in test/advertencias/W*.nv; do
        [ -f "$f" ] || continue
        nombre=$(basename "$f" .nv); codigo=${nombre%%_*}
        salida=$($NOVAC "$f" -o "$TMP/a.out" 2>&1); rc=$?
        obtenidos=$(echo "$salida" | grep -o "advertencia\[W[0-9]*\]" | sed 's/.*\[\(.*\)\]/\1/' | sort -u | tr '\n' ' ')
        case " $obtenidos " in
            *" $codigo "*)
                [ $rc -eq 0 ] && ok "$codigo se reporta y no detiene la compilacion" \
                              || falla "$codigo detuvo la compilacion (rc=$rc)" ;;
            *) falla "$codigo no aparecio ($nombre dio [$obtenidos])" ;;
        esac
    done

    # La marca ^ debe caer sobre el identificador, no sobre la palabra reservada.
    salida=$($NOVAC test/errores/E309_falta_redde.nv 2>&1)
    col=$(echo "$salida" | sed -n '1s/.*nv:\([0-9]*\):\([0-9]*\):.*/\2/p')
    if [ "$col" = "9" ]; then ok "E309 apunta al nombre de la funcion (columna 9)"
    else falla "E309 apunta a la columna $col y deberia ser la 9 (el nombre)"; fi
}

# ---------------------------------------------------------------- fase 4
d_fase4() {
    titulo "Fase 4: codigo intermedio y ensamblador"
    existe_novac

    # El TAC se genera para todos los ejemplos sin errores.
    for f in test/factorial.nv test/ejemplos/*.nv; do
        [ -f "$f" ] || continue
        salida=$($NOVAC --ir "$f" 2>&1); rc=$?
        if [ $rc -eq 0 ]; then ok "TAC de $(basename "$f")"
        else falla "TAC de $(basename "$f") con rc=$rc"; echo "$salida" | head -4 | sed 's/^/        /'; fi
    done

    # Las comparaciones no pueden salir como sumas: ese fue el error que se
    # corrigio, y es el que mas facil se vuelve a colar.
    salida=$($NOVAC --ir test/factorial.nv 2>&1)
    case "$salida" in
        *"n < t"*) ok "las comparaciones se traducen como comparaciones" ;;
        *) falla "no aparece ninguna comparacion en el TAC de factorial.nv" ;;
    esac
    case "$salida" in
        *"call factorial"*) ok "las llamadas aparecen en el TAC" ;;
        *) falla "la llamada a factorial no aparece en el TAC" ;;
    esac
    case "$salida" in
        *"goto L"*) ok "los ciclos conservan su estructura de saltos" ;;
        *) falla "el ciclo de factorial.nv se aplano" ;;
    esac

    # Los tres desplazamientos de Nova son tres instrucciones distintas.
    salida=$($NOVAC -s test/ejemplos/desplazamientos.nv -o "$TMP/x.nvx" 2>&1)
    for par in "sll:<<" "srl:>>>" "sra:>>"; do
        mn=${par%%:*}; nv=${par##*:}
        case "$salida" in
            *"$mn "*) ok "$nv se emite como $mn" ;;
            *) falla "$nv no produjo $mn" ;;
        esac
    done

    # La multiplicacion existe en el ISA y debe emitirse.
    salida=$($NOVAC -s test/factorial.nv -o "$TMP/x.nvx" 2>&1)
    case "$salida" in
        *"mul r"*) ok "la multiplicacion se emite como mul" ;;
        *) falla "no se emitio mul: la multiplicacion se esta perdiendo" ;;
    esac
    # Ningun bundle puede quedar con una instruccion inventada.
    for m in lsl lsr "jal " "jr r15"; do
        if echo "$salida" | grep -q "$m"; then
            falla "se emitio '$m', que no existe en el ISA de CERBERO"
        else
            ok "no se emite '$m'"
        fi
    done
    case "$salida" in
        *"jal.al"*) ok "las llamadas usan jal.al" ;;
        *) falla "no se encontro jal.al" ;;
    esac
    case "$salida" in
        *"jr.al r15"*) ok "los retornos usan jr.al r15" ;;
        *) falla "no se encontro jr.al r15" ;;
    esac
    case "$salida" in
        *halt*) ok "el programa termina con halt" ;;
        *) falla "no se emitio halt: el programa no puede terminar" ;;
    esac

    # Los resultados se verifican en el RTL, no con un modelo de software.
    if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
        for caso in "test/factorial.nv:120" "test/ejecucion/matriz_for.nv:138"; do
            fuente=${caso%:*}
            esperado=${caso##*:}
            if sh test/run_rtl_test.sh "$NOVAC" "$fuente" "$esperado" \
                "${CERBERO_CPU:-ARQUITECTURA/src/cpu}" > "$TMP/rtl.log" 2>&1; then
                ok "$(basename "$fuente") ejecutado en el RTL (R6=$esperado)"
            else
                falla "$(basename "$fuente") fallo en el RTL"
                tail -8 "$TMP/rtl.log" | sed 's/^/        /'
            fi
        done
    else
        nota "iverilog/vvp no estan disponibles; se omite la ejecucion RTL"
    fi
}

# ---------------------------------------------------------------- cobertura
d_cobertura() {
    titulo "Cobertura"
    existe_novac

    # Todo token de la gramatica debe aparecer al menos una vez en el corpus.
    grep -o "TK_[A-Z_]*" fase2_sintactico/nova.tab.h | sort -u > "$TMP/todos"
    for f in test/*.nv test/ejemplos/*.nv; do
        [ -f "$f" ] || continue
        $NOVAC --tokens "$f" 2>/dev/null
    done | grep -o "TK_[A-Z_]*" | grep -v '^TK_EOF$' | sort -u > "$TMP/vistos"

    total=$(grep -c . "$TMP/todos")
    vistos=$(grep -c . "$TMP/vistos")
    faltan=$(comm -23 "$TMP/todos" "$TMP/vistos" | tr '\n' ' ')
    if [ -z "$faltan" ]; then ok "los $total tokens de la gramatica se ejercitan"
    else
        falla "$vistos de $total tokens ejercitados"
        nota "sin probar: $faltan"
    fi
    rm -f "$TMP/todos" "$TMP/vistos"

    # Todo codigo que el compilador puede emitir debe tener una prueba.
    # Se buscan las dos formas: el codigo literal en la llamada a diag_error,
    # y la asignacion a la variable 'codigo' que usa el clasificador de
    # errores sintacticos. Sin la segunda, E203 a E209 quedaban invisibles
    # para esta verificacion aunque el compilador si los emite.
    grep -ho 'diag_error("E[0-9]*"\|diag_advertencia("W[0-9]*"\|codigo = "E[0-9]*"' \
         fase1_lexico/nova.l fase2_sintactico/nova.y \
         fase3_semantico/semantic.c fase4_codigo/codegen.c \
        | sed 's/.*"\([EW][0-9]*\)".*/\1/' | sort -u > "$TMP/emite"
    ls test/errores/*.nv test/advertencias/*.nv 2>/dev/null \
        | sed 's|.*/||; s/_.*//; s/\.nv$//' | grep '^[EW][0-9]' | sort -u > "$TMP/probados"

    # E410 es la verificacion interna del generador: avisa que la fase 4 no
    # encontro algo que la fase 3 debio dejar ubicado. Por construccion no se
    # puede provocar desde un fuente valido, asi que no lleva archivo de
    # prueba; si alguna vez aparece, es un error del compilador, no del
    # programa que se compila.
    echo "E410" >> "$TMP/probados"
    sort -u -o "$TMP/probados" "$TMP/probados"

    sin_prueba=$(comm -23 "$TMP/emite" "$TMP/probados" | tr '\n' ' ')
    if [ -z "$sin_prueba" ]; then
        ok "los $(grep -c . "$TMP/emite") codigos que el compilador emite tienen prueba"
    else
        falla "codigos sin archivo de prueba: $sin_prueba"
    fi
    rm -f "$TMP/emite" "$TMP/probados"
}

# ---------------------------------------------------------------- memoria
d_memoria() {
    titulo "Memoria"

    # ASan + UBSan: detectan desbordes, uso despues de liberar y
    # comportamiento indefinido que -Wall no ve.
    make clean >/dev/null 2>&1
    if make CFLAGS="-Wall -Wextra -g -MMD -MP -fsanitize=address,undefined \
-fno-omit-frame-pointer -Ifase1_lexico -Ifase2_sintactico -Ifase3_semantico \
-Ifase4_codigo" >/dev/null 2>&1; then
        ok "compila con -fsanitize=address,undefined"
        malos=0
        for f in test/factorial.nv test/ejemplos/*.nv test/errores/*.nv \
                 test/advertencias/*.nv; do
            [ -f "$f" ] || continue
            salida=$(ASAN_OPTIONS=detect_leaks=1 $NOVAC --sym --ir -s "$f" -o "$TMP/x.nvx" 2>&1)
            case "$salida" in
                *"runtime error"*|*"AddressSanitizer"*|*"LeakSanitizer"*)
                    falla "sanitizer en $(basename "$f")"
                    echo "$salida" | grep -A3 'runtime error\|ERROR:' | head -6 | sed 's/^/        /'
                    malos=$((malos + 1)) ;;
            esac
        done
        [ "$malos" -eq 0 ] && ok "todo el corpus pasa los sanitizers sin hallazgos"
    else
        nota "los sanitizers no estan disponibles en este gcc; se omite"
    fi
    make clean >/dev/null 2>&1
    make >/dev/null 2>&1

    if command -v valgrind >/dev/null 2>&1; then
        malos=0
        for f in test/factorial.nv test/ejemplos/*.nv; do
            [ -f "$f" ] || continue
            if ! valgrind -q --error-exitcode=9 --leak-check=full \
                 --errors-for-leak-kinds=definite \
                 $NOVAC --sym --ir -s "$f" -o "$TMP/vg.nvx" >/dev/null 2>"$TMP/vg"; then
                falla "valgrind en $(basename "$f")"
                head -8 "$TMP/vg" | sed 's/^/        /'
                malos=$((malos + 1))
            fi
        done
        rm -f "$TMP/vg"
        [ "$malos" -eq 0 ] && ok "valgrind sin errores ni fugas definitivas"
    else
        nota "valgrind no esta instalado (sudo apt install valgrind); se omite"
    fi
}

# ---------------------------------------------------------------- robustez
d_robustez() {
    titulo "Robustez"
    existe_novac

    # El compilador puede rechazar lo que quiera, pero nunca caerse. Se le dan
    # todos los prefijos truncados de cada ejemplo, que es la forma mas rapida
    # de encontrar un AST a medias que la fase 3 no esperaba.
    caidas=0
    casos=0
    for f in test/factorial.nv test/ejemplos/*.nv; do
        [ -f "$f" ] || continue
        total=$(wc -l < "$f")
        i=1
        while [ "$i" -le "$total" ]; do
            head -n "$i" "$f" > "$TMP/trunc.nv"
            $NOVAC --sym "$TMP/trunc.nv" >/dev/null 2>&1
            rc=$?
            casos=$((casos + 1))
            # 0 ok, 1 errores, 2 uso, 3 E/S. Cualquier otro es una senal.
            if [ $rc -gt 3 ]; then
                falla "rc=$rc con las primeras $i lineas de $(basename "$f")"
                caidas=$((caidas + 1))
            fi
            i=$((i + 1))
        done
    done
    rm -f "$TMP/trunc.nv"
    [ "$caidas" -eq 0 ] && ok "$casos prefijos truncados, ninguna caida"

    # Entradas degeneradas.
    : > "$TMP/vacio.nv"
    $NOVAC "$TMP/vacio.nv" >/dev/null 2>&1
    [ $? -le 1 ] && ok "archivo vacio" || falla "archivo vacio dio rc=$?"

    printf '{{{{{{{{{{\n' > "$TMP/basura.nv"
    $NOVAC "$TMP/basura.nv" >/dev/null 2>&1
    [ $? -le 1 ] && ok "archivo de pura basura" || falla "basura dio rc=$?"

    # Anidamiento profundo: no debe desbordar la pila del compilador.
    { printf 'functio principale() -> integer {\n'
      i=0; while [ $i -lt 60 ]; do printf '  si (verum) {\n'; i=$((i+1)); done
      printf '  redde 0;\n'
      i=0; while [ $i -lt 60 ]; do printf '  }\n'; i=$((i+1)); done
      printf '  redde 0;\n}\n'; } > "$TMP/profundo.nv"
    $NOVAC --sym "$TMP/profundo.nv" >/dev/null 2>&1
    [ $? -le 1 ] && ok "60 niveles de si anidados" || falla "anidamiento profundo dio rc=$?"

    # Expresion muy larga.
    { printf 'functio principale() -> integer {\n  redde 1'
      i=0; while [ $i -lt 400 ]; do printf ' + 1'; i=$((i+1)); done
      printf ';\n}\n'; } > "$TMP/larga.nv"
    $NOVAC "$TMP/larga.nv" -o "$TMP/a.out" >/dev/null 2>&1
    [ $? -le 1 ] && ok "expresion de 400 terminos" || falla "expresion larga dio rc=$?"

    rm -f "$TMP/vacio.nv" "$TMP/basura.nv" "$TMP/profundo.nv" "$TMP/larga.nv"
}

# ---------------------------------------------------------------- opciones
d_opciones() {
    titulo "Banderas y codigos de salida"
    existe_novac

    $NOVAC --help >/dev/null 2>&1
    [ $? -eq 0 ] && ok "--help devuelve 0" || falla "--help devolvio $?"

    $NOVAC --version >/dev/null 2>&1
    [ $? -eq 0 ] && ok "--version devuelve 0" || falla "--version devolvio $?"

    $NOVAC >/dev/null 2>&1
    [ $? -eq 2 ] && ok "sin argumentos devuelve 2 (error de uso)" || falla "sin argumentos devolvio $?"

    $NOVAC /no/existe.nv >/dev/null 2>&1
    [ $? -eq 3 ] && ok "archivo inexistente devuelve 3" || falla "archivo inexistente devolvio $?"

    $NOVAC test/factorial.nv -o "$TMP/exe" >/dev/null 2>&1
    [ $? -eq 0 ] && ok "programa valido devuelve 0" || falla "programa valido devolvio $?"
    rm -f "$TMP/exe"

    $NOVAC test/errores/E301_no_declarado.nv >/dev/null 2>&1
    [ $? -eq 1 ] && ok "programa con errores devuelve 1" || falla "programa con errores devolvio $?"

    $NOVAC --max-errors 0 test/errores/multi_mezcla.nv >/dev/null 2>&1
    [ $? -eq 2 ] && ok "--max-errors 0 es error de uso" || falla "--max-errors 0 devolvio $?"

    n=$($NOVAC --max-errors 2 test/errores/multi_mezcla.nv 2>&1 | grep -c 'error\[')
    [ "$n" -eq 2 ] && ok "--max-errors 2 corta en 2 errores" || falla "--max-errors 2 mostro $n"

    # -o debe escribir a archivo y no a pantalla.
    $NOVAC -t -o "$TMP/ast.txt" test/factorial.nv >/dev/null 2>&1
    if [ -s "$TMP/ast.txt" ] && grep -q "Programa" "$TMP/ast.txt"; then
        ok "-o escribe el AST al archivo"
    else
        falla "-o no escribio el AST"
    fi
    rm -f "$TMP/ast.txt"

    # Los diagnosticos van a stderr, no a stdout: asi se pueden filtrar.
    salida=$($NOVAC test/errores/E301_no_declarado.nv 2>/dev/null)
    if [ -z "$salida" ]; then ok "los diagnosticos salen por stderr"
    else falla "hay diagnosticos en stdout"; fi

    # Una compilacion exitosa es silenciosa; -v debe nombrar las cuatro fases.
    salida=$($NOVAC test/factorial.nv -o "$TMP/exe" 2>&1)
    if [ -z "$salida" ]; then ok "una compilacion limpia no imprime nada"
    else falla "una compilacion limpia imprimio algo"; echo "$salida" | sed 's/^/        /'; fi
    rm -f "$TMP/exe"

    salida=$($NOVAC -v test/factorial.nv -o "$TMP/exe" 2>&1)
    faltan=""
    for fase in "Fase 1" "Fase 2" "Fase 3" "Fase 4"; do
        case "$salida" in *"$fase"*) ;; *) faltan="$faltan $fase" ;; esac
    done
    if [ -z "$faltan" ]; then ok "-v nombra las cuatro fases"
    else falla "-v no menciona:$faltan"; fi
    rm -f "$TMP/exe"

    # --- Las banderas de advertencias que promete el documento -------------
    W=test/advertencias/W001_variable_sin_usar.nv

    n=$($NOVAC -Wall "$W" -o "$TMP/exe" 2>&1 | grep -c 'advertencia\[W001\]')
    [ "$n" -eq 1 ] && ok "-Wall deja la advertencia activa" || falla "-Wall mostro $n advertencias"
    rm -f "$TMP/exe"

    salida=$($NOVAC -w "$W" -o "$TMP/exe" 2>&1); rc=$?
    if [ -z "$salida" ] && [ $rc -eq 0 ]; then ok "-w silencia las advertencias"
    else falla "-w no silencio nada (rc=$rc)"; echo "$salida" | sed 's/^/        /'; fi
    rm -f "$TMP/exe"

    salida=$($NOVAC -Wno-W001 "$W" -o "$TMP/exe" 2>&1)
    case "$salida" in
        *W001*) falla "-Wno-W001 no silencio W001" ;;
        *) ok "-Wno-W001 silencia solo esa advertencia" ;;
    esac
    rm -f "$TMP/exe"

    salida=$($NOVAC -Werror "$W" -o "$TMP/exe" 2>&1); rc=$?
    case "$salida" in
        *"error[W001]"*)
            [ $rc -eq 1 ] && ok "-Werror convierte la advertencia en error y devuelve 1" \
                          || falla "-Werror devolvio $rc en lugar de 1" ;;
        *) falla "-Werror no reporto W001 como error"; echo "$salida" | sed 's/^/        /' ;;
    esac
    [ -f "$TMP/exe" ] && falla "-Werror dejo un ejecutable a pesar del error" || ok "-Werror no deja ejecutable"
    rm -f "$TMP/exe"

    $NOVAC -Wloquesea "$W" >/dev/null 2>&1
    [ $? -eq 2 ] && ok "una bandera -W desconocida es error de uso" || falla "-Wloquesea devolvio $?"

    # --- Salida binaria por omision ---------------------------------------
    # El nombre por omision se comprueba desde el directorio temporal, para
    # no dejar el ejecutable en la raiz del proyecto.
    raiz=$(pwd)
    cp test/factorial.nv "$TMP/factorial.nv"
    ( cd "$TMP" && "$raiz/novac" factorial.nv >/dev/null 2>&1 )
    if [ -s "$TMP/factorial" ]; then ok "sin banderas produce el ejecutable con el nombre del fuente"
    else falla "no se produjo el ejecutable 'factorial'"; fi

    # Objetos .nvo y enlace por imports.
    $NOVAC -c test/errores/E405_falta_principale.nv -o "$TMP/modulo.nvo" >/dev/null 2>&1
    if [ $? -eq 0 ] && [ "$(dd if="$TMP/modulo.nvo" bs=1 count=4 2>/dev/null)" = "NVO1" ]; then
        ok "-c produce un objeto .nvo con cabecera valida"
    else
        falla "-c no produjo un objeto .nvo valido"
    fi
    printf 'importa "modulo.nvo" ut m;\nfunctio principale() -> integer { redde m.doble(21); }\n' > "$TMP/enlace.nv"
    $NOVAC "$TMP/enlace.nv" -o "$TMP/enlace.nvx" >/dev/null 2>&1
    [ $? -eq 0 ] && [ -s "$TMP/enlace.nvx" ] \
        && ok "el enlace resuelve llamadas exportadas desde .nvo" \
        || falla "no se pudo enlazar una llamada desde .nvo"

    # Un programa con advertencias compila y debe decir cuantas hubo.
    salida=$($NOVAC test/advertencias/W001_variable_sin_usar.nv -o "$TMP/a.out" 2>&1); rc=$?
    case "$salida" in
        *"compilacion terminada: 1 advertencia"*)
            [ $rc -eq 0 ] && ok "resume las advertencias sin abortar" \
                          || falla "el resumen de advertencias dio rc=$rc" ;;
        *) falla "no se resumieron las advertencias"; echo "$salida" | sed 's/^/        /' ;;
    esac

    # Y con errores debe decir abortada, no terminada.
    salida=$($NOVAC test/errores/E301_no_declarado.nv 2>&1)
    case "$salida" in
        *"compilacion abortada: 1 error"*) ok "resume los errores como 'abortada'" ;;
        *) falla "el resumen de errores no tiene la forma esperada" ;;
    esac
}

# ---------------------------------------------------------------- principal
objetivo=${1:-todo}
d_cerbero() {
    titulo "Contraste con el ensamblador de CERBERO"
    existe_novac

    # El proyecto de CE4301 trae su propio ensamblador. Si esta a mano, es la
    # verificacion mas fuerte que existe: dos implementaciones independientes
    # de la codificacion del ISA tienen que producir los mismos 128 bits.
    ASM=${CERBERO_ASM:-}
    if [ -z "$ASM" ]; then
        for c in ARQUITECTURA/tools/cerbero_asm.py \
                 ../cerbero/tools/cerbero_asm.py ../../cerbero/tools/cerbero_asm.py \
                 ../cerbero/cerbero/tools/cerbero_asm.py; do
            [ -f "$c" ] && ASM=$c && break
        done
    fi
    if [ -z "$ASM" ] || [ ! -f "$ASM" ]; then
        nota "no se encontro cerbero_asm.py; se omite"
        nota "para correrlo: CERBERO_ASM=/ruta/a/cerbero_asm.py make depurar F=cerbero"
        return
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        nota "python3 no esta disponible; se omite"; return
    fi

    ok "se encontro el ensamblador de CERBERO"
    iguales=0; distintos=0; pendientes=0
    for f in test/factorial.nv test/ejemplos/*.nv test/ejecucion/*.nv; do
        [ -f "$f" ] || continue
        n=$(basename "$f" .nv)
        $NOVAC -s "$f" -o "$TMP/c.nvx" > "$TMP/c.s" 2>/dev/null || continue
        if ! python3 "$ASM" "$TMP/c.s" -o "$TMP/c.hex" >"$TMP/c.err" 2>&1; then
            case "$(cat "$TMP/c.err")" in
                *'inmediato mal formado'*'$'*) pendientes=$((pendientes + 1)) ;;
                *) falla "$n: cerbero_asm lo rechaza"
                   head -2 "$TMP/c.err" | sed 's/^/        /'
                   distintos=$((distintos + 1)) ;;
            esac
            continue
        fi
        $NOVAC "$f" -o "$TMP/c.bin" 2>/dev/null || continue
        if python3 - "$TMP/c.bin" "$TMP/c.hex" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
u = lambda o: int.from_bytes(d[o:o+4], 'little')
n = u(8)
nova = [(u(48+b*16+12) << 96) | (u(48+b*16+8) << 64) |
        (u(48+b*16+4) << 32) | u(48+b*16) for b in range(n)]
suyo = [int(l.strip(), 16) for l in open(sys.argv[2]) if l.strip()]
sys.exit(0 if nova == suyo else 1)
PY
        then iguales=$((iguales + 1))
        else falla "$n: los bits de Nova no coinciden con los de cerbero_asm"
             distintos=$((distintos + 1)); fi
    done
    [ "$distintos" -eq 0 ] && ok "los $iguales ejecutables coinciden bit a bit con cerbero_asm"
    [ "$pendientes" -gt 0 ] && nota "$pendientes programas importan otro modulo: los resuelve el enlazador"
    return 0
}

case "$objetivo" in
    build)     d_build ;;
    cerbero)   d_cerbero ;;
    fase1)     d_fase1 ;;
    fase2)     d_fase2 ;;
    fase3)     d_fase3 ;;
    fase4)     d_fase4 ;;
    cobertura) d_cobertura ;;
    memoria)   d_memoria ;;
    robustez)  d_robustez ;;
    opciones)  d_opciones ;;
    todo)
        d_build; d_fase1; d_fase2; d_fase3; d_fase4
        d_cobertura; d_opciones; d_robustez; d_memoria; d_cerbero ;;
    *)
        echo "objetivo desconocido: $objetivo"
        echo "use: build fase1 fase2 fase3 fase4 cerbero cobertura memoria robustez opciones todo"
        exit 2 ;;
esac

printf '\n==================================================\n'
if [ "$FALLOS" -eq 0 ]; then
    echo "todo en orden"
    exit 0
else
    echo "$FALLOS verificaciones fallidas"
    exit 1
fi
