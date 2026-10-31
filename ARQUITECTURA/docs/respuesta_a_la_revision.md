# Respuesta a los señalamientos de la revisión

**CE-4301 Arquitectura de Computadores I — Proyecto Grupal I — Grupo #4**

Los cinco puntos de la revisión, qué se hizo con cada uno y el comando que lo
demuestra. Todo lo de aquí entra en `make` y se verifica solo.

---

## 1. Los programas usaban un solo slot por bundle

**Era cierto, y el número es peor de lo que parecía.** Medido antes de tocar
nada, sobre los 22 programas que produce el compilador:

```
19534 bundles, 6003 instrucciones, 0.31 por bundle de 5 posibles
bundles con más de una instrucción: 0 de 19534
S1 (la segunda ALU): sin usar en todo el conjunto
```

Cero. Ni un solo bundle con dos instrucciones, y una de las dos ALU sin
estrenar. En los programas escritos a mano era mejor —14.7% con más de una—
pero tampoco era un VLIW.

### Qué se hizo

**`tools/empacar.py`**, el planificador que faltaba. Toma un programa escrito
una operación por bundle y junta las independientes, respetando la latencia de
tres bundles, los puertos de escritura, el orden de la memoria y el de la
bóveda. No tiene tablas de opcodes propias: importa las de `cerbero_asm.py`,
porque dos copias de la codificación del ISA es exactamente cómo se producen
binarios que ensamblan bien y calculan mal.

Incluye **renombrado de registros**, que es lo que de verdad desbloquea el
paralelismo. El generador de código usa `r10` y `r11` como únicos temporales y
los reutiliza en cada sentencia; eso crea dependencias falsas que serializan
sentencias que no tienen nada que ver entre sí. Renombrar las definiciones que
mueren dentro del bloque rompe esas cadenas.

### Y lo que empaquetar no puede arreglar

Aquí está la parte que vale la pena entender, porque explica por qué el
problema aparece en primer lugar.

Una cadena de operaciones dependientes cuesta **tres bundles por eslabón**
aunque las cinco ranuras estén libres:

```
        - | - | lw r5, #0(r4) ;
        - ;                        <- no hay nada que meter aquí
        - ;                        <- ni aquí
        mul r5, r5, r5 ;
```

El bundle no queda vacío por falta de ranuras sino por **falta de trabajo
independiente**. En un lazo, el trabajo independiente son las otras vueltas, y
desenrollarlo es lo que las pone a la vista del planificador.

`tools/programas/suma_simple.s` y `suma_vliw.s` son el mismo cálculo —la suma
de los cuadrados de 64 palabras, que da 89440— escrito de las dos formas:

| | ciclos | instrucciones por bundle |
|---|---:|---:|
| `suma_simple.s` tal cual | 1042 | 0.48 |
| `suma_simple.s` empaquetado | 592 | 0.75 |
| `suma_vliw.s` desenrollado | 318 | 0.73 |
| `suma_vliw.s` desenrollado y empaquetado | **262** | **0.96** |

Empaquetar solo vale 1.76×. Desenrollar **y** empaquetar, 3.98×. Los cuatro
dan 89440, que es lo que hace honesta la comparación.

> El techo de este lazo lo pone la LSU, que es una sola: dos accesos a memoria
> no caben en el mismo bundle. Con una carga por elemento, el límite es un
> elemento por bundle, y ahí llega la versión desenrollada.

### Los comandos

```bash
make ocupacion                  # el informe, programa por programa
make empacar PROG=x.s           # empaquetar uno
make vliw                       # la medición de los dos, verificada
```

`make vliw` entra en la suite: comprueba que las dos versiones dan el mismo
resultado y falla si la aceleración cae por debajo de 2×. No es una medida de
calidad del planificador sino una alarma, para que una regresión se note aquí
y no en una revisión.

---

## 2. No había forma comprobable de obtener el hash del cifrado

**`tools/huella.py`.** Imprime el SHA-256 del criptograma que produjo el
procesador, junto al de la implementación de referencia en Python:

```bash
make huella                                       # el archivo de prueba
make huella ARCHIVO=../../foto.png
make huella ARCHIVO=x.txt LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
```

```
  archivo        archivo_prueba.txt
  bytes          23  (+1 de relleno = 3 bloques de 64 bits)
  llave          11111111 22222222 33333333 44444444

  SHA-256 del criptograma, 24 bytes
    hardware    0cfd7d6a1623d418a22c5c9275cd6da9f959038d1e2fbf5c4a216fea0f3df8e6
    referencia  0cfd7d6a1623d418a22c5c9275cd6da9f959038d1e2fbf5c4a216fea0f3df8e6

  COINCIDEN
```

Corre el cifrado en el RTL, saca el criptograma de la memoria de datos y lo
compara. Funciona con cualquier archivo y cualquier llave.

**Lo que hay que fijar para que dos huellas sean comparables**, y es donde se
pierden la mitad de las comparaciones entre implementaciones distintas:

1. El archivo se rellena con ceros hasta un múltiplo de 8 bytes.
2. Cada bloque se parte en dos palabras de 32 bits **little-endian**; la
   primera es `L` y la segunda `R`.
3. Cuatro rondas con `key[0]` a `key[3]`, en ese orden.
4. Las palabras vuelven a bytes en little-endian.
5. El SHA-256 se calcula sobre esos bytes y **solo** sobre esos: los
   `8 × bloques` del criptograma, **sin** los 8 bytes de cabecera que
   `load_file.py` pone en memoria. La cabecera es del formato del buffer, no
   del cifrado.

