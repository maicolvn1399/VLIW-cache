# Registro de decisiones de diseño

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Actualizado tras la Iteración 5.

Las decisiones tomadas y las que faltan, en un solo lugar. Para cada una tomada: qué se escogió, por qué, y con qué evidencia. Para cada una pendiente: cuál es la recomendación y la razón, para llevarla al grupo antes de implementar.

El desarrollo completo de las políticas está en [jerarquia-memoria.md](jerarquia-memoria.md) y los números en [analisis-rendimiento.md](analisis-rendimiento.md).

---

## Decisiones tomadas

### Políticas de caché

| # | Decisión | Alternativa descartada | Por qué | Evidencia |
|---|---|---|---|---|
| 1 | L1-D **write-through** | write-back | La L2 es write-back obligatoria. Con L1 también write-back habría líneas sucias en dos niveles, y haría falta invalidación hacia atrás con recogida del dato. Con write-through, L1 nunca tiene línea sucia. | 13 de 14 programas pierden 0 ciclos por buffer lleno, con y sin L2 |
| 2 | **No-write-allocate** | write-allocate | Con write-through, traer una línea de 53 ciclos para escribirla hacia abajo de todos modos paga la latencia sin ganar nada. | aciertos de escritura = 0, exacto, comprobado |
| 3 | **LRU exacto**, 1 bit por conjunto | FIFO, aleatorio, pseudo-LRU | A dos vías el LRU exacto cuesta un bit: 64 bits para toda la caché. A ese precio, aproximar no ahorra nada. | 384 aciertos exactos en `recorrido_cache.s` |
| 4 | **Stall** para el riesgo RAW | store-to-load forwarding | El forwarding desde el buffer exige resolver máscaras de byte con prioridad por antigüedad, en el camino crítico del acierto de un ciclo. El profesor aceptó el stall. | **1 ciclo** en los 11 programas de la Iteración 3; **0** en las 154 corridas del barrido |
| 5 | Inclusión **inclusiva** (L1 subconjunto de L2) | NINE, exclusiva | Con L1 write-through, invalidar es solo apagar un bit de válido. Hace medible el costo de coherencia entre niveles que pide el enunciado. Ver la nota de abajo. | **0 invalidaciones** con la geometría del proyecto; solo aparecen con L2 del tamaño de L1 |
| 6 | **Sin L1 de instrucciones** | L1-I de 4 KB | Indicación del profesor: corre un programa a la vez, no agregaría nada medible. | n/a |

### Dimensionamiento

| # | Decisión | Rango permitido | Por qué | Evidencia |
|---|---|---|---|---|
| 7 | Write buffer L1 a L2: **8 entradas** | 2 a 8 | Un store entra por ciclo y drenar cuesta 53, así que ninguna profundidad salva una ráfaga sostenida. Lo que compra es tolerancia a ráfagas cortas, y ahí más es mejor sin costo de latencia. Lo que de verdad baja la presión es la fusión. | solo el programa hecho para saturarlo pierde ciclos |
| 8 | Eviction buffer L2 a memoria: **8 entradas** | 4 a 16 | La L2 write-back solo genera tráfico al expulsar, no en cada escritura, así que 16 serían estado sin uso. | **0 ciclos** lleno en las 140 corridas con L2; 5959 sin L2 (P5) |
| 9 | L1-D de **4 KB, 2 vías, líneas de 32 B** | lo fija el enunciado | Además de venir dado, el barrido lo confirma como el codo. Con L2, quedarse corto de L1 cuesta 8 ciclos por fallo en vez de 54. | codo de `recorrido_cache` en 4 KB; pasarse rinde 9 % como máximo |
| 20 | L2 de **16 KB, 4 vías, hit time de 8 ciclos** | lo fija el enunciado | El barrido de capacidad de L2 lo confirma: es el primer tamaño cuatro veces la L1. | 86 % de la ganancia disponible del aleatorio; una L2 de 4 KB es peor que no tener L2; penalidad de acierto medida: 8,0 |
| 21 | Reemplazo de L2: **LRU exacto con edades** | pseudo-LRU de árbol | Ver P1. | 256 aciertos de L2 exactos en `patron_reuso.s` |

### Microarquitectura e implementación

