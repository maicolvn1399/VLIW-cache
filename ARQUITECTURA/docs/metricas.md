# Contadores de rendimiento y línea base

**Proyecto Grupal II — Iteración 1: línea base del procesador VLIW**

Este documento cubre lo que pide la Iteración 1 del proyecto: retomar el
procesador del Proyecto Grupal I, confirmar que su organización segmentada
sigue funcionando, y dejar instalados los contadores de rendimiento que van a
sostener todas las mediciones de las iteraciones siguientes.

La idea de fondo es simple. La jerarquía de caché se justifica por lo que
mejora, y "lo que mejora" solo existe si hay un número de antes. Este documento
produce ese número: el rendimiento de CERBERO-1 con una memoria de datos que
responde siempre en un ciclo, que es exactamente la suposición que la
Iteración 2 va a eliminar.

---

## 1. Qué se agregó y qué no se tocó

| | |
| :--- | :--- |
| Nuevo | `src/cpu/perf_counters.sv`, la unidad de contadores |
| Nuevo | `src/tb/tb_perf_counters.sv`, su testbench |
| Nuevo | `tools/tabla_metricas.py` y el objetivo `make metricas` |
| Modificado | `src/cpu/top.sv`: instancia la unidad y expone sus cuentas |
| Modificado | `src/tb/tb_programa.sv`: imprime las métricas y las contrasta |
| **Sin tocar** | El ISA: ni un opcode, ni un campo, ni un formato de bundle |
| **Sin tocar** | Las unidades funcionales, las fronteras de segmentación, las memorias |

El ISA no se tocó a propósito. El enunciado permite agregar instrucciones
nuevas de control de caché y medición (sección 3.1.2), pero esa extensión
obliga a renegociar el contrato con el compilador de CE1108, y los contadores
no la necesitan: salen por puertos de depuración del módulo `top`, que el
testbench lee directamente. Un programa no puede leerlos, y no hace falta que
pueda: quien analiza el rendimiento es quien corre la simulación.

Los puertos nuevos de `top.sv` son todos de salida. Los testbenches que no
miden nada los dejan sin conectar y siguen compilando sin cambios; eso se
comprobó corriendo las 31 unidades del proyecto.

---

## 2. Las métricas

Las de la tabla 1 del enunciado (métricas del procesador), más la ocupación por
ranura, que es la que responde a la observación del profesor sobre el
aprovechamiento de los bundles.

| Métrica | Qué cuenta | Dónde |
| :--- | :--- | :--- |
| Ciclos de ejecución | Ciclos desde que se suelta el reset hasta que `halted` sube | contador |
| Bundles ejecutados | Bundles válidos que avanzaron por el pipeline | contador |
| Instrucciones ejecutadas | Operaciones no-NOP en todos los slots de esos bundles | contador |
| Ocupación por ranura | Lo mismo, separado por slot: S0, S1, S2, S3, S4 | 5 contadores |
| Bundles vacíos | Bundles cuyos cinco slots traían NOP | contador |
| Saltos tomados | Saltos que la BRU resolvió como tomados | contador |
| Delay slots desperdiciados | Delay slots que no traían ninguna operación | contador |
| Ciclos perdidos por stalls | Ciclos con el pipeline congelado | contador (hoy siempre 0) |
| IPC | Instrucciones ÷ ciclos | derivada |
| Bundles por ciclo | Bundles ÷ ciclos | derivada |
| Ocupación del bundle | Instrucciones ÷ bundles, de 5 ranuras | derivada |

Las tres derivadas se calculan en el informe y no en hardware: un divisor
cuesta área y latencia para producir un número que una resta en el testbench da
igual de bien.

Las métricas de caché (hit/miss de L1-D y L2) y de memoria principal
(accesos, ciclos de transferencia, ancho de banda) no existen todavía porque no
existen todavía esos componentes. Entran con sus iteraciones: la 2 agrega las
de memoria principal y la 3 y la 4 las de cada nivel de caché.

