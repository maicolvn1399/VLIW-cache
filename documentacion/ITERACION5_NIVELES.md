# Iteración 5: los niveles de optimización contra la jerarquía de memoria

Lo que pide la sección 7.1.5 del enunciado: correr los benchmarks bajo distintos
niveles de optimización del compilador y correlacionar tasas de acierto, IPC,
stalls y AMAT con las decisiones de diseño. Es la parte que
`ARQUITECTURA/docs/analisis-rendimiento.md` §11.5 dejó pendiente «a la espera
del equipo de CE1108».

**Cómo se midió.** 39 programas × 3 niveles sobre el RTL con la jerarquía
completa (L1-D 4 KB 2 vías write-through, L2 write-back, memoria principal).
Los números salen de los contadores de hardware de `perf_counters.sv`, leídos
del DUT por nombre jerárquico:

```bash
make medir-niveles                    # corre y arma las tablas
make tabla-niveles METRICAS_DIR=dir   # rehace las tablas de una medición guardada
```

Se recogen dentro de `test/run_equivalencia.sh`, que es la batería que ya
comprueba que los tres niveles **dan el mismo resultado**. Medir en el mismo
paso que se verifica es deliberado: garantiza que la tabla de rendimiento y la
prueba de corrección hablan de los mismos binarios. La corrida que produjo
estas cifras reportó `equivalencia RTL: 117 correctas, 0 fallidas`.

Las cifras agregadas son **sumas sobre el corpus, no promedios de porcentajes**.
Promediar tasas le daría el mismo peso a un programa de 119 ciclos que a
`matriz_1000`, que tiene 352 737.

---

## 1. Lo que cambia cada nivel

| | `-O0` | `-O1` | `-O2` | `-O2` contra `-O0` |
|---|---|---|---|---|
| Ciclos ejecutados | 546 111 | 523 935 | 380 473 | **−30.3 %** |
| Bundles despachados | 536 920 | 515 022 | 373 356 | −30.5 % |
| Operaciones (no-NOP) | 253 261 | 241 110 | 182 659 | −27.9 % |
| **Accesos a memoria del programa** | **120 029** | **111 943** | **45 697** | **−61.9 %** |
| Ciclos de stall | 9 191 | 8 913 | 7 117 | −22.6 % |
| … por fallo de caché | 3 796 | 3 824 | 3 240 | −14.6 % |
| … por conflicto RAW | 5 395 | 5 089 | 3 877 | −28.1 % |
| Accesos a memoria principal | 532 | 528 | 479 | −10.0 % |

El dato que salta: **los accesos a memoria caen al doble de velocidad que los
ciclos** (−61.9 % contra −30.3 %). Eso ya dice dónde está la acción.

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| IPC | 0.464 | 0.460 | 0.480 |
| Ocupación (operaciones / bundle, de 5) | 0.472 | 0.468 | 0.489 |
| Bundles totalmente vacíos | 54.4 % | 54.5 % | 57.1 % |
| **Accesos a memoria sobre las operaciones** | **47.4 %** | 46.4 % | **25.0 %** |
| Tasa de aciertos L1-D | 98.42 % | 98.32 % | **96.35 %** |
| Tasa de aciertos L2 | 99.34 % | 99.31 % | 97.08 % |
| AMAT de lectura (ciclos) | 1.050 | 1.055 | 1.089 |
| Utilización del bus de memoria | 5.07 % | 5.24 % | 6.55 % |

---

## 2. Dos afirmaciones de la §11.5 que ya no se sostienen

El documento de arquitectura dice, sobre la salida de NOVA:

> «Ocupación de 0,48 de 5 ranuras, y **ni un solo bundle con dos operaciones**.
> Usa S0, S2 y S4; **nunca S1 ni S3**.»
> «**44 %** de las instrucciones que emite son accesos a memoria, porque **no
> asigna registros** y baja cada temporal al marco de pila.»

Las dos se midieron contra el NOVA de la iteración 3. Hoy:

| | Lo que decía | Medido ahora |
|---|---|---|
| Ranura S1 (segunda ALU) | nunca se usa | **5 609 operaciones en `-O0`, 5 822 en `-O2`** |
| Ranura S3 (cripto) | nunca se usa | 20 operaciones (solo `cifrado`/`descifrado`) |
| Accesos sobre instrucciones | 44 % | **47.4 % en `-O0`, 25.0 % en `-O2`** |
| Asignación de registros | no existe | linear scan con derrame, desde la iteración 4 |

