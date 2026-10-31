# =============================================================================
# makefile - CERBERO-1 (Icarus Verilog + Verilator)
# CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
#
# Se ejecuta desde src/build:
#
#   make                -> corre todos los testbenches de ../tb (make sim)
#   make key_vault      -> corre solo tb_key_vault.sv
#   make wave-key_vault -> abre tb_key_vault.vcd en GTKWave
#   make lint           -> analisis estatico de todas las unidades
#   make lint-lsu       -> analisis estatico de una unidad
#   make list           -> lista las unidades con testbench
#   make clean          -> borra .vvp y .vcd
#
# Convencion (para que funcione sin tocar este archivo):
#   - Modulo:     ../cpu/<unidad>.sv        (ej. ../cpu/alu.sv)
#   - Testbench:  ../tb/tb_<unidad>.sv      (ej. ../tb/tb_alu.sv, modulo tb_alu)
#   - Paquetes compartidos: ../cpu/*_pkg.sv  (se compilan primero en todos)
#   - Si un modulo instancia otros, declarar sus dependencias abajo:
#         DEPS_crypto_unit := $(CPU)/key_vault.sv
#
# Un testbench que encuentra un error llama a $fatal, lo que le da a vvp un
# codigo de salida distinto de cero y detiene el make. "make sim" que termina
# bien significa que todas las unidades pasaron, no solo que corrieron.
# =============================================================================

IVERILOG  ?= iverilog
VVP       ?= vvp
GTKWAVE   ?= gtkwave
VERILATOR ?= verilator

# Programa y datos para "make top". Opcionales: sin ellos las memorias arrancan
# vacias y el testbench las carga por referencia jerarquica.
#   make top IMEM=../tb/programa.hex DMEM=../tb/datos.hex
IMEM ?=
DMEM ?=
INIT_DEFS :=
ifneq ($(IMEM),)
INIT_DEFS += -DCERBERO_IMEM_FILE='"$(IMEM)"'
endif
ifneq ($(DMEM),)
INIT_DEFS += -DCERBERO_DMEM_FILE='"$(DMEM)"'
endif

FLAGS      := -g2012 -Wall -Wno-timescale -I ../cpu $(INIT_DEFS)
LINT_FLAGS := --lint-only -Wall -I../cpu

CPU   := ../cpu
TB    := ../tb
TOOLS := ../../tools
PROGS := $(TOOLS)/programas
ASM   := python3 $(TOOLS)/cerbero_asm.py

