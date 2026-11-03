# Guion de pruebas del IDE

Lista de comprobación para validar la Iteración 1, y guion de demostración
para la defensa. Cada prueba dice qué hacer y qué debe pasar.

Todo lo de aquí está verificado sobre el estado actual del repositorio.

---

## 0. Automáticas (antes que nada)

```bash
make                       # compila novac y novaide
make prueba-ide            # 52 pruebas del núcleo del IDE
make prueba                # 233 pruebas del compilador
sh tools/verificar.sh 12   # codificación idéntica al ensamblador de CE4301
```

| Comando | Debe decir |
|---|---|
| `make prueba-ide` | `pruebas del IDE: 69 correctas, 0 fallidas` |
| `make prueba` | `pruebas: 233 correctas, 0 fallidas` |
| `verificar.sh 12` | `identicos: 20, distintos: 0, pendientes de enlazar: 2` |

Si las tres pasan, el núcleo está bien y lo que sigue es comprobar la interfaz.

Para levantarla:

```bash
make ide     # abre http://127.0.0.1:8099/
```

---

## 1. Errores marcados gráficamente (requisito 3)

Arrancá del programa de ejemplo que trae el editor.

### 1.1 Error sintáctico

**Hacé:** borrá el `;` del final de la línea 9 (`resultado = resultado * i`).

**Debe pasar:**
- Subrayado rojo ondulado bajo el último carácter de la línea.
- Punto rojo junto al número de línea 9.
- Pastilla arriba a la derecha: `1 error`.
- Pestaña **Problemas** con el contador en 1.

**Pasá el puntero sobre el subrayado.** El globo debe mostrar las cuatro
cosas: código `E202`, título «Falta ';'», el mensaje del compilador, la
explicación de por qué, y en verde cómo se arregla.

### 1.2 Error léxico

**Hacé:** en la línea 5, escribí `varia resultado : integer = 5 $ 3;`

**Debe pasar:** `E101` en la columna del `$`, fase **léxico**. Es un error de
fase distinta al anterior: sirve para mostrar que el IDE distingue las fases.

### 1.3 Error semántico

**Hacé:** cambiá `redde resultado;` (línea 13) por `redde totalXX;`

**Debe pasar:** `E301` «no está declarado en este ámbito», fase **semántico**.
Nótese que es un error que solo se puede detectar después de construir la
tabla de símbolos — el lexer y el parser lo aceptan sin problema.

### 1.4 Error de tipos

**Hacé:** cambiá la condición del `dum` por `dum (i) {`

**Debe pasar:** `E306` «la condición debe ser 'veritas', no 'integer'», con el
remedio sugiriendo `i != 0`. Nova no trata los enteros como valores de verdad.

### 1.5 Advertencia (color distinto)

**Hacé:** agregá `varia sobrante : integer = 7;` después de la línea 6.

**Debe pasar:** subrayado **ámbar**, no rojo: `W001`, variable declarada y
nunca usada. La pastilla dice `1 advertencia` y el programa **sí compila**.

### 1.6 Varios errores a la vez

**Hacé:** borrá tres `;` distintos.

**Debe pasar:** los tres subrayados simultáneos, el contador en 3, y las tres
filas en Problemas. Clic en cualquier fila salta a esa línea.

---

## 2. Corrección automática (requisito 2)

### 2.1 Punto y coma

**Hacé:** borrá el `;` de la línea 9 → pestaña **Correcciones** → `Aplicar`.

**Debe pasar:** «Insertar ';'», confianza **alta**, y al aplicar lo inserta en
la posición exacta y vuelve a analizar. La pastilla vuelve a `sin errores`.

### 2.2 Llave sin cerrar (la prueba interesante)

**Hacé:** borrá el `}` de la línea 11, la que cierra el `dum`.

**Debe pasar:** propone insertar `}` **antes de `redde resultado`**, con la
sangría correcta — no al final del archivo.

**Por qué importa:** poner la llave al final también deja el programa
balanceado, pero `redde resultado` quedaría *dentro* del ciclo y el programa
compilaría haciendo otra cosa. El IDE usa la sangría para deducir dónde la
querías. Es el punto más fuerte de esta parte para la defensa.

