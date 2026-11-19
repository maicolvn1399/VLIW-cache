#!/usr/bin/env python3
"""Tablas de la Iteracion 5: que le hace cada nivel de optimizacion al sistema
de memoria y al empaquetado de bundles.

Lee los volcados que deja `make medir-niveles` (uno por programa y nivel) y
arma las tablas que pide la seccion 7.1.5 del enunciado: correlacionar tasas de
acierto, IPC, stalls y AMAT con las decisiones de diseno --- aqui, con las
decisiones del compilador.

    python3 tools/tabla_niveles.py medicion

Las cifras agregadas son sumas sobre el corpus, no promedios de porcentajes.
Promediar tasas da el mismo peso a un programa de 30 ciclos que a uno de
350 000, que es exactamente el error que haria pasar inadvertido lo unico que
mueve la aguja.
"""

import os
import sys

NIVELES = ("O0", "O1", "O2")

# Lo que cuesta un fallo cuando no lo atrapa el nivel siguiente. Sale de
# ARQUITECTURA/docs/jerarquia-memoria.md; se usa solo para el AMAT analitico,
# que es un control contra el AMAT medido, no un sustituto.
LAT_L1 = 1


def leer(ruta):
    datos = {}
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            partes = linea.split()
            if len(partes) == 2:
                datos[partes[0]] = int(partes[1])
    return datos


def cargar(directorio):
    """{programa: {nivel: contadores}}, solo programas con los tres niveles."""
    crudo = {}
    for nombre in sorted(os.listdir(directorio)):
        if not nombre.endswith(".txt"):
            continue
        tronco, _, resto = nombre.rpartition(".O")
        nivel = "O" + resto[: -len(".txt")]
        if nivel not in NIVELES:
            continue
        crudo.setdefault(tronco, {})[nivel] = leer(
            os.path.join(directorio, nombre))

    completos = {p: v for p, v in crudo.items()
                 if all(n in v for n in NIVELES)}
    parciales = sorted(set(crudo) - set(completos))
    return completos, parciales


def suma(datos, clave):
    return sum(d.get(clave, 0) for d in datos)


def pct(parte, total):
    return 100.0 * parte / total if total else 0.0


def stalls_memoria(d):
    """Solo los stalls que son costo de la jerarquia. stall_por_raw queda
    fuera: es un conflicto del pipeline, no un acceso lento."""
    return d["stall_por_miss"] + d["stall_por_wb"] + d["stall_por_evict"]


def amat(d):
    """AMAT sobre todos los accesos. Se reporta por completitud, pero el de
    abajo es el que significa algo: ver la nota de amat_load()."""
    accesos = d["accesos_load"] + d["accesos_store"]
    if not accesos:
        return None
    return LAT_L1 + stalls_memoria(d) / accesos


def amat_load(d):
    """AMAT del lado de lectura, que es el unico que el programa paga en
    tiempo.

    L1-D es write-through con no-write-allocate (decisiones D1 y D2 de
    ARQUITECTURA/docs/jerarquia-memoria.md), asi que un fallo de ESCRITURA no
    detiene el pipeline: el store se publica en el write buffer y la ejecucion
    sigue. Meter los stores en el denominador del AMAT reparte entre ellos un
    costo que no causaron y da un numero demasiado bueno --- en este corpus,
    2,0 ciclos por fallo, que es menos que el acierto de L2 y por lo tanto
    imposible. Esa cifra imposible es lo que delata el error."""
    if not d["accesos_load"]:
        return None
    return LAT_L1 + stalls_memoria(d) / d["accesos_load"]


def penalidad_load(d):
    """Ciclos de stall por fallo de lectura. Contra este numero se comprueba
    el modelo: tiene que caer entre el acierto de L2 (8) y la memoria (53),
    ponderado por cuantos fallos de L1 se le escapan tambien a la L2."""
    if not d["l1_load_miss"]:
        return None
    return stalls_memoria(d) / d["l1_load_miss"]


