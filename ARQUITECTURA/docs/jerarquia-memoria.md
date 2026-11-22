# Arquitectura de la jerarquía de memoria

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Sección 1 de la documentación de diseño: decisiones de caché, políticas de escritura, reemplazo e inclusión con su justificación, parámetros de los write buffers obligatorios, y diagramas de la jerarquía y su integración con el pipeline.

Complementos: [organizacion.md](organizacion.md) (microarquitectura), [analisis-rendimiento.md](analisis-rendimiento.md) (medición y resultados). El detalle de cada iteración, con los errores encontrados, está en [metricas.md](metricas.md), [memoria.md](memoria.md) y [cache.md](cache.md).

---

## 1. Parámetros

| Nivel | Capacidad | Asociat. | Línea | Conjuntos | Hit time | Escritura | Estado |
|---|---|---|---|---|---|---|---|
| L1-D | 4 KB | 2 vías | 32 B | 64 | 1 ciclo | write-through, no-write-allocate | implementado |
| L2 unificada | 16 KB | 4 vías | 32 B | 128 | 8 ciclos | write-back, write-allocate | implementado |
| Memoria principal | 64 KB | n/a | n/a | n/a | 53 ciclos | n/a | implementado |

No hay L1 de instrucciones, por indicación del profesor: corre un programa a la vez, así que no agregaría nada medible.

| Parámetro del dominio de memoria | Valor | Macro |
|---|---|---|
| Reloj del procesador / de memoria | 100 MHz / 25 MHz | `MEM_CLK_DIV = 4` |
| Ciclos hasta la primera palabra | 25 | `MEM_FIRST_WORD` |
| Palabras por línea | 8 | `LINE_WORDS` |
| **T_mem (línea completa)** | **53 ciclos** | `T_MEM = 25 + 7 × 4` |
| Write buffer L1 a L2 | 8 entradas | `WB_ENTRIES` |
| Eviction buffer L2 a memoria | 8 entradas | `EVICT_ENTRIES` |

Los 53 ciclos no son supuestos: `tb_mem_system.sv` mide el intervalo real entre petición y respuesta y lo compara contra la macro, así que un cambio de divisor o latencia falla la prueba antes de llegar a un informe.

---

## 2. Diagrama de la jerarquía

```
      ┌────────────────────────────────┐
      │  PIPELINE  IF ID EX MEM WB     │
      └──────┬─────────────────────▲───┘
             │ dir, dato, be       │ stall
      ┌──────▼─────────────────────┴───┐
      │  L1-D  4 KB, 2 vías, 64 conj.  │
      │  write-through, no-write-      │
      │  allocate, LRU                 │
      └──┬──────────────────────┬──────┘
  fallo  │                      │ todo store
  de     │                      ▼
  lectura│         ┌────────────────────────┐
         │         │ WRITE BUFFER L1 a L2   │
         │         │ 8 entradas: línea +    │
         │         │ 256 b datos + 32 b de  │
         │         │ máscara; fusiona       │
         │         └────────────┬───────────┘
      ┌──▼──────────────────────▼──────┐
      │  L2  16 KB, 4 vías, LRU edades │  ──► invalidación hacia
      │  write-back, inclusiva         │      atrás sobre L1-D
      └──┬──────────────────────┬──────┘
         │                      │ línea sucia expulsada
         │         ┌────────────▼───────────┐
         │         │ EVICTION BUFFER        │
         │         │ 8 entradas, igual      │
         │         └────────────┬───────────┘
      ┌──▼──────────────────────▼──────┐
      │  CONTROLADOR  FSM de 5 estados │
      │  arbitra lectura vs. drenado   │
      └──────────────┬─────────────────┘
                     │ mem_tick (÷4)
      ┌──────────────▼─────────────────┐
      │  MEMORIA PRINCIPAL  64 KB      │
      │  25 MHz, ráfaga de 8 palabras  │
      └────────────────────────────────┘
```

El árbitro de L2 (`l2_arbiter.sv`) atiende por turnos los fallos de lectura de L1 y el drenado del write buffer, porque la L2 tiene un solo puerto. Los dos hablan el mismo protocolo (`req` / `listo`, línea de 256 bits más máscara de 32).

