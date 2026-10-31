# Integración con el compilador Nova (CE1108)

Este documento describe el contrato de interfaz entre el procesador CERBERO-1
(CE4301) y el compilador Nova del grupo de contraparte de CE1108, y reúne la
evidencia de la validación conjunta que piden las secciones 6.1, 6.2 y 8.2.2c
del enunciado.

| | |
| :--- | :--- |
| Procesador | CERBERO-1, CE4301 Arquitectura de Computadores I, Grupo #4 |
| Compilador | `novac`, lenguaje Nova, CE1108 Compiladores e Intérpretes |
| Contraparte CE1108 | Araya Porras Luis Diego · Piedra Montero Joseph · Somarribas Montero Isaac |
| Especificación compartida | [`isa.md`](isa.md), con su registro de cambios en la sección 14 |
| Documentación del compilador | `documentacion/documentacion_compilador.pdf`, en el proyecto unificado |
| Proyecto unificado | Rama `integracion_global`: el compilador en la raíz y este procesador en `ARQUITECTURA/` |

La integración se corre desde el proyecto unificado, porque ahí conviven `novac`
y el procesador. **Todas las rutas y los comandos de este documento son
relativos a la raíz de ese proyecto**, salvo los enlaces a otros documentos de
`docs/`.

---

## 1. Resumen

El compilador traduce un programa Nova hasta binario de CERBERO y el binario
corre sobre el RTL de este proyecto sin modificaciones. Se comprobó por dos
caminos independientes que llegan a la misma imagen de memoria:

| Camino | Quién produce el binario | Resultado de `demo_revision.nv` |
| :--- | :--- | :--- |
| A | `novac` emite el ejecutable `.nvx`, y `novac_image.py` lo pasa a `.hex` | `R6 = 110`, 843 ciclos, sin fallas |
| B | `novac -s` emite el ensamblador, y **nuestro** `cerbero_asm.py` lo ensambla | `R6 = 110`, 842 bundles ejecutados, sin fallas |

Las dos imágenes de memoria de instrucciones coinciden en los 2048 bundles. El
camino B es el más fuerte como evidencia: el texto que generó el compilador lo
lee una herramienta escrita por el otro curso, que no comparte código con él, y
el resultado es el mismo binario.

---

## 2. El contrato de interfaz (sección 6.1)

| Obligación de CE4301 | Cómo se cumple |
| :--- | :--- |
| Un ensamblador propio, autónomo, que ejercite el 100 % del conjunto | `ARQUITECTURA/tools/cerbero_asm.py`. `ARQUITECTURA/tools/programas/cobertura.s` usa los 63 mnemónicos y `make cobertura` lo comprueba. `probar_asm.py` tiene 71 casos y verifica que ningún mnemónico quede sin cubrir |
| Entregar la especificación completa del ISA, con la codificación binaria exacta de cada instrucción y slot, y la sintaxis del ensamblador | [`isa.md`](isa.md): formato del bundle, los ocho formatos de slot, tablas de opcodes, convención de registros (sección 1.1) y sintaxis del ensamblador (sección 10) |
| Poner a disposición el modelo de simulación | El RTL completo en `ARQUITECTURA/src/cpu`, con `make correr` para ejecutar cualquier programa y un testbench propio de la contraparte, `test/tb_nova_rtl.sv`, que instancia el `top` sin cambios |
| Comunicar formalmente todo cambio posterior al congelamiento | La sección 14 de [`isa.md`](isa.md), versiones v1.1 a v1.6. Cada cambio indica si afecta o no al emisor de binario |

El intercambio funcionó en los dos sentidos. La v1.6 del ISA, que corrige cómo
se extrae un criptograma a un archivo, salió de una pregunta del grupo de CE1108
al probar con un archivo más grande que el de prueba.

### 2.1 Lo que el compilador toma del ISA

Estas son las decisiones del ISA que el generador de código tiene que respetar,
y cómo las resuelve `novac` según su documentación:

