# Arquitectura de la jerarquía de memoria

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Sección 1 de la documentación de diseño: decisiones de caché, políticas de escritura, reemplazo e inclusión con su justificación, parámetros de los write buffers obligatorios, y diagramas de la jerarquía y su integración con el pipeline.

Complementos: [organizacion.md](organizacion.md) (microarquitectura), [analisis-rendimiento.md](analisis-rendimiento.md) (medición y resultados). El detalle de cada iteración, con los errores encontrados, está en [metricas.md](metricas.md), [memoria.md](memoria.md) y [cache.md](cache.md).

---

## 1. Parámetros

| Nivel | Capacidad | Asociat. | Línea | Conjuntos | Hit time | Escritura | Estado |
|---|---|---|---|---|---|---|---|
| L1-D | 4 KB | 2 vías | 32 B | 64 | 1 ciclo | write-through, no-write-allocate | implementado |
| L2 unificada | 16 KB | 4 vías | 32 B | 128 | 8 ciclos | write-back (lo exige el enunciado) | Iteración 4 |
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
      │  L2  16 KB, 4 vías             │  ◄── Iteración 4
      │  write-back, NINE              │
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

Mientras la L2 no exista, el write buffer y el camino de fallo van directo al controlador. El hueco ya está preparado: el write buffer habla el mismo protocolo (`req` / `listo`, línea de 256 bits más máscara de 32) que hablará con la L2.

---

## 3. Decisiones y su justificación

### D1. Escritura de L1-D: write-through

**Alternativas:** write-back o write-through.

**Razón.** La L2 del enunciado es obligatoriamente write-back. Si L1 también lo fuera, habría líneas sucias en dos niveles a la vez y harían falta tres cosas: invalidación hacia atrás con recogida del dato cuando L2 expulsa algo que L1 tiene sucio, un orden de escritura definido hacia memoria, y una definición de "drenado" al final del programa. Con write-through L1 nunca tiene una línea sucia, la L2 es la única dueña de los datos sucios, y los tres problemas desaparecen.

El profesor lo planteó en ambos sentidos: write-through es más simple pero complica la inclusión, y write-back es más complicado. Aquí la complicación de la inclusión se evita con NINE (D6), así que write-through se queda sin su desventaja principal.

**Costo medido.** Cada store cruza la frontera, y eso es lo que absorbe el write buffer. De 11 programas, **10 pierden cero ciclos** por buffer lleno. El único que paga es `recorrido_cache.s`, escrito a propósito para saturarlo: 5035 de 17 706 ciclos.

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

**Costo medido: un (1) ciclo** en los 11 programas, en `lazo_estres.s`. Eso es todo lo que el forwarding habría ahorrado.

```systemverilog
assign espera_raw = falla_lectura && wb_conflicto;
assign mem_req    = (estado == ESPERA) ? (falla_lectura && !wb_conflicto) : !mem_listo;
```

### D5. Reemplazo de L2: pendiente (Iteración 4)

La L2 es de 4 vías, así que el bit de D3 no sirve. Opciones: LRU verdadero con edades de 2 bits por vía (1024 bits en total) o pseudo-LRU de árbol (384 bits). Se presentará al grupo con su justificación antes de implementarla, igual que D1 a D4.

### D6. Inclusión: NINE (Non-Inclusive, Non-Exclusive)

El enunciado pide justificarla explícitamente, dado que el proyecto no tiene coherencia multinúcleo. Tres argumentos:

**1. La propiedad que garantiza no tiene consumidor.** La inclusión existe para que un agente externo pueda preguntarle solo a la L2 si un dato está cacheado en alguna parte. Eso es lo útil en un multinúcleo: el snooping consulta el nivel compartido sin molestar a las L1 privadas. CERBERO-1 tiene un núcleo y ningún otro agente que acceda a memoria, así que esa pregunta no se hace nunca.

**2. Lo que costaría.** Mantenerla obliga a **invalidación hacia atrás**: cuando L2 expulsa una línea tiene que avisarle a L1, porque si no L1 quedaría con una copia de algo que L2 ya no tiene. Eso es un camino de invalidación de L2 hacia L1, un puerto más en los arreglos de etiquetas de L1 para atenderlo, y una decisión de qué hacer si esa invalidación llega en el mismo ciclo en que L1 sirve un acierto a esa línea. Lógica nueva con carreras propias, al servicio de una garantía que nadie usa.

**3. Lo que NINE no rompe.** La duda legítima es la corrección: ¿puede leerse una versión vieja? No, y la razón es D1. Como **L1 es write-through, L1 nunca tiene una línea sucia**, así que toda copia en L1 es idéntica a la de abajo o no existe:

- Si L2 expulsa una línea que L1 tiene, la copia de L1 sigue siendo válida: no hay nada más nuevo en ningún lado.
- Si L1 expulsa una línea, no hay nada que escribir hacia abajo.
- El único dato en vuelo vive en el write buffer, y eso lo resuelve D4 con el stall.

En una línea: **write-through es lo que hace seguro a NINE, y NINE es lo que le quita a write-through su desventaja de complicar la inclusión.** Las dos decisiones se sostienen mutuamente, y por eso se tomaron juntas. El profesor recomendó no usar inclusiva porque complica más; esta es la razón de por qué aquí además no aporta nada.

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

Lo que de verdad baja la presión no es la profundidad sino la **fusión**: varios stores a la misma línea ocupan una sola entrada, así que un recorrido con localidad espacial mete 8 stores en una entrada. La medición lo confirma: 10 de 11 programas pierden cero ciclos, y el único que sufre es el que escribe 128 líneas distintas seguidas, patrón que ninguna profundidad salva.

**Por qué 8 abajo (la mitad del rango).** La L2 es write-back, así que solo genera tráfico cuando **expulsa** una línea sucia, no en cada escritura; con 16 KB y 4 vías las expulsiones son esporádicas frente al flujo de stores, y 16 entradas serían estado sin uso. Queda **sujeto a revisión en la Iteración 4**, cuando se pueda medir en vez de razonar; el contador para verlo ya está puesto.

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
| Contadores de métricas | implementados, 21 contadores |
| **Caché L2 unificada** | **Iteración 4** |
| Coherencia / inclusión | política decidida (NINE, D6); se implementa con la L2 |
| Reemplazo de L2 | decisión pendiente (D5) |

1. **La geometría de L1 es parametrizable en capacidad, no en asociatividad.** `l1_dcache.sv` implementa exactamente dos vías; pedirle otra aborta la elaboración con un mensaje explícito, en vez de simular algo incorrecto. La generalización a N vías llega con la L2 de 4 vías. Por eso el barrido varía capacidad de 512 B a 16 KB a asociatividad fija.
2. **El eviction buffer está dimensionado por razonamiento, no por medición**, porque la L2 que lo alimentará no existe. Se revisa en la Iteración 4.
3. **No hay L1 de instrucciones**, así que las métricas de caché cubren solo accesos a datos.

```bash
cd src/build
make clean && make all     # 35 unidades
make l1_dcache             # la caché: 50 casos
make mem_system            # T_mem contra el RTL
make ejemplos              # 41 casos, contadores contra aritmética
```
