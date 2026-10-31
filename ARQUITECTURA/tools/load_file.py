#!/usr/bin/env python3
"""
load_file.py - Convierte un archivo en la imagen de memoria de datos.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Es el punto 7 del plan del grupo: el programa que toma un archivo y lo pasa a
binario para que el procesador lo cifre. La salida es un archivo de texto con
una palabra de 32 bits por linea, apto para $readmemh, que es como se carga
dmem.sv.

    load_file.py entrada.txt -o datos.hex
    load_file.py foto.png -o datos.hex --base 0x4000 --palabras 16384
    load_file.py cifrado.bin -o datos.hex --cifrado
    load_file.py criptograma_externo.bin -o datos.hex --crudo
    load_file.py --input archivo.txt --output memory.mem --address 0x4000

La ultima forma es la del enunciado (5.4.3). Las opciones en ingles son
sinonimos de las de siempre: --input de la entrada, --output de -o y --address
de --base.

El formato del buffer esta en formato_buffer.py, que es el mismo modulo que usa
extract_data.py para leerlo de vuelta.

-----------------------------------------------------------------------------
POR QUE LA SALIDA EMPIEZA EN LA PALABRA CERO
-----------------------------------------------------------------------------
$readmemh carga desde la posicion 0 del arreglo, no desde una direccion
arbitraria, asi que el archivo tiene que traer ceros desde el principio hasta
donde arranca el buffer. Con la base por omision, 0x4000, eso son 4096 palabras
de ceros antes de los datos.

Se podria usar una marca @4000 y dejar que $readmemh salte, pero entonces el
resto de la memoria queda sin inicializar y cualquier lectura de una variable
global devolveria valores indefinidos, que es justo lo que las cabeceras de
imem.sv y dmem.sv explican que hay que evitar. Rellenar es mas barato que
depurar una X en una forma de onda.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from formato_buffer import (BASE_POR_OMISION, BYTES_POR_BLOQUE,   # noqa: E402
                            de_bloques, de_contenedor, empaquetar,
                            escribir_hex)


# La memoria de datos de top.sv: 16 384 palabras de 32 bits, 64 KB
PALABRAS_DE_LA_MEMORIA = 16384


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Convierte un archivo en una imagen de DMEM para CERBERO-1")
    # Los nombres en ingles son los de la interfaz del enunciado (5.4.3); los
    # en espanol son los de siempre. Los dos funcionan igual.
    ap.add_argument("entrada", nargs="?", default=None,
                    help="archivo a cargar")
    ap.add_argument("--input", dest="input_", default=None,
                    help="lo mismo que la entrada posicional")
    ap.add_argument("-o", "--salida", "--output", dest="salida", required=True,
                    help="archivo .hex de salida, para $readmemh")
    ap.add_argument("--base", "--address", dest="base",
                    default=hex(BASE_POR_OMISION),
                    help="direccion de byte donde arranca el buffer "
                         f"(por omision {BASE_POR_OMISION:#x}, la region de "
                         "buffers del mapa de memoria)")
    ap.add_argument("--palabras", type=int, default=PALABRAS_DE_LA_MEMORIA,
                    help="tamano de la memoria de datos en palabras de 32 "
                         f"bits (por omision {PALABRAS_DE_LA_MEMORIA}, los "
                         "64 KB de DMEM). La salida se rellena hasta ese "
                         "tamano y un archivo que no quepa es un error")
    modo = ap.add_mutually_exclusive_group()
    modo.add_argument("--cifrado", action="store_true",
                      help="la entrada es un contenedor de extract_data.py "
                           "--cifrado: se carga tal cual, sin cabecera nueva")
    modo.add_argument("--crudo", action="store_true",
                      help="la entrada es un criptograma sin cabecera, "
                           "cifrado fuera del proyecto: se carga como bloques "
                           "puros")
    args = ap.parse_args(argv)

    if (args.entrada is None) == (args.input_ is None):
        print("error: el archivo de entrada se da una vez, como argumento o "
              "con --input", file=sys.stderr)
        return 2
    entrada = args.entrada if args.entrada is not None else args.input_

    base = int(args.base, 0)
    if base % 4:
        print(f"error: la base {base:#x} no esta alineada a palabra",
              file=sys.stderr)
        return 2

    if not Path(entrada).is_file():
        print(f"error: no se encontro el archivo {entrada}", file=sys.stderr)
        return 1
    datos = Path(entrada).read_bytes()
    if args.cifrado or args.crudo:
        try:
            cuerpo = (de_contenedor if args.cifrado else de_bloques)(datos)
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
    else:
        cuerpo = empaquetar(datos)

    # Ceros desde la palabra 0 hasta la base, y despues el buffer
    palabras = [0] * (base // 4) + cuerpo

    if args.palabras is not None and len(palabras) > args.palabras:
        print(f"error: el buffer necesita {len(palabras)} palabras y el limite "
              f"es {args.palabras}", file=sys.stderr)
        return 1

    total = escribir_hex(args.salida, palabras, args.palabras)

    print(f"{entrada}: {len(datos)} bytes")
    print(f"  base            {base:#010x}")
    print(f"  zona usada      {base:#010x} a {base + 4 * len(cuerpo) - 1:#010x}"
          f" ({4 * len(cuerpo)} bytes, cabecera incluida)")
    print(f"  bloques de 64 b {cuerpo[1]}")
    if args.cifrado:
        print(f"  contenedor cifrado de un original de {cuerpo[0]} bytes")
    elif args.crudo:
        print("  criptograma crudo: el tamano original no se conoce y el "
              "descifrado incluira el relleno")
    else:
        relleno = (-len(datos)) % BYTES_POR_BLOQUE
        print(f"  relleno         {relleno} byte(s) en cero")
    print(f"{args.salida}: {total} palabras")
    return 0


if __name__ == "__main__":
    sys.exit(main())