### 2.3 Paréntesis

**Hacé:** cambiá la línea 17 por `scribe(factorial(6);`

**Debe pasar:** «Insertar ')'», confianza **alta**, en la columna 24. Esta
viene del parser, no del balanceo: `nova.y` sabía exactamente qué token
esperaba.

### 2.4 Varios a la vez

**Hacé:** borrá los `;` de las líneas 5, 6, 9 y 10.

**Debe pasar:** cuatro correcciones listadas. Aplicalas una por una: después de
cada una se vuelve a analizar. **No se aplican todas de golpe a propósito** —
corregir un error mueve las posiciones del resto.

### 2.5 Caso negativo

**Hacé:** dejá el archivo correcto.

**Debe pasar:** Correcciones en **0**, con el mensaje de que no hay nada que
proponer. Un corrector que siempre propone algo no sirve.

---

## 3. Sugerencias de código (requisito 1)

### 3.1 Filtrado por prefijo

**Hacé:** al final de la línea 10, escribí `res`.

**Debe pasar:** popup con `resultado`, y a la derecha `resultado : integer` y
**`DMEM @0xFFE0 = r14+4`** — dónde vive esa variable en memoria.

### 3.2 Contexto de tipo

**Hacé:** en una línea vacía dentro de una función, escribí `varia x :`

**Debe pasar:** al escribir los dos puntos se abren **exactamente los cuatro
tipos** del lenguaje: `integer`, `nihil`, `textus`, `veritas`. Nada más,
porque ahí nada más puede ir.

Lo mismo con `->` en la firma de una función.

### 3.3 Contexto global

**Hacé:** poné el cursor en la línea 1, fuera de toda función, y pedí
`Ctrl`+`Espacio`.

**Debe pasar:** solo `functio`, `constans`, `privatum`, `importa` y la
plantilla `principale`. **No debe aparecer `varia`**: fuera de las funciones
Nova no admite variables (error E320), así que ofrecerla sería sugerir un
error.

### 3.4 Plantillas

**Hacé:** en una línea vacía escribí `dum` y aceptá con `Enter`.

**Debe pasar:** inserta el ciclo completo con sus llaves, y la palabra
`condicion` queda **seleccionada**. Escribí `i < n`: debe reemplazarla, no
ponerse al lado.

Probá también `per` (inserta el ciclo contado completo) y `si-aliter`.

### 3.5 Intrínsecas

**Hacé:** escribí `scr` en una línea nueva.

**Debe pasar:** `scribe` marcada como **intrínseca**, con su firma
`scribe(valor, ...) -> nihil`.

### 3.6 Sobre código roto (el caso real)

**Hacé:** al final de la línea 10, escribí ` res` dejando el archivo con error
de sintaxis.

**Debe pasar:** el popup **sigue dando el tipo y la dirección de memoria**, y
al mismo tiempo el editor marca el error de sintaxis. Las dos cosas conviven.

**Por qué importa:** es el caso normal al completar — el identificador a medio
escribir casi siempre rompe la sintaxis. Si el análisis se rindiera ahí, nunca
se vería un tipo. El IDE reintenta analizando el mismo texto sin el prefijo.

---

## 3bis. Grafo de flujo (Iteración 2)

### Grafo de un ciclo con condicionales

**Hacé:** abrí `test/ide/cfg_ciclo.nv` → pestaña **Flujo** → `Construir grafo`.

**Debe pasar:** 9 bloques y 11 aristas en `clasificar`. En el dibujo:

- `B1 (L0)` es la cabeza del lazo, con dos salidas.
- Una **línea ámbar discontinua** sube desde el último bloque del cuerpo hasta
  `B1`: es la arista de regreso que cierra el ciclo.
- Los bloques del cuerpo tienen el fondo más oscuro (están en lazo); el de
  salida, no.

Clic en cualquier bloque muestra su código de tres direcciones, y cada
instrucción enlaza con la línea del fuente que la originó.

