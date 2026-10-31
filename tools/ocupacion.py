#!/usr/bin/env python3
"""
Cuanto del bundle se usa realmente.

CERBERO ejecuta cinco ranuras por bundle. El generador emite una instruccion
por bundle y rellena con bundles vacios para pagar la latencia de tres, asi
que la ocupacion real es la medida de cuanto queda por ganar empaquetando.

Empaquetar es optimizacion de codigo, que la seccion 9.1 de la guia excluye
de esta primera version. Este reporte no mide una fase pendiente sino el
margen que queda, y explica por que dos programas no entran en la IMEM.

Uso:
    python3 tools/ocupacion.py [./novac]
"""

import glob
import os
import shutil
import subprocess
import sys
import tempfile

IMEM = 0x8000 // 16          # 2048 bundles de 16 bytes
RANURAS = ("S0 ALU-0", "S1 ALU-1", "S2 LSU", "S3 CRP", "S4 BRU")


def bundles(texto):
    """Cada bundle como la lista de sus cinco ranuras."""
    for linea in texto.splitlines():
        # La direccion va como comentario al final de la linea: se corta
        # antes de mirar el ';' que cierra el bundle.
        t = linea.split("//")[0].strip()
        if not t.endswith(";"):
            continue
        ranuras = [x.strip() for x in t[:-1].split("|")]
        if len(ranuras) == 5:
            yield [x for x in ranuras]


def main():
    novac = sys.argv[1] if len(sys.argv) > 1 else "./novac"
    if not os.path.exists(novac):
        print("no se encontro %s; corra 'make' primero" % novac)
        return 1

    fuentes = (["test/factorial.nv"]
               + sorted(glob.glob("test/ejemplos/*.nv"))
               + sorted(glob.glob("test/ejecucion/*.nv")))

    tmp = tempfile.mkdtemp(prefix="nova_ocup_")
    total_b = total_i = multi = 0
    por_ranura = [0] * 5
    filas = []
    try:
        for f in fuentes:
            # Con -o el ejecutable va al temporal: sin el, novac lo deja en la
            # raiz del proyecto con el nombre del fuente.
            r = subprocess.run([novac, "-s", f, "-o", os.path.join(tmp, "p.nvx")],
                               capture_output=True, text=True, errors="replace")
            if r.returncode:
                continue
            nb = ni = 0
            for b in bundles(r.stdout):
                llenos = [k for k, x in enumerate(b) if x not in ("", "-", "nop")]
                nb += 1
                ni += len(llenos)
                if len(llenos) > 1:
                    multi += 1
                for k in llenos:
                    por_ranura[k] += 1
            if nb == 0:
                continue
            total_b += nb
            total_i += ni
            filas.append((os.path.basename(f)[:-3], nb, ni, nb - ni, ni / nb))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if total_b == 0:
        print("no se pudo compilar ningun programa")
        return 1

    print("%-22s %8s %8s %8s %9s" % ("programa", "bundles", "instr", "vacios", "instr/bun"))
    print("-" * 60)
    for nombre, nb, ni, nv, media in sorted(filas, key=lambda x: -x[1]):
        aviso = "   NO CABE EN IMEM" if nb > IMEM else ""
        print("%-22s %8d %8d %8d %9.2f%s" % (nombre, nb, ni, nv, media, aviso))

    print("-" * 60)
    print("%d programas, %d bundles, %d instrucciones" % (len(filas), total_b, total_i))
    print("ocupacion media: %.2f instrucciones por bundle, de 5 posibles (%.0f%%)"
          % (total_i / total_b, 100 * total_i / (5.0 * total_b)))
    print("bundles con mas de una instruccion: %d de %d (%.1f%%)"
          % (multi, total_b, 100.0 * multi / total_b))
    print()
    print("uso por ranura:")
    for k, nombre in enumerate(RANURAS):
        print("  %-10s %7d bundles  (%4.1f%%)"
              % (nombre, por_ranura[k], 100.0 * por_ranura[k] / total_b))
    print()
    print("Una instruccion por bundle es lo que documenta codegen.h. Empaquetar")
    print("varias es optimizacion de codigo, excluida en la seccion 9.1 de la guia.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