def fila_global(datos):
    d = {}
    for clave in ("ciclos", "bundles", "instrucciones", "bundles_vacios",
                  "accesos_load", "accesos_store", "ciclos_stall",
                  "stall_por_miss", "stall_por_wb", "stall_por_raw",
                  "stall_por_evict", "l1_load_hit", "l1_load_miss",
                  "l1_store_hit", "l1_store_miss", "l2_load_hit",
                  "l2_load_miss", "l2_store_hit", "l2_store_miss",
                  "inv_ejecutadas", "mem_accesos", "mem_ciclos",
                  "saltos_tomados", "delay_vacios",
                  "ops_slot0", "ops_slot1", "ops_slot2", "ops_slot3",
                  "ops_slot4"):
        d[clave] = suma(datos, clave)
    return d


def tabla_resumen(porniv):
    print("## Lo que cambia cada nivel, sobre todo el corpus\n")
    print("| | -O0 | -O1 | -O2 | -O2 contra -O0 |")
    print("|---|---|---|---|---|")

    def linea(etiqueta, f, mejor_es_menor=True, fmt="{:,}"):
        vals = [f(porniv[n]) for n in NIVELES]
        if vals[0]:
            delta = 100.0 * (vals[2] - vals[0]) / vals[0]
            cambio = "{:+.1f} %".format(delta)
        else:
            cambio = "—"
        celdas = " | ".join(fmt.format(v).replace(",", " ") for v in vals)
        print("| {} | {} | {} |".format(etiqueta, celdas, cambio))

    linea("Ciclos ejecutados", lambda d: d["ciclos"])
    linea("Bundles despachados", lambda d: d["bundles"])
    linea("Operaciones (no-NOP)", lambda d: d["instrucciones"])
    linea("Accesos a memoria del programa",
          lambda d: d["accesos_load"] + d["accesos_store"])
    linea("Ciclos de stall", lambda d: d["ciclos_stall"])
    linea("  por fallo de cache", lambda d: d["stall_por_miss"])
    linea("  por conflicto RAW", lambda d: d["stall_por_raw"])
    linea("Accesos a memoria principal", lambda d: d["mem_accesos"])
    print()


def tabla_derivadas(porniv):
    print("## Las razones\n")
    print("| | -O0 | -O1 | -O2 |")
    print("|---|---|---|---|")

    def linea(etiqueta, f, fmt="{:.3f}"):
        print("| {} | {} |".format(
            etiqueta,
            " | ".join(fmt.format(f(porniv[n])) for n in NIVELES)))

    linea("IPC (operaciones / ciclo)",
          lambda d: d["instrucciones"] / d["ciclos"])
    linea("Ocupacion (operaciones / bundle, de 5)",
          lambda d: d["instrucciones"] / d["bundles"])
    linea("Bundles totalmente vacios",
          lambda d: pct(d["bundles_vacios"], d["bundles"]), "{:.1f} %")
    linea("Accesos a memoria sobre las operaciones",
          lambda d: pct(d["accesos_load"] + d["accesos_store"],
                        d["instrucciones"]), "{:.1f} %")
    linea("Tasa de aciertos L1-D",
          lambda d: pct(d["l1_load_hit"] + d["l1_store_hit"],
                        d["l1_load_hit"] + d["l1_store_hit"]
                        + d["l1_load_miss"] + d["l1_store_miss"]),
          "{:.2f} %")
    linea("Tasa de aciertos L2",
          lambda d: pct(d["l2_load_hit"] + d["l2_store_hit"],
                        d["l2_load_hit"] + d["l2_store_hit"]
                        + d["l2_load_miss"] + d["l2_store_miss"]),
          "{:.2f} %")
    linea("Tasa de FALLOS de lectura",
          lambda d: pct(d["l1_load_miss"], d["accesos_load"]), "{:.2f} %")
    linea("Tasa de FALLOS de escritura",
          lambda d: pct(d["l1_store_miss"], d["accesos_store"]), "{:.2f} %")
    linea("AMAT de lectura (ciclos)", lambda d: amat_load(d))
    linea("  penalidad por fallo de lectura", lambda d: penalidad_load(d),
          "{:.1f}")
    linea("AMAT sobre todos los accesos", lambda d: amat(d))
    linea("Stall por operacion ejecutada",
          lambda d: d["ciclos_stall"] / d["instrucciones"])
    linea("Utilizacion del bus de memoria",
          lambda d: pct(d["mem_ciclos"], d["ciclos"]), "{:.2f} %")
    print()
    print("> El AMAT que vale es el de lectura. L1-D es write-through con")
    print("> no-write-allocate, asi que un fallo de escritura no detiene el")
    print("> pipeline: el store se publica en el write buffer y la ejecucion")
    print("> sigue. Repartir el costo entre todos los accesos da 2,0 ciclos")
    print("> por fallo, menos que un acierto de L2, que es imposible.\n")


