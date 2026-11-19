#!/bin/sh
set -eu

NOVAC=${1:-./novac}
CPU=${2:-ARQUITECTURA/src/cpu}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Iteracion 5. Con METRICAS_DIR apuntando a un directorio, cada corrida deja
# ahi su volcado de contadores, uno por programa y nivel.
#
# Se recogen en esta bateria, y no en un guion aparte, a proposito: es la unica
# que corre el corpus completo en los tres niveles comprobando que el resultado
# no cambia. Medir en el mismo paso que se verifica garantiza que la tabla de
# rendimiento y la prueba de equivalencia hablan de los mismos binarios.
METRICAS_DIR=${METRICAS_DIR:-}
if [ -n "$METRICAS_DIR" ]; then
    mkdir -p "$METRICAS_DIR"
fi

if [ ! -x "$NOVAC" ]; then
    echo "no existe el compilador ejecutable: $NOVAC" >&2
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nova_equiv.XXXXXX")
trap 'rm -rf "$TMP"' 0 1 2 15
python3 - "$TMP/muchos_temporales.nv" "$TMP/muchos_temporales.esperado" <<'PY'
import sys

with open(sys.argv[1], "w", encoding="utf-8") as source:
    source.write("functio desplazar(valor : integer) -> integer {\n")
    source.write("    redde valor" + " << 1" * 257 + ";\n}\n")
    source.write("functio principale() -> integer {\n")
    source.write("    redde desplazar(1);\n}\n")

# After 32 one-bit left shifts, the 32-bit value is zero; further shifts stay
# zero. This expected result is independent of the compiler and RTL output.
with open(sys.argv[2], "w", encoding="utf-8") as expected:
    expected.write("R6=0\nSCRIBE=\n")
PY

PASS=0
FAIL=0
FAILED_TESTS=
for source in test/ejecucion/*.nv test/ejemplos/*.nv \
              "$TMP/muchos_temporales.nv" \
              test/optimizaciones/dce_ciclo_finito.nv \
              test/optimizaciones/dce_ciclo_potencialmente_infinito.nv \
              test/optimizaciones/dce_ciclo_con_efecto.nv \
              test/optimizaciones/dce_ciclo_resultado_usado.nv \
              test/integracion/*.nv \
              test/advertencias/W002_oculta_declaracion.nv \
              pruebas_profesor/Test*.nv; do
    [ -f "$source" ] || continue
    grep -Eq '^[[:space:]]*functio[[:space:]]+principale[[:space:]]*\(' "$source" || continue

    expected="${source%.nv}.esperado"
    if [ ! -f "$expected" ]; then
        echo "falta el resultado independiente: $expected" >&2
        exit 1
    fi
    expected_r6=$(sed -n 's/^R6=//p' "$expected" | tr -d '\r')
    # La salida comparte buffer entre scribe y dic; SCRIBE guarda la secuencia
    # completa, incluidas longitud, palabras de texto y terminadores de dic.
    expected_out=$(sed -n 's/^SCRIBE=//p' "$expected" | tr -d '\r')
    max_cycles=$(sed -n 's/^CYCLES=//p' "$expected" | tr -d '\r')
    rot_secret=$(sed -n 's/^ROT_SECRET=//p' "$expected" | tr -d '\r')
    max_cycles=${max_cycles:-20000}
    if [ -z "$expected_r6" ] || [ "$(grep -c '^R6=' "$expected")" -ne 1 ] ||
       [ "$(grep -c '^SCRIBE=' "$expected")" -ne 1 ]; then
        echo "formato invalido en $expected (se requieren R6= y SCRIBE=)" >&2
        exit 1
    fi

    object_source=
    if [ "$source" = "test/integracion/integracion_objeto.nv" ]; then
        object_source=test/integracion/calculos.nv
    fi

    # -O2 va incluido a proposito. Es el nivel que desenrolla lazos, reordena
    # instrucciones y asigna registros con derrame: las tres transformaciones
    # que pueden cambiar el resultado de un programa sin que falle la
    # compilacion. Verificarlo solo sobre casos hechos a medida y dejar el
    # corpus real en -O0 y -O1 es cubrir bien lo seguro y mal lo riesgoso.
    for level in 0 1 2; do
        echo "=== $source -O$level: R6=$expected_r6, salida=[$expected_out] ==="
        METRICAS=
        if [ -n "$METRICAS_DIR" ]; then
            # El nombre del programa lleva la ruta aplanada para que dos
            # fuentes con el mismo basename en carpetas distintas no se pisen.
            plano=$(printf '%s' "${source%.nv}" | tr '/' '_')
            METRICAS="$METRICAS_DIR/${plano}.O$level.txt"
        fi
        export METRICAS
        if OPT="-O$level" sh test/run_rtl_test.sh "$NOVAC" "$source" \
                "$expected_r6" "$CPU" "$object_source" "$rot_secret" \
                "$max_cycles" "$expected_out"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            FAILED_TESTS="${FAILED_TESTS}
  $source -O$level"
            echo "FALLO: $source -O$level" >&2
        fi
    done
done

echo "equivalencia RTL: $PASS correctas, $FAIL fallidas (-O0/-O1/-O2)"
if [ "$FAIL" -gt 0 ]; then
    printf 'casos fallidos:%s\n' "$FAILED_TESTS" >&2
fi
[ "$FAIL" -eq 0 ]
