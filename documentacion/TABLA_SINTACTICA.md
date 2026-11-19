# La tabla sintáctica de Nova

**CE1108 Compiladores e Intérpretes · fase 2, análisis sintáctico**

## La respuesta corta

> **No hay tabla LL(1), y no es un olvido: el parser de Nova no es LL(1).**
> Es **LALR(1)**, generado por bison. La tabla equivalente sí existe, está
> completa, y se genera con `make tabla-sintactica`.

---

## 1. Por qué no es LL(1)

Son dos familias distintas de análisis sintáctico:

| | LL(1) | LALR(1) — lo que usa Nova |
|---|---|---|
| Dirección | **Descendente** (top-down), predictivo | **Ascendente** (bottom-up), *shift-reduce* |
| Deriva | por la izquierda | por la derecha, en reversa |
| La tabla indexa | `[no terminal × terminal]` | `[estado × símbolo]` |
| Cada celda contiene | qué producción aplicar | desplazar / reducir / ir-a |
| Se construye con | conjuntos **PRIMEROS** y **SIGUIENTES** | el **autómata de elementos LR(0)** más los símbolos de anticipación |
| Poder | estricto subconjunto | reconoce más gramáticas |

### La razón técnica: recursión por la izquierda

La gramática de Nova **no puede ser LL(1)** tal como está, porque es recursiva
por la izquierda, que es exactamente lo que un parser descendente no puede
manejar — entraría en bucle infinito llamándose a sí mismo sin consumir ningún
símbolo.

```
expresion             : expresion TK_AUT expresion        ← y los 16 operadores binarios
parametros            : parametros TK_COMA parametro
sentencias_opt        : sentencias_opt sentencia
lista_inicializadores : lista_inicializadores TK_COMA inicializador
importaciones_opt     : importaciones_opt importacion
```

Y esa recursión por la izquierda **es deliberada**, no un descuido: es la que
le da la asociatividad correcta a los operadores. Con `expresion: expresion '-'
expresion` y `%left TK_MENOS`, la expresión `a - b - c` se agrupa como
`(a - b) - c`, que es lo que manda la aritmética. Una gramática LL(1) tendría
que escribirse con recursión por la derecha y recuperar la asociatividad
izquierda después, en el código de las acciones.

### La otra razón: precedencia de operadores

El archivo `fase2_sintactico/nova.y` declara once niveles de precedencia
(líneas 71–81):

```
%left TK_AUT          /* aut  -- el mas debil */
%left TK_ET
...
%left TK_POR TK_ENTRE TK_MODULO
%precedence TK_NON TK_NOT UMENOS   /* unarios -- el mas fuerte */
```

Declarar precedencia y asociatividad para resolver conflictos *desplazar /
reducir* es un mecanismo **propio del análisis ascendente**: presupone que el
parser llega a un punto donde puede reducir una regla o desplazar un token y
hay que decidir. En LL(1) ese dilema no existe, porque la decisión se toma
antes, mirando un solo token por adelantado. La sola presencia de estas
declaraciones ya dice que el parser no es LL(1).

---

## 2. La tabla que sí tiene el proyecto

```bash
make tabla-sintactica
```

Deja `documentacion/tabla_sintactica.txt` con el autómata completo:

| | |
|---|---|
| Reglas de la gramática | **131** |
| Terminales (tokens) | **65** |
| No terminales | **45** |
| Estados del autómata LALR(1) | **257** |
| Conflictos sin resolver | **0** |

El archivo tiene cinco partes:

1. **`Grammar`** — las 131 producciones numeradas. Ese número es el que se
   reduce: cuando el reporte dice «reduce using rule 116», es esta lista.
2. **`Terminals, with rules where they appear`** — cada token y en qué reglas
   aparece.
3. **`Nonterminals, with rules where they appear`** — para cada no terminal, en
   qué reglas se define y en cuáles se usa.
4. **`State 0` … `State 256`** — el autómata. Es el cuerpo de la tabla.
5. Al final, cómo se resolvió **cada conflicto** por precedencia.

### Cómo se lee un estado

```
State 21

   19 decl_func: TK_FUNCTIO . TK_IDENT TK_PAR_IZQ parametros_opt ...

    TK_IDENT  shift, and go to state 30
```

