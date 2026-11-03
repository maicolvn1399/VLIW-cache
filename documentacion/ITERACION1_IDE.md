# Proyecto II — Iteración 1 del compilador: el IDE

**CE1108 Compiladores e Intérpretes · lenguaje Nova · arquitectura CERBERO**

Este documento cubre la Iteración 1 del componente de compiladores, que la
especificación define como:

> *Iteración 1: Se debe realizar el IDE con todos sus requerimientos,
> incluyendo las mejoras del proyecto 1.*

Los requerimientos del IDE (sección 4, punto 4 de la especificación) son cuatro:

1. Sugerencias de código mientras se escribe.
2. Corrección automática de errores (terminación de línea, llaves, paréntesis).
3. Detección de errores marcados gráficamente y con buena descripción.
4. Detección de clones de código Tipo I y Tipo II, capaz de operar entre
   archivos.

---

## 1. Decisión de arquitectura

El profesor fijó la restricción principal: **la lógica del IDE y del compilador
va en C; la interfaz puede ir en Python, Java o C.** De ahí sale la división:

```
┌──────────────────────────────────────────────────────────────┐
│  Interfaz (navegador: HTML + CSS + JavaScript)               │
│  Dibuja. No contiene ninguna regla del lenguaje Nova.        │
└───────────────────────────┬──────────────────────────────────┘
                            │ JSON por HTTP (localhost)
┌───────────────────────────▼──────────────────────────────────┐
│  ide/servidor.py  (Python)                                   │
│  Transporte. Escribe el buffer en un temporal e invoca el    │
│  núcleo. Tampoco conoce el lenguaje.                         │
└───────────────────────────┬──────────────────────────────────┘
                            │ argumentos + JSON por stdout
┌───────────────────────────▼──────────────────────────────────┐
│  novaide  (C)  ← toda la lógica del IDE                      │
│    fase5_ide/ide_diag.c       diagnósticos y tabla de símbolos│
│    fase5_ide/ide_completar.c  sugerencias de código           │
│    fase5_ide/ide_arreglar.c   corrección automática           │
│    fase5_ide/ide_clones.c     clones Tipo I, II y III         │
│    fase5_ide/ide_lex.c        tokenización (llama a yylex)    │
│    fase5_ide/ide_catalogo.c   descripción de cada diagnóstico │
└───────────────────────────┬──────────────────────────────────┘
                            │ enlaza las MISMAS unidades
┌───────────────────────────▼──────────────────────────────────┐
│  Fases 1 a 4 del compilador (las del Proyecto I)             │
│    lex.yy.c · nova.tab.c · semantic.c · symtab.c · tac.c     │
│    codegen.c · enlace.c · diag.c                             │
└──────────────────────────────────────────────────────────────┘
```

### 1.1 Un solo analizador, no dos

La decisión central del diseño es que **`novaide` enlaza los mismos objetos que
`novac`**, no una copia ni una reimplementación. En el Makefile:

```make
NUCLEO_OBJS = $(filter-out main.o,$(OBJS))

$(IDE_BIN): $(IDE_OBJS) $(NUCLEO_OBJS)
	$(CC) $(CFLAGS) -o $@ $(IDE_OBJS) $(NUCLEO_OBJS)
```

La consecuencia es que **el editor no puede discrepar del compilador**:

- Los errores que subraya son los que emiten `nova.l`, `nova.y` y `semantic.c`,
  con la línea, la columna y el largo que esas fases calcularon.
- El coloreado del código se pinta con el flujo de tokens de `yylex()`. Si
  mañana se agrega una palabra reservada a `nova.l`, el editor la pinta como
  reservada sin tocar una línea de JavaScript.
- La tabla de símbolos del panel es la de `symtab.c`, con las direcciones de
  memoria que calcula la fase 4.

La alternativa habitual —escribir un tokenizador en JavaScript y una lista de
palabras reservadas en el frontend— era bastante más rápida de programar, pero
produce dos definiciones del lenguaje que se separan con el primer cambio.

### 1.2 Un proceso por petición

`novaide` atiende **un trabajo por ejecución** y termina. No es un servidor
persistente.

La razón es concreta: el lexer que genera Flex y el parser que genera Bison
llevan estado global (`yylval`, `yylloc`, el buffer de entrada, la pila de
llaves abiertas, los contadores de `diag.c`). Reutilizarlos dentro de un mismo
proceso para análisis sucesivos es una fuente conocida de resultados que
dependen del orden de las peticiones. Arrancar un proceso cuesta menos de un
milisegundo y, a cambio, **cada análisis parte exactamente del mismo estado que
una compilación recién lanzada**.

