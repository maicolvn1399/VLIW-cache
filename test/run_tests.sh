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
    if [ "$nombre" = "W010_efectos_conservados" ]; then
        out=$("$NOVAC" -O1 "$f" -o "$TMPEXE" 2>&1); rc=$?
    elif [ "$nombre" = "W008_region_segura_llena" ]; then
        out=$("$NOVAC" --calendario "$f" -o "$TMPEXE" 2>&1); rc=$?
    else
        out=$("$NOVAC" "$f" -o "$TMPEXE" 2>&1); rc=$?
    fi
    if [ $rc -ne 0 ]; then bad "$nombre: se esperaba rc=0 y fue rc=$rc" "$out"; continue; fi
    codigo=${nombre%%_*}
    obtenidos=$(echo "$out" | grep -o 'advertencia\[W[0-9]*\]' | sed 's/advertencia\[\(.*\)\]/\1/' | tr '\n' ' ')
    case " $obtenidos" in
        *" $codigo "*) ok ;;
        *) bad "$nombre: se esperaba $codigo y se obtuvo [$obtenidos]" "$out" ;;
    esac
    if [ "$nombre" = "W010_efectos_conservados" ]; then
        if echo "$out" | grep -q "W010.*division_muerta.*se conservan efectos de esta linea" &&
           echo "$out" | grep -q "W010.*indice_muerto.*se conservan efectos de esta linea"; then
            ok
        else
            bad "$nombre: los efectos deben atribuirse a la linea, no a la asignacion" "$out"
        fi
    fi
done

printf 'functio principale() -> integer { varia sin_uso : integer = 7; scribe(42); redde 0; }\n' \
    > "$TMP/W010_misma_linea.nv"
