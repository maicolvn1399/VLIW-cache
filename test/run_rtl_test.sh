#!/bin/sh
set -eu

NOVAC=${1:-./novac}
SOURCE=${2:?source file required}
EXPECTED=${3:?expected return value required}
CPU=${4:-../src/cpu}
OBJECT_SOURCE=${5:-}
ROT_SECRET=${6:-}
MAX_CYCLES=${7:-20000}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nova-rtl.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

if [ -n "$OBJECT_SOURCE" ]; then
    cp "$OBJECT_SOURCE" "$TMP/calculos.nv"
    cp "$(dirname "$OBJECT_SOURCE")/basicas.nv" "$TMP/basicas.nv"
    "$NOVAC" -c "$TMP/calculos.nv" -o "$TMP/calculos.nvo"
    "$NOVAC" "$SOURCE" -I "$TMP" -o "$TMP/program.nvx"
else
    "$NOVAC" "$SOURCE" -o "$TMP/program.nvx"
fi
python3 ARQUITECTURA/tools/novac_image.py "$TMP/program.nvx" \
    --imem "$TMP/imem.hex" --dmem "$TMP/dmem.hex"
set -- -g2012 -Wall -Wno-timescale -I "$CPU"
if [ -n "$ROT_SECRET" ]; then
    set -- "$@" "-DCERBERO_ROT_SECRET=$ROT_SECRET"
fi
set -- "$@" "-DCERBERO_MAX_CYCLES=$MAX_CYCLES"
iverilog "$@" \
    -DCERBERO_IMEM_FILE="\"$TMP/imem.hex\"" \
    -DCERBERO_DMEM_FILE="\"$TMP/dmem.hex\"" \
    -s tb_nova_rtl -o "$TMP/sim.vvp" \
    "$CPU"/*.sv test/tb_nova_rtl.sv
vvp -n "$TMP/sim.vvp" "+EXPECTED=$EXPECTED"
