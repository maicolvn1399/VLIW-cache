#!/bin/sh
# Suite funcional del compilador: analisis, diagnosticos y generacion.
#   Uso: sh test/run_tests.sh [./novac]
#
# 1. Todo test/*.nv y test/ejemplos/*.nv debe analizarse sin errores (rc 0) y
#    sin advertencias: son los programas de referencia. Los que son programas
#    completos (tienen principale y no importan nada) tienen que producir
#    tambien su ejecutable binario.
# 2. Cada test/errores/E###_*.nv debe fallar (rc 1) con el codigo del nombre.
# 3. Los test/errores/multi_*.nv reportan varios errores en una sola corrida: la
#    primera linea ("# espera: E201 E202 ...") lista los codigos, en orden.
# 4. Cada test/advertencias/W###_*.nv debe compilar (rc 0) y emitir su codigo.
# 5. --tokens (test/lexico), --sym, --max-errors y el resumen final.

NOVAC=${1:-./novac}
DIR=$(dirname "$0")

# Los ejecutables de prueba van a un directorio temporal que se borra solo,
# para no dejar nada en la raiz del proyecto.
TMP=${TMPDIR:-/tmp}/nova_pruebas_$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' 0 2 15
TMPEXE=$TMP/a.out
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FALLO: $1"; [ -n "$2" ] && echo "$2" | head -8 | sed 's/^/    /'; }

[ -x "$NOVAC" ] || { echo "no existe el ejecutable $NOVAC (corra 'make' primero)"; exit 2; }

