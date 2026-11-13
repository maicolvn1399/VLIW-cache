# Análisis de rendimiento y validación

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Sección 3 de la documentación de diseño: metodología de medición, contadores, benchmarks, análisis de resultados, comparación entre configuraciones y justificación de las decisiones.

Complementos: [jerarquia-memoria.md](jerarquia-memoria.md) (políticas) y [organizacion.md](organizacion.md) (microarquitectura). Todo lo de aquí se reproduce con:

```bash
cd src/build && make metricas
cd .. && ./tools/barrido_cache.sh && python3 tools/tabla_barrido.py barrido
```

---

## 1. Metodología

**Los contadores están en el hardware.** Las métricas las produce `perf_counters.sv`, un módulo RTL dentro de `top.sv`, no un testbench que observa señales internas. La diferencia no es de estilo: un testbench que calcula la tasa de aciertos mirando `dut.u_l1d.acierto` mide su propia interpretación del diseño, y si está mal el número sale mal sin que nada avise. Los contadores reciben pulsos que la caché emite por puertos dedicados y son lo que un procesador real reportaría. No tienen salida hacia el datapath, así que medir no puede cambiar lo medido.

**Por qué no se usó `perf` de Linux.** El profesor pidió revisarlo. No puede medir este sistema, corra o no en WSL, y la razón es qué mide: `perf` instrumenta el procesador del anfitrión, y lo que el anfitrión ejecuta es `vvp`, el simulador. Reportaría los fallos de caché del Intel o AMD de la máquina mientras interpreta el netlist, no los de CERBERO-1. Son dos jerarquías distintas y la que ve es la equivocada. Para el procesador simulado el instrumento correcto son contadores dentro del diseño, que es lo que un procesador real también lleva (los PMU del ARM, el `rdpmc` del x86). `perf` sí serviría para medir el compilador NOVA, que es un programa nativo.

**Qué cuenta como qué.**

| Métrica | Definición exacta | Por qué así |
|---|---|---|
| ciclos | del reset a `HALT` | no incluye los ciclos del arnés esperando el drenado |
| bundles | los que **avanzaron**, no los que estuvieron | un bundle congelado 53 ciclos cuenta una vez, no 54 |
| instrucciones | operaciones no-NOP despachadas | cinco por bundle como máximo |
| aciertos / fallos | un pulso por acceso, en su ciclo | un fallo que espera 53 ciclos cuenta un fallo, no 53 |
| ciclos de stall | un pulso por ciclo perdido, con su causa | así la suma de causas tiene que dar el total |

Los 21 contadores son de 32 bits, **saturan** en vez de envolver, y levantan un bit pegajoso si alguno saturó. Un contador que envuelve en silencio produce un informe plausible y falso.

---

## 2. Cómo se validan los números

Tres mecanismos independientes, porque un contador correcto sobre un diseño mal entendido sigue dando un número falso.

**2.1 La suma de causas tiene que dar el total.** `ciclos_stall` lo cuenta un contador y las tres causas otros tres, por caminos distintos. `tb_programa.sv` compara las dos cifras en cada corrida. En las 11 da `ok`.

**2.2 Un benchmark cuyos contadores se calculan a mano.** Es el mecanismo central y responde a lo que el profesor pidió: validar que las métricas son reales.

`recorrido_cache.s` recorre 128 líneas consecutivas en ciclo, con paso de 32 bytes para tocar una línea por acceso, y repite el recorrido cuatro veces. Su conjunto de trabajo es de 4 KB, el tamaño exacto de L1-D, que tiene capacidad para 128 líneas. Entonces los contadores **solo pueden dar** estos valores:

| Contador | Exigido | De dónde sale, sin simular |
|---|---|---|
| fallos de lectura | 128 | la pasada 1 toca cada línea por primera vez: solo fallos de arranque |
| aciertos de lectura | 384 | las pasadas 2, 3 y 4 completas (128 × 3), porque el conjunto cabe justo |
| aciertos de escritura | 0 | con no-write-allocate ningún store trae su línea, así que ninguno acierta |
| fallos de escritura | 130 | los 128 de la pasada de escritura más los 2 del guardado final |

