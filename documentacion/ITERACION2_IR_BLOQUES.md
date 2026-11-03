# Proyecto II — Iteración 2: representación intermedia y bloques básicos

**CE1108 Compiladores e Intérpretes · lenguaje Nova · arquitectura CERBERO**

La especificación define esta iteración así:

> *Iteración 2: Se debe generar la representación intermedia e identificación de
> bloques básicos.*

---

## 1. Qué había y qué se agregó

La representación intermedia ya existía desde el Proyecto I: `fase4_codigo/tac.c`
genera código de tres direcciones y la bandera `--ir` lo muestra. Lo que faltaba
era la **identificación de bloques básicos** y, con ella, el **grafo de flujo de
control** que las iteraciones siguientes necesitan.

| | |
|---|---|
| Ya estaba | Generación de TAC, bandera `--ir` |
| Nuevo | `fase6_optimizacion/bloques.c` — bloques básicos y CFG |
| Nuevo | Bandera `--bloques` en `novac` |
| Nuevo | Trabajo `bloques` en `novaide` y vista **Flujo** en el IDE |
| Refactor | `tac_print_inst()` — un solo formateador de instrucción para todas las vistas |

---

## 2. La representación intermedia

El TAC opera sobre una máquina abstracta de registros virtuales ilimitados, y es
**independiente de CERBERO**: `codegen.c` es quien lo baja a bundles. Esa
separación es la que permite que las optimizaciones de la Iteración 3 trabajen
sobre el IR sin saber nada del procesador.

Cada instrucción tiene a lo sumo un destino y dos operandos. Para `prueba.nv`:

```
functio factorial:
    t0 = #1
    resultado = t0
    t1 = #1
    i = t1
L0:
    t2 = i <= n
    ifFalse t2 goto L1
    t3 = resultado * i
    resultado = t3
    t4 = #1
    t5 = i + t4
    i = t5
    goto L0
L1:
    ret resultado
fin factorial
```

### 2.1 Una sola rendición de cada instrucción

Antes, `--ir` formateaba las instrucciones en `tac_print()`. Al agregar la vista
de bloques hacía falta imprimirlas otra vez, y una segunda copia del formateo
significa que la misma instrucción puede verse distinta según por dónde se la
mire.

Se extrajo `tac_print_inst()`, que imprime **una** instrucción. La usan `--ir`,
el listado de `--bloques` y el panel del IDE. Es el mismo criterio que se aplicó
en la Iteración 1 con el lexer: una definición, muchas vistas.

---

## 3. Bloques básicos

Un **bloque básico** es una secuencia máxima de instrucciones donde el flujo
entra por la primera y sale por la última: no hay saltos hacia adentro salvo al
inicio, ni saltos hacia afuera salvo al final.

### 3.1 El algoritmo de líderes

Dos pasadas sobre la lista de tres direcciones de cada función.

**Pasada 1 — marcar líderes.** Una instrucción es líder si:

| | Condición |
|---|---|
| a | Es la primera de la función |
| b | Lleva una etiqueta (puede ser destino de un salto) |
| c | Sigue inmediatamente a un salto, un retorno o un `halt` |

**Pasada 2 — delimitar.** Cada líder abre un bloque que llega hasta la
instrucción anterior al siguiente líder.

Sobre `factorial` eso da cuatro bloques:

```
  B0 [entrada]            t0 = #1 · resultado = t0 · t1 = #1 · i = t1
  B1 (L0)                 L0: · t2 = i <= n · ifFalse t2 goto L1
  B2                      t3 = resultado * i · ... · goto L0
  B3 (L1)                 L1: · ret resultado
```

### 3.2 Dos decisiones que conviene justificar

**`TAC_CALL` no parte el bloque.** El grafo es *intraprocedural*: una llamada
devuelve el control a la instrucción siguiente, así que dentro de la función es
una instrucción más. Partir en cada llamada daría un grafo más fragmentado sin
información adicional, y reduciría el tamaño de los bloques justo donde la
calendarización en bundles VLIW necesita margen para empaquetar. Lo que sí hay
que respetar al reordenar es que una llamada tiene efectos; eso es una
**dependencia**, no una arista del grafo.

**Toda etiqueta abre bloque, aunque nadie salte a ella.** Comprobar primero si
está referenciada ahorraría algún bloque, pero el grafo quedaría dependiendo del
orden de recorrido. Un bloque de más no cuesta nada: el que quede sin
predecesores se reporta como inalcanzable, que es información útil y no un
defecto.

---

## 4. El grafo de flujo de control

### 4.1 Aristas

Las salidas de un bloque dependen de cómo termina:

| Termina en | Aristas de salida |
|---|---|
| `caida` — ninguna transferencia | al bloque siguiente |
| `salto` — `goto L` | al bloque de `L` |
| `condicional` — `ifFalse`/`ifTrue L` | **dos**: a `L` y al siguiente (la caída) |
| `retorno` — `ret` / `ret v` | ninguna: es salida de la función |
| `halt` | ninguna |
| `tailcall` — `@cauda` | de regreso al bloque 0 |

Los predecesores se derivan de los sucesores, de modo que no pueden quedar
descuadrados. Hay una prueba que lo verifica.

### 4.2 Alcanzabilidad y código muerto

Un recorrido en profundidad desde el bloque de entrada marca qué bloques son
alcanzables. Los que no lo son **son código muerto**: ninguna ejecución pasa por
ahí.

Medido sobre los 23 programas de `test/ejemplos` y `test/ejecucion`, el
compilador emite hoy **16 bloques inalcanzables**:

