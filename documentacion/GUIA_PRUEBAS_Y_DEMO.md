# Guía práctica para probar y demostrar Nova

Guion reproducible para revisar el compilador, sus optimizaciones, el IDE y la
ejecución en CERBERO. Los ejemplos apuntan a programas que ya están en el
repositorio: es mejor demostrar evidencia real que improvisar un programa
nuevo durante la defensa.

La especificación principal es
[ESPECIFICACION_PROYECTO2.txt](../ESPECIFICACION_PROYECTO2.txt), en particular
las secciones 4, 6, 7.2, 7.3, 8.2 y 9.2. Esta guía se centra en CE1108 y la
integración; no propone modificar `ARQUITECTURA/` ni el ISA.

## 1. Preparar una corrida limpia

En Windows, abrir una terminal WSL en la raíz del proyecto. El `Makefile` usa
`sh`, GCC, Flex, Bison, Python e Icarus Verilog para las pruebas RTL.

```sh
make
make test
make prueba-ide
make prueba-rtl
```

Antes de una defensa, correr las pruebas y guardar su salida. Si algo falla,
corregirlo antes de presentar; no ocultar advertencias ni reportar como
aprobada una prueba que no se ejecutó. `make prueba-rtl` es la comprobación
integral del compilador contra el RTL disponible.

## 2. Mostrar el recorrido del compilador

Usar un ejemplo pequeño y conocido:
[suma_10_15.nv](../test/ejecucion/suma_10_15.nv). En cada paso, explicar qué
produce esa fase y qué salida se está observando.

```sh
./novac --tokens test/ejecucion/suma_10_15.nv
./novac -t test/ejecucion/suma_10_15.nv
./novac --sym test/ejecucion/suma_10_15.nv
./novac --ir test/ejecucion/suma_10_15.nv
./novac --bloques test/ejecucion/suma_10_15.nv
./novac --vivacidad test/ejecucion/suma_10_15.nv
./novac --calendario test/ejecucion/suma_10_15.nv
./novac -p test/ejecucion/suma_10_15.nv
```

Señalar, respectivamente: tokens, AST, símbolos, TAC de tres direcciones,
bloques y flujo de control, conjuntos de vivacidad, slots/NOPs del calendario
y bundles con codificación. Para demostrar la generación del ejecutable:

```sh
./novac test/ejecucion/suma_10_15.nv -o /tmp/suma.nvx
make prueba-rtl-simple
```

La prueba RTL debe terminar con `R6 = 25`. Si se quiere inspeccionar el binario
de forma aislada, `make generar FUENTE_PRUEBA=test/ejecucion/suma_10_15.nv`
también guarda IR, ensamblador, paquetes e imágenes de memoria en `.salida/`.

## 3. Probar una optimización sin confundirla con otra

Comparar el mismo programa con `-O0` y el nivel que activa la transformación.
`--ir` permite ver el TAC; `--metricas` cuantifica cambios en TAC, instrucciones,
bundles, bytes y tiempos. No se debe afirmar que toda optimización siempre
reduce ciclos: se muestran los números medidos para ese programa.

```sh
./novac --ir -O0 test/optimizaciones/unroll_constante.nv
./novac --ir -O2 test/optimizaciones/unroll_constante.nv
./novac --metricas -O0 test/optimizaciones/unroll_constante.nv -o /dev/null
./novac --metricas -O2 test/optimizaciones/unroll_constante.nv -o /dev/null
```

`-O1` aplica DCE y las transformaciones locales de TAC. `-O2` agrega loop
unrolling, asignación de temporales a registros y reordenamiento seguro.
`--unroll=4` pide un factor explícito (1 a 64) y activa `-O2`.

## 4. Demostrar los requisitos de optimización

La sección 6 pide tres casos por grupo. Estos son los casos existentes que
permiten recorrerlos; abrir los archivos fuente antes de mostrar la salida.

### 4.1 Loop unrolling: constante, N pequeño variable y N grande

