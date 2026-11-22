# Caché L1-D y su integración con el pipeline

**Proyecto Grupal II — Iteración 3**

Esta iteración cierra el circuito que la Iteración 2 dejó abierto. El
subsistema de memoria estaba verificado pero desconectado, y la línea base sin
caché era una proyección. Ahora hay una caché de datos entre la LSU y la
memoria, el pipeline se congela cuando un acceso no se resuelve, y los números
son medidos.

**El resultado:** los diez programas quedaron por debajo de la cota optimista
que la Iteración 2 calculó para un sistema sin caché, y el conjunto completo
corre en **1,00×** el tiempo que tardaría con memoria ideal. La jerarquía
recupera prácticamente toda la penalidad de los 53 ciclos.

---

## 1. Qué se agregó y qué se tocó

| | |
| :--- | :--- |
| Nuevo | `src/cpu/l1_dcache.sv` — la caché |
| Nuevo | `src/tb/tb_l1_dcache.sv` — 50 casos |
| Modificado | `fetch.sv`, `reg_if_id.sv`, `reg_id_ex.sv`, `imem.sv` — entrada de congelamiento |
| Modificado | `top.sv` — la jerarquía reemplaza a `dmem`, más el write buffer |
| Modificado | `eviction_buffer.sv`, `mem_controller.sv`, `main_memory.sv` — máscaras de byte |
| Modificado | `perf_counters.sv` — contadores de hit/miss y de stalls por causa |
| Eliminado del datapath | `dmem.sv` — la memoria de datos ideal del Proyecto I |
| **Sin tocar** | El ISA: ni un opcode, ni un campo, ni un formato de bundle |

Las 35 unidades de prueba pasan.

---

## 2. Las decisiones, y lo que cada una produjo

Las tres políticas se eligieron antes de implementar, con su justificación
escrita. Esta sección contrasta lo que se esperaba de cada una contra lo que
efectivamente se midió.

| Decisión | Elegida |
| :--- | :--- |
| Política de escritura | **Write-through** |
| Asignación en miss de escritura | **No-write-allocate** |
| Reemplazo | **LRU** (1 bit por conjunto) |
| Riesgo RAW en los buffers | **Stall** |
| Write buffer L1→L2 | 8 entradas (máximo del rango 2–8) |

### D1 — Write-through

El enunciado obliga write-back en L2 *"dado el alto costo de latencia hacia
memoria principal"*. Ese es el criterio, y aplicado a L1 da lo contrario: el
nivel de abajo de L2 cuesta 53 ciclos, el de L1 cuesta 8. El mismo razonamiento
que hace obligatorio el write-back abajo lo hace innecesario arriba, por un
factor de 6,6.

Lo que esto produjo, medible:

- **La caché no tiene bit de sucio ni camino de desalojo.** Una línea limpia se
  descarta; no hay nada que escribir al reemplazarla.
- **Ningún programa perdió un solo ciclo por el write buffer.** La columna
  "por wb lleno" es cero en los diez (sección 5.3), que era el riesgo principal
  que esta decisión asumía.

### D2 — No-write-allocate

Con write-through, un store que falla no necesita la línea: el dato baja de
todos modos y L1 nunca es la única copia de nada. Traerla costaría 53 ciclos
para después escribir igual hacia abajo.

Lo que esto produjo:

- **Un write miss no detiene el pipeline.** La condición de stall quedó en un
  solo caso real, el fallo de lectura.
- **Tres programas tienen 0 % de aciertos y 0 ciclos de penalidad.**
  `contar_hasta_n`, `fibonacci` y `sesion_sin_logout` solo escriben, así que
  nunca pueblan la caché. Con write-allocate, cada uno de esos stores habría
  traído una línea de 53 ciclos para sobrescribirla entera sin leer un byte de
  lo traído: `fibonacci` habría pagado por sus 47 stores en vez de correr en el
  tiempo ideal.

Ese 0 % es el resultado contraintuitivo de la iteración y conviene no
presentarlo como un defecto. Una tasa de aciertos de cero que cuesta cero
ciclos es exactamente lo que esta política busca.

### D3 — LRU

Con dos vías es un bit por conjunto, 64 bits en toda la caché, y es LRU exacto
y no una aproximación. Cuesta lo mismo que FIFO y rinde mejor; Random además
habría roto la reproducibilidad en la que descansa toda la verificación del
proyecto.

`tb_l1_dcache` lo prueba con el caso que distingue LRU de FIFO: se cargan A y
B, se vuelve a tocar A, y se trae C. LRU desaloja B; FIFO desalojaría A. La
prueba verifica que A sobrevive **y** que B se fue, porque cualquiera de las
dos comprobaciones por separado podría pasar por casualidad.

