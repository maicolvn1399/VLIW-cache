#!/bin/sh
# =============================================================================
# Barrido del lado de ARQUITECTURA (CE 4301).
#
# Toma el .s que genero el compilador, muestra los bundles, comprueba que la
# codificacion coincide con la del ensamblador de CE 4301, ejecuta el programa
# en el procesador por los dos caminos y valida el resultado.
#
#   sh pruebas_profesor/barrido_arquitectura.sh             # usa Test6.nv, espera 55
#   sh pruebas_profesor/barrido_arquitectura.sh Test3 110
#   sh pruebas_profesor/barrido_arquitectura.sh mi_prog.nv 42
# =============================================================================

D=pruebas_profesor
O=$D/.salida_arq
T=${1:-Test6}
case "$T" in
    *.nv) FUENTE=$T ;;
    *)    FUENTE=$D/$T.nv ;;
esac
N=$(basename "$FUENTE" .nv)

# El valor que el programa debe dejar en R6
case "${2:-}" in
    "") case "$N" in
            Test1) ESPERADO=28  ;; Test2_demo) ESPERADO=65  ;;
            Test3) ESPERADO=110 ;; Test4)      ESPERADO=21  ;;
            Test5) ESPERADO=134 ;; Test6)      ESPERADO=55  ;;
            *)     ESPERADO=""  ;;
        esac ;;
    *)  ESPERADO=$2 ;;
esac

ASM=ARQUITECTURA/tools/cerbero_asm.py
IMG=ARQUITECTURA/tools/novac_image.py
BUILD=ARQUITECTURA/src/build
RAIZ=$(pwd)

titulo() {
    printf '\n'
    printf '==============================================================\n'
    printf ' %s\n' "$1"
    printf '==============================================================\n'
}

[ -f "$FUENTE" ] || { echo "no se encontro $FUENTE" >&2; exit 1; }
[ -x ./novac ] || { echo "falta ./novac; corra 'make' primero" >&2; exit 1; }

mkdir -p "$O"

titulo "1. El compilador produce el ensamblador y el binario"
echo "\$ ./novac $FUENTE -s -o $O/$N.nvx"
./novac "$FUENTE" -s -o "$O/$N.nvx" > /dev/null
echo "  $O/$N.asm   el ensamblador, en texto"
echo "  $O/$N.nvx   el ejecutable, en binario"
echo
echo "  Los dos salen de la misma lista de bundles, en una sola pasada, asi"
echo "  que no pueden divergir."

titulo "2. Los bundles: cinco slots de 128 bits"
sed -n '/^\.text/,$p' "$O/$N.asm" | grep -E ";" | grep -v "^//" | head -12
echo "  ..."
echo
echo "  S0:ALU-0 | S1:ALU-1 | S2:LSU | S3:CRP | S4:BRU ;   // direccion"
echo "  Los '-' son slots vacios. El compilador emite una instruccion por"
echo "  bundle, asi que S1 y S3 quedan sin usar en el codigo general."
echo
echo "Cuanto del bundle se usa de verdad:"
# La misma cuenta que tools/ocupacion.py: se corta el comentario y despues
# se miran las cinco ranuras.
python3 - "$O/$N.asm" <<'PY'
import sys
nb = ni = 0
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    t = l.split("//")[0].strip()
    if not t.endswith(";"):
        continue
    r = [x.strip() for x in t[:-1].split("|")]
    if len(r) != 5:
        continue
    nb += 1
    ni += sum(1 for x in r if x not in ("", "-", "nop"))
if nb:
    print("  %d bundles, %d instrucciones  ->  %.2f de 5 ranuras" % (nb, ni, ni / nb))
PY

titulo "3. La codificacion binaria, bit a bit"
echo "\$ ./novac -p $FUENTE"
./novac -p "$FUENTE" | sed -n '1,2p;8,13p'
echo "  ..."
echo
echo "  Los 16 bytes de cada bundle. El slot S4 son los 16 bits bajos, que el"
echo "  listado imprime primero y en little endian."

