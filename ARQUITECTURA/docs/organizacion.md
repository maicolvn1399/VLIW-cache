# Organización y microarquitectura del sistema extendido

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Sección 2 de la documentación de diseño: organización interna en SystemVerilog, diagramas de bloques de los componentes principales con sus interconexiones, y flujo de datos e instrucciones.

Complementos: [jerarquia-memoria.md](jerarquia-memoria.md) (políticas) y [analisis-rendimiento.md](analisis-rendimiento.md) (resultados). El pipeline base y las unidades funcionales del Proyecto I están en [microarchitecture.md](microarchitecture.md); aquí se repite solo lo necesario para ubicar lo nuevo.

---

## 1. Módulos

26 módulos RTL en `src/cpu/`, 6911 líneas, con 38 unidades de prueba. Los ocho del Proyecto II van en negrita.

| Módulo | Qué es | Líneas | Testbench |
|---|---|---|---|
| `top.sv` | el sistema completo: instancia y conecta todo | 1192 | `tb_top`, `tb_patrones` (24), `tb_programa` |
| **`l1_dcache.sv`** | **caché L1-D, 4 KB, 2 vías** | **478** | `tb_l1_dcache` (55) |
| `perf_counters.sv` | 31 contadores de rendimiento | 478 | `tb_perf_counters` (95) |
| **`l2_cache.sv`** | **caché L2 unificada, 16 KB, N vías** | **463** | `tb_l2_cache` (37) |
| **`mem_controller.sv`** | **FSM de 5 estados del acceso a memoria** | **363** | `tb_mem_system` (59) |
| `lsu.sv` / `alu.sv` / `bru.sv` | S2 / S0 y S1 / S4 | 331 / 321 / 311 | los suyos |
| **`eviction_buffer.sv`** | **FIFO de líneas con máscara y fusión** | **249** | `tb_eviction_buffer` (63) |
| `psw_fault_unit.sv` / `key_vault.sv` | fallas y PSW / bóveda | 250 / 239 | los suyos |
| `dmem.sv` | memoria de datos del Proyecto I (ya no la usa `top`) | 208 | `tb_dmem` |
| **`mem_system.sv`** | **envoltorio: reloj, controlador, buffer, memoria** | **196** | `tb_mem_system` |
| `imem.sv` / `dispatch.sv` / `regfile.sv` | instrucciones / etapa ID / banco | 183 / 179 / 175 | los suyos |
| `crypto_unit.sv` / `short_alu.sv` / `load_align.sv` | S3 Feistel4 / S3 corta / MEM | 163 / 160 / 151 | los suyos |
| `reg_id_ex.sv` / `reg_ex_mem.sv` / `reg_if_id.sv` | las tres fronteras | 136 / 132 / 88 | los suyos |
| `fetch.sv` | PC y selección de destino | 127 | `tb_fetch` (50) |
| **`main_memory.sv`** | **64 KB, escritura habilitada por byte** | **120** | `tb_mem_system` |
| **`l2_arbiter.sv`** | **un solo puerto de L2 para la L1 y el write buffer** | **113** | `tb_l2_arbiter` (24) |
| **`mem_clock_gen.sv`** | **divisor ÷4, genera `mem_tick`** | **105** | `tb_mem_clock_gen` (14) |

`dmem.sv` se conserva aunque `top.sv` ya no lo instancie: sigue siendo el modelo de memoria de un ciclo contra el cual se comparan las mediciones.

---

## 2. Diagrama de bloques