| # | Decisión | Alternativa descartada | Por qué |
|---|---|---|---|
| 10 | Latencia de memoria con **máquina de estados** de 5 estados | contador de retardo fijo | Indicación del profesor. Permite modelar la ráfaga de 8 palabras y arbitrar lectura contra drenado, que un contador no puede. |
| 11 | Cruce de dominios por **habilitación** (`mem_tick`) | reloj derivado de 25 MHz | Un reloj derivado en simulación produce carreras entre dominios que no son reales. La habilitación modela lo mismo sin ellas. |
| 12 | **Máscaras de byte** de 32 bits punta a punta | escribir la línea completa | Bajo write-through, un `SB` tiene que viajar sin arrastrar los bytes vecinos, que pueden no estar en la caché. Sin máscara grabaría 31 bytes de basura. |
| 13 | **Fusión** en los buffers, con guardia `head_ocupada` | buffer FIFO simple | La fusión es lo que hace que la localidad espacial no presione el buffer. El guardia existe porque fusionar sobre una línea ya en camino la perdía en silencio 53 ciclos después. |
| 14 | Congelar aguas arriba, burbuja aguas abajo, con la regla **"un efecto solo ocurre si el bundle avanza"** | congelar todo el pipeline | Congelar todo detendría también lo que ya está terminado. La regla evita que un store en stall se empuje al buffer una vez por ciclo de espera. |
| 15 | Contadores **en el RTL**, no en el testbench, y no `perf` | observar señales desde el testbench; `perf` de Linux | Un testbench que observa mide su propia interpretación del diseño. Y `perf` instrumenta el anfitrión que corre el simulador, no el procesador simulado: vería la caché del Intel, no la nuestra. |
| 16 | Contadores **saturantes con bit pegajoso** | envolver en silencio | Un contador que envuelve produce un informe plausible y falso. |

### Alcance

| # | Decisión | Por qué |
|---|---|---|
| 17 | La L1 se escribió para **exactamente 2 vías** | Generalizar a N vías se hizo una sola vez, en el módulo nuevo de la L2. ⚠️ La L1 no tiene guardia: con `L1D_WAYS=1` la simulación no falla, se cuelga 2,5 millones de ciclos leyendo `x`. La L2 sí aborta ante una geometría incoherente. |
| 18 | El barrido varía **capacidad**, no asociatividad | Consecuencia de la 17 para la L1; en la L2 se dejaron las 4 vías fijas para comparar solo capacidad. |
| 19 | Se escribió un benchmark nuevo, `recorrido_cache.s` | Los diez programas del Proyecto I tocan dos o tres líneas cada uno, así que todos sus fallos son de arranque y el barrido salía plano en un rango de 32 veces. Sin un programa cuyo conjunto de trabajo no quepa, el experimento no puede medir geometría. |
| 22 | Se escribió un cuarto patrón, `patron_reuso.s` | El secuencial y el stride tocan cada línea una vez, así que la L2 nunca puede acertar. Hacía falta reuso a una distancia que L1 no cubre y L2 sí: 8 KB, el doble de L1 y la mitad de L2. |
| 23 | Línea base **sin L2** con `-DCERBERO_SIN_L2`, sobre el mismo RTL | Para medir lo que aporta la L2 hay que compararla contra el mismo sistema sin ella, no contra un modelo aparte ni contra la Iteración 3, que tenía otro arbitraje. |

### Nota sobre la decisión 5: se cambió sobre la marcha

Hasta la Iteración 3 la política documentada y acordada era **NINE**, con tres argumentos: que la inclusión sirve para coherencia multinúcleo y aquí hay un solo núcleo, que obliga a implementar invalidación hacia atrás, y que con L1 write-through NINE es seguro porque L1 nunca tiene líneas sucias. El profesor además recomendó explícitamente no usar inclusiva porque complica más.

La Iteración 4 se implementó **inclusiva**. El riesgo que señalaba la justificación de NINE se materializó: la invalidación hacia atrás venía rota (reconstruía la etiqueta de L1 leyendo bits fuera de rango de un vector de 11 bits, así que la comparación no daba verdadero nunca) y nadie lo detectó porque su prueba no comprobaba nada. Se arregló y la prueba ahora comprueba el efecto.