### D4 — Stall para el riesgo RAW

Un store que falla deja su dato solo en el write buffer. Leer esa línea antes
de que drene traería de memoria el valor viejo. Se espera a que drene.

Costó **1 ciclo en todo el conjunto de pruebas** (`lazo_estres`). El
store-to-load forwarding habría evitado ese ciclo a cambio de un multiplexor de
256 bits gobernado por la máscara de bytes.

---

## 3. La integración con el pipeline

### 3.1 La caché ocupa el lugar exacto de la `dmem`

La LSU calcula la dirección en EX y el dato se usa en MEM. La `dmem` del
Proyecto I encajaba ahí porque su lectura estaba registrada. La caché conserva
esa interfaz: un acierto cuesta un ciclo y el dato aparece en MEM igual que
antes. Lo único nuevo hacia el pipeline es `cache_stall`.

Por eso **no hizo falta la etapa adicional** que el enunciado permite
(sección 3.1.2).

### 3.2 Qué se congela y qué se vacía

```
   IF  ───────┐
              │  se CONGELAN: PC, imem, reg_if_id, reg_id_ex
   ID  ───────┤
              │
   EX  ───────┘  ← el bundle que falló se queda aquí
        ╎
        ╎  se inyecta BURBUJA en la frontera EX/MEM
        ╎
   MEM ───────┐
              │  siguen avanzando y terminan su escritura
   WB  ───────┘
```

Aguas arriba se retiene porque ese trabajo todavía no se hizo. Aguas abajo se
vacía porque sí se hizo y hay que dejarlo drenar: si la frontera EX/MEM también
se congelara, el bundle que ya estaba en MEM repetiría su escritura al banco
una vez por ciclo de espera, y un `.INC` volvería a sumar su incremento cada
vez.

### 3.3 La regla que sostiene todo

**Todo efecto ocurre en el ciclo en que `stall` está apagado.**

Mientras el pipeline espera, la LSU vuelve a presentar la misma petición ciclo
tras ciclo. Si los efectos se dispararan con la petición, un store se empujaría
al write buffer 53 veces. La señal `ex_commit` en `top.sv` es esa regla hecha
cable: la miran los puertos de escritura, el registro de fallas y la bóveda de
llaves. Las unidades combinacionales no la necesitan, y la LSU **no debe**
mirarla, porque su petición tiene que seguir presente durante toda la espera.

---

## 4. Tres errores que las pruebas encontraron

Vale la pena dejarlos escritos, porque los tres son silenciosos: ninguno hace
fallar una simulación, los tres hacen que el programa calcule otra cosa.

### 4.1 La `imem` era media frontera IF/ID sin congelar

`imem.sv` tiene su salida registrada, así que esos 128 bits **son** la mitad de
la frontera IF/ID; `reg_if_id` lleva el PC y la validez, y la memoria lleva el
bundle. Se congeló solo la primera mitad.

A partir del segundo ciclo de stall, el PC de ID y el bundle de ID dejaban de
corresponderse. Al levantarse el stall, ID decodificaba el bundle equivocado:
el detenido se perdía sin ejecutarse y el siguiente se ejecutaba dos veces.

Lo encontró `tb_top`, en el caso de un `lbu` inmediatamente posterior a un
fallo de caché. El síntoma era un registro en cero.

### 4.2 Fusionar sobre una línea que ya iba en camino

El controlador de memoria se queda con una **copia** de la línea al arrancar un
drenado, y escribe desde esa copia durante los 53 ciclos que dura. Si en ese
lapso el buffer fusionaba datos nuevos sobre la entrada original, la copia no se
enteraba y esos bytes se perdían al confirmarse el drenado.

Peor: la ventana empieza un ciclo **antes** de lo que parece. La copia se toma
en el mismo flanco en que la máquina sale de su estado libre, así que durante
ese ciclo el estado todavía dice "libre" mientras la entrada ya está condenada.
La primera corrección, que solo excluía los estados de escritura, no alcanzaba.

El síntoma era dos `SW` consecutivos a la misma línea con uno de los dos valores
en memoria y el otro en cero. Ahora `mem_controller` publica `drenando` y el
buffer excluye la cabeza de la fusión durante toda esa ventana, con su prueba
de regresión en `tb_mem_system` caso 8.

### 4.3 El último store del programa no se contaba

Los contadores de caché estaban condicionados a que el procesador no se hubiera
detenido. Pero cuando la búsqueda registra el HALT todavía quedan bundles
dentro del pipeline, empezando por el delay slot del propio HALT — y un
programa suele terminar guardando su resultado justo ahí.

