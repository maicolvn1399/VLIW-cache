#!/usr/bin/env python3
"""
Pruebas del nucleo del IDE.

Se ejecutan contra el binario 'novaide', no contra la interfaz: lo que hay que
garantizar es el comportamiento de la logica en C. La interfaz solo dibuja lo
que este le entrega, asi que si estas pruebas pasan, lo que el editor muestra
es correcto.

Los cinco bloques cubren las cuatro capacidades que pide el proyecto para la
Iteracion 1, mas la integridad del catalogo de diagnosticos:

  1. Catalogo       todo codigo que el compilador puede emitir esta descrito.
  2. Diagnosticos   cada programa de test/errores reporta el codigo que anuncia
                    su nombre, con posicion utilizable por el editor.
  3. Correcciones   los arreglos propuestos, aplicados en secuencia, llevan a un
                    programa que compila de verdad.
  4. Completado     el contexto del cursor decide que se ofrece.
  5. Clones         los Tipos I, II y III se clasifican como corresponde y el
                    caso negativo no se reporta.

Uso:  python3 test/ide/correr_pruebas.py [--verboso]
"""

import glob
import json
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", ".."))
NOVAIDE = os.path.join(RAIZ, "novaide")
NOVAC = os.path.join(RAIZ, "novac")

VERBOSO = "--verboso" in sys.argv

correctas = 0
fallidas = []


def comprobar(nombre, condicion, detalle=""):
    global correctas
    if condicion:
        correctas += 1
        if VERBOSO:
            print(f"  ok    {nombre}")
    else:
        fallidas.append((nombre, detalle))
        print(f"  FALLA {nombre}" + (f"\n          {detalle}" if detalle else ""))


def ide(*argumentos):
    r = subprocess.run([NOVAIDE] + list(argumentos),
                       capture_output=True, text=True, timeout=60, cwd=RAIZ)
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return {"error": "salida no es JSON", "crudo": r.stdout[:400],
                "stderr": r.stderr[:400]}


# ---------------------------------------------------------------- 1. catalogo

