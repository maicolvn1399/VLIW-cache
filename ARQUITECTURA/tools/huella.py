#!/usr/bin/env python3
"""
huella.py - La huella verificable del cifrado de CERBERO.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Imprime el SHA-256 del criptograma que produjo el procesador, junto al de la
implementacion de referencia en Python. Si los dos coinciden, el hardware
implementa Feistel4; y como el SHA-256 es estandar, cualquiera puede calcular
el suyo con su propia implementacion y comparar una sola linea.

    python3 tools/huella.py archivo.txt
    python3 tools/huella.py archivo.txt --llave A1B2C3D4,11223344,55667788,99AABBCC
    python3 tools/huella.py --volcado cifrado_volcado.hex --original archivo.txt

-----------------------------------------------------------------------------
PARA QUE SIRVE
-----------------------------------------------------------------------------
Decir "el cifrado funciona" no se puede comprobar desde afuera. Un numero de
64 digitos que sale de una funcion estandar, si. Esta herramienta existe para
que la pregunta "a ver, cifre esto y digame el hash" tenga una respuesta en un
comando, y para que esa respuesta sea comparable contra una implementacion
hecha por otra persona sin ponerse de acuerdo en nada mas que el algoritmo.

-----------------------------------------------------------------------------
QUE SE LE APLICA EL HASH, EXACTAMENTE
-----------------------------------------------------------------------------
Esto es lo que hay que fijar para que dos huellas sean comparables, y es donde
se pierden la mitad de las comparaciones entre implementaciones distintas:

  1. El archivo se rellena con CEROS hasta un multiplo de 8 bytes. Feistel4
     trabaja sobre bloques de 64 bits y casi ningun archivo mide un multiplo
     exacto de 8.

  2. Cada bloque de 8 bytes se parte en dos palabras de 32 bits LITTLE-ENDIAN.
     La primera es L y la segunda es R, que es el mismo orden de un par de
     registros Pn = R(2n):R(2n+1).

  3. Se aplican las cuatro rondas con key[0] a key[3], en ese orden.

  4. Las dos palabras resultantes vuelven a bytes en little-endian.

  5. El SHA-256 se calcula sobre esos bytes y SOLO sobre esos: los
     `8 x bloques` bytes del criptograma, SIN la cabecera de 8 bytes que
     load_file.py pone en memoria. La cabecera es del formato del buffer, no
     del cifrado, y meterla cambiaria la huella sin que el algoritmo tenga
     nada que ver.

Se imprime tambien el SHA-256 del archivo en claro, que sirve de control: si
ese no coincide es que los dos no estan cifrando el mismo archivo, y no tiene
sentido mirar el otro.

-----------------------------------------------------------------------------
DE DONDE SALE CADA UNO DE LOS DOS NUMEROS
-----------------------------------------------------------------------------
  hardware    De la memoria de datos del procesador despues de correr
              cifrar_archivo.s sobre el RTL. Es el volcado de $writememh que
              deja el testbench, leido con extract_data.py.

  referencia  De las cuatro lineas de Python que hay mas abajo, escritas solo
              desde la formula del enunciado. No comparten nada con el RTL ni
              con el ensamblador.

Que coincidan es la comprobacion cruzada; que el de referencia coincida con el
de un tercero es la comprobacion externa.
"""

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

from formato_buffer import empaquetar, leer_hex, BASE_POR_OMISION   # noqa: E402

M = 0xFFFFFFFF
LLAVE_POR_OMISION = [0x11111111, 0x22222222, 0x33333333, 0x44444444]


# -----------------------------------------------------------------------------
# El modelo de referencia, escrito solo desde la formula del enunciado
#
#   ROL32(x, r) = ((x << r) | (x >> (32 - r))) y 32 bits
#   F(x, k)     = (ROL32(x, 5) + k) XOR ROL32(x, 13)
#   cifrar: para i de 0 a 3,  (L, R) -> (R, L XOR F(R, key[i]))
# -----------------------------------------------------------------------------

def rol(x, n):
    return ((x << n) | (x >> (32 - n))) & M


def f_ronda(x, k):
    return ((rol(x, 5) + k) & M) ^ rol(x, 13)


def cifrar_bloque(L, R, llave):
    for i in range(4):
        L, R = R, L ^ f_ronda(R, llave[i])
    return L, R


def cifrar_bytes(datos, llave):
    """El criptograma de un archivo: bloques completos, sin cabecera."""
    pal = empaquetar(datos)          # [n_bytes, n_bloques, palabras...]
    n_bloques = pal[1]
    salida = []
    for b in range(n_bloques):
        i = 2 + 2 * b
        salida += list(cifrar_bloque(pal[i], pal[i + 1], llave))
    return b"".join(p.to_bytes(4, "little") for p in salida)