**Resuelta en la Iteración 5: se queda inclusiva.** Con el mecanismo funcionando, la medición decidió: con la geometría del proyecto (L2 cuatro veces la L1) hubo **cero invalidaciones** en los 14 programas, así que volver a NINE era borrar lógica probada sin ganar ningún ciclo. La justificación completa, con lo medido, está en [jerarquia-memoria.md](jerarquia-memoria.md) D6 y en [analisis-rendimiento.md](analisis-rendimiento.md) §10.

---

## Decisiones pendientes

Cinco de la Iteración 4 y una de la 5, todas resueltas salvo la confirmación de P4 con el profesor. Se conservan con su recomendación original, porque es la justificación de lo que se hizo.

### P1. Reemplazo de L2 (4 vías)

El bit único de la decisión 3 no sirve con cuatro vías.

| Opción | Costo de estado | Exactitud |
|---|---|---|
| LRU verdadero con edades de 2 bits por vía | 8 bits/conjunto, **1024 bits** | exacto |
| Pseudo-LRU de árbol | 3 bits/conjunto, **384 bits** | aproximado |
| Aleatorio o round-robin | 2 bits/conjunto o menos | sin localidad |

**RESUELTA en la Iteración 4: LRU verdadero con edades**, como se recomendaba. `l2_cache.sv` guarda una matriz de edades de 2 bits por vía con inicialización escalonada, de modo que las edades de un conjunto son siempre una permutación de 0 a 3 y la víctima está siempre bien definida. Comprobado en `tb_l2_cache.sv` caso [7].

La recomendación original, que se mantiene como justificación: los 640 bits que ahorra el pseudo-LRU son el **0,45 %** del estado total de la L2 (los arreglos de datos y etiquetas suman unos 142 000 bits), así que el argumento de costo no aplica a esta escala. Y hay una razón propia del proyecto que decide: nuestra metodología de validación depende de poder **predecir el número exacto de aciertos a mano**, como se hace con `recorrido_cache.s`. Con LRU exacto ese cálculo se puede repetir para la L2; con pseudo-LRU el número esperado deja de ser calculable y perdemos el mejor mecanismo de validación que tenemos.

### P2. Cómo generalizar la caché a N vías

**RESUELTA en la Iteración 4 para la L2**, con comparación por `generate` sobre `WAYS` y edades de `log2(WAYS)` bits, tal como se recomendaba. La L1 sigue siendo de dos vías fijas: la generalización se hizo en el módulo nuevo y no se tocó el que ya estaba verificado, que era el riesgo que preocupaba. El barrido de capacidad sigue funcionando igual.

La recomendación original: comparación de etiquetas por `generate` sobre `L1D_WAYS`, índice de vía de `log2(WAYS)` bits, y el LRU como un arreglo de edades de `log2(WAYS)` bits por vía.

La clave es el criterio de aceptación, no el código: **con `WAYS=2` el comportamiento tiene que ser idéntico al actual y los 50 casos de `tb_l1_dcache.sv` deben pasar sin modificarse.** Si hay que tocar una prueba para que pase, la generalización cambió algo que no debía. Eso convierte un refactor riesgoso sobre un módulo ya verificado en algo comprobable.

### P3. Política de L2 ante fallo de escritura

**RESUELTA en la Iteración 4: write-allocate**, y además con el atajo de línea completa que se sugería. Comprobado en `tb_l2_cache.sv` casos [5] y [6]: una escritura parcial que falla trae la línea y conserva los bytes de afuera, y una que cubre los 32 bytes no baja a memoria.

La justificación original: es forzoso, no una preferencia: la L2 es write-back, y con no-write-allocate los stores le pasarían de largo hacia memoria, así que la L2 nunca tendría datos sucios y el write-back no serviría de nada. Write-back y write-allocate van juntos por la misma razón por la que write-through y no-write-allocate van juntos (decisión 2).

**Optimización que vale considerar en el mismo paquete:** si la máscara que llega del write buffer cubre la línea completa (32 bytes, posible gracias a la fusión), se puede **omitir la lectura de memoria** y escribir la línea directo, porque no hay ningún byte viejo que preservar. Eso ahorra 53 ciclos en el caso que la fusión vuelve común.

### P4. Qué pasa con las instrucciones en una L2 "unificada"

