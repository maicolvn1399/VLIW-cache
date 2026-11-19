#!/usr/bin/env python3
# =============================================================================
# tabla_analisis.py - Tablas y graficos del barrido de la jerarquia.
# CE-4301 Arquitectura de Computadores I - Proyecto Grupal II - Grupo #4
#
# Lee los informes que deja barrido_jerarquia.sh (un directorio por
# configuracion, un metricas_<programa>.txt por programa) y produce:
#
#   <barrido>/tablas.md          las tablas del analisis, en Markdown
#   docs/imgs/it5_*.png          los graficos
#
# Cada numero sale de un informe de make correr; aqui no se calcula nada que
# el informe no traiga, salvo razones entre dos informes (aceleracion).
#
# Los informes se validan al leerlos: si a uno le falta un campo, el script
# falla nombrando el archivo y el campo. Una tabla con un hueco silencioso
# parece completa y no lo es.
#
#   uso:  python3 tabla_analisis.py [directorio_del_barrido] [directorio_imgs]
# =============================================================================

import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
BARRIDO_DEF = AQUI.parent / "barrido" / "jerarquia"
IMGS_DEF = AQUI.parent / "docs" / "imgs"

# Los programas que separan configuraciones, en orden fijo: ese orden es
# tambien el del color de cada serie en los graficos.
PATRONES = ["patron_secuencial", "patron_stride", "patron_aleatorio",
            "patron_reuso", "recorrido_cache"]
NOMBRE_CORTO = {
    "patron_secuencial": "secuencial",
    "patron_stride": "stride",
    "patron_aleatorio": "aleatorio",
    "patron_reuso": "reuso",
    "recorrido_cache": "recorrido_cache",
}

# Configuraciones de cada curva. La base (L1 4 KB, L2 16 KB) entra en las dos.
CURVA_L1 = ["l1_512B", "l1_1KB", "l1_2KB", "base", "l1_8KB", "l1_16KB"]
CURVA_L2 = ["l2_4KB", "l2_8KB", "base", "l2_32KB", "l2_64KB"]

# Paleta categorica validada (dataviz, references/palette.md, modo claro),
# en orden fijo. Superficie y tintas de texto del mismo sistema.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"]
SUPERFICIE = "#fcfcfb"
TINTA = "#0b0b0b"
TINTA_2 = "#52514e"
REJILLA = "#e4e3df"


# -----------------------------------------------------------------------------
# Lectura de un informe
# -----------------------------------------------------------------------------

class InformeInvalido(Exception):
    pass


def _seccion(texto, inicio, fin):
    """El trozo de texto entre dos encabezados de seccion del informe."""
    i = texto.find(inicio)
    if i < 0:
        return None
    j = texto.find(fin, i + len(inicio)) if fin else -1
    return texto[i:j] if j >= 0 else texto[i:]


def _numero(trozo, etiqueta, archivo, campo, real=False):
    patron = re.escape(etiqueta) + r"\s+(-?[0-9]+(?:\.[0-9]+)?)"
    m = re.search(patron, trozo or "")
    if not m:
        raise InformeInvalido(f"{archivo}: falta el campo '{campo}'")
    return float(m.group(1)) if real else int(float(m.group(1)))


