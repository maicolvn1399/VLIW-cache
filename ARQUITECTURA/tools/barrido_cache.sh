#!/usr/bin/env bash
# =============================================================================
# barrido_cache.sh - Compara configuraciones de cache L1-D.
# CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
#
# El enunciado pide medir el impacto de diferentes configuraciones de cache
# (seccion 9.1.1) y comparar entre ellas (seccion 9.1.2). Este script corre el
# mismo conjunto de benchmarks con varias geometrias de L1-D y deja un archivo
# por configuracion para que tabla_barrido.py arme la comparacion.
#
# La geometria se pasa por -D al compilador: las cuatro constantes de L1 en
# cerbero_defs.svh estan con guarda `ifndef` justo para esto. Hay que darlas
# las cuatro y coherentes entre si, porque el preprocesador de Verilog no sabe
# dividir; tb_l1_dcache.sv lo comprueba antes de ejecutar un ciclo.
#
# TODAS las configuraciones son de 2 vias, y eso no es por descuido: el modulo
# l1_dcache.sv implementa exactamente dos vias (compara dos etiquetas con
# nombre propio y guarda el LRU como un bit por conjunto, que es LRU exacto
# solo con dos vias). Pedirle otra asociatividad aborta la elaboracion con un
# mensaje claro. Entonces este barrido mide capacidad a asociatividad fija, que
# es la variable que el enunciado deja libre: la geometria de L1 que exige es
# 4 KB / 2 vias / lineas de 32 B. La comparacion de asociatividad necesita
# generalizar la busqueda a N vias, y eso llega en la Iteracion 4, donde la L2
# del enunciado es de 4 vias.
#
#   uso:  ./barrido_cache.sh [directorio_de_salida]
# =============================================================================

set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$AQUI/../src/build"
SALIDA="${1:-$AQUI/../barrido}"

mkdir -p "$SALIDA"

# Las que de verdad se ejecutan rapido y tienen accesos a memoria. Se deja
# fuera lazo_estres: con 900 000 ciclos por corrida y seis configuraciones, el
# barrido pasaria de minutos a horas, y su patron (100 % de aciertos en
# cualquier geometria) no distingue configuraciones.
# recorrido_cache va de primero porque es el unico que de verdad mide
# geometria: los otros ocho tocan dos o tres lineas cada uno, asi que todos sus
# fallos son de arranque y dan el mismo numero en cualquier configuracion. Eso
# se comprobo corriendo el barrido sin el: salio plano de 512 B a 16 KB.
PROGRAMAS="recorrido_cache fibonacci estadisticas contar_hasta_n div32_prueba \
           feistel sesion_sin_logout suma_simple_emp suma_vliw_emp"

# Capacidad a 2 vias y lineas de 32 B, de 512 B a 16 KB: un rango de 32x.
# conjuntos = bytes / (2 vias x 32 B),  idx = log2(conjuntos)
#
# nombre            bytes  vias  conjuntos  idx
CONFIGS="
512B_2vias           512   2      8         3
1KB_2vias           1024   2     16         4
2KB_2vias           2048   2     32         5
4KB_2vias           4096   2     64         6
8KB_2vias           8192   2    128         7
16KB_2vias         16384   2    256         8
"

echo "Barrido de configuraciones de cache L1-D"
echo "  programas: $(echo $PROGRAMAS | wc -w)"
echo ""

cd "$BUILD" || exit 1

echo "$CONFIGS" | while read -r NOMBRE BYTES VIAS CONJ IDX; do
    [ -z "${NOMBRE:-}" ] && continue

    GEOM="-DL1D_BYTES=$BYTES -DL1D_WAYS=$VIAS -DL1D_SETS=$CONJ -DL1D_SIDX_W=$IDX"
    DEST="$SALIDA/$NOMBRE"
    mkdir -p "$DEST"

    printf '  %-12s  %5d B  %d via(s)  %3d conjuntos ... ' \
           "$NOMBRE" "$BYTES" "$VIAS" "$CONJ"

    # Cada configuracion se compila de cero: el .vvp anterior tiene la geometria
    # vieja compilada adentro y make no sabe que las macros cambiaron.
    make -s clean >/dev/null 2>&1
    rm -f "$DEST"/*.txt

    FALLO=0
    for P in $PROGRAMAS; do
        if ! make -s correr PROG="$P.s" \
                 RESULTADO="$DEST/metricas_$P.txt" ESCRITURAS= \
                 XFLAGS_EXTRA="$GEOM" >/dev/null 2>&1; then
            FALLO=1
            echo "FALLO en $P"
            break
        fi
    done

    [ "$FALLO" = "0" ] && echo "ok"
done

make -s clean >/dev/null 2>&1

echo ""
echo "Resultados en $SALIDA"
echo "Para la tabla:  python3 $AQUI/tabla_barrido.py $SALIDA"