### 1.3 Protocolo

Todo trabajo responde un objeto JSON por la salida estándar, así que el núcleo
se puede probar y demostrar sin la interfaz:

```bash
./novaide diagnosticar programa.nv
./novaide completar programa.nv --linea 7 --columna 12
./novaide arreglar programa.nv
./novaide clones a.nv b.nv c.nv --min-tokens 20 --umbral 0.80
./novaide tokens programa.nv
./novaide catalogo
```

---

## 2. Mejoras al Proyecto I

La especificación pide que el lexer y el parser «corrijan los aspectos del
primer proyecto». Las mejoras estructurales introducidas en esta iteración son:

### 2.1 Extracción del enlazador a su propia unidad

En el Proyecto I, la lectura de fuentes, las fases 1 y 2, y todo el enlace de
módulos vivían dentro de `main.c` como funciones `static`. Eso las ataba al
ejecutable del compilador: cualquier otra herramienta que necesitara el mismo
análisis tenía que reimplementarlo.

Se movieron sin cambiar su comportamiento a `fase2_sintactico/enlace.c` +
`enlace.h`:

| Antes | Ahora |
|---|---|
| `main.c` (1218 líneas) con el enlazador adentro | `main.c` (704 líneas) + `enlace.c` (542 líneas) |
| `parse_source`, `link_modules`, `release_modules` privadas | expuestas en `enlace.h` |
| `-I` guardado en dos arreglos paralelos (`rutas_modulos` sin usar) | un solo `nova_agregar_ruta_modulos()` |

**Verificación:** las 233 pruebas del compilador siguen pasando sin
modificaciones (`make prueba`). La extracción es observablemente neutra.

### 2.2 Puntos de salto en la tabla de símbolos

La guía de CE1108 pide en la Fase 3 «registrar puntos de salto (etiquetas) y
sus direcciones en memoria para condicionales y ciclos». El cálculo ya estaba
hecho y la tabla se emitía como comentario dentro del `.asm`, pero no aparecía
en la vista de `--sym`, que es donde se la busca. Ahora `codegen_etiquetas()`
expone la tabla resuelta, y la muestran tanto `novac --sym` como el panel de
símbolos del IDE. El detalle está en `AUDITORIA_PROYECTO_I.md`.

### 2.3 Modo captura en `diag.c`

`diag.c` sólo sabía escribir en `stderr` y abortaba el proceso al llegar al
máximo de errores. Se agregó un modo captura (`diag_capturar`) que guarda cada
diagnóstico como un registro estructurado —severidad, código, archivo, línea,
columna, largo, mensaje— y **no aborta**.

Esto es lo que permite que el editor subraye el fragmento exacto en vez de
analizar texto, y que un archivo con 60 errores muestre los 60 en vez de
cortarse en el 25. El compilador de línea de comandos nunca enciende el modo,
así que su comportamiento observable no cambió.

---

## 3. Requerimiento 1 — Sugerencias de código

**Implementación:** `fase5_ide/ide_completar.c`

El completado corre casi siempre sobre un archivo que todavía no compila, así
que trabaja en dos capas:

| Capa | Siempre disponible | Qué aporta |
|---|---|---|
| Léxica | sí | qué se declaró y dónde, deducido del flujo de tokens |
| Semántica | sólo si el archivo analiza | tipo exacto, firma, y dirección de memoria |

Un archivo a medio escribir tokeniza sin problema aunque no parsee, de modo que
la capa léxica nunca se queda sin respuesta; la semántica se suma cuando puede.

### 3.1 El contexto decide qué se ofrece

Ofrecer siempre la lista completa es más fácil de programar y mucho peor de
usar. El contexto se deduce del token inmediatamente anterior al cursor:

| Contexto | Se detecta por | Se ofrece |
|---|---|---|
| `tipo` | el token previo es `:` o `->` | `integer`, `veritas`, `textus`, `nihil` — y nada más |
| `sentencia` | el token previo es `;`, `{` o `}`, dentro de una función | plantillas, palabras reservadas, nombres visibles, intrínsecas |
| `expresion` | cualquier otro punto dentro de una función | `et`, `aut`, `non`, `verum`, `falsum`, nombres visibles, intrínsecas |
| `global` | profundidad de llaves cero | sólo `functio`, `constans`, `privatum`, `importa` |

