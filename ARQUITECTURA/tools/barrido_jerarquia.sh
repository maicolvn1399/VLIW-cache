#!/usr/bin/env bash
# =============================================================================
# barrido_jerarquia.sh - Compara configuraciones de la jerarquia L1-D + L2.
# CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
#
# La Iteracion 5 pide medir el efecto de la jerarquia completa (enunciado
# 7.1.5): cuanto aporta la L2, y como cambia el rendimiento con la capacidad
# de cada nivel. Este script corre los mismos programas sobre cada
# configuracion y deja un informe por programa, en el formato de make correr,
# para que tabla_analisis.py arme las tablas y los graficos.
#
# Las configuraciones son cuatro grupos, todos sobre el mismo RTL:
#
#   base       L1 de 4 KB y L2 de 16 KB, la del enunciado
#   sin_l2     CERBERO_SIN_L2: el arbitro va directo a memoria principal
#   l1_*       capacidad de L1 de 512 B a 16 KB (2 vias), con la L2 de 16 KB
#   l2_*       capacidad de L2 de 4 KB a 64 KB (4 vias), con la L1 de 4 KB
#
# Las capacidades base (L1 de 4 KB, L2 de 16 KB) no se repiten en sus grupos:
# son la configuracion base, y tabla_analisis.py la usa en las dos curvas.
#
# La geometria se pasa por -D, coherente entre si, porque el preprocesador no
# divide (cerbero_defs.svh). Una combinacion incoherente aborta la elaboracion:
# top.sv revisa L2_BYTES y l2_cache.sv las potencias de dos.
#
# Si una simulacion falla, o su informe trae una comprobacion en FALLA, el
# script se detiene y nombra la configuracion y el programa. Un barrido con un
# hueco silencioso produciria una tabla que parece completa y no lo es.
#
#   uso:  ./barrido_jerarquia.sh [directorio_de_salida]
#   por omision escribe en ARQUITECTURA/barrido/jerarquia/
# =============================================================================

set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$AQUI/../src/build"
SALIDA="${1:-$AQUI/../barrido/jerarquia}"

# Los de PROGS_METRICAS del makefile, menos lazo_estres: son 900 000 ciclos por
# corrida y su patron (100 % de aciertos en L1 con cualquier geometria) no
# distingue configuraciones; con once configuraciones el barrido pasaria de
# minutos a horas. Los cuatro patrones van primero porque son los que separan
# las configuraciones; el resto toca pocas lineas.
PROGRAMAS="patron_secuencial patron_stride patron_aleatorio patron_reuso \
           recorrido_cache fibonacci estadisticas contar_hasta_n div32_prueba \
           feistel sesion_sin_logout suma_10_15 suma_simple_emp suma_vliw_emp"

# L1: conjuntos = bytes / (2 vias x 32 B), idx = log2(conjuntos)
# L2: conjuntos = bytes / (4 vias x 32 B)
#
# nombre        L1 bytes conj idx   L2 bytes vias conj   sin L2
CONFIGS="
base              4096   64   6      16384    4   128    no
sin_l2            4096   64   6      16384    4   128    si
l1_512B            512    8   3      16384    4   128    no
l1_1KB            1024   16   4      16384    4   128    no
l1_2KB            2048   32   5      16384    4   128    no
l1_8KB            8192  128   7      16384    4   128    no
l1_16KB          16384  256   8      16384    4   128    no
l2_4KB            4096   64   6       4096    4    32    no
l2_8KB            4096   64   6       8192    4    64    no
l2_32KB           4096   64   6      32768    4   256    no
l2_64KB           4096   64   6      65536    4   512    no
"

N_PROGS=$(echo $PROGRAMAS | wc -w)
echo "Barrido de la jerarquia L1-D + L2"
echo "  programas: $N_PROGS"
echo "  salida:    $SALIDA"
echo ""

mkdir -p "$SALIDA"
cd "$BUILD" || exit 1

# Cada configuracion se compila de cero: el .vvp anterior tiene la geometria
# vieja adentro y make no sabe que las macros cambiaron.
limpiar() { make -s clean >/dev/null 2>&1; }

while read -r NOMBRE L1B L1S L1I L2B L2W L2S SINL2; do
    [ -z "${NOMBRE:-}" ] && continue

    GEOM="-DL1D_BYTES=$L1B -DL1D_WAYS=2 -DL1D_SETS=$L1S -DL1D_SIDX_W=$L1I"
    GEOM="$GEOM -DL2_BYTES=$L2B -DL2_WAYS=$L2W -DL2_SETS=$L2S"
    [ "$SINL2" = "si" ] && GEOM="$GEOM -DCERBERO_SIN_L2"

    DEST="$SALIDA/$NOMBRE"
    mkdir -p "$DEST"
    rm -f "$DEST"/*.txt

    printf '  %-10s  L1 %5d B   L2 %5d B%s ... ' "$NOMBRE" "$L1B" "$L2B" \
           "$([ "$SINL2" = "si" ] && echo ' (sin L2)')"

    limpiar
    INICIO=$(date +%s)
    for P in $PROGRAMAS; do
        ARCHIVO="$DEST/metricas_$P.txt"
        # El informe se escribe con un nombre relativo dentro de build y se
        # mueve despues: la receta de make no pone comillas a RESULTADO, y una
        # ruta con espacios (la del repo los tiene) llega partida al simulador.
        rm -f barrido_informe.txt
        if ! make -s correr PROG="$P.s" RESULTADO=barrido_informe.txt ESCRITURAS= \
                 XFLAGS_EXTRA="$GEOM" >"$DEST/.ultimo.log" 2>&1; then
            echo "FALLO"
            echo "error: la simulacion de $P fallo en la configuracion $NOMBRE" >&2
            tail -20 "$DEST/.ultimo.log" >&2
            exit 1
        fi
        [ -s barrido_informe.txt ] && mv barrido_informe.txt "$ARCHIVO"
        if [ ! -s "$ARCHIVO" ] || grep -q "FALLA" "$ARCHIVO"; then
            echo "FALLO"
            echo "error: el informe de $P en $NOMBRE falta o trae una comprobacion en FALLA:" >&2
            grep -n "FALLA" "$ARCHIVO" >&2
            exit 1
        fi
    done
    rm -f "$DEST/.ultimo.log"
    echo "ok ($(( $(date +%s) - INICIO )) s)"
done <<< "$CONFIGS"

limpiar

echo ""
echo "Resultados en $SALIDA"
echo "Tablas y graficos:  python3 $AQUI/tabla_analisis.py $SALIDA"
