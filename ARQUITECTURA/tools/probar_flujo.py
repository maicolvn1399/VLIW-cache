#!/usr/bin/env python3
"""
probar_flujo.py - El flujo completo, de archivo a archivo.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Cierra la cadena del proyecto sobre un volcado DE VERDAD de la simulacion:

    archivo original
      -> load_file.py            imagen de DMEM
      -> tb_archivo.sv           el procesador cifra  ($writememh)
      -> extract_data.py         el criptograma como contenedor (--cifrado)
      -> modelo de referencia     descifrado en Python
      -> debe dar el archivo original, byte por byte

El ultimo paso es el que hace que esto valga la pena. tb_archivo.sv ya comprueba
que el hardware descifra lo que cifro, pero eso se cumpliria igual si F4E y F4D
estuvieran mal de forma inversa. Aqui el descifrado lo hace un modelo escrito en
Python a partir de la formula del enunciado, que no comparte una sola linea con
el RTL ni con el ensamblador. Si el criptograma que produjo el procesador se
deshace con ese modelo, entonces el procesador implementa Feistel4 y no otra
cosa parecida.

Se corre despues de tb_archivo, porque necesita el volcado que ese testbench
escribe:

    make archivo flujo

Un segundo argumento opcional cambia el archivo original, para comprobar el
volcado de tb_cifrado.sv sobre un archivo cualquiera:

    probar_flujo.py cifrado_libre.hex mi_texto.txt

"""

import argparse
import contextlib
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_data                                   # noqa: E402
import load_file                                      # noqa: E402
from llave import LLAVE_POR_OMISION, formato, leer_llave  # noqa: E402
from formato_buffer import (BASE_POR_OMISION, a_contenedor,  # noqa: E402
                            de_contenedor, desempaquetar, empaquetar,
                            leer_hex)

AQUI = Path(__file__).resolve().parent
ORIGINAL = AQUI / "programas" / "archivo_prueba.txt"

M = 0xFFFFFFFF

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


# -----------------------------------------------------------------------------
# Modelo de referencia, escrito solo desde la formula del enunciado
#
#   F(x,k) = (ROL32(x,5) + k) XOR ROL32(x,13)
#   cifrar:    (L,R) -> (R, L XOR F(R,k))     rondas 0 a 3
#   descifrar: (L,R) -> (R XOR F(L,k), L)     rondas 3 a 0
# -----------------------------------------------------------------------------


def rol(x, n):
    return ((x << n) | (x >> (32 - n))) & M


def f_ronda(x, k):
    return ((rol(x, 5) + k) & M) ^ rol(x, 13)


def descifrar_bloque(L, R, llave=LLAVE_POR_OMISION):
    for r in reversed(range(4)):
        L, R = R ^ f_ronda(L, llave[r]), L
    return L, R


def cifrar_bloque(L, R, llave=LLAVE_POR_OMISION):
    for r in range(4):
        L, R = R, L ^ f_ronda(R, llave[r])
    return L, R