def prueba_catalogo():
    print("\n[1] Catalogo de diagnosticos")

    cat = ide("catalogo")
    comprobar("el catalogo responde JSON valido", "entradas" in cat, str(cat)[:200])
    if "entradas" not in cat:
        return

    descritos = {e["codigo"] for e in cat["entradas"]}

    # Codigos que las fases pueden emitir realmente, leidos de las fuentes.
    emitidos = set()
    fuentes = []
    for patron in ("fase*/*.c", "fase*/*.l", "fase*/*.y", "main.c"):
        fuentes += glob.glob(os.path.join(RAIZ, patron))
    for f in fuentes:
        if os.path.basename(f) in ("lex.yy.c", "nova.tab.c"):
            continue
        with open(f, encoding="utf-8", errors="replace") as fh:
            texto = fh.read()
        for m in re.finditer(r'diag_(?:error|advertencia)\s*\(\s*"([EW]\d+)"', texto):
            emitidos.add(m.group(1))

    faltan = sorted(emitidos - descritos)
    comprobar(f"los {len(emitidos)} codigos que emite el compilador estan en el catalogo",
              not faltan, f"sin describir: {', '.join(faltan)}")

    sin_remedio = [e["codigo"] for e in cat["entradas"]
                   if not e.get("remedio") or len(e["remedio"]) < 20]
    comprobar("toda entrada explica como se arregla", not sin_remedio,
              f"sin remedio util: {', '.join(sin_remedio)}")

    # El catalogo tiene que describir lo que el compilador EMITE, no lo que
    # uno cree que emite. Esta comprobacion dispara cada codigo con un
    # programa que lo provoca y verifica que el titulo corresponda al mensaje
    # real. Sin ella, el globo del editor puede quedar explicando otra cosa
    # distinta de la que dice el error, que es un fallo silencioso.
    disparos = {
        "E101": ("functio principale() -> integer {\n varia a : integer = 1 $ 2;\n redde a;\n}\n",
                 "Caracter no valido"),
        "E103": ("#{ sin cerrar\nfunctio principale() -> integer { redde 0; }\n",
                 "Comentario de bloque sin cerrar"),
        "E202": ("functio principale() -> integer {\n varia a : integer = 1\n redde a;\n}\n",
                 "Falta ';'"),
        "E203": ("functio f() -> integer {\n si (1 > 0) {\n  redde 1;\n}\n\n"
                 "functio principale() -> integer { redde f(); }\n",
                 "Bloque sin cerrar"),
        "E204": ("functio principale() -> integer {\n varia a = 1;\n redde a;\n}\n",
                 "Falta ': tipo' en la declaracion"),
        "E205": ("functio principale() -> integer {\n aliter { redde 1; }\n redde 0;\n}\n",
                 "'aliter' sin 'si'"),
        "E207": ("functio principale() -> integer\n redde 0;\n",
                 "Falta el '{' del cuerpo"),
        "E209": ("functio f(n : integer) {\n redde n;\n}\n"
                 "functio principale() -> integer { redde f(1); }\n",
                 "Falta '->'"),
        "E301": ("functio principale() -> integer {\n redde noexiste;\n}\n",
                 "Nombre no declarado"),
        "E302": ("functio principale() -> integer {\n varia a : integer = 1;\n"
                 " varia a : integer = 2;\n redde a;\n}\n",
                 "Nombre duplicado"),
        "E306": ("functio principale() -> integer {\n varia a : integer = 1;\n"
                 " si (a) { redde 1; }\n redde 0;\n}\n",
                 "Condicion que no es 'veritas'"),
        "E311": ("constans K : integer = 5;\nfunctio principale() -> integer {\n"
                 " K = 6;\n redde K;\n}\n",
                 "Asignacion a una constante"),
        "E316": ("functio principale() -> integer {\n varia a : integer = 5 / 0;\n"
                 " redde a;\n}\n",
                 "Division entre cero constante"),
        "E320": ("varia g : integer = 1;\n"
                 "functio principale() -> integer { redde 0; }\n",
                 "Declaracion global no permitida"),
    }

    temporal = os.path.join(AQUI, ".disparo.nv")
    desalineados, no_disparados = [], []
    for codigo, (fuente, titulo_esperado) in sorted(disparos.items()):
        with open(temporal, "w", encoding="utf-8") as f:
            f.write(fuente)
        r = ide("diagnosticar", temporal)
        emitidos = [d for d in r.get("diagnosticos", []) if d["codigo"] == codigo]
        if not emitidos:
            no_disparados.append(codigo)
            continue
        if emitidos[0].get("titulo") != titulo_esperado:
            desalineados.append(
                f"{codigo}: el compilador dice {emitidos[0]['mensaje'][:40]!r} "
                f"y el catalogo lo titula {emitidos[0].get('titulo')!r}")
    if os.path.exists(temporal):
        os.remove(temporal)

    comprobar(f"los {len(disparos)} codigos de muestra se disparan como se espera",
              not no_disparados, f"no se dispararon: {', '.join(no_disparados)}")
    comprobar("el titulo del catalogo corresponde al mensaje real del compilador",
              not desalineados, " | ".join(desalineados))

    fases = {e["fase"] for e in cat["entradas"]}
    comprobar("cada codigo queda asignado a una fase conocida",
              "desconocida" not in fases, f"fases: {fases}")


# ----------------------------------------------------------- 2. diagnosticos

