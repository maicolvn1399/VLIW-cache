#!/bin/sh
set -eu

NOVAC=${1:-./novac}
CPU=${2:-ARQUITECTURA/src/cpu}
DIR=$(dirname "$0")
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nova-spill-rtl.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

verificar_presion() {
    "$NOVAC" --asignacion -O2 "$1" -o "$TMP/asignacion.txt"
    informe=$(cat "$TMP/asignacion.txt")
    printf '%s\n' "$informe" | awk '
        function cerrar_funcion() {
            if (max_funcion > max_global) max_global = max_funcion
        }
        /^Funcion / {
            cerrar_funcion()
            delete vivos
            max_funcion = 0
        }
        /^[[:space:]]+[^ ]+ \[[0-9]+,[0-9]+\] ->/ {
            rango = substr($2, 2, length($2) - 2)
            split(rango, extremos, ",")
            for (p = extremos[1]; p <= extremos[2]; p++) {
                vivos[p]++
                if (vivos[p] > max_funcion) max_funcion = vivos[p]
            }
        }
        END {
            cerrar_funcion()
            if (max_global < 9) exit 1
        }
    ' || {
        echo "Fallo: $1 no alcanza mas de 8 temporales vivos" >&2
        exit 1
    }
    case "$informe" in
        *"spill slot"*) ;;
        *) echo "Fallo: $1 no ejercita spilling" >&2; exit 1 ;;
    esac
    printf '%s\n' "$informe" | awk '
        /Cargas de pila evitadas:/ {
            if (($5 + 0) > 0 && ($10 + 0) > 0) ok = 1
        }
        END { if (!ok) exit 1 }
    ' || {
        echo "Fallo: $1 no reporta cargas/stores evitados" >&2
        exit 1
    }
    metricas=$("$NOVAC" --metricas -O2 "$1" -o /dev/null)
    printf '%s\n' "$metricas" | awk '
        /^[[:space:]]*derramadas:[[:space:]]*[0-9]+/ {
            if (($2 + 0) > 0) ok = 1
        }
        END { if (!ok) exit 1 }
    ' || {
        echo "Fallo: las metricas -O2 no reportan derrames para $1" >&2
        exit 1
    }
}

verificar_presion "$DIR/asignacion_presion.nv"
verificar_presion "$DIR/asignacion_division.nv"
verificar_presion "$DIR/asignacion_cripto.nv"

verificar_renombramiento() {
    fuente=$1
    esperado=$2
    esperado_scribe=$3
    informe_o0=$("$NOVAC" --metricas -O0 "$fuente" -o /dev/null)
    informe_o2=$("$NOVAC" --metricas -O2 "$fuente" -o /dev/null)
    if ! printf '%s\n===O2===\n%s\n' "$informe_o0" "$informe_o2" |
            python3 -c '
import re
import sys

o0, o2 = sys.stdin.read().split("\n===O2===\n", 1)

def medicion(texto):
    despues = texto.split("  DESPUES\n", 1)[1]
    def leer(patron, bloque):
        resultado = re.search(patron, bloque, re.MULTILINE)
        if resultado is None:
            raise ValueError(patron)
        return int(resultado.group(1))
    return {
        "renombradas": leer(r"^\s*renombradas:\s*(\d+)", texto),
        "war": leer(r"^\s*NOPs por dependencia WAR:\s*(\d+)", despues),
        "waw": leer(r"^\s*NOPs por dependencia WAW:\s*(\d+)", despues),
        "dependencias_war": leer(r"^\s*dependencias WAR:\s*(\d+)", despues),
        "dependencias_waw": leer(r"^\s*dependencias WAW:\s*(\d+)", despues),
    }

antes = medicion(o0)
despues = medicion(o2)
nops_antes = antes["war"] + antes["waw"]
nops_despues = despues["war"] + despues["waw"]
dependencias_antes = antes["dependencias_war"] + antes["dependencias_waw"]
dependencias_despues = (
    despues["dependencias_war"] + despues["dependencias_waw"])
if despues["renombradas"] == 0:
    raise SystemExit("renombradas=0")
if nops_despues >= nops_antes:
    raise SystemExit(f"NOPs WAR/WAW no bajaron: {nops_antes} -> {nops_despues}")
if (despues["dependencias_war"] >= antes["dependencias_war"] or
        despues["dependencias_waw"] >= antes["dependencias_waw"] or
        dependencias_despues >= dependencias_antes):
    raise SystemExit(
        "dependencias WAR/WAW no bajaron: "
        f"{dependencias_antes} -> {dependencias_despues}")
'; then
        echo "Fallo: $fuente no reduce dependencias/NOPs WAR/WAW en -O2" >&2
        exit 1
    fi

    salida_o0=$(OPT="-O0" sh test/run_rtl_test.sh "$NOVAC" \
        "$fuente" "$esperado" "$CPU" "" "" 20000 "$esperado_scribe")
    salida_o2=$(OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
        "$fuente" "$esperado" "$CPU" "" "" 20000 "$esperado_scribe")
    printf '%s\n' "$salida_o0"
    printf '%s\n' "$salida_o2"
    if ! printf '%s\n===O2===\n%s\n' "$salida_o0" "$salida_o2" |
            python3 -c '
import re
import sys

o0, o2 = sys.stdin.read().split("\n===O2===\n", 1)

def resultado(texto):
    retorno = re.search(r"retorno R6:\s*(-?\d+)", texto)
    salida = re.findall(r"^\s+\[\d+\]\s+(-?\d+)\s", texto, re.MULTILINE)
    if retorno is None:
        raise SystemExit("no se encontro R6")
    return retorno.group(1), salida

if resultado(o0) != resultado(o2):
    raise SystemExit(f"R6/scribe difieren: {resultado(o0)} != {resultado(o2)}")
'; then
        echo "Fallo: $fuente cambia R6 o scribe entre -O0 y -O2" >&2
        exit 1
    fi
}

