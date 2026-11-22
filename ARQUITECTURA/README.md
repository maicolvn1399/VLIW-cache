# CERBERO-1

Procesador VLIW con ISA propia para aceleración de cifrado por bloques Feistel4,
extendido con una jerarquía de caché de datos de dos niveles y contadores de
rendimiento por hardware.

**CE-4301 Arquitectura de Computadores I — Proyectos Grupales I y II — Grupo #4**
Escuela de Ingeniería en Computadores, Instituto Tecnológico de Costa Rica.

El Proyecto I definió el ISA y el procesador. El Proyecto II, conjunto con
CE-1108 (compilador NOVA), le agrega una L1-D, una L2 unificada, memoria
principal en otro dominio de reloj, write buffer, eviction buffer y los
contadores que miden todo eso, y analiza el rendimiento del sistema con
programas en ensamblador y con código generado por NOVA.

| | |
|---|---|
| Profesor | Dr.-Ing. Jeferson González Gómez |
| Integrantes | Araya Porras Luis Diego (2021086423) · Retana Murillo Braulio (2021050678) · Valverde Navarro Michael (2020044189) · Piedra Montero Joseph (2023047830) · Muñoz Alvarado Adrián (2023207992) |
| **Jerarquía de memoria: políticas y su justificación (Proyecto II)** | [`docs/jerarquia-memoria.md`](docs/jerarquia-memoria.md) |
| **Organización y microarquitectura del sistema extendido (Proyecto II)** | [`docs/organizacion.md`](docs/organizacion.md) |
| **Análisis de rendimiento y validación (Proyecto II)** | [`docs/analisis-rendimiento.md`](docs/analisis-rendimiento.md) |
| **Registro de decisiones (Proyecto II)** | [`docs/decisiones.md`](docs/decisiones.md) |
| Especificación del ISA | [`docs/isa.md`](docs/isa.md) |
| Microarquitectura del Proyecto I | [`docs/microarchitecture.md`](docs/microarchitecture.md) |
| Modelo de simulación | [`docs/simulation.md`](docs/simulation.md) |
| Métricas y línea base (Proyecto II, Iteración 1) | [`docs/metricas.md`](docs/metricas.md) |
| Memoria principal y T_mem (Proyecto II, Iteración 2) | [`docs/memoria.md`](docs/memoria.md) |
| Caché L1-D e integración (Proyecto II, Iteración 3) | [`docs/cache.md`](docs/cache.md) |
| Integración con CE1108 | [`docs/compiler-integration.md`](docs/compiler-integration.md) |
| **Respuesta a la revisión** | [`docs/respuesta_a_la_revision.md`](docs/respuesta_a_la_revision.md) |
| **Escribir un programa de cero** | [`docs/escribir_programas.md`](docs/escribir_programas.md) |
| **Del fuente al binario** | [`docs/del_fuente_al_binario.md`](docs/del_fuente_al_binario.md) |

---

## Qué es

Un bundle de 128 bits con cinco slots de ancho desigual, siete unidades
funcionales y calendarización estática: el hardware no detecta riesgos entre
bundles ni reenvía resultados. Lo único que lo detiene son los stalls
estructurales de la jerarquía de memoria: un fallo de caché, un buffer lleno o
un conflicto RAW contra el write buffer.

```
 127                96 95                 64 63                 32 31        16 15         0
+---------------------+---------------------+---------------------+------------+-----------+
|   S0: ALU-0 (32)    |   S1: ALU-1 (32)    |   S2: LSU (32)      | S3: CRP(16)| S4:BRU(16)|
+---------------------+---------------------+---------------------+------------+-----------+
```

| Slot | Unidad | Módulo |
|---|---|---|
| S0 | ALU-0, única que escribe banderas | `alu.sv` (instancia 0) |
| S1 | ALU-1 | `alu.sv` (instancia 1) |
| S2 | Acceso a memoria, con postincremento | `lsu.sv` |
| S3 | Ronda Feistel4 | `crypto_unit.sv` |
| S3 | Bóveda de llaves y autenticación | `key_vault.sv` |
| S3 | ALU corta, destructiva | `short_alu.sv` |
| S4 | Saltos y enlace | `bru.sv` |
| — | Banco de registros, 9 lecturas y 7 escrituras | `regfile.sv` |
| — | Memoria de instrucciones, 2048 bundles de 128 bits | `imem.sv` |
| — | Memoria de datos ideal de un ciclo del Proyecto I; el procesador ya no la usa, queda como referencia | `dmem.sv` |
| — | Etapa ID: rebanado del bundle y enrutado de lecturas | `dispatch.sv` |
| — | PSW y resolución de fallas | `psw_fault_unit.sv` |
| — | Etapa IF: contador de programa, salto y detención | `fetch.sv` |
| — | Frontera IF/ID: el PC que acompaña al bundle | `reg_if_id.sv` |
| — | Frontera ID/EX: slots y los 9 valores leídos | `reg_id_ex.sv` |
| — | Frontera EX/MEM: los 7 puertos de escritura y las 5 fallas | `reg_ex_mem.sv` |
| — | Extracción del carril de una carga, en MEM | `load_align.sv` |
| — | **El procesador completo, con la jerarquía de memoria** | `top.sv` |

### La jerarquía de memoria de datos (Proyecto II)

```
 LSU ─▶ L1-D ─▶ write buffer ─▶ árbitro ─▶ L2 ─▶ eviction buffer ─▶ memoria principal
         ▲                                  │      (en mem_system, a 25 MHz)
         └──── invalidación hacia atrás ────┘
```