`tb_ejemplos.sv` compara los cuatro contra el hardware y también los datos (la suma 4 × (0+1+...+127) = 32512), porque un contador correcto sobre un cálculo equivocado no prueba nada. Son 13 casos y los 13 pasan. Si la caché acertara de más, el LRU estaría conservando líneas que debió expulsar; si de menos, estaría expulsando líneas que caben. Ningún otro programa de la suite detectaría ninguna de las dos.

**2.3 Los testbenches.**

| Unidad | Casos | Qué fija |
|---|---|---|
| `tb_perf_counters` | 66 | que cada contador cuente su evento y ninguno más, y que la saturación avise |
| `tb_l1_dcache` | 50 | aciertos, fallos, orden de expulsión del LRU, las tres causas de stall |
| `tb_mem_system` | 59 | que T_mem medido contra el RTL sea 53, y la regresión de la carrera de fusión |
| `tb_eviction_buffer` | 63 | FIFO, fusión, conflicto RAW, fusión sobre línea en vuelo |
| `tb_mem_clock_gen` | 14 | que cada `mem_tick` coincida con un flanco de `mem_clk` |
| `tb_ejemplos` | 41 | cinco programas completos contra sus valores esperados |

**35 unidades, 2070 casos, 0 fallos, 0 avisos de compilación.** Quedan dos avisos de `$readmemh` en `tb_dmem` y `tb_imem`, intencionales: cargan archivos más cortos que sus memorias a propósito.

---

## 3. Los benchmarks

Once programas. Los diez primeros vienen del Proyecto I y entran sin recompilarse, lo cual es parte del resultado: la jerarquía se agregó sin tocar la ISA.

| Programa | Qué ejercita | Accesos |
|---|---|---|
| `recorrido_cache.s` | **el único que excede la caché**: 128 líneas × 4 pasadas; satura el write buffer | 642 |
| `lazo_estres.s` | 900 009 ciclos, cinco slots ocupados, localidad perfecta | 300 000 |
| `suma_simple_emp.s` / `suma_vliw_emp.s` | el mismo cálculo sin y con trabajo independiente | 65 cada uno |
| `fibonacci.s` | aritmética encadenada al límite de la latencia; 47 stores, cero lecturas | 47 |
| `div32_prueba.s` | subrutina de división con enlace y retorno | 24 |
| `estadisticas.s` | seis estadísticas sobre ocho palabras, llama a `__div32` | 14 |
| `feistel.s` | la unidad criptográfica y la bóveda | 12 |
| `contar_hasta_n.s` | el lazo mínimo del manual | 11 |
| `sesion_sin_logout.s` | el cierre automático de sesión | 3 |
| `suma_10_15.s` | el caso trivial, sin accesos a memoria | 0 |

**Por qué hubo que escribir uno nuevo.** El primer barrido, con los diez del Proyecto I y seis capacidades de 512 B a 16 KB (un rango de 32 veces), **salió completamente plano**. La causa no es que la caché no funcione, es que esos programas tocan dos o tres líneas distintas cada uno, así que **todos sus fallos son de arranque**: con 241 accesos y conjuntos de trabajo de unas pocas líneas no hay un solo fallo de capacidad ni de conflicto que una caché más grande pudiera salvar.

Un barrido plano no es un resultado sobre la caché sino sobre los benchmarks: el experimento no tenía ningún programa capaz de distinguir las configuraciones. De ahí `recorrido_cache.s`, con conjunto de trabajo de 4 KB y patrón cíclico, que es el peor caso de LRU y por lo tanto el que separa las geometrías de forma limpia.

---

## 4. Línea base del VLIW

