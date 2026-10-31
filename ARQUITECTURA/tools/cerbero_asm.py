#!/usr/bin/env python3
"""
cerbero_asm.py - Ensamblador de CERBERO-1.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Traduce el ensamblador propio que especifica la seccion 10 de docs/isa.md a un
archivo de 32 digitos hexadecimales por bundle, listo para $readmemh.

    cerbero_asm.py programa.s -o programa.hex --listado programa.lst

-----------------------------------------------------------------------------
LAS TABLAS DE OPCODES SE LEEN DE cerbero_defs.svh
-----------------------------------------------------------------------------
Este programa NO tiene los valores de los opcodes escritos adentro: los lee del
mismo archivo de cabecera que incluye el RTL. Es la decision de diseno mas
importante del ensamblador y no es por elegancia.

Durante el proyecto ya ocurrio dos veces que una copia de la tabla de opcodes se
desincronizara de la otra. La peor fue un decodificador que marcaba los opcodes
10011 y 11011 como ilegales: era correcto en la Entrega 1 y dejo de serlo cuando
SETcc y MFPSW los ocuparon. Un ensamblador con su propia copia de la tabla es el
sitio donde ese error duele mas, porque produciria binarios que el procesador
rechaza sin que nada avise hasta la simulacion.

Leyendo el .svh, renumerar un opcode sigue siendo una sola linea de cambio.

-----------------------------------------------------------------------------
VALIDACIONES
-----------------------------------------------------------------------------
La seccion 10.3 del ISA dice que el programa se rechaza, sin emitir binario,
cuando el ensamblador detecta:

  - dos slots escribiendo el mismo registro en un bundle
  - una comparacion fuera de S0
  - una instruccion en un slot que no corresponde a su unidad funcional
  - un campo reservado distinto de cero
  - un desplazamiento de salto fuera de rango
  - un inmediato fuera del rango del campo
  - una etiqueta no definida, o definida dos veces

Y que la violacion de la regla de latencia se emite como ADVERTENCIA y no como
error, porque el generador de codigo puede tener informacion que el ensamblador
no tiene. Se agrega una advertencia mas por el mismo motivo: un salto en el
delay slot de otro salto, que la v1.2 del ISA prohibe.

La comprobacion de latencia mira el orden secuencial de los bundles y no el
flujo de control, asi que no ve las dependencias que cruzan un salto. Es una
limitacion conocida y es parte de por que es advertencia y no error.
"""

import argparse
import re
import sys
from pathlib import Path

# =============================================================================
# Lectura de cerbero_defs.svh
# =============================================================================

RE_DEFINE = re.compile(
    r"^`define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(\d+)'b([01_]+)\s*(?://.*)?$"
)
RE_DEFINE_INT = re.compile(
    r"^`define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(\d+)\s*(?://.*)?$"
)


def cargar_defs(ruta):
    """Devuelve {nombre: valor} de los `define de ancho fijo del encabezado."""
    defs = {}
    texto = Path(ruta).read_text(encoding="utf-8", errors="replace")
    for linea in texto.splitlines():
        linea = linea.strip()
        m = RE_DEFINE.match(linea)
        if m:
            defs[m.group(1)] = int(m.group(3).replace("_", ""), 2)
            continue
        m = RE_DEFINE_INT.match(linea)
        if m:
            defs[m.group(1)] = int(m.group(2))
    return defs


# =============================================================================
# Errores
# =============================================================================


class ErrorEnsamblado(Exception):
    def __init__(self, mensaje, linea=None, texto=None):
        self.mensaje = mensaje
        self.linea = linea
        self.texto = texto
        super().__init__(mensaje)

    def __str__(self):
        cabeza = f"linea {self.linea}: " if self.linea else ""
        cola = f"\n      {self.texto.strip()}" if self.texto else ""
        return f"{cabeza}{self.mensaje}{cola}"


# =============================================================================
# Operandos
# =============================================================================

RE_REG = re.compile(r"^r(\d{1,2})$", re.I)
RE_PAR = re.compile(r"^p([0-7])$", re.I)
RE_LLAVE = re.compile(r"^k(\d)$", re.I)
RE_ETIQ = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

N_LLAVES = 4   # la boveda tiene 4 ranuras: el campo kv es de 2 bits

# Las banderas del PSW son una dependencia igual que un registro y con la misma
# regla de 3 bundles: una comparacion las escribe y SETcc, un salto condicional
# o MFPSW las leen. Se les da un indice propio, fuera del rango de los 16
# registros, para que la comprobacion de latencia las trate como a cualquier
# otro productor sin logica aparte.
BANDERAS = 16


def nombre_recurso(r):
    return "las banderas" if r == BANDERAS else f"R{r}"



def reg(txt):
    m = RE_REG.match(txt.strip())
    if not m:
        raise ErrorEnsamblado(f"se esperaba un registro r0..r15, no '{txt}'")
    n = int(m.group(1))
    if n > 15:
        raise ErrorEnsamblado(f"registro fuera de rango: '{txt}' (son r0..r15)")
    return n


