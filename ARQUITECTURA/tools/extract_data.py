#!/usr/bin/env python3
"""
extract_data.py - Recupera un archivo del volcado de la memoria de datos.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Es la inversa de load_file.py: toma el volcado de dmem que produce $writememh
despues de una corrida y vuelve a armar el archivo.

    extract_data.py volcado.hex -o cifrado.bin
    extract_data.py volcado.hex -o salida.txt --base 0x4000
    extract_data.py volcado.hex -o cifrado.bin --cifrado
    extract_data.py --memory volcado.hex --address 0x4008 --size 4096 \
                    --output resultado.bin

La ultima forma es la del enunciado (5.4.3): --size saca exactamente esa
cantidad de bytes desde la direccion, sin mirar la cabecera. Como el buffer
de este proyecto empieza con 8 bytes de cabecera, los datos empiezan en la
base mas 8. Las opciones en ingles son sinonimos de las de siempre: --memory
del volcado, --output de -o y --address de --base.

La cantidad de bytes del archivo original sale de la cabecera del buffer, asi
que el resultado tiene exactamente el tamano que tenia la entrada: el relleno
que hizo falta para completar el ultimo bloque de 64 bits no aparece. Sin esa
cabecera, un archivo que terminara en 0x00 saldria truncado y uno que no
ocupara un multiplo de 8 saldria con basura al final.

Un volcado CIFRADO no se recorta: con --cifrado sale el buffer entero, que es
lo que load_file.py --cifrado necesita para volver a cargarlo y descifrarlo.

El formato del buffer esta en formato_buffer.py, el mismo modulo que usa
load_file.py para escribirlo.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from formato_buffer import (BASE_POR_OMISION, a_contenedor,    # noqa: E402
                            desempaquetar, leer_hex)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Recupera un archivo del volcado de DMEM de CERBERO-1")
    # Los nombres en ingles son los de la interfaz del enunciado (5.4.3); los
    # en espanol son los de siempre. Los dos funcionan igual.
    ap.add_argument("volcado", nargs="?", default=None,
                    help="archivo .hex que volco la simulacion")
    ap.add_argument("--memory", default=None,
                    help="lo mismo que el volcado posicional")
    ap.add_argument("-o", "--salida", "--output", dest="salida", required=True,
                    help="archivo a escribir")
    ap.add_argument("--base", "--address", dest="base",
                    default=hex(BASE_POR_OMISION),
                    help="direccion de byte donde arranca el buffer "
                         f"(por omision {BASE_POR_OMISION:#x})")
    modo = ap.add_mutually_exclusive_group()
    modo.add_argument("--size", type=int, default=None,
                      help="extrae exactamente esta cantidad de bytes desde "
                           "la direccion, sin mirar la cabecera")
    modo.add_argument("--cifrado", action="store_true",
                      help="escribe el buffer entero, cabecera y bloques "
                           "completos, para un volcado cifrado que despues se "
                           "va a descifrar")
    modo.add_argument("--crudo", action="store_true",
                      help="ignora la cabecera y extrae todas las palabras "
                           "tal cual, para mirar un volcado a mano")
    args = ap.parse_args(argv)

    if (args.volcado is None) == (args.memory is None):
        print("error: el volcado se da una vez, como argumento o con --memory",
              file=sys.stderr)
        return 2
    volcado = args.volcado if args.volcado is not None else args.memory

    base = int(args.base, 0)
    if base % 4:
        print(f"error: la base {base:#x} no esta alineada a palabra",
              file=sys.stderr)
        return 2

    try:
        palabras = leer_hex(volcado)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    inicio = base // 4
    if len(palabras) <= inicio:
        print(f"error: el volcado trae {len(palabras)} palabras y el buffer "
              f"empieza en la {inicio}. Puede ser una base equivocada",
              file=sys.stderr)
        return 1

    buffer_ = palabras[inicio:]

    if args.crudo or args.size is not None:
        datos = bytearray()
        for p in buffer_:
            datos += (p & 0xFFFFFFFF).to_bytes(4, "little")
        if args.size is not None:
            if args.size > len(datos):
                print(f"error: se pidieron {args.size} bytes desde {base:#x} "
                      f"y el volcado solo trae {len(datos)}", file=sys.stderr)
                return 1
            datos = datos[:args.size]
        datos = bytes(datos)
        cabecera = "(ignorada)"
    else:
        convertir = a_contenedor if args.cifrado else desempaquetar
        try:
            datos = convertir(buffer_)
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        cabecera = f"{buffer_[0]} bytes en {buffer_[1]} bloque(s)"

    Path(args.salida).write_bytes(datos)

    print(f"{volcado}: {len(palabras)} palabras")
    print(f"  base      {base:#010x}")
    print(f"  cabecera  {cabecera}")
    print(f"{args.salida}: {len(datos)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
