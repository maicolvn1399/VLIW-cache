# Escribir un programa de CERBERO desde cero

**CE-4301 Arquitectura de Computadores I — Proyecto Grupal I — Grupo #4**

Para cuando hay que escribir un programa en el momento y sin consultar la
especificación entera. Todo lo que de verdad hace falta cabe en tres reglas;
el resto son patrones que se copian.

---

## Las tres reglas

### 1. Un bundle son cinco ranuras y termina en `;`

```
   S0 ALU-0   |   S1 ALU-1   |   S2 memoria   |   S3 cripto   |   S4 saltos   ;
```

Las ranuras que no se usan van con `-`, y las de la derecha se pueden omitir.

```
        add r1, r2, r3 ;                      // solo S0
        add r1, r2, r3 | sub r4, r5, r6 ;     // las dos ALU
        - | - | lw r1, #0(r2) ;               // memoria: hacen falta las barras
        - | - | - | - | br.ne lazo ;          // un salto va hasta S4
```

> **El error que todos cometemos la primera vez.** Escribir `lw r1, #0(r2) ;`
> suelto. Eso pone el `lw` en S0, que es una ALU, y el ensamblador responde
> `'lw' no es una instruccion del slot ALU (S0)`. Memoria y saltos **siempre**
> necesitan sus barras.

Qué va en cada ranura:

| | |
|---|---|
| **S0** | Toda la ALU. Es la única que escribe banderas, así que `cmp`, `cmpi`, `test` y `testi` solo existen aquí |
| **S1** | La misma ALU, menos las comparaciones |
| **S2** | `lw` `lh` `lb` `sw` `sh` `sb` y sus variantes con postincremento |
| **S3** | Cripto (`f4e`, `f4d`), bóveda (`login`, `ksetw`…) y la ALU corta (`add.s`, `mov.s`…), que es destructiva: `add.s r3, #4` es `r3 += 4` |
| **S4** | `br` `jal` `jr` `jalr` `halt` |

### 2. Tres bundles entre quien produce un valor y quien lo lee

```
        add r1, r2, r3 ;
        - ;
        - ;
        sub r4, r1, r5 ;        // aquí sí: han pasado 3 bundles
```

Vale igual para las **banderas**: entre `cmpi` y el `br` que las mira, y entre
`cmp` y un `setcc`. Y para el enlace de `jal`: `r15` no está listo hasta tres
bundles después.

Si falta alguno, el ensamblador avisa y el hardware entrega el valor viejo sin
decir nada. **La advertencia del ensamblador es la red de seguridad; conviene
leerla.**

### 3. Después de todo salto se ejecuta un bundle más

```
        - | - | - | - | br.ne lazo ;
        - ;                             // el delay slot, se ejecuta siempre
```

Se tome o no se tome el salto, el bundle de detrás se ejecuta. Se deja vacío
salvo que se quiera aprovechar. **Nunca se pone otro salto ahí**: la v1.2 del
ISA lo prohíbe.

---

## Los patrones

### Un lazo que cuenta

El esqueleto no cambia nunca:

```
        movi r2, #10 ;                  // cuántas vueltas
        - ;
        - ;
lazo:
        ...el trabajo...
        subi r2, r2, #1 ;
        - ;
        - ;
        cmpi r2, #0 ;
        - ;
        - ;
        - | - | - | - | br.ne lazo ;
        - ;
```

Está completo y funcionando en `tools/programas/contar_hasta_n.s`.

### Recorrer un arreglo

```
        movi r3, #0x400 ;               // puntero
        - ;
        - ;
lazo:
        - | - | lw r1, #0(r3) ;         // leer
        - ;
        - ;
        add r6, r6, r1 | add.s r3, #4 ; // usar y avanzar el puntero
```

`add.s r3, #4` es la ALU corta: ocupa S3, que suele estar libre, y deja las
dos ALU para el cálculo.

### Un condicional

```
        cmp r1, r2 ;                    // solo en S0
        - ;
        - ;
        - | - | - | - | br.ge es_mayor ;
        - ;
        ...rama del menor...
        - | - | - | - | br.al fin ;
        - ;
es_mayor:
        ...rama del mayor...
fin:
```

Condiciones: `al` (siempre) `eq` `ne` `lt` `ge` `ltu` `geu` `auth`.
Las sin signo son `ltu` y `geu`; **`C` es préstamo**, así que `geu` es `!C`.

### Llamar a una subrutina

```
        - | - | - | - | jal.al rutina ;
        - ;
        ...                             // r15 trae el retorno, listo a los 3 bundles
rutina:
        ...
        - | - | - | - | jr.al r15 ;
        - ;
```

Para saltar lejos (fuera del alcance de ±512 bundles) hay que usar un registro:

```
        movi r12, #0x7000 ;
        - ;
        - ;
        - | - | - | - | jalr.al r12 ;
        - ;
```

