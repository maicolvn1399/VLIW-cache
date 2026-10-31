#!/bin/sh
# Genera los artefactos que pide la seccion 10 de la guia del proyecto:
#   10.4 Archivos generados: ensamblador y codigo binario de los tres ejercicios.
#   10.5 Evidencia de ejecucion: salida mostrando la compilacion exitosa y la
#        generacion correcta de los binarios.
#
# Todo queda en entregables/. Se regenera desde cero en cada corrida, para que
# nunca quede desfasado respecto del compilador, que fue justo lo que paso con
# la carpeta ensambladores/.
#
#   sh tools/entregables.sh [./novac]
set -e

NOVAC=${1:-./novac}
DEST=entregables
LOG="$DEST/evidencia_de_ejecucion.txt"

# Los tres ejercicios de la seccion 7 de la guia.
E1=test/factorial.nv            # 7.1 factorial: locales, si, ciclo, aritmetica
E2=test/ejemplos/busqueda_matriz.nv  # 7.2 busqueda en arreglo de dos dimensiones
E3=test/ejemplos/mergesort.nv   # 7.3 programa propuesto

[ -x "$NOVAC" ] || { echo "no se encontro $NOVAC; corra 'make' primero" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"

{
    echo "==========================================================="
    echo " Evidencia de ejecucion -- compilador Nova para CERBERO"
    echo " Generado por tools/entregables.sh el $(date '+%Y-%m-%d %H:%M')"
    echo "==========================================================="
    echo
    "$NOVAC" --version
    echo
} > "$LOG"

n=0
for f in "$E1" "$E2" "$E3"; do
    n=$((n + 1))
    nombre=$(basename "$f" .nv)
    {
        echo "-----------------------------------------------------------"
        echo " Ejercicio $n: $nombre   ($f)"
        echo "-----------------------------------------------------------"
        echo
        echo "\$ novac -s $f -o $DEST/$nombre.nvx"
    } >> "$LOG"

    # -s deja el ensamblador junto al ejecutable y lo repite por stdout.
    "$NOVAC" -s "$f" -o "$DEST/$nombre.nvx" > /dev/null 2>> "$LOG"
    echo "   ensamblador: $DEST/$nombre.asm" >> "$LOG"
    echo "   ejecutable:  $DEST/$nombre.nvx ($(wc -c < "$DEST/$nombre.nvx") bytes)" >> "$LOG"

    # El listado de bundles: slots, direccion, bytes, linea y columna.
    "$NOVAC" -p "$f" -o "$DEST/$nombre.paquetes.txt" >> "$LOG" 2>&1

    # Las imagenes que carga el procesador, en hexadecimal legible (6.1 y 8.4).
    if [ -f ARQUITECTURA/tools/novac_image.py ]; then
        echo "\$ novac_image.py $DEST/$nombre.nvx" >> "$LOG"
        python3 ARQUITECTURA/tools/novac_image.py "$DEST/$nombre.nvx" \
            --imem "$DEST/$nombre.imem.hex" --dmem "$DEST/$nombre.dmem.hex" >> "$LOG" 2>&1
    fi

    # Las primeras lineas del binario en hexadecimal, para el documento.
    {
        echo
        echo "   encabezado y primeros bundles de $nombre.nvx:"
        od -A d -t x1 -N 112 "$DEST/$nombre.nvx" | sed 's/^/     /'
        echo
    } >> "$LOG"
done

# Ejecucion real sobre el RTL de CERBERO, que es la evidencia mas fuerte.
if command -v iverilog > /dev/null 2>&1; then
    {
        echo "-----------------------------------------------------------"
        echo " Ejecucion de los tres ejercicios sobre el RTL de CERBERO"
        echo "-----------------------------------------------------------"
    } >> "$LOG"
    sh test/run_rtl_test.sh "$NOVAC" "$E1" 120 "ARQUITECTURA/src/cpu" >> "$LOG" 2>&1 || true
    sh test/run_rtl_test.sh "$NOVAC" "$E2"  12 "ARQUITECTURA/src/cpu" >> "$LOG" 2>&1 || true
    sh test/run_rtl_test.sh "$NOVAC" "$E3" 192 "ARQUITECTURA/src/cpu" >> "$LOG" 2>&1 || true
else
    echo "iverilog no esta instalado: se omite la ejecucion sobre el RTL" >> "$LOG"
fi

echo "" >> "$LOG"
echo "fin de la evidencia" >> "$LOG"

echo "Entregables en $DEST/:"
ls -1 "$DEST" | sed 's/^/  /'
