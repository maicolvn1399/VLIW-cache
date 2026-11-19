# Unión de los dos proyectos

Compilador Nova (CE1108) en la raíz, procesador CERBERO (CE4301) en
`ARQUITECTURA/`, que es la disposición que describe
`ARQUITECTURA/docs/compiler-integration.md`.

## Qué se tomó de cada lado

No fue copiar un árbol sobre el otro: **cada proyecto traía la versión nueva de
cosas distintas**, y copiar en una sola dirección habría perdido una de las dos.

| | De dónde salió | Por qué |
|---|---|---|
| Todo el compilador: `fase1`…`fase6`, `main.c`, `test/`, `ide/`, `pruebas_profesor/`, `tools/`, `Makefile` | **nova_compiler** | Es el que tiene las cinco iteraciones: desenrollado, reordenamiento, asignación de registros con derrame, calendarización y el simulador de ciclos. El del otro zip es una foto de la iteración 3 (su `fase6_optimizacion/` no tiene `desenrollado.c`). |
| `ARQUITECTURA/` completo | **nova_cerbero** | Trae la jerarquía de caché (`l1_dcache.sv`, `l2_cache.sv`, `l2_arbiter.sv`), los contadores de las secciones 5.2 y 5.3, y el `barrido/` con las métricas por configuración. Lo que traía el compilador era una foto vieja. |
| `test/tb_nova_rtl.sv` | **nova_compiler** | Es el nuevo: lee `perf_ciclos` y `perf_instrucciones` del procesador y acepta `EXPECTED_OUT=`, `DMEM_DUMP=` y `OMITIR_VERIFICACION_RETORNO`. El de nova_cerbero es el viejo y simple. |

### Corrección: la primera versión de este documento afirmaba de más

Decía que «no se perdió ningún archivo de ninguno de los dos lados». **Era
falso**, y lo detectó una auditoría posterior que comparó los listados completos
de los dos árboles. Al tomar `documentacion/` entero del lado del compilador se
perdieron cinco guías que solo existían del otro lado:

`ITERACION1_IDE.md`, `ITERACION2_IR_BLOQUES.md`, `ITERACION3_VIVACIDAD.md`,
`PRUEBA_IDE_ITERACION3.md` y `PRUEBAS_IDE.md` — esta última enlazada desde el
`README`, que quedó con un enlace roto.

Ya están restauradas. El resto de la diferencia entre los dos listados son
artefactos generados (`.hex`, `.s`, `.nvx`, `.salida_arq/`, el binario
`novaide`) y `CAMBIOS_arquitectura_nueva.md`, que se excluyó a propósito por las
razones que están más abajo.

Un caso que **no** fue pérdida: `test/advertencias/W009_no_cabe_en_imem.nv`
desapareció, pero porque `test/run_tests.sh` lo reemplazó por un caso generado
en el momento, con dos aserciones en vez de una. Esa cobertura mejoró.

La lección de método: comparar listas de archivos es barato y había que hacerlo
antes de afirmar que no faltaba nada. Se comprueba así:

```bash
diff <(cd arbol_a && find . -type f | sort) <(cd arbol_b && find . -type f | sort)
```

## Lo que ya se verificó sobre el proyecto unificado

| | |
|---|---|
| Compilación | sin una sola advertencia de `gcc -Wall -Wextra` |
| `make prueba-unidad` | 295 correctas, 0 fallidas |
| `make prueba-ide` | 131 correctas, 0 fallidas |
| `sh tools/verificar.sh 12` en `-O0`, `-O1` y `-O2` | **26 idénticos bit a bit, 0 distintos** en los tres |

Ese último es el que importa para la unión: el `cerbero_asm.py` que ensambla es
el de la arquitectura **nueva**, y acepta el ensamblador que produce el
compilador sin un solo bit de diferencia. El contrato del ISA se mantiene:
`docs/isa.md` es idéntico en los dos proyectos.

### Compatibilidad del RTL, comprobada archivo por archivo

