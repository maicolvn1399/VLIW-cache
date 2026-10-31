#!/usr/bin/env python3
"""
formato_buffer.py - Disposicion del buffer de archivo en la memoria de datos.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

load_file.py y extract_data.py son inversas una de la otra, asi que el formato
vive aqui, en un solo sitio que las dos importan. Si estuviera escrito dos veces
podrian desincronizarse y el archivo recuperado saldria corrido sin que ninguna
de las dos diera error.

-----------------------------------------------------------------------------
DISPOSICION
-----------------------------------------------------------------------------
El buffer arranca en 0x4000, que es donde el mapa de memoria de isa.md 1.4
reserva los 32 KB de "buffers de datos: archivos a cifrar y descifrar".

    BASE + 0x0    cantidad de bytes del archivo original
    BASE + 0x4    cantidad de bloques de 64 bits
    BASE + 0x8    los datos, rellenados con ceros hasta multiplo de 8 bytes

Las dos palabras de cabecera existen por un motivo cada una:

  La cantidad de BYTES hace falta porque Feistel4 trabaja sobre bloques de 64
  bits y casi ningun archivo mide un multiplo exacto de 8. Sin ese numero, al
  extraer no habria forma de distinguir los ceros de relleno de los ceros que
  de verdad estaban en el archivo, y todo archivo que terminara en 0x00 saldria
  truncado.

  La cantidad de BLOQUES hace falta porque el programa que cifra la lee para
  saber cuantas vueltas dar. Se podria calcular en el procesador a partir de la
  cantidad de bytes, pero eso serian una division entre 8 y un redondeo hacia
  arriba en cada corrida; dejarla calculada aqui cuesta una palabra.

-----------------------------------------------------------------------------
ORDEN DE BYTES
-----------------------------------------------------------------------------
Little-endian, como fija isa.md 1.4: el byte de la direccion A vive en los bits
[7:0] de su palabra. De modo que los cuatro primeros bytes del archivo salen en
la primera palabra con el primero en la parte baja.

El par de palabras de cada bloque se interpreta como la mitad L en la palabra de
direccion menor y la R en la mayor, que es el mismo orden que usa un par de
registros Pn = R(2n):R(2n+1).

-----------------------------------------------------------------------------
EL ARCHIVO CIFRADO ES UN CONTENEDOR
-----------------------------------------------------------------------------
Un archivo en claro sale recortado a su cantidad de bytes, pero un criptograma
no puede: despues de cifrar, el relleno del ultimo bloque ya no son ceros sino
parte del criptograma, y sin el el bloque no se descifra. Por eso el cifrado
se guarda como el buffer entero, cabecera incluida:

    bytes 0-3     cantidad de bytes del archivo original, little-endian
    bytes 4-7     cantidad de bloques, little-endian
    bytes 8-...   los bloques completos, 8 bytes cada uno

La cabecera no se cifra, asi que viaja legible y el descifrado recupera el
tamano original. extract_data.py --cifrado lo escribe y load_file.py --cifrado
lo vuelve a poner en memoria sin tocarlo.
"""

BASE_POR_OMISION = 0x4000
BYTES_POR_BLOQUE = 8
CABECERA_BYTES = 8          # dos palabras: bytes del archivo y bloques


def empaquetar(datos):
    """Devuelve la lista de palabras de 32 bits del buffer completo.

    Incluye la cabecera y el relleno. No incluye los ceros que haya antes de
    BASE: de eso se encarga quien escribe el archivo .hex.
    """
    n_bytes = len(datos)
    relleno = (-n_bytes) % BYTES_POR_BLOQUE
    cuerpo = datos + bytes(relleno)
    n_bloques = len(cuerpo) // BYTES_POR_BLOQUE

    palabras = [n_bytes, n_bloques]
    for i in range(0, len(cuerpo), 4):
        palabras.append(int.from_bytes(cuerpo[i:i + 4], "little"))
    return palabras