def leer_informe(ruta):
    texto = ruta.read_text(encoding="utf-8", errors="replace")
    a = ruta

    l1 = _seccion(texto, "  cache L1-D", "  cache L2 unificada")
    l2 = _seccion(texto, "  cache L2 unificada", "  memoria principal")
    mem = _seccion(texto, "  memoria principal", "  AMAT de lectura")
    amat = _seccion(texto, "  AMAT de lectura", "    ok ")
    for nombre, trozo in (("seccion L1", l1), ("seccion L2", l2),
                          ("seccion memoria", mem), ("seccion AMAT", amat)):
        if trozo is None:
            raise InformeInvalido(f"{a}: falta la '{nombre}'")

    m = re.search(r"cache L1-D \(([0-9]+) B", l1)
    if not m:
        raise InformeInvalido(f"{a}: falta el campo 'capacidad de L1'")
    l1_bytes = int(m.group(1))

    sin_l2 = "sin L2" in l2.splitlines()[0]
    if sin_l2:
        l2_kb = 0
    else:
        m = re.search(r"cache L2 unificada \(([0-9]+) KB", l2)
        if not m:
            raise InformeInvalido(f"{a}: falta el campo 'capacidad de L2'")
        l2_kb = int(m.group(1))

    return {
        "ciclos": _numero(texto, "ciclos de ejecucion", a, "ciclos de ejecucion"),
        "ipc": _numero(texto, "IPC  (instrucciones/ciclo)", a, "IPC", real=True),
        "l1_bytes": l1_bytes,
        "l2_kb": l2_kb,
        "sin_l2": sin_l2,
        "l1_ldh": _numero(l1, "lecturas: aciertos", a, "L1 lecturas: aciertos"),
        "l1_ldm": _numero(l1, "lecturas: fallos", a, "L1 lecturas: fallos"),
        "st_miss": _numero(l1, "fallo de lectura", a, "stall por fallo de lectura"),
        "st_l2h": _numero(l1, "que acerto en L2", a, "stall que acerto en L2"),
        "st_l2m": _numero(l1, "que fallo en L2", a, "stall que fallo en L2"),
        "st_wb": _numero(l1, "write buffer lleno", a, "stall por write buffer"),
        "st_raw": _numero(l1, "conflicto RAW", a, "stall por conflicto RAW"),
        "l2_ldh": _numero(l2, "lecturas: aciertos", a, "L2 lecturas: aciertos"),
        "l2_ldm": _numero(l2, "lecturas: fallos", a, "L2 lecturas: fallos"),
        "inv": _numero(l2, "invalidaciones hacia atras", a, "invalidaciones"),
        "mem_acc": _numero(mem, "accesos (lineas completas)", a, "accesos a memoria"),
        "bus": _numero(mem, "utilizacion del bus", a, "utilizacion del bus", real=True),
        "amat_teo": _numero(amat, "teorico", a, "AMAT teorico", real=True),
        "amat_med": _numero(amat, "medido", a, "AMAT medido", real=True),
    }


def leer_barrido(raiz):
    if not raiz.is_dir():
        raise InformeInvalido(f"{raiz}: no existe el directorio del barrido")
    datos = {}
    for dir_conf in sorted(p for p in raiz.iterdir() if p.is_dir()):
        progs = {}
        for f in sorted(dir_conf.glob("metricas_*.txt")):
            progs[f.stem[len("metricas_"):]] = leer_informe(f)
        if progs:
            datos[dir_conf.name] = progs
    faltan = [c for c in ["base", "sin_l2"] + CURVA_L1 + CURVA_L2 if c not in datos]
    if faltan:
        raise InformeInvalido(f"{raiz}: faltan las configuraciones {sorted(set(faltan))}")
    for conf, progs in datos.items():
        for p in PATRONES:
            if p not in progs:
                raise InformeInvalido(f"{raiz / conf}: falta metricas_{p}.txt")
    return datos


# -----------------------------------------------------------------------------
# Derivados
# -----------------------------------------------------------------------------

def pct(num, den):
    return 100.0 * num / den if den else 0.0


def tasa_l1(r):
    return pct(r["l1_ldh"], r["l1_ldh"] + r["l1_ldm"])


def tasa_l2(r):
    return pct(r["l2_ldh"], r["l2_ldh"] + r["l2_ldm"])


def etiqueta_l1(b):
    return f"{b} B" if b < 1024 else f"{b // 1024} KB"


# -----------------------------------------------------------------------------
# Tablas
# -----------------------------------------------------------------------------

def fila(celdas):
    return "| " + " | ".join(str(c) for c in celdas) + " |"


def encabezado(titulos, alineacion):
    return [fila(titulos), "| " + " | ".join(alineacion) + " |"]


def miles(n):
    return f"{n:,}".replace(",", " ")