El contexto `global` refleja una regla real del lenguaje: fuera de las funciones
Nova sólo admite `constans` y `functio` (error E320), así que ofrecer `varia`
ahí sería sugerir un error.

### 3.2 Prefijo

El prefijo se toma **desde el inicio de la palabra hasta el cursor**, no la
palabra completa: al escribir `res|ultado` se completa sobre `res`. Un cursor
pegado al final de la palabra cuenta igual que uno en medio.

### 3.3 Plantillas

Siete plantillas (`functio`, `principale`, `si`, `si-aliter`, `dum`, `per`,
`importa`) se insertan con la sangría de la línea donde se invocan y dejan el
cursor en el primer hueco.

### 3.4 Dirección de memoria en el globo

Cuando el archivo analiza, cada nombre sugerido muestra dónde vive:
`DMEM @0xFFE0 = r14+4` para una local, `IMEM @0x0070` para una función. Sale de
correr el layout de la fase 4 (`codegen_update_symbol_layout`), el mismo cálculo
que `novac --sym`.

---

## 4. Requerimiento 2 — Corrección automática de errores

**Implementación:** `fase5_ide/ide_arreglar.c`

Hay **dos fuentes de arreglos** y se usan las dos, porque cada una sabe cosas
que la otra no.

### 4.1 Fuente A: el propio parser

`nova.y` ya clasifica sus errores. Cuando lo único que esperaba era un `;`
emite **E202 exactamente en el final de la sentencia anterior**; cuando un `{`
no se cierra emite **E203 en la llave culpable**. Un arreglo derivado de ahí no
es una adivinanza: es el token que el analizador necesitaba en ese punto.

| Código | Arreglo | Confianza |
|---|---|---|
| E202 | insertar `;` en la posición reportada | alta |
| E201 con un solo símbolo esperado | insertar ese símbolo | alta |
| E209 | insertar `-> integer` | media |
| E204 | insertar `: integer` | media |
| E102 / E103 | señalar la cadena o el comentario sin cerrar | alta |

### 4.2 Fuente B: balanceo de delimitadores sobre los tokens

El parser se detiene en el primer error de cada región; con varios paréntesis o
corchetes sin cerrar sólo reporta el primero. El balanceo los ve todos a la vez
y además distingue el caso contrario —un cierre que sobra— que no tiene código
de error propio.

**Precedencia:** si el parser ya identificó un delimitador faltante, el balanceo
se omite por completo. Lo que el balanceo ve en ese caso son los cierres que
quedaron descuadrados *aguas abajo* del error real, y proponer arreglos para
esos desplaza el problema en vez de resolverlo. Aplicado el arreglo del parser,
el editor vuelve a analizar y, si todavía falta algo, ahí sí entra el balanceo.

### 4.3 Dónde va la llave que falta: la sangría

Insertar la `}` al final del archivo siempre produce un programa balanceado,
pero casi nunca es lo que el programador quería: si olvidó cerrar un `si`, el
resto de la función termina dentro de la condición y **el programa compila
haciendo otra cosa**.

La heurística usa la sangría, que es la única pista que queda sobre la
intención. Dos reglas:

**Regla 1 — punto de inserción.** Para un `{` abierto en una línea con sangría
*I*, la llave va antes de la primera línea posterior con sangría ≤ *I*. Es el
corte que el programador dibujó: ahí dejó de escribir dentro del bloque.

**Regla 2 — cierre a destiempo.** Si aparece un `}` con *menos* sangría que la
línea donde abrió el bloque más interno, ese `}` fue escrito para cerrar un
bloque de afuera: el de adentro quedó sin cerrar. El conteo de llaves por sí
solo no distingue este caso —sigue cuadrando una apertura con un cierre— y es
justo el error más común al olvidar una llave dentro de una función.

Ejemplo real (`test/ide/llave_sin_cerrar.nv`):

```nova
functio clasificar(v : integer) -> integer {   ← sangría 0
    varia r : integer = 0;
    si (v > 100) {                             ← sangría 4
        r = 2;                                 ← sangría 8
    aliter {                                   ← sangría 4  ...falta la '}'
        r = 1;
    }
    redde r;
}                                              ← sangría 0
```

El conteo de llaves dice que falta una. Sin la sangría, se insertaría al final
y `redde r` quedaría dentro del `si`. Con la Regla 2, el `}` de la línea final
tiene sangría 0 y el bloque más interno abrió con sangría 4, así que **la llave
se propone antes de la línea 5**, que es exactamente donde va.

### 4.4 Se aplica una a la vez