| Caso | Archivo | Qué explicar |
|---|---|---|
| Iteraciones constantes | [unroll_constante.nv](../test/optimizaciones/unroll_constante.nv) | El lazo tiene cinco iteraciones; el resultado esperado es 10. |
| Límite variable pequeño | [unroll_variable_pequena.nv](../test/optimizaciones/unroll_variable_pequena.nv) | El límite llega de una función; resultado 21. Probar el factor 4 para explicar el resto de iteraciones. |
| N grande | [unroll_variable_400.nv](../test/optimizaciones/unroll_variable_400.nv) | El límite es 400; resultado 79800. Explicar que la heurística limita el crecimiento del código. |

Comandos para contrastar TAC y solicitar un factor:

```sh
./novac --ir -O0 test/optimizaciones/unroll_variable_pequena.nv
./novac --ir -O2 test/optimizaciones/unroll_variable_pequena.nv
./novac --ir --unroll=4 test/optimizaciones/unroll_variable_pequena.nv
make prueba-rtl-unrolling
```

En la defensa, verificar que el resultado no cambia; en el IR optimizado, mostrar
cómo se repite el cuerpo del lazo y cómo se conserva la condición para las
iteraciones restantes. La prueba automatizada además comprueba límites y casos
con efectos.

### 4.2 DCE con efectos que deben conservarse

Usar estos tres programas:

* [dce_ciclo_scribe.nv](../test/optimizaciones/dce_ciclo_scribe.nv): el
  acumulador que no se devuelve es muerto; el acumulador de retorno y cada
  `scribe(i)` siguen siendo observables. Resultado: R6 = 6 y salida `0,1,2,3`.
* [propagacion_scribe.nv](../test/optimizaciones/propagacion_scribe.nv):
  muestra propagación y plegado sin perder el valor devuelto.
* [llamadas_scribe.nv](../test/optimizaciones/llamadas_scribe.nv): aunque
  se descarte el resultado de una llamada, la llamada y su `scribe` no se
  eliminan.

```sh
./novac --ir -O0 test/optimizaciones/dce_ciclo_scribe.nv
./novac --ir -O1 test/optimizaciones/dce_ciclo_scribe.nv
make prueba-rtl OPT=-O2
```

Señalar qué cálculo desaparece y qué efectos permanecen. La verificación debe
incluir R6 y la salida completa de `scribe`; también deben preservarse los
checks, stores, divisiones y llamadas con efectos. Los abortos 134, 136 y 137
son parte del comportamiento.

### 4.3 Dependencias WAW/WAR y reutilización de registros

| Dependencia | Archivo | R6 y `scribe` esperados |
|---|---|---:|
| WAW | [renombramiento_waw.nv](../test/optimizaciones/renombramiento_waw.nv) | 77 |
| WAR | [renombramiento_war.nv](../test/optimizaciones/renombramiento_war.nv) | 66 |
| Valor vivo alrededor de una llamada | [renombramiento_llamada.nv](../test/optimizaciones/renombramiento_llamada.nv) | 121 |

```sh
./novac --metricas -O0 test/optimizaciones/renombramiento_waw.nv -o /dev/null
./novac --metricas -O2 test/optimizaciones/renombramiento_waw.nv -o /dev/null
./novac --calendario -O2 test/optimizaciones/renombramiento_waw.nv
```

En métricas, mostrar el contador de temporales renombrados y la comparación de
dependencias/NOPs WAR y WAW antes y después. Aclarar que el compilador no debe
cambiar el resultado ni la salida observable; no basta con que el ensamblador
se vea distinto.

### 4.4 Reordenamiento seguro con control y funciones

| Caso | Archivo | R6 esperado |
|---|---|---:|
| Rama condicional | [reordenamiento_condicional.nv](../test/optimizaciones/reordenamiento_condicional.nv) | 16 |
| Ciclo | [reordenamiento_ciclo.nv](../test/optimizaciones/reordenamiento_ciclo.nv) | 74 |
| Lazos anidados | [reordenamiento_anidado.nv](../test/optimizaciones/reordenamiento_anidado.nv) | 13 |