| Qué | Estado |
|---|---|
| `top.sv` sigue exponiendo `perf_ciclos` y `perf_instrucciones` | sí — el testbench del compilador elabora contra la CPU nueva |
| `CERBERO_IMEM_FILE` / `CERBERO_DMEM_FILE` | siguen siendo el mecanismo de carga |
| `NUM_WORDS` por omisión en `top.sv` | 16384, igual que el `DMEM_WORDS` del testbench |
| Paquetes `*_pkg.sv` que exigirían orden de compilación | ninguno; solo `cerbero_defs.svh`, cubierto por el `-I` |
| Cómo compila el RTL cada proyecto | los dos usan `cpu/*.sv` completo, así que el glob del compilador es correcto |

---

## El arreglo que hizo falta: el testbench y la caché

La unión no funcionó a la primera. Todas las corridas sobre el RTL fallaban en
la elaboración:

```
test/tb_nova_rtl.sv:84: error: Unable to bind wire/reg/memory
                        `dut.u_dmem.storage[OUT_COUNT_WORD]'
```

El testbench lee la salida de `scribe` metiéndose en la memoria del procesador
**por nombre jerárquico**. Con la arquitectura vieja esa memoria era
`dut.u_dmem`; con la jerarquía nueva ya no existe ese módulo. Los puertos
estaban bien —por eso la comprobación de puertos no lo detectó—, lo que cambió
fue la estructura interna.

Pero cambiar la ruta no alcanzaba, y esta es la parte que importa:

> **La L1-D es write-through, pero la L2 es write-back.** Cuando el programa
> levanta `halted`, lo que escribió puede estar todavía **sucio en la L2**, sin
> haber bajado a la memoria principal. Leer el arreglo de memoria en ese momento
> devolvería ceros: los programas correrían, darían el `R6` correcto y
> reportarían **cero valores de salida**. Un fallo silencioso.

El procesador ya resuelve esto: `top.sv` levanta `l2_vaciar` cuando el pipeline
se detuvo, y expone **`mem_drenada`**, que se pone en alto solo cuando el write
buffer está vacío, la L2 no retiene líneas sucias, el eviction buffer está
vacío y el bus está libre.

Los tres cambios en `test/tb_nova_rtl.sv`:

| | |
|---|---|
| Conectar `mem_drenada` del DUT | es la señal que dice que no queda nada en vuelo |
| Esperar a `mem_drenada` en vez de 8 ciclos fijos | un bundle detenido en un fallo puede quedarse decenas de ciclos, y el último store atraviesa dos buffers |
| `dut.u_dmem.storage` → `dut.u_mem_sys.u_mem.storage` | la ruta nueva |

La espera es de ciclos del arnés: `cycles` no avanza ahí, así que **no entra en
las métricas** que se reportan.

## Verificado sobre el RTL con la caché

| | |
|---|---|
| `make prueba-rtl-profesor` | **6 de 6**, con el `R6` y la salida de `scribe` correctos |
| Lectura de la salida de `scribe` | correcta: el drenado funciona |

### Lo que cuesta la caché

| Programa | Sin caché | Con caché | |
|---|---|---|---|
| `matriz_1000.nv` | 351 232 | 352 737 | ×1.00 |
| `cola.nv` | 24 088 | 24 211 | ×1.01 |
| `cifrado.nv` | 269 | 371 | ×1.38 |
| `div_cero.nv` | 48 | 108 | ×2.25 |

**En los programas grandes la caché no cuesta casi nada** —`matriz_1000` sube un
0.4 %— porque tienen buena localidad y los fallos en frío se amortizan. Los que
se ven castigados son los diminutos, donde los fallos obligatorios son casi todo
el trabajo: `div_cero` se duplica, pero son 60 ciclos.

Eso también despeja el techo que preocupaba: `matriz_1000` queda en 352 737 de
500 000, un 70.5 %. **No hizo falta tocar ningún `CYCLES=`.**

---

## El segundo arreglo: la prueba de unrolling medía el IPC

Después de la unión, `make prueba-rtl-unrolling` falló:

```
Fallo: -O2 no mejora el IPC de test/optimizaciones/unroll_variable_pequena.nv
       (-O1=0.393, -O2=0.387)