Corregir un error cambia las posiciones del resto del archivo y suele revelar o
eliminar otros diagnósticos. El IDE aplica un arreglo, vuelve a analizar y
recalcula. Aplicarlos todos de golpe sobre un análisis viejo es menos confiable.

**Verificación:** la prueba `[3]` toma cuatro programas rotos, aplica
repetidamente la primera corrección propuesta, y comprueba que el resultado
**compila de verdad con `novac`**. No basta con que desaparezcan los
diagnósticos.

---

## 5. Requerimiento 3 — Errores marcados gráficamente

**Implementación:** `fase5_ide/ide_diag.c`, `fase5_ide/ide_catalogo.c`

### 5.1 El marcado

El editor es un `textarea` con dos capas detrás, alineadas al píxel:

| Capa | Contenido |
|---|---|
| pintada | el código con color, construida desde los tokens de `yylex()` |
| subrayado | el mismo texto en transparente, con la onda sobre los rangos del compilador |
| textarea | texto transparente y cursor visible; recibe la escritura |

Las tres comparten familia monoespaciada, tamaño, interlineado, relleno y
`tab-size`. Esa coincidencia es lo que hace que el color y el subrayado caigan
sobre el carácter que les corresponde.

**Rangos al final de línea.** Varios diagnósticos apuntan a una columna *una
posición después* del último carácter: el `;` que falta se reporta donde debió
haber estado, no sobre un carácter existente. Subrayar ese rango vacío no
dibuja nada —y es el caso más frecuente—, así que la marca se corre al último
carácter de la línea, que es donde hay que escribir.

### 5.2 La descripción

El compilador dice **qué** está mal. Para que el editor sirva falta la otra
mitad: **por qué** el lenguaje lo prohíbe y **cuál** es el cambio que lo
arregla. Eso es `ide_catalogo.c`: una entrada por código con título,
explicación y remedio.

Ejemplo de lo que se ve al pasar el puntero sobre un subrayado:

> **E306 · Condición que no es `veritas`** — fase semántico
> `la condicion de 'si' debe ser 'veritas', no 'integer'`
> Las condiciones de `si`, `dum` y `per` deben ser de tipo `veritas`. Nova no
> trata los enteros como valores de verdad.
> **Cómo se arregla:** escriba una comparación explícita, por ejemplo `x != 0`
> en vez de `x`.

El catálogo cubre los **54 códigos** (44 errores E1xx–E4xx y 10 advertencias
W0xx) que las fases pueden emitir. La prueba `[1]` lee las fuentes del
compilador, extrae todo código que aparece en una llamada a `diag_error` o
`diag_advertencia`, y **falla si alguno no está descrito**. Agregar un código
nuevo al compilador sin documentarlo rompe la compilación de pruebas.

### 5.3 Panel de tabla de símbolos

El panel muestra, para cada nombre: clase, ámbito, tipo, región (`DMEM`,
`IMEM`), **dirección exacta de memoria**, desplazamiento respecto de R14,
tamaño en bytes y línea de declaración. Los valores son idénticos a los de
`novac --sym`, porque salen del mismo cálculo.

### 5.4 Clase del archivo, no error

`E405` («no hay `principale`») lo emite la generación de código al armar un
ejecutable. El editor **no lo reporta como error**: no puede saber si lo que se
escribe es el programa o un módulo de biblioteca, que legítimamente no tiene
punto de entrada y se compila con `-c`. Marcarlo en rojo dejaría todo módulo
apareciendo roto. En su lugar el IDE informa la clase del archivo
(`ejecutable` / `modulo`) como dato en la barra superior.

---

## 6. Requerimiento 4 — Detección de clones

**Implementación:** `fase5_ide/ide_clones.c`

### 6.1 Método

El análisis es **por flujo de tokens**, que es lo estándar en la literatura de
detección de clones (CCFinder, CP-Miner) y lo que corresponde aquí: ya existe
el lexer del lenguaje, los tokens eliminan por construcción el ruido de
espacios, saltos de línea, sangría y comentarios, y el método sigue funcionando
sobre archivos que todavía no compilan.

La **unidad de comparación es la función**, que es lo que el programador copia y
pega. Aparte se comparan los archivos enteros, para el caso de «un archivo
duplicado donde lo único que cambia es el nombre del archivo».

De cada unidad se derivan dos secuencias:

| Secuencia | Construcción |
|---|---|
| cruda | clase de token + lexema exacto de identificadores y literales |
| normalizada | clase de token, con todo identificador y literal reemplazado por un marcador de su categoría |

