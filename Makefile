CC = gcc
LEX_DIR := fase1_lexico
PARSE_DIR := fase2_sintactico
SEM_DIR := fase3_semantico
GEN_DIR := fase4_codigo

OPT_DIR := fase6_optimizacion
IDE_DIR := fase5_ide

BIN := novac
IDE_BIN := novaide
# -MMD -MP genera los .d con las dependencias de encabezados: cambiar un .h
# recompila lo que lo incluye. Sin esto, editar symtab.h dejaba objetos
# compilados contra estructuras distintas.
CFLAGS := -Wall -Wextra -g -MMD -MP -I$(LEX_DIR) -I$(PARSE_DIR) -I$(SEM_DIR) -I$(GEN_DIR) -I$(OPT_DIR) -I$(IDE_DIR)

SRCS = main.c \
       $(LEX_DIR)/diag.c \
       $(PARSE_DIR)/ast.c \
       $(PARSE_DIR)/enlace.c \
       $(PARSE_DIR)/nova.tab.c \
       $(LEX_DIR)/lex.yy.c \
       $(SEM_DIR)/symtab.c \
       $(SEM_DIR)/semantic.c \
       $(GEN_DIR)/tac.c \
       $(GEN_DIR)/codegen.c \
       $(OPT_DIR)/bloques.c \
       $(OPT_DIR)/vivacidad.c \
       $(OPT_DIR)/muerto.c \
       $(OPT_DIR)/desenrollado.c

OBJS = $(SRCS:.c=.o)

# El IDE comparte con el compilador las fases 1 a 4: las mismas unidades, no
# una copia. Por eso novaide enlaza $(NUCLEO_OBJS), que es $(OBJS) sin main.o.
# Lo que el editor marca sale literalmente del mismo analizador que compila.
NUCLEO_OBJS = $(filter-out main.o,$(OBJS))

IDE_SRCS = $(IDE_DIR)/novaide.c \
           $(IDE_DIR)/jsonw.c \
           $(IDE_DIR)/ide_util.c \
           $(IDE_DIR)/ide_lex.c \
           $(IDE_DIR)/ide_catalogo.c \
           $(IDE_DIR)/ide_diag.c \
           $(IDE_DIR)/ide_completar.c \
           $(IDE_DIR)/ide_arreglar.c \
           $(IDE_DIR)/ide_clones.c \
           $(IDE_DIR)/ide_bloques.c

IDE_OBJS = $(IDE_SRCS:.c=.o)
DEPS = $(OBJS:.o=.d) $(IDE_OBJS:.o=.d)

.PHONY: test prueba prueba-unidad prueba-ciclos

all: $(BIN) $(IDE_BIN)

$(BIN): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

$(IDE_BIN): $(IDE_OBJS) $(NUCLEO_OBJS)
	$(CC) $(CFLAGS) -o $@ $(IDE_OBJS) $(NUCLEO_OBJS)

# Asegura que nova.tab.h exista antes de intentar compilar cualquier .o
$(OBJS) $(IDE_OBJS): $(PARSE_DIR)/nova.tab.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(PARSE_DIR)/nova.tab.c: $(PARSE_DIR)/nova.y
	bison -d -o $(PARSE_DIR)/nova.tab.c $<

# Bison genera el encabezado como salida secundaria. Hacer que dependa del .c
# serializa ambas salidas incluso con make -j; solo vuelve a invocar Bison si
# falta el encabezado, por ejemplo tras una limpieza parcial.
$(PARSE_DIR)/nova.tab.h: $(PARSE_DIR)/nova.tab.c
	@test -f $@ || bison -d -o $(PARSE_DIR)/nova.tab.c $(PARSE_DIR)/nova.y

$(LEX_DIR)/lex.yy.c: $(LEX_DIR)/nova.l $(PARSE_DIR)/nova.tab.h $(PARSE_DIR)/ast.h $(LEX_DIR)/diag.h
	flex -o $@ $<

# ---------------------------------------------------------------- IDE
#
# 'make ide' levanta la interfaz; la logica ya esta compilada en novaide, que
# se construye junto al compilador porque comparten las fases 1 a 4.
ide: $(BIN) $(IDE_BIN)
	python3 ide/servidor.py

