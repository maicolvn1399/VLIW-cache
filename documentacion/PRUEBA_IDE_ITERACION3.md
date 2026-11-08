# Caso de prueba del IDE — Iteración 3

**Archivo:** `test/ide/demo_iteracion3.nv`

Cada función del archivo existe para enseñar una cosa distinta. La prueba son
**nueve pasos**, y al lado de cada uno está lo que tiene que verse. Si algo no
coincide, eso es lo que hay que reportar.

```bash
make            # reconstruir, porque cambio ide_diag.c
make ide        # abre http://127.0.0.1:8099/
```

En el panel izquierdo, **Archivos del proyecto**, escriba `demo` en el filtro y
abra `test/ide/demo_iteracion3.nv`.

---

## Paso 1 — El subrayado mientras se escribe

Apenas abra el archivo, sin tocar nada, el panel de **Problemas** tiene que
mostrar **12 advertencias**, de las cuales **seis son W010**, asignaciones
muertas:

| Línea | Variable |
|---|---|
| 27 | `sobra_1` |
| 28 | `sobra_2` |
| 29 | `sobra_3` |
| 42 | `division` |
| 43 | `indexado` |
| 44 | `llamada` |

El subrayado va **solo bajo el nombre de la variable**, no bajo toda la línea.

> **Esto es nuevo de esta iteración.** Hasta ahora el editor solo podía marcar
> errores de léxico, sintaxis y tipos. W010 es la primera marca que sale de un
> **análisis de flujo de datos sobre el grafo**: para saber que `sobra_1` está
> muerta hay que haber generado el código intermedio, construido el grafo de
> bloques y resuelto el punto fijo de la vivacidad. Todo eso corre en cada
> pausa de tecleo y cuesta menos de 5 ms en el programa más grande del corpus.

**Pase el cursor por encima** de `sobra_1`. El globo tiene que decir:

> **W010 · Asignación muerta** — El análisis de vivacidad encontró que el valor
> que se le asigna a la variable no se vuelve a leer por ningún camino del
> grafo de flujo, así que el cálculo sobra. Con `-O1` la asignación se elimina
> del código generado.

### La pregunta que va a venir: «¿por qué dos advertencias en la misma línea?»

En varias líneas aparecen **W001 y W010 juntas**, y parece que dicen lo mismo.
No lo dicen: son **dos preguntas distintas, de dos fases distintas**.

| | W001 | W010 |
|---|---|---|
| Pregunta | ¿alguien **menciona** este nombre? | ¿el valor que se guarda aquí **llega a leerse**? |
| Fase | 3, análisis semántico | 6, análisis de flujo de datos |
| Qué mira | el árbol sintáctico | el grafo de flujo y el punto fijo de la vivacidad |

Que son distintas no hay que argumentarlo: **se ve en este mismo archivo**,
donde las tres combinaciones aparecen.

| Variable | W001 | W010 | Por qué |
|---|---|---|---|
| `sobra_1` | — | **sí** | **Sí se menciona**: la línea siguiente la lee para calcular `sobra_2`. Por eso no hay W001. Pero su valor igual está muerto, porque la cadena entera lo está, y eso solo lo ve el análisis de flujo. |
| `division` | sí | sí | Ni se menciona ni se lee: las dos tienen razón. |
| `inalcanzable` | **sí** | — | Está en un bloque inalcanzable. No hay W010 porque no hace falta: el bloque entero se elimina, y W003 ya avisó de eso. |

> **`sobra_1` es el ejemplo que conviene tener a mano.** Es exactamente el caso
> que una revisión «a ojo» del código no encuentra: la variable *se usa*, así
> que parece viva. Hace falta seguir la cadena hasta el final y descubrir que
> nadie lee el último eslabón. Eso es lo que hace el recorrido hacia atrás
> sobre el grafo, y es la diferencia entre una comprobación sintáctica y un
> análisis de flujo de datos.

---

## Paso 2 — Los conjuntos del análisis

Abra la pestaña **Flujo** y pulse **Construir grafo**. En el selector de función
elija `acumular`.

En la barra de datos tiene que aparecer:

```
4 bloques    4 aristas    vivacidad: 9 nombres, punto fijo en 3 pasadas
-O1 quitaría 15 instrucciones    total: 8 bloques en 4 funciones
```

Haga clic en **B1 (L0)**, la cabeza del lazo. El panel derecho muestra:

| | |
|---|---|
| `USO` | `i, tope` |
| `DEF` | `t2` |
| `VIVO_ENT` | `suma, i, tope` |
| `VIVO_SAL` | `suma, i, tope` |

