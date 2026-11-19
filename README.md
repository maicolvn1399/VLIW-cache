# Compilador Nova para CERBERO

Compilador del lenguaje Nova para el procesador VLIW CERBERO. El proyecto
incluye análisis léxico, sintáctico y semántico, generación de TAC, optimización,
generación de código VLIW e IDE web.

## Requisitos

En Ubuntu:

```bash
sudo apt update
sudo apt install -y build-essential flex bison python3 iverilog
```

`iverilog` y `vvp` se necesitan para ejecutar programas sobre el RTL. `verilator`
es opcional y se usa al correr el lint de la arquitectura.

## Compilar

Desde la raíz del proyecto:

```bash
make
```

Esto construye `novac` y `novaide`. Para ver las opciones del compilador:

```bash
./novac --help
```

## Abrir y usar el IDE

Inicia el servidor con:

```bash
make ide
```

Deja abierta esa terminal mientras uses el IDE. Se abrirá el navegador y la
terminal mostrará la dirección:

```text
http://127.0.0.1:8099/
```

Si el navegador no se abre automáticamente, copia esa dirección en Chrome o en
otro navegador **del mismo equipo donde corre el servidor**. Si estás usando
SSH, un contenedor o VS Code remoto, reenvía el puerto `8099` desde la pestaña
**Ports** de VS Code y abre la dirección reenviada.

El IDE ya está funcionando si `make ide` dice `Address already in use`: abre la
dirección existente en lugar de iniciar otra instancia. Para levantar otra en
un puerto libre:

```bash
python3 ide/servidor.py --puerto 8100
```

Luego abre `http://127.0.0.1:8100/`. También puedes impedir que el servidor
intente abrir un navegador:

```bash
python3 ide/servidor.py --sin-navegador
```

### Flujo básico

1. Escribe o abre un archivo Nova en el panel izquierdo. Los diagnósticos y el
   coloreado se actualizan mientras editas.
2. Selecciona `-O0`, `-O1` o `-O2` en **Nivel de optimización**.
3. Selecciona el reporte que quieres ver en **Salida** y presiona **Compilar**.
4. Presiona **Ejecutar RTL** para ejecutar el programa en CERBERO. La pestaña
   **Resultado** muestra R6, los valores de `scribe`, ciclos, instrucciones e
   IPC.
5. Abre **DMEM final** para consultar la memoria completa. Puedes filtrar las
   palabras no-cero o buscar por dirección y valor.

La ejecución RTL requiere `iverilog`, `vvp` y las fuentes de
`ARQUITECTURA/src/cpu`. Para `-O1` y `-O2`, el IDE compara R6 y `scribe` con
`-O0`. La DMEM es una instantánea final, no una vista paso a paso. Si relacionas
una variable local con una dirección de DMEM, genera la tabla de símbolos con
el mismo nivel de optimización: `-O2` puede cambiar el tamaño de los marcos de
pila y las direcciones absolutas respecto a `-O0`.

## Usar el compilador desde la terminal

Ejemplo de compilación:

```bash
./novac test/ejecucion/suma_10_15.nv -o suma.nvx
```

Reportes disponibles:

```bash
./novac --tokens test/ejecucion/suma_10_15.nv  # tokens
./novac -t test/ejecucion/suma_10_15.nv        # AST
./novac --sym test/ejecucion/suma_10_15.nv     # tabla de símbolos
./novac --ir test/ejecucion/suma_10_15.nv      # TAC
./novac -s test/ejecucion/suma_10_15.nv        # ensamblador
./novac -p test/ejecucion/suma_10_15.nv        # bundles y slots
```

Los niveles de optimización son acumulativos: `-O1` aplica eliminación de
código muerto y propagación; `-O2` agrega desenrollado de bucles, asignación de
temporales a registros y reordenamiento. Una optimización puede dejar intacto
un programa si no encuentra transformaciones seguras o útiles.

## Pruebas

```bash
make test                     # pruebas del compilador
make prueba-ide               # pruebas del núcleo del IDE
make prueba-rtl               # programas Nova ejecutados en CERBERO RTL
make prueba-rtl-equivalencia  # compara los resultados optimizados con -O0
```

`make prueba-rtl` necesita Icarus Verilog y las fuentes RTL de
`ARQUITECTURA/src/cpu`. `make cerbero` ejecuta, por separado, el lint y las
pruebas del procesador. Las fuentes y fixtures de `test/` se conservan porque
los objetivos de prueba dependen de ellos.

## Estructura

| Ruta | Contenido |
|---|---|
| `fase1_lexico/`–`fase6_optimizacion/` | Fases del compilador |
| `ide/` y `fase5_ide/` | Interfaz web y núcleo del IDE |
| `test/` | Pruebas del compilador, IDE y ejecución RTL |
| `pruebas_profesor/` | Programas y pruebas de integración del curso |
| `entregables/` | Binarios, ensamblador e imágenes preparados para entregar |
| `ensambladores/` | Listados `.asm` de referencia; `entregables/` se regenera desde el compilador |
| `documentacion/` | Guías, pruebas y documentación del compilador |
| `ARQUITECTURA/` | Procesador CERBERO usado como referencia de ejecución |

Para regenerar los archivos de entrega en `entregables/`:

```bash
make entregables
```

Este objetivo reemplaza el contenido existente de `entregables/`.

La [guía de pruebas del IDE](./documentacion/PRUEBAS_IDE.md) describe sus
paneles; la [guía de demo](./documentacion/GUIA_PRUEBAS_Y_DEMO.md) y la
[guía de defensa](./documentacion/GUIA_DEFENSA_COMPILADOR.md) contienen más
ejemplos de uso.

## Rendimiento

Qué gana cada nivel de optimización, medido sobre el RTL:
[evidencia de optimización](./documentacion/EVIDENCIA_OPTIMIZACION.md).

Qué le hace cada nivel a la jerarquía de memoria y al empaquetado de bundles
—la Iteración 5 del proyecto de arquitectura—:
[los niveles contra la jerarquía](./documentacion/ITERACION5_NIVELES.md), con
las [tablas generadas](./documentacion/TABLAS_ITERACION5.md) y la medición en
crudo en [`medicion/`](./medicion/README.md).

```bash
make medir-niveles                        # mide y arma las tablas (~30 min)
make tabla-niveles METRICAS_DIR=medicion  # rehace las tablas sin simular
```
