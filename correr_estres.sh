#!/usr/bin/env bash
# correr_estres.sh -- corre programas Nova sobre el RTL de CERBERO con
# -O0, -O1 y -O2, con L2 y sin L2 (CERBERO_SIN_L2), y muestra las metricas
# principales de cada corrida.
#
# Uso (desde la raiz del repo, en WSL/Linux):
#   ./correr_estres.sh estres_escritura estres_buffers
#   ./correr_estres.sh estres_conflicto
#   NIVELES="O2" ./correr_estres.sh estres_buffers      # solo un nivel
#   ./correr_estres.sh                                  # todos los estres_*.nv
#
# Informe completo de cada corrida: .salida/informes/<programa>-<nivel>-<con|sin>.txt

RAIZ="$(cd "$(dirname "$0")" && pwd)"
cd "$RAIZ" || exit 1

# Sin argumentos corre todos los estres_*.nv de la raiz
if [ $# -eq 0 ]; then
  set -- $(ls estres_*.nv 2>/dev/null)
  [ $# -ge 1 ] || { echo "error: no hay estres_*.nv en la raiz"; exit 2; }
  echo "Programas: $*"
fi
NIVELES="${NIVELES:-O0 O1 O2}"
# Limite de ciclos del simulador. estres_cache sin L2 en -O0 pasa de los
# 2 000 000 que trae make correr por defecto.
CICLOS="${CICLOS:-8000000}"
mkdir -p .salida/informes

# Dos corridas a la vez comparten ARQUITECTURA/src/build y se pisarian el
# simulador compilado (una haria make clean en medio de la otra)
exec 9> .salida/.correr_estres.lock
flock -n 9 || { echo "error: ya hay otra corrida en curso; espera a que termine"; exit 1; }

[ -x ./novac ] || make -s || { echo "error: no se pudo compilar novac"; exit 1; }

for PROG in "$@"; do
  PROG="${PROG%.nv}"
  [ -f "$PROG.nv" ] || { echo "error: no existe $PROG.nv"; continue; }
  for O in $NIVELES; do
    ./novac -$O $PROG.nv -o .salida/$PROG-$O.nvx || continue
    python3 ARQUITECTURA/tools/novac_image.py .salida/$PROG-$O.nvx \
        --imem .salida/$PROG-$O.imem.hex --dmem .salida/$PROG-$O.dmem.hex || continue
    for L2 in con sin; do
      X=""; [ $L2 = sin ] && X="-DCERBERO_SIN_L2"
      echo "=== $PROG -$O, $L2 L2 ==="
      # make clean es obligatorio: el .vvp guarda la configuracion adentro
      ( cd ARQUITECTURA/src/build && make -s clean && \
        make -s correr HEX=../../../.salida/$PROG-$O.imem.hex \
                       MEMORIA=../../../.salida/$PROG-$O.dmem.hex \
                       XFLAGS_EXTRA="$X" ESCRITURAS= CICLOS=$CICLOS ) \
        > .salida/informes/$PROG-$O-$L2.txt 2>&1
      grep -q "llego a HALT" .salida/informes/$PROG-$O-$L2.txt || \
        echo "    NO TERMINO: ver .salida/informes/$PROG-$O-$L2.txt (sube CICLOS=)"
      grep -E "ciclos de ejecucion|IPC|perdidos por stalls|write buffer lleno|conflicto RAW|eviction buffer lleno|tasa de aciertos|invalidaciones|utilizacion del bus|AMAT|teorico  |medido  |r6  =" \
        .salida/informes/$PROG-$O-$L2.txt
    done
  done
done
( cd ARQUITECTURA/src/build && make -s clean )
