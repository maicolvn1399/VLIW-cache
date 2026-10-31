#!/usr/bin/env python3
"""
empacar.py - El planificador de bundles de CERBERO.

CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4

Toma un programa en ensamblador con una instruccion por bundle y lo reescribe
metiendo en un mismo bundle todas las operaciones que son independientes entre
si. Es la fase que convierte un codigo correcto en codigo VLIW.

    python3 tools/empacar.py programa.s -o programa_empacado.s
    python3 tools/empacar.py programa.s --informe

-----------------------------------------------------------------------------
POR QUE ESTA HERRAMIENTA EXISTE
-----------------------------------------------------------------------------
Un bundle de CERBERO tiene cinco ranuras y el procesador las ejecuta todas en
el mismo ciclo. Un programa que pone una sola instruccion por bundle es
correcto, pero desperdicia cuatro quintas partes de la maquina: corre a la
velocidad de un procesador escalar con una penalizacion de tres bundles por
cada dependencia. Si el codigo generado no empaqueta, el VLIW no esta siendo
un VLIW.

La medida antes de empacar, sobre los 22 programas del compilador NOVA:

    19534 bundles, 6003 instrucciones, 0.31 por bundle de 5 posibles
    bundles con mas de una instruccion: 0 de 19534
    S1 (ALU-1) sin usar en todo el conjunto

-----------------------------------------------------------------------------
DE DONDE SALE EL MODELO DE DEPENDENCIAS
-----------------------------------------------------------------------------
De `cerbero_asm.py`, no de una tabla propia. El ensamblador ya calcula, para
cada instruccion, el conjunto de recursos que lee y el que escribe -- incluidas
las banderas, que trata como un registro mas. Este planificador importa esa
clase y llama a sus codificadores.

Duplicar esa informacion seria el error clasico: el dia que alguien agregue un
opcode o cambie que registro lee una instruccion, el ensamblador lo sabria y el
planificador no, y el resultado serian bundles que ensamblan sin queja y
calculan mal. Por eso aqui no hay ni una tabla de opcodes.

-----------------------------------------------------------------------------
LAS REGLAS QUE RESPETA
-----------------------------------------------------------------------------
1. Latencia de 3 bundles. Entre el bundle que produce un valor y el que lo
   consume tiene que haber dos de por medio (isa.md 9.1). Vale igual para las
   banderas: un `cmp` y el salto que las lee.

2. Un solo escritor por recurso y por bundle. Dos ranuras que escriban el mismo
   registro en el mismo bundle son un WCONF: el hardware se queda con la de
   menor indice y lo marca en el PSW.

3. Las ranuras que admite cada instruccion. Las dos ALU son intercambiables,
   salvo las comparaciones, que solo existen en S0 porque es la unica que
   escribe banderas.

4. El orden de la memoria se conserva. Dos accesos a memoria no se reordenan
   entre si, porque este planificador no hace analisis de alias: no puede saber
   si `sw r1,#0(r5)` y `lw r2,#0(r6)` tocan la misma direccion.

5. El orden de la boveda se conserva, por la misma razon y una mas: AUTHW,
   LOGIN y KSETW son una maquina de estados, y reordenarlos rompe el protocolo
   de isa.md 8.2.

6. Un salto cierra su bloque y va en el ultimo bundle. Detras queda su delay
   slot, que el ISA ejecuta siempre. La v1.2 prohibe un salto en el delay slot
   de otro, asi que el delay slot nunca recibe uno.

7. Solo se reordena dentro de un bloque basico. Una etiqueta corta el bloque:
   como a ella se puede llegar por un salto desde cualquier parte, mover una
   operacion a traves de una etiqueta cambiaria lo que ve quien salte ahi.

8. Al cerrar un bloque, las escrituras pendientes se dejan asentar. Si la
   ultima escritura cae en el bundle W, el bloque se extiende hasta W+2, de
   modo que el primer bundle del bloque siguiente ya puede leer ese registro.
   Sin esto, empacar un bloque acercaria su final al bloque que sigue y
   romperia la latencia justo en la frontera, que es donde nadie la mira.

-----------------------------------------------------------------------------
COMO SE COMPRUEBA QUE NO ROMPE NADA
-----------------------------------------------------------------------------
Por dos caminos independientes, y los dos hacen falta:

  - `cerbero_asm.py` ensambla la salida y **no emite ni una advertencia**. El
    ensamblador ya comprueba la latencia y los conflictos de escritura, asi que
    es un verificador que no comparte codigo con el planificador.

  - El programa empacado corre en el RTL y da **el mismo resultado** que el
    original. `probar_empacado.py` lo hace con todos los programas del
    proyecto.

Un planificador que se equivoca produce codigo que ensambla bien y calcula mal,
asi que la segunda comprobacion es la que de verdad cuenta.
"""