# Las pruebas del IDE corren contra el binario, no contra la interfaz: lo que
# hay que garantizar es el comportamiento de la logica en C.
prueba-ide: $(BIN) $(IDE_BIN)
	@PYTHONDONTWRITEBYTECODE=1 python3 test/ide/correr_pruebas.py

prueba test: $(BIN)
	@sh test/run_tests.sh ./$(BIN)

prueba-unidad: test

# Vistas rapidas del fuente. Sobrescribir F para elegir otro programa:
#   make arbol F=test/ejecucion/suma_10_15.nv
F ?= test/ejecucion/suma_10_15.nv
SALIDA := .salida
NOMBRE_F := $(basename $(notdir $(F)))
NVX := $(SALIDA)/$(NOMBRE_F).nvx

tabla: $(BIN)
	./$(BIN) --sym "$(F)"

# Fase 6. 'make vivacidad F=archivo.nv' muestra los conjuntos del analisis;
# 'make metricas F=archivo.nv' pone lado a lado lo que cuesta optimizar y lo
# que se gana, que es el intercambio que hay que poder explicar.
vivacidad: $(BIN)
	./$(BIN) --vivacidad "$(F)"

asignacion: $(BIN)
	./$(BIN) --asignacion "$(F)"

metricas: $(BIN)
	@mkdir -p "$(SALIDA)"
	@echo "=============== SIN OPTIMIZAR ==============="
	@./$(BIN) --metricas "$(F)" -o "$(SALIDA)/$(NOMBRE_F).O0.nvx"
	@echo
	@echo "=============== CON -O1 ====================="
	@./$(BIN) --metricas -O1 "$(F)" -o "$(SALIDA)/$(NOMBRE_F).O1.nvx"
	@echo
	@echo "=============== CON -O2 ====================="
	@./$(BIN) --metricas -O2 "$(F)" -o "$(SALIDA)/$(NOMBRE_F).O2.nvx"

arbol: $(BIN) tools/arbol_svg.py
	@mkdir -p "$(SALIDA)"
	@# Primero el arbol en la terminal, con conectores y color, y despues el SVG
	@# para abrir en el navegador. Los dos usan los mismos grupos de color.
	@./$(BIN) -t "$(F)"
	@echo
	python3 tools/arbol_svg.py --novac ./$(BIN) --source "$(F)" --output "$(SALIDA)/$(NOMBRE_F).svg"

ensamblador: $(BIN)
	@mkdir -p "$(SALIDA)"
	@./$(BIN) -s "$(F)" -o "$(NVX)" > "$(SALIDA)/$(NOMBRE_F).asm.stdout"
	@echo "Ensamblador: $(SALIDA)/$(NOMBRE_F).asm"

binario: $(BIN)
	@mkdir -p "$(SALIDA)"
	./$(BIN) "$(F)" -o "$(NVX)"
	@echo "Ejecutable: $(NVX)"

# Los artefactos de la seccion 10 de la guia: ensamblador y binario de los tres
# ejercicios, mas la evidencia de ejecucion.
entregables: $(BIN) tools/entregables.sh
	@sh tools/entregables.sh ./$(BIN)

# Cuanto del bundle se usa realmente: la medida de lo que falta de la fase 5.
ocupacion: $(BIN) tools/ocupacion.py
	@python3 tools/ocupacion.py ./$(BIN)

paquetes: $(BIN)
	@mkdir -p "$(SALIDA)"
	./$(BIN) -p "$(F)" -o "$(SALIDA)/$(NOMBRE_F).paquetes.txt"
	@echo "Listado de bundles: $(SALIDA)/$(NOMBRE_F).paquetes.txt"

# Genera las salidas de prueba.nv en la raiz, incluidas las imagenes
# de memoria que CERBERO carga con $readmemh. Sobrescribir la fuente al probar:
#   make generar
#   make generar FUENTE_PRUEBA=test/ejecucion/suma_10_15.nv
FUENTE_PRUEBA ?= prueba.nv