| Regla del ISA | Cómo la resuelve el compilador |
| :--- | :--- |
| Tres bundles entre productor y consumidor, sin detección por hardware | Lleva la cuenta de en qué bundle queda disponible cada registro y las banderas, e inserta bundles vacíos solo donde hacen falta. Pone una barrera antes de cada salto y de cada etiqueta |
| Un delay slot después de cada salto, que siempre se ejecuta | Emite un bundle después de cada salto |
| `HALT` también tiene delay slot (v1.2) | Emite un bundle después de cada `halt` |
| No puede haber un salto en el delay slot (v1.2) | El delay slot que emite nunca lleva salto |
| Desplazamiento de 10 bits del tipo C, ±512 bundles | Relajación de saltos: los que quedan fuera de rango se reescriben con `movi` más `jr`/`jalr` del tipo J, y el programa se reconstruye hasta que ninguno se desborde |
| Convención de registros (sección 1.1) | Argumentos en `R6`–`R9`, retorno en `R6`, dirección de retorno en `R15`, pila en `R14` desde `0xFFFC`, temporales en `R10` y `R11`. `R0:R1` queda reservado como el par criptográfico `P0` |
| El ISA no tiene `DIV` | Llama a `__div32`, el nombre que fija la v1.3 |
| El ISA no define puertos de E/S | `scribe` y `dic` escriben en una zona de salida en memoria: la cantidad de palabras en `0x3000` y los datos desde `0x3004` |
| La bóveda solo se usa desde el slot S3 | Las intrínsecas del lenguaje bajan directo a instrucciones de S3: `ingredere` → `AUTHW` ×4 + `LOGIN`, `custodi` → `KSETW` ×4, `feistel` → `F4E` |

Los errores de ejecución del lenguaje se reportan dejando un código en `R6`
antes del `halt`: 134 índice fuera de rango, 136 división entre cero y 137 uso
de la bóveda sin autenticar.

### 2.2 El formato del ejecutable

El ISA no fija un formato de archivo ejecutable, así que el compilador propone
uno y `ARQUITECTURA/tools/novac_image.py` lo convierte en las dos imágenes que cargan
`imem.sv` y `dmem.sv` con `$readmemh`. Cada bundle ocupa 16 bytes en
little-endian, con los cinco slots en las posiciones del ISA: S0 en `127:96`, S1
en `95:64`, S2 en `63:32`, S3 en `31:16` y S4 en `15:0`. Se emiten los ocho
formatos: A, I, M, F, V, AC, C y J.

El encabezado mide 48 bytes:

| Desplazamiento | Campo | Contenido |
| ---: | :--- | :--- |
| 0 | `magia` | `"NOVA"` |
| 4 | `version` | versión, más un campo reservado |
| 8 | `n_bundles` | cantidad de bundles de 16 bytes que siguen al encabezado |
| 12 | `codigo_org` | dirección de IMEM donde se carga el código |
| 16 | `entrada` | dirección de la primera instrucción |
| 20 | `datos_org` | dirección de DMEM donde empieza la sección de datos |
| 24 | `datos_init` | bytes inicializados que trae el archivo |
| 28 | `datos_cero` | bytes que el cargador pone en cero a continuación |
| 32 | `pila_tope` | valor inicial de `R14`, `0xFFFC` |
| 36 | `suma` | verificación del código más los datos inicializados |
| 40 | reservado | dos palabras para el enlazador |

`novac_image.py` verifica la suma antes de escribir las imágenes, y rechaza un
ejecutable que no quepa en IMEM (2048 bundles) o en DMEM (64 KB).

---

## 3. Evidencia de la validación conjunta (sección 6.2)

### 3.1 El programa fuente

`demo_revision.nv`, en la raíz del proyecto. Usa lazos, condicionales, llamadas
con parámetros y retorno, y un arreglo pasado por referencia:

```
functio suma_cuadrados(n : integer) -> integer {
    varia acc : integer = 0;
    varia i   : integer = 1;
    dum (i <= n) {
        acc = acc + i * i;
        i = i + 1;
    }
    redde acc;
}

functio maximo(v : integer[], n : integer) -> integer {
    varia m : integer = v[0];
    varia i : integer = 1;
    dum (i < n) {
        si (v[i] > m) { m = v[i]; }
        i = i + 1;
    }
    redde m;
}

functio principale() -> integer {
    varia datos : integer[4] = {10, 30, 20, 5};
    redde suma_cuadrados(7) - maximo(datos, 4);
}
```

