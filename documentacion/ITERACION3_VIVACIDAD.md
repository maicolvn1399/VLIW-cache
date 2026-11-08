# Proyecto II — Iteración 3: vivacidad y eliminación de código muerto

**CE1108 Compiladores e Intérpretes · lenguaje Nova · arquitectura CERBERO**

La especificación pide para esta iteración cuatro optimizaciones sobre el código
intermedio. Este documento cubre las dos primeras, que son las que habilitan a
las otras dos:

> *Iteración 3: eliminación de código muerto, reordenamiento de instrucciones,
> loop unrolling y spilling register.*

| | Estado |
|---|---|
| **Análisis de vivacidad** (requisito previo de todo lo demás) | hecho |
| **Eliminación de código muerto** | hecho |
| Reordenamiento de instrucciones | pendiente |
| Loop unrolling | pendiente |
| Spilling register | pendiente |

El profesor lo planteó así: *«vamos a tener que hacer y manipular los recorridos
de los grafos para poder calcular y ver si una variable está viva, y si no está
viva poder eliminarla»*. Eso es exactamente lo que hay aquí.

---

## 1. Qué se agregó

| Archivo | Líneas | Qué hace |
|---|---|---|
| `fase6_optimizacion/vivacidad.h` | 125 | Contrato del análisis y tabla de efectos |
| `fase6_optimizacion/vivacidad.c` | 520 | Conjuntos USO/DEF, punto fijo, recorrido hacia atrás |
| `fase6_optimizacion/muerto.h` | 65 | Qué se elimina y qué se reporta |
| `fase6_optimizacion/muerto.c` | 250 | Marcado, barrido e iteración hasta punto fijo |

Y en lo que ya existía:

| Dónde | Cambio |
|---|---|
| `main.c` | Banderas `-O0`/`-O1`, `--vivacidad`, `--metricas`; la fase 6 entra entre el TAC y todo lo demás |
| `fase4_codigo/codegen.c/.h` | `codegen_estadisticas()`: bundles, slots ocupados y bundles vacíos |
| `fase5_ide/ide_bloques.c` | El grafo que recibe el IDE lleva los conjuntos y las instrucciones marcadas |
| `fase5_ide/ide_diag.c` | La fase 6 corre en cada pausa de tecleo, solo por sus advertencias: W010 se subraya en el editor |
| `fase5_ide/ide_catalogo.c` | Entrada de **W010**, asignación muerta |
| `ide/web/` | Los conjuntos en el panel del bloque, el código muerto tachado, casilla `-O1` |
| `test/ide/correr_pruebas.py` | Bloque `[7]`: 26 pruebas nuevas |
| `test/run_rtl_test.sh`, `tools/verificar.sh` | Aceptan `OPT=-O1`: la misma batería, compilando optimizado |

---

## 2. El análisis de vivacidad

### 2.1 La definición

Una variable está **viva** en un punto del programa si el valor que tiene ahí
**puede llegar a leerse** antes de que alguien lo sobrescriba. Si no está viva,
el valor es basura y la instrucción que lo calculó sobra.

Lo importante de la definición es el «puede»: basta que exista **un** camino en
el grafo que lo lea. Por eso el análisis no se puede hacer mirando el programa
línea por línea: hay que recorrer el grafo de flujo.

### 2.2 Por qué va hacia atrás

Lo que decide si un valor sirve no es lo que pasa **antes** de calcularlo sino
lo que pasa **después**. La información viaja entonces desde los usos hacia las
definiciones, en contra de las aristas del grafo.

Por cada bloque básico se calculan cuatro conjuntos:

| Conjunto | Qué contiene |
|---|---|
| `USO[B]` | nombres que B **lee antes de escribirlos** (su valor viene de fuera del bloque) |
| `DEF[B]` | nombres que B **escribe antes de leerlos** (los mata) |
| `VIVO_SAL[B]` | unión de `VIVO_ENT[S]` para cada sucesor S de B |
| `VIVO_ENT[B]` | `USO[B] ∪ (VIVO_SAL[B] − DEF[B])` |

`USO` y `DEF` se calculan recorriendo el bloque **hacia adelante** una sola vez.
El orden importa: en `a = a + 1` la lectura de `a` ocurre antes que su escritura,
así que `a` pertenece a `USO` y **no** a `DEF`.

### 2.3 El punto fijo

Las dos últimas ecuaciones son mutuamente recursivas: `VIVO_SAL` de un bloque
depende de `VIVO_ENT` de sus sucesores, y en un lazo un bloque es sucesor de sí
mismo por transitividad. No hay forma de resolverlas de una pasada.