def tablas(datos):
    base, sin = datos["base"], datos["sin_l2"]
    progs = PATRONES + sorted(p for p in base if p not in PATRONES)
    out = ["# Resultados del barrido de la jerarquia", "",
           "Generado por `tools/tabla_analisis.py` a partir de los informes de "
           "`barrido/jerarquia/`. No se edita a mano: se regenera con "
           "`make analisis`.", ""]

    out += ["## 1. Con L2 contra sin L2", "",
            "L1 de 4 KB en las dos. Aceleracion = ciclos sin L2 / ciclos con L2.", ""]
    out += encabezado(["programa", "ciclos con L2", "ciclos sin L2", "aceleracion",
                       "AMAT con L2", "AMAT sin L2", "aciertos L1",
                       "aciertos L2 (lect.)"],
                      [":---", "---:", "---:", "---:", "---:", "---:", "---:", "---:"])
    for p in progs:
        b, s = base[p], sin[p]
        out.append(fila([f"`{p}`", miles(b["ciclos"]), miles(s["ciclos"]),
                         f"{s['ciclos'] / b['ciclos']:.2f}x",
                         f"{b['amat_med']:.2f}", f"{s['amat_med']:.2f}",
                         f"{tasa_l1(b):.2f} %", f"{tasa_l2(b):.2f} %"]))

    out += ["", "## 2. AMAT de lectura, teorico contra medido (configuracion base)", "",
            "Teorico: `T_L1 + m_L1 x (T_L2 + m_L2 x (T_mem + 2))`, con T_L2 = 8 y "
            "T_mem = 53. Penalidad por tipo = ciclos de stall / lecturas de ese tipo.", ""]
    out += encabezado(["programa", "m_L1", "m_L2 local", "AMAT teorico",
                       "AMAT medido", "penalidad acierto L2", "penalidad fallo L2"],
                      [":---", "---:", "---:", "---:", "---:", "---:", "---:"])
    for p in PATRONES:
        b = base[p]
        m1 = 100.0 - tasa_l1(b)
        m2 = 100.0 - tasa_l2(b) if (b["l2_ldh"] + b["l2_ldm"]) else 0.0
        ph = f"{b['st_l2h'] / b['l2_ldh']:.1f}" if b["l2_ldh"] else "-"
        pm = f"{b['st_l2m'] / b['l2_ldm']:.1f}" if b["l2_ldm"] else "-"
        out.append(fila([f"`{p}`", f"{m1:.2f} %", f"{m2:.2f} %",
                         f"{b['amat_teo']:.2f}", f"{b['amat_med']:.2f}", ph, pm]))

    out += ["", "## 3. Ciclos de stall por causa (configuracion base)", ""]
    out += encabezado(["programa", "fallo L1, acierto L2", "fallo L1, fallo L2",
                       "write buffer lleno", "conflicto RAW", "total"],
                      [":---", "---:", "---:", "---:", "---:", "---:"])
    for p in progs:
        b = base[p]
        out.append(fila([f"`{p}`", miles(b["st_l2h"]), miles(b["st_l2m"]),
                         miles(b["st_wb"]), miles(b["st_raw"]),
                         miles(b["st_miss"] + b["st_wb"] + b["st_raw"])]))

    out += ["", "## 4. Capacidad de L1 (2 vias, L2 de 16 KB)", "",
            "Tasa de aciertos de lectura de L1, y ciclos de ejecucion.", ""]
    caps = [etiqueta_l1(datos[c][PATRONES[0]]["l1_bytes"]) for c in CURVA_L1]
    out += encabezado(["programa"] + caps, [":---"] + ["---:"] * len(caps))
    for p in PATRONES:
        out.append(fila([f"`{p}` aciertos"] +
                        [f"{tasa_l1(datos[c][p]):.2f} %" for c in CURVA_L1]))
        out.append(fila([f"`{p}` ciclos"] +
                        [miles(datos[c][p]["ciclos"]) for c in CURVA_L1]))

    out += ["", "## 5. Capacidad de L2 (4 vias, L1 de 4 KB)", "",
            "Tasa de aciertos de lectura de L2 (local), ciclos de ejecucion e "
            "invalidaciones hacia atras.", ""]
    caps = [f"{datos[c][PATRONES[0]]['l2_kb']} KB" for c in CURVA_L2]
    out += encabezado(["programa"] + caps, [":---"] + ["---:"] * len(caps))
    for p in PATRONES:
        out.append(fila([f"`{p}` aciertos L2"] +
                        [f"{tasa_l2(datos[c][p]):.2f} %" for c in CURVA_L2]))
        out.append(fila([f"`{p}` ciclos"] +
                        [miles(datos[c][p]["ciclos"]) for c in CURVA_L2]))
        out.append(fila([f"`{p}` invalidaciones"] +
                        [datos[c][p]["inv"] for c in CURVA_L2]))

    out += ["", "## 6. Memoria principal, con y sin L2", ""]
    out += encabezado(["programa", "accesos con L2", "accesos sin L2",
                       "uso del bus con L2", "uso del bus sin L2"],
                      [":---", "---:", "---:", "---:", "---:"])
    for p in progs:
        b, s = base[p], sin[p]
        out.append(fila([f"`{p}`", miles(b["mem_acc"]), miles(s["mem_acc"]),
                         f"{b['bus']:.2f} %", f"{s['bus']:.2f} %"]))

    return "\n".join(out) + "\n"