**Cómo leerlo en voz alta:** el bloque lee `i` y `tope` sin haberlos escrito
antes, por eso están en `USO`; define el temporal `t2` de la comparación, por
eso está en `DEF`. Y como el lazo vuelve a este bloque, los tres valores siguen
haciendo falta tanto al entrar como al salir: `VIVO_ENT` y `VIVO_SAL` son
iguales. **Eso es el lazo visto desde el análisis.**

Ahora **B3 (L1)**, el bloque del retorno:

| | |
|---|---|
| `VIVO_ENT` | `suma` |
| `VIVO_SAL` | `∅` |

Al retornar, el marco de la función desaparece: no sobrevive ningún local ni
ningún temporal. **Esa es la condición de frontera que arranca todo el
análisis** — sin ella, los conjuntos vacíos iniciales serían también el punto
fijo y nada estaría vivo nunca.

Y **B0**: `VIVO_ENT` es `tope`, el parámetro. Llega vivo porque su valor viene
de fuera de la función.

---

## Paso 3 — La cadena muerta, tachada en su sitio

Cambie el selector a `con_sobras` y haga clic en **B0**. En el código del bloque
tienen que verse **nueve líneas seguidas tachadas**, con `util = t6` y
`ret util` intactas justo al lado:

```
    t6 = a + b
    util = t6
    t̶7̶ ̶=̶ ̶a̶ ̶*̶ ̶b̶
    s̶o̶b̶r̶a̶_̶1̶ ̶=̶ ̶t̶7̶
    t̶8̶ ̶=̶ ̶#̶7̶
    t̶9̶ ̶=̶ ̶s̶o̶b̶r̶a̶_̶1̶ ̶+̶ ̶t̶8̶
    s̶o̶b̶r̶a̶_̶2̶ ̶=̶ ̶t̶9̶
    t̶1̶0̶ ̶=̶ ̶#̶2̶
    t̶1̶1̶ ̶=̶ ̶s̶o̶b̶r̶a̶_̶2̶ ̶*̶ ̶t̶1̶0̶
    s̶o̶b̶r̶a̶_̶3̶ ̶=̶ ̶t̶1̶1̶
    ret util
```

> **El grafo que se dibuja es el del código SIN optimizar, con lo muerto
> marcado.** Es a propósito: así se ve el código muerto en su sitio —se entiende
> por qué sobra— en vez de un programa del que ya desapareció.

Haga clic en **B1**. Tiene el borde rojo punteado (inalcanzable) y sus tres
instrucciones tachadas: es lo que está después del `redde`.

---

## Paso 4 — Lo que NO se elimina

Este es el paso importante, el que hay que poder defender.

Cambie a `intocables` y haga clic en **B0**. Mire con cuidado estas líneas:

```
    t13 = #1000
    t14 = t13 / d            ← NO tachada
    d̶i̶v̶i̶s̶i̶o̶n̶ ̶=̶ ̶t̶1̶4̶

    t15 = longitudo v, dim 0
    check d, t15             ← NO tachada
    t̶1̶6̶ ̶=̶ ̶v̶[̶d̶]̶

    t19 = call con_sobras, 2  ← en ÁMBAR, subrayado punteado
    l̶l̶a̶m̶a̶d̶a̶ ̶=̶ ̶t̶1̶9̶
```

Tres cosas distintas, y hay que saber decir por qué cada una:

| Línea | Qué pasa | Por qué |
|---|---|---|
| `t14 = t13 / d` | **se queda** | `__nova_div32` termina el programa con el **código 136** si el divisor es cero. Borrarla convertiría un programa que aborta en uno que no, y eso es observable. |
| `check d, t15` | **se queda** | La verificación de rango aborta con el **código 134**. Mismo razonamiento. |
| `t16 = v[d]` | **se va** | Leer memoria es puro: si nadie lee `t16`, la lectura sobra. El `check` que la protegía se quedó. |
| `call con_sobras` | **ámbar** | La llamada se queda —puede imprimir, escribir memoria o tocar la bóveda— pero nadie lee lo que devuelve, así que se descarta **solo el destino**. |

> Esa precisión —quitar el `v[d]` y conservar el `check` que estaba una línea
> antes— sale de tener la tabla de efectos de cada operación en **una sola
> función**, `viv_efecto()`, compartida por el análisis, la eliminación y esta
> vista.

---

## Paso 5 — Una cosa que parece rara y no lo es