| Contenido | Veces |
|---|---|
| `ret` — el retorno de seguridad que el generador agrega al final de toda función | 10 |
| `goto Lx` — un salto muerto | 4 |
| Bloques de etiqueta vacíos | 2 |

Ninguno contiene cálculo, así que no hay falsos positivos. Esos 16 bloques son
el primer material concreto para la eliminación de código muerto de la
Iteración 3.

### 4.3 Detección de lazos

Una arista de un bloque hacia otro de índice **menor o igual** es una **arista
de regreso**: el flujo vuelve atrás, y lo que queda entre el destino y el origen
es el cuerpo de un lazo. Se marca la profundidad de ciclo de esos bloques.

Alcanza para lo que necesitan las iteraciones siguientes: saber qué código está
dentro de un lazo, que es donde el desenrollado y la calendarización rinden. Un
análisis de dominadores daría los lazos naturales con más precisión, pero aquí
el código lo genera el propio compilador y los lazos salen siempre bien anidados.

---

## 5. Cómo verlo

### 5.1 Desde la terminal

```bash
./novac --ir prueba.nv        # el código de tres direcciones
./novac --bloques prueba.nv   # los bloques y el grafo
```

`--bloques` imprime, por función, cada bloque con su etiqueta, sus predecesores,
sus sucesores, cómo termina, si está en un lazo, si es inalcanzable, y su código:

```
functio factorial: 4 bloques, 4 aristas

  B1 (L0) [en lazo, nivel 1]
      predecesores: B0, B2
      sucesores:    B3, B2   (termina en condicional)
    L0:
        t2 = i <= n
        ifFalse t2 goto L1
```

### 5.2 Desde el IDE

La pestaña **Flujo** dibuja el grafo. Los bloques se reparten en niveles según
el camino más largo desde la entrada contando solo aristas hacia adelante — las
de regreso se excluyen, porque si contaran un bloque dentro de un ciclo no
tendría nivel finito. Así un `si/aliter` queda con sus dos ramas lado a lado y
el lazo se dibuja como un arco que sube.

| Elemento | Significado |
|---|---|
| Línea gris continua | flujo normal |
| Línea ámbar discontinua | arista de regreso: cierra un lazo |
| Borde verde | bloque de entrada |
| Borde rojo punteado | bloque inalcanzable |
| Fondo más oscuro | bloque dentro de un lazo |

Al hacer clic en un bloque se ve su código de tres direcciones, y cada
instrucción enlaza con la línea del programa fuente que la originó.

---

## 6. Pruebas

```bash
make prueba-ide    # 69 pruebas (eran 54)
```

El bloque `[5]` agrega 15 pruebas:

| Qué comprueba |
|---|
| Una función sin saltos es un único bloque básico |
| El bloque 0 es la entrada y no tiene predecesores |
| Cada sucesor registra a su predecesor (coherencia del grafo) |
| La cuenta de aristas coincide con las aristas listadas |
| Un ciclo `dum` produce una arista de regreso |
| La cabeza del lazo y su cuerpo quedan marcados, y el resto no |
| Todo bloque condicional tiene exactamente dos sucesores |
| Se reconocen los tres puntos de decisión del programa de prueba |
| Un programa sin código muerto no tiene bloques inalcanzables |
| El código después de un retorno queda en un bloque inalcanzable |
| Un bloque inalcanzable no tiene predecesores |
| `novac --bloques` y el IDE reportan el mismo grafo |
| Sobre un programa con errores no se construye el grafo, y se explica por qué |

---

## 7. Por qué esto importa para lo que sigue

El grafo no es un entregable decorativo: es la estructura sobre la que corren
las tres iteraciones restantes.

| Iteración | Qué necesita del grafo |
|---|---|
| **3** — eliminación de código muerto | Bloques inalcanzables, y análisis de *liveness* recorriendo el grafo **hacia atrás** desde los usos hasta las definiciones |
| **3** — reordenamiento | El reordenamiento solo es seguro **dentro** de un bloque, porque ahí no hay saltos que cambien el orden |
| **3** — loop unrolling | Reconocer los ciclos: las aristas de regreso dicen cuáles son |
| **3** — spilling register | Los rangos de vida de los temporales salen del mismo análisis de liveness |
| **4** — calendarización en bundles | Empaquetar operaciones independientes dentro de cada bloque |

El profesor mencionó explícitamente que «vamos a tener que hacer y manipular los
recorridos de los grafos para poder calcular y ver si una variable está viva, y
si no está viva poder eliminarla». Ese recorrido es exactamente el análisis de
liveness sobre este grafo, y es lo primero de la Iteración 3.

### La línea base que hay que mejorar

El listado de `--bloques` junto al de `-p` (bundles y slots) deja ver el
problema que las optimizaciones tienen que atacar. En el código generado hoy,
casi todo bundle usa **un solo slot de cinco**, y entre un productor y su
consumidor quedan dos bundles vacíos por la latencia de tres:

```
0x00B0   movi r10, #1    | - | -                | - | -
0x00C0   -               | - | -                | - | -     <- vacío
0x00D0   -               | - | -                | - | -     <- vacío
0x00E0   -               | - | sw r10, #12(r14) | - | -
```

El bundle no queda vacío por falta de ranuras sino por falta de **trabajo
independiente**. En un lazo, el trabajo independiente son las otras vueltas: por
eso el desenrollado es lo que habilita la calendarización, y por eso reconocer
los lazos en el grafo es el paso previo.