# -----------------------------------------------------------------------------
# Graficos
# -----------------------------------------------------------------------------

def estilo(ax, titulo, eje_x, eje_y):
    ax.set_facecolor(SUPERFICIE)
    ax.set_title(titulo, color=TINTA, fontsize=12, loc="left", pad=12)
    ax.set_xlabel(eje_x, color=TINTA_2, fontsize=10)
    ax.set_ylabel(eje_y, color=TINTA_2, fontsize=10)
    ax.tick_params(colors=TINTA_2, labelsize=9, length=0)
    for lado in ("top", "right", "left"):
        ax.spines[lado].set_visible(False)
    ax.spines["bottom"].set_color(TINTA_2)
    ax.grid(axis="y", color=REJILLA, linewidth=0.8)
    ax.set_axisbelow(True)


def figura(plt):
    fig, ax = plt.subplots(figsize=(8, 4.6), dpi=150)
    fig.patch.set_facecolor(SUPERFICIE)
    return fig, ax


def leyenda(ax):
    ley = ax.legend(frameon=False, fontsize=9, labelcolor=TINTA,
                    loc="upper left", bbox_to_anchor=(1.0, 1.0))
    return ley


def curva(plt, datos, confs, tasa, eje_x, titulo, eje_y, archivo, etiquetas):
    fig, ax = figura(plt)
    xs = list(range(len(confs)))
    for k, p in enumerate(PATRONES):
        ys = [tasa(datos[c][p]) for c in confs]
        ax.plot(xs, ys, color=SERIES[k], linewidth=2, marker="o", markersize=6,
                markeredgecolor=SUPERFICIE, markeredgewidth=1.5,
                label=NOMBRE_CORTO[p])
    ax.set_xticks(xs, etiquetas)
    ax.set_ylim(-3, 103)
    estilo(ax, titulo, eje_x, eje_y)
    leyenda(ax)

    # Series que coinciden en todos los puntos quedan una encima de otra; se
    # nombran debajo del grafico para que ninguna desaparezca sin aviso.
    valores = {p: tuple(round(tasa(datos[c][p]), 2) for c in confs)
               for p in PATRONES}
    tapadas = []
    for k, p in enumerate(PATRONES):
        iguales = [NOMBRE_CORTO[q] for q in PATRONES[k + 1:]
                   if valores[q] == valores[p]]
        if iguales:
            tapadas.append(f"{NOMBRE_CORTO[p]} coincide con {', '.join(iguales)}"
                           f" en todos los puntos ({valores[p][0]:.0f} %)")
    if tapadas:
        fig.text(0.01, 0.01, "; ".join(tapadas), fontsize=8, color=TINTA_2)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(archivo, facecolor=SUPERFICIE)
    plt.close(fig)