def prueba_diagnosticos():
    print("\n[2] Diagnosticos")

    bien = ide("diagnosticar", os.path.join(AQUI, "correcto.nv"))
    comprobar("un programa correcto no reporta errores",
              bien.get("resumen", {}).get("errores") == 0, str(bien.get("diagnosticos"))[:200])
    comprobar("un programa correcto entrega su tabla de simbolos",
              len(bien.get("simbolos", [])) > 0)

    # Toda variable de la tabla trae su direccion de memoria: es el requisito
    # explicito del curso sobre la tabla de simbolos.
    variables = [s for s in bien.get("simbolos", [])
                 if s["clase"] in ("variable", "parametro")]
    comprobar("toda variable y parametro trae direccion de memoria",
              variables and all(s["direccion"] is not None and s["region"] == "DMEM"
                                for s in variables),
              str([(s["nombre"], s["region"], s["direccion"]) for s in variables]))
    comprobar("toda local trae su desplazamiento respecto de R14",
              all(s["desplazamiento_r14"] is not None for s in variables),
              str([(s["nombre"], s["desplazamiento_r14"]) for s in variables]))

    # Los programas de test/errores anuncian su codigo en el nombre.
    #
    # E405 ('no hay principale') queda fuera a proposito. Lo emite la
    # generacion de codigo al armar un ejecutable, y el editor no puede saber
    # si lo que se escribe es el programa o un modulo de biblioteca, que
    # legitimamente no tiene punto de entrada. Darlo como error dejaria todo
    # modulo marcado en rojo. El IDE informa la clase del archivo en su lugar,
    # y eso se comprueba aparte mas abajo.
    archivos = [a for a in sorted(glob.glob(os.path.join(RAIZ, "test", "errores", "E*.nv")))
                if "E405" not in os.path.basename(a)]
    comprobar("hay programas de error que revisar", len(archivos) > 10)

    aciertos, total = 0, 0
    for ruta in archivos:
        esperado = os.path.basename(ruta).split("_")[0]
        total += 1
        r = ide("diagnosticar", ruta)
        codigos = {d["codigo"] for d in r.get("diagnosticos", [])}
        if esperado in codigos:
            aciertos += 1
        elif VERBOSO:
            print(f"        {os.path.basename(ruta)}: esperaba {esperado}, "
                  f"reporto {sorted(codigos) or 'nada'}")

    comprobar(f"se reporta el codigo esperado en los {total} programas de error",
              aciertos == total, f"{aciertos}/{total} coinciden")

    # Toda posicion debe poder subrayarse.
    malas = []
    for ruta in archivos:
        for d in ide("diagnosticar", ruta).get("diagnosticos", []):
            if d["linea"] < 1 or d["columna"] < 1 or d["largo"] < 1:
                malas.append((os.path.basename(ruta), d["codigo"],
                              d["linea"], d["columna"], d["largo"]))
    comprobar("toda posicion reportada es subrayable (linea, columna y largo validos)",
              not malas, str(malas[:5]))

    # Puntos de salto. La guia (Fase 3) pide registrar las etiquetas de
    # condicionales y ciclos con su direccion en memoria.
    etqs = bien.get("etiquetas", [])
    comprobar("se registran los puntos de salto con su direccion",
              len(etqs) > 0 and all(e["direccion"] is not None for e in etqs),
              str(etqs[:3]))
    comprobar("las etiquetas de codigo traen su bundle de IMEM",
              any(e["region"] == "IMEM" and e["bundle"] is not None for e in etqs),
              str([(e["nombre"], e["region"], e["bundle"]) for e in etqs[:5]]))

    # Un programa con ciclo y condicional genera las etiquetas de ambos.
    ciclo = os.path.join(RAIZ, "prueba.nv")
    if os.path.isfile(ciclo):
        r = ide("diagnosticar", ciclo)
        nombres = " ".join(e["nombre"] for e in r.get("etiquetas", []))
        comprobar("un ciclo 'dum' produce su etiqueta de salto",
                  "L0" in nombres or "L1" in nombres, nombres[:160])
        comprobar("un condicional 'si' produce sus etiquetas de salto",
                  "_si" in nombres and "_fin" in nombres, nombres[:160])

    # La direccion de una etiqueta tiene que coincidir con la que muestra
    # 'novac --sym': el IDE no puede calcular una cosa y el compilador otra.
    sal = subprocess.run([NOVAC, "--sym", ciclo], capture_output=True,
                         text=True, cwd=RAIZ).stdout
    r = ide("diagnosticar", ciclo)
    coinciden = all(f"0x{e['direccion']:04X}" in sal
                    for e in r.get("etiquetas", []))
    comprobar("las direcciones del IDE coinciden con las de 'novac --sym'",
              coinciden)

    # Clase del archivo: ejecutable si tiene 'principale', modulo si no.
    r = ide("diagnosticar", os.path.join(RAIZ, "test", "errores",
                                         "E405_falta_principale.nv"))
    pe = r.get("punto_entrada", {})
    comprobar("un archivo sin 'principale' se informa como modulo, no como error",
              pe.get("clase") == "modulo" and
              not any(d["codigo"] == "E405" for d in r.get("diagnosticos", [])),
              str(pe))
    comprobar("un archivo con 'principale' se informa como ejecutable",
              bien.get("punto_entrada", {}).get("clase") == "ejecutable",
              str(bien.get("punto_entrada")))

    # El analisis no debe abortar aunque se pase del maximo de errores.
    muchos = os.path.join(AQUI, ".muchos_errores.nv")
    with open(muchos, "w", encoding="utf-8") as f:
        f.write("functio principale() -> integer {\n")
        for i in range(60):
            f.write(f"    varia v{i} : integer = {i}\n")
        f.write("    redde 0;\n}\n")
    r = ide("diagnosticar", muchos)
    comprobar("no se aborta al superar el maximo de errores",
              r.get("resumen", {}).get("errores", 0) > 25,
              f"errores reportados: {r.get('resumen')}")
    os.remove(muchos)