Se resuelven **iterando**: todos los conjuntos arrancan vacíos y se recorre el
grafo una y otra vez hasta que una pasada completa no cambia nada.

**Por qué termina.** Los conjuntos solo crecen —cada pasada agrega nombres,
nunca los quita— y el universo de nombres de una función es finito. Una sucesión
creciente y acotada se estanca. Ese estancamiento es el punto fijo, y es el
**menor**: como se parte de vacío, no se da por vivo nada que no se haya
demostrado vivo.

**Por qué converge rápido.** Los bloques se recorren en **orden inverso**, de
`B_n` a `B_0`. Como la información viaja hacia atrás, cada pasada ya aprovecha
lo que se calculó de los sucesores. El orden no cambia el resultado, solo el
costo. En la práctica:

| Forma del código | Pasadas hasta el punto fijo |
|---|---|
| Función sin saltos | 1 |
| Condicional | 2 |
| Un lazo | 3 |
| Lazos anidados | 3 a 4 |

`novac --vivacidad` reporta el número real por función, así que no hay que
creerlo: se mira.

### 2.4 La condición de frontera

A la salida de un bloque que **retorna** o que termina el programa, el marco de
la función deja de existir: no queda vivo ningún local ni ningún temporal. Eso
es lo que arranca todo el análisis — sin esa condición, los conjuntos vacíos
iniciales serían también el punto fijo y nada estaría vivo nunca.

Lo único que sobrevive al retorno son los nombres que **escapan** y los
**globales**, porque su valor se puede observar desde fuera de la función.

### 2.5 Qué lee y qué escribe cada instrucción

Toda la semántica del repertorio está en **una sola función**, `viv_efecto()`
(`vivacidad.c:76`). La comparten el análisis, la eliminación y la vista del IDE,
de modo que los tres ven exactamente el mismo programa.

Tres casos no se leen del nombre del campo y conviene tenerlos a mano:

**`TAC_STORE` es `result[arg1] = arg2`.** El campo `result` **no es un destino**:
es el arreglo del que se lee la dirección base. La instrucción no define ningún
nombre, **lee tres**, y escribe memoria.

**`TAC_CALL` define `result`, pero su `arg1` es el nombre de la función**, no una
variable: de ahí no se lee ningún valor. Los argumentos ya viajaron por sus
`TAC_PARAM`, que sí los leen.

**`TAC_ADDR` es `result = &arg1`.** Marca a `arg1` como **escapado**: a partir de
ahí cualquiera que tenga el puntero puede leerlo o escribirlo, así que el
análisis nunca lo da por muerto.

---

## 3. Eliminación de código muerto

### 3.1 Qué se quita

**Bloques inalcanzables.** Si no hay camino desde la entrada de la función hasta
un bloque, ninguna ejecución pasa por ahí. Lo dice la marca de alcanzabilidad
del grafo, que ya estaba desde la Iteración 2. Se va el bloque entero, etiqueta
incluida: si alguien saltara a esa etiqueta, el bloque sería alcanzable.

**Definiciones muertas.** Una instrucción que calcula un valor en un nombre que
ya no está vivo justo después de ella no sirve para nada.

**Resultados de llamada sin usar.** La llamada se queda —puede imprimir,
escribir memoria o tocar la bóveda— pero si nadie lee lo que devuelve se borra
el destino, y la fase 4 se ahorra guardar el valor de retorno.

### 3.2 El truco de la cadena

Al marcar una instrucción como sobrante **no se avivan sus lecturas**, porque la
instrucción va a desaparecer y no va a leer nada. Eso hace que una cadena entera
de cálculos muertos caiga en **una sola pasada** en vez de necesitar una ronda
por eslabón:

```
varia muere    : integer = a * b;
varia cadena_a : integer = muere + 7;
varia cadena_b : integer = cadena_a * 2;
```

son ocho instrucciones de tres direcciones que se van de una vez. Hay una
prueba que lo comprueba (`rondas <= 3`), porque si el recorrido hacia atrás
estuviera mal el síntoma sería justamente necesitar una ronda por eslabón.

### 3.3 La ronda completa

```
    construir el grafo  →  calcular vivacidad  →  marcar  →  barrer
```

y se repite mientras algo cambie. **El grafo se reconstruye en cada vuelta**:
cuesta un poco más, pero garantiza que la vivacidad se calcula siempre sobre el
programa que quedó y no sobre el anterior. La alternativa —actualizar el grafo a
mano tras cada borrado— es justo donde se cuelan los errores.