El valor esperado se calcula a mano: la suma de los cuadrados de 1 a 7 es
1 + 4 + 9 + 16 + 25 + 36 + 49 = 140, el máximo de `{10, 30, 20, 5}` es 30, y
140 − 30 = **110** (`0x6E`).

### 3.2 Lo que generó el compilador

```bash
./novac demo_revision.nv -s -o demo.nvx
```

El ensamblador completo está en `demo_revision.s`. Ocupa 376 bundles, de
`0x0000` a `0x1770`, y termina con la tabla de símbolos ya resuelta: 21
etiquetas de código y 2 de datos. Este es el arranque:

```
__inicio:
    movi r14, #65532           | -          | -                      | -                  | -                ;  // 0x0000
    -                          | -          | -                      | -                  | -                ;  // 0x0010
    -                          | -          | -                      | -                  | -                ;  // 0x0020
    -                          | -          | -                      | -                  | jal.al principale ;  // 0x0030
    -                          | -          | -                      | -                  | -                ;  // 0x0040
    -                          | -          | -                      | -                  | halt             ;  // 0x0050
    -                          | -          | -                      | -                  | -                ;  // 0x0060
```

En esas siete líneas ya se ven las reglas de la sección 2.1:

- los dos bundles vacíos entre `movi r14` y el primer uso de `r14`;
- el delay slot después del `jal`;
- el bundle después del `halt`.

Cada grupo de bundles lleva como comentario la línea y la columna del fuente
Nova de la que salió, y cada bundle lleva su dirección, así que un salto se
puede seguir a mano.

### 3.3 Camino B: el ensamblador del compilador, ensamblado por CERBERO

```bash
cp demo.asm ARQUITECTURA/tools/programas/demo.s
cd ARQUITECTURA/src/build
make correr PROG=demo.s
```

```
python3 ../../tools/cerbero_asm.py ../../tools/programas/demo.s -o programa.hex --datos programa_datos.hex \
       --bundles 2048 --palabras 16384 --listado programa.lst
programa.hex: 2048 bundles
programa_datos.hex: 16384 palabras
programa.lst: listado
=== tb_programa: programa.hex ===
    memoria de datos inicial: programa_datos.hex

  el programa llego a HALT en 851 ciclos, 842 bundles ejecutados

  registros
    r0  = 00000000            0        r1  = 00000000            0
    r2  = 00000000            0        r3  = 00000000            0
    r4  = 00000000            0        r5  = 00000000            0
    r6  = 0000006e          110        r7  = 00000004            4
    r8  = 00000004            4        r9  = 00000000            0
    r10 = 0000006e          110        r11 = 0000001e           30
    r12 = 00000000            0        r13 = 00000000            0
    r14 = 0000ffdc        65500        r15 = 000016a0         5792

  PSW = 00000001
    banderas  Z=1 N=0 C=0 V=0
    boveda    AUTH=0 AUTHFAIL=0
    fallas    EXC=0 CAUSE=ninguna

---
TERMINO: el programa llego a HALT
```

| Registro | Valor | Qué es |
| :--- | ---: | :--- |
| `R6` | 110 | El valor de retorno de `principale`, el esperado |
| `R11` | 30 | El máximo, el último valor que dejó `maximo` en un temporal |
| `R14` | `0xFFDC` | La pila con el marco de 32 bytes de `principale` todavía abierto, porque `principale` termina en `halt` y no retorna |
| `R15` | `0x16A0` | La dirección de retorno de la última llamada, la de `maximo` en `0x1680` más los dos bundles del salto y su delay slot |
| PSW | `EXC=0` | Ninguna falla en 842 bundles: ningún `ILLOP`, `MISALIGN`, `RANGE` ni `WCONF` |