def par(txt):
    m = RE_PAR.match(txt.strip())
    if not m:
        raise ErrorEnsamblado(f"se esperaba un par p0..p7, no '{txt}'")
    return int(m.group(1))


def llave(txt):
    m = RE_LLAVE.match(txt.strip())
    if not m:
        raise ErrorEnsamblado(f"se esperaba una llave k0..k3, no '{txt}'")
    n = int(m.group(1))
    if n >= N_LLAVES:
        raise ErrorEnsamblado(
            f"llave fuera de rango: '{txt}'. La boveda tiene {N_LLAVES} "
            f"ranuras, asi que son k0..k{N_LLAVES - 1}"
        )
    return n


def inmediato(txt):
    """Acepta #12, #-4, #0x1F y tambien 12, -4, 0x1F sin el numeral."""
    t = txt.strip()
    if t.startswith("#"):
        t = t[1:].strip()
    neg = t.startswith("-")
    if neg:
        t = t[1:].strip()
    try:
        v = int(t, 16) if t.lower().startswith("0x") else int(t, 10)
    except ValueError:
        raise ErrorEnsamblado(f"inmediato mal formado: '{txt}'")
    return -v if neg else v


def cabe_con_signo(v, ancho):
    return -(1 << (ancho - 1)) <= v <= (1 << (ancho - 1)) - 1


def cabe_sin_signo(v, ancho):
    return 0 <= v <= (1 << ancho) - 1


def a_campo(v, ancho):
    return v & ((1 << ancho) - 1)


def partes(txt, n, nombre):
    """Parte una lista de operandos por comas y exige exactamente n."""
    t = txt.strip()
    ops = [] if t == "" else [x.strip() for x in t.split(",")]
    if len(ops) != n:
        raise ErrorEnsamblado(
            f"{nombre} lleva {n} operando(s), se dieron {len(ops)}"
        )
    return ops


# `#imm(rbase)`, con el numeral opcional
RE_MEM = re.compile(r"^(?P<imm>[^()]*)\(\s*(?P<base>[^()]+)\s*\)$")


def mem_operando(txt):
    m = RE_MEM.match(txt.strip())
    if not m:
        raise ErrorEnsamblado(
            f"se esperaba la forma #desp(rbase), no '{txt}'"
        )
    return inmediato(m.group("imm")), reg(m.group("base"))


# =============================================================================
# Ensamblador
# =============================================================================

BUNDLE_BYTES = 16
ANCHO_SLOT = [32, 32, 32, 16, 16]
NOMBRE_SLOT = ["S0", "S1", "S2", "S3", "S4"]


