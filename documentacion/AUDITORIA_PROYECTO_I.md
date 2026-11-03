# Auditoría del Proyecto I contra ambas especificaciones

Revisión del estado entregado contra los dos documentos oficiales:

- **CE1108** — *Proyecto: Compilador para Código Binario* (12 p.)
- **CE4301** — *Proyecto Grupal I: Arquitectura VLIW Propia* (16 p.)

Hecha antes de continuar con la Iteración 2 del Proyecto II.

---

## Resumen

| | |
|---|---|
| Requisitos verificados | 41 |
| Cumplidos sin observación | 40 |
| Hueco encontrado y corregido | 1 |

El único hueco real estaba en el mismo punto por el que ya les habían
penalizado: información que el compilador **sí calcula** pero que **no mostraba**
donde el revisor la busca. Está corregido (sección 3).

---

## 1. Los dos señalamientos de la revisión anterior

### 1.1 «No estaba enlazado con la última versión de la arquitectura»

**Verificado: resuelto.** El contraste automático contra el ensamblador
independiente del equipo de CE4301 (`ARQUITECTURA/tools/cerbero_asm.py`) da
coincidencia exacta:

```
$ sh tools/verificar.sh 12
factorial            IDENTICO bit a bit     166 bundles
busqueda_matriz      IDENTICO bit a bit     683 bundles
mergesort            IDENTICO bit a bit    1216 bundles
multiplicacion       IDENTICO bit a bit    2389 bundles
cifrado              IDENTICO bit a bit    1935 bundles
...
identicos: 20, distintos: 0, pendientes de enlazar: 2
```

Veinte programas producen **el mismo binario bit a bit** por los dos caminos:
el que emite `novac` directamente y el que produce el ensamblador de la
arquitectura desde el `.asm`. Los dos equipos leen el ISA igual.

Los dos «pendientes de enlazar» no son fallas: son programas que usan
`importa`, y el ensamblador de CE4301 trabaja sobre un módulo a la vez.

**Versión del ISA.** `isa.md` va en la v1.6. Las dos últimas entradas del
registro de cambios se revisaron una por una:

| Versión | ¿Afecta al código generado? | Estado |
|---|---|---|
| v1.5 — el `LOGIN` y el lazo de rondas deben quedar dentro de `[SEC_BASE, SEC_LIMIT]` | **Sí** | atendido; el compilador avisa con `W008` si el código de bóveda no cabe en la región |
| v1.6 — cabecera del archivo cifrado | No (sólo herramientas) | nada que cambiar en el compilador |

### 1.2 «La tabla de símbolos no mostraba la dirección de memoria»

**Verificado: resuelto.** `novac --sym` muestra ahora, para cada nombre, la
dirección exacta:

```
n          param   factorial   integer   1   DMEM @0xFFE4  = r14+8    4  linea 1:19
resultado  varia   factorial   integer   1   DMEM @0xFFE0  = r14+4    4  linea 2:11
factorial  functio global      integer   0   IMEM @0x0070             0  linea 1, 1 param, marco 20 B
```

El mismo dato aparece en el panel de símbolos del IDE y en el globo del
autocompletado.

---

## 2. CE1108 — verificación requisito por requisito

### Fases del compilador (§2)

| § | Requisito | Estado |
|---|---|---|
| 2.1 | Palabras reservadas, identificadores, constantes numéricas, operadores, delimitadores, comentarios | cumple — 23 reservadas, enteros decimales y hexadecimales, comentarios de línea `#` y de bloque `#{ }#` |
| 2.2 | Representación interna (AST) | cumple — `fase2_sintactico/ast.c`, visible con `-t` |
| 2.2 | Declaraciones, asignaciones, llamadas y control con sintaxis validada | cumple |
| 2.2 | Bloques correctamente delimitados y anidados | cumple |
| 2.3 | Tabla de símbolos con tipo, **dirección de memoria** y ámbito | cumple (corregido tras la revisión) |
| 2.3 | Resolver referencias; declaración antes de uso; argumentos correctos | cumple — E301, E304, E305 |
| 2.3 | Asignar direcciones según el diseño de la arquitectura | cumple — mapa de CERBERO en `symtab.h` |
| 2.3 | **Registrar puntos de salto (etiquetas) y sus direcciones** | **era el hueco** — ver sección 3 |
| 2.4 | Ensamblador para asignaciones, aritmética y lógica | cumple |
| 2.4 | Saltos condicionales e incondicionales para `if`, `while`, `for` | cumple |
| 2.4 | Llamadas, paso de parámetros y retorno | cumple |
| 2.4 | Contador de instrucciones para calcular direcciones | cumple |
| 2.5 | Identificar etiquetas y sus direcciones numéricas | cumple |
| 2.5 | Resolver referencias a etiquetas | cumple — `resolver_direcciones()` |
| 2.5 | Desplazamientos relativos o direcciones absolutas | cumple |
| 2.5 | Saltos dentro de condicionales anidados y ciclos | cumple |
| 2.6 | Opcodes por instrucción | cumple |
| 2.6 | Codificar operandos | cumple |
| 2.6 | Archivo binario final | cumple — `.nvx` |

