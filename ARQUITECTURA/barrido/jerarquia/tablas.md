# Resultados del barrido de la jerarquia

Generado por `tools/tabla_analisis.py` a partir de los informes de `barrido/jerarquia/`. No se edita a mano: se regenera con `make analisis`.

## 1. Con L2 contra sin L2

L1 de 4 KB en las dos. Aceleracion = ciclos sin L2 / ciclos con L2.

| programa | ciclos con L2 | ciclos sin L2 | aceleracion | AMAT con L2 | AMAT sin L2 | aciertos L1 | aciertos L2 (lect.) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `patron_secuencial` | 16 266 | 15 114 | 0.93x | 8.88 | 7.75 | 87.50 % | 0.00 % |
| `patron_stride` | 72 714 | 63 498 | 0.87x | 64.00 | 55.00 | 0.00 % | 0.00 % |
| `patron_aleatorio` | 79 562 | 84 019 | 1.06x | 43.69 | 48.04 | 12.89 % | 25.45 % |
| `patron_reuso` | 22 301 | 31 773 | 1.42x | 36.50 | 55.00 | 0.00 % | 50.00 % |
| `recorrido_cache` | 13 312 | 17 859 | 1.34x | 3.88 | 15.95 | 75.00 % | 100.00 % |
| `contar_hasta_n` | 99 | 99 | 1.00x | 1.00 | 1.00 | 0.00 % | 0.00 % |
| `div32_prueba` | 4 272 | 4 299 | 1.01x | 12.17 | 14.42 | 83.33 % | 0.00 % |
| `estadisticas` | 874 | 865 | 0.99x | 8.88 | 7.75 | 87.50 % | 0.00 % |
| `feistel` | 169 | 151 | 0.89x | 13.60 | 11.80 | 80.00 % | 0.00 % |
| `fibonacci` | 382 | 382 | 1.00x | 1.00 | 1.00 | 0.00 % | 0.00 % |
| `sesion_sin_logout` | 34 | 34 | 1.00x | 1.00 | 1.00 | 0.00 % | 0.00 % |
| `suma_10_15` | 7 | 7 | 1.00x | 1.00 | 1.00 | 0.00 % | 0.00 % |
| `suma_simple_emp` | 1 087 | 1 015 | 0.93x | 8.88 | 7.75 | 87.50 % | 0.00 % |
| `suma_vliw_emp` | 757 | 685 | 0.90x | 8.88 | 7.75 | 87.50 % | 0.00 % |

## 2. AMAT de lectura, teorico contra medido (configuracion base)

Teorico: `T_L1 + m_L1 x (T_L2 + m_L2 x (T_mem + 2))`, con T_L2 = 8 y T_mem = 53. Penalidad por tipo = ciclos de stall / lecturas de ese tipo.

| programa | m_L1 | m_L2 local | AMAT teorico | AMAT medido | penalidad acierto L2 | penalidad fallo L2 |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `patron_secuencial` | 12.50 % | 100.00 % | 8.88 | 8.88 | - | 63.0 |
| `patron_stride` | 100.00 % | 100.00 % | 64.00 | 64.00 | - | 63.0 |
| `patron_aleatorio` | 87.11 % | 74.55 % | 43.69 | 43.69 | 8.0 | 63.0 |
| `patron_reuso` | 100.00 % | 50.00 % | 36.50 | 36.50 | 8.0 | 63.0 |
| `recorrido_cache` | 25.00 % | 0.00 % | 3.00 | 3.88 | 11.5 | - |

## 3. Ciclos de stall por causa (configuracion base)

| programa | fallo L1, acierto L2 | fallo L1, fallo L2 | write buffer lleno | conflicto RAW | total |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `patron_secuencial` | 0 | 8 064 | 0 | 0 | 8 064 |
| `patron_stride` | 0 | 64 512 | 0 | 0 | 64 512 |
| `patron_aleatorio` | 1 816 | 41 895 | 0 | 0 | 43 711 |
| `patron_reuso` | 2 048 | 16 128 | 0 | 0 | 18 176 |
| `recorrido_cache` | 1 476 | 0 | 6 665 | 0 | 8 141 |
| `contar_hasta_n` | 0 | 0 | 0 | 0 | 0 |
| `div32_prueba` | 0 | 134 | 0 | 0 | 134 |
| `estadisticas` | 0 | 63 | 0 | 0 | 63 |
| `feistel` | 0 | 126 | 0 | 0 | 126 |
| `fibonacci` | 0 | 0 | 0 | 0 | 0 |
| `sesion_sin_logout` | 0 | 0 | 0 | 0 | 0 |
| `suma_10_15` | 0 | 0 | 0 | 0 | 0 |
| `suma_simple_emp` | 0 | 504 | 0 | 0 | 504 |
| `suma_vliw_emp` | 0 | 504 | 0 | 0 | 504 |

## 4. Capacidad de L1 (2 vias, L2 de 16 KB)