def barras_amat(plt, datos, archivo):
    fig, ax = figura(plt)
    xs = range(len(PATRONES))
    ancho = 0.38
    for k, (conf, nombre) in enumerate((("base", "con L2 (16 KB)"),
                                         ("sin_l2", "sin L2"))):
        ys = [datos[conf][p]["amat_med"] for p in PATRONES]
        pos = [x + (k - 0.5) * (ancho + 0.02) for x in xs]
        barras = ax.bar(pos, ys, width=ancho, color=SERIES[k], label=nombre)
        for b, y in zip(barras, ys):
            ax.annotate(f"{y:.1f}", (b.get_x() + b.get_width() / 2, y),
                        xytext=(0, 3), textcoords="offset points",
                        ha="center", fontsize=8, color=TINTA_2)
    ax.set_xticks(list(xs), [NOMBRE_CORTO[p] for p in PATRONES])
    estilo(ax, "AMAT de lectura medido, con y sin L2 (L1 de 4 KB)",
           "programa", "ciclos por lectura")
    leyenda(ax)
    fig.tight_layout()
    fig.savefig(archivo, facecolor=SUPERFICIE)
    plt.close(fig)


def barras_stall(plt, datos, archivo):
    fig, ax = figura(plt)
    causas = [("st_l2h", "fallo L1, acierto L2"),
              ("st_l2m", "fallo L1, fallo L2"),
              ("st_wb", "write buffer lleno"),
              ("st_raw", "conflicto RAW")]
    # Una causa que vale cero en todos los programas no se dibuja ni entra en
    # la leyenda: se dice en una nota, para que su ausencia sea un dato.
    nulas = [n for c, n in causas if all(datos["base"][p][c] == 0 for p in PATRONES)]
    causas = [(c, n) for c, n in causas if n not in nulas]
    nombres = [NOMBRE_CORTO[p] for p in PATRONES]
    izquierda = [0] * len(PATRONES)
    for k, (campo, nombre) in enumerate(causas):
        ws = [datos["base"][p][campo] for p in PATRONES]
        ax.barh(nombres, ws, left=izquierda, color=SERIES[k], label=nombre,
                edgecolor=SUPERFICIE, linewidth=1.5, height=0.6)
        izquierda = [a + b for a, b in zip(izquierda, ws)]
    ax.invert_yaxis()
    estilo(ax, "Ciclos de stall por causa (L1 de 4 KB, L2 de 16 KB)",
           "ciclos", "")
    ax.grid(axis="y", visible=False)
    ax.grid(axis="x", color=REJILLA, linewidth=0.8)
    ax.spines["bottom"].set_visible(False)
    leyenda(ax)
    if nulas:
        fig.text(0.01, 0.01, "sin ciclos en ningun programa: " + ", ".join(nulas),
                 fontsize=8, color=TINTA_2)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(archivo, facecolor=SUPERFICIE)
    plt.close(fig)


def graficos(datos, imgs):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    imgs.mkdir(parents=True, exist_ok=True)
    et_l1 = [etiqueta_l1(datos[c][PATRONES[0]]["l1_bytes"]) for c in CURVA_L1]
    et_l2 = [f"{datos[c][PATRONES[0]]['l2_kb']} KB" for c in CURVA_L2]
    curva(plt, datos, CURVA_L1, tasa_l1, "capacidad de L1 (2 vias)",
          "Aciertos de lectura de L1 segun su capacidad (L2 de 16 KB)",
          "aciertos de L1 (%)", imgs / "it5_aciertos_l1.png", et_l1)
    curva(plt, datos, CURVA_L2, tasa_l2, "capacidad de L2 (4 vias)",
          "Aciertos de lectura de L2 segun su capacidad (L1 de 4 KB)",
          "aciertos de L2, tasa local (%)", imgs / "it5_aciertos_l2.png", et_l2)
    barras_amat(plt, datos, imgs / "it5_amat_con_sin_l2.png")
    barras_stall(plt, datos, imgs / "it5_stall_por_causa.png")
    return ["it5_aciertos_l1.png", "it5_aciertos_l2.png",
            "it5_amat_con_sin_l2.png", "it5_stall_por_causa.png"]


def main(argv):
    raiz = Path(argv[1]) if len(argv) > 1 else BARRIDO_DEF
    imgs = Path(argv[2]) if len(argv) > 2 else IMGS_DEF
    try:
        datos = leer_barrido(raiz)
    except InformeInvalido as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    (raiz / "tablas.md").write_text(tablas(datos), encoding="utf-8")
    hechos = graficos(datos, imgs)
    print(f"tablas:   {raiz / 'tablas.md'}")
    for h in hechos:
        print(f"grafico:  {imgs / h}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