import argparse
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import cerbero_asm as asm                                      # noqa: E402

# Las cinco ranuras, con el ancho de columna con que se imprimen
NOMBRE_SLOT = ("S0", "S1", "S2", "S3", "S4")
ANCHO_COL = (26, 26, 24, 20, 18)

# Cuantos bundles tiene que haber entre el productor y el consumidor
LATENCIA = 3


class Operacion:
    """Una instruccion suelta, con lo que lee, lo que escribe y donde cabe."""

    def __init__(self, texto, slots, escribe, lee, linea, orden):
        self.texto = texto
        self.slots = slots          # ranuras donde puede ir, por preferencia
        self.escribe = escribe      # recursos que escribe
        self.lee = lee              # recursos que lee
        self.linea = linea          # linea del fuente original
        self.orden = orden          # posicion en el bloque, para desempatar
        self.bundle = None          # donde quedo colocada
        self.slot = None

    @property
    def es_salto(self):
        return 4 in self.slots

    @property
    def es_memoria(self):
        return self.slots == [2]

    @property
    def es_boveda(self):
        return self.slots == [3]

    def __repr__(self):
        return f"<{self.texto}>"


class Empacador:
    def __init__(self, ruta, verboso=False):
        self.ruta = ruta
        self.verboso = verboso
        self.avisos = []

        # Un ensamblador de verdad, para que el analisis de dependencias sea
        # exactamente el suyo. Se le corre la primera pasada para que tenga la
        # tabla de etiquetas: sin ella no se puede codificar un salto.
        self.e = asm.Ensamblador(asm.cargar_defs(
            os.path.join(AQUI, "..", "src", "cpu", "cerbero_defs.svh")))

        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
        texto = self.e.expandir_includes(texto, ruta)
        self.lineas = texto.splitlines()
        self.e.primera_pasada(self.lineas)
        if self.e.errores:
            for err in self.e.errores:
                print(f"error: {err}", file=sys.stderr)
            raise SystemExit(1)

    # -- analisis -----------------------------------------------------------

    def analizar(self, texto, i_slot, linea):
        """Lo que una instruccion lee y escribe, segun el ensamblador."""
        # Se silencian los avisos del ensamblador durante el analisis: aqui se
        # le pregunta por una instruccion suelta y fuera de su contexto, asi
        # que sus comprobaciones de latencia no tienen sentido todavia.
        guardadas = self.e.advertencias
        self.e.advertencias = []
        try:
            if i_slot in (0, 1):
                _, esc, lee = self.e._enc_alu(texto, i_slot, linea, texto)
            elif i_slot == 2:
                _, esc, lee = self.e._enc_lsu(texto, linea, texto)
            elif i_slot == 3:
                _, esc, lee = self.e._enc_s3(texto, linea, texto)
            else:
                # El codificador de saltos necesita una direccion para calcular
                # el desplazamiento, y aqui no interesa: solo se le pregunta
                # que lee y que escribe. Se le pasa la direccion de la propia
                # etiqueta destino para que el desplazamiento salga cerca de
                # cero; con direccion 0 un salto a la region segura se sale del
                # campo de 10 bits y el analisis fallaria por una razon que no
                # tiene nada que ver con la dependencia.
                campos = texto.split()
                destino = campos[-1] if len(campos) > 1 else ""
                base = self.e.etiquetas.get(destino, 0)
                _, esc, lee, _ = self.e._enc_s4(texto, base, linea, texto)
        finally:
            self.e.advertencias = guardadas
        return set(esc), set(lee)

    # -- renombrado de registros --------------------------------------------
    #
    # Es lo que de verdad desbloquea el paralelismo, y conviene entender por
    # que. El generador de codigo usa R10 y R11 como unicos temporales y los
    # reutiliza en cada sentencia:
    #
    #     lw   r10, #0(r14)      <- sentencia 1
    #     lw   r11, #8(r14)
    #     add  r10, r10, r11
    #     sw   r10, #4(r14)
    #     lw   r10, #12(r14)     <- sentencia 2, no depende de la 1
    #     ...
    #
    # Las dos sentencias son independientes, pero comparten R10. Eso es una
    # dependencia FALSA: no hay un dato que viaje de una a otra, solo un
    # nombre reutilizado. El planificador no puede solaparlas y el programa
    # queda tan serial como en un procesador escalar.
    #
    # Renombrar la segunda a un registro libre rompe esa cadena y deja que las
    # dos sentencias ocupen los mismos bundles. Es lo mismo que hace por
    # hardware un procesador fuera de orden; en un VLIW le toca al compilador.
    #
    # CUANDO ES SEGURO
    # Solo se renombra una definicion que esta MUERTA al salir del bloque, y
    # eso se sabe sin analisis de flujo: si el bloque escribe R varias veces,
    # todas menos la ultima mueren dentro del bloque, porque la siguiente las
    # pisa. La ultima se deja como estaba, por si alguien la lee despues.
    #
    # Y solo se renombra HACIA registros que el programa entero no menciona ni
    # una vez. Si un registro no aparece en ninguna linea, nadie puede tener un
    # valor vivo en el. R0, R14 y R15 quedan fuera aunque no aparezcan: R0 se
    # usa por convencion como base cero en el codigo escrito a mano, R14 es la
    # pila y R15 el enlace.

    PROHIBIDOS = {0, 14, 15}

    def registros_libres(self):
        """Los que no aparecen en ninguna linea del programa."""
        usados = set()
        en_datos = False
        for l in self.lineas:
            limpia = l.split("//")[0]
            if limpia.strip().startswith(".data"):
                en_datos = True
            elif limpia.strip().startswith(".text"):
                en_datos = False
            if en_datos:
                continue
            for m in re.finditer(r"\br(\d+)\b", limpia):
                usados.add(int(m.group(1)))
        return [r for r in range(16)
                if r not in usados and r not in self.PROHIBIDOS]

    @staticmethod
    def _regs_del_texto(texto):
        return {int(m.group(1)) for m in re.finditer(r"\br(\d+)\b", texto)}

    def renombrar(self, ops, libres):
        """Rompe las dependencias falsas dentro de un bloque.

        Devuelve cuantas definiciones se renombraron. Modifica el texto de las
        operaciones y vuelve a analizarlas, de modo que lo que el planificador
        ve despues es coherente con lo que el ensamblador va a codificar.
        """
        if not libres:
            return 0

        # Un par de F4E/F4D son dos registros adyacentes con un indice de par:
        # renombrarlos exigiria mover el par entero. Se dejan fuera.
        intocables = set()
        for op in ops:
            if op.texto.split()[0].lower() in ("f4e", "f4d"):
                intocables |= op.escribe | op.lee

        # Cuantas veces se define cada registro en el bloque
        definiciones = {}
        for k, op in enumerate(ops):
            for r in op.escribe:
                if r < 16:
                    definiciones.setdefault(r, []).append(k)

        # Nombre vigente de cada registro, y hasta donde llega cada alias
        vigente = {}
        libre_desde = {t: 0 for t in libres}     # alias -> indice donde queda libre
        alias_de = {}                            # alias -> registro original
        renombradas = 0

        for k, op in enumerate(ops):
            regs = self._regs_del_texto(op.texto)
            mapa = {}

            for r in regs:
                # Una operacion que lee Y escribe el mismo registro no abre un
                # rango nuevo: lo continua. Es el caso de movh, de la ALU corta
                # (que es destructiva) y del postincremento de LW.INC.
                lee_y_escribe = (r in op.escribe) and (r in op.lee)

                if r in op.escribe and not lee_y_escribe:
                    defs = definiciones.get(r, [])
                    es_ultima = (not defs) or (k == defs[-1])
                    if es_ultima or r in intocables:
                        vigente[r] = r          # se queda como estaba
                    else:
                        # Un alias que ya no este vivo
                        elegido = None
                        for t in libres:
                            if libre_desde[t] <= k and t not in intocables:
                                elegido = t
                                break
                        if elegido is None:
                            vigente[r] = r
                        else:
                            # Vive hasta la siguiente definicion de r
                            siguiente = next((d for d in defs if d > k), len(ops))
                            libre_desde[elegido] = siguiente
                            alias_de[elegido] = r
                            vigente[r] = elegido
                            renombradas += 1
                if r in vigente and vigente[r] != r:
                    mapa[r] = vigente[r]

            if mapa:
                def sust(m):
                    v = int(m.group(1))
                    return f"r{mapa.get(v, v)}"
                op.texto = re.sub(r"\br(\d+)\b", sust, op.texto)
                op.escribe, op.lee = self.analizar(
                    op.texto, op.slots[0], op.linea)

        return renombradas

    def ranuras_de(self, texto, linea):
        """Donde puede ir esta instruccion, por orden de preferencia.

        Devuelve None si el texto no es una instruccion reconocible, lo que
        hace que el empacador deje el bloque como estaba en vez de adivinar.
        """
        mn = texto.split()[0].lower()

        if mn in self.e.alu:
            # solo_s0 es el tercer campo de la tabla: las comparaciones, que
            # escriben banderas, solo existen en S0
            _, _, solo_s0 = self.e.alu[mn]
            return [0] if solo_s0 else [0, 1]
        if mn in self.e.lsu:
            return [2]
        if mn in self.e.salu or mn in self.e.vctl or \
           mn in ("f4e", "f4d", "ksetw", "authw"):
            return [3]
        # Los saltos llevan sufijo de condicion: br.ne, jal.al, jr.al...
        base = mn.split(".")[0]
        if base in self.e.bru_rel or base in self.e.bru_ind or mn == "halt":
            return [4]
        return None

    # -- lectura del fuente -------------------------------------------------

    def leer_bloques(self):
        """Parte el fuente en trozos: cabecera, bloques de codigo y datos.

        Cada elemento es ('texto', lineas) para lo que se copia tal cual, o
        ('bloque', operaciones) para lo que se puede reordenar.
        """
        piezas = []
        buffer_txt = []
        ops = []
        orden = 0
        seccion = "text"

        def cerrar_texto():
            if buffer_txt:
                piezas.append(("texto", list(buffer_txt)))
                buffer_txt.clear()

        def cerrar_bloque():
            nonlocal ops, orden
            if ops:
                piezas.append(("bloque", ops))
                ops = []
                orden = 0

        for n, cruda in enumerate(self.lineas, start=1):
            sin_com = cruda.split("//")[0]
            limpia = sin_com.strip()

            if not limpia:
                # Una linea en blanco o un comentario suelto no corta nada:
                # se guarda para reponerlo si el bloque no se toca
                continue

            # Directivas y cambios de seccion: cortan el bloque
            if limpia.startswith("."):
                cerrar_bloque()
                cerrar_texto()
                if limpia.split()[0].lower() in (".text", ".data"):
                    seccion = limpia.split()[0].lower()[1:]
                piezas.append(("texto", [cruda]))
                continue

            if seccion == "data":
                cerrar_bloque()
                buffer_txt.append(cruda)
                continue

            # Etiquetas: cortan el bloque, porque se puede saltar a ellas
            etiquetas = []
            resto = limpia
            while True:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", resto)
                if not m:
                    break
                etiquetas.append(m.group(1))
                resto = m.group(2).strip()
            if etiquetas:
                cerrar_bloque()
                cerrar_texto()
                for et in etiquetas:
                    piezas.append(("texto", [f"{et}:"]))
                if not resto:
                    continue
                limpia = resto

            if not limpia.endswith(";"):
                # No es un bundle: se copia tal cual y se corta, por prudencia
                cerrar_bloque()
                buffer_txt.append(cruda)
                continue

            cerrar_texto()

            # Las ranuras del bundle tal como venia escrito
            crudos = [p.strip() for p in limpia[:-1].split("|")]
            for texto in crudos:
                if texto in ("", "-") or texto.split()[0].lower() == "nop":
                    continue
                slots = self.ranuras_de(texto, n)
                if slots is None:
                    self.avisos.append(
                        f"linea {n}: no reconozco '{texto}', el bloque queda "
                        f"sin empacar")
                    cerrar_bloque()
                    buffer_txt.append(cruda)
                    break
                try:
                    esc, lee = self.analizar(texto, slots[0], n)
                except asm.ErrorEnsamblado as err:
                    self.avisos.append(f"linea {n}: {err.mensaje}")
                    cerrar_bloque()
                    buffer_txt.append(cruda)
                    break
                op = Operacion(texto, slots, esc, lee, n, orden)
                orden += 1
                ops.append(op)
                # Un salto cierra el bloque: lo que venga detras es su delay
                # slot y pertenece ya al flujo siguiente
                if op.es_salto:
                    cerrar_bloque()
                    break

        cerrar_bloque()
        cerrar_texto()
        return piezas

    # -- planificacion ------------------------------------------------------

    def planificar(self, ops):
        """Coloca las operaciones del bloque en el menor numero de bundles.

        Planificacion de lista: se recorren las operaciones en el orden del
        programa y cada una va al primer bundle donde quepa sin romper ninguna
        regla. Recorrerlas en orden es lo que hace que WAR y WAW se cumplan
        solos, y lo que deja el resultado reproducible.
        """
        bundles = []        # cada uno: lista de 5 ranuras, None si libre

        def asegurar(b):
            while len(bundles) <= b:
                bundles.append([None] * 5)

        colocadas = []      # operaciones ya colocadas, con su bundle
        piso_mem = -1       # bundle del ultimo acceso a memoria
        piso_s3 = -1        # bundle de la ultima operacion de la boveda

        for op in ops:
            minimo = 0

            # Dependencias con lo ya colocado
            for previa in colocadas:
                b = previa.bundle
                # RAW: leo algo que una previa escribio -> latencia completa
                if op.lee & previa.escribe:
                    minimo = max(minimo, b + LATENCIA)
                # WAW: escribo lo mismo que una previa -> despues, y nunca en
                # el mismo bundle, que seria un WCONF
                if op.escribe & previa.escribe:
                    minimo = max(minimo, b + 1)
                # WAR: escribo lo que una previa lee. La lectura ocurre en ID
                # del ciclo b+1 y la escritura en WB del b'+4, asi que basta
                # con no adelantarse; se exige el mismo bundle o posterior.
                if op.escribe & previa.lee:
                    minimo = max(minimo, b)

            # Orden de memoria y de la boveda: no se reordenan entre si
            if op.es_memoria:
                minimo = max(minimo, piso_mem + 1)
            if op.es_boveda:
                minimo = max(minimo, piso_s3 + 1)

            # Un salto va en el ultimo bundle del bloque: no puede quedar
            # ninguna operacion detras, porque pasaria a ser su delay slot
            if op.es_salto:
                minimo = max(minimo, len(bundles) - 1 if bundles else 0)

            # Primer bundle a partir del minimo donde haya ranura libre y no
            # choque ninguna escritura
            b = minimo
            while True:
                asegurar(b)
                hueco = None
                for s in op.slots:
                    if bundles[b][s] is None:
                        hueco = s
                        break
                if hueco is not None and not self._choca_escritura(
                        op, bundles[b], colocadas, b):
                    break
                b += 1

            asegurar(b)
            bundles[b][hueco] = op
            op.bundle = b
            op.slot = hueco
            colocadas.append(op)
            if op.es_memoria:
                piso_mem = b
            if op.es_boveda:
                piso_s3 = b

        # Las escrituras pendientes se dejan asentar antes de cerrar el
        # bloque, para que el bloque siguiente pueda leerlas desde su primer
        # bundle. Es la regla 8 de la cabecera.
        ultima_escritura = -1
        for op in colocadas:
            if op.escribe:
                ultima_escritura = max(ultima_escritura, op.bundle)
        if ultima_escritura >= 0:
            while len(bundles) < ultima_escritura + LATENCIA:
                bundles.append([None] * 5)

        # Un salto deja su delay slot detras, siempre vacio: la v1.2 del ISA
        # prohibe otro salto ahi, y meter una operacion cualquiera exigiria
        # comprobar que da igual que el salto se tome o no
        if colocadas and colocadas[-1].es_salto:
            bundles.append([None] * 5)

        return bundles

    @staticmethod
    def _choca_escritura(op, bundle, colocadas, b):
        """True si meter `op` en este bundle crearia un WCONF."""
        for s, otra in enumerate(bundle):
            if otra is not None and (op.escribe & otra.escribe):
                return True
        return False

    # -- emision ------------------------------------------------------------

    @staticmethod
    def formatear(bundle):
        campos = []
        for i in range(5):
            op = bundle[i]
            campos.append((op.texto if op else "-").ljust(ANCHO_COL[i]))
        return "    " + " | ".join(campos).rstrip() + " ;"

    def empacar(self, renombrar=True):
        piezas = self.leer_bloques()
        salida = []
        antes_b = antes_i = 0
        despues_b = despues_i = 0
        self.renombradas = 0
        libres = self.registros_libres() if renombrar else []
        self.libres = libres

        for tipo, cuerpo in piezas:
            if tipo == "texto":
                salida.extend(cuerpo)
                continue
            if libres:
                self.renombradas += self.renombrar(cuerpo, libres)
            bundles = self.planificar(cuerpo)
            antes_b += len(cuerpo)      # una por bundle, como venia
            antes_i += len(cuerpo)
            despues_b += len(bundles)
            despues_i += len(cuerpo)
            for bu in bundles:
                salida.append(self.formatear(bu))

        self.estad = {
            "bundles_antes": antes_b,
            "bundles_despues": despues_b,
            "instrucciones": antes_i,
        }
        return salida