Para medir cuánto aporta la L2 existe una configuración sin ella: compilando con `-DCERBERO_SIN_L2`, `top.sv` conecta el árbitro directo a memoria principal (lecturas por `mem_system`, escrituras al eviction buffer). Es el mismo RTL con un nivel menos, no un modelo aparte, y es la línea base de [analisis-rendimiento.md](analisis-rendimiento.md) §8.

---

## 3. Decisiones y su justificación

### D1. Escritura de L1-D: write-through

**Alternativas:** write-back o write-through.

**Razón.** La L2 del enunciado es obligatoriamente write-back. Si L1 también lo fuera, habría líneas sucias en dos niveles a la vez y harían falta tres cosas: invalidación hacia atrás con recogida del dato cuando L2 expulsa algo que L1 tiene sucio, un orden de escritura definido hacia memoria, y una definición de "drenado" al final del programa. Con write-through L1 nunca tiene una línea sucia, la L2 es la única dueña de los datos sucios, y los tres problemas desaparecen.

El profesor lo planteó en ambos sentidos: write-through es más simple pero complica la inclusión, y write-back es más complicado. Aquí pasa lo contrario de lo que se temía: como L1 nunca tiene una línea sucia, la invalidación hacia atrás que exige la inclusión (D6) se reduce a apagar un bit de válido. No hay dato que recoger antes de invalidar.

**Costo medido.** Cada store cruza la frontera, y eso es lo que absorbe el write buffer. En la Iteración 3, sin L2, de 11 programas **10 perdieron cero ciclos** por buffer lleno, y el único que pagó fue `recorrido_cache.s`, escrito a propósito para saturarlo: 5035 de 17 706 ciclos. Con la L2 el resultado se mantiene en los 14 programas del barrido: 13 pierden cero y `recorrido_cache.s` pierde 6665 de 13 312. Sube porque la L2 es write-allocate: cada una de las 129 líneas que drena el buffer falla en L2 y obliga a traerla de memoria antes de escribirla, cosa que sin L2 no pasa (ver [analisis-rendimiento.md](analisis-rendimiento.md) §8).

**Lo que obligó a implementar.** Un `SB` o `SH` escribe 1 o 2 bytes, y con write-through ese store parcial tiene que viajar sin arrastrar los bytes vecinos, que pueden no estar en la caché. Por eso cada entrada del buffer lleva una **máscara de 32 bits, uno por byte**, y la memoria tiene escritura habilitada por byte. Sin la máscara, un `SB` grabaría 31 bytes de basura.

### D2. Fallo de escritura: no-write-allocate

**Razón.** Con write-through, write-allocate no tiene sentido: traer una línea de 53 ciclos para después escribirla hacia abajo de todos modos paga la latencia completa sin ganar nada. Write-allocate se justifica cuando la escritura se queda arriba, es decir con write-back. Esta pareja es la combinación clásica precisamente por eso.

**Peor caso, medido.** Un programa que escribe una zona y luego la lee falla dos veces. En `recorrido_cache.s` los 128 fallos de escritura no cargan ninguna línea, así que la primera pasada de lectura paga otros 128 fallos de arranque. Sigue costando menos que traer 128 líneas de 53 ciclos para escribirlas hacia abajo igual.

**Corolario comprobable.** Con la caché vacía ningún store puede acertar, y `tb_ejemplos.sv` lo exige: aciertos de escritura = 0, exacto.

### D3. Reemplazo de L1-D: LRU exacto

**Razón.** Con dos vías, LRU exacto cuesta **un bit por conjunto**: dice cuál vía se usó de última, y la víctima es la otra. Son 64 bits para toda la caché, sin aproximación ni árbol ni contadores de edad. A ese precio, FIFO o aleatorio ahorrarían nada y perderían la localidad temporal.

```systemverilog
assign via_victima = ~mru[conjunto];
```

Es un argumento sobre esta asociatividad, no sobre LRU en general: con 4 vías el bit único no alcanza y haría falta LRU con edades o pseudo-LRU de árbol. Esa decisión corresponde a la L2.

**Comprobación.** `tb_l1_dcache.sv` carga tres líneas del mismo conjunto en orden conocido y verifica cuál se expulsa. Y `recorrido_cache.s` lo comprueba desde el otro lado: sus 384 aciertos exactos solo salen si el LRU conserva precisamente las líneas que caben.