`EXC=0` importa tanto como el 110. El hardware no detecta dependencias, así que
un bundle mal calendarizado no se detiene: da un resultado equivocado sin
avisar, o levanta `WCONF` si dos slots escriben el mismo registro. Un programa
de 842 bundles que termina sin fallas y con el resultado correcto muestra que el
calendarizador del compilador respeta las latencias del ISA.

### 3.4 El pipeline por dentro

Con `TRAZA=1-40`, `make correr` dibuja una fila por bundle y una columna por
ciclo. Los primeros cinco bundles:

```
make correr PROG=demo.s TRAZA=1-40

  bundle                               1   2   3   4   5   6   7   8   9  10
  00000  movi r14, #65532             ID  EX  ME  WB
  00010  -                            IF  ID  EX  ME  WB
  00020  -                                IF  ID  EX  ME  WB
  00030  jal.al principale                    IF  ID  EX  ME  WB                <- salta a 01050
  00040  -                                        IF  ID  EX  ME  WB            (delay slot)
  01050  subi r14, r14, #32                           IF  ID  EX  ME  WB
  01060  -                                                IF  ID  EX  ME  WB
  01070  -                                                    IF  ID  EX  ME  WB
  01080  sw r15, #28(r14)                                         IF  ID  EX  ME  WB

  eventos
    ciclo     4  REG     r14 <- 0000fffc   (bundle 00000)
    ciclo     4  SALTO   jal.al principale en 00030 salta a 01050; el delay slot 00040 se ejecuta igual
    ciclo     7  REG     r15 <- 00000050   (bundle 00030)
    ciclo     9  REG     r14 <- 0000ffdc   (bundle 01050)
    ciclo    10  MEM     [0fff8] <- 00000050   (bundle 01080)
```

La traza muestra tres cosas del contrato funcionando sobre el código generado:

- Cinco bundles en etapas distintas en el mismo ciclo.
- El salto se resuelve en ID: el bundle de `0x0040` es el delay slot y se
  ejecuta, y el siguiente que se busca ya es el destino, `0x1050`.
- `subi r14` en `0x1050` lee `r14` en el ciclo 7, después de que `movi` lo
  escribió en el ciclo 4. El compilador separó a los dos con los bundles que
  hacían falta, y no con más.

### 3.5 Camino A: el binario de `novac`, sobre el RTL

```bash
sh test/run_rtl_test.sh ./novac demo_revision.nv 110 "ARQUITECTURA/src/cpu"
```

El script compila el programa, convierte el `.nvx` con `novac_image.py`, lo
simula con `test/tb_nova_rtl.sv` y compara `R6` contra el valor esperado:

```
=== ejecutable Nova sobre el RTL CERBERO ===
  ciclos: 843
  retorno R6: 110 (0x0000006e)
  scribe en DMEM del procesador (0 valores):
RESULTADO: OK
```

`tb_nova_rtl.sv` no se limita a comparar `R6`. También termina con `$fatal` si
el PSW registró una excepción, si la sesión de la bóveda quedó abierta o si
falló una autenticación. Para comprobar que la prueba sabe fallar, se corrió la
misma imagen pidiendo 111:

```
FATAL: test/tb_nova_rtl.sv:70: retorno incorrecto: esperado 111, obtenido 110
```

Los dos testbenches cuentan los ciclos con criterios distintos, y por eso uno
reporta 843 y el otro 851.

### 3.6 Los dos caminos dan el mismo binario

```bash
./novac demo_revision.nv -s -o demo.nvx
python3 ARQUITECTURA/tools/novac_image.py demo.nvx --imem a.hex --dmem a_d.hex
python3 ARQUITECTURA/tools/cerbero_asm.py demo.asm -o b.hex --datos b_d.hex --bundles 2048 --palabras 16384
diff -i a.hex b.hex && echo "IDENTICOS en los 2048 bundles"
diff -i a_d.hex b_d.hex && echo "y la DMEM tambien"
```

Hace falta `-i` porque `novac_image.py` escribe el hexadecimal en minúscula y
`cerbero_asm.py` en mayúscula. `$readmemh` lee las dos formas igual.