def tabla_slots(porniv):
    print("## Ocupacion por ranura\n")
    print("Cuantas operaciones fueron a cada ranura. S0 es la unica ALU que")
    print("escribe banderas, S1 la segunda ALU, S2 la unidad de memoria, S3")
    print("la cripto y S4 la de saltos.\n")
    print("| Ranura | -O0 | -O1 | -O2 |")
    print("|---|---|---|---|")
    nombres = ["S0 ALU-0", "S1 ALU-1", "S2 LSU", "S3 CRP", "S4 BRU"]
    for i, nombre in enumerate(nombres):
        clave = "ops_slot{}".format(i)
        celdas = " | ".join(
            "{} ({:.1f} %)".format(
                "{:,}".format(porniv[n][clave]).replace(",", " "),
                pct(porniv[n][clave], porniv[n]["instrucciones"]))
            for n in NIVELES)
        print("| {} | {} |".format(nombre, celdas))
    print()


def tabla_descomposicion(porniv):
    """La pregunta que la seccion 11.5 del analisis de arquitectura dejo
    abierta: si la asignacion de registros reduce mas ciclos que el
    empaquetado. Con los contadores se contesta por separacion de efectos."""
    o0, o2 = porniv["O0"], porniv["O2"]

    mem0 = o0["accesos_load"] + o0["accesos_store"]
    mem2 = o2["accesos_load"] + o2["accesos_store"]
    nomem0 = o0["instrucciones"] - mem0
    nomem2 = o2["instrucciones"] - mem2

    print("## Registros contra empaquetado: de donde sale la mejora\n")
    print("**Que operaciones cambian.**\n")
    print("| | -O0 | -O2 | |")
    print("|---|---|---|---|")
    print("| Operaciones de memoria | {} | {} | **{:+}** |".format(
        mem0, mem2, mem2 - mem0))
    print("| Operaciones que no son de memoria | {} | {} | **{:+}** |".format(
        nomem0, nomem2, nomem2 - nomem0))
    print("| Total | {} | {} | {:+} |".format(
        o0["instrucciones"], o2["instrucciones"],
        o2["instrucciones"] - o0["instrucciones"]))
    print()

    # Separacion: cuantos bundles se ahorran por emitir menos operaciones y
    # cuantos por meter mas operaciones en cada bundle.
    occ0 = o0["instrucciones"] / o0["bundles"]
    contrafactual = o2["instrucciones"] / occ0
    total = o0["bundles"] - o2["bundles"]
    por_ops = o0["bundles"] - contrafactual
    por_pack = contrafactual - o2["bundles"]

    print("**De donde salen los bundles que se ahorran.** Si se toman las")
    print("operaciones de `-O2` y se empaquetan con la ocupacion de `-O0`,")
    print("salen {:.0f} bundles. La diferencia contra los {} reales es lo que".format(
        contrafactual, o2["bundles"]))
    print("aporto empaquetar mejor; el resto es haber emitido menos.\n")
    print("| | Bundles | Del total |")
    print("|---|---|---|")
    print("| Por emitir menos operaciones | {:.0f} | **{:.1f} %** |".format(
        por_ops, pct(por_ops, total)))
    print("| Por empaquetar mejor | {:.0f} | **{:.1f} %** |".format(
        por_pack, pct(por_pack, total)))
    print("| Total ahorrado | {} | 100 % |".format(total))
    print()

    # De los accesos eliminados, cuantos eran aciertos.
    hits0 = o0["l1_load_hit"] + o0["l1_store_hit"]
    hits2 = o2["l1_load_hit"] + o2["l1_store_hit"]
    fallos0 = o0["l1_load_miss"] + o0["l1_store_miss"]
    fallos2 = o2["l1_load_miss"] + o2["l1_store_miss"]
    quitados = (hits0 - hits2) + (fallos0 - fallos2)
    print("**Por que la tasa de aciertos empeora mientras el costo baja.**")
    print("De los {} accesos que desaparecen, **{} ({:.2f} %) eran".format(
        quitados, hits0 - hits2, pct(hits0 - hits2, quitados)))
    print("aciertos**. La asignacion de registros se lleva justamente el")
    print("trafico facil --- el marco de pila, que siempre esta en cache ---")
    print("y deja el que no se puede evitar.\n")
    print("| | -O0 | -O2 | |")
    print("|---|---|---|---|")
    print("| Aciertos L1 | {} | {} | {:+.1f} % |".format(
        hits0, hits2, 100.0 * (hits2 - hits0) / hits0))
    print("| Fallos L1 (absolutos) | {} | {} | {:+.1f} % |".format(
        fallos0, fallos2, 100.0 * (fallos2 - fallos0) / fallos0))
    print("| Ciclos de stall por memoria | {} | {} | {:+.1f} % |".format(
        stalls_memoria(o0), stalls_memoria(o2),
        100.0 * (stalls_memoria(o2) - stalls_memoria(o0))
        / stalls_memoria(o0)))
    print()


