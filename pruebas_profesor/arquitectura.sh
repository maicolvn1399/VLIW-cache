#!/bin/sh
# =============================================================================
# El lado de la arquitectura, con las pruebas del profesor.
#
# Para cada una recorre la cadena completa:
#   1. NOVA compila         -> .asm (texto) y .nvx (binario)
#   2. novac_image.py       -> imagen IMEM desde el .nvx
#   3. cerbero_asm.py       -> imagen IMEM desde el .asm, con el ensamblador
#                              independiente de CE 4301
#   4. diff                 -> las dos imagenes tienen que ser identicas
#   5. make correr          -> el programa sobre el testbench de CERBERO
#
# No escribe nada dentro de ARQUITECTURA/: los artefactos quedan en
# pruebas_profesor/.salida_arq/ y a 'make correr' se le pasa la ruta.
#
#   sh pruebas_profesor/arquitectura.sh
# =============================================================================

NOVAC=${1:-./novac}
D=pruebas_profesor
OUT=$D/.salida_arq
ASM=ARQUITECTURA/tools/cerbero_asm.py
IMG=ARQUITECTURA/tools/novac_image.py
BUILD=ARQUITECTURA/src/build

[ -x "$NOVAC" ] || { echo "no se encontro $NOVAC; corra 'make' primero" >&2; exit 1; }

mkdir -p "$OUT"
RAIZ=$(pwd)
ok=0
dif=0

for t in Test1 Test2_demo Test3 Test4 Test5 Test6; do
    printf '\n############################################################\n'
    printf '## %s\n' "$t"
    printf '############################################################\n'

    # 1. NOVA: ensamblador y binario de una sola pasada
    "$NOVAC" "$D/$t.nv" -s -o "$OUT/$t.nvx" > /dev/null || { dif=$((dif+1)); continue; }

    # 2. La imagen que arma NOVA desde su propio binario
    python3 "$IMG" "$OUT/$t.nvx" --imem "$OUT/$t.nova.hex" \
            --dmem "$OUT/$t.nova_d.hex" | sed 's/^/   /'

    # 3. La imagen que arma el ensamblador de CE 4301 desde el texto.
    #    El $ con que NOVA decora los simbolos de modulo no esta en la
    #    gramatica de etiquetas de ellos, asi que se cambia por _. Es un
    #    renombre uniforme: no toca ni un opcode ni una direccion.
    sed 's/\$/_/g' "$OUT/$t.asm" > "$OUT/$t.s"
    python3 "$ASM" "$OUT/$t.s" -o "$OUT/$t.cerbero.hex" \
            --datos "$OUT/$t.cerbero_d.hex" --bundles 2048 --palabras 16384 \
            | sed 's/^/   /'

    # 4. Las dos codificaciones, bundle por bundle
    if diff -i "$OUT/$t.nova.hex" "$OUT/$t.cerbero.hex" > /dev/null; then
        echo "   IDENTICOS en los 2048 bundles"
        ok=$((ok + 1))
    else
        echo "   **DIFIEREN**"
        diff -i "$OUT/$t.nova.hex" "$OUT/$t.cerbero.hex" | head -6 | sed 's/^/   /'
        dif=$((dif + 1))
    fi

    # 5. Y sobre el testbench de CERBERO, por el camino del ensamblador
    echo "   -- por el ensamblador de CERBERO (PROG=):"
    ( cd "$BUILD" && make -s correr PROG="$RAIZ/$OUT/$t.s" 2>&1 ) \
        | grep -E 'llego a HALT en|r6  =' | sed 's/^/      /'

    # 6. Y el mismo programa por el camino directo.
    #
    #    HEX= carga un binario ya ensamblado, sin pasar por cerbero_asm.py.
    #    Para NOVA es el camino natural, porque el compilador ya emite binario,
    #    y ademas evita el rodeo del paso 3: no hay que renombrar el '$' de los
    #    simbolos de modulo, porque las etiquetas ya estan resueltas a numeros.
    #
    #    MEMORIA= no es opcional. HEX= deja la memoria de datos vacia, asi que
    #    un programa con literales de cadena correria sin fallar y daria un
    #    resultado equivocado: 'scribe' leeria ceros donde esta la longitud de
    #    la cadena y la saltaria. Las dos imagenes van siempre juntas.
    echo "   -- directo, el binario de NOVA (HEX= + MEMORIA=):"
    ( cd "$BUILD" && make -s correr HEX="$RAIZ/$OUT/$t.nova.hex" \
                                    MEMORIA="$RAIZ/$OUT/$t.nova_d.hex" 2>&1 ) \
        | grep -E 'llego a HALT en|r6  =' | sed 's/^/      /'
done

printf '\n############################################################\n'
printf ' %d de 6 identicos bit a bit con cerbero_asm.py; %d distintos\n' "$ok" "$dif"
printf '############################################################\n'
[ "$dif" -eq 0 ]
