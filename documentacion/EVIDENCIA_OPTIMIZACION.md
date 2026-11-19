# Evidencia: qué gana cada nivel de optimización

Medido sobre el **RTL del procesador**, no estimado. Los ciclos salen de los
contadores de hardware (`perf_ciclos`), y cada corrida verificó además que R6 y
la salida de `scribe` no cambian entre niveles.

```bash
make prueba-rtl-equivalencia      # 117 correctas, 0 fallidas (-O0/-O1/-O2)
```

## Resultado global

| | Ciclos ejecutados | Contra `-O0` |
|---|---|---|
| `-O0` | 536 920 | — |
| `-O1` | 515 022 | −4.1 % |
| **`-O2`** | **373 356** | **−30.5 %** |

39 programas. **`-O2` recorta casi un tercio del tiempo de ejecución.**

## Los que más mejoran

| Programa | `-O0` | `-O2` | |
|---|---|---|---|
| `multiplicar_matrices.nv` | 4 331 | 2 530 | −41.6 % |
| `matriz_transpuesta.nv` | 1 775 | 1 094 | −38.4 % |
| `matriz_1000.nv` | 351 232 | 224 345 | −36.1 % |
| `producto_punto.nv` | 1 434 | 949 | −33.8 % |
| `matriz_for.nv` | 2 735 | 1 897 | −30.6 % |
| `cola.nv` | 24 088 | 17 085 | −29.1 % |

El patrón es claro y conviene decirlo: **los que más ganan son los que tienen
lazos con cuerpo regular**. Ahí el desenrollado tiene material, y una vez
desenrollado el planificador tiene trabajo independiente que meter en los slots
vacíos.

## Los tres casos que no mejoran, y por qué

Vale más mencionarlos que esperar a que los encuentre el profesor.

| Programa | `-O0` | `-O2` | Qué pasa |
|---|---|---|---|
| `saludo.nv` | 264 | 264 | Sin lazos ni código muerto: no hay nada que optimizar. |
| `t2_propagacion.nv` | 64 | 40 | Mejora contra `-O0`, pero `-O1` da 34: en un programa de 34 ciclos, el prólogo que agrega el desenrollado cuesta más de lo que ahorra. |
| `dce_ciclo_potencialmente_infinito.nv` | 54 | **60** | **El único que empeora**: +6 ciclos. El compilador no puede probar que el lazo termina, así que no lo desenrolla, y queda solo el costo de preparar la asignación de registros. |

Seis ciclos sobre cincuenta y cuatro. Es ruido, pero es honesto decir que
existe: **una optimización puede costar más de lo que ahorra en programas
diminutos**, y el compilador no tiene cómo saberlo de antemano sin un modelo de
costo que hoy no tiene.

## El tamaño sube y el tiempo baja

`matriz_for.nv`, el caso de demostración:

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| bundles emitidos (tamaño en IMEM) | 336 | 332 | **417**  (+24 %) |
| ciclos ejecutados | 2 735 | 2 687 | **1 897**  (−31 %) |
| IPC | 0.472 | 0.472 | **0.511** |

**El programa crece 24 % y corre 31 % más rápido.** Eso es el desenrollado
cambiando espacio por tiempo: donde había N vueltas de un cuerpo chico ahora hay
N/4 de uno cuatro veces más grande, con menos saltos y menos actualizaciones del
contador. El IPC sube porque el planificador encuentra más operaciones
independientes para poner en el mismo bundle.

---

## El IPC no es una medida de velocidad

Vale la pena tenerlo claro, porque la tabla de arriba trae IPC y es fácil leerlo
al revés. `unroll_variable_pequena.nv`, sobre el RTL con caché:

| | ciclos | instrucciones | IPC |
|---|---|---|---|
| `-O1` | 387 | 152 | 0.393 |
| `-O2` | **300**  (−22.5 %) | 116 | **0.387** |

**El programa corre 22.5 % más rápido y el IPC baja.** No es contradictorio:
IPC = instrucciones ÷ ciclos, y el desenrollado *elimina* instrucciones de
sobrecarga —el salto, la comparación y la actualización del contador de cada
vuelta— más rápido de lo que elimina ciclos. El numerador cae más que el
denominador.

> El IPC mide **qué tan lleno va el pipeline**, no cuánto tarda el programa.
> Una optimización que borra trabajo casi siempre lo baja. La medida de
> velocidad son los **ciclos**.

Por eso `test/optimizaciones/run_rtl.sh` afirma sobre ciclos, no sobre IPC: la
función `verificar_mejora_ciclos()` falla si `-O2` no reduce los ciclos, e
imprime el IPC al lado como información, sin que decida el resultado de la
prueba.

El caso contrario también existe: en `matriz_for` el IPC **sube** (0.472 →
0.511) porque ahí el planificador encontró operaciones independientes con que
llenar slots que antes iban vacíos. Las dos cosas pueden pasar, y por eso el IPC
solo no dice si una optimización sirvió.

---

## Cuidado con la columna «Antes» del panel del IDE

En la pestaña **Optimizacion**, las columnas se llaman *Antes* y *Despues*, y
**no son `-O0` y `-O2`**. Las dos salen de la *misma* compilación en `-O2`:

- **Antes** = el TAC tal como lo dejó la fase 4, pasado por el backend de `-O2`.
- **Despues** = el TAC después de la fase 6, por el mismo backend.

O sea que la columna «Antes» **ya trae el reordenamiento y la planificación**.
Lo que aísla es el efecto de la fase 6 sola. Para `matriz_for`:

| | Antes (panel) | Despues (panel) | `-O0` de verdad |
|---|---|---|---|
| bundles | 279 | 417 | **336** |
| ciclos | 2 017 | 1 897 | **2 735** |

El panel muestra una mejora del 6 % en ciclos; la mejora real contra `-O0` es
del **31 %**. **El panel subestima la ganancia**, porque su línea base ya está
medio optimizada.

> Si en la revisión decís «antes y después de optimizar» señalando esas
> columnas, estás diciendo algo que no es, y los números juegan en contra. Para
> la comparación de verdad hay que compilar en cada nivel por separado — que es
> justo lo que hace la tabla de arriba.

## Un detalle menor

En `-O2`, `t2_ciclo_muerto.nv` emite **tres** advertencias W010 donde `-O1`
emite dos: la de la línea 5 sale repetida. Es consecuencia del desenrollado —
duplica el cuerpo del lazo, y la eliminación de código muerto encuentra la misma
asignación muerta en las dos copias y reporta las dos contra la misma línea del
fuente. No afecta al código generado, pero si alguien lo nota, esa es la razón.