**Marcar y barrer van separados a propósito.** Mientras se decide qué sobra, el
grafo apunta a instrucciones de la lista, así que no se puede desenlazar nada.
Primero se anotan las condenadas, después se recorre la lista una sola vez y se
sacan.

### 3.4 Lo que NO se elimina, y por qué

Esta es la parte que hay que poder defender: una eliminación de más cambia el
programa, y en un compilador eso es el peor error posible.

| No se toca | Por qué |
|---|---|
| **`TAC_DIV`, `TAC_MOD`** | `__nova_div32` termina el programa con el **código 136** si el divisor es cero, porque es lo que promete el lenguaje. Borrar una división muerta convertiría un programa que aborta en uno que no, y eso es observable. |
| **`TAC_CHECK`** | La verificación de rango aborta con el **código 134**. Mismo razonamiento. |
| **`TAC_STORE`** | Para borrar una escritura habría que probar que el arreglo entero está muerto y que nadie tiene su dirección: eso es análisis de alias, y está fuera de esta iteración. |
| **Nombres que escapan por `&`** | Quien tenga el puntero puede leerlos. |
| **Globales** | `constans` es de solo lectura, pero se marcan igual para no darlos nunca por muertos. |
| **Bloques vacíos con solo etiqueta** | Son destino de saltos. Quitarlos es *enhebrado de saltos*, otra optimización. |

Sobre `test/ide/viv_efectos.nv`, donde las tres asignaciones tienen el destino
muerto, se ve exactamente qué sobrevive:

```
functio arriesgar:
    t2 = #100
    t3 = t2 / d          ← la división se queda: puede abortar
    t4 = longitudo v, dim 0
    check d, t4          ← la verificación se queda: puede abortar
    t6 = #7
    param t6  (posicion 1)
    call ruidosa, 1      ← la llamada se queda, sin destino
    t8 = #0
    ret t8
fin arriesgar
```

El `t5 = v[d]` desapareció —leer memoria es puro, y `t5` estaba muerto— pero el
`check` que lo precedía se quedó. Es la precisión que da tener la tabla de
efectos separada del resto.

Una nota honesta: `t3 = t2 / d` se queda aunque nadie lea `t3`. Lo que hay que
conservar es el **aborto**, no el cociente; un compilador más fino emitiría solo
la comparación con cero. Está anotado como mejora, no como algo que esté mal.

---

## 4. La advertencia W010

Cuando el análisis encuentra una asignación muerta a una **variable del
programa**, el compilador lo dice:

```
matriz_1000.nv:3:11: advertencia[W010]: a 'fila' se le asigna un valor que
                     nunca se lee: la asignacion se elimina
3 |     varia fila : integer = 0;
  |           ^^^^
```

Y tenía razón. En ese programa:

```nova
varia fila : integer = 0;
varia columna : integer = 0;

per (fila = 0; fila < longitudo(matriz); fila += 1) {
    per (columna = 0; ...
```

las dos inicializaciones las pisa el `per` inmediatamente. No es un error, pero
es trabajo que el procesador iba a hacer para nada.

Solo se avisa de los nombres que el programador escribió. Las temporales que
caen con ellos son consecuencia del propio TAC —un `varia x = a*b` muerto
arrastra dos o tres— y listarlas llenaría la salida de nombres que no están en
el fuente. Tampoco se avisa de los bloques inalcanzables: eso ya lo reporta W003
en la fase 3.

`-Wno-W010` la silencia, como cualquier otra.

---

## 5. Métricas

El profesor pidió que las métricas tengan sentido y que se sepa cómo se hacen.
Hay **dos clases, y se miden en lugares distintos**:

| Qué | Dónde se mide | Con qué |
|---|---|---|
| Tiempo de **compilación**, tamaño del código | en el compilador | `novac --metricas` |
| Tiempo de **ejecución**: ciclos, bundles, ocupación | en el procesador | contadores del RTL + `ARQUITECTURA/tools/tabla_metricas.py` |

El compilador **no estima** tiempo de ejecución. Lo que mide son cosas que
puede contar exactamente: cuánto tardó, cuántas instrucciones de tres
direcciones quedaron, cuántos bundles salieron y cuántas ranuras llevan trabajo.

```
$ make metricas F=test/ejecucion/matriz_1000.nv
```