generar generar-prueba: $(BIN) tools/arbol_svg.py ARQUITECTURA/tools/novac_image.py
	@test -s "$(FUENTE_PRUEBA)" || { echo "Error: $(FUENTE_PRUEBA) no existe o esta vacio." >&2; exit 1; }
	@mkdir -p "$(SALIDA)"
	@echo "=== Tabla de simbolos ==="
	./$(BIN) --sym "$(FUENTE_PRUEBA)" > "$(SALIDA)/prueba.tabla.txt"
	@cat "$(SALIDA)/prueba.tabla.txt"
	@echo "=== Arbol sintactico ==="
	./$(BIN) -t "$(FUENTE_PRUEBA)" > "$(SALIDA)/prueba.ast.txt"
	@# A pantalla va directo del compilador, que es donde sale con color; la
	@# copia del archivo queda en texto plano para poder compararla o procesarla.
	@./$(BIN) -t "$(FUENTE_PRUEBA)"
	python3 tools/arbol_svg.py --novac ./$(BIN) --source "$(FUENTE_PRUEBA)" --output "$(SALIDA)/prueba.svg"
	@echo "=== Codigo intermedio ==="
	./$(BIN) --ir "$(FUENTE_PRUEBA)" > "$(SALIDA)/prueba.ir.txt"
	@cat "$(SALIDA)/prueba.ir.txt"
	@echo "=== Ensamblador y ejecutable CERBERO ==="
	./$(BIN) -s "$(FUENTE_PRUEBA)" -o "$(SALIDA)/prueba.nvx" > /dev/null
	@echo "Ensamblador: $(SALIDA)/prueba.asm"
	@echo "Ejecutable: $(SALIDA)/prueba.nvx ($$(wc -c < "$(SALIDA)/prueba.nvx") bytes)"
	./$(BIN) -p "$(FUENTE_PRUEBA)" -o "$(SALIDA)/prueba.paquetes.txt"
	python3 ARQUITECTURA/tools/novac_image.py "$(SALIDA)/prueba.nvx" \
		--imem "$(SALIDA)/prueba.imem.hex" --dmem "$(SALIDA)/prueba.dmem.hex"
	@echo "Artefactos para CERBERO: $(SALIDA)/prueba.imem.hex y $(SALIDA)/prueba.dmem.hex"