# ----------------------------------------------------------- 3. correcciones

def aplicar(texto, edicion):
    lineas = texto.split("\n")
    while len(lineas) < edicion["linea"]:
        lineas.append("")
    i = edicion["linea"] - 1
    col = edicion["columna"] - 1
    l = lineas[i]
    if len(l) < col:
        l += " " * (col - len(l))
    lineas[i] = l[:col] + edicion["insertar"] + l[col + edicion.get("borrar", 0):]
    return "\n".join(lineas)


def prueba_correcciones():
    print("\n[3] Correccion automatica de errores")

    casos = [
        ("sin_punto_coma.nv", "varios ';' faltantes"),
        ("llave_sin_cerrar.nv", "una '}' faltante"),
        ("parentesis_sin_cerrar.nv", "un ')' faltante"),
        ("bloque_interno_sin_cerrar.nv", "un bloque interno sin cerrar"),
    ]

    temporal = os.path.join(AQUI, ".arreglando.nv")

    for archivo, descripcion in casos:
        origen = os.path.join(AQUI, archivo)
        with open(origen, encoding="utf-8") as f:
            texto = f.read()

        pasos = 0
        for _ in range(30):
            with open(temporal, "w", encoding="utf-8") as f:
                f.write(texto)
            d = ide("diagnosticar", temporal)
            if d.get("resumen", {}).get("errores", 1) == 0:
                break
            a = ide("arreglar", temporal)
            if not a.get("correcciones"):
                break
            texto = aplicar(texto, a["correcciones"][0]["ediciones"][0])
            pasos += 1

        with open(temporal, "w", encoding="utf-8") as f:
            f.write(texto)
        r = subprocess.run([NOVAC, temporal, "-o", os.devnull],
                           capture_output=True, text=True, cwd=RAIZ)
        comprobar(f"{archivo} ({descripcion}) queda compilando tras {pasos} correccion(es)",
                  r.returncode == 0, r.stderr.strip()[:300])

    if os.path.exists(temporal):
        os.remove(temporal)

    # Un archivo correcto no debe generar arreglos.
    a = ide("arreglar", os.path.join(AQUI, "correcto.nv"))
    comprobar("un programa correcto no genera correcciones",
              a.get("total") == 0, str(a.get("correcciones"))[:200])

    # Los arreglos derivados del parser se marcan con confianza alta.
    a = ide("arreglar", os.path.join(AQUI, "sin_punto_coma.nv"))
    comprobar("los ';' faltantes se proponen con confianza alta",
              a.get("correcciones") and
              all(c["confianza"] == "alta" for c in a["correcciones"]
                  if c["codigo"] == "E202"))


# ------------------------------------------------------------ 4. completado