El síntoma era desconcertante: la memoria tenía el dato correcto y la caché
juraba que nunca hubo una escritura. Lo encontró la comprobación cruzada
`accesos L1 = loads + stores`, que daba 64 contra 65.

---

## 5. Lo que se midió

### 5.1 El veredicto

```
  programa                 ideal     medido   sobrec.    optimista    pesimista    gana
  -------------------  ---------  ---------  --------  -----------  -----------  ------
  contar_hasta_n.s            99         99     1.00x           99          671    6.8x
  div32_prueba.s            4138       4244     1.03x         4762         5386    1.3x
  estadisticas.s             811        864     1.07x         1227         1539    1.8x
  feistel.s                   43        149     3.47x          563          667    4.5x
  fibonacci.s                382        382     1.00x          382         2826    7.4x
  lazo_estres.s           900009     900117     1.00x      6100009     16500009   18.3x
  sesion_sin_logout.s         34         34     1.00x           34          190    5.6x
  suma_10_15.s                 7          7     1.00x            7            7    1.0x
  suma_simple_emp.s          583       1007     1.73x         3911         3963    3.9x
  suma_vliw_emp.s            253        677     2.68x         3581         3633    5.4x
  -------------------  ---------  ---------  --------  -----------  -----------  ------
  total                   906359     907580     1.00x      6114575     16518891   18.2x
```

**Los diez programas quedaron por debajo de la cota optimista** que la
Iteración 2 proyectó para un sistema sin caché — y esa cota era el mejor caso
posible sin jerarquía, no un promedio.

La columna "ideal" no está escrita a mano: es la cuenta de bundles. Sin stalls
el pipeline despacha exactamente uno por ciclo, así que ese contador *es* el
tiempo que el programa tardaría con memoria de un ciclo. El dato sale del mismo
contador que ya existía desde la Iteración 1.

### 5.2 La caché

```
  programa              accesos   ld hit   ld mis   st mis   aciertos    AMAT
  -------------------  --------  -------  -------  -------  ---------  ------
  contar_hasta_n.s           11        0        0       11       0.0%    1.00
  div32_prueba.s             24       10        2       12      41.7%   31.92
  estadisticas.s             14        7        1        6      50.0%   27.50
  feistel.s                  12        8        2        2      66.7%   18.67
  fibonacci.s                47        0        0       47       0.0%    1.00
  lazo_estres.s          300000    99999        1        1     100.0%    1.00
  sesion_sin_logout.s         3        0        0        3       0.0%    1.00
  suma_10_15.s                0        0        0        0       0.0%    1.00
  suma_simple_emp.s          65       56        8        1      86.2%    8.34
  suma_vliw_emp.s            65       56        8        1      86.2%    8.34
```

El AMAT se calcula con la penalidad **medida** (ciclos de stall ÷ fallos de
lectura), no con `T_mem` supuesto. En los programas con fallos reales la
penalidad medida dio exactamente 53, que es la confirmación de que la caché y
el subsistema de memoria se entienden.

Los AMAT altos de `div32_prueba`, `estadisticas` y `feistel` no indican un
problema de la caché: son programas de 12 a 24 accesos, donde dos fallos
obligatorios de primera referencia pesan la mitad de la estadística. En
`lazo_estres`, con 300 000 accesos, el AMAT es 1,00.

### 5.3 Los ciclos perdidos, por causa

```
  programa              por miss   por wb lleno    por RAW      total
  -------------------  ---------  -------------  ---------  ---------
  contar_hasta_n.s             0              0          0          0
  div32_prueba.s             106              0          0        106
  estadisticas.s              53              0          0         53
  feistel.s                  106              0          0        106
  fibonacci.s                  0              0          0          0
  lazo_estres.s              107              0          1        108
  sesion_sin_logout.s          0              0          0          0
  suma_10_15.s                 0              0          0          0
  suma_simple_emp.s          424              0          0        424
  suma_vliw_emp.s            424              0          0        424
```

Dos columnas en cero son el resultado de las decisiones de diseño, no una
casualidad: **el write buffer nunca se llenó** en ningún programa, y el riesgo
RAW costó un solo ciclo en todo el conjunto.

---

## 6. Dónde la Iteración 2 se equivocó

La Iteración 2 anotó tres predicciones antes de medir. Conviene revisarlas con
los números a la vista.

**Se equivocó en `lazo_estres`, y es la más interesante.** Se predijo que su
cota optimista quedaría corta porque hace un store cada 4,5 ciclos contra 53
que tarda cada drenado, y que el buffer de 8 entradas se llenaría casi de
inmediato. Midió **0 ciclos perdidos por buffer lleno**.