- La regla con un **punto** es el *elemento*: marca hasta dónde se reconoció.
  Aquí ya se vio `TK_FUNCTIO` y se espera el nombre de la función.
- `TK_IDENT shift, and go to state 30` es una **celda de la tabla de acción**:
  en el estado 21, con el token `TK_IDENT` por delante, desplazar y pasar al
  estado 30.
- Donde aparece `reduce using rule N`, es una celda de reducción.
- Donde aparece `nombre_no_terminal  go to state N`, es una celda de la
  **tabla de ir-a** (*goto*).

Esas tres clases de celda — desplazar, reducir, ir-a — **son la tabla
sintáctica**. Que esté impresa estado por estado en vez de como una matriz es
solo el formato de bison: la matriz completa sería de **257 estados × 110
símbolos** (65 terminales para la tabla de acción, 45 no terminales para la de
ir-a), unas 28 000 celdas casi todas vacías. El formato por estado lista
únicamente las celdas con contenido.

### Los conflictos y cómo se resolvieron

El reporte termina con líneas como:

```
Conflict between rule 116 and token TK_AUT resolved as reduce (TK_AUT < UMENOS).
```

Se lee: en cierto estado, el parser podía reducir la regla 116 (el menos
unario) o desplazar `TK_AUT`. Como `TK_AUT` tiene **menos** precedencia que
`UMENOS`, se resuelve **reduciendo** — es decir, `-a aut b` se agrupa como
`(-a) aut b` y no como `-(a aut b)`.

**Todos los conflictos quedan resueltos por las declaraciones de precedencia:
bison termina con cero conflictos pendientes**, que es lo que hay que poder
afirmar de una gramática terminada. Se comprueba así:

```bash
bison -d -o /dev/null fase2_sintactico/nova.y   # sin advertencias, salida 0
```

---

## 3. Si lo que se pide es una tabla LL(1) de verdad

Entonces no alcanza con generarla: **habría que reescribir la gramática**, y el
lenguaje saldría distinto por dentro. Harían falta tres cosas:

| Paso | Qué implica |
|---|---|
| **Eliminar la recursión izquierda** | `expresion : expresion OP termino` pasa a `expresion : termino expresion'` con `expresion' : OP termino expresion' \| ε`, para las once capas de precedencia. |
| **Factorizar por la izquierda** | Las reglas que comparten prefijo (una sentencia que empieza con `TK_IDENT` puede ser asignación, llamada o indexado) hay que factorizarlas. |
| **Recuperar la asociatividad en las acciones** | Al quedar recursiva por la derecha, `a - b - c` se agrupa mal por omisión; hay que reconstruir el árbol a mano. |

Además se perdería el mecanismo de recuperación de errores de bison (el token
`error`, que usa la regla 12 `declaracion_global: error`), del que dependen
varios diagnósticos del IDE.

**Esto no es algo que convenga decidir sobre la marcha.** Si el profesor lo
exige como entregable, hay dos caminos y conviene preguntarle cuál quiere:

1. **Documentar la gramática en forma LL(1)** — con la recursión izquierda
   eliminada, y sus tablas de PRIMEROS, SIGUIENTES y la tabla predictiva — como
   un anexo, dejando el compilador tal como está. Es trabajo de papel y no
   toca una línea de código.
2. **Cambiar el parser a descenso recursivo LL(1)**, reescribiendo
   `fase2_sintactico/`. Eso sí rehace la fase 2 entera y hay que volver a
   validar las 233 pruebas.

---

## 4. Dónde está cada cosa

| Qué | Archivo | Líneas |
|---|---|---|
| La gramática, en notación bison | `fase2_sintactico/nova.y` | 131 reglas |
| Declaraciones de precedencia y asociatividad | `fase2_sintactico/nova.y` | 71–81 |
| Mensajes de error detallados (`parse.error verbose`) | `fase2_sintactico/nova.y` | 43 |
| Recuperación de errores con el token `error` | `fase2_sintactico/nova.y` | regla 12 |
| Invocación de bison | `Makefile` | 69–70 |
| Generación de la tabla | `Makefile` | objetivo `tabla-sintactica` |
| **La tabla completa** | `documentacion/tabla_sintactica.txt` | 257 estados |