def prueba_completado():
    print("\n[4] Sugerencias de codigo")

    ruta = os.path.join(AQUI, "correcto.nv")
    with open(ruta, encoding="utf-8") as f:
        lineas = f.read().split("\n")

    # Linea 6: "    varia r : integer = doble(21);"
    fila = next(i for i, l in enumerate(lineas) if "varia r" in l) + 1

    # Despues de los dos puntos se ofrecen tipos y nada mas.
    col = lineas[fila - 1].index(":") + 3
    r = ide("completar", ruta, "--linea", str(fila), "--columna", str(col))
    nombres = {s["nombre"] for s in r.get("sugerencias", [])}
    comprobar("tras ':' el contexto es de tipo", r.get("contexto") == "tipo",
              f"contexto: {r.get('contexto')}")
    comprobar("tras ':' se ofrecen los cuatro tipos del lenguaje",
              nombres == {"integer", "veritas", "textus", "nihil"}, str(nombres))

    # Al inicio de una sentencia se ofrecen plantillas y palabras reservadas.
    r = ide("completar", ruta, "--linea", str(fila), "--columna", "5")
    clases = {s["clase"] for s in r.get("sugerencias", [])}
    comprobar("al inicio de sentencia se ofrecen plantillas",
              "plantilla" in clases, str(clases))
    comprobar("al inicio de sentencia se conoce la funcion que contiene al cursor",
              r.get("funcion") == "principale", f"funcion: {r.get('funcion')}")

    # Fuera de toda funcion solo caben 'constans' y 'functio'.
    r = ide("completar", ruta, "--linea", "1", "--columna", "1")
    nombres = {s["nombre"] for s in r.get("sugerencias", [])}
    comprobar("fuera de las funciones el contexto es global",
              r.get("contexto") == "global", f"contexto: {r.get('contexto')}")
    comprobar("fuera de las funciones no se ofrece 'varia'",
              "varia" not in nombres, str(nombres))

    # El prefijo filtra, incluso con el cursor dentro de la palabra.
    fila_doble = next(i for i, l in enumerate(lineas) if "doble(21)" in l) + 1
    col_doble = lineas[fila_doble - 1].index("doble") + 4   # "dob|le"
    r = ide("completar", ruta, "--linea", str(fila_doble), "--columna", str(col_doble))
    comprobar("el prefijo se toma hasta el cursor, no la palabra completa",
              r.get("prefijo") == "dob", f"prefijo: {r.get('prefijo')!r}")
    comprobar("el prefijo filtra las sugerencias",
              all(s["nombre"].startswith("dob") for s in r.get("sugerencias", [])),
              str([s["nombre"] for s in r.get("sugerencias", [])]))
    comprobar("una funcion propia aparece entre las sugerencias",
              "doble" in {s["nombre"] for s in r.get("sugerencias", [])})

    # Las sugerencias traen la direccion de memoria cuando el archivo analiza.
    r = ide("completar", ruta, "--linea", str(fila_doble), "--columna", "5")
    con_dir = [s for s in r.get("sugerencias", [])
               if "DMEM" in s.get("documentacion", "") or "IMEM" in s.get("documentacion", "")]
    comprobar("las sugerencias informan donde vive cada nombre en memoria",
              len(con_dir) > 0)

    # Sobre un archivo roto el completado sigue respondiendo.
    r = ide("completar", os.path.join(AQUI, "sin_punto_coma.nv"),
            "--linea", "4", "--columna", "5")
    comprobar("el completado responde aunque el archivo no compile",
              len(r.get("sugerencias", [])) > 0, str(r)[:200])

    # Y conserva los tipos y la direccion de memoria.
    #
    # Es el caso NORMAL al completar: el identificador a medio escribir rompe
    # la sintaxis. Si el analisis se rindiera ahi, el globo no mostraria nunca
    # ni el tipo ni la direccion, que es justo lo que se quiere ver. El segundo
    # intento sin el prefijo es lo que lo resuelve.
    medio = os.path.join(AQUI, "a_medio_escribir.nv")
    r = ide("completar", medio, "--linea", "6", "--columna",
            str(len("        i = i + 1; tot") + 1))
    comprobar("el prefijo a medio escribir se reconoce",
              r.get("prefijo") == "tot", f"prefijo: {r.get('prefijo')!r}")
    comprobar("se recuperan los tipos aunque el buffer no compile",
              r.get("con_tipos") is True, f"con_tipos: {r.get('con_tipos')}")
    sug = [s for s in r.get("sugerencias", []) if s["nombre"] == "total"]
    comprobar("la sugerencia trae su tipo",
              sug and "integer" in sug[0]["detalle"],
              str(sug[:1]))
    comprobar("la sugerencia trae su direccion de memoria",
              sug and "DMEM @0x" in sug[0].get("documentacion", ""),
              str(sug[:1]))


# ------------------------------------------------- 5. bloques basicos y CFG

