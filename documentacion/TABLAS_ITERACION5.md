# Iteracion 5: los niveles de optimizacion contra la jerarquia

39 programas, medidos sobre el RTL con la jerarquia de cache completa.

## Lo que cambia cada nivel, sobre todo el corpus

| | -O0 | -O1 | -O2 | -O2 contra -O0 |
|---|---|---|---|---|
| Ciclos ejecutados | 546 111 | 523 935 | 380 473 | -30.3 % |
| Bundles despachados | 536 920 | 515 022 | 373 356 | -30.5 % |
| Operaciones (no-NOP) | 253 261 | 241 110 | 182 659 | -27.9 % |
| Accesos a memoria del programa | 120 029 | 111 943 | 45 697 | -61.9 % |
| Ciclos de stall | 9 191 | 8 913 | 7 117 | -22.6 % |
|   por fallo de cache | 3 796 | 3 824 | 3 240 | -14.6 % |
|   por conflicto RAW | 5 395 | 5 089 | 3 877 | -28.1 % |
| Accesos a memoria principal | 532 | 528 | 479 | -10.0 % |

## Las razones

| | -O0 | -O1 | -O2 |
|---|---|---|---|
| IPC (operaciones / ciclo) | 0.464 | 0.460 | 0.480 |
| Ocupacion (operaciones / bundle, de 5) | 0.472 | 0.468 | 0.489 |
| Bundles totalmente vacios | 54.4 % | 54.5 % | 57.1 % |
| Accesos a memoria sobre las operaciones | 47.4 % | 46.4 % | 25.0 % |
| Tasa de aciertos L1-D | 98.42 % | 98.32 % | 96.35 % |
| Tasa de aciertos L2 | 99.34 % | 99.31 % | 97.08 % |
| Tasa de FALLOS de lectura | 0.35 % | 0.37 % | 0.64 % |
| Tasa de FALLOS de escritura | 3.67 % | 3.83 % | 15.46 % |
| AMAT de lectura (ciclos) | 1.050 | 1.055 | 1.089 |
|   penalidad por fallo de lectura | 14.5 | 14.8 | 13.9 |
| AMAT sobre todos los accesos | 1.032 | 1.034 | 1.071 |
| Stall por operacion ejecutada | 0.036 | 0.037 | 0.039 |
| Utilizacion del bus de memoria | 5.07 % | 5.24 % | 6.55 % |

> El AMAT que vale es el de lectura. L1-D es write-through con
> no-write-allocate, asi que un fallo de escritura no detiene el
> pipeline: el store se publica en el write buffer y la ejecucion
> sigue. Repartir el costo entre todos los accesos da 2,0 ciclos
> por fallo, menos que un acierto de L2, que es imposible.

## Registros contra empaquetado: de donde sale la mejora

**Que operaciones cambian.**

| | -O0 | -O2 | |
|---|---|---|---|
| Operaciones de memoria | 120029 | 45697 | **-74332** |
| Operaciones que no son de memoria | 133232 | 136962 | **+3730** |
| Total | 253261 | 182659 | -70602 |

**De donde salen los bundles que se ahorran.** Si se toman las
operaciones de `-O2` y se empaquetan con la ocupacion de `-O0`,
salen 387242 bundles. La diferencia contra los 373356 reales es lo que
aporto empaquetar mejor; el resto es haber emitido menos.

| | Bundles | Del total |
|---|---|---|
| Por emitir menos operaciones | 149678 | **91.5 %** |
| Por empaquetar mejor | 13886 | **8.5 %** |
| Total ahorrado | 163564 | 100 % |

**Por que la tasa de aciertos empeora mientras el costo baja.**
De los 74332 accesos que desaparecen, **74107 (99.70 %) eran
aciertos**. La asignacion de registros se lleva justamente el
trafico facil --- el marco de pila, que siempre esta en cache ---
y deja el que no se puede evitar.

| | -O0 | -O2 | |
|---|---|---|---|
| Aciertos L1 | 118134 | 44027 | -62.7 % |
| Fallos L1 (absolutos) | 1895 | 1670 | -11.9 % |
| Ciclos de stall por memoria | 3796 | 3240 | -14.6 % |

## Ocupacion por ranura

Cuantas operaciones fueron a cada ranura. S0 es la unica ALU que
escribe banderas, S1 la segunda ALU, S2 la unidad de memoria, S3
la cripto y S4 la de saltos.

| Ranura | -O0 | -O1 | -O2 |
|---|---|---|---|
| S0 ALU-0 | 92 898 (36.7 %) | 89 387 (37.1 %) | 96 584 (52.9 %) |
| S1 ALU-1 | 5 609 (2.2 %) | 5 072 (2.1 %) | 5 822 (3.2 %) |
| S2 LSU | 120 029 (47.4 %) | 111 943 (46.4 %) | 45 697 (25.0 %) |
| S3 CRP | 20 (0.0 %) | 20 (0.0 %) | 20 (0.0 %) |
| S4 BRU | 34 705 (13.7 %) | 34 688 (14.4 %) | 34 536 (18.9 %) |

## Los programas que mas cambian

| Programa | ciclos -O0 | ciclos -O2 | | accesos -O0 | -O2 |
|---|---|---|---|---|---|
| `test_ejecucion_cifrado` | 371 | 209 | -43.7 % | 49 | 12 |
| `test_ejecucion_descifrado` | 371 | 209 | -43.7 % | 49 | 12 |
| `test_ejecucion_multiplicar_matrices` | 4555 | 2618 | -42.5 % | 1041 | 332 |
| `test_ejemplos_bits_y_hex` | 388 | 237 | -38.9 % | 55 | 19 |
| `test_ejecucion_matriz_transpuesta` | 1926 | 1184 | -38.5 % | 432 | 141 |
| `test_ejecucion_t2_ciclo_muerto` | 747 | 466 | -37.6 % | 177 | 59 |
| `test_ejecucion_matriz_1000` | 352737 | 225417 | -36.1 % | 81056 | 23432 |
| `test_ejecucion_matriz_for` | 2891 | 1982 | -31.4 % | 640 | 264 |
| `test_ejemplos_traza` | 634 | 439 | -30.8 % | 111 | 62 |
| `test_ejecucion_producto_punto` | 1671 | 1167 | -30.2 % | 382 | 168 |
| `test_ejecucion_cola` | 24211 | 17216 | -28.9 % | 5011 | 3009 |
| `test_ejemplos_busqueda_matriz` | 1238 | 928 | -25.0 % | 248 | 123 |

**Los que no mejoran, todos, sin umbral:**

| Programa | ciclos -O0 | ciclos -O2 | |
|---|---|---|---|
| `test_optimizaciones_dce_ciclo_potencialmente_infinito` | 119 | 125 | **+5.0 %** |
| `test_ejemplos_saludo` | 450 | 450 | sin cambio |