El 44 % original era correcto y sigue siendo del orden del `-O0` de hoy
(47.4 %). Lo que cambió es que **ya existe un nivel donde esa cifra se parte por
la mitad**. S3 sigue casi sin usarse, pero por una razón legítima: solo dos
programas del corpus usan la unidad cripto.

---

## 3. La pregunta abierta, contestada

La §11.5 formula la pregunta así:

> «La medición que hay que hacer en la Iteración 5 es si la asignación de
> registros reduce más ciclos que el empaquetado, y la respuesta esperable,
> dada la sección 6 de este documento, es que sí.»

**La respuesta es sí, y la separación de efectos la cuantifica: 91.5 % contra
8.5 %.**

### 3.1 `-O2` no borra trabajo: lo cambia de sitio

| | `-O0` | `-O2` | |
|---|---|---|---|
| Operaciones de memoria | 120 029 | 45 697 | **−74 332** |
| Operaciones que no son de memoria | 133 232 | 136 962 | **+3 730** |
| Total | 253 261 | 182 659 | −70 602 |

**Las operaciones de memoria que desaparecen (74 332) son más que la reducción
neta (70 602)**, porque las operaciones que no son de memoria *aumentan* en
3 730. No es una contradicción: es exactamente lo que hace la asignación de
registros. Donde antes había `store` al marco y `load` de vuelta, ahora hay un
registro vivo y, de vez en cuando, una operación de ALU extra para moverlo.
**Se cambia tráfico de memoria por trabajo de registro.**

### 3.2 De dónde salen los bundles que se ahorran

El procesador despacha un bundle por ciclo salvo stall, y los stalls son el
1.7 % de los ciclos. Así que ahorrar ciclos es, casi exactamente, ahorrar
bundles. Y `bundles = operaciones / ocupación`, así que solo hay dos maneras:
emitir menos operaciones, o meter más en cada bundle.

Si se toman las operaciones de `-O2` y se empaquetan con la ocupación de `-O0`,
salen **387 242** bundles. Los reales son **373 356**:

| | Bundles | Del total ahorrado |
|---|---|---|
| Por emitir menos operaciones | 149 678 | **91.5 %** |
| Por empaquetar mejor | 13 886 | **8.5 %** |
| Total | 163 564 | 100 % |

**Nueve de cada diez ciclos que `-O2` ahorra los ahorra por no ejecutar la
operación, no por ejecutarla mejor.** La ocupación apenas se mueve: 0.472 →
0.489 de 5 ranuras posibles. El calendarizador funciona, pero lo que mueve la
aguja en este corpus es quitar accesos a memoria.

### 3.3 Los stores son donde estaba el tráfico

| | `-O0` | `-O2` | |
|---|---|---|---|
| Accesos de lectura | 75 517 | 36 404 | −52.0 % |
| **Accesos de escritura** | **44 512** | **9 293** | **−79.1 %** |

Las escrituras caen mucho más que las lecturas, y es la firma del derrame: un
temporal en pila se escribe una vez y se relee varias, pero mantenerlo en
registro elimina **la escritura entera y todas sus recargas**. El marco de pila
era, sobre todo, tráfico de escritura.

---

## 4. El resultado contraintuitivo: la tasa de aciertos empeora y el costo baja

| | `-O0` | `-O2` |
|---|---|---|
| Tasa de aciertos L1-D | 98.42 % | **96.35 %** |
| Tasa de fallos de escritura | 3.67 % | **15.46 %** |
| AMAT de lectura | 1.050 | **1.089** |

Visto así parece que optimizar **empeora** el comportamiento de caché. No es
eso, y la cuenta absoluta lo demuestra:

| | `-O0` | `-O2` | |
|---|---|---|---|
| Aciertos L1 | 118 134 | 44 027 | −62.7 % |
| **Fallos L1 (absolutos)** | **1 895** | **1 670** | **−11.9 %** |
| **Ciclos de stall por memoria** | **3 796** | **3 240** | **−14.6 %** |

De los **74 332 accesos que desaparecen, 74 107 — el 99.70 % — eran
aciertos**.