Usá el botón **Ampliar panel** para que el grafo se vea completo.

### Código muerto

**Hacé:** abrí `test/ide/cfg_muerto.nv` y construí el grafo.

**Debe pasar:** un bloque con **borde rojo punteado**, sin predecesores. Es el
`scribe` que viene después del `redde`: ninguna ejecución pasa por ahí.

### Contraste con la terminal

```bash
./novac --bloques test/ide/cfg_ciclo.nv
```

Debe reportar el mismo número de bloques y aristas que el IDE. Hay una prueba
automática que lo verifica, pero mostrarlo en vivo convence más.

### Caso negativo

**Hacé:** borrá un `;` y construí el grafo.

**Debe pasar:** no se dibuja nada y se explica por qué — el grafo se construye
sobre el código intermedio, que solo se genera si el programa analiza limpio.

---

## 4. Detección de clones (requisito 4)

### 4.1 Los tres tipos

**Hacé:** pestaña **Clones** → marcá «incluir todos los archivos del
proyecto» → `Buscar clones`.

**Debe pasar:** las tarjetas con el conteo por tipo, y entre los resultados
estos dos reales del repositorio:

| Tipo | Dónde |
|---|---|
| **I** | `matriz.nv:imprimir` ↔ `multiplicacion.nv:imprimir` — copiada literal |
| **II** | `cifrado.nv:cifrar_un_rondo` ↔ `descifrado.nv:descifrar_un_rondo` — renombrado consistente |

En el Tipo II fijate en las etiquetas: `renombrado consistente` y el número de
nombres cambiados. Eso es la biyección entre identificadores.

### 4.2 El umbral solo mueve el Tipo III

**Hacé:** cambiá «Umbral Tipo III» de `0.80` a `0.85` y volvé a buscar. Después
probá `0.90`.

**Debe pasar:** Tipo I y Tipo II **no cambian** (son comparaciones exactas, no
dependen de umbral), y Tipo III baja. Medido sobre `test/ejemplos` y
`test/ejecucion`:

| Umbral | Tipo I | Tipo II | Tipo III |
|---|---|---|---|
| 0.80 | 1 | 3 | 5 |
| 0.85 | 1 | 3 | 3 |
| 0.90 | 1 | 3 | 1 |

**Para la defensa usá 0.85.** El 0.80 es permisivo para un corpus donde muchos
programas recorren arreglos de forma parecida.

### 4.3 Filtro por tamaño

**Hacé:** poné «Tokens mínimos» en `5000` y buscá.

**Debe pasar:** cero clones. Confirma que el filtro de tamaño funciona: dos
funciones de tres líneas coinciden casi siempre sin que eso signifique nada.

### 4.4 Navegación

**Hacé:** clic en cualquiera de los dos lados de un clon.

**Debe pasar:** abre ese archivo y salta a la línea donde empieza la función.

---

## 5. Tabla de símbolos y puntos de salto

**Hacé:** con el archivo compilando, abrí la pestaña **Tabla de símbolos**.

**Debe pasar, arriba:** cada variable y parámetro con clase, ámbito, tipo,
región, **dirección exacta** (`DMEM @0xFFE4`), desplazamiento respecto de R14,
bytes y línea de declaración.

**Debe pasar, abajo:** la sección **Puntos de salto y etiquetas resueltas**,
con `L0` (la cabeza del ciclo `dum`), `__c0_si` y `__c0_fin` (las dos ramas del
condicional), cada una con su dirección y su número de bundle.

### Contraste con la terminal

**Tiene que ser el mismo archivo en los dos lados.** El ejemplo que trae el
editor al arrancar *no* es `prueba.nv`: su `principale` no declara locales y el
de `prueba.nv` sí (`varia i : integer = 1907`). Esa variable agranda el marco
de `principale` en 4 bytes, y como la direccion que se muestra para una local
es la de su **primera activacion** -- calculada propagando por el grafo de
llamadas desde `principale`-- el marco de `factorial` arranca 4 bytes mas
arriba. Las dos tablas son correctas; corresponden a programas distintos.

