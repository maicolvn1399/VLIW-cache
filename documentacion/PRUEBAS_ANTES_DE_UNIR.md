# Qué probar antes de unir los dos proyectos

El objetivo de esta ronda no es lucir el compilador: es **decidir si se puede
unir**. Por eso el orden importa — los pasos están de más decisivo a menos.

Si el paso 1 falla, no sigás: eso es lo que hay que arreglar antes de tocar el
merge.

---

## Parte A — Terminal

### Paso 1 · La prueba que decide (hacela primero)

```bash
make prueba-rtl-equivalencia
```

Corre cada programa del corpus sobre el RTL en `-O0`, `-O1` **y `-O2`**, y
compara el valor de retorno R6 y la salida de `scribe` entre niveles. Si un
programa da distinto, la optimización está rota.

> **Esto es lo que cambié.** El script recorría `for level in 0 1`: el corpus
> real se verificaba en `-O0` y `-O1`, y `-O2` solo sobre casos hechos a medida
> más un programa real. Y `-O2` es justo el nivel que desenrolla lazos,
> reordena instrucciones y asigna registros con derrame — las tres cosas que
> pueden cambiar el resultado sin que falle la compilación. La cobertura estaba
> al revés del riesgo.

Son 39 programas × 3 niveles. Lo que tiene que salir al final:

```
equivalencia RTL: 117 correctas, 0 fallidas (-O0/-O1/-O2)
```

**Si alguno falla**, el script imprime `FALLO: <archivo> -O<nivel>` y los lista
al final. Mandame esa lista: el nivel y el programa ya acotan cuál de las tres
transformaciones es la culpable.

### Paso 2 · Que el binario siga siendo CERBERO válido

```bash
                sh tools/verificar.sh 12
OPT=-O1         sh tools/verificar.sh 12
OPT=-O2         sh tools/verificar.sh 12
```

Pasa nuestro ensamblador por el **ensamblador independiente del equipo de
CE4301** y compara bit a bit con nuestro binario. Los tres tienen que dar:

```
identicos: 26, distintos: 0
```

Ya lo corrí de mi lado y da eso en los tres niveles. Lo repetís para confirmar
que en tu máquina también.

### Paso 3 · Las pruebas del profesor, en los tres niveles

```bash
make prueba-rtl-profesor
OPT=-O1 make prueba-rtl-profesor
OPT=-O2 make prueba-rtl-profesor
```

Test1 a Test6 sobre el RTL, cada uno contra su `.esperado`. Tienen que dar
`RESULTADO: OK` los seis, en los tres niveles. Son los programas que el profesor
va a querer ver corriendo.

### Paso 4 · El resto de la cadena

```bash
make prueba-unidad     # 295 pruebas del compilador
make prueba-ide        # 128 pruebas del nucleo del IDE
make prueba-rtl        # la bateria completa sobre el RTL
make prueba-ciclos     # el simulador de ciclos en C
```

Las dos primeras ya pasan de mi lado. `prueba-ide` pasa **ahora**: había una
prueba que se contradecía consigo misma y no podía pasar en una máquina sin
Icarus. En la tuya nunca la viste fallar porque sí tenés `iverilog`.

### Paso 5 · Memoria

```bash
valgrind -q ./novac -O2 test/ejemplos/mergesort.nv -o /dev/null
```

Corrí los 67 programas del corpus en `-O2` bajo valgrind: cero errores. Con uno
que hagas alcanza para confirmar que en tu entorno también.

---

## Parte B — El IDE

```bash
make ide        # abre http://127.0.0.1:8099/
```

Abrí `test/ejecucion/matriz_for.nv` desde **Archivos del proyecto**. Ese
programa es el mejor demo porque en `-O2` dispara **desenrollado, reordenamiento
y renombramiento** a la vez, y además es uno de los que corre sobre el RTL con
valor esperado conocido (138).

### Paso 6 · La tabla que hay que entender antes de enseñarla

En la barra de arriba hay un selector **-O0 / -O1 / -O2**. Poné el modo en
**métricas de compilación** y dale a Ejecutar una vez por nivel. Después abrí la
pestaña **Optimizacion**.

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| instrucciones de tres direcciones | 72 | 69 | **98** |
| bundles emitidos | 336 | 332 | **417** |
| bucles desenrollados | 0 | 0 | **2** |
| instrucciones reordenadas | 0 | 0 | **58** |
| registros renombrados | 0 | 0 | **23** |
| ocupación media | 0.46 / 5 | 0.46 / 5 | **0.49 / 5** |