Cambie a `principale` y mire **B0**: `VIVO_ENT` contiene `v`, el arreglo.

¿Cómo puede estar vivo *al entrar* un arreglo que se declara dentro de la
función? Porque más abajo aparece `t30 = &v`: se toma su dirección para pasarlo
a `intocables`. Un nombre cuya dirección se toma **escapa**, y el análisis lo
trata como intocable — nunca se da por muerto, en ningún punto.

Es una respuesta **conservadora**: de más, no de menos. Una respuesta de más
cuesta una instrucción que no se elimina; una de menos cambia el programa.

Nótese también que las escrituras `v[t21] = t23` y `v[t24] = t26` **no están
tachadas**: las escrituras a memoria no se tocan en esta iteración.

---

## Paso 6 — El código intermedio, con y sin optimizar

En la barra de arriba, **Compilar → código de tres direcciones**, con la casilla
`-O1` **apagada**, y pulse **Ejecutar**. Anote el final de `con_sobras`.

Ahora **encienda la casilla `-O1`** y vuelva a pulsar **Ejecutar**. La cabecera
del panel de Salida tiene que decir ahora:

```
$ novac -O1 [ir] demo_iteracion3.nv
```

Y `con_sobras` queda en tres líneas:

```
functio con_sobras:
    t6 = a + b
    util = t6
    ret util
fin con_sobras
```

Las nueve instrucciones de la cadena y las tres del bloque inalcanzable
desaparecieron. **Y se fueron en una sola pasada**, no una ronda por eslabón:
al marcar una instrucción como sobrante no se avivan sus lecturas, porque la
instrucción va a desaparecer y no va a leer nada.

---

## Paso 7 — Las métricas

**Compilar → métricas de compilación**, primero sin `-O1` y después con `-O1`.
Los dos reportes, lado a lado:

| | `-O0` | `-O1` |
|---|---|---|
| tiempo total de compilación | ~0.69 ms | **~0.80 ms** |
| del cual, la fase 6 | — | 0.17 ms |
| instrucciones de tres direcciones | 80 | **65** (−18.8 %) |
| en bloques inalcanzables | — | 3 (en 1 bloque) |
| definiciones muertas | — | 12 |
| resultados de llamada sueltos | — | 1 |
| rondas hasta el punto fijo | — | 2 |
| bloques inalcanzables que quedan | 1 | **0** |
| bundles emitidos | 585 | **516** (−69) |
| bytes de IMEM | 9 360 | **8 256** |
| ocupación media | 0.41 de 5 | 0.40 de 5 |
| bundles totalmente vacíos | 345 (59.0 %) | 312 (60.5 %) |

**Lo que hay que decir sobre esta tabla:**

1. **El compilador tarda más para que el programa tarde menos.** +16 % de tiempo
   de compilación, −69 bundles. Cada bundle es un ciclo de emisión, así que son
   69 ciclos menos cada vez que el programa corre. Es exactamente el intercambio
   que mencionó el profesor.

2. **Los tiempos son medidos, no estimados.** `clock()` alrededor de la fase 6 y
   alrededor de toda la compilación.

3. **El compilador no estima tiempo de ejecución.** Los ciclos los dan los
   contadores del procesador al correr el binario sobre el RTL. Lo que el
   compilador cuenta son cosas que puede contar exactamente: instrucciones,
   bloques, bundles y ranuras ocupadas.

4. **La ocupación de 0.40 de 5 ranuras, con el 60 % de bundles vacíos, es el
   problema que sigue.** Eso no lo arregla la eliminación de código muerto; lo
   arregla la calendarización, y por eso es la Iteración 4.

---

## Paso 8 — Los bundles y la tabla de símbolos

**Compilar → bundles y slots**, sin `-O1` y con `-O1`. El listado baja de 585 a
516 líneas. Las direcciones del final se corren hacia arriba exactamente 69
bundles — `69 × 16 = 1104` bytes menos de IMEM.

Ahora **Compilar → tabla de símbolos**, con y sin `-O1`, y compare la función
`con_sobras`. Hay **tres cosas distintas**, y conviene no confundirlas:

| | `-O0` | `-O1` | ¿Por qué? |
|---|---|---|---|
| `util = r14+16` | `r14+16` | `r14+16` | **No cambia.** El desplazamiento dentro del marco lo calcula la fase 3, y la optimización no toca declaraciones. |
| marco de `con_sobras` | 36 B | **32 B** | **Cambia.** Al desaparecer instrucciones, los temporales viven menos y hacen falta menos ranuras de respaldo en el marco. |
| `util` en DMEM | `0xFF98` | **`0xFF9C`** | **Cambia 4 bytes**, que es justo lo que se achicó el marco: la dirección de primera activación se propaga desde `principale` hacia abajo, y si un marco encoge, todo lo que va debajo sube. |
| `intocables` en IMEM | `0x08B0` | **`0x05E0`** | **Cambia.** El código es más corto, así que las funciones siguientes quedan antes. |

> **Que esto cambie es correcto, y que coincida es lo que costó trabajo.** La
> tabla de símbolos se calcula con un segundo recorrido de la fase 4 sobre una
> copia del código intermedio. Si esa copia no se optimizara, la tabla
> describiría un programa **que no es el que está en el binario**: diría que
> `util` vive en `0xFF98` cuando el procesador la va a buscar a `0xFF9C`.
> Por eso la copia se optimiza también cuando se compila con `-O1`.

Es la clase de detalle que vale la pena mencionar sin que lo pregunten, porque
es exactamente el punto por el que nos penalizaron en el Proyecto I: que la
tabla de símbolos diga la dirección de memoria **de verdad**.

### Dos confirmaciones que regala la misma pantalla

Baje hasta **Puntos de salto y etiquetas resueltas**, debajo de la tabla. Ahí
hay dos comprobaciones que no cuestan nada y que son **independientes** de todo
lo anterior.

**1. La división sobrevivió, y se ve sin mirar el código intermedio.**

En las dos columnas siguen apareciendo `__nova_div32` y las ocho etiquetas
`__dv_*`. Esa rutina **solo se emite si el programa tiene alguna división**: la
fase 4 recorre el código de tres direcciones y enciende `usa_div` al encontrar
un `TAC_DIV` o un `TAC_MOD`. Un programa sin divisiones no la lleva.

> Si la eliminación hubiera borrado la división muerta de `intocables`, esas
> nueve etiquetas **desaparecerían de la tabla**. Que sigan ahí con `-O1` es una
> confirmación de que la división se conservó, obtenida por un camino
> completamente distinto al de leer el `--ir`.

**2. Los 69 bundles ahorrados cuadran por dos caminos.**

Mire la última etiqueta, `__scribe_int`:

| | `-O0` | `-O1` | diferencia |
|---|---|---|---|
| `__scribe_int`, bundle | 469 | 400 | **69** |
| bundles emitidos (`--metricas`) | 585 | 516 | **69** |

El primer número sale de la **relajación de saltos**, que ubica cada etiqueta
iterando hasta converger. El segundo sale del **emisor**, que cuenta bundles.
Son dos mecanismos distintos y dan el mismo ahorro. Si no coincidieran, uno de
los dos estaría describiendo un programa que no es el que se generó.

Las dos están fijadas con pruebas de regresión en el bloque `[7]`.

---

## Paso 9 — Que el programa sigue haciendo lo mismo

Esto ya no es en el IDE, pero es la pregunta que va a venir después de todo lo
anterior: *¿y cómo saben que no rompieron nada?*

```bash
OPT=-O1 sh tools/verificar.sh 12   # 20 idénticos bit a bit, 0 distintos
make prueba-rtl-optimizado         # los 12 programas, mismo valor de retorno
```

La primera pasa nuestro ensamblador optimizado por el **ensamblador
independiente del equipo de CE4301** y compara bit a bit con nuestro binario: el
código que sale de la fase 6 sigue siendo CERBERO válido y bien formado.

La segunda es la de verdad: **la misma batería de programas, con los mismos
valores de retorno esperados, compilando con `-O1`**, corriendo sobre el RTL del
procesador. Ya corrió: los 12 dieron `RESULTADO: OK`.

---

## Resumen de una línea por si hay que acortar

| Paso | Qué demuestra |
|---|---|
| 1 | El análisis de flujo de datos llega al editor mientras se escribe |
| 2 | Los cuatro conjuntos y el punto fijo, sobre un lazo real |
| 3 | Una cadena muerta entera, tachada en su sitio |
| **4** | **Lo que NO se elimina, y por qué: división, rango, llamada** |
| 5 | Lo que escapa por `&` es intocable: conservador de más, no de menos |
| 6 | El código intermedio antes y después |
| 7 | Compilar cuesta más, el programa cuesta menos |
| 8 | La tabla de símbolos describe el programa optimizado, no otro |
| 9 | El RTL devuelve lo mismo con `-O1` |

Si solo hay tiempo para dos, son el **4** y el **7**.
