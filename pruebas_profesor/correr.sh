#!/bin/sh
# =============================================================================
# Las seis pruebas del profesor, traducidas a NOVA y ejecutadas sobre el RTL
# de CERBERO con -O0, -O1 y -O2. Cada resultado se compara contra el que da el
# programa original en Python; al final se tabulan ciclos e IPC.
#
# No toca ningun archivo del proyecto: se apoya en test/run_rtl_test.sh, que
# ya venia, y escribe solo en su propio directorio temporal.
#
#   sh pruebas_profesor/correr.sh            # usa ./novac
#   sh pruebas_profesor/correr.sh ./novac
#   CERBERO_CPU=/otra/ruta/src/cpu sh pruebas_profesor/correr.sh
# =============================================================================

NOVAC=${1:-./novac}
CPU=${CERBERO_CPU:-ARQUITECTURA/src/cpu}
D=pruebas_profesor

if [ ! -x "$NOVAC" ]; then
    echo "No se encontro el compilador en '$NOVAC'. Corra 'make' primero." >&2
    exit 1
fi
if [ ! -d "$CPU" ]; then
    echo "No se encontro el RTL de CERBERO en '$CPU'." >&2
    exit 1
fi
if ! command -v iverilog > /dev/null 2>&1; then
    echo "Falta iverilog:  sudo apt install -y iverilog" >&2
    exit 1
fi

T=${TMPDIR:-/tmp}/nova_pruebas_prof_$$
mkdir -p "$T"
trap 'rm -rf "$T"' 0 2 15

ok=0
fallos=0

# corre <nombre> <retorno esperado> <lo que dice Python> <salida scribe>
corre() {
    nombre=$1
    esperado=$2
    python=$3
    scribe=$4

    printf '\n############################################################\n'
    printf '## %s\n' "$nombre"
    printf '##   Python original: %s\n' "$python"
    printf '############################################################\n'

    for nivel in 0 1 2; do
        if OPT="-O$nivel" sh test/run_rtl_test.sh "$NOVAC" \
            "$D/$nombre.nv" "$esperado" "$CPU" "" "" 50000 "$scribe" \
            > "$T/salida.txt" 2>&1; then
            ciclos=$(awk '/ciclos RTL:/ { print $3; exit }' "$T/salida.txt")
            ipc=$(awk '/IPC RTL:/ { print $3; exit }' "$T/salida.txt")
            if grep -q 'RESULTADO: OK' "$T/salida.txt" &&
                [ -n "$ciclos" ] && [ -n "$ipc" ]; then
                estado=OK
                ok=$((ok + 1))
            else
                estado=FALLO
                fallos=$((fallos + 1))
            fi
        else
            ciclos=-
            ipc=-
            estado=FALLO
            fallos=$((fallos + 1))
        fi

        printf '  %-12s %-4s %10s %8s %s\n' \
            "$nombre" "-O$nivel" "$ciclos" "$ipc" "$estado"
        if [ "$estado" != OK ]; then
            echo "   --- la corrida completa:"
            sed 's/^/   /' "$T/salida.txt"
        fi
    done
}

echo "============================================================"
echo " Las seis pruebas del profesor sobre el procesador CERBERO"
echo " Compilador: $NOVAC     RTL: $CPU"
echo "============================================================"
printf '  %-12s %-4s %10s %8s %s\n' "Prueba" "-O" "ciclos" "IPC" "resultado"

corre Test1       28  "28"                                               "28"
corre Test2_demo  65  "maximo_lista([3,4,5,24,5,65,46]) = 65"             "65"
corre Test3      110  "(100, 10)   -> se imprimen 100 y 10, se retorna su suma" "100,10"
corre Test4       21  "[[1,4],[2,5],[3,6]]   -> se imprimen los 6, se retorna 21" "1,4,2,5,3,6"
corre Test5      134  "[[19,22],[43,50]]     -> se imprimen los 4, se retorna 134" "19,22,43,50"
corre Test6       55  "55"                                               "55"

printf '\n============================================================\n'
printf ' %d de 18 corridas coinciden con R6 y scribe; %d fallan\n' "$ok" "$fallos"
printf '============================================================\n'

[ "$fallos" -eq 0 ]
