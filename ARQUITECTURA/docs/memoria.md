# Modelo realista de memoria principal

**Proyecto Grupal II — Iteración 2: la línea base sin caché**

Esta iteración construye el sistema de memoria principal que la jerarquía de
caché va a tener debajo: un controlador en su propio dominio de reloj, con la
latencia real de un acceso externo, y el eviction buffer que el enunciado hace
obligatorio.

Su propósito es producir un número. La Iteración 1 midió el procesador con una
memoria que respondía siempre en un ciclo, lo cual es cómodo y falso. Esta
iteración dice cuánto cuesta de verdad un acceso, y con eso queda fijado contra
qué se va a comparar todo lo que venga después.

---

## 1. Qué se agregó y qué no se tocó

| | |
| :--- | :--- |
| Nuevo | `src/cpu/mem_clock_gen.sv` — el dominio de 25 MHz |
| Nuevo | `src/cpu/main_memory.sv` — los 64 KB |
| Nuevo | `src/cpu/eviction_buffer.sv` — el FIFO de líneas sucias |
| Nuevo | `src/cpu/mem_controller.sv` — la máquina de estados de T_mem |
| Nuevo | `src/cpu/mem_system.sv` — los cuatro juntos |
| Nuevo | `tb_mem_clock_gen.sv`, `tb_eviction_buffer.sv`, `tb_mem_system.sv` |
| Modificado | `perf_counters.sv` — contadores de loads y stores por separado |
| Modificado | `tools/tabla_metricas.py` — la proyección sin caché |
| **Sin tocar** | El ISA: ni un opcode, ni un campo, ni un formato de bundle |
| **Sin tocar** | `top.sv` y el pipeline: el subsistema todavía no se conecta |

El ISA no se tocó. El enunciado permite agregar instrucciones de control de
caché (sección 3.1.2), pero esa extensión obliga a renegociar el contrato con el
compilador de CE1108 y nada de esta iteración la necesita.

### 1.1 Por qué el procesador no cambió todavía