### Arquitectura (§3)

| § | Requisito | Estado |
|---|---|---|
| 3.1 | Tamaño de palabra de instrucción documentado | cumple — bundle de 128 bits, 5 slots |
| 3.2 | Número y propósito de registros; temporales, parámetros, retorno; código numérico | cumple — 16 registros; R14 pila, R15 enlace, R6 retorno |
| 3.3 | Memoria total, segmentos, asignación de direcciones | cumple — 64 KB; globales `0x0000–0x3FFF`, pila desde `0xFFFC` |
| 3.4 | **Mínimo 15 instrucciones** en las categorías exigidas | cumple — más de 60 |

Las siete categorías que pide el documento están todas: carga/almacenamiento
(`LW`, `SW`, `LB`, `SB`…), aritméticas (`ADD`, `SUB`, `MUL`, división por
rutina), lógicas (`AND`, `OR`, `NOT`, `XOR`), comparación (`CMP`, `CMPI`,
`TEST`), saltos (`BR`, `JAL`, `JALR`, `JR`), control de flujo (`JAL`/`JR` para
llamada y retorno) y especiales (`NOP`, `HALT`).

### Lenguaje de entrada (§4)

| Requisito | Nova |
|---|---|
| Comentarios | `#` de línea, `#{ }#` de bloque |
| Declaración de variables | `varia x : integer = 10;` |
| Asignaciones | `=`, `+=`, `-=`, `*=`, `/=`, `%=` |
| Expresiones aritméticas, lógicas y de comparación | completas |
| Condicionales `if` / `else if` / `else` | `si` / `sin` / `aliter` |
| Ciclos `while` o `for` | `dum` y `per` — están los dos |
| Funciones con parámetros y retorno | `functio … -> tipo`, `redde` |
| Llamadas con paso de argumentos | sí, incluidos arreglos por referencia |

### Invocación (§5.1)

Las siete opciones exigidas existen y se verificaron una por una:

| Opción | Exigido | Estado |
|---|---|---|
| `-o <archivo>` | nombre de salida | funciona |
| `-v` | modo detallado por fase | funciona |
| `-s` | genera `.asm` además del binario | funciona |
| `-t` | imprime el AST | funciona |
| `-m` | tabla de símbolos y asignaciones de memoria | funciona |
| `-x` | ensambla un `.s` a binario | funciona |
| `-p` | paquetes de instrucciones en ensamblador y binario | funciona |

### Salida (§6) y ejercicios (§7)

| Requisito | Estado |
|---|---|
| Binario con encabezado, código y datos | cumple — encabezado `.nvx` de 48 B con versión, tamaños, punto de entrada, ubicación de datos y checksum |
| `.asm` con mnemotécnicos, números de línea y direcciones | cumple |
| `.asm` con tabla de símbolos (etiquetas y direcciones) | cumple |
| Ejercicio 1 — factorial con locales, condicional, ciclo y aritmética | `test/factorial.nv` |
| Ejercicio 2 — búsqueda en matriz 2D | `test/ejemplos/busqueda_matriz.nv` |
| Ejercicio 3 — propuesto, con funciones, llamadas múltiples y anidamiento | `test/ejemplos/mergesort.nv` |

**Nota sobre §9.1.** La guía dice que esta primera versión *no* necesita manejo
exhaustivo de errores ni módulos múltiples. El proyecto hace las dos cosas de
todos modos: 44 códigos de error con posición exacta, 10 advertencias, y un
enlazador de módulos con `importa … ut`. Va por encima de lo pedido, no por
debajo.

---

## 3. El hueco encontrado, y su corrección

### Qué decía la especificación

> **§2.3 (Fase 3)** — «Registrar puntos de salto (etiquetas) y sus direcciones
> en memoria para condicionales y ciclos.»

### Qué estaba pasando

El cálculo **estaba hecho y era correcto** —los saltos se resuelven, los
programas corren bien sobre el RTL— y la tabla de etiquetas con sus direcciones
**sí se emitía**, pero sólo como comentario dentro del archivo `.asm`:

```asm
//   ETIQUETA                     DIRECCION  UBICACION
//   __inicio                     0x0000     IMEM bundle 0
//   principale                   0x0070     IMEM bundle 7
```

Eso cumple §6.2 («Archivo de Ensamblador … tabla de símbolos (etiquetas y
direcciones)»), pero **no §2.3**: en la vista de tabla de símbolos —`-m`, que
es la que el profesor abre para revisar este punto— las etiquetas no aparecían.

Es exactamente la misma forma de problema que el de la revisión anterior: el
dato existe, el compilador lo calcula bien, y no está donde se lo busca.

### Qué se hizo

`construir_programa()` resuelve cada etiqueta a su bundle y `liberar_todo()`
borra esas estructuras enseguida, así que la información se perdía al terminar
la fase 4. Ahora se toma una copia antes de liberar y se expone:

- `codegen.h` — `codegen_etiquetas()` devuelve la tabla resuelta.
- `novac --sym` — la imprime debajo de la tabla de símbolos.
- El IDE la muestra en el panel de símbolos y la devuelve en su JSON.

Resultado sobre `prueba.nv`, que tiene un ciclo `dum` y un condicional:

```
=== Puntos de salto y etiquetas resueltas ===
ETIQUETA                       DIRECCION    BUNDLE UBICACION
------------------------------------------------------------------------
__out_n                        0x3000       -      DMEM (dato)
__out_buf                      0x3004       -      DMEM (dato)
__inicio                       0x0000       0      IMEM (codigo)
factorial                      0x0070       7      IMEM (codigo)
__factorial_cuerpo             0x00B0       11     IMEM (codigo)
L0                             0x0150       21     IMEM (codigo)   <- cabeza del ciclo 'dum'
__c0_si                        0x0230       35     IMEM (codigo)   <- rama del 'si'
__c0_fin                       0x0260       38     IMEM (codigo)   <- salida del 'si'
L1                             0x0440       68     IMEM (codigo)
principale                     0x04A0       74     IMEM (codigo)
__principale_cuerpo            0x04E0       78     IMEM (codigo)
__scribe_int                   0x0700       112    IMEM (codigo)
12 etiquetas en total.
```

`L0` es la cabeza del ciclo y `__c0_si` / `__c0_fin` son las dos etiquetas del
condicional: precisamente lo que pide el requisito.

### Verificación

- Las direcciones de las funciones coinciden con las que ya mostraba la tabla
  de símbolos (`factorial` en `0x0070`, `principale` en `0x04A0`).
- Una prueba nueva comprueba que las direcciones que reporta el IDE son las
  mismas que imprime `novac --sym`: el editor no puede calcular una cosa y el
  compilador otra.
- Las 233 pruebas del compilador siguen pasando.
- Los 20 programas siguen siendo idénticos bit a bit contra el ensamblador de
  CE4301, así que el cambio no tocó la codificación.

---

## 4. CE4301 — lo que toca al compilador

El componente de arquitectura se evalúa aparte; aquí sólo se verificó lo que la
especificación pone del lado del contrato con el compilador.

| § | Requisito | Estado |
|---|---|---|
| 6.1 | El compilador llega hasta binario, en el formato de bundles de la arquitectura | cumple |
| 6.1 | El ensamblador propio funciona de forma autónoma, sin depender del compilador | cumple — `cerbero_asm.py` |
| 6.1 | Especificación completa del ISA entregada a la contraparte, con codificación binaria exacta | cumple — `isa.md`, 1083 líneas con el *instruction reference sheet* |
| 6.1 | Todo cambio al ISA comunicado formalmente | cumple — registro de cambios v1.1 a v1.6 en §14 |
| 6.2 | Al menos un programa del compilador ejecutado sobre el procesador | cumple — `make prueba-rtl`, 13 programas |
| 7 | `docs/` con `isa.md`, `microarchitecture.md`, `simulation.md`, `compiler-integration.md` | los cuatro presentes |
| 5.3 | Ensamblador propio | `ARQUITECTURA/tools/cerbero_asm.py` |
| 5.4 | Herramienta de carga y de extracción de archivos | `load_file.py`, `extract_data.py` |

---

## 5. Comandos que reproducen esta auditoría

```bash
make                      # compilador + núcleo del IDE
make prueba               # 233 pruebas del compilador
make prueba-ide           # 48 pruebas del IDE
sh tools/verificar.sh 12  # codificación idéntica al ensamblador de CE4301
./novac --sym prueba.nv   # símbolos con dirección + puntos de salto
make prueba-rtl           # 13 programas ejecutados sobre el procesador
make todo                 # la cadena completa
```
