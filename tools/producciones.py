#!/usr/bin/env python3
"""
Extrae las producciones de nova.y sin las acciones en C, para poder comparar
la gramatica real contra la del documento (la seccion de EBNF).

    python3 tools/producciones.py                      # a pantalla
    python3 tools/producciones.py > producciones.txt
    python3 tools/producciones.py --tokens             # solo los terminales

No se puede hacer con un sed de una linea: las acciones tienen llaves
anidadas, y algunas contienen llaves dentro de cadenas de C, como en
"se esperaba ')' pero se encontro '{'". Hay que llevar la cuenta de las
llaves ignorando lo que esta dentro de comillas y de comentarios.
"""

import re
import signal
import sys

# Para que 'python3 tools/producciones.py | head' no reviente con BrokenPipe.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass

RUTA = "fase2_sintactico/nova.y"


def cuerpo_gramatical(texto):
    """Lo que esta entre el primer y el segundo %% de la linea."""
    partes = re.split(r"(?m)^%%[ \t]*$", texto)
    if len(partes) < 2:
        sys.exit("no se encontraron los separadores %% en " + RUTA)
    return partes[1]


def quitar_acciones(cuerpo):
    """
    Borra las acciones { ... } contando la profundidad de llaves, saltando
    las que aparecen dentro de cadenas, caracteres o comentarios de C.
    """
    salida = []
    prof = 0
    i = 0
    n = len(cuerpo)

    while i < n:
        c = cuerpo[i]
        par = cuerpo[i:i + 2]

        # Comentarios: se conservan solo fuera de las acciones.
        if par == "/*":
            fin = cuerpo.find("*/", i + 2)
            fin = n if fin == -1 else fin + 2
            if prof == 0:
                salida.append(cuerpo[i:fin])
            i = fin
            continue

        # Cadenas y caracteres: se copian enteros, sin mirarles las llaves.
        if c in "\"'":
            j = i + 1
            while j < n:
                if cuerpo[j] == "\\":
                    j += 2
                    continue
                if cuerpo[j] == c:
                    j += 1
                    break
                j += 1
            if prof == 0:
                salida.append(cuerpo[i:j])
            i = j
            continue

        if c == "{":
            prof += 1
            i += 1
            continue

        if c == "}":
            if prof > 0:
                prof -= 1
            i += 1
            continue

        if prof == 0:
            salida.append(c)
        elif c == "\n":
            salida.append("\n")      # conserva la estructura de lineas
        i += 1

    return "".join(salida)


def limpiar(texto):
    lineas = []
    for linea in texto.splitlines():
        linea = linea.rstrip()
        if linea.strip() == "":
            # Las lineas que deja una accion borrada se descartan; solo se
            # conserva una linea en blanco antes de empezar otra produccion.
            anterior = lineas[-1] if lineas else ""
            if anterior.lstrip().startswith((":", "|")) or anterior == "":
                continue
            lineas.append("")
            continue
        lineas.append(linea)
    while lineas and lineas[0] == "":
        lineas.pop(0)
    return "\n".join(lineas)


def main():
    try:
        with open(RUTA, encoding="utf-8") as f:
            texto = f.read()
    except OSError as e:
        sys.exit("no se pudo leer %s: %s" % (RUTA, e))

    if "--tokens" in sys.argv:
        tokens = sorted(set(re.findall(r"\bTK_[A-Z_]+\b", texto)))
        print("\n".join(tokens))
        print("\n-- %d terminales --" % len(tokens))
        return

    producciones = limpiar(quitar_acciones(cuerpo_gramatical(texto)))
    print(producciones)

    reglas = len([l for l in producciones.splitlines()
                  if re.match(r"^[a-z_][a-z0-9_]*$", l.strip())])
    print("\n-- %d no terminales, %d lineas --"
          % (reglas, len(producciones.splitlines())))


if __name__ == "__main__":
    main()