### 6.2 Los tres tipos

**Tipo I — secuencias crudas iguales.** El código es el mismo; sólo cambian el
formato, los comentarios y el archivo donde vive.

**Tipo II — secuencias normalizadas iguales.** La estructura es idéntica y lo
único que cambia son los nombres de variables y los literales. Se comprueba
además que el renombrado sea **consistente**: que exista una biyección entre los
identificadores de una y los de la otra. Si `a` se vuelve `x` en un lugar y `y`
en otro, el renombrado no es sistemático y se reporta como tal. Es la condición
de *parameterized match* de Baker.

**Tipo III — similitud alta sobre la secuencia normalizada.** Es el caso de la
copia a la que se le agregaron o quitaron sentencias o variables.

### 6.3 Por qué el Tipo III necesita más que la LCS

La primera versión medía la similitud con la subsecuencia común más larga sobre
la secuencia normalizada:

```
similitud = 2 · |LCS(a, b)| / (|a| + |b|)
```

Resultó **demasiado permisiva**. En Nova casi toda sentencia se reduce a la
misma plantilla de clases de token, de modo que dos funciones que no tienen
nada que ver se parecen sólo por compartir el esqueleto del lenguaje. Medido
sobre el juego de pruebas, `promedio` y `maximo` —funciones distintas que
apenas comparten el recorrido de un arreglo— daban **0.859**, mientras que un
clon verdadero daba 0.901. El margen no servía para separar nada.

Se corrigió con dos cambios:

**(a) Codificación parametrizada.** Borrar los nombres por completo es correcto
para decidir el Tipo II, donde las secuencias deben ser idénticas; para la
similitud resulta demasiado grosero. Lo que sí distingue una copia de una
coincidencia estructural es el **patrón de reúso de los nombres**: cuándo una
variable se vuelve a usar y a qué distancia. Ese patrón sobrevive al renombrado
—llamarle `acumulado` en vez de `suma` no cambia dónde aparece— pero cambia por
completo entre dos funciones distintas. Cada identificador se codifica entonces
como la distancia hasta su aparición anterior dentro de la unidad, y 0 si es la
primera vez.

**(b) Racha contigua mínima.** Dos funciones distintas pueden acumular una LCS
alta a base de coincidencias de un token suelto, pero no comparten un tramo
largo de código seguido. Se exige además una subcadena común contigua de al
menos 10 tokens y un cuarto de la unidad más corta.

Resultado sobre el mismo juego de pruebas: **cero falsos positivos**, y los
clones verdaderos se siguen detectando.

### 6.4 Rendimiento

Comparar todos los pares es cuadrático en el número de unidades, y cada
comparación Tipo III es un DP cuadrático en los tokens. Para no colgar el
editor se aplica un **filtro admisible** antes del DP: la LCS nunca puede ser
mayor que la intersección de los multiconjuntos de tokens de las dos unidades,
así que ese valor es una **cota superior** de la similitud. Si la cota ya queda
por debajo del umbral, el par no puede ser clon y el cálculo caro se evita. Al
ser cota superior, el filtro no descarta ningún clon verdadero.

Medición sobre el repositorio completo: **36 archivos, 101 unidades, 28 ms.**

### 6.5 Hallazgos reales en este repositorio

Corriendo la detección sobre el proyecto del Proyecto I:

| Tipo | Unidades | Observación |
|---|---|---|
| I | `matriz.nv:imprimir` ↔ `multiplicacion.nv:imprimir` | función copiada literalmente entre dos pruebas |
| II | `cifrado.nv:cifrar_un_rondo` ↔ `descifrado.nv:descifrar_un_rondo` | mismo algoritmo con los nombres cambiados de forma consistente |
| II | `cifrado.nv` ↔ `descifrado.nv` (archivo completo) | el archivo entero es una copia renombrada |

---

## 7. Cómo usarlo

### 7.1 Requisitos

Los del Proyecto I (GCC, Flex, Bison, Make) más Python 3, que ya viene en
Ubuntu y WSL. **No hay dependencias nuevas**: ni bibliotecas de C, ni paquetes
de Python, ni JavaScript descargado de Internet. El IDE funciona sin conexión.

### 7.2 Arranque

```bash
make          # construye novac y novaide
make ide      # levanta la interfaz y abre el navegador
```

En WSL el navegador que abre es el de Windows. Si no abre solo, la dirección es
`http://127.0.0.1:8099/`.

### 7.3 Atajos

