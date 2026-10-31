#!/usr/bin/env python3
"""Convierte un ejecutable NOVA en archivos de inicializacion para CERBERO.

Utilidad de integración de la arquitectura CERBERO.
"""

import argparse
import sys
from pathlib import Path

HEADER_SIZE = 48
IMEM_BUNDLES = 2048
DMEM_WORDS = 16384
DMEM_SIZE = DMEM_WORDS * 4
CHECKSUM_OFFSET = 36


def u32(data, offset):
    return int.from_bytes(data[offset:offset + 4], "little")


def checksum(data):
    value = 0
    for byte in data:
        value = (value * 31 + byte) & 0xFFFFFFFF
    return value


def decode(path):
    raw = path.read_bytes()
    if len(raw) < HEADER_SIZE or raw[:4] != b"NOVA":
        raise ValueError("el archivo no tiene un encabezado NOVA valido")
    version = int.from_bytes(raw[4:6], "little")
    if version != 1:
        raise ValueError(f"version de ejecutable no soportada: {version}")
    if any(raw[6:8]) or any(raw[40:48]):
        raise ValueError("los campos reservados del encabezado deben ser cero")

    bundle_count = u32(raw, 8)
    code_origin = u32(raw, 12)
    entry = u32(raw, 16)
    data_origin = u32(raw, 20)
    initialized_size = u32(raw, 24)
    zero_size = u32(raw, 28)

    if code_origin != 0:
        raise ValueError(f"el RTL CERBERO arranca IMEM en 0, no en 0x{code_origin:X}")
    if bundle_count == 0 or bundle_count > IMEM_BUNDLES:
        raise ValueError(
            f"el codigo ocupa {bundle_count} bundles; CERBERO admite {IMEM_BUNDLES}"
        )
    code_size = bundle_count * 16
    if entry % 16 or entry >= code_size:
        raise ValueError(f"punto de entrada invalido: 0x{entry:X}")

    expected_size = HEADER_SIZE + code_size + initialized_size
    if len(raw) != expected_size:
        raise ValueError(
            f"el archivo mide {len(raw)} bytes; el encabezado describe {expected_size}"
        )
    payload = raw[HEADER_SIZE:]
    expected_checksum = u32(raw, CHECKSUM_OFFSET)
    if checksum(payload) != expected_checksum:
        raise ValueError("la suma de verificacion del ejecutable no coincide")
    if data_origin % 4:
        raise ValueError(f"la seccion de datos no esta alineada: 0x{data_origin:X}")
    if data_origin + initialized_size + zero_size > DMEM_SIZE:
        raise ValueError("la seccion de datos excede la DMEM de CERBERO (64 KiB)")

    code = payload[:code_size]
    initial_data = payload[code_size:]
    return bundle_count, code, data_origin, initial_data


def write_images(code, data_origin, initial_data, imem_path, dmem_path):
    imem_path.parent.mkdir(parents=True, exist_ok=True)
    dmem_path.parent.mkdir(parents=True, exist_ok=True)

    padded_code = code + bytes((IMEM_BUNDLES * 16) - len(code))
    with imem_path.open("w", encoding="ascii", newline="\n") as out:
        for offset in range(0, len(padded_code), 16):
            bundle = int.from_bytes(padded_code[offset:offset + 16], "little")
            out.write(f"{bundle:032x}\n")

    data = bytearray(DMEM_SIZE)
    data[data_origin:data_origin + len(initial_data)] = initial_data
    with dmem_path.open("w", encoding="ascii", newline="\n") as out:
        for offset in range(0, DMEM_SIZE, 4):
            word = int.from_bytes(data[offset:offset + 4], "little")
            out.write(f"{word:08x}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--imem", type=Path, required=True, help="imagen de instrucciones .hex")
    parser.add_argument("--dmem", type=Path, required=True, help="imagen de datos .hex")
    args = parser.parse_args(argv)

    try:
        bundles, code, data_origin, initial_data = decode(args.executable)
        write_images(code, data_origin, initial_data, args.imem, args.dmem)
    except (OSError, ValueError) as exc:
        print(f"novac_image: {exc}", file=sys.stderr)
        return 1

    print(
        f"imagenes CERBERO: {bundles} bundles; "
        f"datos inicializados {len(initial_data)} bytes desde 0x{data_origin:04X}"
    )
    print(f"IMEM: {args.imem}")
    print(f"DMEM: {args.dmem}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