| Programa | Ciclos | Bundles | Instr. | IPC bundles | Ocupación | Vacíos | Delay desp. |
|---|---|---|---|---|---|---|---|
| `contar_hasta_n.s` | 99 | 99 | 76 | 0,768 | 0,77 | 56 % | 9 |
| `div32_prueba.s` | 4244 | 4138 | 2563 | 0,604 | 0,62 | 52 % | 198 |
| `estadisticas.s` | 864 | 811 | 567 | 0,656 | 0,70 | 50 % | 33 |
| `feistel.s` | 149 | 43 | 29 | 0,195 | 0,67 | 35 % | 2 |
| `fibonacci.s` | 382 | 382 | 381 | 0,997 | 1,00 | 62 % | 46 |
| `lazo_estres.s` | 900 117 | 900 009 | 1 400 010 | 1,555 | 1,56 | 56 % | 99 999 |
| `recorrido_cache.s` | 17 706 | 5171 | 3872 | 0,219 | 0,75 | 62 % | 638 |
| `sesion_sin_logout.s` | 34 | 34 | 25 | 0,735 | 0,74 | 44 % | 2 |
| `suma_10_15.s` | 7 | 7 | 4 | 0,571 | 0,57 | 43 % | 0 |
| `suma_simple_emp.s` | 1007 | 583 | 453 | 0,450 | 0,78 | 45 % | 63 |
| `suma_vliw_emp.s` | 677 | 253 | 267 | 0,394 | 1,06 | 22 % | 15 |

1. **Sin accesos a memoria el pipeline despacha un bundle por ciclo.** `fibonacci.s` da 0,997 (los tres ciclos que faltan son el llenado). Eso confirma que el "ideal" de la sección 6 es la cuenta de bundles, y que todo lo que sobre es costo de memoria.
2. **Los bundles están casi vacíos: entre 22 % y 62 % son NOP puros.** El profesor señaló que deberían usar su capacidad completa, y el número es que la ocupación va de 0,6 a 1,1 operaciones de las cinco ranuras. No es un defecto del procesador sino la medida de lo que el compilador NOVA tiene por ganar, y es el punto de contacto medible entre los dos cursos. El empaquetador ya se nota: `suma_vliw_emp.s` tiene 22 % de vacíos y ocupación 1,06, contra 45 % y 0,78 de la versión escalar del mismo cálculo.
3. **Los delay slots se desperdician casi siempre.** `lazo_estres.s` desperdicia 99 999 de 100 000, y cada uno aprovechado es un ciclo.

---

## 5. La caché L1-D

Geometría: 4 KB, 2 vías, 64 conjuntos, líneas de 32 B, write-through, no-write-allocate, LRU.

| Programa | Accesos | ld hit | ld miss | st miss | Aciertos | AMAT | Stall: miss / wb / RAW |
|---|---|---|---|---|---|---|---|
| `lazo_estres.s` | 300 000 | 99 999 | 1 | 1 | **100,0 %** | 1,00 | 107 / 0 / **1** |
| `suma_simple_emp.s` | 65 | 56 | 8 | 1 | 86,2 % | 8,34 | 424 / 0 / 0 |
| `suma_vliw_emp.s` | 65 | 56 | 8 | 1 | 86,2 % | 8,34 | 424 / 0 / 0 |
| `feistel.s` | 12 | 8 | 2 | 2 | 66,7 % | 18,67 | 106 / 0 / 0 |
| `recorrido_cache.s` | 642 | 384 | 128 | 130 | 59,8 % | 24,55 | 7500 / **5035** / 0 |
| `estadisticas.s` | 14 | 7 | 1 | 6 | 50,0 % | 27,50 | 53 / 0 / 0 |
| `div32_prueba.s` | 24 | 10 | 2 | 12 | 41,7 % | 31,92 | 106 / 0 / 0 |
| `contar_hasta_n.s` | 11 | 0 | 0 | 11 | 0,0 % | 1,00 | 0 / 0 / 0 |
| `fibonacci.s` | 47 | 0 | 0 | 47 | 0,0 % | 1,00 | 0 / 0 / 0 |
| `sesion_sin_logout.s` | 3 | 0 | 0 | 3 | 0,0 % | 1,00 | 0 / 0 / 0 |

Dos lecturas que conviene hacer explícitas:

**El AMAT usa la penalidad medida, no T_mem supuesto.** Que las dos se parezcan es una comprobación; que no se parezcan es un hallazgo. En `recorrido_cache.s` no se parecen: 58,6 ciclos medidos contra 53 de T_mem. Los 5,6 de diferencia son arbitraje, porque el controlador está drenando el write buffer cuando llega la petición de lectura. Es un costo real de write-through que solo aparece bajo presión del buffer.

