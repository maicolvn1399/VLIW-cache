#!/usr/bin/env python3
"""tabla_barrido.py - Compara las configuraciones de cache que dejo el barrido.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4

Lee el arbol que produce barrido_cache.sh (un subdirectorio por configuracion,
con un metricas_*.txt por programa) y arma dos tablas:

  1. Resumen por configuracion, agregando los programas: tasa de aciertos,
     AMAT medido y ciclos totales.
  2. Tasa de aciertos de cada programa en cada configuracion, que es donde se
     ve cual programa responde al tamano y cual no.

    python3 tabla_barrido.py ../barrido

No calcula nada por su cuenta: todos los numeros salen de los contadores de
hardware, igual que en tabla_metricas.py, y de hecho reusa su lector para que
las dos herramientas no puedan discrepar sobre como se lee un archivo.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tabla_metricas import leer, L1_HIT, razon   # noqa: E402


def orden_config(nombre):
    """Ordena 512B, 1KB, 2KB ... por tamano real, no alfabeticamente.

    Sin esto '16KB' queda antes de '1KB' y la tabla deja de leerse como un
    barrido.
    """
    hallado = re.match(r"(\d+)(B|KB)", nombre)
    if not hallado:
        return (1, 0, nombre)
    valor = int(hallado.group(1))
    if hallado.group(2) == "KB":
        valor *= 1024
    return (0, valor, nombre)


def cargar(raiz):
    """{config: {programa: metricas}} a partir del arbol del barrido."""
    configs = {}
    for carpeta in sorted(Path(raiz).iterdir(), key=lambda p: orden_config(p.name)):
        if not carpeta.is_dir():
            continue
        programas = {}
        for archivo in sorted(carpeta.glob("metricas_*.txt")):
            datos = leer(archivo)
            if datos is not None:
                programas[datos["programa"]] = datos
        if programas:
            configs[carpeta.name] = programas
    return configs


def agregado(programas):
    """Suma los contadores de todos los programas de una configuracion.

    Se agregan los CONTADORES y despues se divide, no se promedian las tasas
    de cada programa: promediar tasas le da el mismo peso a un programa con
    diez accesos que a uno con diez mil, y eso no es la tasa de aciertos del
    conjunto.
    """
    t = {k: 0 for k in ("ld_hit", "ld_miss", "st_hit", "st_miss",
                        "ciclos", "stalls", "stall_miss")}
    for d in programas.values():
        for k in t:
            t[k] += d[k]

    t["accesos"] = t["ld_hit"] + t["ld_miss"] + t["st_hit"] + t["st_miss"]
    t["aciertos"] = t["ld_hit"] + t["st_hit"]
    t["tasa"] = razon(t["aciertos"], t["accesos"])

    # Penalidad MEDIDA: ciclos de stall por fallo de lectura. Es la que importa
    # porque incluye lo que de verdad costo (arbitraje, buffer ocupado), no el
    # T_mem teorico.
    penalidad = razon(t["stall_miss"], t["ld_miss"])
    t["penalidad"] = penalidad
    t["amat"] = L1_HIT + razon(t["ld_miss"], t["accesos"]) * penalidad
    t["desbordado"] = any(d["desbordado"] for d in programas.values())
    return t


def tabla_resumen(configs):
    n = len({p for c in configs.values() for p in c})
    print(f"  Resumen por configuracion (los {n} programas agregados)")
    print()
    print(f"  {'configuracion':<14}  {'accesos':>8}  {'fallos ld':>9}  "
          f"{'aciertos':>9}  {'penal.':>7}  {'AMAT':>6}  {'ciclos':>8}  {'stalls':>7}")
    print(f"  {'-' * 14}  {'-' * 8}  {'-' * 9}  {'-' * 9}  "
          f"{'-' * 7}  {'-' * 6}  {'-' * 8}  {'-' * 7}")

    base = None
    for nombre, programas in configs.items():
        t = agregado(programas)
        if base is None:
            base = t
        marca = "  (!) contador desbordado" if t["desbordado"] else ""
        print(f"  {nombre:<14}  {t['accesos']:>8}  {t['ld_miss']:>9}  "
              f"{t['tasa'] * 100:>8.2f}%  {t['penalidad']:>7.1f}  "
              f"{t['amat']:>6.2f}  {t['ciclos']:>8}  {t['stalls']:>7}{marca}")
    print()


def tabla_por_programa(configs):
    nombres = list(configs.keys())
    programas = sorted({p for c in configs.values() for p in c})
    ancho = max((len(p) for p in programas), default=8)

    print("  Tasa de aciertos de cada programa, por configuracion")
    print()
    encabezado = f"  {'programa':<{ancho}}"
    for n in nombres:
        encabezado += f"  {n:>12}"
    print(encabezado)
    print(f"  {'-' * ancho}" + "".join(f"  {'-' * 12}" for _ in nombres))

    for p in programas:
        fila = f"  {p:<{ancho}}"
        for n in nombres:
            d = configs[n].get(p)
            if d is None:
                fila += f"  {'-':>12}"
                continue
            acc = d["ld_hit"] + d["ld_miss"] + d["st_hit"] + d["st_miss"]
            tasa = razon(d["ld_hit"] + d["st_hit"], acc)
            fila += f"  {tasa * 100:>11.2f}%"
        print(fila)
    print()


def veredicto(configs):
    """Donde dejan de pagar los bytes extra.

    El punto del barrido no es que mas cache sea mejor, que ya se sabe, sino
    donde se aplana la curva: ese es el tamano que se puede justificar.
    """
    print("  Lectura del barrido")
    print()

    nombres = list(configs)
    anterior = None
    for i, (nombre, programas) in enumerate(configs.items()):
        t = agregado(programas)
        if anterior is None:
            print(f"    {nombre:<12}  base del barrido: "
                  f"{t['tasa'] * 100:.2f}% de aciertos en {t['ciclos']} ciclos")
        else:
            d_tasa = (t["tasa"] - anterior["tasa"]) * 100
            ahorro = anterior["ciclos"] - t["ciclos"]
            pct = razon(ahorro, anterior["ciclos"]) * 100
            # El signo se dice con palabras y no con un + delante del numero:
            # "+20352 ciclos" se lee como que tardo mas, cuando es lo contrario.
            verbo = "ahorra" if ahorro >= 0 else "cuesta"
            print(f"    {nombre:<12}  al duplicar desde {nombres[i - 1]:<12} "
                  f"{d_tasa:+6.2f} pp de aciertos y {verbo} "
                  f"{abs(ahorro):6d} ciclos ({abs(pct):5.2f}%)")
        anterior = t
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("raiz", nargs="?", default="../barrido",
                    help="directorio que dejo barrido_cache.sh")
    args = ap.parse_args()

    raiz = Path(args.raiz)
    if not raiz.is_dir():
        print(f"no existe el directorio {raiz}", file=sys.stderr)
        return 1

    configs = cargar(raiz)
    if not configs:
        print(f"no hay metricas en {raiz}; corra primero barrido_cache.sh",
              file=sys.stderr)
        return 1

    print()
    print("=" * 78)
    print("  CERBERO-1: barrido de configuraciones de cache L1-D")
    print("  Todas de 2 vias y lineas de 32 B; varia la capacidad.")
    print("=" * 78)
    print()

    tabla_resumen(configs)
    tabla_por_programa(configs)
    veredicto(configs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