def prueba_bloques():
    print("\n[5] Bloques basicos y grafo de flujo")

    # --- Programa recto: una funcion sin saltos es un solo bloque ---
    r = ide("bloques", os.path.join(AQUI, "cfg_recto.nv"))
    comprobar("el grafo se construye sobre un programa correcto",
              r.get("ok") is True, str(r)[:200])
    if not r.get("ok"):
        return
    fn = {f["nombre"]: f for f in r["funciones"]}
    comprobar("una funcion sin saltos es un unico bloque basico",
              fn["sumar"]["bloques"] == 1 and fn["sumar"]["aristas"] == 0,
              str(fn.get("sumar")))

    # --- Ciclo con condicionales anidados ---
    r = ide("bloques", os.path.join(AQUI, "cfg_ciclo.nv"))
    fn = {f["nombre"]: f for f in r["funciones"]}["clasificar"]
    b = {x["id"]: x for x in fn["lista"]}

    comprobar("el bloque 0 es la entrada y no tiene predecesores",
              b[0]["entrada"] and b[0]["predecesores"] == [], str(b[0]))

    # Toda arista tiene su predecesor correspondiente: el grafo es coherente.
    incoherentes = []
    for x in fn["lista"]:
        for s in x["sucesores"]:
            if x["id"] not in b[s]["predecesores"]:
                incoherentes.append(f"B{x['id']}->B{s}")
    comprobar("cada sucesor registra a su predecesor",
              not incoherentes, ", ".join(incoherentes))

    # La suma de aristas declarada coincide con las que hay.
    total = sum(len(x["sucesores"]) for x in fn["lista"])
    comprobar("la cuenta de aristas coincide con las aristas listadas",
              total == fn["aristas"], f"{total} != {fn['aristas']}")

    # Un ciclo produce al menos una arista de regreso (destino <= origen).
    regresos = [(x["id"], s) for x in fn["lista"] for s in x["sucesores"] if s <= x["id"]]
    comprobar("un ciclo 'dum' produce una arista de regreso",
              len(regresos) >= 1, str(regresos))

    # El destino de la arista de regreso es la cabeza del lazo, y tanto ella
    # como el cuerpo quedan marcados como 'en lazo'.
    cabeza = regresos[0][1]
    comprobar("la cabeza del lazo queda marcada dentro del ciclo",
              b[cabeza]["profundidad_ciclo"] > 0, str(b[cabeza]))
    en_lazo = [x["id"] for x in fn["lista"] if x["profundidad_ciclo"] > 0]
    comprobar("el cuerpo del lazo queda marcado y el resto no",
              len(en_lazo) > 1 and len(en_lazo) < fn["bloques"],
              f"en lazo: {en_lazo} de {fn['bloques']}")

    # Un condicional produce exactamente dos salidas.
    cond = [x for x in fn["lista"] if x["fin"] == "condicional"]
    comprobar("todo bloque condicional tiene dos sucesores",
              cond and all(len(x["sucesores"]) == 2 for x in cond),
              str([(x["id"], x["sucesores"]) for x in cond]))

    # Los dos 'si' anidados mas la condicion del 'dum' dan tres condicionales.
    comprobar("se reconocen los tres puntos de decision del programa",
              len(cond) == 3, f"condicionales: {[x['id'] for x in cond]}")

    # Todo bloque salvo la entrada es alcanzable en este programa.
    comprobar("no hay bloques inalcanzables en un programa sin codigo muerto",
              fn["inalcanzables"] == 0, str(fn))

    # --- Codigo muerto ---
    r = ide("bloques", os.path.join(AQUI, "cfg_muerto.nv"))
    fn = r["funciones"][0]
    muertos = [x for x in fn["lista"] if not x["alcanzable"]]
    comprobar("el codigo despues de un retorno queda en un bloque inalcanzable",
              fn["inalcanzables"] >= 1 and len(muertos) == fn["inalcanzables"],
              str(fn))
    comprobar("un bloque inalcanzable no tiene predecesores",
              all(x["predecesores"] == [] for x in muertos), str(muertos))

    # --- El IDE y novac tienen que dar el mismo grafo ---
    ruta = os.path.join(AQUI, "cfg_ciclo.nv")
    texto = subprocess.run([NOVAC, "--bloques", ruta],
                           capture_output=True, text=True, cwd=RAIZ).stdout
    r = ide("bloques", ruta)
    fn = {f["nombre"]: f for f in r["funciones"]}["clasificar"]
    esperado = f"functio clasificar: {fn['bloques']} bloques, {fn['aristas']} aristas"
    comprobar("'novac --bloques' y el IDE reportan el mismo grafo",
              esperado in texto, esperado)

    # --- Sin analisis limpio no hay grafo, y se explica por que ---
    r = ide("bloques", os.path.join(AQUI, "sin_punto_coma.nv"))
    comprobar("sobre un programa con errores no se construye el grafo",
              r.get("ok") is False and r.get("motivo"), str(r)[:160])


# ---------------------------------------------------------------- 6. clones