# 1. archivos validos --------------------------------------------------------
for f in "$DIR"/*.nv "$DIR"/ejemplos/*.nv "$DIR"/ejecucion/*.nv; do
    [ -f "$f" ] || continue
    # Analisis y codigo intermedio.
    out=$("$NOVAC" --ir "$f" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then ok; else bad "$f deberia analizarse sin errores (rc=$rc)" "$out"; fi
    out=$("$NOVAC" --tokens "$f" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then ok; else bad "$f --tokens deberia terminar sin errores (rc=$rc)" "$out"; fi
    out=$("$NOVAC" -t "$f" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then ok; else bad "$f -t deberia terminar sin errores (rc=$rc)" "$out"; fi
    # Fase 3: ninguno de los programas de referencia debe producir advertencias.
    # W009 queda fuera a proposito: no habla del programa sino de cuanto cabe en
    # la IMEM de CERBERO, y hay programas de referencia que no caben. El reporte
    # de ocupacion esta en el bloque 15 de tools/verificar.sh.
    out=$("$NOVAC" -Wno-W009 --sym "$f" 2>&1); rc=$?
    n=$(echo "$out" | grep -c 'advertencia\[')
    if [ $rc -eq 0 ] && [ "$n" -eq 0 ]; then ok; else
        bad "$f --sym deberia compilar sin advertencias (rc=$rc, advertencias=$n)" "$out"; fi
    # La tabla de simbolos debe salir con el encabezado y el resumen de memoria.
    case "$out" in
        *"=== Tabla de simbolos ==="*"datos globales:"*) ok ;;
        *) bad "$f --sym no imprimio la tabla de simbolos completa" "$out" ;;
    esac

    # Todo programa principal, incluso con imports resolubles, produce binario.
    completo=1
    grep -q 'functio  *principale' "$f" || completo=0
    out=$("$NOVAC" "$f" -o "$TMPEXE" 2>&1); rc=$?
    if [ "$completo" -eq 1 ]; then
        if [ $rc -eq 0 ] && [ -s "$TMPEXE" ]; then ok
        else bad "$f deberia producir un ejecutable (rc=$rc)" "$out"; fi
    else
        if [ $rc -eq 1 ]; then ok
        else bad "$f no es un programa completo y aun asi dio rc=$rc" "$out"; fi
    fi
    rm -f "$TMPEXE"
done

# 2 y 3. archivos con errores ------------------------------------------------------
for f in "$DIR"/errores/*.nv; do
    [ -f "$f" ] || continue
    nombre=$(basename "$f" .nv)
    out=$("$NOVAC" "$f" 2>&1); rc=$?
    if [ $rc -ne 1 ]; then bad "$nombre: se esperaba rc=1 y fue rc=$rc" "$out"; continue; fi
    obtenidos=$(echo "$out" | grep -o 'error\[E[0-9]*\]' | sed 's/error\[\(.*\)\]/\1/' | tr '\n' ' ')
    primera=$(head -1 "$f")
    case "$primera" in
        "# espera:"*)
            esperados="$(echo "${primera#\# espera:}" | tr -s ' ' | sed 's/^ //; s/ *$//') "
            if [ "$obtenidos" = "$esperados" ]; then ok; else
                bad "$nombre: codigos esperados [$esperados] obtenidos [$obtenidos]" "$out"; fi ;;
        *)
            codigo=${nombre%%_*}
            case " $obtenidos" in
                *" $codigo "*) ok ;;
                *) bad "$nombre: se esperaba $codigo y se obtuvo [$obtenidos]" "$out" ;;
            esac ;;
    esac
done

# 4. advertencias -----------------------------------------------------------
# Compilan bien (rc 0) pero deben emitir el codigo W del nombre del archivo.
for f in "$DIR"/advertencias/*.nv; do
    [ -f "$f" ] || continue
    nombre=$(basename "$f" .nv)
    out=$("$NOVAC" "$f" -o "$TMPEXE" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then bad "$nombre: se esperaba rc=0 y fue rc=$rc" "$out"; continue; fi
    codigo=${nombre%%_*}
    obtenidos=$(echo "$out" | grep -o 'advertencia\[W[0-9]*\]' | sed 's/advertencia\[\(.*\)\]/\1/' | tr '\n' ' ')
    case " $obtenidos" in
        *" $codigo "*) ok ;;
        *) bad "$nombre: se esperaba $codigo y se obtuvo [$obtenidos]" "$out" ;;
    esac
done

# 5. opciones y resumen --------------------------------------------------------------
multi="$DIR/errores/multi_mezcla.nv"
out=$("$NOVAC" --max-errors 2 "$multi" 2>&1); rc=$?
n=$(echo "$out" | grep -c 'error\[')
if [ $rc -eq 1 ] && [ "$n" -eq 2 ]; then ok; else bad "--max-errors 2 deberia mostrar exactamente 2 errores (rc=$rc, errores=$n)" "$out"; fi

out=$("$NOVAC" --max-errors 0 "$multi" 2>&1); rc=$?
if [ $rc -eq 2 ]; then ok; else bad "--max-errors 0 deberia ser error de uso (rc=$rc)" "$out"; fi

out=$("$NOVAC" "$multi" 2>&1)
case "$out" in
    *"compilacion abortada: 6 errores (2 lexicos, 4 sintacticos)"*) ok ;;
    *) bad "el resumen final no tiene el desglose esperado" "$out" ;;
esac

out=$("$NOVAC" --tokens "$DIR/lexico/multi_lexicos.nv" 2>&1); rc=$?
n=$(echo "$out" | grep -c 'error\[')
if [ $rc -eq 1 ] && [ "$n" -eq 5 ]; then ok; else bad "--tokens deberia reportar los 5 errores lexicos (rc=$rc, errores=$n)" "$out"; fi

"$NOVAC" /no/existe.nv >/dev/null 2>&1; rc=$?
if [ $rc -eq 3 ]; then ok; else bad "archivo inexistente deberia dar rc=3 (rc=$rc)"; fi

"$NOVAC" >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ]; then ok; else bad "sin argumentos deberia dar rc=2 (rc=$rc)"; fi

# Objetos de fuente empaquetada: el enlazador vuelve a analizarlos y resuelve
# las referencias de modulo en el ejecutable final.
obj="$TMP/doble.nvo"
out=$("$NOVAC" -c test/errores/E405_falta_principale.nv -o "$obj" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -s "$obj" ]; then ok; else bad "-c deberia crear un objeto NOVA (rc=$rc)" "$out"; fi
magic=$(dd if="$obj" bs=1 count=4 2>/dev/null)
if [ "$magic" = "NVO1" ]; then ok; else bad "el objeto debe tener encabezado NVO1"; fi
printf 'importa "doble.nvo" ut lib;\nfunctio principale() -> integer { redde lib.doble(21); }\n' > "$TMP/main.nv"
out=$("$NOVAC" "$TMP/main.nv" -o "$TMPEXE" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -s "$TMPEXE" ]; then ok; else bad "el enlazador debe aceptar un modulo .nvo (rc=$rc)" "$out"; fi

# un hexadecimal con letras ya no da un E105 falso
printf 'constans A : integer = 0xDEADBEEF;\n' > "$DIR/.hex.tmp.nv"
out=$("$NOVAC" -t "$DIR/.hex.tmp.nv" 2>&1); rc=$?
rm -f "$DIR/.hex.tmp.nv"
case "$out" in
    *"Entero -559038737"*) [ $rc -eq 0 ] && ok || bad "0xDEADBEEF rc=$rc" "$out" ;;
    *) bad "0xDEADBEEF deberia valer -559038737 (integer de 32 bits con signo)" "$out" ;;
esac

# Opciones de entrega: -s conserva su volcado por stdout y genera el .asm junto
# al ejecutable; -p lista bundles/bytes; -x ensambla el .asm de forma separada.
out=$("$NOVAC" -s "$DIR/ejecucion/suma_10_15.nv" -o "$TMP/suma.nvx" \
    > "$TMP/suma.stdout" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -s "$TMP/suma.nvx" ] && [ -s "$TMP/suma.asm" ] &&
   grep -q '__inicio:' "$TMP/suma.stdout" &&
   grep -q 'Nova fuente: linea 2' "$TMP/suma.asm"; then
    ok
else
    bad "-s debe producir .nvx/.asm con posiciones de fuente y conservar stdout (rc=$rc)" "$out"
fi

out=$("$NOVAC" -p "$DIR/ejecucion/suma_10_15.nv" -o "$TMP/paquetes.txt" 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q 'Direccion  Linea' "$TMP/paquetes.txt" &&
   grep -Eq '^0x[0-9A-F]+ +[1-9][0-9]*' "$TMP/paquetes.txt" &&
   grep -q '0x0000' "$TMP/paquetes.txt"; then
    paquetes=$(awk '/^0x0000/{print $NF; exit}' "$TMP/paquetes.txt")
    binario=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).read_bytes()[48:64].hex().upper())' "$TMP/suma.nvx")
    if [ "$paquetes" = "$binario" ]; then
        ok
    else
        bad "-p debe reportar los mismos bytes que el primer bundle del .nvx" ""
    fi

    out=$(python3 tools/arbol_svg.py --novac "$NOVAC" \
        --source "$DIR/ejecucion/suma_10_15.nv" --output "$TMP/suma.svg" 2>&1); rc=$?
    if [ $rc -eq 0 ] && [ -s "$TMP/suma.svg" ] &&
       python3 -c '
import collections, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = {"s": "http://www.w3.org/2000/svg"}
nodes = root.findall(".//s:g[@class=\"node\"]", ns)
edges = root.findall(".//s:path", ns)
assert root.tag.endswith("svg") and nodes and len(edges) == len(nodes) - 1
levels = collections.defaultdict(list)
for node in nodes:
    x, y = map(float, node.attrib["transform"][10:-1].split(","))
    width = float(node.find("s:rect", ns).attrib["width"])
    levels[y].append((x - width / 2, x + width / 2))
for boxes in levels.values():
    boxes.sort()
    assert all(left[1] <= right[0] + 0.01 for left, right in zip(boxes, boxes[1:]))
' "$TMP/suma.svg"; then
        ok
    else
        bad "el renderizador debe crear un SVG valido, completo y sin nodos solapados (rc=$rc)" "$out"
    fi

    out=$("$NOVAC" --sym "$DIR/ejecucion/matriz_for.nv" 2>&1); rc=$?
    if [ $rc -eq 0 ] && echo "$out" | grep -Eq 'DMEM @0x[0-9A-F]{4} += r14[-+][0-9]+'; then
        ok
    else
        bad "la tabla debe dar la direccion absoluta de cada local y su offset (rc=$rc)" "$out"
    fi

    out=$("$NOVAC" --sym "$DIR/factorial.nv" 2>&1); rc=$?
    # principale reserva 16 y factorial 20, asi que sus marcos quedan en
    # 0xFFFC-16 = 0xFFEC y 0xFFEC-20 = 0xFFD8. Las tres locales de factorial
    # salen de ahi: +8, +4 y +0.
    if [ $rc -eq 0 ] &&
       echo "$out" | grep -Fq 'DMEM @0xFFE0  = r14+8' &&
       echo "$out" | grep -Fq 'DMEM @0xFFDC  = r14+4' &&
       echo "$out" | grep -Fq 'DMEM @0xFFD8  = r14+0' &&
       echo "$out" | grep -Eq 'factorial +functio +global +integer +0 +IMEM @0x[0-9A-F]{4}' &&
       echo "$out" | grep -Eq 'principale +functio +global +integer +0 +IMEM @0x[0-9A-F]{4}'; then
        ok
    else
        bad "la tabla del factorial debe dar direcciones absolutas e IMEM (rc=$rc)" "$out"
    fi

    out=$("$NOVAC" --sym "$DIR/ejemplos/multiplicacion.nv" 2>&1); rc=$?
    if [ $rc -eq 0 ] && echo "$out" | grep -Fq '= r14+76'; then
        ok
    else
        bad "la tabla debe incluir el espacio de argumentos salientes en el marco efectivo (rc=$rc)" "$out"
    fi
else
    bad "-p debe listar bundles con direccion y bytes (rc=$rc)" "$out"
fi

out=$("$NOVAC" -p "$DIR/errores/E405_falta_principale.nv" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q 'E405' &&
   ! echo "$out" | grep -q '^Direccion'; then
    ok
else
    bad "-p debe rechazar modulos sin principale sin imprimir paquetes parciales (rc=$rc)" "$out"
fi

out=$("$NOVAC" -x "$TMP/suma.asm" -o "$TMP/suma.hex" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -s "$TMP/suma.hex" ] &&
   [ -s "$TMP/suma.hex.dmem.hex" ] && [ -s "$TMP/suma.hex.lst" ]; then
    python3 ARQUITECTURA/tools/novac_image.py "$TMP/suma.nvx" --imem "$TMP/suma.imem" \
        --dmem "$TMP/suma.dmem" >/dev/null 2>&1
    n=$(wc -l < "$TMP/suma.hex")
    head -n "$n" "$TMP/suma.imem" | tr '[:lower:]' '[:upper:]' > "$TMP/suma.imem.prefix"
    if cmp -s "$TMP/suma.hex" "$TMP/suma.imem.prefix"; then
        ok
    else
        bad "-x debe codificar el mismo codigo que el ejecutable NOVA" ""
    fi
else
    bad "-x debe producir imagen IMEM, DMEM y listado (rc=$rc)" "$out"
fi

echo
echo "pruebas: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