# Compila y ejecuta un binario Nova sobre el RTL real de CERBERO.
CERBERO_CPU ?= $(if $(wildcard ARQUITECTURA/src/cpu),ARQUITECTURA/src/cpu,../src/cpu)
RTL_TB := test/tb_nova_rtl.sv
RTL_SRCS := $(wildcard $(CERBERO_CPU)/*.sv)
RTL_IMEM := $(abspath .tmp_nova_imem.hex)
RTL_DMEM := $(abspath .tmp_nova_dmem.hex)
RTL_EXE := $(abspath .tmp_nova_sum.nvx)
RTL_VVP := .tmp_nova_rtl.vvp

# Ejecuta prueba.nv en el RTL y muestra ciclos y retorno en R6.
# El programa actual calcula 6! y su resultado esperado es 720.
# Si cambia el programa, indicar su retorno esperado con RESULTADO_ESPERADO.
RESULTADO_ESPERADO ?= 720
ejecutar-prueba ejecutar-prueba-rtl: $(BIN) $(RTL_TB) $(RTL_SRCS) ARQUITECTURA/tools/novac_image.py
	@test -s "$(FUENTE_PRUEBA)" || { echo "Error: $(FUENTE_PRUEBA) no existe o esta vacio." >&2; exit 1; }
	@mkdir -p "$(SALIDA)"
	./$(BIN) "$(FUENTE_PRUEBA)" -o "$(SALIDA)/prueba.nvx"
	python3 ARQUITECTURA/tools/novac_image.py "$(SALIDA)/prueba.nvx" \
		--imem "$(SALIDA)/prueba.imem.hex" --dmem "$(SALIDA)/prueba.dmem.hex"
	@echo "=== Ejecucion de prueba.nv en el procesador CERBERO RTL ==="
	iverilog -g2012 -Wall -Wno-timescale -I "$(CERBERO_CPU)" \
		-DCERBERO_IMEM_FILE="\"$(abspath $(SALIDA)/prueba.imem.hex)\"" \
		-DCERBERO_DMEM_FILE="\"$(abspath $(SALIDA)/prueba.dmem.hex)\"" \
		-s tb_nova_rtl -o "$(SALIDA)/prueba_rtl.vvp" \
		"$(CERBERO_CPU)"/*.sv "$(RTL_TB)"
	vvp -n "$(SALIDA)/prueba_rtl.vvp" "+EXPECTED=$(RESULTADO_ESPERADO)"

# Banderas con las que run_rtl_test.sh invoca al compilador. Vacias por
# omision; 'make prueba-rtl OPT=-O1' corre la misma bateria con la fase 6
# encendida. Se exporta porque el script la lee del entorno.
OPT ?=
export OPT

metricas-rtl: $(BIN) $(RTL_TB) $(RTL_SRCS) test/optimizaciones/medir_niveles.sh
	sh test/optimizaciones/medir_niveles.sh ./$(BIN) "$(CERBERO_CPU)" \
		"$(FUENTE_PRUEBA)" "$(RESULTADO_ESPERADO)"

prueba-rtl: prueba-rtl-simple prueba-rtl-integracion prueba-rtl-objeto prueba-rtl-factorial prueba-rtl-busqueda prueba-rtl-propuesto prueba-rtl-matriz prueba-rtl-matriz-1000 prueba-rtl-transpuesta prueba-rtl-producto-punto prueba-rtl-multiplicacion prueba-rtl-multiplicacion-ejemplo prueba-rtl-convolucion prueba-rtl-crypto prueba-rtl-cola prueba-rtl-boveda prueba-rtl-rango prueba-rtl-div-cero prueba-rtl-bits prueba-rtl-operadores prueba-rtl-traza prueba-rtl-desplazamientos prueba-rtl-profesor prueba-rtl-unrolling

prueba-rtl-unrolling: $(BIN) $(RTL_TB) $(RTL_SRCS) test/optimizaciones/run_rtl.sh
	sh test/optimizaciones/run_rtl.sh ./$(BIN) "$(CERBERO_CPU)"

# La prueba de que optimizar no cambia el programa: la misma bateria, los
# mismos valores de retorno esperados, compilando con -O1. Si una sola cambia
# de resultado, la fase 6 esta rota.
prueba-rtl-optimizado:
	$(MAKE) prueba-rtl OPT=-O1

prueba-rtl-simple: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/suma_10_15.nv 25 "$(CERBERO_CPU)"

prueba-rtl-integracion: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/integracion/integracion.nv 175 "$(CERBERO_CPU)"

prueba-rtl-objeto: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/integracion/integracion_objeto.nv 175 "$(CERBERO_CPU)" test/integracion/calculos.nv

prueba-rtl-matriz: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/matriz_for.nv 138 "$(CERBERO_CPU)"

prueba-rtl-matriz-1000: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/matriz_1000.nv 5000 "$(CERBERO_CPU)" "" "" 500000

prueba-rtl-transpuesta: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/matriz_transpuesta.nv 2122 "$(CERBERO_CPU)"

prueba-rtl-producto-punto: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/producto_punto.nv 182 "$(CERBERO_CPU)"

prueba-rtl-multiplicacion: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/multiplicar_matrices.nv 415 "$(CERBERO_CPU)"

prueba-rtl-multiplicacion-ejemplo: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/multiplicacion.nv 0 "$(CERBERO_CPU)" "" "" 20000 "58,64,0,10,139,154,0,10"

prueba-rtl-convolucion: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/convolucion.nv 0 "$(CERBERO_CPU)" "" "" 500000 "10,1970496882,1684108396,14959,10,10,-30,-30,-30,10,0,10,-30,130,50,130,-30,0,10,-30,50,250,50,-30,0,10,-30,130,50,130,-30,0,10,10,-30,-30,-30,10,0,10,10,1836020336,1869177957,15648,26,10,8,1769496941,1025535853,250,10"

prueba-rtl-factorial: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/factorial.nv 120 "$(CERBERO_CPU)"

prueba-rtl-busqueda: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/busqueda_matriz.nv 12 "$(CERBERO_CPU)"

prueba-rtl-propuesto: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/mergesort.nv 192 "$(CERBERO_CPU)"

prueba-rtl-cifrado: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/cifrado.nv 0 "$(CERBERO_CPU)" "" "128'h0000_0000_0000_0000_0000_0000_7654_3210"

prueba-rtl-descifrado: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/descifrado.nv 0 "$(CERBERO_CPU)" "" "128'h0000_0000_0000_0000_0000_0000_7654_3210"

prueba-rtl-crypto: prueba-rtl-cifrado prueba-rtl-descifrado

prueba-rtl-cola: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/cola.nv 0 "$(CERBERO_CPU)" "" "" 100000 "125250"

prueba-rtl-boveda: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/boveda.nv 137 "$(CERBERO_CPU)" "" "" 20000 ""

prueba-rtl-rango: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/rango.nv 134 "$(CERBERO_CPU)" "" "" 20000 ""

prueba-rtl-div-cero: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejecucion/div_cero.nv 136 "$(CERBERO_CPU)" "" "" 20000 ""

prueba-rtl-bits: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/bits_y_hex.nv -65419 "$(CERBERO_CPU)" "" "" 20000 ""

prueba-rtl-operadores: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/operadores.nv 0 "$(CERBERO_CPU)" "" "" 50000 "8,1634166126,1870031220,10,4,15,-16,3"

prueba-rtl-traza: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/traza.nv 0 "$(CERBERO_CPU)" "" "" 20000 "15"

prueba-rtl-desplazamientos: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) test/ejemplos/desplazamientos.nv 0 "$(CERBERO_CPU)" "" "" 20000 "3840,15,-16,268435440"

prueba-rtl-profesor: prueba-rtl-test1 prueba-rtl-test2-demo prueba-rtl-test3 prueba-rtl-test4 prueba-rtl-test5 prueba-rtl-test6

prueba-rtl-test1: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test1.nv 28 "$(CERBERO_CPU)" "" "" 50000 "28"

prueba-rtl-test2-demo: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test2_demo.nv 65 "$(CERBERO_CPU)" "" "" 50000 "65"

prueba-rtl-test3: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test3.nv 110 "$(CERBERO_CPU)" "" "" 50000 "100,10"

prueba-rtl-test4: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test4.nv 21 "$(CERBERO_CPU)" "" "" 50000 "1,4,2,5,3,6"

prueba-rtl-test5: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test5.nv 134 "$(CERBERO_CPU)" "" "" 50000 "19,22,43,50"

prueba-rtl-test6: $(BIN) $(RTL_TB) $(RTL_SRCS)
	sh test/run_rtl_test.sh ./$(BIN) pruebas_profesor/Test6.nv 55 "$(CERBERO_CPU)" "" "" 50000 "55"

prueba-rtl-equivalencia: $(BIN) $(RTL_TB) $(RTL_SRCS) test/run_equivalencia.sh
	sh test/run_equivalencia.sh ./$(BIN) "$(CERBERO_CPU)"

# Iteracion 5: la misma bateria, recogiendo los contadores de cada corrida, y
# despues las tablas. El directorio es un parametro para poder guardar una
# medicion y compararla con otra.
#
# Es especifico de este objetivo: `prueba-rtl-equivalencia` a secas no debe
# escribir nada, para que la prueba de siempre siga siendo la prueba de siempre.
METRICAS_DIR ?= medicion
medir-niveles: export METRICAS_DIR := $(METRICAS_DIR)

medir-niveles: $(BIN) $(RTL_TB) $(RTL_SRCS) test/run_equivalencia.sh
	sh test/run_equivalencia.sh ./$(BIN) "$(CERBERO_CPU)"
	python3 tools/tabla_niveles.py "$(METRICAS_DIR)"

tabla-niveles:
	python3 tools/tabla_niveles.py "$(METRICAS_DIR)"

prueba-ciclos: $(BIN) $(RTL_TB) $(RTL_SRCS) test/optimizaciones/comparar_ciclos.sh
	sh test/optimizaciones/comparar_ciclos.sh ./$(BIN) "$(CERBERO_CPU)"

# Depuracion por partes. Sin argumento corre todo; con F se elige el objetivo:
#   make depurar
#   make depurar F=fase3
depurar: $(BIN)
	@sh tools/depurar.sh "$(F)"

# Informe completo de verificacion. Con B se corre un solo bloque:
#   make verificar
#   make verificar B=6
verificar: $(BIN)
	@sh tools/verificar.sh "$(B)"

# -----------------------------------------------------------------------------
# Los dos proyectos de una sola corrida
# -----------------------------------------------------------------------------
# CE1108 entrega el compilador y CE4301 el procesador, pero el entregable de
# verdad es la cadena entera: un programa en NOVA que termina ejecutandose en
# el RTL. Este objetivo la recorre completa, de los dos lados:
#
#   1. las pruebas del compilador            test/run_tests.sh
#   2. la suite completa de CERBERO          ARQUITECTURA/src/build
#   3. la integracion, que es lo unico que
#      toca los dos proyectos a la vez       prueba-rtl
#
# Cualquiera de las tres que falle detiene el make, asi que si esto termina
# bien, los dos proyectos estan de acuerdo.
.PHONY: todo cerbero
todo: test prueba-ide cerbero prueba-rtl prueba-rtl-equivalencia
	@echo ""
	@echo "=============================================================="
	@echo " Compilador NOVA y procesador CERBERO: la cadena completa paso"
	@echo "=============================================================="

# La suite de CERBERO, con su propio makefile. El lint va primero porque
# Verilator ve cosas que Icarus deja pasar.
cerbero:
	@echo ""
	@echo "######## CERBERO: analisis estatico y suite completa ########"
	$(MAKE) -C ARQUITECTURA/src/build lint
	$(MAKE) -C ARQUITECTURA/src/build

# Deja el arbol como viene del repositorio: solo fuentes. Los .o, los .d, lo
# que generan bison y flex, el ejecutable del compilador y cualquier
# ejecutable de CERBERO que haya quedado de una corrida manual.
clean:
	rm -f $(BIN) $(IDE_BIN) $(OBJS) $(IDE_OBJS) $(DEPS) \
	      $(PARSE_DIR)/nova.tab.* $(PARSE_DIR)/nova.output $(LEX_DIR)/lex.yy.c
	rm -f test/ide/.arreglando.nv test/ide/.muchos_errores.nv test/.hex.tmp.nv
	rm -f .tmp_nova_sum.nvx .tmp_nova_imem.hex .tmp_nova_dmem.hex .tmp_nova_rtl.vvp
	rm -f .prueba_rtl.vvp
	rm -f .salida/*.nvx .salida/*.asm .salida/*.asm.stdout .salida/*.svg \
	      .salida/*.paquetes.txt .salida/*.hex .salida/*.vvp \
	      .salida/*.ir.txt .salida/*.tabla.txt .salida/*.ast.txt
	@rmdir .salida 2>/dev/null || true
	rm -f prueba.ast.txt prueba.svg prueba.tabla.txt prueba.ir.txt \
	      prueba.asm prueba.nvx prueba.paquetes.txt prueba.imem.hex prueba.dmem.hex
	@rm -f .tmp_* a.out factorial saludo traza mergesort multiplicacion \
	       bits_y_hex busqueda_matriz desplazamientos operadores matriz \
	       estadistica convolucion rango div_cero boveda cola cifrado descifrado \
	       matriz_1000 matriz_for matriz_transpuesta multiplicar_matrices \
	       producto_punto sin suma_10_15 prueba
	rm -f asignacion_cripto asignacion_division asignacion_presion dce_ciclo_scribe \
	      muchos_temporales nova_shift_temporales_08a8134067014a6c8fb4d61de2eda9ea \
	      nova_temporales_44c4fccd0527433eb80c61c682b99ed7 \
	      nova_w009_scheduler nova_w009_scheduler_single propagacion_scribe \
	      renombramiento_llamada renombramiento_war renombramiento_waw \
	      reordenamiento_anidado reordenamiento_ciclo reordenamiento_condicional \
	      t2_ciclo_muerto t2_propagacion t3_reorden_flags Test1 \
	      unroll_anidado unroll_constante unroll_grande unroll_variable_400 \
	      unroll_variable_pequena
	rm -f ./*.asm
	@find . -maxdepth 1 -type f -name 'W0[0-9][0-9]_*' ! -name '*.*' -delete 2>/dev/null || true
	@find . -maxdepth 1 -type f -name 'E[0-9][0-9][0-9]_*' ! -name '*.*' -delete 2>/dev/null || true
	@find . -path ./ARQUITECTURA -prune -o -type d -name __pycache__ \
		-prune -exec rm -rf {} + 2>/dev/null || true

# clean deja tambien el arbol de CERBERO como viene: sus .vvp, .vcd y los
# .hex que ensambla, que si quedan viejos hacen fallar una simulacion por el
# binario anterior y no por el procesador.
clean: clean-cerbero
.PHONY: clean-cerbero
clean-cerbero:
	@$(MAKE) -C ARQUITECTURA/src/build clean 2>/dev/null || true

limpiar: clean

-include $(DEPS)
