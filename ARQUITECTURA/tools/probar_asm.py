#!/usr/bin/env python3
"""
probar_asm.py - Pruebas del ensamblador de CERBERO-1.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Un ensamblador que acepta todo no sirve de nada: la seccion 10.3 del ISA le pide
rechazar ocho clases de programa invalido, y esa parte es la que no se nota si
esta rota, porque los programas correctos siguen saliendo bien.

Este archivo prueba las dos mitades:

  - que los programas VALIDOS se ensamblen y den el binario esperado, con los
    valores calculados a mano fuera de la herramienta
  - que cada programa INVALIDO se rechace, y que se rechace por el motivo
    correcto y no por otro

Lo segundo importa tanto como lo primero. Un ensamblador que rechazara todo
tambien pasaria una prueba que solo mirara "hubo error", asi que cada caso exige
que el mensaje mencione lo que de verdad esta mal.

    python3 probar_asm.py

Salida en el mismo formato que los testbenches del RTL, para que se lea igual.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cerbero_asm import Ensamblador, cargar_defs   # noqa: E402

RUTA_DEFS = Path(__file__).resolve().parent.parent / "src" / "cpu" / \
    "cerbero_defs.svh"

casos = 0
fallidos = 0


def ensamblar(fuente):
    asm = Ensamblador(cargar_defs(RUTA_DEFS))
    ok = asm.ensamblar(fuente)
    return asm, ok


def check(nombre, condicion, detalle=""):
    global casos, fallidos
    casos += 1
    if condicion:
        print(f"  ok     {nombre}")
    else:
        fallidos += 1
        print(f"  FALLA  {nombre}")
        if detalle:
            for linea in str(detalle).splitlines():
                print(f"           {linea}")


def acepta(nombre, fuente, bundle_esperado=None, indice=0):
    """El programa debe ensamblarse, y opcionalmente dar un bundle concreto."""
    asm, ok = ensamblar(fuente)
    if not ok:
        check(nombre, False, "\n".join(str(e) for e in asm.errores))
        return asm
    if bundle_esperado is None:
        check(nombre, True)
        return asm
    obtenido = asm.salida[indice][1]
    if obtenido == bundle_esperado:
        check(f"{nombre} -> {obtenido:032X}", True)
    else:
        check(nombre, False,
              f"obtenido {obtenido:032X}\nesperado {bundle_esperado:032X}")
    return asm


def rechaza(nombre, fuente, fragmento):
    """El programa debe rechazarse, y el mensaje debe mencionar el fragmento."""
    asm, ok = ensamblar(fuente)
    if ok:
        check(nombre, False, "se ensamblo sin errores y debia rechazarse")
        return
    mensajes = " | ".join(str(e) for e in asm.errores).lower()
    if fragmento.lower() in mensajes:
        check(nombre, True)
    else:
        check(nombre, False,
              f"se rechazo, pero por otro motivo:\n{mensajes}")


def advierte(nombre, fuente, fragmento):
    """El programa debe ensamblarse Y emitir una advertencia concreta."""
    asm, ok = ensamblar(fuente)
    if not ok:
        check(nombre, False,
              "se rechazo y debia ser solo advertencia:\n" +
              "\n".join(str(e) for e in asm.errores))
        return
    texto = " | ".join(asm.advertencias).lower()
    if fragmento.lower() in texto:
        check(nombre, True)
    else:
        check(nombre, False,
              f"no hubo la advertencia esperada. Hubo: {texto or '(ninguna)'}")


# =============================================================================
# 1. Codificacion de programas validos
# =============================================================================

print("=== probar_asm: el ensamblador de CERBERO-1 ===")
print("")
print("[1] codificacion, contra valores calculados a mano")

# add r1, r2, r3 -> opcode 00001, rd=1, rs1=2, rs2=3, reservado en cero
#   (1<<27) | (1<<23) | (2<<19) | (3<<15) = 0x08918000
acepta("add r1, r2, r3 en S0",
       "add r1, r2, r3 ;",
       0x08918000 << 96)

# El mismo en S1, para comprobar que el slot no cambia la codificacion
acepta("el mismo add en S1",
       "- | add r1, r2, r3 ;",
       0x08918000 << 64)

# addi r1, r1, #4 -> este es el ejemplo de la seccion 10.5 del ISA, cuyo valor
# el documento trae mal: rd son los bits 26:23 y cruza dos digitos hexadecimales
acepta("addi r1, r1, #4 (el ejemplo del ISA 10.5)",
       "addi r1, r1, #4 ;",
       0x88880004 << 96)

# lw.inc r2, #0(r0) -> opcode 10110, rd=2, rbase=0, imm=0
acepta("lw.inc r2, #0(r0) en S2",
       "- | - | lw.inc r2, #0(r0) ;",
       0xB1000000 << 32)

# f4e p0, k0, #0 -> 001 | 000 | 00 | 00 | 000000
acepta("f4e p0, k0, #0 en S3",
       "- | - | - | f4e p0, k0, #0 ;",
       0x2000 << 16)

# Inmediato negativo: addi r1, r2, #-1 -> imm19 = 0x7FFFF
acepta("un inmediato negativo se extiende bien",
       "addi r1, r2, #-1 ;",
       ((0b10001 << 27) | (1 << 23) | (2 << 19) | 0x7FFFF) << 96)

# Inmediato en hexadecimal
acepta("inmediato en hexadecimal",
       "andi r1, r2, #0xFF ;",
       ((0b10100 << 27) | (1 << 23) | (2 << 19) | 0xFF) << 96)

# movh usa imm16 en [18:3] y deja cond en cero
acepta("movh pone el inmediato en [18:3]",
       "movh r1, #0xABCD ;",
       ((0b11101 << 27) | (1 << 23) | (0xABCD << 3)) << 96)

# setcc pone el codigo de condicion en [2:0]
acepta("setcc pone la condicion en [2:0]",
       "setcc r1, lt ;",
       ((0b10011 << 27) | (1 << 23) | 0b011) << 96)

# halt en S4
acepta("halt en S4",
       "- | - | - | - | halt ;",
       0xA000)

# Relleno de slots omitidos: una linea con dos campos equivale a cinco
asm = acepta("los slots omitidos se rellenan con NOP",
             "add r1, r2, r3 | sub r4, r5, r6 ;",
             ((0x08918000 << 96) | (0x122B0000 << 64)))

# El guion y nop son equivalentes
a1, _ = ensamblar("- | - | - | - | halt ;")
a2, _ = ensamblar("nop | nop | nop | nop | halt ;")
check("el guion y nop dan el mismo binario",
      a1.salida[0][1] == a2.salida[0][1],
      f"{a1.salida[0][1]:032X} vs {a2.salida[0][1]:032X}")

# Salto relativo: destino = pc + 16*(1+desp). Conviene tener clavados los dos
# casos de borde, porque el "+1" de la formula se olvida con facilidad:
#   desp = 0  ->  el destino es el propio delay slot
#   desp = 1  ->  el destino es el bundle que sigue al delay slot
acepta("desp 0 apunta al delay slot mismo",
       "- | - | - | - | br.al destino ;\ndestino: - ;",
       ((0b001 << 13) | (0 << 10) | 0))

acepta("desp 1 apunta al bundle que sigue al delay slot",
       "- | - | - | - | br.al destino ;\n- ;\ndestino: - ;",
       ((0b001 << 13) | (0 << 10) | 1))

# Salto hacia atras: de 0x20 a 0x00 -> desp = -3
acepta("un salto hacia atras lleva el desplazamiento negativo",
       "atras: - ;\n- ;\n- | - | - | - | br.al atras ;",
       ((0b001 << 13) | (0 << 10) | ((-3) & 0x3FF)), indice=2)

# =============================================================================
# 2. Directivas y datos
# =============================================================================

print("")
print("[2] directivas y seccion de datos")

asm = acepta(".word emite palabras little-endian",
             ".data\n.word 0x11223344, 0x55667788\n.text\n- ;")
check(".word deja las dos palabras en orden",
      asm.hex_dmem()[:2] == ["11223344", "55667788"],
      asm.hex_dmem()[:2])

asm = acepta(".byte y .space colocan bytes sueltos",
             ".data\n.byte 0xAA, 0xBB\n.space 2\n.byte 0xCC\n.text\n- ;")
check(".byte llena los carriles de la palabra",
      asm.hex_dmem()[0] == "0000BBAA",
      asm.hex_dmem()[:2])

asm = acepta(".org mueve la direccion de ensamblado",
             ".text\n.org 0x100\nalla: - ;")
check(".org fija la direccion de la etiqueta",
      asm.etiquetas.get("alla") == 0x100,
      asm.etiquetas)

asm = acepta("una etiqueta en su propia linea",
             ".text\ninicio:\n- ;")
check("la etiqueta en linea propia apunta al bundle siguiente",
      asm.etiquetas.get("inicio") == 0,
      asm.etiquetas)

# =============================================================================
# 3. Las ocho validaciones de la seccion 10.3
# =============================================================================

print("")
print("[3] lo que el ISA 10.3 manda rechazar")

rechaza("dos slots escribiendo el mismo registro",
        "add r1, r2, r3 | sub r1, r4, r5 ;",
        "dos slots escriben r1")

rechaza("dos slots al mismo registro por el par de S3",
        "add r10, r2, r3 | - | - | f4e p5, k0, #0 ;",
        "dos slots escriben r10")

rechaza("dos slots al mismo registro por el postincremento",
        "add r3, r1, r2 | - | lw.inc r4, #0(r3) ;",
        "dos slots escriben r3")

rechaza("una comparacion fuera de S0",
        "- | cmp r1, r2 ;",
        "solo existe en s0")

rechaza("una comparacion con inmediato fuera de S0",
        "- | cmpi r1, #5 ;",
        "solo existe en s0")

rechaza("una instruccion de memoria en el slot de la ALU",
        "lw r1, #0(r2) ;",
        "no es una instruccion del slot alu")

rechaza("una instruccion de la ALU en el slot de memoria",
        "- | - | add r1, r2, r3 ;",
        "no es una instruccion del slot lsu")

rechaza("una instruccion de S3 en el slot de saltos",
        "- | - | - | - | f4e p0, k0, #0 ;",
        "no es una instruccion del slot s4")

rechaza("una unaria de la ALU corta con dos operandos",
        "- | - | - | not.s r3, r4 ;",
        "lleva 1 operando")

rechaza("un desplazamiento de salto fuera de rango",
        ".text\n.org 0\n- | - | - | - | br.al lejos ;\n.org 0x8000\nlejos: - ;",
        "fuera de alcance")

rechaza("un inmediato fuera del rango del campo",
        "addi r1, r2, #262144 ;",
        "no cabe en 19 bits")

rechaza("un inmediato de la ALU corta fuera de rango",
        "- | - | - | add.s r1, #32 ;",
        "no cabe en 5 bits")

rechaza("una etiqueta no definida",
        "- | - | - | - | br.al ninguna_parte ;",
        "etiqueta no definida")

rechaza("una etiqueta definida dos veces",
        "doble: - ;\ndoble: - ;",
        "definida dos veces")

# =============================================================================
# 4. Rangos de operandos
# =============================================================================

print("")
print("[4] rangos de los operandos")

rechaza("un registro que no existe",
        "add r16, r1, r2 ;",
        "fuera de rango")

rechaza("un par que no existe",
        "- | - | - | f4e p8, k0, #0 ;",
        "p0..p7")

# La boveda tiene 4 ranuras, aunque la seccion 10.2 del ISA diga k0..k7
rechaza("una llave fuera de las cuatro ranuras de la boveda",
        "- | - | - | f4e p0, k4, #0 ;",
        "4 ranuras")

rechaza("una ronda fuera de rango",
        "- | - | - | f4e p0, k0, #4 ;",
        "fuera de rango")

rechaza("un indice de palabra fuera de rango en ksetw",
        "- | - | - | ksetw k0, #4, r1 ;",
        "fuera de rango")

rechaza("una condicion de salto que no existe",
        "- | - | - | - | br.xx destino ;\ndestino: - ;",
        "condicion desconocida")

rechaza("una condicion de setcc que no existe",
        "setcc r1, xx ;",
        "condicion desconocida")

# =============================================================================
# 5. Errores de sintaxis
# =============================================================================

print("")
print("[5] sintaxis")

rechaza("un bundle sin punto y coma",
        "add r1, r2, r3",
        "terminar en ';'")

rechaza("un bundle con mas de cinco slots",
        "- | - | - | - | - | - ;",
        "5 slots")

rechaza("una instruccion en la seccion de datos",
        ".data\nadd r1, r2, r3 ;",
        "seccion de datos")

rechaza("una directiva que no existe",
        ".vector 4\n- ;",
        "directiva desconocida")

rechaza("un inmediato mal formado",
        "addi r1, r2, #tres ;",
        "mal formado")

rechaza("faltan operandos",
        "add r1, r2 ;",
        "lleva 3 operando")

rechaza(".org de codigo sin alinear al bundle",
        ".text\n.org 0x104\n- ;",
        "multiplo de 16")

rechaza(".endsecure sin .secure",
        ".endsecure\n- ;",
        "sin .secure")

rechaza("codigo .secure fuera de la region segura",
        ".text\n.org 0\n.secure\n- ;\n.endsecure",
        "fuera de la region segura")

acepta("codigo .secure dentro de la region segura",
       ".text\n.org 0x7000\n.secure\n- ;\n.endsecure")

# =============================================================================
# 6. Lo que es advertencia y no error
# =============================================================================

print("")
print("[6] advertencias, que no detienen el ensamblado")

advierte("leer un registro a un bundle de su productor",
         "movi r1, #5 ;\nadd r2, r1, r3 ;",
         "solo 1 bundle")

advierte("leer un registro a dos bundles de su productor",
         "movi r1, #5 ;\n- ;\nadd r2, r1, r3 ;",
         "solo 2 bundle")

acepta("a tres bundles ya no hay advertencia",
       "movi r1, #5 ;\n- ;\n- ;\nadd r2, r1, r3 ;")
asm, _ = ensamblar("movi r1, #5 ;\n- ;\n- ;\nadd r2, r1, r3 ;")
check("y no se emite ninguna advertencia",
      asm.advertencias == [], asm.advertencias)

# Las banderas son una dependencia igual que un registro, y con la misma regla
# de 3 bundles. Sin esto, la cadena cmp -> setcc de __div32 no se podria
# verificar: ningun registro las conecta.
advierte("setcc a un bundle de su comparacion",
         "cmp r1, r2 ;\nsetcc r3, geu ;",
         "las banderas")

advierte("un salto condicional a un bundle de su comparacion",
         "cmpi r1, #0 ;\n- | - | - | - | br.ne a ;\na: - ;",
         "las banderas")

advierte("mfpsw tambien lee el PSW",
         "cmp r1, r2 ;\n- ;\nmfpsw r3 ;",
         "las banderas")

acepta("a tres bundles de la comparacion ya no hay advertencia",
       "cmp r1, r2 ;\n- ;\n- ;\nsetcc r3, geu ;")

asm, _ = ensamblar("- | - | - | - | br.al a ;\na: - ;")
check("un salto incondicional no depende de las banderas",
      asm.advertencias == [], asm.advertencias)

advierte("un salto en el delay slot de otro salto",
         "- | - | - | - | br.al a ;\n- | - | - | - | br.al b ;\n"
         "a: - ;\nb: - ;",
         "delay slot")

# =============================================================================
# 7. Cobertura del conjunto completo
# =============================================================================

print("")
print("[7] cobertura del conjunto de instrucciones")

ruta_cob = Path(__file__).resolve().parent / "programas" / "cobertura.s"
asm, ok = ensamblar(ruta_cob.read_text(encoding="utf-8"))
check("programas/cobertura.s se ensambla sin errores", ok,
      "\n".join(str(e) for e in asm.errores))
check("y sin advertencias", asm.advertencias == [], asm.advertencias)

usados, faltantes = asm.cobertura()
check(f"usa los {len(usados)} mnemonicos del conjunto, sin faltantes",
      not faltantes, f"sin usar: {', '.join(faltantes)}")

# =============================================================================
# 8. Las tablas vienen del encabezado del RTL
# =============================================================================

print("")
print("[8] las tablas se leen de cerbero_defs.svh")

defs = cargar_defs(RUTA_DEFS)
check("se leyeron los define del encabezado", len(defs) > 100, len(defs))
check("ALU_SETCC vale 10011 como en el RTL", defs.get("ALU_SETCC") == 0b10011,
      defs.get("ALU_SETCC"))
check("ALU_MFPSW vale 11011 como en el RTL", defs.get("ALU_MFPSW") == 0b11011,
      defs.get("ALU_MFPSW"))

# La prueba de que las tablas NO estan escritas aqui: si se renumera un opcode
# en el encabezado, el ensamblador tiene que seguirlo sin tocar una linea.
defs_mod = dict(defs)
defs_mod["ALU_ADD"] = 0b01111
asm_mod = Ensamblador(defs_mod)
asm_mod.ensamblar("add r1, r2, r3 ;")
esperado = ((0b01111 << 27) | (1 << 23) | (2 << 19) | (3 << 15)) << 96
check("renumerar un opcode en el encabezado cambia el binario",
      asm_mod.salida[0][1] == esperado,
      f"{asm_mod.salida[0][1]:032X} vs {esperado:032X}")

# =============================================================================

print("---")
print(f"casos: {casos}   fallidos: {fallidos}")
if fallidos:
    print("RESULTADO: FALLA")
    sys.exit(1)
print("RESULTADO: OK")