---

## 3. Decisiones de diseño

### D1 — Se cuenta en decodificación, no en escritura

Un bundle se puede contar al entrar al pipeline (en ID) o al salir (en WB). En
CERBERO-1 las dos cuentas dan el mismo número, porque ningún bundle se descarta
nunca: no hay vaciado de pipeline, el delay slot lo evita, y una falla anula su
propio slot sin cancelar el bundle.

Se eligió ID porque es la única etapa donde los 128 bits del bundle existen
juntos. Los slots S0 a S3 cruzan la frontera ID/EX, pero S4 no: la BRU resuelve
en ID y a EX solo le llega su resultado. Contar en WB obligaría a arrastrar los
cinco opcodes tres etapas más, solo para medir.

### D2 — Un bundle se cuenta cuando avanza, no cuando está

La condición de conteo es `valid && !stall`, no `valid`.

Hoy son equivalentes, porque el pipeline nunca se detiene. Dejan de serlo en la
Iteración 3: un miss de L1-D congela el bundle completo, y el mismo bundle
quedaría varios ciclos seguidos en ID. Contar "cada ciclo con un bundle válido"
se convertiría, el día del primer miss, en una cuenta de ciclos disfrazada de
cuenta de bundles, y el IPC resultante sería 1 por construcción.

La entrada `stall` del módulo ya existe y hoy está atada a cero en `top.sv`.
La Iteración 3 le conecta la señal `cache_stall` de la jerarquía de memoria y
no hay que volver a tocar ni el módulo ni los contadores.

### D3 — Qué cuenta como instrucción ejecutada

Una operación no-NOP en cualquiera de los cinco slots de un bundle despachado.
En los cinco slots el NOP es el opcode cero, así que la prueba es la misma para
todos aunque el campo mida 5 o 3 bits.

Dos casos discutibles, y la razón por la que se cuentan:

- **Un salto condicional que no se toma.** La BRU lo evaluó: leyó las banderas
  y decidió. Que la decisión fuera seguir de largo no lo convierte en un NOP.
- **Una operación que levanta una falla.** Se decodificó y se ejecutó; lo que
  se anula es su escritura.

Las dos ocupan una ranura que ninguna otra operación pudo usar, y la medida que
importa —cuánto del paralelismo disponible usa el programa— tiene que verlas.

### D4 — Los contadores saturan y lo avisan

Un contador de 32 bits que da la vuelta no avisa: a los 4 294 967 296 eventos
vuelve a cero y el informe sale con un número chico, verosímil y falso. Aquí
cada contador se queda en su tope y enciende `desbordado`, un bit pegajoso que
el testbench revisa antes de imprimir nada.

Mientras ese bit esté apagado, las cifras son exactas. Si se enciende, el
informe dice que no se puede confiar en ellas en vez de inventar una. Con el
tope de ciclos de los testbenches (2 000 000) ningún programa se acerca al
límite: el contador más alto de toda la línea base (1 400 010 instrucciones en
`lazo_estres`) usa el 0,03 % del rango.

### D5 — Los contadores no tienen salida hacia el datapath

`perf_counters.sv` es la única unidad del procesador cuyas salidas no van a
ninguna otra. Solo observa señales que ya existían. Quitarla cambiaría el área,
no el resultado de ningún programa, y esa propiedad es lo que permite medir sin
preguntarse si la medición alteró lo medido.

---

## 4. Cómo se validan los números

Un contador equivocado no rompe nada: el programa corre igual y el error sale
como una cifra creíble en el informe. Por eso hay dos capas de verificación.

**La unidad, contra cuentas escritas a mano.** `tb_perf_counters.sv` arma
bundles sintéticos y verifica 54 casos: bundles llenos, vacíos, inválidos,
saltos con y sin delay slot aprovechado, el congelamiento por `stall` antes de
que exista la caché, el comportamiento en HALT, y la saturación (con una
segunda instancia de 8 bits, que llega al tope en 255 ciclos en vez de en
4,29 mil millones).

