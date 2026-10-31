#!/usr/bin/env python3
"""
llave.py - La llave de cifrado de archivos, desde la linea de comandos.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

La llave que usan cifrar_archivo.s y descifrar_archivo.s vive en
cargar_llave.s, escrita como ocho instrucciones MOVI y MOVH. Para cifrar con
otra llave sin editar el ensamblador a mano, esta herramienta genera una copia
de los programas con la llave cambiada:

    llave.py 0xA1B2C3D4,0x11223344,0x55667788,0x99AABBCC --salida dir/
    llave.py A1B2C3D4112233445566778899AABBCC --salida dir/

y el makefile la ensambla desde ahi. Los programas originales no se tocan.

-----------------------------------------------------------------------------
COMO SE LEE LA LLAVE
-----------------------------------------------------------------------------
Es la key[4] de la implementacion de referencia del enunciado (Fig. 1), donde
la ronda i usa key[i]. Se acepta de dos formas:

  cuatro palabras separadas por coma   key[0],key[1],key[2],key[3]
  un solo numero de 32 digitos hex     key[0] son los PRIMEROS 8 digitos

En la segunda forma el numero se lee como se escribe: los primeros ocho
digitos son key[0] y los ultimos ocho son key[3]. La herramienta imprime
siempre como quedo cada key[i], para que se pueda comprobar de un vistazo.
"""

import argparse
import re
import sys
from pathlib import Path

# La llave por omision, la misma que trae cargar_llave.s
LLAVE_POR_OMISION = [0x11111111, 0x22222222, 0x33333333, 0x44444444]

# Los registros donde cargar_llave.s arma key[0] a key[3], en ese orden
REGISTROS_LLAVE = ["r5", "r6", "r7", "r8"]

# Los programas de archivo y los fragmentos que incluyen
PROGRAMAS = ["cifrar_archivo.s", "descifrar_archivo.s",
             "cargar_llave.s", "vault_sesion.s"]


def leer_llave(texto):
    """Devuelve key[0..3] como cuatro enteros de 32 bits.

    Rechaza todo lo que no sea exactamente 128 bits, porque una llave con un
    digito de menos cifraria con otra llave sin dar ningun aviso.
    """
    limpio = texto.strip().replace("_", "")
    if "," in limpio:
        partes = [p.strip() for p in limpio.split(",")]
        if len(partes) != 4:
            raise ValueError(
                f"la llave tiene {len(partes)} palabras y deben ser 4")
        palabras = []
        for i, p in enumerate(partes):
            digitos = p[2:] if p.lower().startswith("0x") else p
            if not re.fullmatch(r"[0-9a-fA-F]{1,8}", digitos):
                raise ValueError(
                    f"key[{i}] = '{p}' no es una palabra hexadecimal de "
                    f"32 bits")
            palabras.append(int(digitos, 16))
        return palabras

    digitos = limpio[2:] if limpio.lower().startswith("0x") else limpio
    if not re.fullmatch(r"[0-9a-fA-F]{32}", digitos):
        raise ValueError(
            f"'{texto}' no es una llave de 128 bits: se esperan 32 digitos "
            f"hexadecimales, o cuatro palabras separadas por coma")
    return [int(digitos[8 * i:8 * i + 8], 16) for i in range(4)]


def con_llave(fuente, llave):
    """Devuelve el texto de cargar_llave.s con la llave cambiada.

    Reemplaza el inmediato de los ocho MOVI y MOVH de r5 a r8: la mitad baja
    de cada palabra va en el MOVI y la alta en el MOVH. Exige encontrar
    exactamente esos ocho, para que un cambio en cargar_llave.s rompa aqui y
    no produzca en silencio un programa con la llave a medias.
    """
    cuenta = 0

    def sustituir(m):
        nonlocal cuenta
        cuenta += 1
        op, reg = m.group(1).lower(), m.group(2).lower()
        palabra = llave[REGISTROS_LLAVE.index(reg)]
        mitad = palabra & 0xFFFF if op == "movi" else palabra >> 16
        return f"{m.group(1)} {m.group(2)}, #0x{mitad:04X}"

    patron = re.compile(r"\b(movi|movh)\s+(r[5-8])\s*,\s*#0x[0-9A-Fa-f]+",
                        re.IGNORECASE)
    texto = patron.sub(sustituir, fuente)
    if cuenta != 8:
        raise ValueError(
            f"se esperaban 8 MOVI/MOVH sobre r5 a r8 en cargar_llave.s y hay "
            f"{cuenta}")
    return texto


def formato(llave):
    return "  ".join(f"key[{i}]={p:08X}" for i, p in enumerate(llave))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Genera los programas de archivo con otra llave")
    ap.add_argument("llave", help="key[0],key[1],key[2],key[3] o 32 digitos hex")
    modo = ap.add_mutually_exclusive_group(required=True)
    modo.add_argument("--salida",
                      help="directorio donde escribir los programas")
    modo.add_argument("--hex", action="store_true",
                      help="solo imprime la llave como 32 digitos, key[0] "
                           "primero, que es como la toman los testbenches")
    ap.add_argument("--programas",
                    default=str(Path(__file__).resolve().parent / "programas"),
                    help="directorio de los programas originales")
    args = ap.parse_args(argv)

    try:
        llave = leer_llave(args.llave)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if args.hex:
        print("".join(f"{p:08X}" for p in llave))
        return 0

    origen, destino = Path(args.programas), Path(args.salida)
    destino.mkdir(parents=True, exist_ok=True)
    for nombre in PROGRAMAS:
        texto = (origen / nombre).read_text(encoding="utf-8")
        if nombre == "cargar_llave.s":
            try:
                texto = con_llave(texto, llave)
            except ValueError as e:
                print(f"error: {e}", file=sys.stderr)
                return 1
        (destino / nombre).write_text(texto, encoding="utf-8")

    print(f"llave  {formato(llave)}")
    print(f"programas con esa llave en {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