Tasa de aciertos de lectura de L1, y ciclos de ejecucion.

| programa | 512 B | 1 KB | 2 KB | 4 KB | 8 KB | 16 KB |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `patron_secuencial` aciertos | 87.50 % | 87.50 % | 87.50 % | 87.50 % | 87.50 % | 87.50 % |
| `patron_secuencial` ciclos | 16 266 | 16 266 | 16 266 | 16 266 | 16 266 | 16 266 |
| `patron_stride` aciertos | 0.00 % | 0.00 % | 0.00 % | 0.00 % | 0.00 % | 0.00 % |
| `patron_stride` ciclos | 72 714 | 72 714 | 72 714 | 72 714 | 72 714 | 72 714 |
| `patron_aleatorio` aciertos | 1.37 % | 4.49 % | 7.32 % | 12.89 % | 23.83 % | 32.62 % |
| `patron_aleatorio` ciclos | 80 506 | 80 250 | 80 018 | 79 562 | 78 831 | 78 056 |
| `patron_reuso` aciertos | 0.00 % | 0.00 % | 0.00 % | 0.00 % | 50.00 % | 50.00 % |
| `patron_reuso` ciclos | 22 301 | 22 301 | 22 301 | 22 301 | 20 253 | 20 253 |
| `recorrido_cache` aciertos | 0.00 % | 0.00 % | 0.00 % | 75.00 % | 75.00 % | 75.00 % |
| `recorrido_cache` ciclos | 16 384 | 16 384 | 16 384 | 13 312 | 13 312 | 13 312 |

## 5. Capacidad de L2 (4 vias, L1 de 4 KB)

Tasa de aciertos de lectura de L2 (local), ciclos de ejecucion e invalidaciones hacia atras.

| programa | 4 KB | 8 KB | 16 KB | 32 KB | 64 KB |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `patron_secuencial` aciertos L2 | 0.00 % | 0.00 % | 0.00 % | 0.00 % | 0.00 % |
| `patron_secuencial` ciclos | 16 266 | 16 266 | 16 266 | 16 266 | 16 266 |
| `patron_secuencial` invalidaciones | 1 | 0 | 0 | 0 | 0 |
| `patron_stride` aciertos L2 | 0.00 % | 0.00 % | 0.00 % | 0.00 % | 0.00 % |
| `patron_stride` ciclos | 72 714 | 72 714 | 72 714 | 72 714 | 72 714 |
| `patron_stride` invalidaciones | 897 | 0 | 0 | 0 | 0 |
| `patron_aleatorio` aciertos L2 | 2.30 % | 13.00 % | 25.45 % | 29.71 % | 29.71 % |
| `patron_aleatorio` ciclos | 92 152 | 85 667 | 79 562 | 77 472 | 77 472 |
| `patron_aleatorio` invalidaciones | 404 | 0 | 0 | 0 | 0 |
| `patron_reuso` aciertos L2 | 0.00 % | 50.00 % | 50.00 % | 50.00 % | 50.00 % |
| `patron_reuso` ciclos | 36 381 | 22 301 | 22 301 | 22 301 | 22 301 |
| `patron_reuso` invalidaciones | 385 | 0 | 0 | 0 | 0 |
| `recorrido_cache` aciertos L2 | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % |
| `recorrido_cache` ciclos | 13 312 | 13 312 | 13 312 | 13 312 | 13 312 |
| `recorrido_cache` invalidaciones | 1 | 0 | 0 | 0 | 0 |

## 6. Memoria principal, con y sin L2

| programa | accesos con L2 | accesos sin L2 | uso del bus con L2 | uso del bus sin L2 |
| :--- | ---: | ---: | ---: | ---: |
| `patron_secuencial` | 130 | 129 | 40.60 % | 44.22 % |
| `patron_stride` | 1 026 | 1 025 | 72.86 % | 83.87 % |
| `patron_aleatorio` | 667 | 893 | 43.45 % | 55.23 % |
| `patron_reuso` | 258 | 513 | 59.48 % | 83.81 % |
| `recorrido_cache` | 258 | 257 | 64.90 % | 74.60 % |
| `contar_hasta_n` | 6 | 5 | 39.15 % | 93.19 % |
| `div32_prueba` | 6 | 8 | 6.54 % | 9.56 % |
| `estadisticas` | 3 | 3 | 11.27 % | 16.08 % |
| `feistel` | 4 | 3 | 30.86 % | 75.73 % |
| `fibonacci` | 12 | 8 | 53.65 % | 94.33 % |
| `sesion_sin_logout` | 2 | 2 | 18.64 % | 79.39 % |
| `suma_10_15` | 0 | 0 | 0.00 % | 0.00 % |
| `suma_simple_emp` | 10 | 9 | 32.34 % | 43.66 % |
| `suma_vliw_emp` | 10 | 9 | 40.69 % | 63.07 % |