```sh
./novac --metricas -O0 test/optimizaciones/reordenamiento_condicional.nv -o /dev/null
./novac --metricas -O2 test/optimizaciones/reordenamiento_condicional.nv -o /dev/null
./novac --calendario -O2 test/optimizaciones/reordenamiento_condicional.nv
```

Mostrar el contador de operaciones reordenadas y el calendario. Explicar que
solo se mueven operaciones independientes dentro del bloque; se respetan
dependencias, banderas, memoria, saltos, llamadas y slots de delay.

### 4.5 Spilling (derrame a pila) bajo presión de temporales

| Presión | Archivo | R6 esperado |
|---|---|---:|
| Muchos valores vivos | [asignacion_presion.nv](../test/optimizaciones/asignacion_presion.nv) | 78 |
| División | [asignacion_division.nv](../test/optimizaciones/asignacion_division.nv) | 80 |
| Operaciones criptográficas | [asignacion_cripto.nv](../test/optimizaciones/asignacion_cripto.nv) | 55 |

```sh
./novac --asignacion -O2 test/optimizaciones/asignacion_presion.nv
./novac --metricas -O2 test/optimizaciones/asignacion_presion.nv -o /dev/null
make prueba-rtl-unrolling
```

En `--asignacion`, señalar intervalos, registros usados y temporales que
quedaron en `spill slot`; en métricas, el contador de derrames y las cargas/
stores de pila evitados. La prueba específica verifica presión de más de ocho
temporales vivos y compara resultados en RTL.

## 5. Probar el IDE

Arrancar el servidor local:

```sh
make ide
```

Abrir `http://127.0.0.1:8099/` y demostrar en vivo:

1. Quitar un `;` para ver el diagnóstico y la ubicación del error; luego
   aplicar la corrección sugerida.
2. Escribir un prefijo como `res` dentro de una función para mostrar
   autocompletado y tipo.
3. Abrir **Flujo** y construir el CFG de
   `test/ide/cfg_ciclo.nv`; luego comparar con:

   ```sh
   ./novac --bloques test/ide/cfg_ciclo.nv
   ```
4. Abrir **Clones** y buscar en más de un archivo.
5. Si hay tiempo, comparar `-O0` y `-O2` en **métricas de compilación**.

El guion detallado, incluidos los resultados esperados de correcciones,
sugerencias, clones y flujo, está en
[PRUEBAS_IDE.md](./PRUEBAS_IDE.md).

## 6. Comparar rendimiento en el RTL

Para una comparación reproducible de `-O0`, `-O1` y `-O2` en el mismo programa:

```sh
make metricas-rtl FUENTE_PRUEBA=test/ejecucion/suma_10_15.nv RESULTADO_ESPERADO=25
```

Registrar ciclos, instrucciones e IPC para cada nivel. Acompañar las métricas
con la comprobación de R6 y `scribe`; los ciclos o IPC por sí solos no prueban
equivalencia. Para correr toda la suite con `-O2`:

```sh
make prueba-rtl OPT=-O2
```

No presentar los ciclos como una medición de consumo eléctrico: para afirmar
ahorro de energía haría falta medir potencia con un método y una plataforma
documentados.

## 7. Orden sugerido para una defensa corta

1. Mostrar `make test` y `make prueba-ide` completados.
2. Recorrer una fuente desde tokens/AST hasta TAC, calendario y bundles.
3. Comparar el mismo caso de optimización en `-O0` y `-O2`.
4. Usar un caso de cada tabla anterior; señalar el cambio y su resultado
   esperado.
5. Mostrar las pruebas en RTL y concluir con ciclos/IPC del mismo benchmark.
6. Terminar indicando límites: una optimización puede no mejorar toda carga,
   `-O2` está limitado por las precondiciones y los límites de código, y el
   ISA no implementa detección dinámica de hazards.

Para profundizar en el funcionamiento de las reglas, consultar
[T2_OPTIMIZACIONES.md](./T2_OPTIMIZACIONES.md),
[ITERACION4_OPTIMIZACIONES.md](./ITERACION4_OPTIMIZACIONES.md) y
[GUIA_DEFENSA_COMPILADOR.md](./GUIA_DEFENSA_COMPILADOR.md).