titulo "4. Contraste con el ensamblador de CE 4301"
echo "NOVA arma la imagen desde su propio binario:"
python3 "$IMG" "$O/$N.nvx" --imem "$O/$N.nova.hex" --dmem "$O/$N.nova_d.hex" | sed 's/^/  /'
echo
echo "Y cerbero_asm.py la arma desde el texto:"
# El '$' con que NOVA decora los simbolos de modulo no esta en la gramatica de
# etiquetas de ellos. Es un renombre uniforme: no toca ningun opcode.
sed 's/\$/_/g' "$O/$N.asm" > "$O/$N.s"
python3 "$ASM" "$O/$N.s" -o "$O/$N.cerbero.hex" --datos "$O/$N.cerbero_d.hex" \
        --bundles 2048 --palabras 16384 | sed 's/^/  /'
echo
if diff -i "$O/$N.nova.hex" "$O/$N.cerbero.hex" > /dev/null; then
    echo "  IDENTICOS en los 2048 bundles"
    echo
    echo "  Dos implementaciones del ISA escritas por separado producen los"
    echo "  mismos bits. Si una sola direccion estuviera mal calculada, no"
    echo "  coincidirian."
else
    echo "  **DIFIEREN** -- esto es un defecto"
    diff -i "$O/$N.nova.hex" "$O/$N.cerbero.hex" | head -6 | sed 's/^/  /'
fi

titulo "5. El programa en el procesador, por los dos caminos"
echo "-- Camino A: ensamblando el texto con la herramienta de CE 4301"
( cd "$BUILD" && make -s correr PROG="$RAIZ/$O/$N.s" 2>&1 ) \
    | grep -E "llego a HALT en|r6  =|EXC|CAUSE" | sed 's/^/  /'
echo
echo "-- Camino B: el binario de NOVA, cargado tal cual (HEX=)"
echo "   MEMORIA= va siempre: HEX= deja la memoria de datos vacia, y un"
echo "   programa con cadenas daria un resultado equivocado sin fallar."
( cd "$BUILD" && make -s correr HEX="$RAIZ/$O/$N.nova.hex" \
                                MEMORIA="$RAIZ/$O/$N.nova_d.hex" 2>&1 ) \
    | grep -E "llego a HALT en|r6  =|EXC|CAUSE" | sed 's/^/  /'

titulo "6. El pipeline, ciclo por ciclo"
( cd "$BUILD" && make -s correr PROG="$RAIZ/$O/$N.s" TRAZA=1-12 2>&1 ) \
    | grep -A 24 "traza de los ciclos" | head -26
echo
echo "  Cada bundle pasando por IF, ID, EX, ME y WB. El bundle que sigue a un"
echo "  salto va marcado como delay slot: se ejecuta siempre, salte o no."

titulo "7. Cada escritura a registro y a memoria"
( cd "$BUILD" && make -s correr PROG="$RAIZ/$O/$N.s" \
                                ESCRITURAS="$RAIZ/$O/$N.escrituras.txt" > /dev/null 2>&1 )
if [ -f "$O/$N.escrituras.txt" ]; then
    sed -n '7,20p' "$O/$N.escrituras.txt"
    echo "  ..."
    echo "  ($(grep -c . "$O/$N.escrituras.txt") lineas en $O/$N.escrituras.txt)"
    echo
    echo "  Se ve la pila trabajando: R14 arranca en 0xFFFC y cada prologo la"
    echo "  baja. Una variable local no vive en un registro: vive en la memoria,"
    echo "  en la direccion R14 + su desplazamiento."
fi

titulo "8. Validacion del resultado"
if [ -n "$ESPERADO" ]; then
    echo "\$ sh test/run_rtl_test.sh ./novac $FUENTE $ESPERADO ARQUITECTURA/src/cpu"
    sh test/run_rtl_test.sh ./novac "$FUENTE" "$ESPERADO" ARQUITECTURA/src/cpu 2>&1 \
        | grep -E "ciclos|retorno R6|scribe|^    \[|RESULTADO" | sed 's/^/  /'
    echo
    echo "  Este si verifica: compara R6 contra el valor esperado y falla si no"
    echo "  coincide. 'make correr' solo muestra, no compara."
else
    echo "  Sin valor esperado. Para validar:"
    echo "  sh test/run_rtl_test.sh ./novac $FUENTE <esperado> ARQUITECTURA/src/cpu"
fi

printf '\n==============================================================\n'
printf ' Fin del barrido de Arquitectura\n'
printf '==============================================================\n'
