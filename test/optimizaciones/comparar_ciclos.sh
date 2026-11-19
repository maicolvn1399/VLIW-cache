#!/bin/sh
set -eu

NOVAC=${1:-./novac}
CPU=${2:-ARQUITECTURA/src/cpu}
DIR=test/optimizaciones
comparaciones=0

printf '%-48s %4s %10s %14s %8s %8s\n' \
    'Programa' 'Nivel' 'Ciclos' 'Instrucciones' 'IPC' 'Bundles'

comparar() {
    fuente=$1
    esperado=$2
    nivel=$3
    scribe=${4-}

    estimacion=$("$NOVAC" --ciclos "-O$nivel" "$fuente" -o /dev/null)
    ciclos_estimados=$(printf '%s\n' "$estimacion" |
        sed -n 's/.*ciclos estimados=\([0-9][0-9]*\).*/\1/p')
    if [ -z "$ciclos_estimados" ]; then
        case "$estimacion" in
            *"no soportado:"*)
                printf '  omitida (%s): %s\n' "$fuente" "$estimacion"
                return
                ;;
            *)
                echo "Fallo: el simulador no dio resultado ni motivo para $fuente" >&2
                exit 1
                ;;
        esac
    fi

    if [ -n "$scribe" ]; then
        rtl=$(OPT="-O$nivel" sh test/run_rtl_test.sh "$NOVAC" \
            "$fuente" "$esperado" "$CPU" "" "" 500000 "$scribe")
    else
        rtl=$(OPT="-O$nivel" sh test/run_rtl_test.sh "$NOVAC" \
            "$fuente" "$esperado" "$CPU" "" "" 500000)
    fi
    ciclos_rtl=$(printf '%s\n' "$rtl" |
        sed -n 's/^[[:space:]]*ciclos RTL:[[:space:]]*//p')
    instrucciones_rtl=$(printf '%s\n' "$rtl" |
        sed -n 's/^[[:space:]]*instrucciones RTL:[[:space:]]*//p')
    ipc_rtl=$(printf '%s\n' "$rtl" |
        sed -n 's/^[[:space:]]*IPC RTL:[[:space:]]*//p')
    metricas=$("$NOVAC" --metricas "-O$nivel" "$fuente" -o /dev/null)
    bundles=$(printf '%s\n' "$metricas" | sed -n \
        's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    if [ -z "$ciclos_rtl" ] || [ -z "$instrucciones_rtl" ] ||
        [ -z "$ipc_rtl" ] || [ -z "$bundles" ]; then
        echo "Fallo: faltan metricas RTL/backend para $fuente -O$nivel" >&2
        exit 1
    fi
    if [ "$ciclos_estimados" -ne "$ciclos_rtl" ]; then
        echo "DIFERENCIA: $fuente -O$nivel: estimado=$ciclos_estimados, RTL=$ciclos_rtl" >&2
        exit 1
    fi
    comparaciones=$((comparaciones + 1))
    printf '  OK %-48s -O%d ciclos=%s\n' "$fuente" "$nivel" "$ciclos_rtl"
    printf '%-48s %4d %10s %14s %8s %8s\n' \
        "$fuente" "$nivel" "$ciclos_rtl" "$instrucciones_rtl" "$ipc_rtl" "$bundles"
}

comparar test/ejecucion/suma_10_15.nv 25 0
comparar test/ejecucion/suma_10_15.nv 25 1
comparar test/ejecucion/suma_10_15.nv 25 2
comparar test/ejecucion/matriz_for.nv 138 2
comparar test/ejecucion/matriz_transpuesta.nv 2122 2
comparar test/ejecucion/producto_punto.nv 182 2
comparar test/ejecucion/multiplicar_matrices.nv 415 2
comparar "$DIR/unroll_constante.nv" \
    "$(tr -d '\r' < "$DIR/unroll_constante.esperado")" 2
comparar "$DIR/unroll_variable_pequena.nv" \
    "$(tr -d '\r' < "$DIR/unroll_variable_pequena.esperado")" 2
comparar "$DIR/unroll_grande.nv" \
    "$(tr -d '\r' < "$DIR/unroll_grande.esperado")" 2
comparar "$DIR/renombramiento_waw.nv" 77 2
comparar "$DIR/renombramiento_war.nv" 66 2
comparar "$DIR/renombramiento_llamada.nv" 121 2
comparar "$DIR/reordenamiento_condicional.nv" 16 2
comparar "$DIR/reordenamiento_ciclo.nv" 74 2
comparar "$DIR/reordenamiento_anidado.nv" 13 2
comparar "$DIR/asignacion_presion.nv" 78 2
comparar "$DIR/asignacion_division.nv" 80 2
comparar "$DIR/dce_ciclo_scribe.nv" 6 2 "0,1,2,3"
comparar "$DIR/propagacion_scribe.nv" 14 2 "0,14"
comparar "$DIR/llamadas_scribe.nv" 0 2 "5,7"

no_soportado=$("$NOVAC" --ciclos -O2 "$DIR/asignacion_cripto.nv" -o /dev/null)
case "$no_soportado" in
    *"no soportado:"*) ;;
    *) echo "Fallo: la cripto debe identificarse como no soportada" >&2; exit 1 ;;
esac
case "$no_soportado" in
    *"ciclos estimados="*|*"bundles ejecutados="*|*"IPC estimado="*)
        echo "Fallo: se publicaron numeros para una simulacion no soportada" >&2
        exit 1
        ;;
esac
printf '  OK %-48s marcado no soportado sin cifras\n' \
    "$DIR/asignacion_cripto.nv"
printf 'Comparaciones RTL exactas: %d\n' "$comparaciones"