```

**No era un fallo del compilador.** `-O2` corre ese programa en **300 ciclos
contra 387 de `-O1`, un 22.5 % más rápido**. Lo que bajó fue el IPC, y bajó
*porque* la optimización funcionó: el desenrollado elimina instrucciones de
sobrecarga más rápido de lo que elimina ciclos, así que el numerador de
`instrucciones ÷ ciclos` cae más que el denominador.

Antes de unir, este caso daba `0.459 → 0.470` y pasaba por un pelo. La caché
empujó los dos IPC hacia abajo y cruzó el umbral. **La caché lo destapó; la
causa es que la aserción estaba mal escrita desde el principio.**

`test/optimizaciones/run_rtl.sh`: `verificar_mejora_ipc()` →
`verificar_mejora_ciclos()`, que exige que bajen los ciclos e imprime el IPC al
lado como información.

| Caso | ciclos `-O1` → `-O2` | | IPC |
|---|---|---|---|
| `reordenamiento_ciclo.nv` | 688 → 577 | −16.1 % | 0.385 → 0.430 |
| `unroll_variable_pequena.nv` | 387 → 300 | −22.5 % | 0.393 → 0.387 |
| `unroll_variable_400.nv` | 15 714 → 4 250 | −73.0 % | 0.460 → 0.540 |

Hay más sobre esto en `documentacion/EVIDENCIA_OPTIMIZACION.md`.

### Y una advertencia repetida 164 veces

`$value$plusargs("EXPECTED_OUT=%s", …)` se llamaba descartando el resultado, e
Icarus avisaba en **cada** corrida sobre el RTL — 164 advertencias por batería
tapando la salida útil. Ya se recoge en una variable; la batería sale limpia.

---

## La prueba que decide, sobre el proyecto unificado

```
equivalencia RTL: 117 correctas, 0 fallidas (-O0/-O1/-O2)
```

39 programas × 3 niveles sobre el RTL **con la jerarquía de caché**, comparando
`R6` y la salida de `scribe` entre niveles. La unión está verificada.

### Lo que gana optimizar, ahora medido con caché

| | Ciclos | Contra `-O0` |
|---|---|---|
| `-O0` | 546 111 | — |
| `-O1` | 523 935 | −4.1 % |
| **`-O2`** | **380 473** | **−30.3 %** |

Prácticamente lo mismo que sin caché (−30.5 %). Tiene sentido: el desenrollado y
la calendarización atacan el tiempo de emisión, no el de memoria, así que la
ganancia sobrevive al cambio de jerarquía.

### Por qué la caché no rompe la corrección

`ARQUITECTURA/src/cpu/top.sv` instancia ahora
`LSU → L1-D → write buffer → l2_arbiter → L2 → mem_system`, con una señal
`cache_stall` que detiene el pipeline cuando un acceso no se resuelve en el
ciclo.

**Esto no afecta la corrección**: el hardware hace el interbloqueo, y la regla
de tres bundles entre productor y consumidor —de la que depende todo el relleno
que emite el compilador— es de dependencias de registro, no de memoria, y sigue
igual. Por eso los 26 programas siguen saliendo idénticos bit a bit.

**Lo que sí cambia son los ciclos.** Todas las cifras medidas hasta ahora salen
del procesador *sin* caché, así que hay que volver a tomarlas.

> ⚠️ `CAMBIOS_arquitectura_nueva.md`, que venía en la raíz del proyecto de
> arquitectura, **quedó desactualizado**: dice «no hay tal caché» y que las
> latencias no cambian. Era cierto para la versión anterior; la de este zip sí
> trae la jerarquía instanciada. No se incluyó en la unión para no dejar un
> documento que contradice al RTL.

### El único techo de ciclos que está ajustado

Si algo falla por tiempo, va a ser este:

| Programa | Ciclos sin caché | Techo declarado | Uso |
|---|---|---|---|
| **`matriz_1000.nv`** | 351 232 | 500 000 | **70 %** |
| `cola.nv` | 24 088 | 100 000 | 24 % |
| `convolucion.nv` | 91 946 | 500 000 | 18 % |
| el resto | — | 20 000 (por omisión) | < 48 % |

Si `matriz_1000` se pasa del techo, **no es un error del compilador**: es que la
caché agregó detenciones. El arreglo es una línea, subir `CYCLES=` en
`test/ejecucion/matriz_1000.esperado`.

Vale la pena mirar los ciclos nuevos aunque todo pase: comparar
`matriz_1000` con y sin caché es material directo para el análisis de
rendimiento de la Iteración 5.