**Las tres tasas de 0,0 % no son un defecto.** `fibonacci.s`, `contar_hasta_n.s` y `sesion_sin_logout.s` solo escriben, nunca leen, y con no-write-allocate ningún store puede acertar, así que 0 % es el único valor posible. Su AMAT de 1,00 dice la verdad: ninguno pierde un solo ciclo, porque los stores no esperan.

La columna de stalls es la que justifica dos decisiones de diseño (sección 8).

---

## 6. Contra la línea base sin caché

La Iteración 2 proyectó dos cotas antes de que la caché existiera: la **optimista** (solo los loads pagan los 53 ciclos) y la **pesimista** (todo acceso los paga). Compararse contra una proyección hecha antes es más informativo que contra un ideal, porque la proyección se puede equivocar y entonces se aprende algo.

| Programa | Ideal | Medido | Sobrec. | Optimista | Pesimista | Gana |
|---|---|---|---|---|---|---|
| `contar_hasta_n.s` | 99 | 99 | 1,00× | 99 | 671 | 6,8× |
| `div32_prueba.s` | 4138 | 4244 | 1,03× | 4762 | 5386 | 1,3× |
| `estadisticas.s` | 811 | 864 | 1,07× | 1227 | 1539 | 1,8× |
| `feistel.s` | 43 | 149 | 3,47× | 563 | 667 | 4,5× |
| `fibonacci.s` | 382 | 382 | 1,00× | 382 | 2826 | 7,4× |
| `lazo_estres.s` | 900 009 | 900 117 | 1,00× | 6 100 009 | 16 500 009 | 18,3× |
| `recorrido_cache.s` | 5171 | 17 706 | 3,42× | 31 795 | 38 555 | 2,2× |
| `sesion_sin_logout.s` | 34 | 34 | 1,00× | 34 | 190 | 5,6× |
| `suma_10_15.s` | 7 | 7 | 1,00× | 7 | 7 | 1,0× |
| `suma_simple_emp.s` | 583 | 1007 | 1,73× | 3911 | 3963 | 3,9× |
| `suma_vliw_emp.s` | 253 | 677 | 2,68× | 3581 | 3633 | 5,4× |
| **total** | **911 530** | **925 286** | **1,02×** | **6 146 370** | **16 557 446** | **17,9×** |

**Los 11 programas quedaron por debajo de la cota optimista**, que era el mejor caso posible sin jerarquía. Los cuatro que la igualan son precisamente los que no leen memoria, y ahí la cota coincide con el ideal por construcción. La sobrecarga total sobre el ideal es de **1,02×**: con memoria de 53 ciclos el sistema corre a un 2 % del costo de una memoria imaginaria de un ciclo.

### El hallazgo que vale llevar a la defensa

La Iteración 2 predijo que la latencia de memoria comprime la ventaja del VLIW, y la Iteración 3 lo confirmó:

| | Escalar | VLIW | Ganancia |
|---|---|---|---|
| Ideal (memoria de un ciclo) | 583 bundles | 253 bundles | **2,30×** |
| Medido (memoria de 53 ciclos) | 1007 ciclos | 677 ciclos | **1,49×** |

Se pierde el 35 % de la ventaja, porque los 424 ciclos de stall por fallo de lectura son **los mismos en las dos versiones**: empaquetar instrucciones reduce los bundles, no los accesos a memoria. Esperar la memoria no se paraleliza.

Es un argumento directo para el proyecto de compiladores: el reordenamiento y el loop unrolling ganan sobre el conteo de bundles, que es el numerador, mientras el denominador (los fallos de caché) no se mueve. La optimización que de verdad compone con el VLIW es la que mejora la **localidad**.

Esta predicción cumplida obligó a bajar el umbral de `tb_vliw` de 2,0× a 1,3×: no es una prueba relajada para que pasara, es un resultado del proyecto que la prueba ahora registra.

---

## 7. Comparación entre configuraciones

Seis capacidades de 512 B a 16 KB (un rango de 32 veces), a 2 vías y líneas de 32 B, sobre nueve programas y 883 accesos iguales en las seis.