def validar_cabecera(palabras):
    """Comprueba la cabecera contra el tamano real y devuelve cuantas palabras
    ocupa el buffer completo.

    Un volcado truncado o una base equivocada se notan justo aqui y no cuando
    el archivo recuperado sale raro.
    """
    if len(palabras) < 2:
        raise ValueError(
            "el volcado no alcanza ni para la cabecera de dos palabras")

    n_bytes, n_bloques = palabras[0], palabras[1]

    esperadas = 2 + n_bloques * (BYTES_POR_BLOQUE // 4)
    if len(palabras) < esperadas:
        raise ValueError(
            f"la cabecera dice {n_bloques} bloques, o sea {esperadas} palabras, "
            f"y el volcado solo trae {len(palabras)}. "
            f"Puede ser una base equivocada o un volcado recortado")

    minimo = (n_bloques - 1) * BYTES_POR_BLOQUE + 1 if n_bloques else 0
    if not (minimo <= n_bytes <= n_bloques * BYTES_POR_BLOQUE):
        raise ValueError(
            f"la cabecera es incoherente: dice {n_bytes} bytes en "
            f"{n_bloques} bloques de {BYTES_POR_BLOQUE}")

    return esperadas


def desempaquetar(palabras):
    """Inversa de empaquetar: devuelve los bytes del archivo original."""
    esperadas = validar_cabecera(palabras)
    n_bytes = palabras[0]

    cuerpo = bytearray()
    for p in palabras[2:esperadas]:
        cuerpo += (p & 0xFFFFFFFF).to_bytes(4, "little")
    return bytes(cuerpo[:n_bytes])


def a_contenedor(palabras):
    """Devuelve el buffer completo como bytes: cabecera y bloques enteros.

    Es el formato de un archivo cifrado. Nada se recorta, porque despues de
    cifrar el relleno del ultimo bloque ya es parte del criptograma.
    """
    esperadas = validar_cabecera(palabras)
    return b"".join((p & 0xFFFFFFFF).to_bytes(4, "little")
                    for p in palabras[:esperadas])


def de_bloques(datos):
    """Arma el buffer de un criptograma crudo, sin cabecera.

    Es el caso de un archivo cifrado fuera del proyecto: trae solo los
    bloques, asi que el tamano original no se conoce. La cabecera dice que el
    archivo mide exactamente esos bloques, y el descifrado sale con el relleno
    del ultimo bloque incluido.
    """
    if len(datos) % BYTES_POR_BLOQUE:
        raise ValueError(
            f"el criptograma mide {len(datos)} bytes, que no es un multiplo "
            f"de {BYTES_POR_BLOQUE}: un cifrado por bloques siempre lo es")
    return [len(datos), len(datos) // BYTES_POR_BLOQUE] + [
        int.from_bytes(datos[i:i + 4], "little")
        for i in range(0, len(datos), 4)]


def de_contenedor(datos):
    """Inversa de a_contenedor: devuelve las palabras del buffer tal cual.

    Exige que el archivo mida exactamente lo que dice su cabecera. Un
    contenedor recortado o con bytes de mas no es un criptograma valido, y
    aceptarlo descifraria basura sin avisar.
    """
    if len(datos) % 4:
        raise ValueError(
            f"el contenedor mide {len(datos)} bytes, que no es un multiplo "
            f"de palabra")
    palabras = [int.from_bytes(datos[i:i + 4], "little")
                for i in range(0, len(datos), 4)]
    esperadas = validar_cabecera(palabras)
    if len(palabras) != esperadas:
        raise ValueError(
            f"la cabecera dice {esperadas} palabras y el contenedor trae "
            f"{len(palabras)}")
    return palabras


def leer_hex(ruta):
    """Lee un archivo en formato $readmemh o $writememh y devuelve palabras.

    Acepta comentarios, lineas vacias y marcas de direccion @XXXX, que es lo
    que emite $writememh cuando el volcado tiene huecos. Las marcas se usan para
    colocar la palabra donde corresponde y rellenar con ceros lo que falte.
    """
    palabras = []
    pos = 0
    with open(ruta, "r", encoding="utf-8", errors="replace") as f:
        for n, cruda in enumerate(f, start=1):
            linea = cruda.split("//")[0].strip()
            if not linea:
                continue
            for pieza in linea.split():
                if pieza.startswith("@"):
                    pos = int(pieza[1:], 16)
                    continue
                try:
                    v = int(pieza, 16)
                except ValueError:
                    raise ValueError(
                        f"{ruta}:{n}: '{pieza}' no es hexadecimal")
                while len(palabras) <= pos:
                    palabras.append(0)
                palabras[pos] = v
                pos += 1
    return palabras


def escribir_hex(ruta, palabras, total=None):
    """Escribe palabras de 32 bits, una por linea, para $readmemh.

    Si se da un total, rellena con ceros hasta esa cantidad de palabras. Vale la
    pena: cuando el archivo trae menos palabras que la memoria, Icarus avisa
    "Not enough words in the file for the requested range" en cada corrida.
    """
    salida = list(palabras)
    if total is not None and len(salida) < total:
        salida += [0] * (total - len(salida))
    with open(ruta, "w", encoding="utf-8") as f:
        for p in salida:
            f.write(f"{p & 0xFFFFFFFF:08X}\n")
    return len(salida)