Ahí está todo. La asignación de registros se lleva justamente el tráfico fácil:
el marco de pila, unas pocas palabras que se tocan una y otra vez y que por eso
están siempre en caché. Lo que queda es el tráfico que no se puede evitar —los
arreglos de verdad—, que tiene más fallos obligatorios. **La tasa empeora
porque el denominador perdió a sus miembros más fáciles, no porque la caché
funcione peor.** En términos absolutos hay menos fallos y menos ciclos perdidos.

> Esto es una trampa para la defensa oral. Si alguien señala «el hit rate baja
> con `-O2`» y uno no tiene la cuenta absoluta a mano, parece un defecto. La
> respuesta de una línea es: **optimizar no degradó la caché, le quitó los
> aciertos gratis.**

### 4.1 Por qué los fallos de escritura se cuadruplican

De 3.67 % a 15.46 %, y la causa es la decisión **D2 de la arquitectura:
no-write-allocate**. Un fallo de escritura no instala la línea. En `-O0`, las
escrituras al marco acertaban porque algún `load` del marco ya había traído esa
línea; al desaparecer esas lecturas, lo que queda son escrituras a arreglos de
salida cuya línea nadie trajo antes. **La tasa de fallos de escritura sube
porque desapareció el tráfico de lectura que le estaba poblando la caché.**

---

## 5. El AMAT hay que calcularlo solo sobre las lecturas

Al medir, el AMAT sobre *todos* los accesos daba **2.00 ciclos de stall por
fallo**. Eso es imposible: un acierto de L2 ya cuesta 8.

La cifra imposible es lo que delata el error. Con L1-D **write-through y
no-write-allocate** (decisiones D1 y D2), **un fallo de escritura no detiene el
pipeline**: el store se publica en el write buffer y la ejecución continúa.
Meter los stores en el denominador reparte entre ellos un costo que no
causaron.

Separados:

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| AMAT sobre todos los accesos (engañoso) | 1.032 | 1.034 | 1.071 |
| **AMAT de lectura** | **1.050** | **1.055** | **1.089** |
| Penalidad por fallo de lectura | 14.5 | 14.8 | 13.9 |

**La penalidad medida valida el modelo.** El 8 % de los fallos de L1 se le
escapan también a la L2, así que lo teórico es
`0.92 × 8 + 0.08 × 53 = 11.6` ciclos. Lo medido son 14.5. Los ~3 ciclos de
diferencia son arbitraje del bus y encolado, que el modelo analítico no
incluye. Estar dentro de 3 ciclos sobre 11.6 por dos caminos independientes es
una comprobación cruzada, no una coincidencia.

---

## 6. Ocupación por ranura: dónde queda el margen

| Ranura | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| S0 ALU-0 | 92 898 (36.7 %) | 89 387 (37.1 %) | 96 584 (52.9 %) |
| S1 ALU-1 | 5 609 (2.2 %) | 5 072 (2.1 %) | 5 822 (3.2 %) |
| S2 LSU | 120 029 (47.4 %) | 111 943 (46.4 %) | **45 697 (25.0 %)** |
| S3 CRP | 20 (0.0 %) | 20 (0.0 %) | 20 (0.0 %) |
| S4 BRU | 34 705 (13.7 %) | 34 688 (14.4 %) | 34 536 (18.9 %) |

El perfil de la carga **cambia de forma**, no solo de tamaño. En `-O0` la ranura
más usada es la de memoria (47.4 %); en `-O2` es la ALU-0 (52.9 %). El
compilador convirtió un programa limitado por memoria en uno limitado por ALU.

Y ahí está el margen que queda: **S1, la segunda ALU, recibe el 3.2 % del
trabajo.** Con S0 al 52.9 %, repartir entre las dos ALU es la optimización con
más techo que le queda al compilador. La ocupación global sigue en 0.489 de 5:
**el 90 % de las ranuras del procesador viajan vacías.**

---

## 7. Las invalidaciones, confirmadas con programas de verdad

La §11.4 del análisis de arquitectura reporta **cero invalidaciones hacia atrás**
en los tres patrones sintéticos, y argumenta que es estructural: la L2 tiene 512
líneas y la L1 128, así que la L2 casi nunca expulsa algo que la L1 conserve.