La razón es la fusión de escrituras. El modelo de la Iteración 2 contaba
*stores*, y el buffer no drena stores: drena **líneas**. Varios stores a la
misma línea de 32 bytes se combinan en una sola entrada y cuestan un solo viaje
a memoria. Un programa con escritura secuencial —el patrón más común que
existe— divide su tráfico real hasta por ocho. Esa reducción estaba
implementada desde la Iteración 2 y aun así no entró en la proyección, porque la
proyección razonaba en accesos del programa y no en transacciones de memoria.

**Acertó en que la cota pesimista era demasiado pesimista** para los programas
con pocos accesos: `contar_hasta_n` tiene 11 stores en 99 ciclos y pagó cero.

**Acertó en que ninguna cota modelaba localidad**, y que por eso la mejora
medida sería mayor que la sugerida. Lo fue: 18,2× sobre la cota pesimista.

---

## 7. El hallazgo que sigue sosteniéndose

La Iteración 2 predijo que la ventaja del empaquetado VLIW se comprimiría al
aparecer la latencia de memoria, porque las dos versiones del mismo cálculo
hacen los mismos accesos y el empaquetado reordena operaciones sin eliminarlas.

`tb_vliw` lo mide ahora de forma directa:

| | Aceleración de `suma_vliw` sobre `suma_simple` |
| :--- | :---: |
| Memoria ideal (Proyecto I) | **2,30×** |
| Jerarquía de caché (Iteración 3) | **1,49×** |

**La latencia de memoria se come el 63 % de la ventaja del compilador.** Y la
degradación relativa es peor en la versión optimizada: 2,68× de sobrecarga
contra 1,73× de la versión simple, porque al bajar el tiempo de cómputo lo único
que queda es la espera.

El umbral de esa prueba bajó de 2,0× a 1,3×. No se aflojó para que pasara: el
sistema cambió, el testbench ahora imprime las dos cifras y el porcentaje de
ventaja perdida, y ese número es un resultado del proyecto.

Para la Iteración 5 la consecuencia es la misma que ya se anotó: medir el
empaquetado sobre memoria lenta subestima el trabajo del compilador de CE1108,
y medir la caché sobre programas mal empaquetados la sobreestima. Las
comparaciones finales hay que cruzarlas.

---

## 8. Cómo reproducir

```bash
cd src/build

make l1_dcache      # la cache aislada, 50 casos
make sim            # las 35 unidades del proyecto
make metricas       # las tres tablas de la seccion 5
make correr PROG=fibonacci.s    # un programa con su informe de cache
```

Cambiar la geometría de la caché es `L1D_BYTES` y `L1D_WAYS` en
`src/cpu/cerbero_defs.svh`; la frecuencia de memoria, `MEM_CLK_DIV`. Los
testbenches comparan contra valores calculados desde esas constantes, así que
siguen siendo pruebas.

---

## 9. Limitaciones conocidas

| Limitación | Efecto | Estado |
| :--- | :--- | :--- |
| No hay L2: un fallo de L1 va directo a memoria | La penalidad es `T_mem` (53) y no `8` u `8+53` como describe la sección 3.3 del enunciado para la jerarquía completa | Se resuelve en la Iteración 4 |
| La caché es bloqueante | Un fallo detiene el pipeline completo; no hay accesos solapados | Opcional en el enunciado (*non-blocking*, 7.1.4) |
| La lectura de `main_memory` es combinacional | En FPGA haría falta una etapa más de segmentación y `T_mem` subiría un ciclo de memoria | Documentada desde la Iteración 2 |
| `ciclos` se detiene en el HALT; los contadores de caché no | Difieren por los últimos bundles del delay slot | Documentada en `perf_counters.sv` |

---

## 10. Lo que sigue

| Iteración | Qué agrega | Qué cambia de aquí |
| :---: | :--- | :--- |
| 4 | Caché L2 unificada, política de inclusión, reemplazo de L2 | El write buffer pasa a drenar en L2; la penalidad se parte en 8 y 8+53 |
| 5 | Benchmarks bajo distintos niveles de optimización | El cruce de la sección 7 |

Para la Iteración 4, las decisiones que quedan pendientes son la política de
reemplazo de L2 (4 vías: árbol pseudo-LRU con 3 bits por conjunto es la
respuesta estándar) y la política de inclusión. Write-through en L1 deja esa
segunda decisión barata en los dos sentidos: con las líneas de L1 siempre
limpias, la invalidación hacia atrás que exige la política inclusiva se reduce a
borrar un bit de válido.
