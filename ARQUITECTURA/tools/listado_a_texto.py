#!/usr/bin/env python3
"""
listado_a_texto.py - El texto de cada bundle, para la traza de tb_programa.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Lee el listado que genera cerbero_asm.py --listado y escribe un archivo con
una linea por bundle: la direccion en hexadecimal y el texto del bundle,
resumido para que entre en una columna de la traza.

    listado_a_texto.py programa.lst -o programa_texto.txt

El resumen deja solo las operaciones del bundle, separadas por " | ", sin los
slots vacios ni los comentarios:

    - | - | - | authw #0, r1 ;              ->  authw #0, r1
    mfpsw r11 | - | sw r10, #4(r13) ;       ->  mfpsw r11 | sw r10, #4(r13)
    - ;                                     ->  -

tb_programa.sv lo carga con +TEXTO= y muestra ese texto en lugar de solo la
direccion de cada bundle.
"""

import argparse
import re
import sys
from pathlib import Path

# Una linea de bundle en el listado:
#   direccion (8 hex)  bundle (32 hex)  numero de linea  texto fuente
LINEA_DE_BUNDLE = re.compile(
    r"^([0-9A-Fa-f]{8})\s+[0-9A-Fa-f]{32}\s+\d+\s+(.*)$")


def resumir(texto_fuente):
    """Deja solo las operaciones del bundle, sin slots vacios ni comentarios."""
    sin_comentario = texto_fuente.split("//", 1)[0]
    # Una etiqueta al principio de la linea ("lazo:") no es una operacion
    sin_comentario = re.sub(r"^\s*[A-Za-z_]\w*:\s*", "", sin_comentario)
    sin_punto_y_coma = sin_comentario.strip().rstrip(";").strip()
    operaciones = [op.strip() for op in sin_punto_y_coma.split("|")]
    operaciones = [re.sub(r"\s+", " ", op) for op in operaciones
                   if op and op != "-"]
    return " | ".join(operaciones) if operaciones else "-"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Texto de cada bundle a partir del listado del ensamblador")
    ap.add_argument("listado", help="archivo de cerbero_asm.py --listado")
    ap.add_argument("-o", "--salida", required=True,
                    help="archivo de texto para tb_programa (+TEXTO=)")
    args = ap.parse_args(argv)

    lineas_de_salida = []
    for linea in Path(args.listado).read_text().splitlines():
        coincidencia = LINEA_DE_BUNDLE.match(linea)
        if coincidencia:
            direccion, texto_fuente = coincidencia.groups()
            lineas_de_salida.append(f"{direccion} {resumir(texto_fuente)}")

    Path(args.salida).write_text("\n".join(lineas_de_salida) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())