El subsistema de memoria queda verificado como bloque, pero no está conectado al
pipeline. Es deliberado y sigue la división que hace el propio enunciado: los
stalls del pipeline son la sección 3.3 y la integración es el trabajo de la
Iteración 3 (sección 7.1.3, *"La integración con el pipeline requiere especial
atención al manejo de stalls"*).

Conectarlo ahora obligaría a agregar la entrada de congelamiento a `fetch.sv` y
a las tres fronteras de segmentación, y a revisar sus cuatro testbenches, todo
antes de tener la caché que es lo que de verdad justifica el stall. Haciéndolo
en su iteración, el cambio llega junto con el motivo.

La consecuencia es que la línea base sin caché de la sección 5 es una
**proyección** calculada sobre contadores reales, no una medición. Eso la
convierte en una predicción falsable: la Iteración 3 va a medir esos mismos
programas con el subsistema conectado, y si el número no cae dentro de las cotas
proyectadas, algo del modelo está mal. Es una propiedad deseable, no una excusa.

Los 31 testbenches del Proyecto I siguen pasando sin que se les tocara una
línea.

---

## 2. Las decisiones de diseño

### D1 — Frecuencia de memoria: 25 MHz (divisor ÷4)

El enunciado deja elegir entre 20 y 50 MHz contra los 100 MHz del procesador, y
la elección fija la penalidad de todo acceso:

```
T_mem = 25 + 7 × (100 MHz / f_mem)   [ciclos de procesador]
```

| f_mem | Razón | T_mem | Observación |
| :---: | :---: | :---: | :--- |
| 50 MHz | 2× | 39 | El extremo rápido; la caché luciría menos |
| **25 MHz** | **4×** | **53** | **Elegida** |
| 20 MHz | 5× | 60 | Máximo contraste, divisor impar |

Se eligió 25 MHz por tres razones. Es el punto medio del rango permitido, así
que no sesga el análisis hacia ningún extremo. El divisor es entero y par, lo
que da un reloj simétrico y, sobre todo, **mesócrono**: cada flanco de memoria
cae exactamente sobre un flanco de procesador, y eso cambia cómo se resuelve el
cruce de dominios (D2). Y una penalidad de 53 ciclos es lo bastante grande como
para que el efecto de la jerarquía de caché se vea con claridad en la Iteración
5, sin llegar al extremo de volver impracticable la simulación de los programas
largos.

El valor vive en una sola línea de `cerbero_defs.svh` (`MEM_CLK_DIV`). Cambiarlo
reconfigura el RTL y los testbenches se ajustan solos, porque comparan contra
`T_MEM` calculado y no contra un 53 escrito a mano.

### D2 — El cruce de dominios se resuelve con habilitación, no con dos relojes

El enunciado pide que el controlador maneje el *crossing* de dominios de reloj.
La respuesta corta es que el cruce se eliminó eligiendo bien la relación entre
los relojes, y la larga vale la pena.

Dos relojes sin relación de fase obligan a sincronizadores de dos biestables y a
convivir con metaestabilidad. Pero el reloj de memoria aquí **sale del de
procesador** por división entera, así que los dos están en fase por
construcción. Técnicamente son mesócronos, y entre dominios mesócronos el cruce
se hace con una señal de habilitación: no hay ventana de metaestabilidad porque
no hay dos flancos independientes.

Por eso `mem_clock_gen.sv` produce dos salidas. `mem_clk` es el reloj lento de
verdad, que existe para que los dos dominios se vean en la forma de onda y para
que el diagrama de bloques diga la verdad. `mem_tick` es un pulso de un ciclo de
procesador, encendido exactamente donde `mem_clk` sube, y **es la señal que
controla toda la lógica**.

La regla que se respeta en todo el subsistema: ningún proceso se sensibiliza a
`mem_clk`. Todo conmuta con `clk` y mira `mem_tick`.

Esto no es una simplificación: es lo que una herramienta de síntesis produce
cuando se le pide un reloj derivado por división entera, porque un reloj generado
en lógica tiene problemas de *skew* que una habilitación no tiene. Y además evita
un error real. Si `main_memory` se sensibilizara a `posedge mem_clk`, ese flanco
llegaría en el mismo instante de simulación en que los registros del controlador
toman su valor nuevo, así que la memoria vería la dirección del ciclo siguiente,
con tiempo de establecimiento cero. En simulación anda; en hardware no.

Esa invariante es la que sostiene toda la temporización, así que
`tb_mem_clock_gen.sv` la verifica ciclo a ciclo en toda la corrida y en los tres
divisores del rango permitido, en vez de mirarla en puntos sueltos. La primera
versión del generador la violaba exactamente una vez, en el primer ciclo después
del reset, y fue el testbench el que lo encontró.

### D3 — El tiempo vive en el controlador, el almacenamiento en la memoria

`main_memory.sv` es el arreglo y nada más. La latencia de primera palabra y la
secuencia del burst están en `mem_controller.sv`.

El motivo es que las dos latencias del enunciado son de naturaleza distinta. La
de primera palabra (25 ciclos de procesador) es el costo de abrir la fila y
atravesar el bus; no depende del arreglo. La del burst (una palabra por ciclo de
memoria) sí es la velocidad del arreglo, y esa está en la memoria: su escritura
solo ocurre en los flancos de memoria, así que no puede aceptar ocho palabras en
un ciclo ni queriendo.

### D4 — Riesgo RAW en memoria: stall

El enunciado obliga a elegir entre stall y store-to-load forwarding para el caso
en que se lee una dirección que todavía espera en un buffer. **Se eligió el
stall.**

El forwarding es lo que hacen los procesadores modernos y el enunciado lo marca
como preferido, pero aquí costaría caro. Una entrada del buffer puede tener solo
algunas palabras sucias (ver D5), así que reenviar no sería entregar la entrada:
sería combinarla con la línea que viene de memoria palabra por palabra, según la
máscara. Eso es un multiplexor de 256 bits más el camino de datos que lo
alimenta, y acelera un caso que ocurre solo cuando el programa lee una línea que
acaba de escribir y que todavía no se drenó.

El stall es una comparación y una espera, y no puede bloquearse
indefinidamente: mientras hay conflicto, el controlador le da el bus al drenado,
el FIFO avanza, y el conflicto se despeja en a lo sumo `EVICT_ENTRIES` drenados.

Esa inversión de prioridad es lo que hace correcta la espera. La regla general es
que la lectura tiene prioridad, porque tiene al procesador esperándola y el
drenado no tiene a nadie. Pero durante un conflicto la prioridad se invierte: si
la lectura la mantuviera, ninguno de los dos avanzaría.

El costo medido está en la sección 4.

### D5 — Cada entrada del buffer lleva una máscara de palabras

Una entrada guarda la línea completa de 32 bytes más ocho bits que dicen cuáles
de sus ocho palabras están sucias.

Con una línea desalojada de L2 estarán las ocho, y la máscara no hará falta. El
caso que la justifica es el de hoy y el de cualquier escritura suelta: sin
máscara habría que **leer** la línea de memoria antes de escribirla, solo para
rellenar las siete palabras que nadie modificó, y eso costaría un T_mem entero
por cada store. Con máscara, el controlador escribe solo lo sucio.

El mismo módulo sirve entonces a los dos usos sin cambios, que es lo que lo deja
listo para la Iteración 4.

### D6 — Las escrituras a la misma línea se fusionan

Si llega un depósito para una línea que ya está encolada, se combina con la
entrada existente en vez de ocupar una nueva.

No es una optimización opcional. Sin fusionar, las dos entradas se drenarían en
orden y la segunda pisaría a la primera, lo cual es correcto; el problema es que
un patrón de escritura secuencial —el más común que existe— llenaría las ocho
entradas en ocho stores y dejaría el buffer inútil justo donde más se usa.

La fusión tiene un caso de borde que importa: si la entrada que se quiere
fusionar es la cabeza y el controlador la está retirando en ese mismo ciclo, el
dato nuevo se escribiría en una entrada que deja de existir en ese flanco, y esa
escritura jamás llegaría a memoria. El módulo excluye la cabeza cuando hay
`head_ack`, y el caso tiene su propia prueba (`tb_eviction_buffer`, caso 8).

### D7 — Ocho entradas en el eviction buffer

El enunciado lo acota entre 4 y 16. Ocho es el medio del rango y potencia de dos,
así que el índice del FIFO es una máscara y no una comparación contra un tope
arbitrario. El valor es el parámetro `EVICT_ENTRIES`.

### D8 — El contrato del protocolo: `req` baja al ver `listo`

`listo` y el regreso del controlador a su estado libre ocurren en el mismo
flanco, así que durante el ciclo de `listo` la máquina ya está libre y vuelve a
mirar `req`. Como no hay forma de distinguir *el pedido viejo que todavía no se
soltó* de *un pedido nuevo a la misma línea*, el que sabe cuál es cuál es el
cliente.

Se probó la alternativa de bloquear dentro del controlador. Funciona, pero le
cuesta un ciclo a toda lectura que siga inmediatamente a otra, y entonces T_mem
deja de ser 53 y pasa a depender de si la lectura anterior estaba pegada. Un
número que cambia según el contexto no se puede contrastar contra el valor
teórico, que es justamente lo que esta iteración produce.

---

## 3. La máquina de estados

El enunciado pide expresamente que los delays se simulen con una máquina de
estados. Son cinco estados y dos contadores.

```
                   ┌─────────────────────────────────────────┐
                   │                                         │
                   ▼                                         │
              ┌─────────┐                                    │
   ┌─────────▶│  LIBRE  │─────────┐                          │
   │          └─────────┘         │                          │
   │               │              │                          │
   │   hay lectura │              │ hay línea sucia          │
   │   sin conflicto              │ y el bus está libre      │
   │               ▼              ▼                          │
   │         ┌──────────┐   ┌──────────┐                     │
   │         │  RD_LAT  │   │  WR_LAT  │   25 ciclos         │
   │         │ 25 ciclos│   │ 25 ciclos│   de procesador     │
   │         └──────────┘   └──────────┘                     │
   │               │              │                          │
   │               ▼              ▼                          │
   │        ┌───────────┐  ┌───────────┐                     │
   │        │ RD_BURST  │  │ WR_BURST  │   7 palabras,       │
   │        │ 28 ciclos │  │ 28 ciclos │   1 por ciclo       │
   │        └───────────┘  └───────────┘   de memoria        │
   │               │              │                          │
   └───────────────┘              └──────────────────────────┘
          listo                        ev_ack
```

### 3.1 De dónde salen los 53 ciclos

| Fase | Duración | Qué pasa |
| :--- | :---: | :--- |
| Arbitraje | 1 ciclo | El controlador acepta la solicitud |
| `RD_LAT` | 24 ciclos | Latencia de primera palabra (25 en total con el arbitraje) |
| `RD_BURST` | 28 ciclos | Las 7 palabras restantes, una por flanco de memoria |
| **Total** | **53 ciclos** | |

El ciclo de arbitraje cuenta como parte de la latencia porque el enunciado mide
los 25 ciclos *"desde que se emite la solicitud"*, y la solicitud está puesta en
ese ciclo. Contarlo aparte daría 54 ciclos de punta a punta: un error de uno que
nadie notaría mirando la forma de onda, y que el testbench sí detecta porque
compara contra el valor calculado.

### 3.2 Por qué el burst se cuenta en ciclos de procesador

La fase de burst dura `7 × 4 = 28` ciclos de procesador, no "7 flancos de
memoria". Los dos criterios mueven las mismas siete palabras, porque en una
ventana de 28 ciclos caen exactamente 7 flancos de memoria sin importar en qué
fase empiece.

La diferencia está en el determinismo. Contando ciclos, T_mem vale 53 siempre.
Contando flancos, valdría entre 50 y 53 según dónde cayera el primero, y una
latencia que cambia sola es imposible de contrastar contra el valor teórico.

Que en 28 ciclos caigan siempre exactamente 7 flancos no se da por obvio:
`tb_mem_clock_gen.sv` lo verifica para las cuatro fases posibles.

### 3.3 La asimetría entre leer y escribir la primera palabra

En una lectura, la palabra 0 sale gratis: la dirección apunta a ella durante toda
la latencia, así que al terminar los 25 ciclos el dato ya está en la salida del
arreglo. En una escritura no hay tal regalo, porque escribir necesita su propio
flanco de memoria.

Si la palabra 0 de una escritura esperara al burst, las ocho palabras
necesitarían ocho flancos y en la ventana solo caben siete: la última no se
escribiría y la línea quedaría con una palabra vieja, en silencio. Por eso la
escritura de la palabra 0 ocurre durante `WR_LAT`, y el burst empieza por la
palabra 1 igual que en una lectura.

---

## 4. Lo que se midió

`make mem_system` corre el subsistema completo y compara contra el valor teórico
calculado desde las constantes del enunciado.

| Medición | Resultado |
| :--- | :--- |
| T_mem de una lectura de línea | **53 ciclos** (teórico: 53) |
| T_mem de una segunda lectura | 53 ciclos |
| T_mem de una lectura encadenada a la anterior | 53 ciclos |
| Aceptar un desalojo en el buffer | **1 ciclo** |
| Lectura con conflicto RAW | **107 ciclos** (53 de drenado + 53 de lectura, más el arbitraje) |
| Lectura con un desalojo pendiente sin conflicto | 53 ciclos (la lectura no espera) |

Dos de estos números son el argumento del eviction buffer. Un desalojo se acepta
en **1 ciclo** en vez de 53, y una lectura con un desalojo pendiente a otra línea
tarda **53 y no 106**: la escritura vieja y la lectura nueva no se encadenan.

El tercero es el costo del stall por RAW: **107 ciclos**, el doble de una lectura
normal. Es la cota superior del mecanismo elegido en D4, y es exactamente lo que
el store-to-load forwarding habría evitado. Ocurre solo cuando el programa lee
una línea que acaba de escribir y que todavía no se drenó.

---

## 5. La línea base sin caché

Esta es la proyección descrita en 1.1: una cuenta sobre contadores que el
hardware midió de verdad, con el modelo de que cada acceso del programa va a
memoria principal.

- **Optimista:** solo los loads detienen el pipeline, `T_mem − 1` ciclos cada
  uno. Supone que el buffer nunca se llena y que ningún load pide una línea
  encolada. Es lo mejor que podría pasar.
- **Pesimista:** todo acceso detiene `T_mem − 1` ciclos. Es lo que ocurriría con
  el buffer siempre lleno, o con una política write-through síncrona sin buffer.

Se reportan las dos a propósito. Dar un solo número aquí sería presentar una
suposición como si fuera una medición.

```
  proyeccion sin cache, con T_mem = 53 ciclos

  programa                 ideal    loads   stores    optimista      x    pesimista      x
  -------------------  ---------  -------  -------  -----------  -----  -----------  -----
  contar_hasta_n.s            99        0       11           99    1.0          671    6.8
  div32_prueba.s            4138       12       12         4762    1.2         5386    1.3
  estadisticas.s             811        8        6         1227    1.5         1539    1.9
  feistel.s                   43       10        2          563   13.1          667   15.5
  fibonacci.s                382        0       47          382    1.0         2826    7.4
  lazo_estres.s           900009   100000   200000      6100009    6.8     16500009   18.3
  sesion_sin_logout.s         34        0        3           34    1.0          190    5.6
  suma_10_15.s                 7        0        0            7    1.0            7    1.0
  suma_simple_emp.s          583       64        1         3911    6.7         3963    6.8
  suma_vliw_emp.s            253       64        1         3581   14.2         3633   14.4
  -------------------  ---------  -------  -------  -----------  -----  -----------  -----
  total                   906359   100158   200083      6114575    6.7     16518891   18.2
```

### 5.1 El margen es de entre 6,7× y 18,2×

Ese es el tamaño del problema que la jerarquía de caché existe para resolver. Un
procesador que ejecutaba un bundle por ciclo pasa a tardar casi siete veces más
en el mejor caso.

También dice qué tan grande es la diferencia entre las dos cotas, y por lo tanto
cuánto importa que el eviction buffer funcione: 6,7× contra 18,2× es un factor de
2,7 que depende enteramente de si las escrituras se absorben o detienen.

### 5.2 El hallazgo que vale la pena llevar a la defensa

Comparar `suma_simple_emp` con `suma_vliw_emp` es el resultado más interesante
de la iteración. Son el mismo cálculo escrito de dos formas, y en la Iteración 1
la versión bien empaquetada era **2,3× más rápida** (253 ciclos contra 583).

Con memoria realista, esa ventaja casi desaparece: 3581 contra 3911 ciclos, es
decir **1,09×**. Y la degradación relativa es *peor* en la versión optimizada,
14,2× contra 6,7×.

No es una paradoja. Las dos versiones hacen los mismos 64 loads, porque el
empaquetado reordena operaciones pero no elimina accesos a memoria. Al bajar el
tiempo de cómputo, lo único que queda es la espera, y el programa pasa a estar
limitado por memoria en vez de por cómputo.

La conclusión práctica para la Iteración 5 es directa: **las optimizaciones del
compilador y la jerarquía de caché no se suman, se habilitan**. Medir el efecto
del empaquetado de bundles sobre una memoria lenta subestima el trabajo del
compilador de CE1108, y medir la caché sobre programas mal empaquetados la
sobreestima, porque los NOP esconden la latencia. Las comparaciones finales hay
que cruzarlas: las dos dimensiones a la vez.

### 5.3 Dónde la proyección puede estar equivocada

Vale la pena anotarlo antes de medirlo, para que la Iteración 3 lo confirme o lo
desmienta:

- **La cota optimista va a quedar corta en `lazo_estres`.** Hace 200 000 stores
  en 900 009 ciclos: un store cada 4,5 ciclos, contra 53 ciclos que tarda cada
  drenado. El buffer de 8 entradas se va a llenar casi de inmediato y el programa
  va a correr cerca de la cota pesimista.
- **La cota pesimista es demasiado pesimista en los programas con pocos
  accesos.** `contar_hasta_n` hace 11 stores en 99 ciclos, de sobra para que el
  buffer los absorba.
- **Ninguna de las dos modela localidad**, porque sin caché no hay localidad que
  modelar. Dos accesos a la misma línea cuestan dos T_mem completos. Esa es
  exactamente la ineficiencia que la Iteración 3 va a eliminar, y por eso la
  mejora medida ahí va a ser mayor que la que estas cotas sugieren.

---

## 6. Cómo reproducir todo esto

```bash
cd src/build

make mem_clock_gen     # la invariante del dominio de reloj, 14 casos
make eviction_buffer   # el FIFO y el riesgo RAW, 48 casos
make mem_system        # T_mem medido contra el teorico, 52 casos
make sim               # las 34 unidades del proyecto
make metricas          # la tabla de arriba, incluida la proyeccion
```

Para cambiar la frecuencia de memoria basta `MEM_CLK_DIV` en
`src/cpu/cerbero_defs.svh`. Los testbenches comparan contra `T_MEM` calculado,
así que se ajustan solos y siguen siendo pruebas.

---

## 7. Limitaciones conocidas

| Limitación | Efecto | Estado |
| :--- | :--- | :--- |
| La lectura de `main_memory` es combinacional, no registrada | En FPGA sería un bloque de RAM con salida registrada y haría falta una etapa más de segmentación en el controlador; T_mem subiría un ciclo de memoria | Documentada (ver el encabezado de `main_memory.sv`) |
| Una escritura cuesta lo mismo que una lectura | Es realista (abrir la fila cuesta igual), pero un controlador real podría tener la fila abierta de un acceso anterior | Documentada |
| El subsistema no está conectado al pipeline | La línea base de la sección 5 es proyección, no medición | Se resuelve en la Iteración 3 |
| Durante `WR_LAT` la palabra 0 se escribe una vez por cada flanco de memoria | Escrituras idénticas, sin efecto a partir de la primera | Documentada (ver `mem_controller.sv`) |

---

## 8. Lo que sigue

| Iteración | Qué agrega | Qué resuelve de aquí |
| :---: | :--- | :--- |
| 3 | Caché L1-D y los stalls del pipeline | Conecta `mem_system` y convierte la proyección en medición |
| 4 | Caché L2, política de inclusión y el write buffer L1→L2 | El segundo cliente del `mem_system` |
| 5 | Benchmarks bajo distintos niveles de optimización | El cruce de 5.2: compilador × jerarquía |

Para la Iteración 3 el trabajo concreto es: agregar la entrada de congelamiento
a `fetch.sv` y a las tres fronteras de segmentación, conectar `cache_stall` a la
entrada `stall` de `perf_counters` (decisión D2 de
[`metricas.md`](metricas.md)), y poner la caché L1-D entre la LSU y este
subsistema.