PKGS  := $(wildcard $(CPU)/*_pkg.sv)
# tb_descifrado necesita un archivo cifrado de entrada, asi que no entra en
# "make sim": se corre con "make solo-descifrar".
UNITS := $(filter-out descifrado programa,$(patsubst $(TB)/tb_%.sv,%,$(wildcard $(TB)/tb_*.sv)))

# Unidades con modulo propio en ../cpu. Se excluyen los testbenches de
# integracion, que no tienen un ../cpu/<nombre>.sv detras.
RTL_UNITS := $(patsubst $(CPU)/%.sv,%,$(wildcard $(CPU)/*.sv))

# ---- Submodulos RTL por unidad ----------------------------------------------
# Modulos de ../cpu que otra unidad instancia. Se compilan junto a ella Y se
# analizan junto a ella, que es la diferencia con DEPS_: esas son dependencias
# del testbench, no del modulo.
SUB_lsu := $(CPU)/load_align.sv
SUB_top := $(filter-out $(CPU)/top.sv,$(wildcard $(CPU)/*.sv))

# ---- Dependencias extra por unidad (agregar aqui) ---------------------------
DEPS_crypto_unit  := $(TB)/key_vault_model.sv
DEPS_crypto_vault := $(CPU)/crypto_unit.sv $(CPU)/key_vault.sv
DEPS_latency      := $(CPU)/regfile.sv
DEPS_wconf        := $(CPU)/psw_fault_unit.sv $(CPU)/regfile.sv
DEPS_pipeline     := $(CPU)/reg_if_id.sv $(CPU)/reg_id_ex.sv \
                     $(CPU)/reg_ex_mem.sv $(CPU)/regfile.sv
DEPS_fetch_flow   := $(CPU)/fetch.sv $(CPU)/imem.sv $(CPU)/reg_if_id.sv \
                     $(CPU)/bru.sv
# tb_asm carga el binario que produce el ensamblador, asi que depende del .hex
DEPS_asm          := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/feistel.hex $(PROGS)/feistel_datos.hex
DEPS_div          := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/div32_prueba.hex $(PROGS)/div32_prueba_datos.hex
# tb_archivo carga tres imagenes por referencia jerarquica, no por macro: son
# dos programas distintos en una misma simulacion y las macros son globales.
DEPS_archivo      := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/cifrar_archivo.hex \
                     $(PROGS)/descifrar_archivo.hex \
                     $(PROGS)/archivo_prueba.hex
# tb_cifrado carga los mismos dos programas; la imagen del archivo la lee en
# tiempo de simulacion, asi que va como requisito de la corrida, no de aqui
DEPS_cifrado      := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/cifrar_archivo.hex \
                     $(PROGS)/descifrar_archivo.hex
# tb_descifrado carga el contenedor en tiempo de simulacion, igual que
# tb_cifrado carga el archivo
DEPS_descifrado   := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/descifrar_archivo.hex
# tb_programa carga en tiempo de simulacion el programa que se le indique
DEPS_programa     := $(wildcard $(CPU)/*.sv)
# tb_credencial corre cifrar_archivo sobre un procesador con otro ROT_SECRET
DEPS_credencial   := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/cifrar_archivo.hex \
                     $(PROGS)/archivo_prueba.hex
# tb_ejemplos monta tres procesadores, uno por programa de demostracion, y
# compara lo que dejan contra los valores de sus cabeceras
DEPS_ejemplos     := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/fibonacci.hex \
                     $(PROGS)/estadisticas.hex \
                     $(PROGS)/sesion_sin_logout.hex \
                     $(PROGS)/contar_hasta_n.hex
# tb_logout responde a una pregunta concreta -- si la boveda queda abierta
# cuando el programa no hace LOGOUT -- y por eso tiene nombre propio en vez de
# vivir dentro de tb_ejemplos: una propiedad de seguridad que no se puede
# enseñar en un comando no esta demostrada para quien viene a preguntarla.
DEPS_logout       := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/sesion_sin_logout.hex
# tb_vliw mide el mismo calculo escrito con y sin trabajo independiente. Los
# dos programas pasan por el empaquetador antes de ensamblarse.
DEPS_vliw         := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/suma_simple_emp.hex \
                     $(PROGS)/suma_vliw_emp.hex
# tb_sum corre el programa que produjo el compilador NOVA de CE1108, para
# comprobar que su generador de codigo y este procesador siguen de acuerdo
DEPS_sum          := $(wildcard $(CPU)/*.sv) \
                     $(PROGS)/suma_10_15.hex $(PROGS)/suma_10_15_datos.hex

# ---- Opciones de compilacion por unidad -------------------------------------
# tb_asm es el unico testbench que no arma su programa adentro: el .hex entra
# por macro, porque Icarus no puede pasar un parametro string a un submodulo.
XFLAGS_asm := -DCERBERO_IMEM_FILE='"$(PROGS)/feistel.hex"' \
              -DCERBERO_DMEM_FILE='"$(PROGS)/feistel_datos.hex"'
XFLAGS_div := -DCERBERO_IMEM_FILE='"$(PROGS)/div32_prueba.hex"' \
              -DCERBERO_DMEM_FILE='"$(PROGS)/div32_prueba_datos.hex"'
XFLAGS_sum := -DCERBERO_IMEM_FILE='"$(PROGS)/suma_10_15.hex"' \
              -DCERBERO_DMEM_FILE='"$(PROGS)/suma_10_15_datos.hex"'

# ---- Unidades sin modulo propio (testbenches de integracion) ----------------
# Para estas, la receta no antepone $(CPU)/<unidad>.sv
NO_RTL := crypto_vault latency wconf pipeline fetch_flow asm div archivo cifrado \
          logout vliw \
          credencial descifrado programa ejemplos sum

# Objetivos derivados. Se nombran en variables porque las reglas de abajo son
# ESTATICAS y no implicitas: make omite la busqueda de reglas implicitas para
# los objetivos declarados .PHONY, asi que una regla de patron normal como
# "lint-%:" nunca llegaria a ejecutarse y el objetivo pasaria sin hacer nada.
LINT_TARGETS := $(addprefix lint-,$(RTL_UNITS))
WAVE_TARGETS := $(addprefix wave-,$(UNITS))

.PHONY: all sim list clean lint $(UNITS) $(WAVE_TARGETS) $(LINT_TARGETS)

all: herramientas sim flujo

# ---- Pruebas de las herramientas en Python ----------------------------------
# El ensamblador tiene su propio arnes, con el mismo formato de salida que los
# del RTL. Incluye la comprobacion de que programas/cobertura.s usa el 100% del
# conjunto de instrucciones, que es lo que pide el enunciado.
.PHONY: herramientas
herramientas:
	@echo ""
	@echo "---- pruebas del ensamblador ----"
	python3 $(TOOLS)/probar_asm.py
	@echo ""
	@echo "---- pruebas de load_file y extract_data ----"
	python3 $(TOOLS)/probar_archivos.py
	@echo ""
	@echo "---- pruebas de llave.py ----"
	python3 $(TOOLS)/probar_llave.py

sim: $(UNITS)
	@echo ""
	@echo "=============================================================="
	@echo " Todas las unidades pasaron"
	@echo "=============================================================="

list:
	@echo "Unidades con testbench: $(UNITS)"
	@echo "Modulos RTL:            $(RTL_UNITS)"

# make <unidad>: compila y ejecuta su testbench
$(UNITS): %: tb_%.vvp
	@echo ""
	@echo "---- $* ----"
	$(VVP) -n $< +VCD=tb_$*.vcd $(PLUS_$*)

# Compilacion: paquetes + modulo + dependencias + testbench
.SECONDARY:
.SECONDEXPANSION:
tb_%.vvp: $$(PKGS) $$(if $$(filter $$*,$$(NO_RTL)),,$(CPU)/%.sv) $$(SUB_$$*) $$(DEPS_$$*) $(TB)/tb_%.sv
	$(IVERILOG) $(FLAGS) $(XFLAGS_$*) -s tb_$* -o $@ $(filter %.sv,$^)

# ---- Ensamblado de programas -------------------------------------------------
# Un .s produce los dos .hex de una pasada.
#
# El relleno tiene que coincidir EXACTAMENTE con el tamano de las memorias del
# testbench que va a cargar el binario. Icarus avisa en los dos sentidos:
# "Not enough words" si el archivo es mas corto que la memoria y "Too many
# words" si es mas largo. Ninguno de los dos rompe la simulacion, pero el ruido
# tapa los avisos que si importan, asi que cada programa declara su tamano.
BUNDLES_feistel      := 2048
PALABRAS_feistel     := 64
BUNDLES_div32_prueba := 128
PALABRAS_div32_prueba := 64
BUNDLES_cifrar_archivo    := 2048
BUNDLES_descifrar_archivo := 2048
# tb_ejemplos carga el .data de estadisticas.s en una dmem de 16384 palabras
PALABRAS_estadisticas := 16384
# Los dos programas de la demostracion VLIW llevan su vector en .data
PALABRAS_suma_simple_emp := 16384
PALABRAS_suma_vliw_emp   := 16384
PALABRAS_contar_hasta_n  := 16384
# tb_sum instancia memorias chicas: 64 bundles y 16 palabras
BUNDLES_suma_10_15  := 64
PALABRAS_suma_10_15 := 16

# Un programa que termina en _emp lo produce el empaquetador a partir del
# que tiene el mismo nombre sin el sufijo. Es la fase de planificacion VLIW:
# el fuente se escribe una operacion por bundle y la herramienta las junta.
$(PROGS)/%_emp.s: $(PROGS)/%.s $(TOOLS)/empacar.py $(CPU)/cerbero_defs.svh
	python3 $(TOOLS)/empacar.py $< -o $@

$(PROGS)/%.hex $(PROGS)/%_datos.hex: $(PROGS)/%.s $(CPU)/cerbero_defs.svh
	$(ASM) $< -o $(PROGS)/$*.hex --datos $(PROGS)/$*_datos.hex \
	       --bundles $(or $(BUNDLES_$*),2048) \
	       --palabras $(or $(PALABRAS_$*),64)

.PHONY: programas cobertura
programas: $(PROGS)/feistel.hex $(PROGS)/div32_prueba.hex \
           $(PROGS)/cifrar_archivo.hex $(PROGS)/descifrar_archivo.hex \
           $(PROGS)/archivo_prueba.hex $(PROGS)/fibonacci.hex \
           $(PROGS)/estadisticas.hex $(PROGS)/sesion_sin_logout.hex \
           $(PROGS)/suma_10_15.hex

# Los dos programas de archivo incluyen los mismos dos fragmentos
$(PROGS)/cifrar_archivo.hex $(PROGS)/descifrar_archivo.hex: \
	$(PROGS)/cargar_llave.s $(PROGS)/vault_sesion.s

# La imagen del archivo de prueba la produce load_file.py, no el ensamblador
$(PROGS)/archivo_prueba.hex: $(PROGS)/archivo_prueba.txt $(TOOLS)/load_file.py
	python3 $(TOOLS)/load_file.py $< -o $@ --palabras 16384

# div32_prueba.s incluye div32.s, asi que su binario depende de los dos
$(PROGS)/div32_prueba.hex: $(PROGS)/div32.s

# El flujo completo, de archivo a archivo. Depende del volcado que escribe
# tb_archivo, asi que corre el testbench primero.
.PHONY: flujo
flujo: archivo
	@echo ""
	@echo "---- flujo completo de archivo a archivo ----"
	python3 $(TOOLS)/probar_flujo.py cifrado_volcado.hex

# ---- Cifrar un archivo cualquiera ---------------------------------------------
#   make cifrar ARCHIVO=../../tools/programas/mi_texto.txt
#
# tb_archivo tiene escrito el criptograma de archivo_prueba.txt, asi que solo
# sirve para ese archivo. tb_cifrado no trae valores fijos y probar_flujo.py
# hace de oraculo con su modelo de referencia. Sin ARCHIVO usa el de prueba.
ARCHIVO ?= $(PROGS)/archivo_prueba.txt

# Se regenera en cada corrida: si solo cambia la variable ARCHIVO, make no
# veria ningun archivo mas nuevo y cargaria la imagen anterior.
.PHONY: archivo_libre.hex cifrar
archivo_libre.hex:
	python3 $(TOOLS)/load_file.py $(ARCHIVO) -o $@ --palabras 16384

# ---- Cifrar con otra llave ----------------------------------------------------
#   make solo-cifrar ARCHIVO=... LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
#   make solo-cifrar ARCHIVO=... LLAVE=A1B2C3D4112233445566778899AABBCC
#
# LLAVE funciona en cifrar, solo-cifrar y solo-descifrar. Es la key[4] de la
# referencia del enunciado: key[0] primero, sea en cuatro palabras o en los
# primeros ocho de 32 digitos. llave.py genera en llave_gen/ una copia de los
# programas con esa llave, y el testbench y el modelo de referencia reciben la
# misma, asi que la llave se escribe en un solo lugar. Sin LLAVE se usa la de
# cargar_llave.s y no se genera nada.
LLAVE ?=
LLAVE_DIR := llave_gen

ifneq ($(strip $(LLAVE)),)
PROGRAMAS_LLAVE := programas-llave
PLUS_LLAVE      := +CIFRAR=$(LLAVE_DIR)/cifrar_archivo.hex \
                   +DESCIFRAR=$(LLAVE_DIR)/descifrar_archivo.hex \
                   +LLAVE=$(shell python3 $(TOOLS)/llave.py "$(LLAVE)" --hex)
ARG_LLAVE       := --llave "$(LLAVE)"
endif
PLUS_cifrado := $(PLUS_LLAVE)

.PHONY: programas-llave
programas-llave:
	python3 $(TOOLS)/llave.py "$(LLAVE)" --salida $(LLAVE_DIR)
	$(ASM) $(LLAVE_DIR)/cifrar_archivo.s -o $(LLAVE_DIR)/cifrar_archivo.hex \
	       --bundles 2048
	$(ASM) $(LLAVE_DIR)/descifrar_archivo.s -o $(LLAVE_DIR)/descifrar_archivo.hex \
	       --bundles 2048

# El criptograma sin la cabecera, que es lo que se compara contra un
# resultado calculado por fuera del proyecto
CRIPTOGRAMA := criptograma.bin

cifrado: archivo_libre.hex $(PROGRAMAS_LLAVE)

cifrar: cifrado
	@echo ""
	@echo "---- flujo completo sobre $(ARCHIVO) ----"
	python3 $(TOOLS)/probar_flujo.py cifrado_libre.hex $(ARCHIVO) \
	        --crudo $(CRIPTOGRAMA) $(ARG_LLAVE)

# Solo el cifrado: el segundo procesador no arranca. El criptograma lo sigue
# verificando probar_flujo.py contra el modelo de referencia, que no necesita
# del descifrado del hardware.
#   make solo-cifrar ARCHIVO=../../tools/programas/mi_texto.txt
.PHONY: solo-cifrar
solo-cifrar: tb_cifrado.vvp archivo_libre.hex $(PROGRAMAS_LLAVE)
	@echo ""
	@echo "---- solo cifrar $(ARCHIVO) ----"
	$(VVP) -n tb_cifrado.vvp +SOLO_CIFRAR $(PLUS_LLAVE)
	@echo ""
	@echo "---- el criptograma contra el modelo de referencia ----"
	python3 $(TOOLS)/probar_flujo.py cifrado_libre.hex $(ARCHIVO) \
	        --crudo $(CRIPTOGRAMA) $(ARG_LLAVE)

# Solo el descifrado, partiendo de un archivo cifrado en disco. Por omision
# toma el que deja "make solo-cifrar"; con ORIGINAL, tambien compara contra el.
#   make solo-descifrar
#   make solo-descifrar CIFRADO=cifrado_libre.bin ORIGINAL=../../mi_texto.txt
# El archivo descifrado queda en descifrado_libre.bin.
CIFRADO  ?= cifrado_libre.bin
ORIGINAL ?=

# Un criptograma cifrado FUERA del proyecto no trae cabecera. Con
#   make solo-descifrar CIFRADO_CRUDO=externo.bin LLAVE=...
# se carga como bloques puros. El tamano original no viaja en ningun lado, asi
# que el descifrado sale con el relleno del ultimo bloque incluido.
CIFRADO_CRUDO ?=
ifneq ($(strip $(CIFRADO_CRUDO)),)
ENTRADA_DESCIFRAR := $(CIFRADO_CRUDO)
MODO_CARGA        := --crudo
ARG_CRUDO         := --crudo
else
ENTRADA_DESCIFRAR := $(CIFRADO)
MODO_CARGA        := --cifrado
ARG_CRUDO         :=
endif

.PHONY: solo-descifrar contenedor_libre.hex
contenedor_libre.hex:
	python3 $(TOOLS)/load_file.py $(ENTRADA_DESCIFRAR) -o $@ --palabras 16384 \
	        $(MODO_CARGA)

solo-descifrar: tb_descifrado.vvp contenedor_libre.hex $(PROGRAMAS_LLAVE)
	@echo ""
	@echo "---- solo descifrar $(ENTRADA_DESCIFRAR) ----"
	$(VVP) -n tb_descifrado.vvp $(PLUS_LLAVE)
	@echo ""
	@echo "---- el descifrado contra el modelo de referencia ----"
	python3 $(TOOLS)/probar_descifrado.py $(ENTRADA_DESCIFRAR) \
	        descifrado_libre.hex descifrado_libre.bin $(ORIGINAL) \
	        $(ARG_LLAVE) $(ARG_CRUDO)

# ---- Correr un programa cualquiera ---------------------------------------------
#   make correr PROG=fibonacci.s MOSTRAR=0x100 PALABRAS=47
#
# Ensambla el programa y lo corre en el procesador completo hasta HALT. Muestra
# cuando sube y baja AUTH, la primera falla, los registros, el PSW y la memoria
# que el programa escribio.
#
#   PROG=      el programa en ensamblador. Basta el nombre, con o sin .s: se
#              busca aqui y en tools/programas
#   HEX=       en lugar de PROG, un programa ya en binario: un bundle por linea,
#              32 digitos hexadecimales, como el que produce el ensamblador o
#              un compilador que emita binario. Se carga tal cual, sin
#              ensamblar; la traza muestra direcciones en vez de instrucciones
#   MEMORIA=   imagen inicial de la memoria de datos, por ejemplo la que genera
#              load_file.py. Sin ella, la memoria arranca con el .data del
#              programa
#   VOLCADO=   archivo donde guardar la memoria de datos completa al terminar,
#              para sacar el resultado con extract_data.py
#   RESULTADO= archivo donde guardar el resumen final (ciclos, registros, PSW y
#              la memoria de MOSTRAR). Por omision resultado_<programa>.txt;
#              RESULTADO= vacio no lo guarda
#   ESCRITURAS= archivo con cada escritura a registros y a memoria de toda la
#              corrida: ciclo, bundle, valor e instruccion. Por omision
#              escrituras_<programa>.txt; ESCRITURAS= vacio no lo guarda
#   ESCRITURAS_MAX= tope de lineas de ese archivo (50 000)
#   LLAVE=     solo para cifrar_archivo.s y descifrar_archivo.s: corre una copia
#              del programa con esa llave, generada por llave.py
#   MOSTRAR=   direccion desde donde mostrar la memoria en pantalla, y
#   PALABRAS=  cuantas palabras de 32 bits mostrar
#   CICLOS=    tope de ciclos (por omision 2 000 000)
#   TRAZA=     detalle de una ventana de ciclos: TRAZA=30 son los ciclos 1 a
#              30, TRAZA=100-130 los ciclos 100 a 130 (hasta 500). Imprime el
#              diagrama del pipeline (una fila por bundle, una columna por
#              ciclo) y la lista de eventos: registros y memoria escritos,
#              saltos, banderas, boveda y fallas
#
# Cifrar un archivo es cargar, correr y extraer:
#
#   python3 ../../tools/load_file.py --input foto.png --output entrada.hex
#   make correr PROG=cifrar_archivo.s MEMORIA=entrada.hex VOLCADO=salida.hex
#   python3 ../../tools/extract_data.py salida.hex -o cifrado.bin --cifrado
PROG     ?=
MEMORIA  ?=
VOLCADO  ?=
MOSTRAR  ?= 0
HEX      ?=
RESULTADO ?= resultado_$(NOMBRE_PROG).txt
ESCRITURAS ?= escrituras_$(NOMBRE_PROG).txt
ESCRITURAS_MAX ?= 50000
PALABRAS ?= 0
CICLOS   ?= 2000000
TRAZA    ?= 0

# PROG puede ser solo el nombre del programa, con o sin .s: si no trae
# carpeta, se busca primero aqui y despues en tools/programas. Una ruta
# completa se usa tal cual.
PROG_CON_S   = $(if $(filter %.s,$(PROG)),$(PROG),$(PROG).s)
PROG_ENCONTRADO = $(if $(findstring /,$(PROG_CON_S)),$(PROG_CON_S),$(if \
                  $(wildcard $(PROG_CON_S)),$(PROG_CON_S),$(PROGS)/$(PROG_CON_S)))

# Nombre del programa para los archivos de salida, venga de PROG o de HEX
NOMBRE_PROG = $(if $(strip $(HEX)),$(basename $(notdir $(HEX))),$(basename $(notdir $(PROG_CON_S))))
FUENTE_PROG = $(if $(strip $(HEX)),$(notdir $(HEX)),$(notdir $(PROG_CON_S)))

# Con LLAVE, el programa que se ensambla es la copia que genera llave.py
PROG_A_ENSAMBLAR = $(if $(strip $(LLAVE)),$(LLAVE_DIR)/$(notdir $(PROG_CON_S)),$(PROG_ENCONTRADO))

.PHONY: correr
correr: tb_programa.vvp
	@test -z "$(MEMORIA)" -o -f "$(MEMORIA)" || \
	    { echo "error: no se encontro la imagen de memoria $(MEMORIA)"; exit 2; }
ifneq ($(strip $(HEX)),)
	@test -z "$(PROG)" || { echo "error: se usa PROG= o HEX=, no los dos"; exit 2; }
	@test -f "$(HEX)" || { echo "error: no se encontro $(HEX)"; exit 2; }
	@! grep -nvE '^[[:space:]]*([0-9A-Fa-f_]{1,32}|@[0-9A-Fa-f]+|//.*)?[[:space:]]*\r?$$' "$(HEX)" | head -3 | \
	    sed 's/^/error: linea que no es un bundle en hexadecimal: /' | grep . || exit 2
	@# Se rellena con NOP hasta los 2048 bundles de la memoria, para que
	@# $$readmemh no avise que faltan palabras
	{ cat "$(HEX)"; yes 00000000000000000000000000000000 | head -n 2048; } | \
	    head -n 2048 > programa.hex
	@rm -f programa_datos.hex programa_texto.txt
	@touch programa_datos.hex
else
	@test -n "$(PROG)" || { echo "error: falta PROG=programa.s (o HEX=programa.hex)"; exit 2; }
	@test -f "$(PROG_ENCONTRADO)" || \
	    { echo "error: no se encontro $(PROG_CON_S) ni aqui ni en tools/programas"; \
	      exit 2; }
ifneq ($(strip $(LLAVE)),)
	python3 $(TOOLS)/llave.py "$(LLAVE)" --salida $(LLAVE_DIR)
	@test -f "$(PROG_A_ENSAMBLAR)" || \
	    { echo "error: LLAVE solo se aplica a cifrar_archivo.s y descifrar_archivo.s"; \
	      exit 2; }
endif
	$(ASM) $(PROG_A_ENSAMBLAR) -o programa.hex --datos programa_datos.hex \
	       --bundles 2048 --palabras 16384 --listado programa.lst
	@python3 $(TOOLS)/listado_a_texto.py programa.lst -o programa_texto.txt
endif
	$(VVP) -n tb_programa.vvp +PROGRAMA=programa.hex \
	       +TEXTO=$(if $(strip $(HEX)),,programa_texto.txt) \
	       +DATOS=$(if $(MEMORIA),$(MEMORIA),$$(grep -q "[0-9A-Fa-f]" programa_datos.hex && echo programa_datos.hex)) \
	       +VOLCADO=$(VOLCADO) +CICLOS=$(CICLOS) \
	       +MOSTRAR=$(shell printf '%d' $(MOSTRAR)) +PALABRAS=$(PALABRAS) \
	       +TRAZA=$(TRAZA) +RESULTADO=$(RESULTADO) +FUENTE=$(FUENTE_PROG) \
	       +ESCRITURAS=$(ESCRITURAS) +ESCRITURAS_MAX=$(ESCRITURAS_MAX)

# Comprueba que el programa de cobertura usa el 100% del conjunto
# ---- Las cinco etapas del pipeline ------------------------------------------
# "Revisar que el procesador y sus etapas funcionan correctamente" en un
# comando. Corre los testbenches que miran la segmentacion por dentro, en vez
# de mirar solo el resultado final de un programa:
#
#   reg_if_id / reg_id_ex / reg_ex_mem   cada frontera por separado, campo a
#                                        campo, con huella de bits
#   pipeline                             la latencia expuesta medida sobre la
#                                        cadena real de registros mas el banco
#   latency                              la misma medida contra el modelo, y
#                                        comparada con los 3 bundles del ISA
#   fetch / fetch_flow                   el contador de programa, el delay slot
#                                        y HALT con la BRU real
#   wconf                                los dos detectores de conflicto de
#                                        escritura, contrastados entre si
#   top                                  las cinco etapas juntas, siete
#                                        programas
.PHONY: etapas
etapas: reg_if_id reg_id_ex reg_ex_mem pipeline latency fetch fetch_flow wconf top
	@echo ""
	@echo "=============================================================="
	@echo " Las cinco etapas, cada frontera y la latencia: todo verificado"
	@echo "=============================================================="

# ---- Ocupacion de los bundles y empaquetado ---------------------------------
# Las dos herramientas que responden a "¿esta usando el bundle de verdad?".
#
#   make ocupacion            el informe de todos los programas
#   make empacar PROG=x.s     empaqueta uno y deja x_emp.s al lado
#
# El empaquetador NO cambia lo que el programa calcula: junta en un mismo
# bundle las operaciones que son independientes, respetando la latencia de
# tres, los puertos de escritura y el orden de la memoria. Lo que el programa
# hace es cosa del programador; cuantos bundles tarda, de la herramienta.
.PHONY: ocupacion empacar vliw-comparar
ocupacion:
	@echo ""
	@echo "---- cuanto del bundle se usa, programa por programa ----"
	@for f in $(PROGS)/*.s; do 	    case "$$f" in *_emp.s) continue;; esac; 	    python3 $(TOOLS)/empacar.py "$$f" --informe 2>/dev/null; 	done

empacar:
	@test -n "$(PROG)" || { echo "error: falta PROG=programa.s"; exit 2; }
	python3 $(TOOLS)/empacar.py $(if $(findstring /,$(PROG)),$(PROG),$(PROGS)/$(PROG))

# La comparacion de la demostracion VLIW, fuera del testbench, para enseñarla
# con los dos programas a la vista
vliw-comparar: $(PROGS)/suma_simple_emp.hex $(PROGS)/suma_vliw_emp.hex
	@echo ""
	@echo "---- el mismo calculo, escrito de dos formas ----"
	@$(MAKE) -s correr PROG=suma_simple_emp.s  MOSTRAR=0x200 PALABRAS=1 | 	    grep -E "HALT en|0x00000200"
	@$(MAKE) -s correr PROG=suma_vliw_emp.s    MOSTRAR=0x200 PALABRAS=1 | 	    grep -E "HALT en|0x00000200"

# ---- La huella del cifrado --------------------------------------------------
# El SHA-256 del criptograma, para comparar contra otra implementacion.
#
#   make huella                                  el archivo de prueba
#   make huella ARCHIVO=../../mi_foto.png
#   make huella ARCHIVO=x.txt LLAVE=A1B2C3D4,11223344,55667788,99AABBCC
#
# Corre el cifrado en el RTL, saca el criptograma de la memoria de datos y lo
# compara con el modelo de referencia en Python. Los dos numeros tienen que
# coincidir, y el de arriba es el que se le da a quien quiera comprobarlo con
# su propia implementacion.
.PHONY: huella
huella:
	python3 $(TOOLS)/huella.py $(ARCHIVO) $(if $(strip $(LLAVE)),--llave "$(LLAVE)",)

cobertura:
	@echo "---- cobertura del conjunto de instrucciones ----"
	$(ASM) $(PROGS)/cobertura.s --cobertura

$(WAVE_TARGETS): wave-%: %
	$(GTKWAVE) tb_$*.vcd &

# ---- Analisis estatico ------------------------------------------------------
# Verilator ve cosas que Icarus deja pasar: anchos inconsistentes, senales no
# usadas y latches inferidos en un always_comb incompleto. Conviene correrlo
# antes de cada commit, no solo cuando algo falla.
lint: $(LINT_TARGETS)
	@echo ""
	@echo "=============================================================="
	@echo " Analisis estatico limpio en todas las unidades"
	@echo "=============================================================="

$(LINT_TARGETS): lint-%:
	@echo "---- verilator $* ----"
	$(VERILATOR) $(LINT_FLAGS) $(SUB_$*) $(CPU)/$*.sv --top-module $*

# clean borra TAMBIEN los binarios que produce el ensamblador. No es por
# prolijidad: las marcas de tiempo del sistema de archivos tienen granularidad
# de un segundo, asi que editar un .s y correr make en el mismo segundo puede
# dejar el .hex anterior en pie, y la simulacion correria el programa viejo sin
# que nada avise. Con "make clean && make" eso no puede pasar.
clean:
	rm -f *.vvp *.vcd cifrado_volcado.hex cifrado_volcado.bin
	rm -f archivo_libre.hex cifrado_libre.hex cifrado_libre.bin
	rm -f contenedor_libre.hex descifrado_libre.hex descifrado_libre.bin
	rm -f criptograma.bin programa.hex programa_datos.hex programa.lst programa_texto.txt resultado_*.txt escrituras_*.txt
	rm -rf llave_gen
	rm -f $(PROGS)/*.hex