| Atajo | Acción |
|---|---|
| escribir | análisis automático tras una pausa breve |
| `Ctrl`+`Espacio` | sugerencias de código |
| `↑` `↓` `Enter` `Tab` | navegar y aceptar una sugerencia |
| `Ctrl`+`S` | guardar |
| puntero sobre un subrayado | descripción completa del error |

### 7.4 El núcleo sin la interfaz

Todo se puede demostrar desde la terminal, que a veces es más claro en una
defensa:

```bash
./novaide diagnosticar test/ide/correcto.nv
./novaide arreglar test/ide/llave_sin_cerrar.nv
./novaide clones test/ide/clones/*.nv --min-tokens 20
./novaide completar prueba.nv --linea 6 --columna 12
```

---

## 8. Pruebas

```bash
make prueba-ide    # 48 pruebas del núcleo del IDE
make prueba        # 233 pruebas del compilador (siguen pasando)
make todo          # cadena completa: compilador + IDE + CERBERO + RTL
```

Las pruebas del IDE corren contra el **binario**, no contra la interfaz: lo que
hay que garantizar es el comportamiento de la lógica en C.

| Bloque | Qué comprueba |
|---|---|
| `[2]` Diagnósticos | … incluye que se registren los puntos de salto con su dirección |
| `[1]` Catálogo | todo código que el compilador puede emitir está descrito, y toda entrada explica cómo se arregla |
| `[2]` Diagnósticos | cada programa de `test/errores` reporta el código que anuncia su nombre; toda posición es subrayable; no se aborta al superar el máximo de errores; toda variable trae dirección de memoria |
| `[3]` Correcciones | los arreglos, aplicados en secuencia, producen un programa que **compila con `novac`** |
| `[4]` Completado | el contexto decide qué se ofrece; el prefijo filtra; responde sobre archivos rotos |
| `[5]` Clones | los tres tipos se clasifican correctamente y los casos negativos **no** se reportan |

---

## 9. Archivos nuevos y modificados

### Nuevos

| Archivo | Líneas | Contenido |
|---|---|---|
| `fase5_ide/novaide.c` | ~170 | punto de entrada y protocolo |
| `fase5_ide/ide.h` | ~90 | interfaz del núcleo |
| `fase5_ide/ide_catalogo.c` | ~400 | descripción de los 54 diagnósticos |
| `fase5_ide/ide_diag.c` | ~250 | diagnósticos, símbolos, clase del archivo |
| `fase5_ide/ide_completar.c` | ~450 | sugerencias de código |
| `fase5_ide/ide_arreglar.c` | ~420 | corrección automática |
| `fase5_ide/ide_clones.c` | ~470 | clones Tipo I, II y III |
| `fase5_ide/ide_lex.c` / `.h` | ~290 | tokenización sobre `yylex()` |
| `fase5_ide/jsonw.c` / `.h` | ~150 | escritor de JSON sin dependencias |
| `fase5_ide/ide_util.c` | ~30 | lectura de archivos |
| `fase2_sintactico/enlace.c` / `.h` | ~620 | extraído de `main.c` |
| `ide/servidor.py` | ~330 | transporte HTTP |
| `ide/web/index.html` · `estilo.css` · `app.js` | ~1400 | interfaz |
| `test/ide/` | — | 43 pruebas y sus programas de prueba |

### Modificados

| Archivo | Cambio |
|---|---|
| `fase1_lexico/diag.h` / `diag.c` | modo captura; no aborta mientras está activo |
| `fase4_codigo/codegen.h` / `codegen.c` | `codegen_etiquetas()`: tabla de puntos de salto resueltos |
| `main.c` | enlazador extraído; `-I` usa `nova_agregar_ruta_modulos()`; `--sym` imprime los puntos de salto |
| `Makefile` | `novaide`, `make ide`, `make prueba-ide`, `prueba-ide` dentro de `make todo` |

---

## 10. Qué sigue

| Iteración | Contenido |
|---|---|
| 2 | Representación intermedia e identificación de bloques básicos |
| 3 | Loop unrolling, spilling register, eliminación de código muerto, reordenamiento |
| 4 | Calendarización estática y empaquetado de bundles VLIW |
| 5 | Integración con la jerarquía de caché y análisis de métricas |

La Iteración 2 ya tiene base: la generación de TAC existe desde el Proyecto I
(`fase4_codigo/tac.c`), y lo que falta es la construcción del grafo de flujo
sobre los bloques básicos, que es lo que después alimenta el análisis de
liveness para la eliminación de código muerto.
