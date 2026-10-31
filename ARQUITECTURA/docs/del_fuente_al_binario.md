# Del fuente al binario: cómo se obtienen el `.s` y el hexadecimal

**CE-4301 Arquitectura de Computadores I — Proyecto Grupal I — Grupo #4**

Esta es la respuesta a *«¿cómo se obtiene el ensamblador o el hexa de un
programa?»*. La cadena entera, con los comandos y con quién hace qué.

La especificación reparte el trabajo entre los dos cursos, pero **la cadena es
una sola y el lado de arquitectura puede recorrerla completo sin ayuda del
compilador**: `cerbero_asm.py` es nuestro, y para un programa escrito a mano no
hace falta nada más.

---

## El mapa

```
  programa.nv            programa.s              programa.hex
  (lenguaje NOVA)        (ensamblador)           (binario, un bundle
       │                      │                   de 128 bits por línea)
       │   novac -s           │  cerbero_asm.py        │
       └──────────┬───────────┘                        │
                  │                                    │
                  │  novac -o  (emisor propio)         │
                  └────────────────────────────────────┤
                                                       │
                                            novac_image.py
                                                       │
                                                       ▼
                                              imem.hex + dmem.hex
                                                       │
                                                       ▼
                                           el procesador (iverilog)
```

Hay **dos caminos** hasta el binario y los dos llegan al mismo sitio. Eso no es
redundancia: es la comprobación cruzada del proyecto, y más abajo está el
comando que lo demuestra.

---

## Camino A — desde un programa escrito a mano

Es el camino que no depende del compilador y el que conviene saber de memoria.

```bash
cd ARQUITECTURA

# 1. Ensamblar: del texto al binario
python3 tools/cerbero_asm.py tools/programas/contar_hasta_n.s \
        -o programa.hex --datos programa_datos.hex \
        --bundles 2048 --palabras 16384

# 2. Correrlo en el procesador
cd src/build
make correr PROG=contar_hasta_n.s MOSTRAR=0x400 PALABRAS=11
```

El paso 1 produce dos archivos:

| | |
|---|---|
| `programa.hex` | La memoria de instrucciones. Una línea por bundle, 32 dígitos hexadecimales = 128 bits |
| `programa_datos.hex` | La memoria de datos: lo que declaran `.word`, `.byte` y `.space` |

`make correr` hace el paso 1 por dentro, así que en la práctica basta con él.
El `.hex` queda en `src/build/programa.hex` por si hay que enseñarlo.

### Ver qué salió, bundle por bundle

```bash
python3 tools/cerbero_asm.py tools/programas/contar_hasta_n.s \
        -o /dev/null --listado programa.lst
```

El listado pone, en la misma línea, la dirección, la línea del fuente, las
cinco ranuras y los 16 bytes codificados. Es con lo que se comprueba a mano
que un salto quedó bien, y la sección «Fase 5» de `pruebas_profesor/LEEME.md`
hace exactamente esa comprobación.

---

## Camino B — desde un programa en NOVA

El compilador de CE 1108 hace las dos cosas de una pasada:

```bash
# Desde la raíz del proyecto unificado
./novac programa.nv -s -o programa.nvx
```

| | |
|---|---|
| `programa.asm` | El ensamblador, legible. **Ojo: hereda el nombre del `-o`**, no el del fuente |
| `programa.nvx` | El ejecutable binario propio de NOVA, con su cabecera |

Y de ahí a las imágenes de memoria:

```bash
python3 ARQUITECTURA/tools/novac_image.py programa.nvx \
        --imem programa.imem.hex --dmem programa.dmem.hex
```

El `.asm` también se puede ensamblar con **nuestra** herramienta, que es lo
interesante:

```bash
sed 's/\$/_/g' programa.asm > programa.s     # NOVA decora los símbolos con '$'
python3 ARQUITECTURA/tools/cerbero_asm.py programa.s \
        -o b.hex --datos b_d.hex --bundles 2048 --palabras 16384
```

---

## Los dos caminos dan el mismo binario

Esta es la comprobación que vale la pena saber enseñar, porque demuestra que
las dos implementaciones del ISA coinciden:

```bash
./novac programa.nv -s -o p.nvx
python3 ARQUITECTURA/tools/novac_image.py p.nvx --imem a.hex --dmem a_d.hex
sed 's/\$/_/g' p.asm > p.s
python3 ARQUITECTURA/tools/cerbero_asm.py p.s -o b.hex --datos b_d.hex \
        --bundles 2048 --palabras 16384
diff -i a.hex b.hex && echo "IDENTICOS en los 2048 bundles"
```

> El `-i` del `diff` hace falta porque `novac_image.py` escribe el hexadecimal
> en minúscula y `cerbero_asm.py` en mayúscula. `$readmemh` no distingue caja
> —lo dice el estándar de Verilog— así que los valores son los mismos.

`sh pruebas_profesor/arquitectura.sh` lo corre sobre los seis programas del
profesor y termina con `6 de 6 identicos bit a bit`.

---

## Qué hace el ensamblador por dentro

Dos pasadas, que es lo clásico y es lo que hay que poder explicar:

**Primera pasada.** Recorre las líneas asignando direcciones. Cada bundle
ocupa 16 bytes. Cuando ve una etiqueta, anota en qué dirección cayó. Procesa
las directivas (`.org`, `.word`, `.space`) y emite la memoria de datos. Al
terminar tiene la **tabla de símbolos**: cada nombre con su dirección.

**Segunda pasada.** Ahora sí codifica. Para cada bundle, mira sus cinco
ranuras y para cada una busca el opcode, lee los operandos y arma los bits.
Los saltos ya se pueden resolver porque la tabla de símbolos está completa:
el desplazamiento de un salto relativo es

```
destino − origen − 1
```

donde el `−1` es el delay slot, que se ejecuta siempre.

**De dónde salen los opcodes.** No están escritos dentro del ensamblador: los
lee de `src/cpu/cerbero_defs.svh`, el mismo archivo que incluye el RTL. Por eso
renumerar un opcode se hace en una línea y el hardware y el ensamblador quedan
sincronizados solos. Si estuvieran duplicados, el día que alguien cambiara uno
el ensamblador produciría binarios que el procesador no entiende, y los dos
«funcionarían» por separado.

**Lo que además comprueba.** Las validaciones de la sección 10.3 del ISA: dos
ranuras que escriben el mismo registro, una comparación fuera de S0, una
instrucción de memoria en la ranura de la ALU, un inmediato que no cabe, una
etiqueta sin definir. Y avisa —sin detenerse— cuando un valor se lee antes de
los tres bundles de latencia, que es el error más fácil de cometer.

---

## El formato del `.hex`

Una línea por bundle, 32 dígitos hexadecimales, del bundle 0 en adelante:

```
E700FFFC000000000000000000000000
0000000000000000000000000000A000
```

Los 128 bits se leen de izquierda a derecha como
`S0(32) S1(32) S2(32) S3(16) S4(16)`. El primero de arriba es
`movi r14, #65532` en S0 y nada más; el segundo es un `halt` en S4.

Lo carga `$readmemh` dentro de `imem.sv`. El archivo tiene que traer
exactamente tantas líneas como bundles tenga la memoria del testbench, y por
eso el `--bundles` del ensamblador: si sobran, Icarus avisa `Too many words`;
si faltan, `Not enough words`.

La memoria de datos es igual pero con palabras de 32 bits, una por línea.

---

## Resumen de comandos

| Para | Comando |
|---|---|
| Ensamblar a mano | `python3 tools/cerbero_asm.py x.s -o x.hex --datos x_d.hex --bundles 2048 --palabras 16384` |
| Ver el listado | añadir `--listado x.lst` |
| Correr en el procesador | `cd src/build && make correr PROG=x.s` |
| Correr un binario ya hecho | `make correr HEX=x.hex MEMORIA=x_d.hex` |
| Ver el pipeline | `make correr PROG=x.s TRAZA=1-40` |
| Ver cada escritura | `make correr PROG=x.s ESCRITURAS=x.txt` |
| Compilar NOVA a ensamblador | `./novac x.nv -s -o x.nvx` |
| NOVA a imágenes de memoria | `python3 ARQUITECTURA/tools/novac_image.py x.nvx --imem i.hex --dmem d.hex` |
| Empaquetar bundles | `python3 tools/empacar.py x.s -o x_emp.s` |
| Huella del cifrado | `python3 tools/huella.py archivo.txt` |