### D4. Riesgo RAW en memoria: stall

**Alternativas:** store-to-load forwarding o stall.

**Razón.** El forwarding desde el buffer no es el del pipeline: habría que comparar la dirección contra las 8 entradas y resolver la **máscara de bytes** de cada coincidencia, porque una entrada puede tener solo 2 de los 4 bytes pedidos y el dato correcto sería una mezcla de buffer y memoria. Con fusión activa, varias entradas pueden aportar bytes distintos de la misma línea. Eso es un multiplexor por byte con prioridad por antigüedad en el camino crítico de un acierto de un ciclo.

El profesor dijo que el stall es aceptable si el forwarding no se puede implementar. Aquí no es que no se pudo: es que cuesta menos que no equivocarse en el forwarding.

**Costo medido: un (1) ciclo** en los 11 programas de la Iteración 3, en `lazo_estres.s`, y **cero** en las 154 corridas del barrido de la Iteración 5. El peor caso medido sale de código de NOVA que lee la línea que acaba de escribir: `estres_escritura` pierde **7749 ciclos** con `-O0` y `-O1`, el 6,8 % de su stall, y 69 con `-O2`, porque el compilador separa los accesos ([analisis-rendimiento.md](analisis-rendimiento.md) §12.1). Ese es el techo de lo que el forwarding habría ahorrado; el resto del stall de ese programa no lo toca el forwarding.

```systemverilog
assign espera_raw = falla_lectura && wb_conflicto;
assign mem_req    = (estado == ESPERA) ? (falla_lectura && !wb_conflicto) : !mem_listo;
```

### D5. Reemplazo de L2: LRU exacto con edades

**Alternativas:** LRU exacto con edades de 2 bits por vía (8 bits por conjunto, 1024 en total), pseudo-LRU de árbol (3 bits por conjunto, 384 en total) o aleatorio.

**Razón.** Con cuatro vías el bit único de D3 ya no alcanza, pero el ahorro del pseudo-LRU son 640 bits, el 0,45 % del estado de la L2 (datos y etiquetas suman unos 142 000 bits). A esa escala el costo no decide. Lo que decide es la validación: la metodología del proyecto se apoya en **predecir a mano el número exacto de aciertos**, y con pseudo-LRU ese número deja de ser calculable.

**Cómo está hecho.** `l2_cache.sv` guarda una edad de `log2(WAYS)` bits por vía, con inicialización escalonada: las edades de un conjunto son siempre una permutación de 0 a 3, así que la víctima está siempre bien definida. Al acertar, la vía usada pasa a edad 0 y envejecen solo las que eran más jóvenes que ella.

**Comprobación.** `tb_l2_cache.sv` caso [7] fija el orden de expulsión, y `patron_reuso.s` lo confirma desde un programa: 256 aciertos de L2 exactos en la segunda pasada, el número que se calcula sin simular (ver [analisis-rendimiento.md](analisis-rendimiento.md) §11).

### D6. Inclusión: inclusiva, con invalidación hacia atrás

**Alternativas:** inclusiva, NINE (Non-Inclusive, Non-Exclusive) o exclusiva.

**Historia de la decisión.** Hasta la Iteración 3 la política acordada era NINE, y el profesor recomendó no usar inclusiva porque complica más. La Iteración 4 se implementó inclusiva, y para la Iteración 5 el grupo decidió quedarse con ella en vez de volver atrás. Esta sección explica por qué, y qué dice la medición sobre lo que cuesta.

**1. Lo que cuesta implementarla aquí es poco, gracias a D1.** La inclusión obliga a que cuando L2 expulsa una línea, L1 la suelte también. En general eso exige recoger el dato si la copia de L1 está sucia. Aquí L1 es write-through y nunca tiene una línea sucia, así que invalidar es solo **apagar el bit de válido**:

```systemverilog
if (inv_req) begin
    if (inv_hit_v0) valido[0][inv_conjunto] <= 1'b0;
    if (inv_hit_v1) valido[1][inv_conjunto] <= 1'b0;
end
```