**El procesador completo, contra una cuenta independiente.**
`tb_programa.sv` cuenta por su lado mientras corre cada programa y compara al
final. El contraste vale por lo que es, y conviene decirlo con precisión:

| Comparación | Qué tan independiente es |
| :--- | :--- |
| Bundles | Independiente: el testbench mira `ex_valid`, una etapa distinta |
| Ciclos | Independiente: el testbench cuenta flancos |
| Instrucciones y ranuras | Parcial: decodifica el mismo `id_bundle`, con lógica escrita aparte |

La comparación de instrucciones comprueba el decodificador de NOP y la
acumulación, no la señal de origen. Si los dos leyeran mal el mismo cable,
ninguno lo notaría; ese hueco lo cubre `tb_perf_counters.sv`, que arma los
bundles él mismo.

Si alguna comparación no cuadra, la corrida termina con `$fatal`. Un informe
aproximado sería un informe falso.

---

## 5. La línea base

Medida con `make metricas`, sobre el RTL tal como quedó del Proyecto Grupal I,
con la memoria de datos respondiendo en un ciclo.

```
  programa               ciclos   bundles     instr     IPC    ocup    vacios   delay
  -------------------  --------  --------  --------  ------  ------  --------  ------
  contar_hasta_n.s           99        99        76   0.768    0.77     55   56%       9
  div32_prueba.s           4138      4138      2563   0.619    0.62   2163   52%     198
  estadisticas.s            811       811       567   0.699    0.70    402   50%      33
  feistel.s                  43        43        29   0.674    0.67     15   35%       2
  fibonacci.s               382       382       381   0.997    1.00    238   62%      46
  lazo_estres.s          900009    900009   1400010   1.556    1.56  500003   56%   99999
  sesion_sin_logout.s        34        34        25   0.735    0.74     15   44%       2
  suma_10_15.s                7         7         4   0.571    0.57      3   43%       0
  suma_simple_emp.s         583       583       453   0.777    0.78    260   45%      63
  suma_vliw_emp.s           253       253       267   1.055    1.06     55   22%      15

  ocupacion por ranura (operaciones no-NOP despachadas)

  programa                 S0      S1      S2      S3      S4
  -------------------  ------  ------  ------  ------  ------
  contar_hasta_n.s         32      12      11      10      11
  div32_prueba.s         1746     588      24       0     205
  estadisticas.s          344     166      14       0      43
  feistel.s                 1       0      12      13       3
  fibonacci.s              96      96      47      94      48
  lazo_estres.s        400005  400004  300000  200000  100001
  sesion_sin_logout.s       8       5       3       6       3
  suma_10_15.s              3       0       0       0       1
  suma_simple_emp.s       258      65      65       0      65
  suma_vliw_emp.s         149      36      65       0      17

  reparto del total (1404375 operaciones)   S0: 29%  S1: 29%  S2: 21%  S3: 14%  S4: 7%
```

### 5.1 Bundles por ciclo: 1,000 exacto

En todos los programas, `bundles ejecutados` es igual a `ciclos de ejecución`.
No es una coincidencia ni un error de medición: es la propiedad central del
diseño del Proyecto I. El pipeline no se detiene nunca, así que entra
exactamente un bundle por ciclo desde el reset hasta HALT.

Esa igualdad es también la línea base más importante del proyecto. Cuando la
caché entre, `bundles` va a quedar por debajo de `ciclos`, y la diferencia será
exactamente el costo de la jerarquía de memoria. Hoy esa diferencia es cero
porque la memoria de datos es ideal.

### 5.2 Los bundles están casi vacíos

La ocupación va de 0,57 a 1,56 operaciones por bundle, sobre cinco ranuras
disponibles. Entre el 22 % y el 62 % de los bundles no traen ninguna operación:
son ciclos completos gastados en nada.

