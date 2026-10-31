#!/bin/sh
# =============================================================================
# Las seis pruebas del profesor, traducidas a NOVA y ejecutadas sobre el RTL
# de CERBERO. Cada resultado se compara contra el que da el programa original
# en Python.
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

# corre <nombre> <retorno esperado> <lo que dice el original en Python>
corre() {
    nombre=$1
    esperado=$2
    python=$3

    printf '\n############################################################\n'
    printf '## %s\n' "$nombre"
    printf '##   Python original: %s\n' "$python"
    printf '############################################################\n'

    sh test/run_rtl_test.sh "$NOVAC" "$D/$nombre.nv" "$esperado" "$CPU" \
        > "$T/salida.txt" 2>&1

    grep -E 'imagenes CERBERO|ciclos:|retorno R6:|^    \[|RESULTADO:' "$T/salida.txt"

    if grep -q 'RESULTADO: OK' "$T/salida.txt"; then
        ok=$((ok + 1))
    else
        fallos=$((fallos + 1))
        echo "   --- la corrida completa:"
        sed 's/^/   /' "$T/salida.txt"
    fi
}

echo "============================================================"
echo " Las seis pruebas del profesor sobre el procesador CERBERO"
echo " Compilador: $NOVAC     RTL: $CPU"
echo "============================================================"

corre Test1       28  "28"
corre Test2_demo  65  "maximo_lista([3,4,5,24,5,65,46]) = 65"
corre Test3      110  "(100, 10)   -> se imprimen 100 y 10, se retorna su suma"
corre Test4       21  "[[1,4],[2,5],[3,6]]   -> se imprimen los 6, se retorna 21"
corre Test5      134  "[[19,22],[43,50]]     -> se imprimen los 4, se retorna 134"
corre Test6       55  "55"

printf '\n============================================================\n'
printf ' %d de 6 coinciden con el original en Python; %d fallan\n' "$ok" "$fallos"
printf '============================================================\n'

[ "$fallos" -eq 0 ]