El único caso delicado es que la invalidación llegue en el mismo ciclo en que L1 termina de rellenar esa misma línea. Ahí gana la invalidación, porque L2 ya no la tiene. `tb_l1_dcache.sv` caso [INV] prueba que la línea invalidada deja de acertar y que invalidar otra línea no toca esta. El caso del mismo ciclo está resuelto en `l1_dcache.sv` pero no tiene prueba propia (ver §6).

**2. Lo que se gana es una propiedad comprobable.** Con inclusión, toda línea de L1 está también en L2. Eso no tiene consumidor en un sistema de un núcleo (no hay snooping que la aproveche), pero es un invariante que el testbench puede verificar, y obliga a implementar y probar el mecanismo de coherencia entre niveles que el enunciado pide contar (§5.2: invalidaciones hacia atrás ejecutadas). Con NINE ese contador sería siempre cero por construcción, y la métrica que el enunciado pide no mediría nada.

**3. Lo que cuesta en rendimiento, medido.** El contador de invalidaciones ejecutadas sobre L1-D se corrió en las 10 configuraciones con L2 del barrido:

| L2 / L1 | Configuraciones | Invalidaciones |
|---|---|---|
| 4× o más | base (16 KB / 4 KB), L2 de 32 y 64 KB, L1 de 512 B a 2 KB | **0** en los 14 programas |
| 2× | L2 de 8 KB; L1 de 8 KB | 0, y 2 en `patron_aleatorio` con L1 de 8 KB |
| 1× | L2 de 4 KB; L1 de 16 KB | hasta 897 (`patron_stride`) |

**Con la geometría del enunciado, la inclusión no cuesta nada en el barrido**: la L2 tiene cuatro veces las líneas de L1 y casi nunca expulsa por capacidad algo que L1 todavía tenga. Por capacidad, el costo aparece solo cuando L1 se acerca al tamaño de L2. Con L2 de 4 KB, `patron_aleatorio` pierde 20 aciertos de L1 (de 132 a 112) por líneas que la L2 le obligó a soltar.

**El conflicto sí la alcanza con la L2 de 16 KB.** La relación de tamaños no protege cuando más de cuatro líneas que L1 está usando caen en el mismo conjunto de L2: la L2 tiene que expulsar una aunque le sobre capacidad. `estres_conflicto` con `-O2`, un programa de NOVA con ocho líneas separadas 4 KB, produce **24 invalidaciones**, y la L1 acierta exactamente 24 lecturas menos que sin L2 (2722 contra 2746, un 0,9 %). Es el costo más alto medido con la geometría del proyecto, y sale de un patrón escrito para provocarlo ([analisis-rendimiento.md](analisis-rendimiento.md) §12.1).

La medición también muestra la consecuencia estructural de la inclusión: **la capacidad útil de la jerarquía es la de L2, no la suma**. En `patron_aleatorio`, agrandar L1 de 4 a 16 KB con L2 de 16 KB mueve aciertos de L2 a L1 (aciertos L1 + L2: 359, 356, 357) sin bajar los fallos de L2 (665 a 667). Con NINE la jerarquía podría guardar algo más; con esta relación de tamaños, la diferencia no se vería.

**Por qué no se volvió a NINE.** El argumento de NINE era que la inclusión complica y no aporta. Lo primero resultó cierto una vez: la invalidación vino rota en la Iteración 4 (comparaba una etiqueta reconstruida con bits fuera de rango y no invalidaba nunca) y su prueba no lo detectaba. Ya está arreglada y la prueba ahora comprueba el efecto. Con el mecanismo funcionando y su costo medido (cero en el barrido, y un 0,9 % de los aciertos de L1 en el peor patrón de conflicto), volver a NINE era borrar lógica probada para recuperar, en el mejor caso, 24 aciertos de L1 en un programa escrito para perderlos.

---

## 4. Los write buffers obligatorios

Los dos son instancias del mismo módulo, `eviction_buffer.sv`, porque hacen el mismo trabajo en lugares distintos.

| | Write buffer L1 a L2 | Eviction buffer L2 a memoria |
|---|---|---|
| Instancia | `top.sv : u_write_buffer` | `mem_system.sv : u_evict` |
| Rango del enunciado | 2 a 8 | 4 a 16 |
| **Escogido** | **8** | **8** |
| Entrada | etiqueta + 256 b datos + 32 b máscara | igual |
| Fusión por línea / conflicto RAW | sí / sí | sí / sí |

