# Alineación con la versión nueva de CERBERO

Revisión de `VLIW-cache-main` contra lo que Nova traía, y los cambios que hizo
falta hacer.

**Resultado corto: la generación de código no necesitó ni una línea de cambio.**
El procesador y el ISA son idénticos; lo que cambió es el banco de pruebas, y
trae una vía nueva que a Nova le conviene usar.

Estado después de los cambios: **233 pruebas**, **172 verificaciones**,
**13 corridas sobre el RTL**, **20 programas idénticos bit a bit** y las **6 del
profesor en 6 de 6**, todo pasando, sin advertencias de `gcc -Wall -Wextra`.

---

## 1. Qué cambió de verdad

Comparando archivo por archivo los dos árboles, **solo difieren dos**:

| Archivo | Qué cambió |
|---|---|
| `src/build/makefile` | Agrega `HEX=`, `RESULTADO=`, `ESCRITURAS=` y `ESCRITURAS_MAX=` a `make correr` |
| `src/tb/tb_programa.sv` | Los implementa, y además registra qué palabras de memoria escribió el programa |

**Lo que NO cambió**, y es lo que importaba:

- Todo `src/cpu/` — byte a byte idéntico. Las latencias, los formatos de slot y
  las codificaciones son las mismas.
- `docs/isa.md` — idéntico, sigue en v1.6.
- Todo `tools/` — `cerbero_asm.py` y `novac_image.py` sin cambios.

El nombre del repositorio, `VLIW-cache`, hace pensar en una caché que cambiaría
las latencias. **No hay tal caché**: `src/cpu/` no tiene ningún módulo de caché
y el ISA mantiene «ninguna detención por dependencias de datos; se emite un
bundle por ciclo». La regla de tres bundles entre productor y consumidor sigue
igual, que es de lo que depende todo el relleno que emite Nova.

Por eso las 20 imágenes siguen saliendo idénticas bit a bit contra
`cerbero_asm.py` sin tocar el generador.

---

## 2. La vía nueva: `HEX=`

Es el cambio que vale la pena aprovechar. `make correr` ahora acepta, en lugar
de un programa en ensamblador, **un binario ya ensamblado**: un bundle por línea
en hexadecimal, que es exactamente lo que produce `novac_image.py`.

El propio makefile lo describe como *«el que produce el ensamblador o un
compilador que emita binario»*, así que está pensado para este caso.

### Por qué conviene

El camino que usábamos pasaba por el ensamblador de ellos, y eso obligaba a un
rodeo: Nova decora los símbolos de módulo con `$`
(`m_Test2_934d2dec$maximo_lista`), carácter que no está en la gramática de
etiquetas de `cerbero_asm.py`. Había que renombrarlo con `sed` antes de
ensamblar.

Por la vía directa **ese problema desaparece**: dentro del binario las etiquetas
ya están resueltas a números, así que no hay ningún `$` que renombrar.

### Los dos caminos conviven

Conviene mostrar los dos, porque prueban cosas distintas:

| Camino | Qué demuestra |
|---|---|
| `PROG=programa.s` | Que las dos implementaciones del ISA coinciden: el texto de Nova, ensamblado por la herramienta de ellos |
| `HEX=imagen.hex` | Que el binario que Nova produce por su cuenta corre en el procesador tal cual |

`pruebas_profesor/arquitectura.sh` ahora corre **los dos** sobre las mismas seis
pruebas. Los seis programas dan el mismo `R6` por ambos caminos.

### Una trampa que conviene conocer

**`HEX=` carga solo la memoria de instrucciones y deja la de datos vacía.**

Un programa con literales de cadena entonces **corre sin fallar y da un
resultado equivocado**, que es la peor forma de equivocarse. Medido con
`saludo.nv`:

```
HEX= solo:            3 palabras de salida, sin el texto     (220 ciclos)
HEX= con MEMORIA=:    6 palabras, "Salve, mundo" completo    (346 ciclos)
```