### Constantes de 32 bits

`movi` carga 19 bits con signo. Para una constante completa, `movi` y después
`movh`, en ese orden y con los tres bundles de por medio:

```
        movi r1, #0x3210 ;
        - ;
        - ;
        movh r1, #0x7654 ;              // ahora r1 = 0x76543210
```

---

## Llenar el bundle

Las tres reglas dan un programa correcto. Esto lo hace rápido, y es lo que
distingue a un VLIW de un procesador normal.

**Lo que no se puede juntar:** operaciones donde una lee lo que la otra
escribe. **Lo que sí:** todo lo demás.

```
        add r1, r2, r3 ;                // antes: tres bundles
        sub r4, r5, r6 ;
        - | - | lw r7, #0(r8) ;

        add r1, r2, r3 | sub r4, r5, r6 | lw r7, #0(r8) ;   // después: uno
```

Las tres son independientes, así que caben juntas. Dentro de un bundle **todas
las ranuras leen el estado de registros previo al bundle**, así que esto es
correcto y vale la pena saberlo:

```
        - | - | lw r1, #0(r4) | - | - ;
```
```
        addi r4, r4, #4 | - | lw r1, #0(r4) ;   // el lw lee el r4 VIEJO
```

Lo único prohibido es que **dos ranuras escriban el mismo registro** en el
mismo bundle: eso es un `WCONF`, gana la de menor índice y el PSW lo marca.

### Cuando el bundle se queda vacío de todas formas

Si el bundle queda vacío no es porque falten ranuras sino porque **no hay
trabajo independiente**: una cadena de operaciones dependientes cuesta tres
bundles por eslabón aunque las cinco ranuras estén libres.

En un lazo, el trabajo independiente son **las otras vueltas**. Desenrollar el
lazo las pone a la vista:

```
lazo:
        - | - | lw r10, #0(r4) ;        // cuatro elementos por vuelta
        - | - | lw r11, #4(r4) ;
        - | - | lw r12, #8(r4) ;
        - | - | lw r13, #12(r4) ;
        mul r10, r10, r10 ;             // ya no dependen entre sí
        mul r11, r11, r11 ;
        ...
```

`tools/programas/suma_simple.s` y `suma_vliw.s` son el mismo cálculo escrito
de las dos formas: 1042 ciclos contra 262, con el mismo resultado.

### Y no hay que empaquetar a mano

```bash
python3 tools/empacar.py mi_programa.s -o mi_programa_emp.s
```

Toma el programa escrito una operación por bundle y las junta respetando la
latencia, los puertos de escritura y el orden de la memoria. El programador
decide el algoritmo y si desenrolla; la herramienta hace la planificación.

---

## Probarlo

```bash
cd src/build
make correr PROG=mi_programa.s
```

Imprime los 16 registros, el PSW decodificado y, con `MOSTRAR=0x400
PALABRAS=8`, un trozo de memoria. Otras opciones útiles:

| | |
|---|---|
| `TRAZA=1-40` | El pipeline ciclo por ciclo, con el delay slot marcado |
| `ESCRITURAS=w.txt` | Cada escritura a registro y memoria, con su ciclo |
| `MEMORIA=d.hex` | Cargar una imagen de datos inicial |

> `make correr` **no verifica nada**: muestra el resultado, no lo compara.
> Un programa que calcula mal termina igual de bien. Para que quede verificado
> va a `tb_ejemplos.sv`, que compara contra valores esperados.

---

## Los errores que de verdad ocurren

| Síntoma | Causa |
|---|---|
| `'lw' no es una instruccion del slot ALU (S0)` | Falta `- \| - \|` delante de una instrucción de memoria |
| `el bundle debe terminar en ';'` | Falta el punto y coma, o hay un comentario sin `//` |
| El valor leído es el viejo | Menos de tres bundles desde su productor. El ensamblador lo avisó |
| El salto va a un sitio raro | Se olvidó el delay slot, o hay dos saltos seguidos |
| `dos slots escriben rN` | Dos ranuras del mismo bundle escriben el mismo registro |
| `salto fuera de alcance` | Más de ±512 bundles: usar `movi` + `jalr` |
| El programa no termina | Falta el `halt`, o el contador del lazo nunca llega a cero |

---

## Programas de referencia

| | |
|---|---|
| `contar_hasta_n.s` | El lazo mínimo, comentado paso a paso |
| `suma_simple.s` / `suma_vliw.s` | El mismo cálculo sin y con desenrollado |
| `estadisticas.s` | Arreglo, máximo y mínimo sin saltos, llamada a subrutina |
| `fibonacci.s` | Aritmética encadenada con la latencia al límite |
| `div32.s` | División sin signo, lazo de 32 vueltas |
| `sesion_sin_logout.s` | La bóveda y el cierre automático de sesión |
| `cobertura.s` | Usa los 63 mnemónicos del conjunto |
