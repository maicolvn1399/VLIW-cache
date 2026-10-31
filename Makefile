CC = gcc
LEX_DIR := fase1_lexico
PARSE_DIR := fase2_sintactico
SEM_DIR := fase3_semantico
GEN_DIR := fase4_codigo

BIN := novac
# -MMD -MP genera los .d con las dependencias de encabezados: cambiar un .h
# recompila lo que lo incluye. Sin esto, editar symtab.h dejaba objetos
# compilados contra estructuras distintas.
CFLAGS := -Wall -Wextra -g -MMD -MP -I$(LEX_DIR) -I$(PARSE_DIR) -I$(SEM_DIR) -I$(GEN_DIR)

SRCS = main.c \
       $(LEX_DIR)/diag.c \
       $(PARSE_DIR)/ast.c \
       $(PARSE_DIR)/nova.tab.c \
       $(LEX_DIR)/lex.yy.c \
       $(SEM_DIR)/symtab.c \
       $(SEM_DIR)/semantic.c \
       $(GEN_DIR)/tac.c \
       $(GEN_DIR)/codegen.c

OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS:.o=.d)

.PHONY: all prueba test tabla arbol ensamblador binario paquetes ocupacion entregables generar generar-prueba ejecutar-prueba ejecutar-prueba-rtl prueba-rtl prueba-rtl-simple prueba-rtl-integracion prueba-rtl-objeto prueba-rtl-matriz prueba-rtl-matriz-1000 prueba-rtl-transpuesta prueba-rtl-producto-punto prueba-rtl-multiplicacion prueba-rtl-busqueda prueba-rtl-factorial prueba-rtl-propuesto prueba-rtl-crypto prueba-rtl-cifrado prueba-rtl-descifrado depurar verificar clean limpiar

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

# Asegura que nova.tab.h exista antes de intentar compilar cualquier .o
$(OBJS): $(PARSE_DIR)/nova.tab.h

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(PARSE_DIR)/nova.tab.c $(PARSE_DIR)/nova.tab.h: $(PARSE_DIR)/nova.y
	bison -d -o $(PARSE_DIR)/nova.tab.c $<

$(LEX_DIR)/lex.yy.c: $(LEX_DIR)/nova.l $(PARSE_DIR)/nova.tab.h $(PARSE_DIR)/ast.h $(LEX_DIR)/diag.h
	flex -o $@ $<

prueba test: $(BIN)
	@sh test/run_tests.sh ./$(BIN)

# Vistas rapidas del fuente. Sobrescribir F para elegir otro programa:
#   make arbol F=test/ejecucion/suma_10_15.nv
F ?= test/ejecucion/suma_10_15.nv
SALIDA := .salida
NOMBRE_F := $(basename $(notdir $(F)))
NVX := $(SALIDA)/$(NOMBRE_F).nvx

tabla: $(BIN)
	./$(BIN) --sym "$(F)"

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
	@echo "=== Tabla de simbolos ==="
	./$(BIN) --sym "$(FUENTE_PRUEBA)" > prueba.tabla.txt
	@cat prueba.tabla.txt
	@echo "=== Arbol sintactico ==="
	./$(BIN) -t "$(FUENTE_PRUEBA)" > prueba.ast.txt
	@# A pantalla va directo del compilador, que es donde sale con color; la
	@# copia del archivo queda en texto plano para poder compararla o procesarla.
	@./$(BIN) -t "$(FUENTE_PRUEBA)"
	python3 tools/arbol_svg.py --novac ./$(BIN) --source "$(FUENTE_PRUEBA)" --output prueba.svg
	@echo "=== Codigo intermedio ==="
	./$(BIN) --ir "$(FUENTE_PRUEBA)" > prueba.ir.txt
	@cat prueba.ir.txt
	@echo "=== Ensamblador y ejecutable CERBERO ==="
	./$(BIN) -s "$(FUENTE_PRUEBA)" -o prueba.nvx > /dev/null
	@echo "Ensamblador: prueba.asm"
	@echo "Ejecutable: prueba.nvx ($$(wc -c < prueba.nvx) bytes)"
	./$(BIN) -p "$(FUENTE_PRUEBA)" -o prueba.paquetes.txt
	python3 ARQUITECTURA/tools/novac_image.py prueba.nvx --imem prueba.imem.hex --dmem prueba.dmem.hex
	@echo "Artefactos para CERBERO: prueba.imem.hex y prueba.dmem.hex"

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
	./$(BIN) "$(FUENTE_PRUEBA)" -o prueba.nvx
	python3 ARQUITECTURA/tools/novac_image.py prueba.nvx --imem prueba.imem.hex --dmem prueba.dmem.hex
	@echo "=== Ejecucion de prueba.nv en el procesador CERBERO RTL ==="
	iverilog -g2012 -Wall -Wno-timescale -I "$(CERBERO_CPU)" \
		-DCERBERO_IMEM_FILE="\"$(abspath prueba.imem.hex)\"" \
		-DCERBERO_DMEM_FILE="\"$(abspath prueba.dmem.hex)\"" \
		-s tb_nova_rtl -o .prueba_rtl.vvp \
		"$(CERBERO_CPU)"/*.sv "$(RTL_TB)"
	vvp -n .prueba_rtl.vvp "+EXPECTED=$(RESULTADO_ESPERADO)"

prueba-rtl: prueba-rtl-simple prueba-rtl-integracion prueba-rtl-objeto prueba-rtl-factorial prueba-rtl-busqueda prueba-rtl-propuesto prueba-rtl-matriz prueba-rtl-matriz-1000 prueba-rtl-transpuesta prueba-rtl-producto-punto prueba-rtl-multiplicacion prueba-rtl-crypto

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
todo: test cerbero prueba-rtl
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
	rm -f $(BIN) $(OBJS) $(DEPS) \
	      $(PARSE_DIR)/nova.tab.* $(PARSE_DIR)/nova.output $(LEX_DIR)/lex.yy.c
	rm -f .tmp_nova_sum.nvx .tmp_nova_imem.hex .tmp_nova_dmem.hex .tmp_nova_rtl.vvp
	rm -f .prueba_rtl.vvp
	rm -f .salida/*.nvx .salida/*.asm .salida/*.asm.stdout .salida/*.svg .salida/*.paquetes.txt
	@rmdir .salida 2>/dev/null || true
	rm -f prueba.ast.txt prueba.svg prueba.tabla.txt prueba.ir.txt \
	      prueba.asm prueba.nvx prueba.paquetes.txt prueba.imem.hex prueba.dmem.hex
	@rm -f .tmp_* a.out factorial saludo traza mergesort multiplicacion \
	       bits_y_hex busqueda_matriz desplazamientos operadores matriz \
	       estadistica convolucion rango div_cero boveda cola cifrado descifrado \
	       matriz_1000 matriz_for matriz_transpuesta multiplicar_matrices \
	       producto_punto sin suma_10_15
	rm -f ./*.asm
	@find . -maxdepth 1 -type f -name 'W0[0-9][0-9]_*' ! -name '*.*' -delete 2>/dev/null || true
	@find . -maxdepth 1 -type f -name 'E[0-9][0-9][0-9]_*' ! -name '*.*' -delete 2>/dev/null || true

# clean deja tambien el arbol de CERBERO como viene: sus .vvp, .vcd y los
# .hex que ensambla, que si quedan viejos hacen fallar una simulacion por el
# binario anterior y no por el procesador.
clean: clean-cerbero
.PHONY: clean-cerbero
clean-cerbero:
	@$(MAKE) -C ARQUITECTURA/src/build clean 2>/dev/null || true

limpiar: clean

-include $(DEPS)