| | `-O0` | `-O1` |
|---|---|---|
| tiempo de compilación | 0.93 ms | **1.42 ms** (+53 %) |
| del cual, la fase 6 | — | 0.51 ms |
| instrucciones de tres direcciones | 130 | **126** |
| bundles emitidos | 785 | **775** |
| bytes de IMEM | 12 560 | **12 400** |
| ocupación media | 0.47 de 5 | 0.46 de 5 |
| bundles totalmente vacíos | 419 (53.4 %) | 415 (53.5 %) |

Eso es exactamente el intercambio que mencionó el profesor: **el compilador
tarda más para que el programa tarde menos**. Los 10 bundles menos son 10 ciclos
de emisión menos cada vez que se ejecuta.

### 5.1 El resultado honesto sobre todo el corpus

| | Total |
|---|---|
| Instrucciones de tres direcciones | 2151 → 2133 (**−0.8 %**) |
| Bundles emitidos | 21 045 → 20 988 (**−0.27 %**) |
| Bloques inalcanzables eliminados | 12 |
| Asignaciones muertas encontradas en el fuente | 2 |

**Es poco, y hay que decirlo así.** Los 23 programas del corpus y los 6 del
profesor son código escrito a mano y limpio: casi no tienen código muerto. En
`Test1` a `Test6` del profesor la eliminación no encuentra **nada**, y el
binario sale idéntico.

Eso no significa que la pasada no sirva. Significa tres cosas:

1. **Es el requisito previo de lo que falta.** El *spilling register* necesita
   los rangos de vida que salen de este análisis: sin saber qué está vivo no se
   sabe qué registro se puede reusar. El reordenamiento necesita saber qué
   valores siguen haciendo falta para no pisarlos.

2. **El código muerto lo va a generar el propio compilador.** El *loop
   unrolling* duplica cuerpos de lazo y deja cálculos de índice repetidos; la
   calendarización mueve instrucciones y deja copias sin usar. La eliminación es
   la pasada de limpieza que corre **después** de ellas, y ahí es donde va a
   tener material.

3. **Como diagnóstico ya encontró algo real.** Las dos asignaciones muertas de
   `matriz_1000.nv` estaban en nuestro propio código desde el Proyecto I.

El número que de verdad importa para la Iteración 4 está en esa misma tabla:
**ocupación media de 0.47 ranuras de 5, con el 53 % de los bundles completamente
vacíos**. El VLIW se está usando como un procesador escalar caro. Eso no lo
arregla la eliminación de código muerto; lo arregla la calendarización, y por
eso es lo que sigue.

---

## 6. Cómo verlo

### 6.1 Desde la terminal

```bash
./novac --vivacidad prueba.nv        # USO, DEF, VIVO_ENT, VIVO_SAL por bloque
./novac --ir -O1 prueba.nv           # el código intermedio ya optimizado
./novac --metricas -O1 prueba.nv -o p.nvx
make vivacidad F=prueba.nv
make metricas  F=prueba.nv           # las dos columnas, -O0 y -O1, de una vez
```

`--vivacidad` imprime, por bloque, los cuatro conjuntos y qué quitaría `-O1`:

```
functio factorial: 9 nombres, punto fijo en 3 pasadas

  B1 (L0)
      USO:      i, n
      DEF:      t2
      VIVO_ENT: resultado, i, n
      VIVO_SAL: resultado, i, n
```

Se lee así: al entrar a la cabeza del lazo hacen falta `resultado`, `i` y `n`;
el bloque lee `i` y `n` sin escribirlos antes, y define el temporal `t2` de la
comparación. Como el lazo vuelve a este bloque, los tres siguen vivos a la
salida.

### 6.2 Desde el IDE

En la pestaña **Flujo**, al hacer clic en un bloque, el panel derecho muestra
los cuatro conjuntos y el código del bloque con **lo que `-O1` quitaría
tachado**. La barra superior dice cuántos nombres se analizaron, en cuántas
pasadas convergió y cuántas instrucciones se irían.

El grafo que se dibuja es el del código **sin optimizar**, con lo muerto
marcado. Es a propósito: así se ve el código muerto en su sitio —se entiende por
qué sobra— en vez de un programa del que ya desapareció.

Y en la barra de **Compilar** hay una casilla `-O1` que vale para todos los
modos: se puede mirar el mismo archivo con y sin optimizar en el código
intermedio, en el ensamblador o en los bundles, y comparar.

---

## 7. Pruebas

```bash
make prueba        # 233 pruebas del compilador
make prueba-ide    # 95 pruebas del nucleo del IDE (eran 69)
```

