#!/usr/bin/env python3
"""
probar_llave.py - Pruebas de llave.py.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Una llave mal leida no da error: cifra con otra llave y el resultado sale
distinto sin que nada avise. Por eso aqui se fija contra valores escritos a
mano el orden de key[0..3] en las dos formas de escribirla, y que el programa
generado arme exactamente esas palabras en r5 a r8.

    python3 probar_llave.py
"""

import contextlib
import io
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import llave                                              # noqa: E402

AQUI = Path(__file__).resolve().parent
casos = 0
fallidos = 0


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


def falla(nombre, texto, fragmento):
    global casos, fallidos
    casos += 1
    try:
        llave.leer_llave(texto)
    except ValueError as e:
        if fragmento in str(e):
            print(f"  ok     {nombre}")
            return
        fallidos += 1
        print(f"  FALLA  {nombre}")
        print(f"           fallo por otro motivo: {e}")
        return
    fallidos += 1
    print(f"  FALLA  {nombre}")
    print("           no fallo y debia fallar")


def palabras_armadas(texto):
    """Reconstruye r5 a r8 a partir de los MOVI y MOVH del programa."""
    reg = {}
    for op, r, v in re.findall(r"\b(movi|movh)\s+(r[5-8])\s*,\s*#0x([0-9A-F]+)",
                               texto, re.IGNORECASE):
        v = int(v, 16)
        if op.lower() == "movi":
            reg[r] = (reg.get(r, 0) & 0xFFFF0000) | v
        else:
            reg[r] = (reg.get(r, 0) & 0x0000FFFF) | (v << 16)
    return [reg.get(r) for r in llave.REGISTROS_LLAVE]


ESPERADA = [0xA1B2C3D4, 0x11223344, 0x55667788, 0x99AABBCC]

print("=== probar_llave: la llave desde la linea de comandos ===")
print("")
print("[1] las dos formas de escribirla dan la misma key[0..3]")

check("cuatro palabras con 0x, key[0] primero",
      llave.leer_llave("0xA1B2C3D4,0x11223344,0x55667788,0x99AABBCC")
      == ESPERADA)
check("cuatro palabras sin 0x y con espacios",
      llave.leer_llave("a1b2c3d4, 11223344, 55667788, 99aabbcc") == ESPERADA)
check("32 digitos: key[0] son los primeros ocho",
      llave.leer_llave("A1B2C3D4112233445566778899AABBCC") == ESPERADA)
check("32 digitos con 0x y guiones bajos",
      llave.leer_llave("0xA1B2C3D4_11223344_55667788_99AABBCC") == ESPERADA)
check("una palabra corta vale lo mismo que con ceros a la izquierda",
      llave.leer_llave("1,2,3,4") == [1, 2, 3, 4])

print("")
print("[2] lo que debe fallar")

falla("tres palabras", "1,2,3", "deben ser 4")
falla("cinco palabras", "1,2,3,4,5", "deben ser 4")
falla("una palabra de mas de 32 bits", "1,2,3,123456789", "key[3]")
falla("una palabra que no es hexadecimal", "1,2,xyz,4", "key[2]")
falla("31 digitos", "A1B2C3D4112233445566778899AABBC", "128 bits")
falla("33 digitos", "A1B2C3D4112233445566778899AABBCC0", "128 bits")

print("")
print("[3] el programa generado arma esa llave en r5 a r8")

fuente = (AQUI / "programas" / "cargar_llave.s").read_text(encoding="utf-8")
check("el cargar_llave.s original arma la llave por omision",
      palabras_armadas(fuente) == llave.LLAVE_POR_OMISION,
      [f"{p:08X}" if p is not None else None
       for p in palabras_armadas(fuente)])

generado = llave.con_llave(fuente, ESPERADA)
check("el generado arma key[0..3] en r5, r6, r7 y r8",
      palabras_armadas(generado) == ESPERADA,
      [f"{p:08X}" if p is not None else None
       for p in palabras_armadas(generado)])

# La credencial vive en r1 a r4 y no se toca
def credencial(texto):
    return re.findall(r"\b(?:movi|movh)\s+r[1-4]\s*,\s*#0x[0-9A-F]+", texto,
                      re.IGNORECASE)


check("y deja intacta la credencial de r1 a r4",
      credencial(generado) == credencial(fuente))

# Si cargar_llave.s cambiara de forma, la herramienta tiene que negarse
casos += 1
try:
    llave.con_llave("movi r5, #0x1111 ;\n", ESPERADA)
    fallidos += 1
    print("  FALLA  rechaza un cargar_llave.s sin los ocho MOVI/MOVH")
except ValueError:
    print("  ok     rechaza un cargar_llave.s sin los ocho MOVI/MOVH")

print("")
print("[4] la linea de comandos")

with tempfile.TemporaryDirectory() as tmp:
    with contextlib.redirect_stdout(io.StringIO()):
        r = llave.main(["A1B2C3D4112233445566778899AABBCC", "--salida", tmp])
    check("escribe los cuatro programas", r == 0 and all(
        (Path(tmp) / n).is_file() for n in llave.PROGRAMAS), r)
    check("y el cargar_llave.s escrito tiene la llave pedida",
          palabras_armadas((Path(tmp) / "cargar_llave.s").read_text(
              encoding="utf-8")) == ESPERADA)
    with contextlib.redirect_stdout(io.StringIO()), \
            contextlib.redirect_stderr(io.StringIO()):
        r = llave.main(["123", "--salida", tmp])
    check("una llave invalida termina con error", r == 1, r)

salida = io.StringIO()
with contextlib.redirect_stdout(salida):
    r = llave.main(["0xA1B2C3D4,0x11223344,0x55667788,0x99AABBCC", "--hex"])
check("--hex imprime los 32 digitos con key[0] primero",
      r == 0 and salida.getvalue().strip()
      == "A1B2C3D4112233445566778899AABBCC", salida.getvalue())

print("---")
print(f"casos: {casos}   fallidos: {fallidos}")
if fallidos:
    print("RESULTADO: FALLA")
    sys.exit(1)
print("RESULTADO: OK")