def tabla_por_programa(datos, limite=12):
    print("## Los programas que mas cambian\n")
    todas = [(porniv["O2"]["ciclos"] - porniv["O0"]["ciclos"], prog,
              porniv["O0"]["ciclos"], porniv["O2"]["ciclos"], porniv)
             for prog, porniv in datos.items()]
    # El umbral vale solo para el ranking de los que mas mejoran: en un
    # programa de cien ciclos el prologo domina y el porcentaje engana. NO
    # vale para los que empeoran, que se reportan siempre y completos --- un
    # filtro que esconda justo el resultado incomodo no es un filtro.
    filas = [f for f in todas if f[2] >= 300]
    filas.sort(key=lambda f: 100.0 * f[0] / f[2])

    print("| Programa | ciclos -O0 | ciclos -O2 | | accesos -O0 | -O2 |")
    print("|---|---|---|---|---|---|")
    for _, prog, c0, c2, porniv in filas[:limite]:
        a0 = porniv["O0"]["accesos_load"] + porniv["O0"]["accesos_store"]
        a2 = porniv["O2"]["accesos_load"] + porniv["O2"]["accesos_store"]
        print("| `{}` | {} | {} | {:+.1f} % | {} | {} |".format(
            prog, c0, c2, 100.0 * (c2 - c0) / c0, a0, a2))

    empeoran = [f for f in todas if f[0] > 0]
    iguales = [f for f in todas if f[0] == 0]
    print("\n**Los que no mejoran, todos, sin umbral:**\n")
    if not empeoran and not iguales:
        print("Ninguno: los {} programas mejoran con `-O2`.".format(
            len(todas)))
    else:
        print("| Programa | ciclos -O0 | ciclos -O2 | |")
        print("|---|---|---|---|")
        for _, prog, c0, c2, _p in sorted(
                empeoran, key=lambda f: -100.0 * f[0] / f[2]):
            print("| `{}` | {} | {} | **{:+.1f} %** |".format(
                prog, c0, c2, 100.0 * (c2 - c0) / c0))
        for _, prog, c0, c2, _p in sorted(iguales, key=lambda f: f[1]):
            print("| `{}` | {} | {} | sin cambio |".format(prog, c0, c2))
    print()


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    directorio = sys.argv[1]
    if not os.path.isdir(directorio):
        print("no existe el directorio de medicion: {}".format(directorio),
              file=sys.stderr)
        return 2

    datos, parciales = cargar(directorio)
    if not datos:
        print("no hay ningun programa con los tres niveles en {}".format(
            directorio), file=sys.stderr)
        return 1

    desbordados = [p for p, v in datos.items()
                   if any(v[n].get("desbordado") for n in NIVELES)]
    if desbordados:
        print("AVISO: contadores desbordados en {}; sus cifras no valen"
              .format(", ".join(sorted(desbordados))), file=sys.stderr)

    porniv = {n: fila_global([v[n] for v in datos.values()])
              for n in NIVELES}

    print("# Iteracion 5: los niveles de optimizacion contra la jerarquia\n")
    print("{} programas, medidos sobre el RTL con la jerarquia de cache "
          "completa.\n".format(len(datos)))
    if parciales:
        print("> Sin los tres niveles, excluidos: {}\n".format(
            ", ".join(parciales)))

    tabla_resumen(porniv)
    tabla_derivadas(porniv)
    tabla_descomposicion(porniv)
    tabla_slots(porniv)
    tabla_por_programa(datos)
    return 0


if __name__ == "__main__":
    sys.exit(main())