**Por qué 8 arriba (el máximo).** Un store entra al buffer hasta una vez por ciclo; drenar una línea cuesta 53. La tasa de llegada puede ser 53 veces la de salida, así que ninguna profundidad razonable evita que se llene ante una ráfaga sostenida de stores a líneas distintas. Lo que la profundidad compra es tolerancia a ráfagas cortas, que es el caso común, y ahí más entradas es estrictamente mejor sin costo de latencia.

Lo que de verdad baja la presión no es la profundidad sino la **fusión**: varios stores a la misma línea ocupan una sola entrada, así que un recorrido con localidad espacial mete 8 stores en una entrada. La medición lo confirma: 10 de 11 programas pierden cero ciclos, y el único que sufre es el que escribe 128 líneas distintas seguidas, patrón que ninguna profundidad salva. Los programas de NOVA de la Iteración 5 llevan ese caso al extremo: `estres_buffers` hace un store por línea sobre 32 KB y pasa el 56 % de su ejecución con el buffer lleno (296 364 ciclos con `-O2`), porque con la L2 write-allocate cada entrada que drena trae su línea de memoria ([analisis-rendimiento.md](analisis-rendimiento.md) §12.1).

**Por qué 8 abajo (la mitad del rango).** La L2 es write-back, así que solo genera tráfico cuando **expulsa** una línea sucia, no en cada escritura; con 16 KB y 4 vías las expulsiones son esporádicas frente al flujo de stores, y 16 entradas serían estado sin uso.

**Medido en la Iteración 5.** El contador `stall_por_evict` cuenta los ciclos en que la L2 quiere expulsar y el eviction buffer está lleno. En las 140 corridas del barrido con L2 (10 configuraciones × 14 programas) marca **0**. La L2 absorbe los stores: `recorrido_cache.s`, que escribe 128 líneas distintas, se las queda sucias en la L2 y no expulsa ninguna antes del final.

La contraprueba sale de la configuración sin L2, donde cada store baja directo al eviction buffer: ahí el mismo programa pierde **5959 ciclos** con el buffer lleno. El buffer de 8 no es el que alcanza por suerte; es la L2 write-back la que le quita la presión, que es justo el argumento del párrafo anterior. Bajarlo a 4 probablemente tampoco costaría ciclos, pero no se midió con 4, así que se queda en 8, dentro del rango del enunciado.

**La fusión y su carrera.** El controlador copia la línea al empezar a drenarla, así que un store que se fusione después dentro de esa entrada se pierde 53 ciclos más tarde, en silencio. La ventana peligrosa empieza en el ciclo en que el controlador **decide** drenar, cuando todavía está en `LIBRE`:

```systemverilog
assign drenando = ((estado == LIBRE) && puede_drenar) ||
                  (estado == WR_LAT) || (estado == WR_BURST);
```

El buffer recibe eso como `head_ocupada` y se niega a fusionar sobre la cabeza. Hay regresiones en `tb_eviction_buffer.sv` (caso 10) y `tb_mem_system.sv` (caso 8).

---

## 5. Integración con el pipeline

La caché ocupa el lugar exacto que tenía `dmem.sv`, con los mismos puertos que la LSU ya usaba más uno de salida: `stall`. Eso mantiene lo que el profesor pidió conservar: no se tocó la ISA, ningún programa del Proyecto I se recompiló, y los testbenches de ese proyecto siguen corriendo.

```
     ID               EX                MEM          WB
 ┌─────────┐   ┌───────────────┐   ┌──────────┐  ┌─────────┐
 │ decode  │   │ ALU0  ALU1    │   │ load_    │  │ regfile │
 │ regfile │──▶│ LSU           │──▶│ align    │─▶│ PSW     │
 │ BRU     │   │ S3  BRU       │   │          │  │         │
 └─────────┘   └──────┬────────┘   └──────────┘  └─────────┘
                      │ dir, dato, be
               ┌──────▼────────┐
               │  l1_dcache    │
               └──────┬────────┘
                      │ stall
     ┌────────────────┴──────────────────┐
  se CONGELA (retiene)            se VACÍA (burbuja)
  PC, imem, reg_if_id,            EX y MEM no cometen
  reg_id_ex
```