def main(volcado, ruta_original=ORIGINAL, llave=LLAVE_POR_OMISION,
         crudo=None):
    print("=== probar_flujo: de archivo a archivo, sobre el volcado real ===")
    print("")
    print(f"  llave    {formato(llave)}")

    ruta_original = Path(ruta_original)
    if not ruta_original.is_file():
        print(f"  FALLA  no se encontro el archivo original {ruta_original}")
        return 1
    original = ruta_original.read_bytes()
    print(f"  archivo original: {len(original)} bytes")

    ruta_volcado = Path(volcado)
    if not ruta_volcado.is_file():
        print(f"  FALLA  no se encontro el volcado {volcado}")
        print("           hay que correr antes el testbench: make archivo")
        return 1

    # --- el criptograma que produjo el procesador ---------------------------
    # Sale como contenedor, con la cabecera y los bloques completos: el relleno
    # del ultimo bloque ya es criptograma y recortarlo lo haria indescifrable.
    # Se escribe junto al volcado, en el directorio de build.
    cifrado = ruta_volcado.with_suffix(".bin")
    with contextlib.redirect_stdout(io.StringIO()):
        r = extract_data.main([str(ruta_volcado), "-o", str(cifrado),
                               "--cifrado"])
    check("extract_data --cifrado lee el volcado de $writememh", r == 0,
          f"devolvio {r}")
    if r != 0:
        return 1

    contenedor = cifrado.read_bytes()
    pal = de_contenedor(contenedor)
    n_bloques = pal[1]
    check("el contenedor guarda el tamano original en la cabecera",
          pal[0] == len(original), f"{pal[0]} contra {len(original)}")
    check("y los bloques completos, sin recortar el ultimo",
          len(contenedor) == 8 + 8 * n_bloques,
          f"{len(contenedor)} bytes para {n_bloques} bloques")
    check("que no son el original: el procesador si cifro",
          n_bloques == 0 or pal[2:] != empaquetar(original)[2:])

    # --- el modelo de referencia lo deshace ---------------------------------
    claro = []
    for b in range(n_bloques):
        i = 2 + 2 * b
        L, R = descifrar_bloque(pal[i], pal[i + 1], llave)
        claro += [L, R]
    recuperado = desempaquetar(pal[:2] + claro)

    check("el modelo de referencia descifra lo que cifro el hardware",
          recuperado == original,
          f"original   {original[:64]!r}\nrecuperado {recuperado[:64]!r}")

    # --- y en el otro sentido: el modelo cifra lo mismo que el hardware -----
    pal_claro = empaquetar(original)
    esperado = pal_claro[:2]
    for b in range(pal_claro[1]):
        i = 2 + 2 * b
        L, R = cifrar_bloque(pal_claro[i], pal_claro[i + 1], llave)
        esperado += [L, R]

    check("y cifra bloque por bloque lo mismo que el hardware",
          pal == esperado,
          f"hardware {a_contenedor(pal)[:64].hex()}\n"
          f"modelo   {a_contenedor(esperado)[:64].hex()}\n"
          f"Si el procesador termino sin fallas en su PSW, cifro con OTRA "
          f"LLAVE\nque la del modelo, {formato(llave)}.\n"
          f"La llave de cargar_llave.s (r5 a r8) y la de LLAVE= tienen que "
          f"ser la misma.")

    # --- el contenedor vuelve a memoria tal como salio ----------------------
    # Es lo que cargaria el procesador que descifra si el archivo viajara
    # fuera de la simulacion y volviera
    recarga = cifrado.with_suffix(".recarga.hex")
    with contextlib.redirect_stdout(io.StringIO()):
        r = load_file.main([str(cifrado), "-o", str(recarga), "--cifrado"])
    inicio = BASE_POR_OMISION // 4
    check("load_file --cifrado devuelve a memoria el mismo buffer",
          r == 0 and leer_hex(recarga)[inicio:inicio + len(pal)] ==
          leer_hex(ruta_volcado)[inicio:inicio + len(pal)],
          f"devolvio {r}")
    recarga.unlink(missing_ok=True)

    # --- el criptograma solo, sin la cabecera -------------------------------
    # Es lo que se compara contra un resultado calculado por fuera: la
    # cabecera es una convencion de este proyecto y no forma parte del cifrado
    criptograma = contenedor[8:]
    if crudo is not None:
        Path(crudo).write_bytes(criptograma)

    print("")
    print(f"  claro        {original[:64]!r}")
    print(f"  criptograma  {len(criptograma)} bytes en {n_bloques} bloques, "
          f"sin la cabecera:")
    for i in range(0, min(len(criptograma), 64), 16):
        fila = criptograma[i:i + 16]
        print(f"    {i:08x}  " + " ".join(fila[j:j + 4].hex()
                                          for j in range(0, len(fila), 4)))
    if len(criptograma) > 64:
        print(f"    (primeros 64 de {len(criptograma)} bytes)")
    if crudo is not None:
        print(f"  escrito en   {crudo}")
    print("")
    print("---")
    print(f"casos: {casos}   fallidos: {fallidos}")
    if fallidos:
        print("RESULTADO: FALLA")
        return 1
    print("RESULTADO: OK")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Compara el cifrado del hardware con el modelo")
    ap.add_argument("volcado", nargs="?", default="cifrado_volcado.hex")
    ap.add_argument("original", nargs="?", default=str(ORIGINAL))
    ap.add_argument("--llave", default=None,
                    help="la llave con que cifro el hardware, como en llave.py")
    ap.add_argument("--crudo", default=None,
                    help="escribe aqui el criptograma sin la cabecera")
    args = ap.parse_args()
    try:
        clave = leer_llave(args.llave) if args.llave else LLAVE_POR_OMISION
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(args.volcado, args.original, clave, args.crudo))