def prueba_clones():
    print("\n[6] Deteccion de clones")

    d = os.path.join(AQUI, "clones")
    archivos = [os.path.join(d, n) for n in
                ("base.nv", "tipo1.nv", "tipo2.nv", "tipo3.nv",
                 "ninguno.nv", "copia_de_base.nv")]
    r = ide("clones", *archivos, "--min-tokens", "20")
    comprobar("la deteccion de clones responde", "clones" in r, str(r)[:200])
    if "clones" not in r:
        return

    def buscar(unidad_a, unidad_b):
        for c in r["clones"]:
            nombres = {c["a"]["unidad"], c["b"]["unidad"]}
            if nombres == {unidad_a, unidad_b}:
                return c
        return None

    c1 = buscar("promedio", "promedio")
    comprobar("la copia exacta se clasifica como Tipo I",
              c1 is not None and c1["tipo"] == "I",
              f"encontrado: {c1['tipo'] if c1 else 'nada'}")

    c2 = buscar("promedio", "media")
    comprobar("la copia renombrada se clasifica como Tipo II",
              c2 is not None and c2["tipo"] == "II",
              f"encontrado: {c2['tipo'] if c2 else 'nada'}")
    comprobar("el renombrado de la copia Tipo II se detecta consistente",
              c2 is not None and c2["renombrado"] == "consistente",
              f"renombrado: {c2['renombrado'] if c2 else 'nada'}")
    comprobar("se cuentan los identificadores que cambiaron de nombre",
              c2 is not None and c2["identificadores_cambiados"] >= 4,
              f"cambiados: {c2['identificadores_cambiados'] if c2 else 0}")

    c3 = buscar("promedio", "promedio_contado")
    comprobar("la copia con sentencias agregadas se clasifica como Tipo III",
              c3 is not None and c3["tipo"] == "III",
              f"encontrado: {c3['tipo'] if c3 else 'nada'}")
    comprobar("la similitud del Tipo III queda entre el umbral y 1",
              c3 is not None and 0.80 <= c3["similitud"] < 1.0,
              f"similitud: {c3['similitud'] if c3 else 0}")

    # Caso negativo: lo que no es copia no debe reportarse.
    falsos = [c for c in r["clones"]
              if "ordenar_par" in (c["a"]["unidad"], c["b"]["unidad"])]
    comprobar("una funcion sin relacion no se reporta como clon de ninguna",
              not falsos,
              str([(c["tipo"], c["a"]["unidad"], c["b"]["unidad"],
                    round(c["similitud"], 2)) for c in falsos]))

    falsos2 = [c for c in r["clones"]
               if {c["a"]["unidad"], c["b"]["unidad"]} == {"promedio", "distinta"}]
    comprobar("dos funciones que solo comparten el esqueleto no son clones",
              not falsos2, str(falsos2)[:200])

    # El archivo duplicado con otro nombre se detecta como tal.
    completos = [c for c in r["clones"] if c["archivo_completo"]]
    comprobar("un archivo duplicado con otro nombre se detecta completo",
              any(c["tipo"] == "I" for c in completos),
              str([(c["tipo"], c["a"]["archivo"], c["b"]["archivo"]) for c in completos]))

    # El filtro por tamano debe excluir unidades pequenas.
    chico = ide("clones", *archivos, "--min-tokens", "5000")
    comprobar("--min-tokens excluye las unidades pequenas",
              chico.get("resumen", {}).get("total") == 0,
              str(chico.get("resumen")))

    # Las posiciones reportadas tienen que servir para saltar al codigo.
    malas = [c for c in r["clones"]
             if c["a"]["linea_inicio"] < 1 or c["b"]["linea_inicio"] < 1
             or c["a"]["linea_fin"] < c["a"]["linea_inicio"]]
    comprobar("las ubicaciones de cada clon son utilizables", not malas, str(malas[:3]))


# ------------------------------------------------------------------ arranque

def main():
    if not os.path.isfile(NOVAIDE):
        print(f"No se encontro {NOVAIDE}. Compile con 'make' primero.")
        return 1

    print("Pruebas del nucleo del IDE (novaide)")
    print("=" * 62)

    prueba_catalogo()
    prueba_diagnosticos()
    prueba_correcciones()
    prueba_completado()
    prueba_bloques()
    prueba_clones()

    print("=" * 62)
    if fallidas:
        print(f"pruebas del IDE: {correctas} correctas, {len(fallidas)} fallidas")
        return 1
    print(f"pruebas del IDE: {correctas} correctas, 0 fallidas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
