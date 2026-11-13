# Organización y microarquitectura del sistema extendido

CE-4301 Arquitectura de Computadores I · Proyecto Grupal II · Grupo #4 · CERBERO-1

Sección 2 de la documentación de diseño: organización interna en SystemVerilog, diagramas de bloques de los componentes principales con sus interconexiones, y flujo de datos e instrucciones.

Complementos: [jerarquia-memoria.md](jerarquia-memoria.md) (políticas) y [analisis-rendimiento.md](analisis-rendimiento.md) (resultados). El pipeline base y las unidades funcionales del Proyecto I están en [microarchitecture.md](microarchitecture.md); aquí se repite solo lo necesario para ubicar lo nuevo.

---

## 1. Módulos

23 módulos RTL en `src/cpu/`, 5970 líneas, con 35 unidades de prueba. Los seis del Proyecto II van en negrita.

| Módulo | Qué es | Líneas | Testbench |
|---|---|---|---|
| `top.sv` | el sistema completo: instancia y conecta todo | 1010 | `tb_top`, `tb_programa` |
| **`l1_dcache.sv`** | **caché L1-D, 4 KB, 2 vías** | **421** | `tb_l1_dcache` (50) |
| **`mem_controller.sv`** | **FSM de 5 estados del acceso a memoria** | **359** | `tb_mem_system` (59) |
| `perf_counters.sv` | 21 contadores de rendimiento | 356 | `tb_perf_counters` (66) |
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
│                     │ valido[2][64]      │                                │
│                     │ mru[64]            │                                │
│                     │ FSM: ESPERA/LLENA  │                                │
│                     └──┬──────┬───────┬──┘                                │
│         stall ◀─────────┘      │       │ wb_push, wb_linea,               │
│                                │       │ wb_datos, wb_mascara             │
│  ┌───────────────┐   mem_req   │       ▼                                  │
│  │ perf_counters │  mem_linea  │  ┌──────────────────────┐                │
│  │ 21 contadores │◀─ ev_load_* │  │ eviction_buffer      │                │
│  │ saturantes    │   ev_store_*│  │ u_write_buffer, 8    │                │
│  │ + bit pegajoso│   ev_stall_*│  │ fusión + conflicto   │                │
│  └───────────────┘  mem_listo  │  └──────┬───────────────┘                │
│                     mem_datos  │         │ head_valido / head_ack         │
│                   ┌────────────▼─────────▼──────────────────┐             │
│                   │            mem_system.sv                │             │
│                   │  mem_clock_gen (DIV=4) ── mem_tick ──┐  │             │
│                   │  eviction_buffer u_evict, 8          │  │             │
│                   │        │ ev_valido / ev_ack          │  │             │
│                   │  mem_controller ◀───────────────────-┘  │             │
│                   │    LIBRE RD_LAT RD_BURST WR_LAT WR_BURST│            │
│                   │        │ addr, we, be, wdata             │            │
│                   │  main_memory  16384 palabras, gated      │            │
│                   └─────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────────────────────┘
```

El diagrama corresponde al código: cada caja es un módulo con ese nombre de archivo y cada etiqueta es el nombre que la señal tiene en el RTL. Los nombres de instancia (`u_l1d`, `u_write_buffer`, `u_evict`, `u_mem_sys`) son los que usan los testbenches para alcanzar el estado interno.

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

Estas líneas son las que fijan la asociatividad en dos. El módulo aborta la elaboración si se le pide otra, en vez de indexar una vía que no existe.

### 3.3 Máquina de estados

Dos estados, no cinco, porque la caché no modela el tiempo: el tiempo vive en el controlador.

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
| nivel de abajo | `mem_req`, `mem_linea` | out | traer esta línea |
| | `mem_listo`, `mem_datos` | in | la línea llegó |
| contadores | `ev_load_hit/miss`, `ev_store_hit/miss` | out | un pulso por evento |
| | `ev_stall_miss/wb/raw` | out | un pulso por ciclo perdido |

Los siete `ev_*` son pulsos de un ciclo que van directo a `perf_counters.sv`. Importa que sean salidas de la caché y no algo que el testbench deduzca: las métricas las produce el hardware.

---

## 4. El sistema de memoria por dentro

`mem_system.sv` no tiene lógica propia: conecta cuatro módulos y expone un solo protocolo hacia arriba.

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

**Prioridad.** Una lectura gana sobre un drenado, porque la lectura tiene al pipeline detenido esperándola y el drenado no detiene a nadie. La excepción es el conflicto RAW: si lo que se quiere leer está en el buffer, hay que drenar primero.

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

21 contadores de 32 bits con la misma estructura: suman de 0 a 7 por ciclo, **saturan** en el máximo en vez de envolver, y levantan un bit pegajoso si alguno saturó.

```systemverilog
if (cont[k] > TOPE - inc[k]) begin
    cont[k]    <= TOPE;
    desbordado <= 1'b1;       // pegajoso: una vez levantado no baja