El enunciado pide una L2 unificada, pero no hay L1 de instrucciones (decisión 6) y la `imem` es de un ciclo. Entonces, en la práctica, a la L2 solo le llegaría tráfico de datos.

**RESUELTA en la Iteración 4 tal como se recomendaba**: la `imem` quedó intacta y la L2 recibe solo tráfico de datos. Sigue pendiente confirmarlo con el profesor.

La recomendación original: dejar la `imem` como está y documentar que la L2 es unificada en estructura. Es decir, no distingue instrucciones de datos y serviría a las dos si existiera una L1-I, pero en este sistema solo recibe datos. Enrutar la búsqueda de instrucciones por la L2 obligaría a convertir la `imem` en algo que falla, lo cual toca el pipeline ya entregado, y el profesor pidió explícitamente no mover lo del primer proyecto. Conviene plantearlo al profesor para confirmar que esta lectura de "unificada" es la que espera.

### P5. Revisar la profundidad del eviction buffer

**RESUELTA en la Iteración 5: se queda en 8.** El contador `stall_por_evict` marca **0** en las 140 corridas del barrido con L2 (10 configuraciones × 14 programas). La L2 write-back se queda con los stores sucios y casi no expulsa durante el programa.

La contraprueba es la configuración sin L2, donde cada store baja directo al eviction buffer: ahí `recorrido_cache.s` pierde **5959 ciclos** con el buffer lleno. El buffer no alcanza por suerte; es la L2 la que le quita la presión, que era el razonamiento original de la decisión 8.

La recomendación anterior era bajarlo a 4 si el contador salía en cero. No se hizo porque no se midió con 4: dejar 8, dentro del rango del enunciado y con un número que lo respalda, es más defendible que bajarlo sin medir.

El razonamiento original de por qué hacía falta ese contador: cuando el eviction buffer se llena, el write buffer de arriba no puede drenar, y la presión se ve como `stall_por_wb`. Sin un contador propio no se podía distinguir si el write buffer se llenaba porque drenar cuesta 53 ciclos o porque el buffer de abajo estaba lleno, y esas dos causas piden arreglos opuestos.

### P6. Qué comparar en la Iteración 5

**RESUELTA en la Iteración 5**, en dos mediciones que se complementan:

- **La jerarquía**, con los cuatro patrones de acceso y un barrido de 11 configuraciones: con y sin L2, capacidad de L1 de 512 B a 16 KB y de L2 de 4 a 64 KB. Ver [analisis-rendimiento.md](analisis-rendimiento.md) §7 a §11.
- **El compilador**, con 39 programas de NOVA en `-O0`, `-O1` y `-O2` sobre el mismo RTL, medido por el equipo de CE1108. Ver [ITERACION5_NIVELES.md](../../documentacion/ITERACION5_NIVELES.md) y su resumen en [analisis-rendimiento.md](analisis-rendimiento.md) §12.

La recomendación era medir la presión sobre la caché además de la ocupación, y eso es lo que salió: de los ciclos que ahorra `-O2`, el 91,5 % viene de emitir menos operaciones (sobre todo accesos al marco de pila) y solo el 8,5 % de empaquetar mejor. Los accesos a memoria caen un 61,9 % y los ciclos un 30,3 %.

---

## Resumen

23 decisiones tomadas. De ellas:

- **Once están respaldadas por una medición** (1, 2, 3, 4, 5, 7, 8, 9, 19, 20, 21): hay un número del hardware que las defiende.
- **Cinco fueron validadas por una prueba que encontró un error real** (11, 12, 13, 14, 17): no se sabía que hacían falta hasta que el testbench mostró el defecto.
- **Cinco son de razonamiento** sobre consecuencias de otras decisiones o del enunciado, o sobre cómo medir (10, 15, 18, 22, 23).
- **Dos vienen dadas** por indicación del profesor o del enunciado (6, y la geometría de 9 y 20).

La 8, la profundidad del eviction buffer, era la única sin respaldo; desde la Iteración 5 tiene su medición (P5).

Las 6 decisiones pendientes quedaron resueltas. Solo P4, la lectura de "L2 unificada" cuando no hay L1 de instrucciones, sigue esperando la confirmación del profesor.