**Qué se congela y qué se vacía.** Aguas arriba se retiene: el PC no avanza, la `imem` retiene su bundle, y `reg_if_id` y `reg_id_ex` mantienen lo que tienen. Aguas abajo se inyecta burbuja: EX y MEM no cometen nada, no se escribe el banco, no se registran fallas, no se cuentan instrucciones.

Congelar `reg_if_id` no era suficiente, porque `imem.sv` tiene **salida registrada**: es la otra mitad de la frontera IF/ID. Congelando solo el registro, desde el segundo ciclo de stall el PC y el bundle se desincronizaban, se perdía un bundle y el siguiente se ejecutaba dos veces, en silencio. Lo encontró `tb_top`. El arreglo es que `imem.sv` también reciba `stall`. Por eso el congelamiento se documenta como propiedad de **toda la frontera** y no de un registro.

**La regla que sostiene todo.** Hay una sola invariante:

> Un efecto solo ocurre cuando el bundle avanza. Nada se escribe, se cuenta, se empuja a un buffer ni se registra como falla mientras `stall` esté levantado.

```systemverilog
assign ex_commit = ex_valid && !cache_stall;
if (!ex_commit) ex_wen = '0;                              // no escribe registros
if (!ex_commit) begin ex_fault = 5'd0; ex_cause = '0; end // no registra fallas
assign wb_push = es_store && !stall;                      // no empuja al buffer
```

Sin ella, un store en un ciclo de stall se empujaría al buffer una vez por ciclo de espera.

**Cuándo la memoria está drenada.** Un store ya no llega a memoria en el ciclo en que se ejecuta, así que revisar la memoria al llegar a `HALT` daría por perdidos stores en camino. `top.sv` publica una señal que los testbenches esperan antes de comparar, y son ciclos del arnés que no entran en ninguna métrica:

```systemverilog
assign mem_drenada = halted && !id_valid && !ex_valid && !mem_valid
                  && !cache_stall && wb_vacio && mem_sys_ev_vacio && !mem_sys_ocupado;
```

---

## 6. Estado y limitaciones

| Elemento del enunciado | Estado |
|---|---|
| L1-D con políticas elegidas | implementado, 50 casos en `tb_l1_dcache.sv` |
| Write buffer obligatorio | implementado, 8 entradas, con fusión y detección RAW |
| Eviction buffer obligatorio | implementado, 8 entradas |
| Mecanismo para el riesgo RAW | implementado (stall) |
| Stalls por fallos | implementado, con desglose por causa |
| Memoria principal realista | implementado, 53 ciclos medidos contra el RTL |
| Contadores de métricas | implementados, 31 contadores (incluye stall por acierto y por fallo de L2) |
| Caché L2 unificada | implementada, 16 KB, 4 vías, write-back, write-allocate |
| Coherencia / inclusión | inclusiva con invalidación hacia atrás (D6), con contador |
| Reemplazo de L2 | LRU exacto con edades (D5) |
| Línea base sin L2 | `-DCERBERO_SIN_L2`, mismo RTL |

1. **La L1 es parametrizable en capacidad, no en asociatividad.** `l1_dcache.sv` implementa exactamente dos vías (compara dos etiquetas y guarda el LRU como un bit). ⚠️ No tiene guardia: compilarla con `L1D_WAYS` distinto de 2 no aborta, sino que **se cuelga** leyendo `x` de una vía que no existe. La L2 sí es de N vías y sí tiene guardias (`l2_cache.sv` exige potencias de dos, `top.sv` exige `L2_BYTES = L2_SETS × L2_WAYS × 32`). Por eso el barrido varía la capacidad de L1 a 2 vías fijas.
2. **El caso de invalidación en el mismo ciclo que el relleno** está resuelto en `l1_dcache.sv` (gana la invalidación) pero no tiene prueba propia.
3. **No hay L1 de instrucciones**, así que las métricas de caché cubren solo accesos a datos. La L2 es unificada en estructura pero solo recibe tráfico de datos.

```bash
cd src/build
make clean && make all     # todas las unidades
make l1_dcache             # la L1, incluido el caso [INV]
make l2_cache              # la L2 y su LRU por edades
make mem_system            # T_mem contra el RTL
make patrones              # los cuatro patrones, con oráculo exacto
make analisis              # el barrido de la jerarquía, tablas y gráficos
```