| Nivel | Configuración | Módulo |
|---|---|---|
| L1-D | 4 KB, 2 vías, líneas de 32 B, write-through, no-write-allocate, LRU de 1 bit, acierto en 1 ciclo | `l1_dcache.sv` |
| Write buffer (L1 a L2) | 8 entradas con fusión por línea; el RAW contra él se resuelve con stall | `eviction_buffer.sv` (`u_write_buffer`) |
| Árbitro | un solo puerto de L2 para los rellenos de L1 y los drenados del write buffer; la lectura gana | `l2_arbiter.sv` |
| L2 unificada | 16 KB, 4 vías, write-back, write-allocate, LRU exacto por edades, acierto en 8 ciclos, **inclusiva** con invalidación hacia atrás | `l2_cache.sv` |
| Eviction buffer (L2 a memoria) | 8 entradas | `eviction_buffer.sv` (`u_evict`) |
| Memoria principal | 64 KB a 25 MHz (÷4), ráfaga de 8 palabras: T_mem = 53 ciclos | `mem_system.sv`, `mem_controller.sv`, `mem_clock_gen.sv`, `main_memory.sv` |
| Contadores | 31 contadores saturantes: IPC, stalls por causa, aciertos y fallos por nivel, invalidaciones, accesos y ciclos de memoria | `perf_counters.sv` |

La geometría y las latencias viven en `src/cpu/cerbero_defs.svh` y se pueden
sobreescribir desde la línea de comandos para un barrido. Con
`-DCERBERO_SIN_L2` se quita la L2 y el árbitro va directo a memoria, que es la
línea base del análisis. El diagrama de bloques completo está en
[`docs/organizacion.md`](docs/organizacion.md) y la justificación de cada
política en [`docs/jerarquia-memoria.md`](docs/jerarquia-memoria.md).

### Herramientas

| | |
|---|---|
| Ensamblador propio | `tools/cerbero_asm.py` |
| Su arnés de pruebas, 71 casos | `tools/probar_asm.py` |
| Archivo a imagen de memoria | `tools/load_file.py` |
| Volcado de memoria a archivo | `tools/extract_data.py` |
| Formato del buffer, compartido por las dos | `tools/formato_buffer.py` |
| Su arnés de pruebas, 54 casos | `tools/probar_archivos.py` |
| La llave desde la línea de comandos, y sus 19 casos | `tools/llave.py`, `tools/probar_llave.py` |
| El flujo completo contra un modelo de referencia, 7 casos | `tools/probar_flujo.py` |
| Ejecutable NOVA a imágenes de memoria (puente con CE1108) | `tools/novac_image.py` |
| Programa de cifrado Feistel4 de un bloque | `tools/programas/feistel.s` |
| **Cifra un archivo completo** | `tools/programas/cifrar_archivo.s` |
| **Lo descifra** | `tools/programas/descifrar_archivo.s` |
| Prólogo compartido: credencial, llave y cabecera | `tools/programas/cargar_llave.s` |
| Prólogo compartido: sesión de bóveda e instalación | `tools/programas/vault_sesion.s` |
| Programas de demostración, comprobados en `make` | `tools/programas/fibonacci.s`, `estadisticas.s`, `sesion_sin_logout.s` |
| Lazo de 100 000 vueltas, a mano | `tools/programas/lazo_estres.s` |
| Subrutina de división de 32 bits | `tools/programas/div32.s` |
| Programa que usa el 100% del conjunto | `tools/programas/cobertura.s` |
| Planificador: empaqueta operaciones independientes en un bundle | `tools/empacar.py` |
| **Patrones de acceso a memoria** (secuencial, stride, aleatorio, con reuso) | `tools/programas/patron_*.s` |
| Recorrido escrito para saturar el write buffer | `tools/programas/recorrido_cache.s` |
| **Barrido de la jerarquía**: base, sin L2, capacidades de L1 y de L2 | `tools/barrido_jerarquia.sh` |
| Tablas y gráficos del barrido | `tools/tabla_analisis.py` |
| Tabla de las métricas de todos los programas | `tools/tabla_metricas.py` |
| Barrido de capacidad de L1 de la Iteración 3, sin L2 | `tools/barrido_cache.sh`, `tools/tabla_barrido.py` |

Las tres unidades de S3 se excluyen entre sí: el opcode del slot decide cuál
actúa. O el programa cifra, o usa la ALU corta.

---

## Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| [Icarus Verilog](https://steveicarus.github.io/iverilog/) | 12 o superior, probado en 13.0 | Simulación, con `-g2012`. La 10 no soporta `always_comb` ni `logic` |
| [Python](https://www.python.org/) | 3.8 o superior | Ensamblador, herramientas de carga y extracción, y sus pruebas. Solo biblioteca estándar, sin paquetes extra |
| [Verilator](https://verilator.org/) | 5.x | Solo análisis estático (`make lint`); la simulación es con Icarus. Opcional pero recomendado |
| [GTKWave](https://gtkwave.sourceforge.net/) | cualquiera | Ver formas de onda. Opcional |
| `make` | GNU Make | |
| `bash` | cualquiera | Solo para `make analisis` y los barridos. Viene con WSL, MSYS2 y Git Bash |

```bash
# Ubuntu, Debian y WSL
sudo apt install iverilog verilator gtkwave make python3

# macOS
brew install icarus-verilog verilator gtkwave python
```

**Windows.** Lo más directo es WSL con los mismos paquetes de Ubuntu. Sin
WSL, con [MSYS2](https://www.msys2.org/):

```bash
pacman -S mingw-w64-x86_64-iverilog mingw-w64-x86_64-make
```

y Python desde python.org. Dos detalles:

- El ejecutable de GNU Make en MSYS2 se llama `mingw32-make`. Se usa igual:
  `mingw32-make`, `mingw32-make top`.
- El makefile invoca `python3`. En Windows ese nombre suele resolver al acceso
  directo de la Microsoft Store, que no ejecuta nada y falla con
  `Python was not found`. Hay que desactivar los alias `python3.exe` en
  *Configuración → Aplicaciones → Alias de ejecución de aplicaciones*, o poner
  primero en el `PATH` un directorio con un `python3.exe` real.

---

## Cómo se ejecuta

Todo se corre desde `src/build`:

```bash
cd src/build

make            # pruebas de las herramientas, todos los testbenches y el flujo
make jerarquia  # solo la jerarquía: mem_system, l1_dcache, l2_cache, l2_arbiter, eviction_buffer
make patrones   # los patrones de acceso contra sus oráculos exactos
make correr PROG=patron_reuso   # un programa y su informe completo de métricas
make metricas   # el informe de todos los programas, en una tabla
make analisis   # el barrido de la jerarquía, sus tablas y sus gráficos
make ocupacion  # cuánto del bundle usa cada programa
make empacar PROG=x.s   # empaqueta operaciones independientes en un bundle
make vliw       # el mismo cálculo con y sin paralelismo, y sus ciclos
make logout     # ¿queda la bóveda abierta si no se hace LOGOUT?
make huella ARCHIVO=x   # SHA-256 del criptograma, para comparar por fuera
make lint       # análisis estático con Verilator (opcional)
make top        # corre los siete programas sobre el procesador completo
make archivo    # cifra y descifra un archivo completo sobre el RTL
make flujo      # y lo descifra con un modelo de referencia en Python
make cifrar ARCHIVO=ruta  # lo mismo, sobre un archivo cualquiera
make solo-cifrar ARCHIVO=ruta  # solo el cifrado, verificado contra el modelo
make solo-descifrar ORIGINAL=ruta  # descifra el .bin que dejo solo-cifrar
make credencial # con la credencial equivocada no se cifra nada
make ejemplos   # fibonacci, estadisticas y sesion_sin_logout, comprobados
make sum        # suma_10_15.s, el programa de la validación con CE1108, en el RTL
make correr PROG=fibonacci.s   # corre un programa y MUESTRA el resultado
make asm        # ensambla feistel.s y corre el binario en el RTL
make herramientas  # solo las pruebas de las herramientas en Python
make div        # corre la subrutina de división en el procesador
make cobertura  # comprueba que se usa el 100% del conjunto
make lsu        # solo el testbench de la LSU
make wave-lsu   # abre su forma de onda en GTKWave
make list       # lista las unidades disponibles
make clean      # borra los artefactos, incluidos los .hex ensamblados
```

Un testbench que encuentra un error llama a `$fatal`, lo que le da a `vvp` un
código de salida distinto de cero y detiene el `make`. Que `make` termine bien
significa que todas las unidades pasaron, no sólo que corrieron.

Salida esperada:

```
---- alu ----
casos: 334   fallidos: 0
RESULTADO: OK
...
==============================================================
 Todas las unidades pasaron
==============================================================
```

`tb_imem` y `tb_dmem` imprimen un aviso de Icarus, `Not enough words in the
file for the requested range`. **Esos dos son esperados y son los únicos dos que
debe haber**: los archivos de ejemplo traen menos palabras que la memoria, y
comprobar que las posiciones restantes quedan en cero es justamente uno de los
casos. No quedan indefinidas porque el módulo barre el arreglo a cero antes de
leer el archivo.

El aviso contrario, `Too many words`, nunca es intencional: significa que el
relleno con que el ensamblador generó el `.hex` no coincide con el tamaño de la
memoria del testbench que lo carga. El makefile declara el tamaño de cada
programa por separado (`BUNDLES_<programa>`) para que los dos números cuadren.

`make clean` borra también los `.hex` que produce el ensamblador, y eso tampoco
es prolijidad: las marcas de tiempo del sistema de archivos tienen granularidad
de un segundo, así que un `.s` editado y su `.hex` ya existente pueden caer en
el mismo segundo y `make` se salta el reensamblado. El resultado es una
simulación que corre el binario anterior y falla sin motivo aparente. Ante
cualquier resultado que no cuadre, `make clean && make`.

### La jerarquía de memoria y el análisis de rendimiento

`make correr` ejecuta un programa sobre el procesador completo e imprime lo
que miden los contadores de hardware. El informe queda también en
`src/build/resultado_<programa>.txt`. Un extracto de
`make correr PROG=patron_reuso`, que recorre dos veces 8 KB, el doble de la
L1 y la mitad de la L2:

```
  cache L1-D (4096 B, 2 vias, 64 conjuntos, lineas de 32 B,
              write-through, no-write-allocate, LRU)
    accesos totales                     513
      lecturas: fallos                  512
    ciclos perdidos, por causa
      fallo de lectura                18176
        que acerto en L2               2048
        que fallo en L2               16128

  cache L2 unificada (16 KB, 4 vias, 128 conjuntos, write-back,
                      write-allocate, LRU exacto, hit time 8)
      lecturas: aciertos                256
      lecturas: fallos                  256
    invalidaciones hacia atras            0  (ejecutadas sobre L1-D)

  memoria principal
    accesos (lineas completas)          258
    utilizacion del bus              59.48%  (del reset al drenado completo)

  AMAT de lectura con dos niveles
    teorico                           36.50 ciclos  (T_L1=1, T_L2=8, T_mem=53+2)
    medido                            36.50 ciclos
    ok     stall_l2_hit + stall_l2_miss = stall_por_miss 18176
```

Las líneas `ok` son comprobaciones cruzadas entre contadores independientes;
si alguna sale `FALLA`, el informe no es confiable.

**Configuraciones.** Las constantes de la jerarquía se sobreescriben con
`XFLAGS_EXTRA`. Como el `.vvp` guarda la configuración con que se compiló,
hay que hacer `make clean` al cambiarla:

```bash
make clean && make correr PROG=patron_reuso XFLAGS_EXTRA=-DCERBERO_SIN_L2     # sin L2
make clean && make correr PROG=patron_reuso \
     XFLAGS_EXTRA="-DL2_BYTES=8192 -DL2_SETS=64"                               # L2 de 8 KB
```

⚠️ El preprocesador de Verilog no divide, así que las constantes de un nivel
se pasan coherentes entre sí: `L2_BYTES = L2_SETS × L2_WAYS × 32`, y para la
L1 las cuatro (`L1D_BYTES`, `L1D_WAYS`, `L1D_SETS`, `L1D_SIDX_W`). La L2
aborta si la combinación es incoherente. La L1 es de exactamente 2 vías.

**Binarios de NOVA.** Un programa compilado por NOVA se corre con sus dos
imágenes, las que genera `tools/novac_image.py`:

```bash
make correr HEX=programa.nova.hex MEMORIA=programa.nova_d.hex
```

⚠️ Con `HEX=` solo, se carga la memoria de instrucciones pero no la de datos:
un programa con datos inicializados corre sin fallar y da un resultado
equivocado.

**El barrido.** `make analisis` corre `tools/barrido_jerarquia.sh` sobre once
configuraciones (base, sin L2, cinco capacidades de L1 y cuatro de L2) con
catorce programas, y después `tools/tabla_analisis.py`. Tarda unos minutos.
Deja los informes crudos en `barrido/jerarquia/<configuración>/`, las tablas
en `barrido/jerarquia/tablas.md` y los gráficos en `docs/imgs/it5_*.png`.
`make tablas-analisis` regenera solo las tablas y los gráficos sobre el
barrido que ya existe. El análisis de esos resultados está en
[`docs/analisis-rendimiento.md`](docs/analisis-rendimiento.md).

### El ensamblador propio

Un bundle por línea: cinco campos posicionales separados por `|`, en el orden
S0 a S4, y terminados en `;`. El guión `-` es el NOP de ese slot, y los slots
que se omiten a la derecha también quedan en NOP. La referencia completa está en
la sección 10 de [`docs/isa.md`](docs/isa.md). Un fragmento de
`tools/programas/fibonacci.s`, con cuatro unidades trabajando en el mismo
bundle:

```
        .text
        .org 0x0000

inicio:
        movi r1, #0      | movi r2, #1 ;
        movi r3, #47     | movi r4, #0x100 ;
        - ;
        - ;

lazo:
        add r5, r1, r2   | subi r3, r3, #1 | sw r1, #0(r4) | add.s r4, #4 ;
        - ;
        - ;
```

Los dos `- ;` después de cada productor no son relleno: el hardware no detecta
dependencias, así que quien escribe el programa espera los 3 bundles de latencia
antes de leer el resultado.

Se ensambla directamente, sin `make`:

```bash
python3 tools/cerbero_asm.py tools/programas/fibonacci.s \
        -o fibonacci.hex --datos fibonacci_datos.hex --listado fibonacci.lst
```

```
fibonacci.hex: 14 bundles
fibonacci_datos.hex: 0 palabras
```

`fibonacci.hex` tiene una línea de 32 dígitos hexadecimales por bundle, lista
para `$readmemh` en `imem.sv`:

```
E0800000E10000010000000000000000
E180002FE20001000000000000000000
```

| Opción | Efecto |
|---|---|
| `-o` | Imagen de la memoria de instrucciones |
| `--datos` | Imagen de la memoria de datos, con lo declarado en `.data` |
| `--listado` | Listado con la dirección y la codificación de cada bundle junto a su línea fuente |
| `--bundles N`, `--palabras N` | Rellena las imágenes hasta el tamaño de la memoria que las carga |
| `--cobertura` | Informa qué mnemónicos del conjunto no usa el programa |

Para correrlo y ver el resultado: `make correr PROG=fibonacci.s MOSTRAR=0x100 PALABRAS=47`.

### La herramienta de carga, con distintos tipos de archivo

`load_file.py` acepta cualquier archivo, porque lo trata como bytes. Estas son
tres corridas reales con la interfaz literal del enunciado: un texto, una
imagen PNG y un binario de 20 003 bytes.

```bash
python3 tools/load_file.py --input tools/programas/archivo_prueba.txt --output texto.mem  --address 0x4000
python3 tools/load_file.py --input firma.png                          --output imagen.mem --address 0x4000
python3 tools/load_file.py --input datos.bin                          --output binario.mem --address 0x4000
```

```
tools/programas/archivo_prueba.txt: 23 bytes
  base            0x00004000
  zona usada      0x00004000 a 0x0000401f (32 bytes, cabecera incluida)
  bloques de 64 b 3
  relleno         1 byte(s) en cero

firma.png: 45655 bytes
  base            0x00004000
  zona usada      0x00004000 a 0x0000f25f (45664 bytes, cabecera incluida)
  bloques de 64 b 5707
  relleno         1 byte(s) en cero

datos.bin: 20003 bytes
  base            0x00004000
  zona usada      0x00004000 a 0x00008e2f (20016 bytes, cabecera incluida)
  bloques de 64 b 2501
  relleno         5 byte(s) en cero
```

Cada `.mem` trae las 16 384 palabras de los 64 KB de DMEM. Los primeros 8 bytes
del buffer son una cabecera con el tamaño original, así que los datos empiezan
en `base + 8`. Para sacar un archivo de un volcado de memoria:

```bash
python3 tools/extract_data.py --memory imagen.mem --address 0x4008 --size 45655 --output recuperada.png
cmp firma.png recuperada.png && echo IGUAL
```

**Cifrar y descifrar la imagen en el procesador.** `make cifrar` hace la
cadena completa: carga el archivo, un procesador lo cifra y otro lo descifra.
Después compara el resultado con el original, y comprueba el criptograma contra
el modelo de referencia en Python:

```bash
cd src/build
make cifrar ARCHIVO=../../firma.png
```

```
[5] el archivo volvio
  ok     cabecera y datos iguales al original
[6] aislamiento de la boveda
  ok     ninguna subllave aparece en los 64 KB de datos
casos: 13   fallidos: 0
...
  ok     el modelo de referencia descifra lo que cifro el hardware
  ok     y cifra bloque por bloque lo mismo que el hardware
  criptograma  45656 bytes en 5707 bloques, sin la cabecera:
    00000000  8199d587 e4d5645e 644c8cd6 6949837c
casos: 7   fallidos: 0
RESULTADO: OK
```

El tamaño máximo es 49 144 bytes, lo que cabe entre `0x4008` y el final de la
memoria de datos. Un archivo más grande es un error de `load_file.py`, no un
desborde silencioso.

### Cifrar un archivo con una llave dada

La llave se da en la línea de comandos. No hace falta editar el ensamblador:

```bash
cd src/build
make solo-cifrar ARCHIVO=../../archivo.txt LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
cmp criptograma.bin esperado.bin && echo COINCIDE
```

`LLAVE` funciona igual en `cifrar`, `solo-cifrar` y `solo-descifrar`.
`tools/llave.py` genera en `src/build/llave_gen/` una copia de los programas de
archivo con esa llave, y el testbench y el modelo de referencia reciben la
misma. Sin `LLAVE` se usa la de `cargar_llave.s`. La salida imprime cómo quedó
cada `key[i]` y los primeros bytes del criptograma.

El criptograma queda en `src/build/criptograma.bin`, **sin cabecera**: es el
archivo que se compara contra un resultado calculado por fuera del proyecto.
`cifrado_libre.bin` es el mismo criptograma con la cabecera de 8 bytes que
necesita `solo-descifrar`.

Para descifrar:

```bash
make solo-descifrar CIFRADO=cifrado_libre.bin LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
make solo-descifrar CIFRADO_CRUDO=externo.bin LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
```

La primera forma es para lo que cifró este proyecto: la cabecera trae el tamaño
original y el resultado sale recortado a ese tamaño. La segunda es para un
criptograma **cifrado fuera del proyecto**, sin cabecera: se carga como bloques
puros y, como el tamaño original no viaja en ningún lado, el resultado trae los
ceros de relleno del último bloque. En las dos, el resultado queda en
`src/build/descifrado_libre.bin`, y con `ORIGINAL=ruta` también se compara
contra el archivo original.

**Convenciones.** El enunciado fija la función de ronda pero no cómo se arma un
archivo en bloques. Si un resultado externo no coincide, la diferencia está en
alguna de estas filas:

| | Convención de este proyecto |
| :--- | :--- |
| Llave | La `key[4]` de la Fig. 1 del enunciado: la ronda `i` usa `key[i]`. Se escribe como cuatro palabras separadas por coma, con `key[0]` primero, o como 32 dígitos hexadecimales, donde los **primeros** ocho son `key[0]` |
| Bloques | Little-endian. `L` son los bytes 0 a 3 del bloque y `R` los bytes 4 a 7, cada uno leído como entero de 32 bits con el primer byte en la parte baja. Es lo que hace `memcpy` en un programa en C en una PC |
| Relleno | Ceros hasta completar un múltiplo de 8 bytes. Sólo afecta al último bloque |
| Modo | Cada bloque se cifra por separado. Dos bloques iguales del archivo dan el mismo criptograma |
| Salida | Los bloques completos: el criptograma mide el tamaño del archivo redondeado hacia arriba a múltiplo de 8 |
| Tamaño máximo | 49 144 bytes, lo que cabe entre `0x4008` y el final de la memoria de datos |

Con estas convenciones, el criptograma del procesador coincide byte por byte con
el de la implementación en C de la Fig. 1 del enunciado. Se comprobó con un
archivo binario de 20 003 bytes y la llave `A1B2C3D4 11223344 55667788
99AABBCC`, compilando ese código C sin cambios. En el otro sentido, el
procesador descifra con `CIFRADO_CRUDO` el criptograma que produce ese mismo
código C y recupera el archivo más su relleno.

**La interfaz del enunciado (5.4.3) también funciona.** `load_file.py` acepta
`--input`, `--output` y `--address`, y `extract_data.py` acepta `--memory`,
`--address`, `--size` y `--output`, además de las opciones de siempre. Con
`--size`, `extract_data.py` saca exactamente esa cantidad de bytes desde la
dirección sin mirar la cabecera; como el buffer empieza con 8 bytes de
cabecera, los datos de un archivo cargado en `0x4000` empiezan en `0x4008`.

---

## El bundle, y cuánto se usa de él

Un bundle de CERBERO tiene cinco ranuras y el procesador las ejecuta todas en
el mismo ciclo. Un programa que pone una sola instrucción por bundle es
correcto, pero desperdicia cuatro quintas partes de la máquina.

```bash
make ocupacion                        # el informe, programa por programa
python3 tools/empacar.py x.s -o y.s   # empaquetar uno
```

`tools/empacar.py` es el planificador: toma un programa escrito una operación
por bundle y junta en el mismo bundle las que son independientes, respetando
la latencia de tres, los puertos de escritura y el orden de la memoria. No
tiene tablas de opcodes propias — importa las de `cerbero_asm.py`, para que el
día que cambie una codificación no queden dos versiones de la verdad.

**Lo que empaquetar no puede arreglar.** Una cadena de operaciones dependientes
cuesta tres bundles por eslabón aunque las cinco ranuras estén libres: el
bundle queda vacío porque no hay trabajo independiente, no porque falten
ranuras. En un lazo, el trabajo independiente son las otras vueltas, y
desenrollarlo es lo que las pone a la vista del planificador.

`make vliw` lo mide sobre el mismo cálculo escrito de las dos formas:

| | ciclos | ocupación |
|---|---:|---:|
| `suma_simple.s` tal cual | 1042 | 0.48 |
| `suma_simple.s` empaquetado | 592 | 0.75 |
| `suma_vliw.s` desenrollado | 318 | 0.73 |
| `suma_vliw.s` desenrollado y empaquetado | **262** | **0.96** |

Los cuatro dan 89440. El empaquetado solo vale 1.76×; desenrollar y empaquetar,
**3.98×**. La guía completa, con los patrones y el ejemplo mínimo, está en
[`docs/escribir_programas.md`](docs/escribir_programas.md).

---

## Cobertura actual

| Unidad | Casos | Qué verifica |
|---|---:|---|
| `alu` | 334 | Los 32 opcodes, extensión de signo, enmascarado del desplazamiento, las cuatro banderas, los ocho códigos de condición de `SETcc`, las dos fuentes de `ILLOP` |
| `bru` | 295 | Las ocho condiciones, destino relativo e indirecto, enlace, detención, bits reservados del tipo J |
| `crypto_unit` | 93 | Cifrado y descifrado ronda a ronda, decodificación del par, aislamiento de la subllave sin permiso |
| `key_vault` | 100 | Protocolo completo, `KVALID`, auto-logout, las tres causas de falla, fuga de subllave |
| `lsu` | 245 | Los cuatro carriles en los dos sentidos, postincremento, `ILLOP`, `MISALIGN`, `RANGE` y su prioridad |
| `short_alu` | 92 | Las ocho suboperaciones en las dos formas, aritmética envolvente, combinaciones reservadas |
| `regfile` | 90 | Los 7 puertos de escritura y los 9 de lectura, prioridad ante colisión, y la lectura del negedge sobre la escritura del posedge |
| `imem` | 23 | Lectura síncrona, escalado del índice, bundle nulo fuera de rango, carga por `$readmemh` |
| `dmem` | 38 | Las ocho máscaras de byte con dato replicado, los dos flancos por separado, little-endian, fuera de rango sin envolver |
| `dispatch` | 34 | Los 128 bits del bundle caen en su slot y su posición, enrutado de los 9 puertos de lectura, la excepción de `MOVH`, las 8 codificaciones de par |
| `psw_fault_unit` | 41 | Las 16 combinaciones de banderas, las 6 causas en los 5 slots, los 10 pares de prioridad, `EXC` pegajoso, `WCONF` puerto por puerto |
| `crypto_vault` | 90 | **Integración**: bóveda y unidad de ronda juntas, contra el modelo de referencia |
| `latency` | 3 | **Integración**: mide la latencia expuesta contra el modelo de pipeline y la compara con los 3 bundles del ISA |
| `reg_if_id` | 20 | Retraso de un ciclo exacto medido sobre una secuencia, independencia de `valid` y `pc` |
| `reg_id_ex` | 32 | Aislamiento de los 12 campos con huella de bits, los 9 puertos de lectura uno por uno |
| `reg_ex_mem` | 10 | Aislamiento de los 10 campos, los 7 puertos de escritura y las 5 causas elemento por elemento |
| `wconf` | 12 | **Integración**: 4000 vectores aleatorios comparando los dos detectores de conflicto de escritura, el del banco y el del PSW |
| `fetch` | 50 | Avance de 16 en 16, salto tomado, destino desalineado forzado a múltiplo de 16, `HALT` congela el PC y apaga `valid`, el reset lo libera |
| `pipeline` | 6 | **Integración**: mide la latencia expuesta sobre la cadena real de registros más el banco, y que el PC acompañe al bundle en ID y en EX |
| `fetch_flow` | 23 | **Integración**: `fetch`, `imem`, `reg_if_id` y `bru` sobre un programa de saltos; un delay slot exacto por salto, el de `HALT` se ejecuta, y el caso medido de un salto dentro de un delay slot |
| `top` | 45 | **El procesador completo** corriendo siete programas: aritmética con la latencia de 3 bundles, memoria en los tres tamaños con y sin signo, llamada y retorno, **cifrado Feistel4 completo** contra valores calculados fuera del simulador, la misma rutina denegada fuera de la región segura, `ILLOP` y `MISALIGN`, y que nada se ejecute después de `HALT` |
| `asm` | 12 | **La cadena completa**: el binario que produce `cerbero_asm.py` desde `feistel.s`, corriendo en el RTL, cifrando bien y con el cierre automático de sesión al salir de la región segura |
| `div` | 15 | **La subrutina de división** corriendo en el procesador: seis pares, con divisor cero y con el bit 31 encendido |
| `archivo` | 29 | **La cadena completa sobre un archivo real**: dos procesadores, uno cifra y el otro descifra lo que el primero dejó en memoria; criptograma contra valores calculados fuera del simulador, el archivo recuperado byte por byte, la cabecera intacta, un barrido de los 64 KB de las dos memorias buscando subllaves filtradas, y que ni la llave ni la credencial queden en el banco de registros |
| `cifrado` | 13 | **Un archivo cualquiera**: `make cifrar ARCHIVO=...` sobre un archivo y una llave dados en la línea de comandos, con `probar_flujo.py` de oráculo en vez de valores fijos |
| `credencial` | 7 | **La credencial equivocada**: el `LOGIN` no coincide, `AUTHFAIL` se enciende, las rondas se anulan con `DENIED` y el archivo queda sin cifrar |
| `ejemplos` | 41 | **Los programas de demostración, comprobados**: `fibonacci.s` contra la sucesión que el testbench calcula por su cuenta, los seis resultados de `estadisticas.s` (que llama a `__div32` con enlace y retorno) y las tres fotos del PSW de `sesion_sin_logout.s` |
| `sum` | 3 | **La validación con CE1108**: `suma_10_15.s`, ensamblado con `cerbero_asm.py` y corriendo en este procesador. El origen del programa y la evidencia de la validación conjunta están en [`docs/compiler-integration.md`](docs/compiler-integration.md) |
| `logout` | 15 | **La bóveda sin `LOGOUT`**: una rutina abre sesión dentro de la región segura y vuelve sin cerrarla; el hardware la cierra solo al cruzar la frontera, y una ronda intentada después se anula con `DENIED`. Registra el ciclo y el PC de cada flanco de `AUTH` |
| `vliw` | 7 | **Cuánto cuesta no llenar el bundle**: el mismo cálculo con y sin trabajo independiente, verificando que dan el mismo resultado y midiendo los ciclos de cada uno |
| **`l1_dcache`** | 55 | **Proyecto II.** Fallo y acierto, las dos vías de un conjunto, la víctima LRU, el acierto en un ciclo, write-through con no-write-allocate, un store empujado una sola vez aunque el pipeline espere, el conflicto RAW contra el write buffer, stores de byte y media palabra, la invalidación hacia atrás, y todo eso con el T_mem real |
| **`l2_cache`** | 37 | Fallo y acierto, el hit time medido contra la macro, write-back, write-allocate parcial que conserva los bytes de afuera, el atajo de línea completa, LRU exacto de N vías, la víctima sucia al eviction buffer, el stall por buffer lleno, el vaciado de fin de programa y el contrato `req`/`listo` durante toda la prueba |
| **`l2_arbiter`** | 24 | Prioridad estricta a la lectura de L1, ninguna transacción abandonada a medias, `wb_drenando` durante todo el drenado |
| **`eviction_buffer`** | 63 | FIFO, lleno y vaciado en orden, el conflicto RAW, la fusión por línea con la palabra más reciente ganando, depositar y drenar en el mismo ciclo, y que fusionar contra la cabeza que se drena no pierda el dato |
| **`mem_system`** | 59 | La línea completa, **T_mem medido contra el teórico**, el desalojo aceptado en un ciclo y drenado solo, la lectura de una línea que todavía está en el buffer, la prioridad de la lectura |
| **`mem_clock_gen`** | 14 | Sin ticks en reset, el periodo de `mem_clk`, cada `mem_tick` sobre un flanco de `mem_clk`, los divisores del rango permitido |
| **`perf_counters`** | 95 | Cada contador con un estímulo dirigido: reset, ciclos y `HALT`, ocupación por ranura, bundles vacíos, un bundle congelado contado una sola vez, saltos, saturación, los contadores de L2 y los de la sección 5 del enunciado |
| **`patrones`** | 24 | **Integración**: los patrones secuencial, stride, aleatorio y con reuso sobre el procesador completo, con **oráculos exactos** de aciertos y fallos en L1 y L2 calculados desde la geometría, y el costo de la inclusión |
| **Total** | **2189** | |

A eso se suman **151 casos** de las herramientas en Python, que `make` corre antes y después de los testbenches:

| | |
|---|---|
| `probar_asm.py` | 71 casos: la codificación contra valores calculados a mano, las ocho validaciones que el ISA 10.3 manda rechazar, los rangos de cada operando, qué es advertencia y qué es error, y que los 63 mnemónicos del conjunto estén cubiertos |
| `probar_archivos.py` | 54 casos: ida y vuelta con los tamaños que rompen las cosas (vacío, un byte, exactamente un bloque, y sobre todo un archivo que **termina en cero**), la disposición del buffer contra palabras escritas a mano, lo que debe fallar, el contenedor del archivo cifrado, la interfaz del enunciado y el criptograma crudo |
| `probar_llave.py` | 19 casos: el orden de `key[0..3]` en las dos formas de escribir la llave, contra valores escritos a mano, y que el programa generado la arme en `r5` a `r8` |
| `probar_flujo.py` | 7 casos: toma el volcado de `$writememh` que dejó `tb_archivo` o `tb_cifrado`, lo convierte en contenedor cifrado con `extract_data.py --cifrado` y lo descifra con un **modelo de referencia escrito sólo desde la fórmula del enunciado**, que no comparte una línea con el RTL ni con el ensamblador |

El último es el que cierra el argumento. `tb_archivo` comprueba que el hardware
descifra lo que cifró, pero eso se cumpliría igual si `F4E` y `F4D` estuvieran
mal de forma inversa. Si el criptograma que produjo el procesador se deshace con
un modelo independiente, entonces el procesador implementa Feistel4 y no otra
cosa parecida.

### Autoprueba del arnés

Un testbench que siempre pasa no prueba nada. Todos los que verifican, salvo `tb_sum`, aceptan `-DFORCE_FAIL`,
que inyecta un caso deliberadamente incorrecto para comprobar que el arnés sabe
reportar una falla:

```bash
iverilog -g2012 -Wall -I ../cpu -DFORCE_FAIL -s tb_lsu -o /tmp/f.vvp \
         ../cpu/lsu.sv ../tb/tb_lsu.sv
vvp -n /tmp/f.vvp ; echo "codigo de salida: $?"     # debe ser distinto de 0
```

---

## Estructura

```
ARQUITECTURA/
├── README.md
├── barrido/
│   ├── jerarquia/               Barrido de la Iteración 5: un directorio por configuración
│   │   └── tablas.md            Las tablas que genera tabla_analisis.py
│   └── <capacidad>_2vias/       Barrido de capacidad de L1 de la Iteración 3
├── docs/
│   ├── jerarquia-memoria.md     Políticas de la jerarquía y su justificación
│   ├── organizacion.md          Diagramas de bloques y flujo del sistema extendido
│   ├── analisis-rendimiento.md  Metodología, benchmarks, resultados y comparaciones
│   ├── decisiones.md            Registro de decisiones de diseño
│   ├── metricas.md              Contadores y línea base (Iteración 1)
│   ├── memoria.md               Memoria principal y T_mem (Iteración 2)
│   ├── cache.md                 La L1-D y su integración (Iteración 3)
│   ├── isa.md                   Especificación del ISA (contrato con CE1108)
│   ├── microarchitecture.md     Organización interna del Proyecto I
│   ├── simulation.md            Modelo de simulación
│   ├── compiler-integration.md  Contrato con CE1108 y validación conjunta
│   ├── escribir_programas.md    Guía para escribir un programa
│   ├── del_fuente_al_binario.md Del fuente al binario
│   ├── respuesta_a_la_revision.md
│   └── imgs/                    Figuras; it5_*.png son los gráficos del barrido
├── tools/
│   ├── cerbero_asm.py           Ensamblador propio
│   ├── probar_asm.py            Sus pruebas, 71 casos
│   ├── empacar.py               Planificador: junta operaciones independientes
│   ├── load_file.py             Archivo a imagen de memoria
│   ├── extract_data.py          Volcado de memoria a archivo
│   ├── formato_buffer.py        El formato que comparten las dos
│   ├── probar_archivos.py       Sus pruebas, 54 casos
│   ├── llave.py                 La llave desde la línea de comandos
│   ├── probar_llave.py          Sus pruebas, 19 casos
│   ├── probar_flujo.py          El flujo completo contra el modelo de referencia
│   ├── probar_descifrado.py     El descifrado del hardware contra el modelo
│   ├── huella.py                SHA-256 del criptograma
│   ├── novac_image.py           Ejecutable NOVA a imágenes de memoria
│   ├── listado_a_texto.py       El texto de cada bundle, para la traza de make correr
│   ├── barrido_jerarquia.sh     Barrido de la jerarquía (make analisis)
│   ├── tabla_analisis.py        Sus tablas y gráficos
│   ├── tabla_metricas.py        Tabla de make metricas
│   ├── barrido_cache.sh         Barrido de capacidad de L1 de la Iteración 3
│   ├── tabla_barrido.py         Su tabla
│   └── programas/
│       ├── feistel.s            Cifrado de un bloque con sesión de bóveda
│       ├── cifrar_archivo.s     Cifra un archivo completo, bloque por bloque
│       ├── descifrar_archivo.s  Y lo devuelve a claro
│       ├── cargar_llave.s       Prólogo incluido por los dos: constantes
│       ├── vault_sesion.s       Prólogo incluido por los dos: sesión y llave
│       ├── archivo_prueba.txt   El archivo de 23 bytes que se cifra
│       ├── fibonacci.s          F(0) a F(46), aritmética encadenada
│       ├── estadisticas.s       Suma, máximo, mínimo y promedio con __div32
│       ├── sesion_sin_logout.s  El cierre automático de sesión, visto por el programa
│       ├── contar_hasta_n.s     Un lazo que solo escribe
│       ├── lazo_estres.s        100 000 vueltas con los cinco slots ocupados
│       ├── div32.s              Subrutina de división sin signo
│       ├── div32_prueba.s       Seis pares para probarla
│       ├── suma_10_15.s         El programa de la validación con CE1108
│       ├── suma_simple.s        Un cálculo escrito una operación por bundle
│       ├── suma_vliw.s          El mismo, desenrollado
│       ├── cobertura.s          Usa el 100% del conjunto de instrucciones
│       ├── recorrido_cache.s    Escrito para saturar el write buffer
│       ├── patron_secuencial.s  Recorrido secuencial: localidad espacial perfecta
│       ├── patron_stride.s      Paso de una línea: localidad espacial nula
│       ├── patron_aleatorio.s   Direcciones pseudoaleatorias
│       └── patron_reuso.s       Dos pasadas sobre 8 KB: cabe en L2 y no en L1
└── src/
    ├── build/
    │   └── makefile             Punto de entrada de simulación y lint
    ├── cpu/
    │   ├── cerbero_defs.svh     ISA, geometría y latencias de la jerarquía
    │   ├── regfile.sv           Banco de registros
    │   ├── alu.sv               S0 y S1
    │   ├── lsu.sv               S2
    │   ├── crypto_unit.sv       S3, ronda Feistel4
    │   ├── key_vault.sv         S3, bóveda
    │   ├── short_alu.sv         S3, ALU corta
    │   ├── bru.sv               S4
    │   ├── imem.sv              Memoria de instrucciones
    │   ├── dmem.sv              Memoria de datos del Proyecto I (referencia)
    │   ├── dispatch.sv          Etapa ID
    │   ├── psw_fault_unit.sv    PSW y unidad de fallas
    │   ├── fetch.sv             Etapa IF, contador de programa
    │   ├── reg_if_id.sv         Frontera IF/ID
    │   ├── reg_id_ex.sv         Frontera ID/EX
    │   ├── reg_ex_mem.sv        Frontera EX/MEM
    │   ├── load_align.sv        Extracción del carril, usada en MEM
    │   ├── l1_dcache.sv         Caché L1-D
    │   ├── l2_arbiter.sv        Árbitro entre la L1 y el write buffer
    │   ├── l2_cache.sv          Caché L2 unificada
    │   ├── eviction_buffer.sv   Write buffer y eviction buffer
    │   ├── mem_system.sv        Envoltorio de la memoria principal
    │   ├── mem_controller.sv    FSM del acceso a memoria
    │   ├── mem_clock_gen.sv     Divisor de reloj de la memoria
    │   ├── main_memory.sv       64 KB, escritura por byte
    │   ├── perf_counters.sv     Contadores de rendimiento
    │   └── top.sv               El procesador completo
    └── tb/
        ├── key_vault_model.sv   Modelo de bóveda para probar crypto_unit sola
        ├── tb_<unidad>.sv       Un testbench por unidad
        ├── tb_crypto_vault.sv   Cosimulación de bóveda y ronda
        ├── tb_latency.sv        Medición de la latencia expuesta
        ├── tb_wconf.sv          Cosimulación de los dos detectores de WCONF
        ├── tb_pipeline.sv       Latencia expuesta sobre la cadena de registros
        ├── tb_fetch_flow.sv     Búsqueda, delay slot y HALT con la BRU real
        ├── tb_top.sv            Siete programas sobre el procesador completo
        ├── tb_patrones.sv       Patrones de acceso contra oráculos exactos
        ├── tb_asm.sv            El binario del ensamblador sobre el RTL
        ├── tb_div.sv            La subrutina de división sobre el RTL
        ├── tb_archivo.sv        Cifrado y descifrado de un archivo completo
        ├── tb_cifrado.sv        Lo mismo sobre un archivo y una llave cualesquiera
        ├── tb_credencial.sv     Con la credencial equivocada no se cifra nada
        ├── tb_descifrado.sv     Descifra un .bin de disco (manual)
        ├── tb_ejemplos.sv       Los programas de demostración, comprobados
        ├── tb_sum.sv            El programa de la validación con CE1108
        ├── tb_vliw.sv           El mismo cálculo con y sin paralelismo
        ├── tb_logout.sv         La bóveda sin LOGOUT
        ├── tb_programa.sv       Ejecutor de make correr: traza e informe de métricas
        ├── imem_init.hex        Programa de ejemplo para tb_imem
        └── dmem_init.hex        Datos de ejemplo para tb_dmem
```

### `cerbero_defs.svh`

Única fuente de verdad para los números del ISA: anchos, posiciones de campo,
opcodes de los cinco slots, códigos de condición, bits del PSW y causas de
falla, y desde el Proyecto II también la geometría y las latencias de la
jerarquía, con guardas `ifndef` para que un barrido las sobreescriba con `-D`.
Lo incluyen todos los módulos y los testbenches, de modo que renumerar un
opcode se hace en una línea y el RTL y las pruebas quedan sincronizados. Si
estuviera escrito a mano en cada archivo, un testbench podría quedar probando
una codificación que el módulo ya no implementa, y ambos "pasarían".

---

## Cómo agregar una unidad

El `makefile` descubre las unidades por patrón, así que no hay que tocarlo:

1. `src/cpu/<unidad>.sv` con el módulo.
2. `src/tb/tb_<unidad>.sv` con el testbench, módulo `tb_<unidad>`.
3. Si el módulo instancia a otros, declarar la dependencia en el `makefile`:
   `DEPS_<unidad> := $(CPU)/otro.sv`

Para un testbench de integración, que no tiene un `cpu/<nombre>.sv` detrás,
agregar el nombre a `NO_RTL`.