def leer_llave(texto):
    """Acepta las dos formas: cuatro palabras con coma, o 32 digitos."""
    if not texto:
        return list(LLAVE_POR_OMISION)
    t = texto.strip().replace("0x", "").replace("0X", "")
    if "," in t:
        partes = [p.strip() for p in t.split(",")]
        if len(partes) != 4:
            raise SystemExit("error: la llave lleva cuatro palabras de 32 bits")
        return [int(p, 16) & M for p in partes]
    if len(t) != 32:
        raise SystemExit(
            f"error: la llave en una pieza son 32 digitos hexadecimales, "
            f"no {len(t)}")
    return [int(t[i:i + 8], 16) for i in range(0, 32, 8)]


def sha(datos):
    return hashlib.sha256(datos).hexdigest()


def del_hardware(volcado, base):
    """El criptograma que dejo el procesador en su memoria de datos."""
    palabras = leer_hex(volcado)
    i0 = base // 4
    if len(palabras) <= i0 + 1:
        raise SystemExit(
            f"error: el volcado trae {len(palabras)} palabras y el buffer "
            f"empieza en la {i0}. Puede ser una base equivocada")
    n_bloques = palabras[i0 + 1]
    cuerpo = palabras[i0 + 2: i0 + 2 + 2 * n_bloques]
    if len(cuerpo) < 2 * n_bloques:
        raise SystemExit("error: el volcado esta truncado")
    return b"".join((p & M).to_bytes(4, "little") for p in cuerpo), n_bloques


def correr_en_rtl(ruta_archivo, llave_txt):
    """Cifra el archivo en el procesador y devuelve el volcado."""
    build = os.path.join(AQUI, "..", "src", "build")
    if not os.path.isdir(build):
        raise SystemExit(f"error: no encuentro {build}")
    cmd = ["make", "-s", "solo-cifrar",
           f"ARCHIVO={os.path.abspath(ruta_archivo)}"]
    if llave_txt:
        cmd.append(f"LLAVE={llave_txt}")
    r = subprocess.run(cmd, cwd=build, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-3000:])
        sys.stderr.write(r.stderr[-3000:])
        raise SystemExit("error: la simulacion no termino bien")
    volcado = os.path.join(build, "cifrado_libre.hex")
    if not os.path.isfile(volcado):
        raise SystemExit(f"error: la simulacion no dejo {volcado}")
    return volcado


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="SHA-256 del criptograma de CERBERO, para comparar contra "
                    "otra implementacion")
    ap.add_argument("archivo", nargs="?",
                    help="archivo a cifrar; se corre el RTL y se compara")
    ap.add_argument("--volcado",
                    help="usar un volcado de DMEM ya existente en vez de "
                         "correr la simulacion")
    ap.add_argument("--original",
                    help="el archivo en claro que corresponde a ese volcado")
    ap.add_argument("--llave", default="",
                    help="cuatro palabras con coma, o 32 digitos hexadecimales")
    ap.add_argument("--base", default=hex(BASE_POR_OMISION),
                    help="direccion del buffer en DMEM (por omision 0x4000)")
    args = ap.parse_args(argv)

    llave = leer_llave(args.llave)
    base = int(args.base, 0)

    if args.volcado:
        if not args.original:
            raise SystemExit("error: con --volcado hace falta --original")
        claro = open(args.original, "rb").read()
        volcado = args.volcado
    elif args.archivo:
        claro = open(args.archivo, "rb").read()
        print("  corriendo cifrar_archivo.s en el procesador...",
              file=sys.stderr)
        volcado = correr_en_rtl(args.archivo, args.llave)
    else:
        ap.error("hace falta un archivo, o --volcado con --original")

    cif_hw, n_bloques = del_hardware(volcado, base)
    cif_ref = cifrar_bytes(claro, llave)

    nombre = os.path.basename(args.original or args.archivo)
    relleno = (-len(claro)) % 8

    print("")
    print("=== huella del cifrado de CERBERO-1 ===")
    print("")
    print(f"  archivo        {nombre}")
    print(f"  bytes          {len(claro)}  (+{relleno} de relleno "
          f"= {n_bloques} bloques de 64 bits)")
    print(f"  llave          " + " ".join(f"{k:08X}" for k in llave))
    print("")
    print(f"  SHA-256 del claro")
    print(f"    {sha(claro)}")
    print("")
    print(f"  SHA-256 del criptograma, {len(cif_hw)} bytes")
    print(f"    hardware    {sha(cif_hw)}")
    print(f"    referencia  {sha(cif_ref)}")
    print("")

    if cif_hw == cif_ref:
        print("  COINCIDEN: el procesador y el modelo de referencia dan el")
        print("  mismo criptograma byte por byte.")
        print("")
        print("  Para comparar contra otra implementacion, el numero es el de")
        print("  arriba: SHA-256 de los bloques completos, sin la cabecera del")
        print("  buffer. Los primeros bytes del criptograma, por si ayuda:")
        print(f"    {cif_hw[:32].hex()}")
        return 0

    print("  NO COINCIDEN. El primer byte que difiere:")
    for i, (a, b) in enumerate(zip(cif_hw, cif_ref)):
        if a != b:
            print(f"    byte {i}: hardware 0x{a:02x}, referencia 0x{b:02x}")
            print(f"    bloque {i // 8}, palabra {(i % 8) // 4}")
            break
    else:
        print(f"    los tamanos difieren: {len(cif_hw)} y {len(cif_ref)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