for caso in \
    "renombramiento_waw.nv 77 77" \
    "renombramiento_war.nv 66 66" \
    "renombramiento_llamada.nv 121 121"; do
    set -- $caso
    verificar_renombramiento "$DIR/$1" "$2" "$3"
done

for caso in \
    "reordenamiento_condicional.nv 16" \
    "reordenamiento_ciclo.nv 74" \
    "reordenamiento_anidado.nv 13"; do
    set -- $caso
    fuente="$DIR/$1"
    esperado=$2
    informe=$("$NOVAC" --metricas -O2 "$fuente" -o /dev/null)
    if ! printf '%s\n' "$informe" |
            grep -Eq '^[[:space:]]+reordenadas:[[:space:]]+[1-9][0-9]*'; then
        echo "Fallo: $fuente no demuestra reordenamiento en -O2" >&2
        exit 1
    fi
    OPT="-O0" sh test/run_rtl_test.sh "$NOVAC" "$fuente" "$esperado" "$CPU"
    OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" "$fuente" "$esperado" "$CPU"
done

# Que -O2 corra mas rapido que -O1, medido en CICLOS.
#
# Antes esta comprobacion exigia que subiera el IPC, y eso es medir lo que no
# se quiere. El IPC es instrucciones/ciclos: una optimizacion que quita trabajo
# baja las dos cosas, y el cociente puede moverse para cualquier lado. El
# desenrollado quita justamente instrucciones de puro gasto -- la actualizacion
# del contador y el salto de cada vuelta -- asi que las instrucciones pueden
# caer mas rapido que los ciclos y el IPC bajar mientras el programa se acelera.
#
# Paso con 'unroll_variable_pequena.nv' al montar la jerarquia de memoria:
#
#       -O1   387 ciclos, 152 instrucciones, IPC 0.393
#       -O2   300 ciclos, 116 instrucciones, IPC 0.387
#
# 22.5% menos ciclos, y la comprobacion del IPC lo daba por fallo. Sin cache el
# equilibrio caia del otro lado y pasaba, pero por casualidad, no porque la
# afirmacion fuera correcta.
#
# Los ciclos si son la medida: son el tiempo de ejecucion. El IPC se sigue
# reportando, que para eso sirve -- dice cuanto del ancho VLIW se aprovecha --
# pero no decide si la prueba pasa.
verificar_mejora_ciclos() {
    fuente=$1
    esperado=$2
    salida_o1=$(OPT="-O1" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU")
    salida_o2=$(OPT="-O2" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU")
    ciclos_o1=$(printf '%s\n' "$salida_o1" | awk '/ciclos RTL:/ { print $3; exit }')
    ciclos_o2=$(printf '%s\n' "$salida_o2" | awk '/ciclos RTL:/ { print $3; exit }')
    ipc_o1=$(printf '%s\n' "$salida_o1" | awk '/IPC RTL:/ { print $3; exit }')
    ipc_o2=$(printf '%s\n' "$salida_o2" | awk '/IPC RTL:/ { print $3; exit }')
    if [ -z "$ciclos_o1" ] || [ -z "$ciclos_o2" ] ||
        [ "$ciclos_o2" -ge "$ciclos_o1" ]; then
        echo "Fallo: -O2 no reduce los ciclos de $fuente" \
             "(-O1=$ciclos_o1, -O2=$ciclos_o2)" >&2
        exit 1
    fi
    printf '  %s: ciclos -O1=%s -O2=%s (-%s%%), IPC -O1=%s -O2=%s\n' \
        "$(basename "$fuente")" "$ciclos_o1" "$ciclos_o2" \
        "$(awk -v a="$ciclos_o1" -v b="$ciclos_o2" \
             'BEGIN { printf "%.1f", 100*(a-b)/a }')" \
        "$ipc_o1" "$ipc_o2"
}

verificar_mejora_ciclos "$DIR/reordenamiento_ciclo.nv" 74
verificar_mejora_ciclos "$DIR/unroll_variable_pequena.nv" \
    "$(cat "$DIR/unroll_variable_pequena.esperado")"
verificar_mejora_ciclos "$DIR/unroll_variable_400.nv" \
    "$(tr -d '\r' < "$DIR/unroll_variable_400.esperado")"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/unroll_constante.nv" "$(cat "$DIR/unroll_constante.esperado")" "$CPU"

OPT="-O2 --unroll=4" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/unroll_variable_pequena.nv" \
    "$(cat "$DIR/unroll_variable_pequena.esperado")" "$CPU"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/unroll_grande.nv" "$(cat "$DIR/unroll_grande.esperado")" "$CPU"

for caso in \
    "unroll_ruta_inicial.nv 6" \
    "unroll_update_condicional.nv 3" \
    "unroll_limite_paso_condicional.nv 2"; do
    set -- $caso
    fuente="$DIR/$1"
    esperado=$2
    OPT="-O0" sh test/run_rtl_test.sh "$NOVAC" "$fuente" "$esperado" "$CPU"
    OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" "$fuente" "$esperado" "$CPU"
done

verificar_niveles_unroll() {
    fuente=$1
    esperado=$2
    for nivel in 0 1 2; do
        salida=$(OPT="-O$nivel" sh test/run_rtl_test.sh \
            "$NOVAC" "$fuente" "$esperado" "$CPU")
        printf '%s\n' "$salida"
        retorno=$(printf '%s\n' "$salida" |
            awk '/retorno R6:/ { print $3; exit }')
        if [ "$retorno" != "$esperado" ]; then
            echo "Fallo: $fuente cambia R6 en -O$nivel ($retorno)" >&2
            exit 1
        fi
    done
}

for caso in \
    "unroll_n0.nv 10" \
    "unroll_n1.nv 1" \
    "unroll_resto_variable.nv 21" \
    "unroll_descendente.nv 22" \
    "unroll_division.nv 354" \
    "unroll_limite_modificado.nv 3" \
    "unroll_rumpe.nv 3" \
    "unroll_perge.nv 12" \
    "unroll_anidado.nv 138"; do
    set -- $caso
    verificar_niveles_unroll "$DIR/$1" "$2"
done

for caso in \
    "unroll_division_cero.nv 136" \
    "unroll_rango.nv 134" \
    "unroll_boveda.nv 137"; do
    set -- $caso
    verificar_niveles_unroll "$DIR/$1" "$2"
done

for caso in \
    "unroll_descendente.nv 22 3" \
    "unroll_division.nv 354 4" \
    "unroll_division_cero.nv 136 2" \
    "unroll_rango.nv 134 2" \
    "unroll_boveda.nv 137 2"; do
    set -- $caso
    fuente="$DIR/$1"
    esperado=$2
    factor=$3
    OPT="-O2 --unroll=$factor" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU"
done

for fuente in \
    "$DIR/unroll_limite_modificado.nv" \
    "$DIR/unroll_rumpe.nv" \
    "$DIR/unroll_perge.nv" \
    "$DIR/unroll_anidado.nv"; do
    esperado=$(tr -d '\r' < "${fuente%.nv}.esperado")
    OPT="-O2 --unroll=4" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU"
done

if "$NOVAC" --ir -O2 --unroll=4 \
        "$DIR/unroll_resto_variable.nv" |
        grep -Eq '^[[:space:]]*nop([[:space:]]|$)'; then
    echo "Fallo: quedo un TAC_NOP en el IR desenrollado" >&2
    exit 1
fi

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    test/ejecucion/matriz_for.nv 138 "$CPU"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/asignacion_presion.nv" 78 "$CPU"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/asignacion_division.nv" 80 "$CPU"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/asignacion_cripto.nv" 55 "$CPU" "" \
    "128'h0000_0000_0000_0000_0000_0000_7654_3210"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/dce_ciclo_scribe.nv" 6 "$CPU" "" "" 20000 "0,1,2,3"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/propagacion_scribe.nv" 14 "$CPU" "" "" 20000 "0,14"

OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/llamadas_scribe.nv" 0 "$CPU" "" "" 20000 "5,7"

salida_o0=$(OPT="-O0" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/unroll_reduccion_ciclos.nv" 190 "$CPU")
printf '%s\n' "$salida_o0"
ciclos_o0=$(printf '%s\n' "$salida_o0" |
    awk '/ciclos RTL:/ { print $3; exit }')

salida_o2=$(OPT="-O2" sh test/run_rtl_test.sh "$NOVAC" \
    "$DIR/unroll_reduccion_ciclos.nv" 190 "$CPU")
printf '%s\n' "$salida_o2"
ciclos_o2=$(printf '%s\n' "$salida_o2" |
    awk '/ciclos RTL:/ { print $3; exit }')

if [ -z "$ciclos_o0" ] || [ -z "$ciclos_o2" ] ||
        [ "$ciclos_o2" -ge "$ciclos_o0" ]; then
    echo "Fallo: -O2 no redujo los ciclos RTL del bucle dinamico " \
         "($ciclos_o0 -> $ciclos_o2)" >&2
    exit 1
fi
printf '  Ciclos del bucle dinamico: -O0=%s, -O2=%s\n' \
    "$ciclos_o0" "$ciclos_o2"

verificar_ciclos_unroll() {
    fuente=$1
    esperado=$2
    salida_o0=$(OPT="-O0" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU")
    salida_o2=$(OPT="-O2" sh test/run_rtl_test.sh \
        "$NOVAC" "$fuente" "$esperado" "$CPU")
    printf '%s\n' "$salida_o0"
    printf '%s\n' "$salida_o2"
    ciclos_o0=$(printf '%s\n' "$salida_o0" |
        awk '/ciclos RTL:/ { print $3; exit }')
    ciclos_o2=$(printf '%s\n' "$salida_o2" |
        awk '/ciclos RTL:/ { print $3; exit }')
    if [ -z "$ciclos_o0" ] || [ -z "$ciclos_o2" ] ||
            [ "$ciclos_o2" -ge "$ciclos_o0" ]; then
        echo "Fallo: -O2 no redujo ciclos en $fuente " \
             "($ciclos_o0 -> $ciclos_o2)" >&2
        exit 1
    fi
    printf '  Ciclos de %s: -O0=%s, -O2=%s\n' \
        "$(basename "$fuente")" "$ciclos_o0" "$ciclos_o2"
}

verificar_ciclos_unroll "$DIR/unroll_variable_pequena.nv" \
    "$(cat "$DIR/unroll_variable_pequena.esperado")"
verificar_ciclos_unroll "$DIR/unroll_variable_400.nv" \
    "$(tr -d '\r' < "$DIR/unroll_variable_400.esperado")"
verificar_niveles_unroll "$DIR/unroll_variable_400.nv" \
    "$(tr -d '\r' < "$DIR/unroll_variable_400.esperado")"
verificar_niveles_unroll "$DIR/unroll_variable_pequena.nv" \
    "$(cat "$DIR/unroll_variable_pequena.esperado")"

ciclos_default=$(OPT="-O2" sh test/run_rtl_test.sh \
    "$NOVAC" "$DIR/unroll_variable_400.nv" \
    "$(tr -d '\r' < "$DIR/unroll_variable_400.esperado")" "$CPU" |
    awk '/ciclos RTL:/ { print $3; exit }')
mejor_factor=2147483647
for factor in 2 4 8; do
    ciclos_factor=$(OPT="-O2 --unroll=$factor" sh test/run_rtl_test.sh \
        "$NOVAC" "$DIR/unroll_variable_400.nv" \
        "$(tr -d '\r' < "$DIR/unroll_variable_400.esperado")" "$CPU" |
        awk '/ciclos RTL:/ { print $3; exit }')
    if [ -z "$ciclos_factor" ]; then
        echo "Fallo: no se midieron ciclos con --unroll=$factor" >&2
        exit 1
    fi
    if [ "$ciclos_factor" -lt "$mejor_factor" ]; then
        mejor_factor=$ciclos_factor
    fi
done
if [ -z "$ciclos_default" ] || [ "$ciclos_default" -gt "$mejor_factor" ]; then
    echo "Fallo: el default ($ciclos_default) supera el mejor factor " \
         "2/4/8 ($mejor_factor)" >&2
    exit 1
fi
printf '  Ciclos N=400: default=%s, mejor --unroll=2/4/8=%s\n' \
    "$ciclos_default" "$mejor_factor"