Para contrastar de verdad, abri `prueba.nv` desde el panel de archivos y
recien entonces corre:

```bash
./novac --sym prueba.nv
```

Ahi sí, las direcciones que imprime la terminal y las que muestra el IDE deben
ser **las mismas**. No son dos cálculos: el IDE enlaza las mismas unidades que el
compilador. Hay una prueba automática que lo verifica, pero mostrarlo en vivo
convence más.

---

## 6. El botón Ejecutar: las seis fases

**Hacé:** con el archivo correcto, recorré el desplegable **Compilar** de
arriba a abajo, ejecutando cada uno.

| Opción | Qué muestra |
|---|---|
| tokens (fase 1) | tabla de los 68 tokens con lexema, tipo, línea y columna |
| AST (fase 2) | el árbol sintáctico |
| tabla de símbolos (fase 3) | símbolos con direcciones |
| código de tres direcciones | el TAC |
| ensamblador CERBERO | el `.asm` con bundles y slots |
| bundles y slots | cada bundle con su dirección y bytes |
| binario .nvx | el ejecutable, con su tamaño en bytes |

Todos reportan el **tiempo de compilación** en milisegundos, que es una de las
métricas que el Proyecto II pide registrar.

### Las fases son independientes de verdad

**Hacé:** borrá un `;` y ejecutá **tokens (fase 1)**.

**Debe pasar:** la fase 1 **termina bien** y dice «análisis léxico completado
sin errores», mientras todas las demás fallan.

**Por qué:** un `;` faltante es un error sintáctico, no léxico. El lexer solo
parte el texto en tokens y `resultado = resultado * i` son cinco tokens
perfectamente válidos. El error aparece en la fase 2.

**Ahora el contrario:** poné un `$` en una expresión y ejecutá tokens. Ahora
**sí falla desde la fase 1**, porque `E101` es un error léxico.

Esta pareja de pruebas demuestra que las fases están realmente separadas y no
es un compilador monolítico.

---

## 7. Manejo de archivos

| Hacé | Debe pasar |
|---|---|
| Clic en un archivo del panel izquierdo | lo abre y lo analiza |
| Escribir el filtro `cifr` | la lista se reduce |
| Editar un archivo | aparece el punto ámbar de «sin guardar» |
| `Ctrl`+`S` | guarda y el punto desaparece |
| Abrir `test/modulos/matriz.nv` | la pastilla dice **modulo**, no error — no tiene `principale` y es correcto que no lo tenga |
| Abrir `prueba.nv` | la pastilla dice **ejecutable** |

---

## 8. El núcleo sin la interfaz

Para la defensa conviene tener esto a mano: demuestra que la lógica está en C
y que la interfaz es solo una capa de dibujo.

```bash
./novaide diagnosticar prueba.nv
./novaide arreglar test/ide/llave_sin_cerrar.nv
./novaide completar prueba.nv --linea 9 --columna 12
./novaide clones test/ide/clones/*.nv --min-tokens 20
./novaide catalogo
./novaide tokens prueba.nv
```

Todos contestan JSON. `./novaide catalogo` imprime los 54 diagnósticos del
lenguaje con su explicación y su remedio.

---

## Guion corto para la defensa (unos 6 minutos)

1. `make prueba-ide` y `make prueba` — 52 y 233 en verde.
2. Abrir el IDE, borrar un `;`: subrayado, hover con la explicación completa.
3. Correcciones → Aplicar.
4. Borrar la `}` del `dum`: mostrar que la propone en el lugar correcto y
   explicar por qué el final del archivo sería incorrecto.
5. `varia x :` → los cuatro tipos. `dum` → la plantilla.
6. Tabla de símbolos: direcciones de memoria y puntos de salto.
7. Lo mismo en terminal con `./novac --sym` — los números coinciden.
8. Clones con umbral 0.85: mostrar el Tipo I y el Tipo II reales del
   repositorio.
9. Pestaña **Flujo**: el grafo del ciclo, con la arista de regreso en ámbar.
10. Cerrar con el desplegable Compilar recorriendo las seis fases.
