#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
NOVAC=${1:-"$ROOT/novac"}
CPU=${2:-"$ROOT/ARQUITECTURA/src/cpu"}
SOURCE=${3:-"$ROOT/test/ejecucion/suma_10_15.nv"}
EXPECTED=${4:-25}
MAX_CYCLES=${5:-200000}

cd "$ROOT"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nova-niveles.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

printf '%-5s %10s %14s %8s\n' '-O' 'ciclos' 'instrucciones' 'IPC'
for nivel in 0 1 2; do
    "$NOVAC" "-O$nivel" "$SOURCE" -o "$TMP/program.nvx"
    python3 ARQUITECTURA/tools/novac_image.py "$TMP/program.nvx" \
        --imem "$TMP/imem.hex" --dmem "$TMP/dmem.hex"
    iverilog -g2012 -Wall -Wno-timescale -I "$CPU" \
        "-DCERBERO_MAX_CYCLES=$MAX_CYCLES" \
        "-DCERBERO_IMEM_FILE=\"$TMP/imem.hex\"" \
        "-DCERBERO_DMEM_FILE=\"$TMP/dmem.hex\"" \
        -s tb_nova_rtl -o "$TMP/sim.vvp" \
        "$CPU"/*.sv test/tb_nova_rtl.sv
    resultado=$(vvp -n "$TMP/sim.vvp" "+EXPECTED=$EXPECTED")
    ciclos=$(printf '%s\n' "$resultado" |
        awk '/ciclos RTL:/ { print $3; exit }')
    instrucciones=$(printf '%s\n' "$resultado" |
        awk '/instrucciones RTL:/ { print $3; exit }')
    if [ -z "$ciclos" ] || [ -z "$instrucciones" ] || [ "$ciclos" -eq 0 ]; then
        printf 'Fallo: no se obtuvieron contadores RTL para -O%s\n' "$nivel" >&2
        exit 1
    fi
    ipc=$(awk -v i="$instrucciones" -v c="$ciclos" \
        'BEGIN { printf "%.3f", i / c }')
    printf '%-5s %10s %14s %8s\n' "-O$nivel" "$ciclos" "$instrucciones" "$ipc"
done