class Ensamblador:
    def __init__(self, defs, sec_base=None, sec_limit=None):
        self.d = defs
        self.sec_base = (
            sec_base if sec_base is not None else defs.get("SEC_BASE_DEF", 0x7000)
        )
        self.sec_limit = (
            sec_limit if sec_limit is not None else defs.get("SEC_LIMIT_DEF", 0x7FFF)
        )

        self.errores = []
        self.advertencias = []

        self.etiquetas = {}        # nombre -> direccion
        self.bundles = []          # (direccion, [slots], n_linea, texto)
        self.datos = {}            # direccion de byte -> valor de byte
        self.usados = set()        # mnemonicos que aparecieron, para cobertura

        self._construir_tablas()

    # -- registro de diagnosticos --------------------------------------------

    def _error(self, mensaje, linea=None, texto=None):
        self.errores.append(ErrorEnsamblado(mensaje, linea, texto))

    def _advertir(self, mensaje, linea=None):
        cabeza = f"linea {linea}: " if linea else ""
        self.advertencias.append(f"{cabeza}{mensaje}")

    # -- tablas --------------------------------------------------------------

    def _construir_tablas(self):
        d = self.d

        # Condiciones de salto
        self.cond = {
            "al": d["COND_AL"], "eq": d["COND_EQ"], "ne": d["COND_NE"],
            "lt": d["COND_LT"], "ge": d["COND_GE"], "ltu": d["COND_LTU"],
            "geu": d["COND_GEU"], "auth": d["COND_AUTH"],
        }

        # Codigos de condicion de SETcc: la misma tabla
        self.setcc_cond = dict(self.cond)

        # --- Slot ALU (S0 y S1) ---
        # forma: (opcode, plantilla). La plantilla dice como leer los operandos.
        self.alu = {}

        def alu(nombre, clave, plantilla, solo_s0=False):
            self.alu[nombre] = (d[clave], plantilla, solo_s0)

        for n, k in [("add", "ALU_ADD"), ("sub", "ALU_SUB"), ("mul", "ALU_MUL"),
                     ("and", "ALU_AND"), ("or", "ALU_OR"), ("xor", "ALU_XOR"),
                     ("sll", "ALU_SLL"), ("srl", "ALU_SRL"), ("sra", "ALU_SRA"),
                     ("rol", "ALU_ROL"), ("ror", "ALU_ROR")]:
            alu(n, k, "rd,rs1,rs2")

        for n, k in [("mov", "ALU_MOV"), ("not", "ALU_NOT"), ("neg", "ALU_NEG")]:
            alu(n, k, "rd,rs1")

        alu("cmp",  "ALU_CMP",  "rs1,rs2", solo_s0=True)
        alu("test", "ALU_TEST", "rs1,rs2", solo_s0=True)

        for n, k in [("addi", "ALU_ADDI"), ("subi", "ALU_SUBI"),
                     ("andi", "ALU_ANDI"), ("ori", "ALU_ORI"),
                     ("xori", "ALU_XORI"), ("slli", "ALU_SLLI"),
                     ("srli", "ALU_SRLI"), ("srai", "ALU_SRAI"),
                     ("roli", "ALU_ROLI")]:
            alu(n, k, "rd,rs1,imm19")

        alu("cmpi",  "ALU_CMPI",  "rs1,imm19", solo_s0=True)
        alu("testi", "ALU_TESTI", "rs1,imm19", solo_s0=True)

        alu("movi",  "ALU_MOVI",  "rd,imm19")
        alu("movh",  "ALU_MOVH",  "rd,imm16")
        alu("setcc", "ALU_SETCC", "rd,cond")
        alu("mfpsw", "ALU_MFPSW", "rd")

        # --- Slot LSU (S2) ---
        self.lsu = {
            "lw":     (d["LSU_LW"],     "rd,mem"),
            "lh":     (d["LSU_LH"],     "rd,mem"),
            "lhu":    (d["LSU_LHU"],    "rd,mem"),
            "lb":     (d["LSU_LB"],     "rd,mem"),
            "lbu":    (d["LSU_LBU"],    "rd,mem"),
            "sw":     (d["LSU_SW"],     "rs,mem"),
            "sh":     (d["LSU_SH"],     "rs,mem"),
            "sb":     (d["LSU_SB"],     "rs,mem"),
            "lw.inc": (d["LSU_LW_INC"], "rd,mem"),
            "sw.inc": (d["LSU_SW_INC"], "rs,mem"),
        }

        # --- Slot S3 ---
        self.salu = {
            "add.s": d["SALU_ADD"], "sub.s": d["SALU_SUB"],
            "and.s": d["SALU_AND"], "or.s":  d["SALU_OR"],
            "xor.s": d["SALU_XOR"], "mov.s": d["SALU_MOV"],
            "not.s": d["SALU_NOT"], "neg.s": d["SALU_NEG"],
        }
        self.salu_unarias = {"not.s", "neg.s"}

        self.vctl = {
            "login":  d["VCTL_LOGIN"],
            "logout": d["VCTL_LOGOUT"],
            "pwset":  d["VCTL_PWSET"],
            "kclr":   d["VCTL_KCLR"],
        }

        # --- Slot BRU (S4) ---
        self.bru_rel = {"br": d["BRU_BR"], "jal": d["BRU_JAL"]}
        self.bru_ind = {"jr": d["BRU_JR"], "jalr": d["BRU_JALR"]}

        # Conjunto completo de mnemonicos, para la cobertura
        self.todos = set(self.alu) | set(self.lsu) | set(self.salu) | \
            set(self.vctl) | {"f4e", "f4d", "ksetw", "authw", "halt", "nop"} | \
            set(self.bru_rel) | set(self.bru_ind)

    # -- primera pasada ------------------------------------------------------

    def primera_pasada(self, lineas):
        """Asigna direcciones, recoge etiquetas y emite los datos."""
        pc = 0
        seccion = "text"
        en_segura = False
        self.rangos_seguros = []
        inicio_segura = None

        for n, cruda in enumerate(lineas, start=1):
            linea = cruda.split("//")[0].strip()
            if not linea:
                continue

            # Etiqueta al inicio de la linea
            while True:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", linea)
                if not m:
                    break
                nombre, resto = m.group(1), m.group(2)
                if nombre in self.etiquetas:
                    self._error(f"etiqueta '{nombre}' definida dos veces", n, cruda)
                else:
                    self.etiquetas[nombre] = pc
                linea = resto.strip()
            if not linea:
                continue

            # Directivas
            if linea.startswith("."):
                campos = linea.split(None, 1)
                dirv = campos[0].lower()
                arg = campos[1].strip() if len(campos) > 1 else ""

                if dirv in (".text", ".data"):
                    seccion = dirv[1:]
                elif dirv == ".org":
                    try:
                        pc = inmediato(arg)
                    except ErrorEnsamblado as e:
                        self._error(f".org: {e.mensaje}", n, cruda)
                    if seccion == "text" and pc % BUNDLE_BYTES:
                        self._error(
                            f".org en la seccion de codigo debe ser multiplo de "
                            f"{BUNDLE_BYTES}, no 0x{pc:X}", n, cruda)
                elif dirv == ".word":
                    for pieza in arg.split(","):
                        try:
                            v = inmediato(pieza)
                        except ErrorEnsamblado as e:
                            self._error(f".word: {e.mensaje}", n, cruda)
                            continue
                        for b in range(4):
                            self.datos[pc + b] = (v >> (8 * b)) & 0xFF
                        pc += 4
                elif dirv == ".byte":
                    for pieza in arg.split(","):
                        try:
                            v = inmediato(pieza)
                        except ErrorEnsamblado as e:
                            self._error(f".byte: {e.mensaje}", n, cruda)
                            continue
                        if not cabe_sin_signo(v & 0xFF, 8):
                            self._error(f".byte fuera de rango: {v}", n, cruda)
                        self.datos[pc] = v & 0xFF
                        pc += 1
                elif dirv == ".space":
                    try:
                        pc += inmediato(arg)
                    except ErrorEnsamblado as e:
                        self._error(f".space: {e.mensaje}", n, cruda)
                elif dirv == ".include":
                    # Ya se expandio antes de las pasadas; si llega aqui es que
                    # se ensamblo sin pasar el archivo base.
                    self._error(
                        ".include requiere conocer el archivo de origen; "
                        "use la linea de comandos y no la API directa", n, cruda)
                elif dirv == ".secure":
                    if en_segura:
                        self._error(".secure anidado", n, cruda)
                    en_segura, inicio_segura = True, pc
                elif dirv == ".endsecure":
                    if not en_segura:
                        self._error(".endsecure sin .secure", n, cruda)
                    else:
                        self.rangos_seguros.append((inicio_segura, pc, n))
                        en_segura = False
                else:
                    self._error(f"directiva desconocida: '{dirv}'", n, cruda)
                continue

            # Bundle
            if seccion != "text":
                self._error("hay una instruccion en la seccion de datos", n, cruda)
                continue
            if not linea.endswith(";"):
                self._error("el bundle debe terminar en ';'", n, cruda)
                continue

            cuerpo = linea[:-1]
            slots = [x.strip() for x in cuerpo.split("|")]
            if len(slots) > 5:
                self._error(
                    f"un bundle tiene 5 slots y esta linea trae {len(slots)}",
                    n, cruda)
                continue
            # Relleno hacia la derecha, como pide la seccion 10.2
            slots += ["-"] * (5 - len(slots))

            self.bundles.append([pc, slots, n, cruda])
            pc += BUNDLE_BYTES

        if en_segura:
            self._error(".secure sin .endsecure")

        # El codigo marcado como seguro tiene que caber en la region
        for ini, fin, n in self.rangos_seguros:
            if ini < self.sec_base or (fin - 1) > self.sec_limit:
                self._error(
                    f"el bloque .secure ocupa 0x{ini:04X}..0x{fin - 1:04X}, "
                    f"fuera de la region segura "
                    f"0x{self.sec_base:04X}..0x{self.sec_limit:04X}", n)

    # -- codificacion de cada slot -------------------------------------------

    def _enc_alu(self, texto, slot_idx, n, cruda):
        campos = texto.split(None, 1)
        mn = campos[0].lower()
        ops = campos[1] if len(campos) > 1 else ""

        if mn not in self.alu:
            raise ErrorEnsamblado(
                f"'{mn}' no es una instruccion del slot ALU "
                f"({NOMBRE_SLOT[slot_idx]})")
        opc, plantilla, solo_s0 = self.alu[mn]
        self.usados.add(mn)

        if solo_s0 and slot_idx != 0:
            raise ErrorEnsamblado(
                f"'{mn}' escribe banderas y solo existe en S0, no en "
                f"{NOMBRE_SLOT[slot_idx]}")

        rd = rs1 = rs2 = 0
        imm19 = imm16 = cond = 0
        usa_imm16 = usa_cond = False

        if plantilla == "rd,rs1,rs2":
            a, b, c = partes(ops, 3, mn)
            rd, rs1, rs2 = reg(a), reg(b), reg(c)
        elif plantilla == "rd,rs1":
            a, b = partes(ops, 2, mn)
            rd, rs1 = reg(a), reg(b)
        elif plantilla == "rs1,rs2":
            a, b = partes(ops, 2, mn)
            rs1, rs2 = reg(a), reg(b)
        elif plantilla == "rd,rs1,imm19":
            a, b, c = partes(ops, 3, mn)
            rd, rs1 = reg(a), reg(b)
            imm19 = inmediato(c)
            if not cabe_con_signo(imm19, 19):
                raise ErrorEnsamblado(
                    f"el inmediato {imm19} no cabe en 19 bits con signo "
                    f"(-262144 a 262143)")
        elif plantilla == "rs1,imm19":
            a, b = partes(ops, 2, mn)
            rs1 = reg(a)
            imm19 = inmediato(b)
            if not cabe_con_signo(imm19, 19):
                raise ErrorEnsamblado(
                    f"el inmediato {imm19} no cabe en 19 bits con signo")
        elif plantilla == "rd,imm19":
            a, b = partes(ops, 2, mn)
            rd = reg(a)
            imm19 = inmediato(b)
            if not cabe_con_signo(imm19, 19):
                raise ErrorEnsamblado(
                    f"el inmediato {imm19} no cabe en 19 bits con signo")
        elif plantilla == "rd,imm16":
            a, b = partes(ops, 2, mn)
            rd = reg(a)
            imm16 = inmediato(b)
            if not (cabe_sin_signo(imm16, 16) or cabe_con_signo(imm16, 16)):
                raise ErrorEnsamblado(
                    f"el inmediato de movh {imm16} no cabe en 16 bits")
            imm16 = a_campo(imm16, 16)
            usa_imm16 = True
        elif plantilla == "rd,cond":
            a, b = partes(ops, 2, mn)
            rd = reg(a)
            c = b.strip().lower()
            if c not in self.setcc_cond:
                raise ErrorEnsamblado(
                    f"condicion desconocida para setcc: '{b}'. "
                    f"Son {', '.join(sorted(self.setcc_cond))}")
            cond = self.setcc_cond[c]
            usa_cond = True
        elif plantilla == "rd":
            a, = partes(ops, 1, mn)
            rd = reg(a)
        else:
            raise ErrorEnsamblado(f"plantilla interna desconocida: {plantilla}")

        if usa_imm16 or usa_cond:
            # Tipo U: imm16 en [18:3] y cond en [2:0]
            v = (opc << 27) | (rd << 23) | (rs1 << 19) | (imm16 << 3) | cond
        elif plantilla in ("rd,rs1,imm19", "rs1,imm19", "rd,imm19"):
            v = (opc << 27) | (rd << 23) | (rs1 << 19) | a_campo(imm19, 19)
        else:
            # Tipo A: reservado [14:0] en cero
            v = (opc << 27) | (rd << 23) | (rs1 << 19) | (rs2 << 15)

        escribe = set()
        lee = set()
        # Solo las comparaciones escriben banderas, y solo en S0
        if mn in ("cmp", "test", "cmpi", "testi"):
            escribe.add(BANDERAS)
        # SETcc materializa una condicion y MFPSW lee el PSW entero
        if mn in ("setcc", "mfpsw"):
            lee.add(BANDERAS)
        if plantilla in ("rd,rs1,rs2", "rd,rs1", "rd,rs1,imm19",
                         "rd,imm19", "rd,imm16", "rd,cond", "rd"):
            escribe.add(rd)
        if plantilla in ("rd,rs1,rs2", "rd,rs1", "rs1,rs2",
                         "rd,rs1,imm19", "rs1,imm19"):
            lee.add(rs1)
        if plantilla in ("rd,rs1,rs2", "rs1,rs2"):
            lee.add(rs2)
        if plantilla == "rd,imm16":
            lee.add(rd)      # movh conserva la mitad baja de rd
        return v & 0xFFFFFFFF, escribe, lee

    def _enc_lsu(self, texto, n, cruda):
        campos = texto.split(None, 1)
        mn = campos[0].lower()
        ops = campos[1] if len(campos) > 1 else ""

        if mn not in self.lsu:
            raise ErrorEnsamblado(
                f"'{mn}' no es una instruccion del slot LSU (S2)")
        opc, plantilla = self.lsu[mn]
        self.usados.add(mn)

        a, b = partes(ops, 2, mn)
        rdato = reg(a)
        desp, rbase = mem_operando(b)
        if not cabe_con_signo(desp, 19):
            raise ErrorEnsamblado(
                f"el desplazamiento {desp} no cabe en 19 bits con signo")

        v = (opc << 27) | (rdato << 23) | (rbase << 19) | a_campo(desp, 19)

        escribe, lee = set(), {rbase}
        if plantilla == "rd,mem":
            escribe.add(rdato)
        else:
            lee.add(rdato)
        if mn.endswith(".inc"):
            escribe.add(rbase)
        return v & 0xFFFFFFFF, escribe, lee

    def _enc_s3(self, texto, n, cruda):
        campos = texto.split(None, 1)
        mn = campos[0].lower()
        ops = campos[1] if len(campos) > 1 else ""
        d = self.d

        # --- Ronda Feistel ---
        if mn in ("f4e", "f4d"):
            self.usados.add(mn)
            opc = d["CRP_F4E"] if mn == "f4e" else d["CRP_F4D"]
            a, b, c = partes(ops, 3, mn)
            p, k = par(a), llave(b)
            rnd = inmediato(c)
            if not cabe_sin_signo(rnd, 2):
                raise ErrorEnsamblado(
                    f"la ronda {rnd} esta fuera de rango: son #0 a #3")
            v = (opc << 13) | (p << 10) | (k << 8) | (rnd << 6)
            regs = {2 * p, 2 * p + 1}
            return v & 0xFFFF, set(regs), set(regs)

        # --- Boveda ---
        if mn == "ksetw":
            self.usados.add(mn)
            a, b, c = partes(ops, 3, mn)
            k = llave(a)
            w = inmediato(b)
            rs = reg(c)
            if not cabe_sin_signo(w, 2):
                raise ErrorEnsamblado(
                    f"el indice de palabra {w} esta fuera de rango: #0 a #3")
            v = (d["CRP_KSETW"] << 13) | (k << 11) | (w << 9) | (rs << 5)
            return v & 0xFFFF, set(), {rs}

        if mn == "authw":
            self.usados.add(mn)
            a, b = partes(ops, 2, mn)
            w = inmediato(a)
            rs = reg(b)
            if not cabe_sin_signo(w, 2):
                raise ErrorEnsamblado(
                    f"el indice de palabra {w} esta fuera de rango: #0 a #3")
            # [12:11] va reservado en cero, que es la decision D1 del ISA
            v = (d["CRP_AUTHW"] << 13) | (w << 9) | (rs << 5)
            return v & 0xFFFF, set(), {rs}

        if mn in self.vctl:
            self.usados.add(mn)
            subfn = self.vctl[mn]
            if mn == "kclr":
                a, = partes(ops, 1, mn)
                k = llave(a)
                v = (d["CRP_VCTL"] << 13) | (subfn << 11) | (k << 9)
            else:
                partes(ops, 0, mn)
                v = (d["CRP_VCTL"] << 13) | (subfn << 11)
            return v & 0xFFFF, set(), set()

        # --- ALU corta ---
        if mn in self.salu:
            self.usados.add(mn)
            subop = self.salu[mn]
            if mn in self.salu_unarias:
                a, = partes(ops, 1, mn)
                rd = reg(a)
                # Con i = 0 el campo fuente va en cero, y el bit 4 tambien
                v = (d["CRP_SALU"] << 13) | (0 << 12) | (subop << 9) | (rd << 5)
                return v & 0xFFFF, {rd}, {rd}
            a, b = partes(ops, 2, mn)
            rd = reg(a)
            b = b.strip()
            if b.startswith("#"):
                imm = inmediato(b)
                if not cabe_sin_signo(imm, 5):
                    raise ErrorEnsamblado(
                        f"el inmediato de la ALU corta {imm} no cabe en 5 bits "
                        f"sin signo (0 a 31)")
                v = (d["CRP_SALU"] << 13) | (1 << 12) | (subop << 9) | \
                    (rd << 5) | imm
                return v & 0xFFFF, {rd}, {rd}
            rs2 = reg(b)
            # Con i = 0 el bit 4 del campo de operando va reservado en cero
            v = (d["CRP_SALU"] << 13) | (0 << 12) | (subop << 9) | \
                (rd << 5) | rs2
            return v & 0xFFFF, {rd}, {rd, rs2}

        raise ErrorEnsamblado(f"'{mn}' no es una instruccion del slot S3")

    def _enc_s4(self, texto, direccion, n, cruda):
        campos = texto.split(None, 1)
        bruto = campos[0].lower()
        ops = campos[1] if len(campos) > 1 else ""
        d = self.d

        if bruto == "halt":
            self.usados.add("halt")
            partes(ops, 0, "halt")
            return (d["BRU_HALT"] << 13) & 0xFFFF, set(), set(), False

        # Sufijo de condicion: br.eq, jal.al, jr.auth ...
        if "." in bruto:
            mn, suf = bruto.split(".", 1)
        else:
            mn, suf = bruto, "al"

        if suf not in self.cond:
            raise ErrorEnsamblado(
                f"condicion desconocida: '.{suf}'. "
                f"Son {', '.join(sorted(self.cond))}")
        cond = self.cond[suf]

        if mn in self.bru_rel:
            self.usados.add(mn)
            a, = partes(ops, 1, mn)
            destino_txt = a.strip()
            if RE_ETIQ.match(destino_txt):
                if destino_txt not in self.etiquetas:
                    raise ErrorEnsamblado(f"etiqueta no definida: '{destino_txt}'")
                destino = self.etiquetas[destino_txt]
            else:
                destino = inmediato(destino_txt)
            # destino = pc + 16 * (1 + desp)  =>  desp = (destino - pc)/16 - 1
            delta = destino - direccion
            if delta % BUNDLE_BYTES:
                raise ErrorEnsamblado(
                    f"el destino 0x{destino:X} no esta alineado a bundle")
            desp = delta // BUNDLE_BYTES - 1
            if not cabe_con_signo(desp, 10):
                raise ErrorEnsamblado(
                    f"salto fuera de alcance: hacen falta {desp} bundles y el "
                    f"campo tiene 10 bits con signo (-512 a 511)")
            v = (self.bru_rel[mn] << 13) | (cond << 10) | a_campo(desp, 10)
            escribe = {15} if mn == "jal" else set()
            # Un salto incondicional no mira el PSW; AUTH no lo escribe una
            # comparacion, asi que tampoco cuenta para esta regla
            lee = set() if suf in ("al", "auth") else {BANDERAS}
            return v & 0xFFFF, escribe, lee, True

        if mn in self.bru_ind:
            self.usados.add(mn)
            a, = partes(ops, 1, mn)
            rs = reg(a)
            v = (self.bru_ind[mn] << 13) | (cond << 10) | (rs << 5)
            escribe = {15} if mn == "jalr" else set()
            lee = {rs} if suf in ("al", "auth") else {rs, BANDERAS}
            return v & 0xFFFF, escribe, lee, True

        raise ErrorEnsamblado(f"'{bruto}' no es una instruccion del slot S4 (BRU)")

    # -- segunda pasada ------------------------------------------------------

    def segunda_pasada(self):
        self.salida = []           # (direccion, valor de 128 bits, n, texto)
        escrituras_previas = []    # por bundle: conjunto de registros escritos
        salto_previo = False

        for direccion, slots, n, cruda in self.bundles:
            valores = [0, 0, 0, 0, 0]
            escribe_bundle = {}
            lee_bundle = set()
            hay_salto = False

            for i, texto in enumerate(slots):
                if texto in ("-", ""):
                    self.usados.add("nop")
                    continue
                if texto.split()[0].lower() == "nop":
                    self.usados.add("nop")
                    continue
                try:
                    if i in (0, 1):
                        v, esc, lee = self._enc_alu(texto, i, n, cruda)
                    elif i == 2:
                        v, esc, lee = self._enc_lsu(texto, n, cruda)
                    elif i == 3:
                        v, esc, lee = self._enc_s3(texto, n, cruda)
                    else:
                        v, esc, lee, hay_salto = self._enc_s4(
                            texto, direccion, n, cruda)
                except ErrorEnsamblado as e:
                    self._error(f"{NOMBRE_SLOT[i]}: {e.mensaje}", n, cruda)
                    continue

                valores[i] = v
                lee_bundle |= lee
                for r in esc:
                    if r in escribe_bundle:
                        self._error(
                            f"dos slots escriben {nombre_recurso(r)} en el "
                            f"mismo bundle: {escribe_bundle[r]} y "
                            f"{NOMBRE_SLOT[i]}", n, cruda)
                    else:
                        escribe_bundle[r] = NOMBRE_SLOT[i]

            # Advertencia: salto en el delay slot de otro salto (v1.2 del ISA)
            if hay_salto and salto_previo:
                self._advertir(
                    "hay un salto en el delay slot de otro salto. La v1.2 del "
                    "ISA lo prohibe: los dos surten efecto encadenados y el "
                    "destino del primero se ejecuta un solo bundle", n)
            salto_previo = hay_salto

            # Advertencia de latencia: productor a menos de 3 bundles
            if lee_bundle:
                for atras in (1, 2):
                    if len(escrituras_previas) >= atras:
                        previas = escrituras_previas[-atras]
                        choque = sorted(lee_bundle & previas)
                        if choque:
                            nombres = ", ".join(nombre_recurso(r) for r in choque)
                            self._advertir(
                                f"lectura de {nombres} a solo {atras} "
                                f"bundle(s) de su productor; el ISA exige 3 y "
                                f"el hardware va a entregar el valor viejo", n)
            escrituras_previas.append(set(escribe_bundle))

            palabra = 0
            for i in range(5):
                palabra = (palabra << ANCHO_SLOT[i]) | valores[i]
            self.salida.append((direccion, palabra, n, cruda))

    # -- entrada principal ---------------------------------------------------

    def expandir_includes(self, texto, base, vistos=None, profundidad=0):
        """Sustituye cada .include por el contenido del archivo.

        Se hace ANTES de las dos pasadas y no durante, para que las etiquetas y
        las direcciones salgan de un solo flujo de lineas. El archivo incluido
        se busca junto al que lo incluye, que es lo que espera cualquiera que
        escriba .include "div32.s" desde la misma carpeta.
        """
        if vistos is None:
            vistos = set()
        if profundidad > 16:
            self._error(".include anidado demasiado profundo")
            return texto

        salida = []
        for n, cruda in enumerate(texto.splitlines(), start=1):
            limpia = cruda.split("//")[0].strip()
            if not limpia.lower().startswith(".include"):
                salida.append(cruda)
                continue
            resto = limpia[len(".include"):].strip()
            if len(resto) >= 2 and resto[0] in "\"'" and resto[-1] == resto[0]:
                resto = resto[1:-1]
            ruta = (Path(base).parent / resto).resolve()
            if ruta in vistos:
                # Incluir dos veces el mismo archivo duplicaria sus etiquetas,
                # asi que el segundo se ignora en silencio, como una guarda de
                # cabecera. Es lo que hace falta cuando dos programas incluyen
                # la misma rutina.
                continue
            if not ruta.is_file():
                self._error(f".include: no se encontro '{resto}'", n, cruda)
                continue
            vistos.add(ruta)
            salida.append(f"// ---- .include {resto} ----")
            salida.append(self.expandir_includes(
                ruta.read_text(encoding="utf-8"), ruta, vistos, profundidad + 1))
        return "\n".join(salida)

    def ensamblar(self, texto, base=None):
        if base is not None:
            texto = self.expandir_includes(texto, base)
        lineas = texto.splitlines()
        self.primera_pasada(lineas)
        self.segunda_pasada()
        return not self.errores

    # -- emision -------------------------------------------------------------

    def hex_imem(self, num_bundles=None):
        """Lineas de 32 digitos hexadecimales, una por bundle, desde la 0."""
        if not self.salida:
            return []
        tope = max(d for d, _, _, _ in self.salida) // BUNDLE_BYTES + 1
        if num_bundles is not None:
            tope = max(tope, num_bundles)
        palabras = [0] * tope
        for direccion, palabra, _, _ in self.salida:
            palabras[direccion // BUNDLE_BYTES] = palabra
        return [f"{p:032X}" for p in palabras]

    def hex_dmem(self, num_words=None):
        """Lineas de 8 digitos hexadecimales, una por palabra, desde la 0."""
        if not self.datos:
            return []
        tope = max(self.datos) // 4 + 1
        if num_words is not None:
            tope = max(tope, num_words)
        palabras = [0] * tope
        for direccion, b in self.datos.items():
            palabras[direccion // 4] |= b << (8 * (direccion % 4))
        return [f"{p:08X}" for p in palabras]

    def listado(self):
        lineas = []
        for direccion, palabra, n, cruda in self.salida:
            lineas.append(
                f"{direccion:08X}  {palabra:032X}  {n:4d}  {cruda.rstrip()}")
        if self.etiquetas:
            lineas.append("")
            lineas.append("Etiquetas:")
            for nombre, direccion in sorted(
                    self.etiquetas.items(), key=lambda kv: kv[1]):
                lineas.append(f"  {direccion:08X}  {nombre}")
        return lineas

    def cobertura(self):
        """Devuelve (usados, faltantes) sobre el conjunto completo."""
        return sorted(self.usados), sorted(self.todos - self.usados)


# =============================================================================
# Linea de comandos
# =============================================================================


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Ensamblador de CERBERO-1")
    ap.add_argument("fuente", help="archivo .s de entrada")
    ap.add_argument("-o", "--salida", help="archivo .hex para IMEM")
    ap.add_argument("--datos", help="archivo .hex para DMEM")
    ap.add_argument("--listado", help="archivo de listado")
    ap.add_argument("--defs", default=None,
                    help="ruta de cerbero_defs.svh "
                         "(por omision, ../src/cpu/ junto a esta herramienta)")
    ap.add_argument("--bundles", type=int, default=None,
                    help="rellena el .hex de IMEM hasta esta cantidad de "
                         "bundles, para que $readmemh no avise")
    ap.add_argument("--palabras", type=int, default=None,
                    help="rellena el .hex de DMEM hasta esta cantidad de palabras")
    ap.add_argument("--cobertura", action="store_true",
                    help="informa que mnemonicos del conjunto no se usaron")
    args = ap.parse_args(argv)

    if args.defs:
        ruta_defs = Path(args.defs)
    else:
        ruta_defs = Path(__file__).resolve().parent.parent / \
            "src" / "cpu" / "cerbero_defs.svh"
    if not ruta_defs.is_file():
        print(f"error: no se encontro cerbero_defs.svh en {ruta_defs}",
              file=sys.stderr)
        return 2

    defs = cargar_defs(ruta_defs)
    asm = Ensamblador(defs)

    texto = Path(args.fuente).read_text(encoding="utf-8")
    ok = asm.ensamblar(texto, base=args.fuente)

    for a in asm.advertencias:
        print(f"advertencia: {a}", file=sys.stderr)

    if not ok:
        for e in asm.errores:
            print(f"error: {e}", file=sys.stderr)
        print(f"\n{len(asm.errores)} error(es): no se emitio binario",
              file=sys.stderr)
        return 1

    if args.salida:
        lineas = asm.hex_imem(args.bundles)
        Path(args.salida).write_text("\n".join(lineas) + "\n")
        print(f"{args.salida}: {len(lineas)} bundles")

    if args.datos:
        lineas = asm.hex_dmem(args.palabras)
        Path(args.datos).write_text("\n".join(lineas) + "\n")
        print(f"{args.datos}: {len(lineas)} palabras")

    if args.listado:
        Path(args.listado).write_text("\n".join(asm.listado()) + "\n")
        print(f"{args.listado}: listado")

    if args.cobertura:
        usados, faltantes = asm.cobertura()
        print(f"\ncobertura: {len(usados)} de {len(usados) + len(faltantes)} "
              f"mnemonicos")
        if faltantes:
            print("sin usar: " + ", ".join(faltantes))

    return 0


if __name__ == "__main__":
    sys.exit(main())