```
                                top.sv
┌──────────────────────────────────────────────────────────────────────────┐
│  IF            ID              EX              MEM         WB            │
│ ┌───────┐  ┌───────────┐  ┌──────────────┐  ┌────────┐  ┌─────────┐      │
│ │ fetch │  │ dispatch  │  │ alu (S0)     │  │ load_  │  │ regfile │      │
│ │  PC   │─▶│ regfile rd│─▶│ alu (S1)     │─▶│ align  │─▶│ psw     │      │
│ │ imem  │  │ bru       │  │ lsu (S2)     │  │        │  │         │      │
│ └───┬───┘  └─────┬─────┘  │ short_alu    │  └───┬────┘  └────┬────┘      │
│     │            │        │ key_vault    │      │            │           │
│ reg_if_id   reg_id_ex     │ crypto_unit  │  reg_ex_mem        │           │
│     │            │        │ bru (S4)     │      │            │           │
│     ▼ stall      ▼ stall  └──┬────────┬──┘      │            │           │
│  (retiene)    (retiene)      │  dir, dato, be, we            │           │
│                     ┌────────▼────────▼──┐                   │           │
│                     │     l1_dcache      │                   │           │
│                     │ etiqueta[2][64] 21b│                   │           │
│                     │ datos[2][64]   256b│── rdata ──────────┘           │
│                     │ valido[2][64]      │                               │
│                     │ mru[64]            │◀── inv_req, inv_linea ─────┐  │
│                     │ FSM: ESPERA/LLENA  │                            │  │
│                     └──┬──────┬───────┬──┘                            │  │
│         stall ◀────────┘      │       │ wb_push, wb_linea,            │  │
│                     mem_req   │       │ wb_datos, wb_mascara          │  │
│                     mem_linea │       ▼                               │  │
│           mem_listo ▲         │  ┌──────────────────────┐             │  │
│           mem_datos │         │  │ eviction_buffer      │             │  │
│                     │         │  │ u_write_buffer, 8    │             │  │
│                     │         │  │ fusión + conflicto   │             │  │
│                     │         │  └──────┬───────────────┘             │  │
│                     │         │         │ head_valido / head_ack,     │  │
│                     │         │         │ head_ocupada                │  │
│                   ┌─┴─────────▼─────────▼─┐                           │  │
│                   │      l2_arbiter       │                           │  │
│                   │ LIBRE / SIRVIENDO_L1 /│                           │  │
│                   │ SIRVIENDO_WB          │                           │  │
│                   │ la lectura gana       │                           │  │
│                   └───────────┬───────────┘                           │  │
│                               │ req_lectura, req_escritura,           │  │
│                               │ req_linea, req_wdata, req_wmask       │  │
│                   ┌───────────▼───────────┐                           │  │
│                   │       l2_cache        │── l2_inv_req, ────────────┘  │
│                   │ etiqueta[4][128]   4b │   l2_inv_linea               │
│                   │ datos[4][128]    256b │                              │
│                   │ valido[4][128]        │                              │
│                   │ sucio[4][128]         │                              │
│                   │ edades[4][128]     2b │                              │
│                   │ FSM: 7 estados        │                              │
│                   └────┬─────────────┬────┘                              │
│           mem_req,     │             │ ev_push, ev_linea, ev_datos       │
│           mem_linea    │             │ (línea sucia expulsada)           │
│                   ┌────▼─────────────▼──────────────────────┐            │
│                   │            mem_system.sv                │            │
│                   │  mem_clock_gen (DIV=4) ── mem_tick ──┐  │            │
│                   │  eviction_buffer u_evict, 8          │  │            │
│                   │        │ ev_valido / ev_ack          │  │            │
│                   │  mem_controller ◀────────────────────┘  │            │
│                   │    LIBRE RD_LAT RD_BURST WR_LAT WR_BURST│            │
│                   │        │ addr, we, be, wdata            │            │
│                   │  main_memory  16384 palabras, gated     │            │
│                   └─────────────────────────────────────────┘            │
│                                                                          │
│  ┌───────────────┐                                                       │
│  │ perf_counters │◀── ev_* de l1_dcache, l2_cache y mem_system           │
│  │ 31 contadores │                                                       │
│  │ saturantes    │                                                       │
│  │ + bit pegajoso│                                                       │
│  └───────────────┘                                                       │
└──────────────────────────────────────────────────────────────────────────┘
```

El diagrama corresponde al código: cada caja es un módulo con ese nombre de archivo y cada etiqueta es el nombre que la señal tiene en el RTL. Los nombres de instancia (`u_l1d`, `u_write_buffer`, `u_l2_arbiter`, `u_l2_cache`, `u_evict`, `u_mem_sys`) son los que usan los testbenches para alcanzar el estado interno.

---

## 3. La caché L1-D por dentro

### 3.1 Dirección y estado

```
   31                        11 10          5 4      2 1   0
  ┌─────────────────────────────┬─────────────┬────────┬─────┐
  │        etiqueta 21 b        │ conjunto 6 b│palabra │byte │
  └─────────────────────────────┴─────────────┴────────┴─────┘
         `L1D_TAG`                 `L1D_SET`   `LINE_WIDX` `LINE_BOFF`
```

Los cuatro campos son macros derivadas de la geometría, no escritas a mano:

```systemverilog
`define L1D_TAG_W (`XLEN - `L1D_SIDX_W - `LINE_OFF_W)          // 32-6-5 = 21
`define L1D_SET  (`L1D_SIDX_W + `LINE_OFF_W - 1):`LINE_OFF_W   // [10:5]
```

| Arreglo | Dimensiones | Bits | Para qué |
|---|---|---|---|
| `etiqueta` | `[0:1][0:63]` × 21 b | 2688 | comparar contra la dirección |
| `datos` | `[0:1][0:63]` × 256 b | 32768 | los 4 KB |
| `valido` | `[0:1][0:63]` × 1 b | 128 | si la vía tiene algo |
| `mru` | `[0:63]` × 1 b | 64 | LRU exacto de dos vías |

192 bits de control para administrar 4 KB de datos, que es la razón por la que el LRU de un bit es la decisión correcta a esta asociatividad.

### 3.2 Búsqueda

Las dos vías se comparan en paralelo, combinacional, listo en el mismo ciclo. Eso es lo que hace que un acierto cueste un ciclo:

```systemverilog
assign acierto_v0 = valido[0][conjunto] && (etiqueta[0][conjunto] == tag);
assign acierto_v1 = valido[1][conjunto] && (etiqueta[1][conjunto] == tag);
assign acierto      = acierto_v0 || acierto_v1;
assign via_acertada = acierto_v1;        // con dos vías, el acierto es un bit
assign via_victima  = ~mru[conjunto];    // la víctima es la que no es MRU
```

⚠️ Estas líneas son las que fijan la asociatividad en dos. Los arreglos se dimensionan con `L1D_WAYS`, pero la búsqueda y la víctima no, y el módulo no comprueba que `L1D_WAYS` valga 2. Por eso el barrido de capacidad de L1 cambia `L1D_BYTES`, `L1D_SETS` y `L1D_SIDX_W` y deja las vías en dos. La L2 sí es de N vías (§3b.2).

### 3.3 Máquina de estados

Dos estados, no cinco, porque la caché no modela el tiempo: el tiempo vive abajo, en la L2 y en el controlador de memoria.

```
      ┌──────────────────────────────────────────┐
      ▼                                          │
 ┌──────────┐  falla de lectura && !wb_conflicto  │
 │  ESPERA  │ ──────────────────────────────────▶ │
 │ accesos  │        (emite mem_req)       ┌──────┴────┐
 │ normales │                              │   LLENA   │
 │ stall =  │                              │ espera la │
 │ falla_   │ ◀──────── mem_listo ──────── │ línea     │
 │ lectura  │   (escribe la vía víctima,   │ stall =   │
 │ ||espera_│    actualiza mru)            │ !mem_listo│
 │ buffer   │                              └───────────┘
 └──────────┘
 espera_raw = falla_lectura && wb_conflicto
   se queda en ESPERA con stall, sin emitir
```

Las tres condiciones de stall son las tres causas que los contadores distinguen:

```systemverilog
assign falla_lectura = es_load && !acierto;            // hay que traer la línea
assign espera_raw    = falla_lectura && wb_conflicto;  // el dato está en el buffer
assign espera_buffer = es_store && wb_lleno;           // no hay dónde poner el store
```

### 3.4 Puertos

| Grupo | Señales | Dir. | Qué lleva |
|---|---|---|---|
| LSU | `req`, `addr`, `we`, `be`, `wdata` | in | el acceso pedido |
| | `rdata`, `stall` | out | el dato y la orden de congelar |
| write buffer | `wb_push`, `wb_linea`, `wb_datos`, `wb_mascara` | out | el store que baja |
| | `wb_lleno` | in | no hay espacio |
| | `wb_consulta` / `wb_conflicto` | out / in | la pregunta RAW y su respuesta |
| nivel de abajo (árbitro) | `mem_req`, `mem_linea` | out | traer esta línea |
| | `mem_listo`, `mem_datos` | in | la línea llegó |
| L2 | `inv_req`, `inv_linea` | in | invalidación hacia atrás: soltar esta línea |
| contadores | `ev_load_hit/miss`, `ev_store_hit/miss` | out | un pulso por evento |
| | `ev_stall_miss/wb/raw` | out | un pulso por ciclo perdido |
| | `ev_inv_ejecutada` | out | un pulso por invalidación que encontró la línea |

La invalidación compara la línea que manda la L2 contra las dos vías del conjunto y apaga el bit de válido de la que coincida. `ev_inv_ejecutada` solo se levanta si la L1 de verdad tenía la línea: cuenta invalidaciones ejecutadas, no pedidas, que es lo que pide la sección 5.2 del enunciado. Si la invalidación llega en el mismo ciclo en que la L1 termina de rellenar esa línea, gana la invalidación.

Los ocho `ev_*` son pulsos de un ciclo que van directo a `perf_counters.sv`. Importa que sean salidas de la caché y no algo que el testbench deduzca: las métricas las produce el hardware.

---

## 3b. La caché L2 por dentro

### 3b.1 Dirección y estado

La L2 no recibe direcciones de byte sino números de línea: el árbitro le entrega `req_linea`, de 11 bits (`MEM_LIDX_W`), porque la memoria es de 64 KB y tiene 2048 líneas de 32 B. La palabra y el byte ya los resolvió la L1.

```
   15         12 11           5 4      2 1   0      dirección de byte
  ┌─────────────┬──────────────┬────────┬─────┐
  │ etiqueta 4 b│ conjunto 7 b │palabra │byte │
  └─────────────┴──────────────┴────────┴─────┘
   req_linea      req_linea      (los resuelve la L1)
   [10:7]         [6:0]
```

Los anchos salen de los parámetros `WAYS` y `SETS` del módulo, no escritos a mano:

```systemverilog
localparam int SET_W = $clog2(SETS);           // 7
localparam int TAG_W = `MEM_LIDX_W - SET_W;    // 11 - 7 = 4
localparam int WAY_W = $clog2(WAYS);           // 2
```

| Arreglo | Dimensiones | Bits | Para qué |
|---|---|---|---|
| `etiqueta` | `[0:3][0:127]` × 4 b | 2048 | comparar contra la línea pedida |
| `datos` | `[0:3][0:127]` × 256 b | 131072 | los 16 KB |
| `valido` | `[0:3][0:127]` × 1 b | 512 | si la vía tiene algo |
| `sucio` | `[0:3][0:127]` × 1 b | 512 | la línea cambió y memoria tiene una copia vieja (write-back) |
| `edades` | `[0:3][0:127]` × 2 b | 1024 | LRU exacto de cuatro vías |

4096 bits de control para administrar 16 KB de datos. Un pseudo-LRU de árbol usaría 384 bits en vez de los 1024 de las edades; la diferencia es menos del 0,5 % del estado de la L2, que es por qué la decisión P1 de [decisiones.md](decisiones.md) se quedó con LRU exacto.

### 3b.2 Búsqueda

Las cuatro vías se comparan en paralelo, combinacional, como en la L1, pero los comparadores salen de un `generate` y no están escritos uno por uno. Eso es lo que hace a la L2 de N vías:

```systemverilog
generate
    for (i = 0; i < WAYS; i++) begin : gen_comparadores
        assign acierto_via[i] = valido[i][conjunto] && (etiqueta[i][conjunto] == tag_buscado);
    end
endgenerate
assign acierto = |acierto_via;
```

La víctima es la vía con la edad máxima. En cada conjunto las edades son siempre una permutación de 0 a 3: en un acierto, la vía acertada pasa a 0 y envejecen en 1 solo las que eran más jóvenes que ella; en un fallo, la víctima pasa a 0 y envejecen todas las demás. El reset las arranca escalonadas (`edades[v] = v`).

```systemverilog
if (edades[v][conjunto] == WAY_W'(WAYS - 1)) via_victima = WAY_W'(v);
```

El módulo aborta la elaboración si `WAYS` no es potencia de dos mayor o igual que 2, o si `SETS` no es potencia de dos, en vez de indexar bits equivocados en silencio.

### 3b.3 Máquina de estados

Siete estados. A diferencia de la L1, la L2 sí modela tiempo: su hit time de 8 ciclos se cuenta en su propia FSM.

```
                ┌──────────────────────────────────────────────────┐
                ▼                                                  │
          ┌──────────┐ req_lectura ||       ┌──────────┐           │
          │  ESPERA  │ req_escritura        │ LATENCIA │           │
          │          │ ───────────────────▶ │ cuenta   │           │
          └──┬────▲──┘                      │ hit time │           │
   vaciar && │    │ vac_fin                 └────┬─────┘           │
  tiene_     ▼    │                              ▼                 │
  sucias ┌────────┴─┐                     ┌──────────────┐ acierto │
         │ VACIANDO │                     │   EVALUAR    │─────────┤
         │ empuja   │                     │ acierto o    │ (listo) │
         │ sucias   │                     │ fallo        │         │
         └──────────┘                     └──┬────────┬──┘         │
                                  víctima    │        │ víctima    │
                                  sucia      ▼        │ limpia o   │
                                     ┌──────────┐     │ inválida   │
                                     │  EVICT   │     │            │
                                     │ ev_push  │     │            │
                                     └────┬─────┘     │            │
                                !ev_lleno ▼           ▼            │
                                     ┌──────────────────────┐      │
                                     │      ALLOCATE        │      │
                                     │ mem_req, espera      │      │
                                     │ mem_listo (o bypass  │      │
                                     │ si la máscara es     │      │
                                     │ de 32 B completos)   │      │
                                     └──────────┬───────────┘      │
                                                ▼                  │
                                     ┌──────────────────────┐      │
                                     │     ACTUALIZAR       │──────┘
                                     │ instala en la víctima│ (listo)
                                     │ edades, l2_inv_req   │
                                     └──────────────────────┘
```

Un acierto cuesta 1 ciclo en `ESPERA`, 6 en `LATENCIA` (el contador arranca en `L2_HIT_CYCLES - 3`) y 1 en `EVALUAR`: 8, exactamente la macro. Un fallo suma los 53 de memoria en `ALLOCATE` y 2 ciclos más: `EVALUAR`, que en un fallo ya no entrega nada, y `ACTUALIZAR`, en que la L2 escribe la línea antes de entregarla. Total 63 (`L2_MISS_EXTRA = 2`). Sin L2, un fallo de L1 cuesta 53 + 1 = 54 (`MEM_DIRECTO_EXTRA`). Las tres cifras se miden fallo por fallo en [analisis-rendimiento.md](analisis-rendimiento.md) §9. Las políticas viven en lo que se escribe al salir de cada estado:

- write-back: una escritura que acierta solo marca `sucio`; la línea baja a memoria cuando se expulsa (`EVICT`) o en el vaciado.
- write-allocate: una escritura que falla trae la línea y la mezcla byte por byte con lo escrito, según la máscara. Si la máscara cubre los 32 bytes, `ALLOCATE` no lee memoria (bypass).
- inclusión: cuando la víctima es válida, `l2_inv_req` y `l2_inv_linea` le piden a la L1 que la suelte. En la L1 eso solo apaga un bit de válido, porque la L1 es write-through y nunca tiene una línea sucia.
- vaciado: al terminar el programa, `top.sv` levanta `vaciar` y la L2 recorre sus 512 entradas empujando las sucias; `mem_drenada` no sube mientras `tiene_sucias` siga en alto.

Las condiciones que gobiernan las salidas hacia los otros niveles:

```systemverilog
assign mem_req      = (estado == ALLOCATE) && !(req_escritura && mascara_completa_32B)
                   && !mem_listo;                         // contrato req/listo
assign ev_push      = ((estado == EVICT) && !ev_lleno)
                   || ((estado == VACIANDO) && vac_sucia && !ev_lleno);
assign l2_inv_req   = (estado == ACTUALIZAR && valido[via_victima][conjunto])
                   || (estado == EVALUAR && proximo_estado == EVICT);
assign listo        = ((estado == EVALUAR) && acierto) || (estado == ACTUALIZAR);
```

El `!mem_listo` de `mem_req` es el contrato de la sección 8. Sin él, el controlador leía el pedido viejo como uno nuevo en el ciclo de `listo` y arrancaba una lectura fantasma cuyos datos terminaban en el relleno de otra línea; fue un error real de la Iteración 4.

### 3b.4 Puertos

| Grupo | Señales | Dir. | Qué lleva |
|---|---|---|---|
| árbitro | `req_lectura`, `req_escritura`, `req_linea` | in | rellenar una línea de L1 o drenar una del write buffer |
| | `req_wdata`, `req_wmask` | in | la línea de 256 bits y la máscara de 32 de los bytes escritos |
| | `rdata`, `listo` | out | la línea y el fin de la petición |
| L1-D | `l2_inv_req`, `l2_inv_linea` | out | invalidación hacia atrás |
| fin de programa | `vaciar` / `tiene_sucias` | in / out | el pedido de vaciado y su condición de parada |
| memoria | `mem_req`, `mem_linea` | out | traer esta línea |
| | `mem_listo`, `mem_datos` | in | la línea llegó |
| eviction buffer | `ev_push`, `ev_linea`, `ev_datos`, `ev_mascara` | out | la línea sucia expulsada, siempre con máscara completa |
| | `ev_lleno` | in | no hay espacio, `EVICT` espera |
| contadores | `ev_l2_load_hit/miss`, `ev_l2_store_hit/miss` | out | un pulso por petición, en `EVALUAR` |
| | `ev_stall_evict` | out | un pulso por ciclo en `EVICT` con el buffer lleno |

La L2 tiene un solo puerto y dos clientes. `l2_arbiter.sv` los reparte con tres estados (`LIBRE`, `SIRVIENDO_L1`, `SIRVIENDO_WB`): la lectura gana porque tiene al pipeline detenido, un drenado que ya entró termina antes de atender otra cosa, y mientras drena levanta `wb_drenando`, conectado a `head_ocupada` del write buffer, para que un store nuevo no se fusione con la línea que ya va en camino. Compilado con `-DCERBERO_SIN_L2`, `top.sv` no instancia `l2_cache` y conecta el árbitro directo a `mem_system`: la lectura del árbitro pasa a ser `mem_req`, y el drenado del write buffer entra al eviction buffer con su máscara, en un ciclo salvo que esté lleno. La L1, el write buffer, el árbitro y el subsistema de memoria son exactamente los mismos, así que la diferencia medida es la que aporta la L2. La invalidación se ata a cero y los contadores de L2 quedan en cero. Es la línea base de [analisis-rendimiento.md](analisis-rendimiento.md).

---

## 4. El sistema de memoria por dentro

`mem_system.sv` no tiene lógica propia: conecta cuatro módulos y expone un solo protocolo hacia arriba. Su cliente es la L2, que lee con `mem_req` en `ALLOCATE` y escribe con `ev_push` en `EVICT` y `VACIANDO`; sin L2, el cliente es el árbitro. El módulo no cambió al insertar la L2.

### 4.1 Cruce de dominios de reloj

El cruce no se hace con dos relojes sino con una **habilitación**. Ninguna lógica depende de `mem_clk`, que existe solo para observar en GTKWave; todo lo que debe ocurrir al ritmo de la memoria ocurre en el flanco de `clk` cuando `mem_tick` está levantado, porque un reloj derivado en simulación produce carreras entre dominios que no son reales.

```systemverilog
output logic mem_clk,    // solo para observar
output logic mem_tick    // esta es la que controla toda la lógica
```

Su testbench comprueba una invariante: **cada `mem_tick` coincide con un flanco de subida de `mem_clk`**. Esa prueba encontró un error real, en que el reset dejaba `cuenta = 0` y `mem_clk = 1` y el primer ciclo tras el reset tenía `mem_tick` sin flanco.

### 4.2 FSM del controlador

```
                  ┌──────────────────────────────┐
                  ▼                              │
            ┌──────────┐                         │
            │  LIBRE   │  arbitra                │
            └─┬──────┬─┘                         │
  puede_leer  │      │  puede_drenar             │
              ▼      ▼                           │
      ┌─────────┐  ┌─────────┐ mem_we ya activo  │
      │ RD_LAT  │  │ WR_LAT  │ (palabra 0)       │
      │24 ciclos│  │         │                   │
      └────┬────┘  └────┬────┘                   │
           ▼            ▼                        │
     ┌──────────┐ ┌──────────┐                   │
     │ RD_BURST │ │ WR_BURST │                   │
     │7 palabras│ │ palabras │                   │
     │ × 4 cicl.│ │  1 a 7   │                   │
     └────┬─────┘ └────┬─────┘                   │
          └─────┬───────┘                        │
                └────────────────────────────────┘
```

**Prioridad.** Una lectura gana sobre un drenado, porque la lectura tiene a alguien esperándola y el drenado no. La excepción es el conflicto RAW: si lo que se quiere leer está en el buffer, hay que drenar primero.

```systemverilog
assign puede_leer   = req && !ev_conflicto;
assign puede_drenar = ev_valido && (!req || ev_conflicto) && !ev_ack;
```

**De dónde salen los 53 ciclos.** El ciclo de arbitraje en `LIBRE` cuenta como el primero de la latencia, así que `RD_LAT` carga `faltan <= MEM_FIRST_WORD - 2`; después vienen 7 palabras a 4 ciclos. Total 25 + 28 = 53. El off-by-one aquí costó una depuración (daba 54), y `tb_mem_system.sv` mide el intervalo real para que no vuelva a pasar.

**Asimetría entre leer y escribir.** En una escritura `mem_we` ya está activo durante `WR_LAT`, así que la palabra 0 se escribe durante la latencia y `WR_BURST` escribe las palabras 1 a 7. Sin eso, 8 palabras necesitan 8 flancos de memoria pero la ventana de la ráfaga solo contiene 7, y la palabra 7 nunca se escribía. Fue un error real que encontró el testbench.

### 4.3 El buffer, un módulo usado dos veces

```
 ┌──────────────┬───────────────────────────┬──────────────────────┐
 │ línea (11 b) │     datos (256 bits)      │  máscara (32 bits)   │
 │ cuál línea   │  las 8 palabras de la     │ un bit por byte: qué │
 │ de memoria   │  línea                    │ bytes hay que grabar │
 └──────────────┴───────────────────────────┴──────────────────────┘
```

Tres funciones: **FIFO** (las líneas salen en el orden en que entraron), **fusión** (un `push` a una línea que ya está no ocupa entrada nueva: mezcla datos y hace OR de máscaras) y **detección de conflicto** (`consulta_linea` entra, `conflicto` sale, y eso implementa el stall por RAW). La entrada `head_ocupada` impide fusionar sobre una línea que ya va en camino.

---

## 5. Los contadores de métricas

31 contadores de 32 bits con la misma estructura: suman de 0 a 7 por ciclo, **saturan** en el máximo en vez de envolver, y levantan un bit pegajoso si alguno saturó.

```systemverilog
if (cont[k] > TOPE - inc[k]) begin
    cont[k]    <= TOPE;
    desbordado <= 1'b1;       // pegajoso: una vez levantado no baja
end
else cont[k] <= cont[k] + inc[k];
```

| Grupo | Contadores | Sección del enunciado |
|---|---|---|
| Tiempo y trabajo | `ciclos`, `bundles`, `instrucciones` | 5.1 |
| Ocupación del VLIW | `ops_por_slot[0..4]` | 5.1 |
| Accesos | `accesos_load`, `accesos_store` | 5.1 |
| Eficiencia del código | `bundles_vacios`, `saltos_tomados`, `delay_vacios` | 5.1 |
| Stalls por causa | `ciclos_stall`, y `stall_por_miss`, `stall_por_wb`, `stall_por_raw`, `stall_por_evict` | 5.1 |
| Stall de fallo de L1, según la L2 | `stall_l2_hit`, `stall_l2_miss` | 5.1 |
| L1-D | `l1_load_hit`, `l1_load_miss`, `l1_store_hit`, `l1_store_miss` | 5.2 |
| L2 | `l2_load_hit`, `l2_load_miss`, `l2_store_hit`, `l2_store_miss` | 5.2 |
| Inclusión | `inv_ejecutadas` | 5.2 |
| Memoria principal | `mem_accesos`, `mem_ciclos` | 5.3 |

Las lecturas de L2 son los rellenos de la L1 y las escrituras son los drenados del write buffer, así que la separación que pide el Cuadro 2 ("reads y writes por separado desde L1-D") la da el hardware. La utilización del bus se calcula en el informe como `mem_ciclos` sobre los ciclos del reset al drenado completo: la ventana incluye el vaciado de la L2 posterior al `HALT`, porque ahí el bus sigue transfiriendo.

**El reparto del stall de un fallo.** Cuando la L1 falla, todavía no se sabe si la L2 va a acertar: eso se decide en `EVALUAR`, varios ciclos después de que empezó el stall. Por eso `perf_counters.sv` acumula los ciclos del fallo en curso y, cuando la línea llega a la L1 (`ev_relleno_fin`), los descarga enteros en `stall_l2_hit` o en `stall_l2_miss` según si esa lectura llegó a memoria principal. La suma de los dos es `stall_por_miss`, y `tb_programa.sv` lo comprueba en cada corrida.

Dos habilitaciones, y la diferencia importa:

```systemverilog
assign avanza = rst_n && id_valid && !stall;   // trabajo cometido
assign corre  = rst_n && !halted;              // el procesador está vivo
```

Los eventos de caché se cuentan bajo `rst_n` y **no** bajo `corre`: el último store de un programa suele vivir en el delay slot del `HALT`, y contarlo bajo `corre` lo perdía. Era un error real de la Iteración 3. Los contadores no tienen salida hacia el datapath, para que medir no pueda cambiar lo medido. La metodología completa está en [analisis-rendimiento.md](analisis-rendimiento.md).

---

## 6. Flujo de instrucciones

Sin stall, un bundle por ciclo, y por eso el "ideal" de las tablas de resultados es la cuenta de bundles. Con stall por fallo de caché:

```
ciclo    IF      ID      EX        MEM       WB     cache_stall
  n      k+3     k+2     k+1 (lw)  k         k-1        0
 n+1     k+3 ◀─  k+2 ◀─  k+1 ◀─    burbuja   k          1   ← congela
 ...     (retenidos P ciclos)                           1
n+P+1    k+4     k+3     k+2       k+1       burbuja    0   ← sigue
```

`P` es la penalidad del fallo: 8 ciclos si la L2 acierta, 63 si falla, 54 sin L2. Arriba se retiene (`fetch`, `imem`, `reg_if_id`, `reg_id_ex` reciben `stall`), abajo se inyecta burbuja (`ex_commit` baja). Esas burbujas son los ciclos que los contadores reportan como `ciclos_stall`. El pipeline no sabe nada de la L2: solo ve `cache_stall`, que sale de la L1.

---

## 7. Flujo de datos

**Load que acierta en L1 (1 ciclo).** `lsu` calcula la dirección, `l1_dcache` la parte, compara las dos vías en paralelo, selecciona la palabra de la línea y actualiza `mru[conjunto]`. `load_align` extrae el byte, half o word según el opcode, y `regfile` escribe.

**Load que falla en L1 y acierta en L2 (8 ciclos más).** Si hay `wb_conflicto`, la L1 se queda en `ESPERA` con stall, sin emitir, hasta que el árbitro drene esa línea a la L2. Si no, emite `mem_req` y pasa a `LLENA`. El árbitro pasa a `SIRVIENDO_L1` y levanta `req_lectura`. La L2 cuenta su hit time en `LATENCIA`, acierta en `EVALUAR`, rejuvenece la vía y levanta `listo` con la línea. Al llegarle, la L1 escribe la vía víctima (`~mru`), pone válido y etiqueta, actualiza `mru`, baja `stall` y entrega la palabra.

**Load que falla en los dos (63 ciclos más).** Igual hasta `EVALUAR`, donde la L2 falla. Si su víctima está sucia, va a `EVICT`: levanta `l2_inv_req` para que la L1 la suelte y empuja la línea al eviction buffer. Después, en `ALLOCATE`, pide la línea a `mem_system`, cuyo controlador arbitra en `LIBRE`, pasa 24 ciclos en `RD_LAT` y 7 palabras × 4 ciclos en `RD_BURST`. En `ACTUALIZAR` la L2 instala la línea limpia, avisa la invalidación de la víctima si era válida y entrega la línea hacia arriba por el mismo camino.

**Store (nunca espera, salvo buffer lleno).**

```
 lsu calcula dir, dato, be ──▶ l1_dcache
   ├─ ¿la línea está en la caché?
   │    sí → actualiza la palabra en la vía acertada (write-through:
   │         también baja), cuenta l1_store_hit
   │    no → NO trae la línea (no-write-allocate), cuenta l1_store_miss
   └─ en ambos casos, si !stall:
        wb_push con la línea, los datos y la MÁSCARA de los bytes que
        este store de verdad escribe (1, 2 o 4)
            ▼
 u_write_buffer: ¿ya tengo esta línea y no va en camino?
     sí → fusiona: mezcla datos, OR de máscaras, no ocupa entrada
     no → entrada nueva; si no hay, levanta lleno y la caché hace stall
            ▼
 l2_arbiter: drena la cabeza cuando la L1 no está leyendo
            ▼
 l2_cache: ¿la línea está en la L2?
     sí → escribe los bytes de la máscara y la marca sucia (write-back)
     no → la trae de memoria (write-allocate), salvo que la máscara
          cubra los 32 bytes; mezcla y la instala sucia
            ▼
 la línea queda en la L2. Baja a memoria solo cuando la L2 la expulsa
 (EVICT) o al vaciar al final (VACIANDO), siempre como línea completa
            ▼
 u_evict ──▶ mem_controller ──▶ main_memory
```

La máscara es la pieza que hace correcto un `SB` bajo write-through, y por eso recorre el sistema entero: la produce la LSU, la lleva la L1, la fusiona el write buffer y la aplica la L2 al mezclar; desde ahí la línea viaja completa. Sin L2, la máscara llega hasta el controlador, que la recorta palabra por palabra (`mem_be = mascara_actual[idx*4 +: 4]`), y la aplica la memoria.

---

## 8. El protocolo entre niveles

Todos los niveles hablan la misma pareja de señales, y eso es lo que permitió insertar la L2 en la Iteración 4 sin tocar `mem_system` ni el camino de relleno de la L1 (lo único que la L1 ganó fue el puerto de invalidación), y lo que permite quitarla con una macro.

| Señal | Quién la levanta | Contrato |
|---|---|---|
| `req` | el nivel de arriba | "necesito esta línea" |
| `listo` | el nivel de abajo | "aquí está, un ciclo" |

**La regla: `req` baja al ver `listo`.** El de arriba lo mantiene hasta ver `listo` y entonces lo baja; el de abajo no acepta otra petición en el mismo ciclo en que entrega. Sin eso, un `req` que se queda levantado un ciclo más se lee como petición nueva y dispara otra transferencia de 53 ciclos.

| Frontera | Arriba | Abajo |
|---|---|---|
| L1 ↔ árbitro | `l1_dcache` (`mem_req`) | `l2_arbiter` (`l1_listo`) |
| árbitro ↔ L2 | `l2_arbiter` (`req_lectura`, `req_escritura`) | `l2_cache` (`listo`) |
| L2 ↔ memoria | `l2_cache` (`mem_req`) | `mem_system` (`listo`) |

La interfaz de línea, igual en los dos buffers y en todos los niveles: índice de línea 11 bits (`MEM_LIDX_W`), datos 256 bits (`LINE_W`), máscara 32 bits (`LINE_MASK_W`).

---

## 9. Cómo recorrer el código

`cerbero_defs.svh` (geometría y tiempos en un lugar), `l1_dcache.sv` (la sección 3.2 es su corazón), `l2_arbiter.sv` (113 líneas, la FSM completa), `l2_cache.sv` (§3b), la sección "JERARQUIA DE MEMORIA DE DATOS" de `top.sv` (donde se conecta todo, se define `ex_commit` y vive `CERBERO_SIN_L2`), `mem_system.sv` (196 líneas que solo conectan), `mem_controller.sv` (donde vive el tiempo de la memoria), `perf_counters.sv` (el reparto del stall de §5) y `tb_l1_dcache.sv` y `tb_l2_cache.sv` (cuyos 55 y 37 casos dicen qué se considera correcto).

```bash
cd src/build
make                     # lista las unidades disponibles
make clean && make all   # las 38
make jerarquia           # mem_system, l1_dcache, l2_cache, l2_arbiter, eviction_buffer
make l2_cache            # una sola; deja tb_l2_cache.vcd
gtkwave tb_l2_cache.vcd
make clean && make correr PROG=patron_reuso XFLAGS_EXTRA=-DCERBERO_SIN_L2   # sin L2
```