> **Mirá bien: en `-O2` el programa se hace MÁS GRANDE.** 336 → 417 bundles, un
> 24 % más. Si el profesor ve solo esta tabla, la pregunta obvia es «¿y entonces
> en qué mejoró?».

### Paso 7 · La respuesta, y la demostración de la frase del profesor

El tamaño estático no es el tiempo de ejecución. Poné el modo en **métricas** y
mirá los ciclos simulados, o corré en terminal:

```bash
./novac --ciclos -O0 test/ejecucion/matriz_for.nv -o /tmp/x.nvx
./novac --ciclos -O2 test/ejecucion/matriz_for.nv -o /tmp/x.nvx
```

| | `-O0` | `-O1` | `-O2` |
|---|---|---|---|
| bundles **emitidos** (tamaño) | 336 | 332 | **417**  (+24 %) |
| ciclos **ejecutados** | 2735 | 2687 | **1897**  (−31 %) |
| IPC | 0.472 | 0.472 | **0.511** |

**El código crece 24 % y corre 31 % más rápido.** Eso es exactamente lo que
hace el desenrollado: cambia espacio por tiempo. Donde había N vueltas de un
cuerpo chico ahora hay N/4 vueltas de un cuerpo cuatro veces más grande —
menos saltos, menos actualizaciones del contador, y más trabajo independiente
que el planificador puede meter en el mismo bundle. Por eso el IPC sube.

> Es la frase del profesor —«cuando se optimiza, el tiempo de compilación sube
> y el de ejecución baja»— con un matiz que conviene decir vos antes de que lo
> pregunte él: **el tamaño también puede subir, y está bien que suba.**

### Paso 8 · Ejecutarlo de verdad

Pestaña **Ejecucion**. Corré `matriz_for.nv` en `-O0` y después en `-O2`.

- **R6 tiene que dar 138 en los dos.** Ese es el valor esperado del programa.
- Los **ciclos** tienen que bajar en `-O2`.
- La pestaña **DMEM final** muestra la memoria al terminar.

Que R6 no cambie y los ciclos sí bajen, en la misma pantalla, es la
demostración más corta de que la optimización funciona y no rompe nada.

### Paso 9 · Derrame de registros

`matriz_for` no derrama ninguno. Para eso abrí
`test/optimizaciones/asignacion_presion.nv` en `-O2`:

```
  temporales asignados a registro:    13
  derramadas:                         11
```

Y en terminal, el detalle con los intervalos de vida:

```bash
./novac --asignacion -O2 test/optimizaciones/asignacion_presion.nv
```

```
Funcion principale: 24 temporales, 11 derramados
  t0 [0,24] -> spill slot 0
  t1 [1,23] -> spill slot 1
```

Los `[0,24]` son los **intervalos de vida**, y salen del análisis de vivacidad
de la Iteración 3. Ese es el enlace que conviene señalar: el *spilling* no es
una optimización aparte, es la misma información de liveness usada para decidir
qué valor se queda en registro y cuál se manda a memoria cuando hay más valores
vivos que registros.

> Ojo: `--asignacion` con `-o` manda el **reporte** a ese archivo en vez de a
> pantalla, como el resto de las banderas de inspección de este compilador.
> Corrélo sin `-o`.

### Paso 10 · Que el grafo y la vivacidad siguen ahí

Pestaña **Flujo** → Construir grafo. Los conjuntos `USO`, `DEF`, `VIVO_ENT`,
`VIVO_SAL` por bloque, y lo que `-O1` elimina tachado en su sitio. Es la
Iteración 3, y es de donde salen los intervalos del paso anterior.

---

## Resumen

| Paso | Qué decide |
|---|---|
| **1** | **Si se puede unir o no** |
| 2 | Que el binario es CERBERO válido |
| 3 | Que las pruebas del profesor corren en los tres niveles |
| 4–5 | Que no hay regresiones ni problemas de memoria |
| 6–8 | Que las métricas se entienden y se pueden defender |
| 9–10 | Que el spilling se conecta con la vivacidad |

Si el paso 1 sale `117 correctas, 0 fallidas`, el lado de compiladores está
listo y pasamos al merge.