Esto confirma, con medición y no con inspección del fuente, la observación del
profesor sobre el Proyecto I. El procesador puede despachar cinco operaciones
por ciclo y los programas le están dando una.

El reparto por ranura muestra dónde está el desbalance: S4 (saltos) recibe el
7 % de las operaciones y S3 el 14 %, mientras S0 concentra el 29 %. Hay
programas que ni siquiera tocan algunas unidades: `div32_prueba` y
`estadisticas` no usan S3 en ningún bundle, y `suma_10_15` —el programa que
produjo el compilador NOVA— usa 4 ranuras de 35 disponibles en sus 7 bundles.

El par `suma_simple_emp` y `suma_vliw_emp` mide el tamaño del margen: es el
mismo cálculo escrito de dos formas, y la versión que aprovecha las ranuras
tarda 253 ciclos contra 583, **2,3 veces más rápido**, con una ocupación de
1,06 contra 0,78.

### 5.3 Los delay slots se desperdician casi siempre

En `fibonacci` hay 46 saltos tomados y 46 delay slots vacíos: *todos*. En
`div32_prueba`, 198. Cada uno es un ciclo que el procesador gastó ejecutando un
bundle de puros NOP porque el ISA obliga a ejecutar el bundle que sigue a un
salto.

Son los "ciclos perdidos por saltos" de la tabla 1 del enunciado, en la forma
que toman en este procesador: CERBERO-1 no vacía el pipeline en un salto
—por eso no hay *branch flush* que contar— sino que ejecuta el delay slot pase
lo que pase. El costo no desaparece, cambia de lugar.

### 5.4 Qué significa esto para el proyecto

El enunciado pide analizar cómo interactúan las optimizaciones del compilador
con la jerarquía de caché. La línea base dice que, antes de llegar a la caché,
hay un factor grande disponible solo con llenar los bundles —2,3 veces medido
en el par `suma_simple`/`suma_vliw`, y hasta 5 en el límite del ancho del
bundle— y que ese trabajo le toca al compilador de CE1108 (calendarización estática y empaquetado
de bundles, sección 4 del enunciado) o al empaquetador propio
(`tools/empacar.py`, `make ocupacion`).

Importa para la Iteración 5: un programa con bundles vacíos tiene menos
accesos a memoria por ciclo, así que *esconde* la latencia de la caché y hace
ver mejor cualquier jerarquía. Las comparaciones entre configuraciones de caché
hay que hacerlas con programas bien empaquetados, o el resultado dirá más sobre
los NOP que sobre la caché.

---

## 6. Cómo reproducir todo esto

```bash
cd src/build

make etapas          # las cinco etapas y cada frontera, del Proyecto I
make perf_counters   # los 54 casos de los contadores
make sim             # las 31 unidades del proyecto
make metricas        # corre los programas y arma la tabla de arriba

# un programa suelto, con su informe de métricas al final
make correr PROG=fibonacci.s
```

`make ocupacion` y `make metricas` responden a la misma pregunta desde dos
lados: el primero lee el fuente y dice lo que el programa **trae**; el segundo
corre el procesador y dice lo que **hizo**.

---

## 7. Lo que sigue

| Iteración | Qué agrega | Qué métricas habilita |
| :---: | :--- | :--- |
| 2 | Modelo realista de memoria principal con `T_mem` y eviction buffer | Accesos a memoria, ciclos en transferencias, ancho de banda |
| 3 | Caché L1-D y los stalls del pipeline | Hit/miss de L1-D, ciclos perdidos por miss |
| 4 | Caché L2 y la política de inclusión | Hit/miss de L2, tráfico entre niveles, AMAT |
| 5 | Benchmarks bajo distintos niveles de optimización | La comparación completa contra esta línea base |

El único cambio que la Iteración 3 tiene que hacer en los contadores es
conectar `cache_stall` a la entrada `stall` de `perf_counters` en `top.sv`
(decisión D2).