Se repitió con los archivos que el compilador dejó en el repositorio:
`cerbero_asm.py` ensambló `demo_revision.s`, y su imagen coincide con
`demo_revision.imem.hex` en los 2048 bundles y con `demo_revision.dmem.hex` en
las 16 384 palabras.

Es la comprobación más fuerte de la codificación. Dos herramientas escritas por
separado, cada una desde la sección del ISA que le corresponde, producen los
mismos 128 bits para cada uno de los 376 bundles del programa.

### 3.7 La bóveda y Feistel4 desde el lenguaje

`demo_crypto.nv` abre sesión en la bóveda, instala una llave y aplica una ronda
de Feistel4 a un bloque. Devuelve 0 si el resultado coincide con el que se
calcula a mano desde la fórmula del enunciado, y 1 si no:

```
F(x,k) = (ROL32(x,5) + k) XOR ROL32(x,13)

Bloque (0xDEADBEEF, 0xCAFEBABE), key[0] = 0x11111111:
  L nueva = R vieja       = 0xCAFEBABE
  R nueva = L XOR F(R, k) = 0x79120F5A
```

```bash
sh test/run_rtl_test.sh ./novac demo_crypto.nv 0 "ARQUITECTURA/src/cpu" "" "128'h0000_0000_0000_0000_0000_0000_7654_3210"
```

```
  ciclos: 307
  retorno R6: 0 (0x00000000)
RESULTADO: OK
```

El último argumento fija el `ROT_SECRET` del procesador para que coincida con la
credencial que pide `ingredere`. Sin él, el `LOGIN` no coincide, la ronda se
anula con `DENIED`, el bloque queda sin cifrar y el programa devuelve 1. Que la
prueba distinga los dos casos es lo que la hace valer.

---

## 4. Cómo reproducirlo

Desde la raíz del proyecto unificado, en Linux o WSL, con `novac` compilado:

| Qué | Comando | Resultado esperado |
| :--- | :--- | :--- |
| El programa de revisión, binario de `novac` | `sh test/run_rtl_test.sh ./novac demo_revision.nv 110 "ARQUITECTURA/src/cpu"` | `RESULTADO: OK` |
| El mismo, por el ensamblador de CERBERO | `make correr PROG=demo.s`, desde `ARQUITECTURA/src/build` | `r6 = 0000006e` |
| La ronda Feistel4 | ver la sección 3.7 | `RESULTADO: OK` |
| La batería completa | `make prueba-rtl` | Doce programas, cada uno contra su valor esperado |

Si en la revisión no da tiempo de compilar, `demo_revision.s`,
`demo_revision.imem.hex` y `demo_revision.dmem.hex` ya están generados en la
raíz del proyecto.

Cualquier programa con una `functio principale() -> integer` sirve para una
prueba en el momento. El valor que devuelve queda en `R6`:

```bash
sh test/run_rtl_test.sh ./novac programa.nv <valor_esperado> "ARQUITECTURA/src/cpu"
```

---

## 5. Limitaciones conocidas

- **El compilador no empaqueta varias operaciones por bundle.** Emite una
  instrucción por bundle y rellena con bundles vacíos lo que pide la latencia.
  La ocupación medida va de 0,22 a 0,49 instrucciones por bundle, y los slots S1
  y S3 quedan sin usar en el código de propósito general. El programa es
  correcto, pero no aprovecha el paralelismo del VLIW. El paralelismo entre
  slots sí se demuestra en los programas escritos a mano: `fibonacci.s` ocupa
  cuatro slots del mismo bundle en cada vuelta, y `lazo_estres.s` los cinco.
- **No hay asignación de registros.** Cada valor vive en la pila y cada
  operación carga sus operandos, calcula y guarda, usando `R10` y `R11` como
  temporales. Por eso el programa de revisión necesita 842 bundles para algo
  que a mano cabría en muchos menos.
- **No hay enlazador.** Los programas de un solo archivo están completos; los
  que importan otro módulo se reportan con el error E401.
- **El formato `.nvx` lo propuso el compilador**, porque el ISA no fija uno.
  `novac_image.py` es la única pieza de CERBERO que lo conoce, así que un cambio
  del formato no toca el RTL.