Se imprime también el SHA-256 del archivo en claro, que sirve de control: si
ese no coincide, los dos no están cifrando lo mismo y no tiene sentido mirar
el otro.

---

## 3. Costó escribir un programa de cero en el ISA

Dos cosas, para que la próxima vez salga en el momento:

**`tools/programas/contar_hasta_n.s`** — el lazo que se pidió, comentado paso
a paso. Cuenta de 1 a N guardando cada número en memoria y dejando la suma en
`r6`. Entra en la suite (`tb_ejemplos`), así que está verificado y no es un
ejemplo que nadie corrió.

**`docs/escribir_programas.md`** — la guía. Todo lo que de verdad hace falta
son tres reglas:

1. Un bundle son cinco ranuras separadas por `|` y termina en `;`. Memoria y
   saltos **siempre** necesitan sus barras: `- | - | lw r1, #0(r2) ;`
2. Tres bundles entre quien produce un valor y quien lo lee. También para las
   banderas.
3. Después de todo salto se ejecuta un bundle más, el delay slot.

El resto son patrones que se copian: el esqueleto del lazo, recorrer un
arreglo, un condicional, llamar a una subrutina, armar una constante de 32
bits. Y una tabla de los errores que de verdad ocurren, con su causa.

---

## 4. No supimos explicar cómo se obtiene el `.s` o el hexadecimal

**`docs/del_fuente_al_binario.md`.** La cadena entera con los comandos, los
dos caminos —el del ensamblador propio y el del emisor binario de NOVA— y la
comprobación de que dan el mismo binario.

Lo esencial, para no depender del documento:

```bash
# Desde un programa escrito a mano: no hace falta el compilador para nada
python3 tools/cerbero_asm.py mi_programa.s -o p.hex --datos p_d.hex \
        --bundles 2048 --palabras 16384

# Desde NOVA
./novac programa.nv -s -o programa.nvx        # deja programa.asm y .nvx
python3 ARQUITECTURA/tools/novac_image.py programa.nvx \
        --imem i.hex --dmem d.hex
```

Y el ensamblador por dentro, que es lo que conviene poder explicar: dos
pasadas. La primera asigna direcciones (16 bytes por bundle) y anota dónde
cayó cada etiqueta; la segunda codifica, y ya puede resolver los saltos porque
la tabla de símbolos está completa. El desplazamiento de un salto relativo es
`destino − origen − 1`, donde el `−1` es el delay slot.

**Los opcodes no están escritos dentro del ensamblador**: los lee de
`src/cpu/cerbero_defs.svh`, el mismo archivo que incluye el RTL. Por eso
renumerar un opcode se hace en una línea y el hardware y la herramienta quedan
sincronizados solos.

---

## 5. No se encontró el testbench de la sesión sin `LOGOUT`

**La comprobación existía**, dentro de `tb_ejemplos`, mezclada con otros dos
programas. Eso bastaba para que la suite la corriera y no bastaba para que
alguien que viene a preguntar justo eso la encuentre: `make list` no la
nombraba y no había forma de correrla sola.

Ahora tiene nombre propio:

```bash
make logout
```

```
[1] la rutina SI abre sesion, dentro de la region segura
         subio en el ciclo 15, con el PC en 0x00007060
  ok     el PC estaba DENTRO de [0x7000, 0x7FFF] al abrirla

[2] la rutina vuelve SIN LOGOUT y la sesion se cierra sola
         bajo en el ciclo 24, con el PC en 0x000000a0
  ok     el PC estaba FUERA de la region al cerrarse
  ok     foto 2: AUTH = 0 ya afuera, sin haber ejecutado LOGOUT

[3] el cierre no es cosmetico: el permiso se retiro de verdad
  ok     foto 3: la ronda de afuera se anulo con DENIED
  ok     y la causa registrada es DENIED

[4] y la llave no quedo a la vista en ninguna parte
```

Los tres casos hacen falta los tres. Con solo el primero, un procesador que
**nunca** abriera sesión pasaría la prueba; el segundo es la pregunta del
enunciado; el tercero descarta que la bandera baje por cosmética y el permiso
siga ahí.

Registra el ciclo y el PC de cada flanco de `AUTH`, que es lo que convierte
«se cierra sola» en algo que se puede enseñar.

---

## Lo que además se pidió para el proyecto 2

> *«Revisar que el procesador y sus etapas funcionan correctamente.»*

```bash
make etapas
```

Corre los testbenches que miran la segmentación por dentro, no el resultado
final de un programa: cada frontera por separado campo a campo, la latencia
expuesta medida sobre la cadena real, el contador de programa con su delay
slot y `HALT`, los dos detectores de conflicto de escritura contrastados entre
sí, y las cinco etapas juntas sobre siete programas. **171 casos.**

---

## El estado, en números

```bash
make clean && make lint && make
```

| | |
|---|---|
| Análisis estático | 17 unidades, limpio |
| Casos de testbench | **1775** en 30 testbenches |
| Casos de herramientas | 151 en Python |
| Avisos esperados | 2 (`Not enough words` de `tb_dmem` y `tb_imem`) |
| Fallos | 0 |

Y desde la raíz del proyecto unificado, los dos cursos a la vez:

```bash
make todo
```

233 pruebas del compilador, la suite completa de CERBERO y 13 programas NOVA
ejecutados sobre el RTL.
