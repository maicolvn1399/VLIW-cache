#!/usr/bin/env python3
"""tabla_metricas.py - Arma la tabla de linea base a partir de las corridas.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4

Lee los archivos de resultado que deja `make correr RESULTADO=...` y junta sus
metricas en una sola tabla. No simula ni calcula nada por su cuenta: todos los
numeros salen de los contadores del procesador, tal como el testbench los
imprimio.

    make metricas                      corre los programas y arma la tabla
    python3 tabla_metricas.py *.txt    solo arma la tabla, con lo ya corrido

La columna "ocupacion" es instrucciones/bundles: cuantas de las cinco ranuras
de un bundle llevaban trabajo, en promedio. Es la medida que dice si el VLIW
se esta usando como VLIW o como un procesador escalar caro.
"""

import argparse
import re
import sys
from pathlib import Path

# Cada metrica, con la etiqueta exacta que imprime tb_programa.sv
CAMPOS = {
    "ciclos":        r"ciclos de ejecucion\s+(\d+)",
    "bundles":       r"bundles ejecutados\s+(\d+)",
    "instrucciones": r"instrucciones ejecutadas\s+(\d+)",
    "vacios":        r"bundles vacios \(puros NOP\)\s+(\d+)",
    "saltos":        r"saltos tomados\s+(\d+)",
    "delay":         r"delay slots desperdiciados\s+(\d+)",
    "stalls":        r"ciclos perdidos por stalls\s+(\d+)",
    "s0":            r"S0 ALU-0\s+(\d+)",
    "s1":            r"S1 ALU-1\s+(\d+)",
    "s2":            r"S2 LSU\s+(\d+)",
    "s3":            r"S3 cripto\s+(\d+)",
    "s4":            r"S4 BRU\s+(\d+)",
}


def leer(ruta):
    """Saca las metricas de un archivo de resultado. None si no las trae."""
    texto = Path(ruta).read_text(errors="replace")

    datos = {}
    for nombre, patron in CAMPOS.items():
        hallado = re.search(patron, texto)
        if hallado is None:
            return None
        datos[nombre] = int(hallado.group(1))

    # El nombre del programa va en la primera linea del archivo
    cabecera = re.search(r"=== resultado de (.+) ===", texto)
    datos["programa"] = cabecera.group(1).strip() if cabecera else Path(ruta).stem

    # Un desbordamiento invalida todo lo demas, asi que se marca aparte
    datos["desbordado"] = "algun contador se desbordo" in texto

    return datos


def razon(numerador, denominador):
    return numerador / denominador if denominador else 0.0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archivos", nargs="+",
                        help="archivos de resultado de make correr")
    args = parser.parse_args()

    filas = []
    for ruta in sorted(args.archivos):
        datos = leer(ruta)
        if datos is None:
            print(f"  (sin metricas: {ruta})", file=sys.stderr)
            continue
        filas.append(datos)

    if not filas:
        print("No se encontro ningun resultado con metricas.", file=sys.stderr)
        return 1

    ancho = max(len(f["programa"]) for f in filas)

    print()
    print("  linea base del procesador VLIW, sin jerarquia de cache")
    print()
    print(f"  {'programa':<{ancho}}  {'ciclos':>8}  {'bundles':>8}  "
          f"{'instr':>8}  {'IPC':>6}  {'ocup':>6}  {'vacios':>8}  {'delay':>6}")
    print(f"  {'-' * ancho}  {'-' * 8}  {'-' * 8}  {'-' * 8}  "
          f"{'-' * 6}  {'-' * 6}  {'-' * 8}  {'-' * 6}")

    for f in filas:
        ipc = razon(f["instrucciones"], f["ciclos"])
        ocupacion = razon(f["instrucciones"], f["bundles"])
        porcentaje_vacios = 100 * razon(f["vacios"], f["bundles"])
        marca = "  <-- DESBORDADO" if f["desbordado"] else ""
        print(f"  {f['programa']:<{ancho}}  {f['ciclos']:>8}  "
              f"{f['bundles']:>8}  {f['instrucciones']:>8}  {ipc:>6.3f}  "
              f"{ocupacion:>6.2f}  {f['vacios']:>5} {porcentaje_vacios:>4.0f}%  "
              f"{f['delay']:>6}{marca}")

    print()
    print("  ocupacion por ranura (operaciones no-NOP despachadas)")
    print()
    print(f"  {'programa':<{ancho}}  {'S0':>6}  {'S1':>6}  {'S2':>6}  "
          f"{'S3':>6}  {'S4':>6}")
    print(f"  {'-' * ancho}  {'-' * 6}  {'-' * 6}  {'-' * 6}  "
          f"{'-' * 6}  {'-' * 6}")
    for f in filas:
        print(f"  {f['programa']:<{ancho}}  {f['s0']:>6}  {f['s1']:>6}  "
              f"{f['s2']:>6}  {f['s3']:>6}  {f['s4']:>6}")

    # Los totales dicen que unidades funcionales estan de adorno en el conjunto
    # de pruebas, que es una decision de diseno y no una curiosidad.
    print()
    totales = {s: sum(f[s] for f in filas) for s in ("s0", "s1", "s2", "s3", "s4")}
    total_instr = sum(totales.values())
    reparto = "  ".join(
        f"{s.upper()}: {100 * razon(v, total_instr):.0f}%"
        for s, v in totales.items())
    print(f"  reparto del total ({total_instr} operaciones)   {reparto}")
    print()

    if any(f["desbordado"] for f in filas):
        print("  AVISO: alguna corrida desbordo sus contadores; esos numeros")
        print("         estan saturados y no se pueden usar.")
        print()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