El bloque `[7]` agrega **26 pruebas**. Las que importan no son las que
comprueban que algo se elimina, sino las que comprueban que algo **no** se
elimina:

| Qué comprueba |
|---|
| Los parámetros están vivos a la entrada de la función |
| A la salida de un retorno no queda vivo ningún local |
| Un nombre que solo se lee no entra en `DEF` |
| El análisis converge en un número razonable de pasadas |
| La cadena de cálculos muertos se marca entera |
| **El valor que se devuelve nunca se marca como muerto** |
| `-O1` reduce el código intermedio y conserva lo que se usa |
| `-O1` elimina el bloque inalcanzable |
| La cadena muerta cae sin una ronda por eslabón |
| **Una división con destino muerto no se elimina** (aborta con 136) |
| **La verificación de rango no se elimina** (aborta con 134) |
| **Una llamada con resultado sin usar se conserva**, pero su destino se descarta |
| **Un arreglo que escapa por `&` conserva sus escrituras** |
| `-O1` nunca aumenta el número de instrucciones (todo el corpus) |
| **Ningún temporal llega vivo a la entrada de una función** (todo el corpus) |
| Todo el corpus compila con `-O1` |
| El IDE anuncia exactamente lo mismo que `-O1` elimina |
| **El marco encoge al optimizar**: `--sym` mide el código optimizado |
| El desplazamiento relativo a `r14` no cambia al optimizar |
| Una asignación muerta se subraya mientras se escribe, marcando solo el nombre |

### 7.1 El invariante fuerte

> **En el bloque de entrada de cada función, solo pueden llegar vivos los
> parámetros y los nombres que vienen de fuera.**

Si un temporal apareciera en `VIVO_ENT` del bloque 0, significaría que el
programa **lee algo que nadie definió**: exactamente el síntoma de una
eliminación mal hecha. La prueba lo comprueba sobre los 21 programas del corpus,
y es barata porque el propio análisis de vivacidad la contesta.

### 7.2 Verificación de que optimizar no cambia el programa

Hay dos comprobaciones que corren contra el proyecto de arquitectura, y las dos
aceptan `OPT=-O1`:

```bash
OPT=-O1 sh tools/verificar.sh 12   # contraste con el ensamblador de CE4301
make prueba-rtl-optimizado         # la bateria completa sobre el RTL
```

La primera pasa nuestro ensamblador optimizado por el **ensamblador
independiente** del equipo de CE4301 y compara bit a bit con nuestro binario:

```
identicos: 20, distintos: 0, pendientes de enlazar: 2
```

El mismo resultado que sin optimizar. Eso prueba que el código que sale de la
fase 6 sigue siendo CERBERO válido y bien formado.

La segunda es la prueba de verdad: **la misma batería de programas, con los
mismos valores de retorno esperados, compilando con `-O1`**. Si una sola cambia
de resultado, la fase 6 está rota. Necesita `iverilog`, así que corre en la
máquina de trabajo y no en el contenedor.

### 7.3 Memoria

El barrido desenlaza instrucciones de una lista que el grafo todavía apunta, que
es donde más fácil se rompe algo. Todo el corpus corre bajo `valgrind` sin un
solo error:

```bash
valgrind -q ./novac -O1 test/ejemplos/convolucion.nv -o /dev/null
```

---

## 8. Lo que sigue

| Iteración | Qué necesita de lo que hay aquí |
|---|---|
| **3** — reordenamiento | Saber qué valores siguen vivos para no pisarlos al mover instrucciones |
| **3** — loop unrolling | Los lazos del grafo (Iteración 2); genera código muerto que esta pasada limpia |
| **3** — spilling register | Los rangos de vida salen directamente de `VIVO_ENT`/`VIVO_SAL` |
| **4** — calendarización | Atacar el 53 % de bundles vacíos y la ocupación de 0.47 |
| **5** — análisis de rendimiento | Comparar los contadores del procesador con y sin optimizar |

Las mejoras pendientes dentro de esta pasada, anotadas donde corresponde en el
código:

- **Eliminar escrituras a arreglos locales muertos**, que necesita análisis de
  alias.
- **Reemplazar una división muerta por su comprobación de cero**, en vez de
  conservar la división entera.
- **Propagación de copias** antes de la eliminación: el TAC genera
  `t0 = a + b; vive = t0`, y propagar la copia dejaría más definiciones muertas
  a la vista.
- **Enhebrado de saltos**, para los bloques que solo llevan etiqueta.
