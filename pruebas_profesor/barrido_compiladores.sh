#!/bin/sh
# =============================================================================
# Barrido del lado de COMPILADORES (CE 1108).
#
# Recorre las seis fases del compilador sobre un programa, y despues ejecuta
# las seis pruebas del profesor sobre el procesador.
#
#   sh pruebas_profesor/barrido_compiladores.sh            # usa Test6.nv
#   sh pruebas_profesor/barrido_compiladores.sh Test1      # otra de las seis
#   sh pruebas_profesor/barrido_compiladores.sh mi_prog.nv # cualquier .nv
# =============================================================================

D=pruebas_profesor
T=${1:-Test6}
case "$T" in
    *.nv) FUENTE=$T ;;          # una ruta completa
    *)    FUENTE=$D/$T.nv ;;    # el nombre de una de las seis
esac
NOMBRE=$(basename "$FUENTE" .nv)

TMP=${TMPDIR:-/tmp}/nova_barrido_$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' 0 2 15

titulo() {
    printf '\n'
    printf '==============================================================\n'
    printf ' %s\n' "$1"
    printf '==============================================================\n'
}

[ -f "$FUENTE" ] || { echo "no se encontro $FUENTE" >&2; exit 1; }

titulo "0. El compilador se construye sin advertencias"
make clean > /dev/null 2>&1
make 2>&1 | grep -E "warning|error" && echo "  ^^ HAY ADVERTENCIAS" || \
    echo "  0 advertencias con -Wall -Wextra"
./novac --version

titulo "El programa: $FUENTE"
cat "$FUENTE"

titulo "FASE 1 - Analisis lexico:  novac --tokens"
./novac --tokens "$FUENTE" | head -14
echo "  ..."
./novac --tokens "$FUENTE" | grep -E "<EOF>|-- [0-9]+ tokens --"
echo
echo "  Cada token con su lexema, su clase, y su LINEA y COLUMNA."

titulo "FASE 2 - Analisis sintactico:  novac -t"
./novac -t "$FUENTE"
echo
echo "  Conectores y color por clase de nodo. Cada nodo trae linea y columna."
echo "  'make arbol F=$FUENTE' genera ademas un SVG en .salida/"

titulo "FASE 3 - Tabla de simbolos:  novac -m"
./novac -m "$FUENTE" | grep -vE "^(longitudo|scribe|dic|ingredere|exi|custodi|feistel|desfeistel) "
echo
echo "  La columna DIRECCION es lo que pide la seccion 2.3 del enunciado:"
echo "    IMEM @0xNNNN              direccion de codigo de una funcion"
echo "    DMEM @0xNNNN  = r14+M     direccion de memoria de una variable"
echo
echo "  La direccion de una local sale de la pila: arranca en 0xFFFC y cada"
echo "  funcion baja su marco. Se puede comprobar con la columna ORIGEN, que"
echo "  da el tamano del marco que resta el prologo. En una llamada anidada"
echo "  la misma variable queda un marco mas abajo."
echo
echo "  La columna NIV es el nivel de ambito: una variable dentro de un bloque"
echo "  anidado sale en un nivel mayor."

titulo "FASE 4 - Codigo intermedio:  novac --ir"
./novac --ir "$FUENTE"
echo
echo "  Tres direcciones. 't1 = n <= t0' y despues 'ifFalse t1 goto L0':"
echo "  la comparacion produce un valor y el salto lo consulta."

titulo "FASE 5 - Calculo de saltos y resolucion de referencias"
./novac -s "$FUENTE" -o "$TMP/p.nvx" > /dev/null
echo "Los saltos del programa:"
awk -F'|' '/br\.|jal\.|jr\.|jalr\./ {
         salto = $5; sub(/;.*/, "", salto); gsub(/^ +| +$/, "", salto)
         dir = $0; sub(/.*\/\/ */, "", dir)
         printf "  %-24s  en %s\n", salto, dir }' "$TMP/p.asm" > "$TMP/saltos.txt"
head -12 "$TMP/saltos.txt"
n=$(grep -c . "$TMP/saltos.txt")
[ "$n" -gt 12 ] && echo "  ... y $((n - 12)) mas, $n saltos en total"
echo
echo "Y donde quedo cada etiqueta, ya resuelta a su direccion:"
grep "IMEM bundle" "$TMP/p.asm" > "$TMP/etqs.txt"
head -14 "$TMP/etqs.txt"
n=$(grep -c . "$TMP/etqs.txt")
[ "$n" -gt 14 ] && echo "  ... y $((n - 14)) mas, $n etiquetas en total"
echo
echo "  El desplazamiento del tipo C es 'destino - origen - 1'."
echo "  El -1 es el delay slot: ese bundle se ejecuta igual, salte o no."

titulo "FASE 6 - Generacion de codigo binario:  novac -p"
./novac -p "$FUENTE" | head -16
echo "  ..."
echo
echo "  Direccion, LINEA y COLUMNA del fuente, los cinco slots y los 16 bytes."
echo "  Las filas con '-' son prologo, epilogo y rutinas de soporte: no vienen"
echo "  de ninguna linea del fuente."
echo
echo "El ejecutable:"
./novac "$FUENTE" -o "$TMP/$NOMBRE.nvx" > /dev/null
ls -l "$TMP/$NOMBRE.nvx" | awk '{printf "  %s   %s bytes\n", $NF, $5}'
echo "  Encabezado de 48 bytes con la magia NOVA, el punto de entrada, el tope"
echo "  de pila y una suma de verificacion; despues los bundles de 16 bytes."

titulo "Un error que tiene que salir: un modulo no es un programa"
echo "\$ ./novac $D/Test2.nv"
./novac "$D/Test2.nv" 2>&1 | head -3
echo
echo "  Test2.nv es una biblioteca sin 'principale', igual que el Test2.py"
echo "  original, cuyo print esta comentado. Test2_demo.nv la importa y la usa."

titulo "Las seis pruebas del profesor sobre el procesador"
sh "$D/correr.sh" ./novac 2>&1 | grep -E '^## |retorno R6|RESULTADO:|coinciden con el'

printf '\n==============================================================\n'
printf ' Fin del barrido de Compiladores\n'
printf '==============================================================\n'