end
else cont[k] <= cont[k] + inc[k];
```

| Grupo | Contadores |
|---|---|
| Tiempo y trabajo | `ciclos`, `bundles`, `instrucciones` |
| Ocupación del VLIW | `ops_por_slot[0..4]` |
| Accesos | `accesos_load`, `accesos_store` |
| Eficiencia del código | `bundles_vacios`, `saltos_tomados`, `delay_vacios` |
| Stalls | `ciclos_stall`, y `stall_por_miss`, `stall_por_wb`, `stall_por_raw` |
| Caché | `l1_load_hit`, `l1_load_miss`, `l1_store_hit`, `l1_store_miss` |

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
 ...     (retenidos, 53 ciclos)                         1
n+54     k+4     k+3     k+2       k+1       burbuja    0   ← sigue
```

Arriba se retiene (`fetch`, `imem`, `reg_if_id`, `reg_id_ex` reciben `stall`), abajo se inyecta burbuja (`ex_commit` baja). Esas burbujas son los ciclos que los contadores reportan como `ciclos_stall`.

---

## 7. Flujo de datos

**Load que acierta (1 ciclo).** `lsu` calcula la dirección, `l1_dcache` la parte, compara las dos vías en paralelo, selecciona la palabra de la línea y actualiza `mru[conjunto]`. `load_align` extrae el byte, half o word según el opcode, y `regfile` escribe.

**Load que falla (53 ciclos más).** Si hay `wb_conflicto`, se queda en `ESPERA` con stall sin emitir, hasta que el buffer drene esa línea. Si no, emite `mem_req` y pasa a `LLENA`. El controlador arbitra en `LIBRE` (la lectura gana), pasa 24 ciclos en `RD_LAT` y 7 palabras × 4 ciclos en `RD_BURST`. Al llegar `listo`, la caché escribe la vía víctima (`~mru`), pone válido y etiqueta, actualiza `mru`, baja `stall` y entrega la palabra.

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
 mem_controller: drena cuando no hay lectura pendiente.
     mem_be = mascara_actual[idx*4 +: 4]   (recorta la máscara a la palabra)
            ▼
 main_memory: escribe solo los bytes habilitados
```

La máscara es la pieza que hace correcto un `SB` bajo write-through, y por eso recorre el sistema entero: la produce la LSU, la lleva la caché, la fusiona el buffer, la recorta el controlador palabra por palabra, y la aplica la memoria.

---

## 8. El protocolo entre niveles

Todos los niveles hablan la misma pareja de señales, y eso permitirá insertar la L2 sin tocar lo que está alrededor.

| Señal | Quién la levanta | Contrato |
|---|---|---|
| `req` | el nivel de arriba | "necesito esta línea" |
| `listo` | el nivel de abajo | "aquí está, un ciclo" |

**La regla: `req` baja al ver `listo`.** El de arriba lo mantiene hasta ver `listo` y entonces lo baja; el de abajo no acepta otra petición en el mismo ciclo en que entrega. Sin eso, un `req` que se queda levantado un ciclo más se lee como petición nueva y dispara otra transferencia de 53 ciclos.

La interfaz de línea, igual en los dos buffers y en los dos niveles: índice de línea 11 bits (`MEM_LIDX_W`), datos 256 bits (`LINE_W`), máscara 32 bits (`LINE_MASK_W`).

---

## 9. Cómo recorrer el código

`cerbero_defs.svh` (geometría y tiempos en un lugar), `l1_dcache.sv` (la sección 3.2 es su corazón), `mem_system.sv` (196 líneas que solo conectan: la estructura del subsistema de un vistazo), `mem_controller.sv` (donde vive el tiempo), la sección de memoria de datos de `top.sv` (donde la caché se enchufa y se define `ex_commit`) y `tb_l1_dcache.sv` (cuyos 50 casos dicen qué se considera correcto).

```bash
cd src/build
make                     # lista las unidades disponibles
make clean && make all   # las 35
make l1_dcache           # una sola; deja tb_l1_dcache.vcd
gtkwave tb_l1_dcache.vcd
```