def contar_ocupacion(lineas):
    """Bundles, instrucciones y uso por ranura de un texto en ensamblador."""
    b = i = multi = 0
    por_slot = [0] * 5
    en_datos = False
    for l in lineas:
        limpia = l.split("//")[0].strip()
        if not limpia:
            continue
        if limpia.startswith(".data"):
            en_datos = True
            continue
        if limpia.startswith(".text"):
            en_datos = False
            continue
        if en_datos or not limpia.endswith(";"):
            continue
        campos = [p.strip() for p in limpia[:-1].split("|")]
        usados = 0
        for s, c in enumerate(campos[:5]):
            if c and c != "-" and c.split()[0].lower() != "nop":
                usados += 1
                por_slot[s] += 1
        b += 1
        i += usados
        if usados > 1:
            multi += 1
    return b, i, multi, por_slot


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Empaqueta operaciones independientes en un mismo bundle")
    ap.add_argument("fuente", help="programa en ensamblador de CERBERO")
    ap.add_argument("-o", "--salida", help="donde escribir el resultado")
    ap.add_argument("--informe", action="store_true",
                    help="solo medir, sin escribir nada")
    args = ap.parse_args(argv)

    emp = Empacador(args.fuente)
    # Se compara contra el fuente YA EXPANDIDO, no contra el archivo en disco:
    # un programa que incluye otros tiene en disco menos bundles de los que de
    # verdad ejecuta, y medir contra el archivo haria parecer que empacar
    # empeora las cosas.
    originales = list(emp.lineas)
    salida = emp.empacar()

    b0, i0, m0, s0 = contar_ocupacion(originales)
    b1, i1, m1, s1 = contar_ocupacion(salida)

    for aviso in emp.avisos:
        print(f"aviso: {aviso}", file=sys.stderr)

    nombre = os.path.basename(args.fuente)
    print(f"{nombre}")
    print(f"  bundles        {b0:>6}  ->{b1:>6}   "
          f"({100 * (b0 - b1) / b0:.0f}% menos)" if b0 else "")
    print(f"  instrucciones  {i0:>6}  ->{i1:>6}")
    if b0 and b1:
        print(f"  por bundle     {i0 / b0:>6.2f}  ->{i1 / b1:>6.2f}   de 5")
        print(f"  con mas de una {m0:>6}  ->{m1:>6}")
    print(f"  por ranura     " + "  ".join(
        f"{NOMBRE_SLOT[k]}:{s1[k]}" for k in range(5)))

    if args.informe:
        return 0

    destino = args.salida
    if not destino:
        raiz, ext = os.path.splitext(args.fuente)
        destino = f"{raiz}_empacado{ext}"
    with open(destino, "w", encoding="utf-8") as f:
        f.write("\n".join(salida) + "\n")
    print(f"  escrito en     {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