| Configuración | Fallos ld | Aciertos | Penalidad | AMAT | Ciclos | Stalls |
|---|---|---|---|---|---|---|
| 512 B / 1 KB / 2 KB, 2 vías | 533 | 15,52 % | 54,3 | 33,80 | 45 514 | 34 000 |
| **4 KB / 8 KB / 16 KB, 2 vías** | 149 | **59,00 %** | 57,8 | **10,75** | **25 162** | 13 648 |

Las seis configuraciones dan exactamente dos resultados distintos, y las tres de cada grupo son idénticas entre sí. Las tasas se calculan agregando los contadores y dividiendo después, no promediando las tasas de cada programa: promediar le daría el mismo peso a un programa de diez accesos que a uno de diez mil.

**Dónde está el codo.**

| Paso | Aciertos | Ciclos ahorrados |
|---|---|---|
| 512 B a 1 KB, y 1 KB a 2 KB | +0,00 pp | 0 (0,00 %) |
| **2 KB a 4 KB** | **+43,49 pp** | **20 352 (44,72 %)** |
| 4 KB a 8 KB, y 8 KB a 16 KB | +0,00 pp | 0 (0,00 %) |

**Quién responde al tamaño.** Un solo programa, y es el único que podía:

| Programa | 512 B a 2 KB | 4 KB a 16 KB |
|---|---|---|
| `recorrido_cache.s` | 0,00 % | **59,81 %** |
| `suma_simple_emp.s`, `suma_vliw_emp.s` | 86,15 % | 86,15 % |
| `feistel.s` | 66,67 % | 66,67 % |
| `estadisticas.s` | 50,00 % | 50,00 % |
| `div32_prueba.s` | 41,67 % | 41,67 % |
| `contar_hasta_n.s`, `fibonacci.s`, `sesion_sin_logout.s` | 0,00 % | 0,00 % |

**El codo cae exactamente en 4 KB, la geometría que exige el enunciado.** Duplicar de 2 KB a 4 KB ahorra 44,72 % de los ciclos; duplicar de 4 KB a 16 KB, cuatro veces más silicio, no ahorra ninguno.

Hay que ser honesto sobre por qué cae ahí: `recorrido_cache.s` se escribió con conjunto de trabajo de 4 KB a propósito, para que el barrido midiera el punto de diseño y no un tamaño cualquiera. El resultado no es que 4 KB sea mágicamente óptimo, sino tres cosas más útiles. Primero, **la caché se comporta como la teoría predice**: un recorrido cíclico sobre un conjunto que no cabe da 0 % de aciertos y no una degradación gradual, porque al volver a la primera línea ya fue expulsada, y la medición reproduce ese peor caso de LRU sin valores intermedios. Segundo, **el codo cae donde el conjunto deja de caber y en ningún otro lugar**: 128 líneas entran en 4 KB (64 conjuntos × 2 vías) y no en 2 KB (32 × 2), así que el salto confirma que la capacidad efectiva es la que dice la geometría. Tercero, **la planicie de los otros ocho también es un resultado**: sus fallos son irreducibles porque son de arranque, y el gasto de pasar de 4 KB a 16 KB no se recupera con este software.

### Qué no se barrió

**La asociatividad no se varió.** `l1_dcache.sv` implementa exactamente dos vías: compara dos etiquetas con nombre propio y guarda el LRU como un bit, que es LRU exacto solo con dos vías. Pedirle otra aborta la elaboración:

```
FATAL: ../cpu/l1_dcache.sv:154: l1_dcache.sv implementa 2 vias, se pidieron 1
```

Ese guardia se agregó al descubrir el problema de la peor forma: un barrido con `L1D_WAYS=1` no falló, **se colgó 2,5 millones de ciclos**, porque el módulo indexaba una vía que no existe y leía `x`. Que ahora aborte en el tiempo 0 con el motivo es la diferencia entre una limitación documentada y una trampa. La generalización a N vías llega con la Iteración 4, donde la L2 es de 4 vías y hace falta de todos modos.

**`lazo_estres.s` quedó fuera:** 900 000 ciclos por corrida y seis configuraciones pasarían el barrido de minutos a horas, y su patrón (100 % de aciertos en cualquier geometría) no distingue nada.