out=$("$NOVAC" -O1 "$TMP/W010_misma_linea.nv" -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -q "W010.*sin_uso.*se conservan efectos de esta linea"; then
    ok
else
    bad "W010 no debe atribuir scribe a la asignacion muerta de la misma linea (rc=$rc)" "$out"
fi

# T2: el marcado desde efectos elimina una recurrencia que solo se usa a si
# misma, y la propagacion/plegado/reduccion de fuerza queda visible en el TAC.
out=$("$NOVAC" -Wno-W010 --ir -O1 "$DIR/ejecucion/t2_ciclo_muerto.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   ! echo "$out" | grep -q 'acumulador_muerto =' &&
   echo "$out" | grep -q 'acumulador_vivo'; then
    ok
else
    bad "DCE debe quitar el ciclo muerto y conservar el acumulador devuelto" "$out"
fi

metricas_o0=$("$NOVAC" --metricas -O0 "$DIR/ejecucion/matriz_for.nv" \
    -o "$TMPEXE" 2>&1)
rc_o0=$?
metricas_o1=$("$NOVAC" --metricas -O1 "$DIR/ejecucion/matriz_for.nv" \
    -o "$TMPEXE" 2>&1)
rc_o1=$?
bundles_o0=$(echo "$metricas_o0" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
bundles_o1=$(echo "$metricas_o1" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
if [ "$rc_o0" -eq 0 ] && [ "$rc_o1" -eq 0 ] &&
   [ -n "$bundles_o0" ] && [ -n "$bundles_o1" ] &&
   [ "$bundles_o1" -lt "$bundles_o0" ]; then
    ok
else
    bad "-O1 debe reducir los bundles de matriz_for con shifts inmediatos (O0=$bundles_o0, O1=$bundles_o1)" \
        "$metricas_o0
$metricas_o1"
fi

out=$("$NOVAC" --ir -O1 "$DIR/ejecucion/t2_propagacion.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'total = #14' &&
   echo "$out" | grep -q 'valor <<'; then
    ok
else
    bad "O1 debe propagar, plegar y reducir valor * 8 a un desplazamiento" "$out"
fi

out=$("$NOVAC" --metricas -O1 "$DIR/ejecucion/t2_propagacion.nv" \
    -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -Eq 'constantes plegadas:[[:space:]]*[1-9][0-9]*' &&
   echo "$out" | grep -Eq 'valores propagados:[[:space:]]*[1-9][0-9]*' &&
   echo "$out" | grep -Eq 'reducciones de fuerza:[[:space:]]*[1-9][0-9]*'; then
    ok
else
    bad "--metricas debe contar plegados, propagaciones y reducciones de fuerza" "$out"
fi

# Regresiones de optimizacion con efectos observables. Las llamadas a scribe
# deben sobrevivir aunque alrededor haya definiciones muertas o ciclos sin raiz.
opt_dir="$DIR/optimizaciones"
for fuente in \
    "$opt_dir/dce_ciclo_scribe.nv" \
    "$opt_dir/propagacion_scribe.nv" \
    "$opt_dir/llamadas_scribe.nv"; do
    out=$("$NOVAC" --ir -O1 "$fuente" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'call __scribe_int'; then
        ok
    else
        bad "O1 debe conservar las llamadas a scribe de $fuente (rc=$rc)" "$out"
    fi
done

out=$("$NOVAC" --ir -O1 "$opt_dir/dce_ciclo_scribe.nv" 2>&1); rc=$?
ir=$(printf '%s\n' "$out" | sed -n \
    '/^=== Codigo intermedio de tres direcciones ===$/,$p')
if [ "$rc" -eq 0 ] &&
   ! echo "$ir" | grep -q 'acumulador_muerto =' &&
   echo "$ir" | grep -q 'acumulador_vivo'; then
    ok
else
    bad "O1 debe eliminar el ciclo muerto y conservar el valor observable" "$out"
fi

out=$("$NOVAC" --ir -O1 "$opt_dir/propagacion_scribe.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'total = #14' &&
   echo "$out" | grep -q 'acumulado = #0' &&
   ! echo "$out" | grep -q 'acumulado = t'; then
    ok
else
    bad "O1 debe propagar #0 y plegar constantes en los valores observables" "$out"
fi

out=$("$NOVAC" --ir -O1 "$opt_dir/llamadas_scribe.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -q 'call informar, 1' &&
   ! echo "$out" | grep -q '= call informar' &&
   ! echo "$out" | grep -Eq 'calculo_muerto =|ciclo_muerto ='; then
    ok
else
    bad "O1 debe conservar efectos y eliminar el calculo y ciclo muertos" "$out"
fi

out=$("$NOVAC" --metricas -O1 "$opt_dir/propagacion_scribe.nv" \
    -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -Eq 'eliminadas:[[:space:]]*[1-9][0-9]*' &&
   echo "$out" | grep -Eq 'constantes plegadas:[[:space:]]*[1-9][0-9]*' &&
   echo "$out" | grep -Eq 'valores propagados:[[:space:]]*[1-9][0-9]*'; then
    ok
else
    bad "--metricas debe contar eliminaciones, plegados y propagaciones" "$out"
fi

out=$("$NOVAC" --ir -O1 "$opt_dir/dce_ciclo_finito.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   ! echo "$out" | grep -Eq '^[[:space:]]*(ifFalse|ifTrue|goto)[[:space:]]'; then
    ok
else
    bad "DCE debe eliminar el ciclo finito sin efectos cuyo contador es muerto (rc=$rc)" "$out"
fi

for caso in \
    "dce_ciclo_potencialmente_infinito.nv ifFalse" \
    "dce_ciclo_con_efecto.nv call __scribe_int" \
    "dce_ciclo_resultado_usado.nv ifFalse"; do
    set -- $caso
    out=$("$NOVAC" --ir -O1 "$opt_dir/$1" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "$2"; then
        ok
    else
        bad "DCE debe conservar el ciclo de $1 ($2)" "$out"
    fi
done

# T3: el calendarizador debe respetar la dependencia de banderas antes de un
# salto condicional, aunque el bloque tenga una comparacion y un calculo
# independiente en la misma region.
out=$("$NOVAC" --ir -O1 "$DIR/ejecucion/t3_reorden_flags.nv" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'ifFalse'; then
    ok
else
    bad "la comparacion y el salto condicional deben mantenerse correctos" "$out"
fi

# Iteracion 4: -O2 aplica el unrolling sobre el TAC antes del DCE. El caso
# variable con factor 4 verifica que las copias conservan la condicion para el
# resto (7 iteraciones = un grupo de 4 y tres iteraciones restantes).
for fuente in \
    "$DIR/optimizaciones/unroll_constante.nv" \
    "$DIR/optimizaciones/unroll_grande.nv"; do
    out=$("$NOVAC" --metricas -O2 "$fuente" -o "$TMPEXE" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] &&
       echo "$out" | grep -Eq 'bucles desplegados antes del DCE:[[:space:]]*[1-9][0-9]*'; then
        ok
    else
        bad "O2 debe desenrollar el lazo contado de $fuente (rc=$rc)" "$out"
    fi
done

out=$("$NOVAC" --metricas --unroll=4 \
    "$DIR/optimizaciones/unroll_variable_pequena.nv" -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -Eq 'bucles desplegados antes del DCE:[[:space:]]*[1-9][0-9]*'; then
    ok
else
    bad "--unroll=4 debe aceptar un lazo con trip count variable (rc=$rc)" "$out"
fi

out=$("$NOVAC" --unroll=0 "$DIR/optimizaciones/unroll_constante.nv" 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'valor invalido para --unroll'; then
    ok
else
    bad "--unroll debe rechazar factores fuera del rango documentado (rc=$rc)" "$out"
fi

metricas_unroll4=$("$NOVAC" --metricas --unroll=4 \
    "$DIR/optimizaciones/unroll_constante.nv" -o "$TMPEXE" 2>&1); rc4=$?
metricas_unroll8=$("$NOVAC" --metricas --unroll=8 \
    "$DIR/optimizaciones/unroll_constante.nv" -o "$TMPEXE" 2>&1); rc8=$?
bundles_unroll4=$(echo "$metricas_unroll4" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
bundles_unroll8=$(echo "$metricas_unroll8" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
ir_unroll8=$("$NOVAC" --ir --unroll=8 \
    "$DIR/optimizaciones/unroll_constante.nv" 2>&1); rc_ir=$?
if [ "$rc4" -eq 0 ] && [ "$rc8" -eq 0 ] && [ "$rc_ir" -eq 0 ] &&
   [ -n "$bundles_unroll4" ] && [ -n "$bundles_unroll8" ] &&
   [ "$bundles_unroll8" -lt "$bundles_unroll4" ] &&
   ! echo "$ir_unroll8" | grep -Eq '^[[:space:]]*(ifFalse|ifTrue|goto)[[:space:]]'; then
    ok
else
    bad "--unroll=8 debe desplegar totalmente las 5 iteraciones y emitir menos bundles que --unroll=4 (rc4=$rc4, rc8=$rc8, rc_ir=$rc_ir, bundles4=$bundles_unroll4, bundles8=$bundles_unroll8)" "$ir_unroll8"
fi

out=$("$NOVAC" -O2 --metricas "$DIR/ejecucion/matriz_for.nv" \
    -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -Eq 'bucles desplegados antes del DCE:[[:space:]]*[1-9][0-9]*'; then
    ok
else
    bad "O2 debe desenrollar lazos internos sin exceder el alcance de salto (rc=$rc)" "$out"
fi

out=$("$NOVAC" -w --metricas -O1 "$DIR/ejecucion/multiplicar_matrices.nv" \
    -o "$TMPEXE" 2>&1); rc=$?
bundles=$(echo "$out" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
if [ "$rc" -eq 0 ] && [ -n "$bundles" ] && [ "$bundles" -le 2048 ]; then
    ok
else
    bad "la heuristica de unrolling debe respetar el presupuesto de IMEM (rc=$rc, bundles=$bundles)" "$out"
fi

# W009 sigue siendo necesario para programas que realmente exceden la IMEM.
# Varias llamadas en una funcion generan mas de 2048 bundles sin rebasar
# MAX_TEMPS; el caso se construye aqui para no mantener un vector enorme.
python3 - "$TMP/W009_no_cabe_en_imem.nv" <<'PY'
import sys

calls = " + ".join(["repetir()"] * 240)
with open(sys.argv[1], "w", encoding="utf-8") as source:
    source.write("functio repetir() -> integer { redde 1; }\n")
    source.write(f"functio principale() -> integer {{ redde {calls}; }}\n")
PY
out=$("$NOVAC" "$TMP/W009_no_cabe_en_imem.nv" -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'error\[E410\]' &&
   echo "$out" | grep -q 'limite de IMEM' && ! echo "$out" | grep -q 'advertencia\[W009\]' &&
   [ ! -e "$TMPEXE" ]; then
    ok
else
    bad "un ejecutable que excede 2048 bundles debe fallar con E410 y no dejar binario (rc=$rc)" "$out"
fi

out=$("$NOVAC" --calendario "$TMP/W009_no_cabe_en_imem.nv" \
    -o "$TMPEXE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'advertencia\[W009\]'; then
    ok
else
    bad "el modo de analisis debe conservar W009 para programas que exceden la IMEM (rc=$rc)" "$out"
fi

# La tabla dinamica debe admitir mas de 512 temporales. 257 shifts crean un
# temporal para cada literal y otro para cada resultado, pero caben en IMEM.
python3 - "$TMP/muchos_temporales.nv" <<'PY'
import sys

with open(sys.argv[1], "w", encoding="utf-8") as source:
    source.write("functio desplazar(valor : integer) -> integer {\n")
    source.write("    redde valor" + " << 1" * 257 + ";\n}\n")
    source.write("functio principale() -> integer {\n")
    source.write("    redde desplazar(1);\n}\n")
PY
ir=$("$NOVAC" --ir "$TMP/muchos_temporales.nv" 2>&1); rc_ir=$?
temporales=$(echo "$ir" | grep -Ec '^[[:space:]]*t[0-9]+[[:space:]]*=')
if [ "$rc_ir" -eq 0 ] && [ "$temporales" -gt 512 ]; then
    ok
else
    bad "la regresion debe crear mas de 512 temporales TAC (rc=$rc_ir, temporales=$temporales)" "$ir"
fi

out=$("$NOVAC" --metricas "$TMP/muchos_temporales.nv" -o "$TMPEXE" 2>&1); rc=$?
bundles=$(echo "$out" | sed -n \
    's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
bytes=$(echo "$out" | sed -n \
    's/.*bundles emitidos:[[:space:]]*[0-9][0-9]*[[:space:]]*(\([0-9][0-9]*\) bytes de IMEM).*/\1/p')
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'error\[E410\]' &&
   [ -n "$bundles" ] && [ -n "$bytes" ] &&
   [ "$bundles" -le 2048 ] &&
   [ "$bytes" -eq $((bundles * 16)) ]; then
    ok
else
    bad "mas de 512 temporales deben caber en IMEM y satisfacer bytes=16*bundles (rc=$rc, bundles=$bundles, bytes=$bytes)" "$out"
fi

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
printf 'constans A : integer = 0xDEADBEEF;\n' > "$TMP/hex.tmp.nv"
out=$("$NOVAC" -t "$TMP/hex.tmp.nv" 2>&1); rc=$?
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
    # La asignacion de temporales puede cambiar el tamano total de cada marco;
    # las posiciones de las tres locales deben conservar sus offsets relativos.
    if [ $rc -eq 0 ] &&
       echo "$out" | grep -Eq 'DMEM @0x[0-9A-F]{4}  = r14\+8' &&
       echo "$out" | grep -Eq 'DMEM @0x[0-9A-F]{4}  = r14\+4' &&
       echo "$out" | grep -Eq 'DMEM @0x[0-9A-F]{4}  = r14\+0' &&
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

out=$("$NOVAC" -p "$DIR/ejemplos/convolucion.nv" \
    -o "$TMP/convolucion.paquetes.txt" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && awk -F '|' '
    /^0x/ {
        slots[1] = substr($1, 21, 26)
        slots[2] = $2
        slots[3] = $3
        slots[4] = $4
        slots[5] = substr($5, 1, 16)
        usados = 0
        for (i = 1; i <= 5; i++) {
            gsub(/[[:space:]]/, "", slots[i])
            if (slots[i] != "" && slots[i] != "-") usados++
        }
        if (usados > 1) encontrado = 1
        if (slots[2] != "" && slots[2] != "-") usa_alu1 = 1
    }
    END { exit !(encontrado && usa_alu1) }
' "$TMP/convolucion.paquetes.txt"; then
    ok
else
    bad "la calendarizacion debe ocupar S1 y empaquetar operaciones independientes (rc=$rc)" "$out"
fi

archivo_calendario="$TMP/suma_10_15.calendario.txt"
out=$("$NOVAC" --calendario -O1 "$DIR/ejecucion/suma_10_15.nv" \
    -o "$archivo_calendario" 2>&1); rc=$?
if [ -f "$archivo_calendario" ]; then
    out="$out
$(cat "$archivo_calendario")"
fi
calendario_correcto=0
if [ "$rc" -eq 0 ] &&
   echo "$out" | grep -q '^Calendario estatico:' &&
   echo "$out" | grep -Fq \
       "NOP S1: dependencia RAW R0: op 1 'movi r0, #25' -> op 2 'mov r6, r0' (3 bundles)" &&
   echo "$out" | awk '
       /^[0-9][0-9][0-9][0-9] / {
           numero = substr($0, 1, 4) + 0
           if (espera_delay) {
               es_delay = numero == salto + 1
               espera_delay = 0
           } else {
               es_delay = 0
           }
           if (index($0, "S4=jal.al principale") > 0) {
               salto = numero
               espera_delay = 1
           }
           next
       }
       es_delay && index($0, "NOP S0: NOP de delay slot") > 0 {
           delay_encontrado = 1
       }
       END { exit !delay_encontrado }
   '; then
    calendario_correcto=1
    ok
else
    bad "--calendario debe mostrar RAW de 3 bundles (operaciones/slot) y un NOP justo tras jal (rc=$rc)" "$out"
fi
mutado=$(printf '%s\n' "$out" | sed \
    "s/NOP S1: dependencia RAW R0: op 1 'movi r0, #25' -> op 2 'mov r6, r0' (3 bundles)/NOP S1: dependencia RAW R0: op 1 'movi r0, #25' -> op 2 'mov r6, r0' (2 bundles)/")
if [ "$calendario_correcto" -eq 1 ] &&
   ! printf '%s\n' "$mutado" | grep -Fq \
       "NOP S1: dependencia RAW R0: op 1 'movi r0, #25' -> op 2 'mov r6, r0' (3 bundles)"; then
    ok
else
    bad "la comprobacion de --calendario debe detectar mutar 3 bundles a 2" "$mutado"
fi

for fuente in "$DIR/ejemplos/convolucion.nv" "$DIR/ejemplos/multiplicacion.nv"; do
    nombre=$(basename "$fuente" .nv)
    out=$("$NOVAC" -Wno-W009 --metricas "$fuente" \
        -o "$TMP/$nombre.nvx" 2>&1); rc=$?
    bundles=$(echo "$out" | sed -n \
        's/.*bundles emitidos:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    if [ "$rc" -eq 0 ] && [ -n "$bundles" ] && [ "$bundles" -le 2048 ]; then
        ok
    else
        bad "$nombre debe caber en los 2048 bundles de IMEM (rc=$rc, bundles=$bundles)" "$out"
    fi
    rm -f "$TMP/$nombre.nvx"
done

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

out=$(python3 "$DIR/verificar_presupuesto_imem.py" "$NOVAC" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    ok
else
    bad "O2 debe mantener los programas ejecutables de test/ dentro de IMEM (rc=$rc)" "$out"
fi

echo
echo "pruebas: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