Sin los datos, `scribe` lee ceros donde está la longitud de la cadena y la
salta. No hay error, no hay excepción en el PSW: simplemente sale menos.

Por eso las dos imágenes van **siempre** juntas:

```sh
make correr HEX=programa.nova.hex MEMORIA=programa.nova_d.hex
```

---

## 3. Lo que se cambió en Nova

Ningún cambio en el compilador. Tres en la documentación y los guiones:

| Archivo | Cambio |
|---|---|
| `ARQUITECTURA/` | Reemplazado por `VLIW-cache-main` |
| `pruebas_profesor/arquitectura.sh` | Paso 6 nuevo: cada programa también por la vía directa `HEX= + MEMORIA=` |
| `pruebas_profesor/LEEME.md` | Documenta la vía nueva y la trampa de `MEMORIA=` |
| `README.md` | Menciona las dos formas de correr en el testbench |

El testbench de CERBERO ahora deja `resultado_*.txt` y `escrituras_*.txt` en
`ARQUITECTURA/src/build/`, que es su propio directorio de trabajo; su
`make limpiar` ya los contempla. No ensucian la raíz del proyecto.

El `escrituras_*.txt` es útil y no lo teníamos antes: registra **cada escritura
a registro y a memoria de toda la corrida**, con su ciclo, su bundle y la
instrucción que la hizo.

---

## 4. Dos cosas para avisarle al grupo de CE 4301

Están en `ARQUITECTURA/docs/compiler-integration.md`, sección 5, y describen a
Nova como menos capaz de lo que es. Conviene corregirlas antes de que alguien
las lea como el estado actual.

**«No hay enlazador. Los programas de un solo archivo están completos; los que
importan otro módulo se reportan con el error E401.»**

Ya no es cierto. Comprobado: `Test3.nv` importa `Test2.nv`, compila con `rc=0`,
**no emite E401**, y corre en el procesador dando `R6 = 110`. Además `novac -c`
produce objetos `.nvo` de 235 bytes. El enlazador está hecho y funciona por los
dos caminos del testbench.

**«La ocupación medida va de 0,22 a 0,49 instrucciones por bundle.»**

El rango real hoy es **0,04 a 0,49**. Los programas que usan la bóveda lo bajan,
porque el `.org 0x7000` de la región segura mete relleno que cuenta como
bundles: `boveda` queda en 0,04 y `cifrado`/`descifrado` en 0,09. La media sigue
siendo 0,31. Se reproduce con `make ocupacion`.

**Y una sugerencia:** `HEX=` no aparece en `compiler-integration.md`. Siendo la
vía pensada para un compilador que emite binario, valdría la pena documentarla
ahí, junto con la advertencia de que necesita `MEMORIA=` cuando el programa
tiene datos inicializados.

---

## 5. Cómo comprobarlo

```sh
make clean && make              # sin advertencias
make prueba                     # 233 pruebas
make depurar F=todo             # las verificaciones extendidas
sh tools/verificar.sh           # las dos baterias, el RTL y los 20 bit a bit
sh pruebas_profesor/correr.sh   # 6 de 6 contra el original en Python
sh pruebas_profesor/arquitectura.sh   # 6 de 6 bit a bit, por los dos caminos
```

Y la vía nueva, sobre una prueba sola:

```sh
T=Test3
O=pruebas_profesor/.salida_arq
RAIZ=$(pwd)
mkdir -p $O
./novac pruebas_profesor/$T.nv -o $O/$T.nvx > /dev/null
python3 ARQUITECTURA/tools/novac_image.py $O/$T.nvx --imem $O/$T.nova.hex --dmem $O/$T.nova_d.hex
( cd ARQUITECTURA/src/build && make correr HEX=$RAIZ/$O/$T.nova.hex MEMORIA=$RAIZ/$O/$T.nova_d.hex )
```

Sin `cerbero_asm.py` y sin el `sed`: el binario de Nova entra directo y da
`r6 = 0000006e`, que son 110.