---

## 8. Justificación de las decisiones a partir de lo medido

El razonamiento de cada política está en [jerarquia-memoria.md](jerarquia-memoria.md). Aquí está lo que la medición agregó, que es la parte que no se podía saber antes de construirlo.

| Decisión | Lo que la medición aportó |
|---|---|
| **Write-through** | 10 de 11 programas pierden **cero ciclos** por buffer lleno. El costo teórico resulta invisible en carga real y solo aparece cuando un programa escrito a propósito lo fuerza: 5035 de 17 706 ciclos. La decisión se sostiene, con su límite cuantificado. |
| **No-write-allocate** | Su peor caso está medido: los 128 fallos de escritura de `recorrido_cache.s` no cargan ninguna línea, así que la primera pasada de lectura paga otros 128 fallos de arranque. Sigue costando menos que traer 128 líneas de 53 ciclos para escribirlas hacia abajo igual. |
| **LRU exacto, un bit** | Los 384 aciertos exactos solo salen si el LRU conserva precisamente las líneas que caben. A dos vías un bit por conjunto da LRU exacto, y la medición confirma que basta. |
| **Stall para el RAW** | **Un (1) ciclo** perdido en los 11 programas. Eso es todo lo que el store-to-load forwarding habría ahorrado, a cambio de un multiplexor por byte con prioridad por antigüedad en el camino crítico del acierto de un ciclo. Convierte la decisión de un juicio en una cuenta. |
| **8 entradas en el write buffer** | Solo el programa diseñado para saturarlo pierde ciclos. Lo que baja la presión no es la profundidad sino la fusión: ninguna profundidad salva 128 líneas distintas seguidas, y cualquiera razonable alcanza para un patrón con localidad. |
| **8 entradas en el eviction buffer** | **Sin medición todavía**, porque la L2 que lo alimentará no existe. Dimensionado por razonamiento y sujeto a revisión en la Iteración 4; el contador para verlo ya está puesto. |
| **Geometría 4 KB / 2 vías** | El barrido dice que es el codo: 44,72 % de ciclos ahorrados al llegar a 4 KB y 0 % al pasarse. La geometría que exige el enunciado es defendible con el barrido, no solo por obediencia. |

---

## 9. Limitaciones del análisis

1. **La asociatividad no se comparó.** El barrido mide capacidad a asociatividad fija; comparar asociatividades requiere generalizar la caché a N vías, trabajo de la Iteración 4.
2. **No hay L2.** Todo lo medido es L1-D contra memoria principal. Cuando la L2 exista, las penalidades de fallo de L1 bajarán de 53 a 8 ciclos donde la L2 acierte, y los AMAT de aquí quedarán como la cota superior contra la cual medirla.
3. **El conjunto está dominado por dos programas.** `lazo_estres.s` aporta 300 000 accesos y `recorrido_cache.s` 642; los otros nueve 241 entre todos. Por eso se reportan tablas por programa y no un número agregado.
4. **`recorrido_cache.s` es un microbenchmark, no carga real.** Sirve para separar geometrías y validar contadores contra aritmética; no para estimar el rendimiento de un programa de verdad. Y las tasas de los otros ocho son casi enteramente función de los fallos de arranque, así que dicen poco sobre la caché y bastante sobre los programas. Mejorarlo pide benchmarks con localidad real, candidato natural para la Iteración 5 con los programas que genere NOVA.
5. **La frecuencia es un modelo, no una medición física.** Los 53 ciclos salen del modelo de 25 MHz con ráfaga de 8 palabras. No hay síntesis ni medición en silicio, así que el número es consistente dentro del proyecto pero no es una latencia de DRAM real.

---

## 10. Cómo reproducir

```bash
cd src/build
make clean && make all     # 35 unidades, 2070 casos, 0 fallos esperados
make ejemplos              # 41 casos, contadores contra aritmética
make metricas              # las tablas de las secciones 4, 5 y 6
make correr PROG=recorrido_cache.s MOSTRAR=0x100 PALABRAS=2

cd ..
./tools/barrido_cache.sh                    # el barrido de la sección 7
python3 tools/tabla_barrido.py barrido      # su tabla
```