Medido sobre los 39 programas de NOVA, en los tres niveles:

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| Invalidaciones ejecutadas | **0** | **0** | **0** |

**117 corridas de programas reales, cero invalidaciones.** Esto extiende el
hallazgo de la §11.4 de tres microbenchmarks a un corpus de verdad, y refuerza
su conclusión: el costo de la política inclusiva es nulo porque la garantía que
mantiene no se ejerce nunca con esta relación de tamaños.

---

## 8. Los programas, uno por uno

| Programa | ciclos `-O0` | ciclos `-O2` | | accesos `-O0` | `-O2` |
|---|---|---|---|---|---|
| `cifrado` | 371 | 209 | −43.7 % | 49 | 12 |
| `descifrado` | 371 | 209 | −43.7 % | 49 | 12 |
| `multiplicar_matrices` | 4 555 | 2 618 | −42.5 % | 1 041 | 332 |
| `bits_y_hex` | 388 | 237 | −38.9 % | 55 | 19 |
| `matriz_transpuesta` | 1 926 | 1 184 | −38.5 % | 432 | 141 |
| `t2_ciclo_muerto` | 747 | 466 | −37.6 % | 177 | 59 |
| `matriz_1000` | 352 737 | 225 417 | −36.1 % | 81 056 | 23 432 |
| `matriz_for` | 2 891 | 1 982 | −31.4 % | 640 | 264 |
| `traza` | 634 | 439 | −30.8 % | 111 | 62 |
| `producto_punto` | 1 671 | 1 167 | −30.2 % | 382 | 168 |
| `cola` | 24 211 | 17 216 | −28.9 % | 5 011 | 3 009 |
| `busqueda_matriz` | 1 238 | 928 | −25.0 % | 248 | 123 |

La columna de accesos es la que explica la de ciclos: **donde los accesos caen a
un tercio, los ciclos caen un 40 %**.

### Los que no mejoran

| Programa | ciclos `-O0` | ciclos `-O2` | |
|---|---|---|---|
| `dce_ciclo_potencialmente_infinito` | 119 | 125 | **+5.0 %** |
| `saludo` | 450 | 450 | sin cambio |

Dos de 39, y conviene decirlos antes de que los encuentre el profesor.
`saludo` no tiene lazos ni código muerto: no hay nada que optimizar.
`dce_ciclo_potencialmente_infinito` **empeora 6 ciclos**: el compilador no puede
probar que el lazo termina, así que no lo desenrolla, y queda solo el costo de
preparar la asignación de registros. Seis ciclos sobre ciento diecinueve es
ruido, pero es honesto decir que existe: **una optimización puede costar más de
lo que ahorra en programas diminutos**, y el compilador no tiene hoy un modelo
de costo que se lo diga de antemano.

---

## 9. Limitaciones de esta medición

Vale más declararlas que defenderlas.

1. **El corpus está dominado por un programa.** `matriz_1000` aporta 352 737 de
   los 546 111 ciclos de `-O0`, el 65 %. Las sumas globales son, en buena
   medida, ese programa. Por eso está la tabla por programa de la sección 8.
2. **La caché casi no se ejerce.** Los stalls son el 1.7 % de los ciclos y el
   AMAT de lectura es 1.05. Este corpus tiene conjuntos de trabajo chicos y
   buena localidad, así que mide bien al compilador y mal a la jerarquía. Los
   tres patrones de la §11 del análisis de arquitectura siguen siendo la
   medición válida de la caché.
3. **No se aisló cada transformación.** `-O2` enciende desenrollado,
   reordenamiento y asignación de registros a la vez. La separación de la
   sección 3.2 reparte el efecto entre «menos operaciones» y «mejor
   empaquetado», que es una línea de corte real, pero no dice cuánto del
   «menos operaciones» es desenrollado y cuánto es asignación de registros.
   Que los accesos de escritura caigan un 79 % apunta fuerte a la asignación
   de registros, porque el desenrollado no elimina accesos, solo saltos y
   actualizaciones de contador. Medirlo de verdad pide banderas por
   transformación.
4. **`-O1` es casi `-O0`.** −4.1 % en ciclos, porque `-O1` solo hace
   eliminación de código muerto. Es el resultado esperado y no un problema,
   pero significa que el salto real es `-O1` → `-O2`.
