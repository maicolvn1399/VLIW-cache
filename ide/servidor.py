#!/usr/bin/env python3
"""
Servidor de la interfaz del IDE de Nova.

La division de responsabilidades que pide el proyecto es estricta: toda la
logica que entiende el lenguaje esta en C, dentro de 'novaide', y este
servidor no sabe nada de Nova. Lo unico que hace es recibir lo que el editor
del navegador tiene en pantalla, pasarselo a 'novaide' y devolver su
respuesta tal cual. Si algo del analisis hay que cambiarlo, se cambia en C;
aqui no hay reglas del lenguaje que puedan quedar desincronizadas.

Cada peticion escribe el contenido del editor en un archivo temporal y lanza
'novaide' sobre el. Eso permite analizar lo que el usuario esta escribiendo
sin obligarlo a guardar, y mantiene al nucleo trabajando siempre sobre un
archivo real, igual que el compilador.

Uso:
    python3 ide/servidor.py [--puerto 8099] [--raiz .]
"""

import argparse
import glob
import http.server
import json
import os
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import webbrowser

AQUI = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(AQUI, "web")

# Limite de tiempo por invocacion. El analisis de un archivo normal tarda
# milisegundos; este tope solo existe para que un caso patologico no deje la
# interfaz colgada esperando.
TIEMPO_LIMITE = 20
TIEMPO_LIMITE_RTL = 60
DMEM_WORDS = 16384


def leer_metricas(texto):
    """Interpreta el formato comparativo producido por novac --metricas."""
    secciones = re.split(r"^\s*(ANTES|DESPUES)\s*$", texto, flags=re.MULTILINE)
    if len(secciones) < 5:
        return None

    def bloque_metricas(bloque):
        patrones = {
            "tac": r"instrucciones TAC:\s*(\d+)",
            "instrucciones": r"instrucciones finales no-NOP:\s*(\d+)",
            "bundles": r"bundles:\s*(\d+)",
            "bytes": r"bytes de codigo:\s*(\d+)",
            "ocupacion_pct": r"ocupacion:\s*([\d.]+)%",
            "dependencias_war": r"dependencias WAR:\s*(\d+)",
            "dependencias_waw": r"dependencias WAW:\s*(\d+)",
            "nops_war": r"NOPs por dependencia WAR:\s*(\d+)",
            "nops_waw": r"NOPs por dependencia WAW:\s*(\d+)",
        }
        valores = {}
        for clave, patron in patrones.items():
            m = re.search(patron, bloque)
            if m is None:
                return None
            valores[clave] = float(m.group(1)) if clave == "ocupacion_pct" else int(m.group(1))
        return valores

    antes = bloque_metricas(secciones[2])
    despues = bloque_metricas(secciones[4])
    if antes is None or despues is None:
        return None

    tiempos = {}
    for clave, patron in {
        "fase_1_2": r"tiempo fase 1-2 \(lexico/sintactico\):\s*([\d.]+)",
        "fase_3": r"tiempo fase 3 \(semantica/enlace\):\s*([\d.]+)",
        "fase_4_tac": r"tiempo fase 4 \(generacion TAC\):\s*([\d.]+)",
        "fase_4_backend": r"tiempo fase 4 \(backend VLIW\):\s*([\d.]+)",
        "fase_6": r"tiempo fase 6 \(optimizacion\):\s*([\d.]+)",
        "total": r"tiempo total de compilacion:\s*([\d.]+)",
    }.items():
        m = re.search(patron, texto)
        if m is None:
            return None
        tiempos[clave] = float(m.group(1))

    contadores = {}
    for clave, patron in {
        "eliminadas": r"^\s*eliminadas:\s*(\d+)",
        "reordenadas": r"^\s*reordenadas:\s*(\d+)",
        "renombradas": r"^\s*renombradas:\s*(\d+)",
        "temporales_asignados_registro":
            r"^\s*temporales asignados a registro:\s*(\d+)",
        "derramadas": r"^\s*derramadas:\s*(\d+)",
        "bucles": r"^\s*bucles desenrollados:\s*(\d+)",
    }.items():
        encontrados = re.findall(patron, texto, flags=re.MULTILINE)
        if not encontrados:
            return None
        contadores[clave] = int(encontrados[-1])

    def simulacion_ciclos(etiqueta):
        m = re.search(
            rf"^\s*{etiqueta}: ciclos estimados=(\d+); "
            r"bundles ejecutados=(\d+); instrucciones no-NOP=(\d+); "
            r"IPC estimado=([\d.]+)$",
            texto, flags=re.MULTILINE,
        )
        if m is not None:
            return {
                "disponible": True,
                "ciclos": int(m.group(1)),
                "bundles": int(m.group(2)),
                "instrucciones": int(m.group(3)),
                "ipc": float(m.group(4)),
            }
        m = re.search(
            rf"^\s*{etiqueta}: no soportado: (.+)$",
            texto, flags=re.MULTILINE,
        )
        if m is not None:
            return {"disponible": False, "motivo": m.group(1)}
        return None

    return {
        "antes": antes,
        "despues": despues,
        "tiempos_ms": tiempos,
        "contadores": contadores,
        "ciclos_estimados": {
            # No es -O0: es el TAC previo a la fase 6 pasado por el mismo
            # backend que la corrida actual. Ver el comentario en main.c.
            "antes": simulacion_ciclos(r"ANTES \(sin fase 6, mismo backend\)"),
            "despues": simulacion_ciclos(r"DESPUES \(-O[012]\)"),
        },
    }


class Nucleo:
    """Envoltura de los binarios en C."""

    def __init__(self, raiz):
        self.raiz = os.path.abspath(raiz)
        self.novaide = os.path.join(self.raiz, "novaide")
        self.novac = os.path.join(self.raiz, "novac")

    def disponible(self):
        return os.path.isfile(self.novaide) and os.access(self.novaide, os.X_OK)

    def ejecutar(self, argumentos):
        """Corre novaide y devuelve su JSON ya interpretado."""
        try:
            r = subprocess.run(
                [self.novaide] + argumentos,
                capture_output=True, text=True,
                timeout=TIEMPO_LIMITE, cwd=self.raiz,
            )
        except subprocess.TimeoutExpired:
            return {"error": "el analisis excedio el tiempo limite"}
        except OSError as e:
            return {"error": f"no se pudo ejecutar novaide: {e}"}

        if not r.stdout.strip():
            return {"error": "novaide no produjo salida", "stderr": r.stderr[-2000:]}
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError as e:
            return {"error": f"respuesta de novaide ilegible: {e}",
                    "crudo": r.stdout[:2000]}

    @staticmethod
    def leer_volcado_dmem(ruta):
        palabras = []
        with open(ruta, encoding="ascii") as archivo:
            for indice, linea in enumerate(archivo):
                coincidencia = re.fullmatch(
                    r"([0-9a-fA-F]{8})\s+([0-9a-fA-FxXzZ]{8})",
                    linea.strip(),
                )
                if coincidencia is None:
                    raise ValueError(
                        f"formato invalido en la linea {indice + 1} del volcado"
                    )

                direccion = int(coincidencia.group(1), 16)
                if direccion != indice * 4:
                    raise ValueError(
                        f"direccion inesperada en la linea {indice + 1}: "
                        f"0x{direccion:04X}"
                    )
                valor = coincidencia.group(2).upper()
                palabras.append({
                    "direccion": f"0x{direccion:04X}",
                    "valor": f"0x{valor}",
                    "no_cero": valor != "00000000",
                })

        if len(palabras) != DMEM_WORDS:
            raise ValueError(
                f"el volcado contiene {len(palabras)} palabras; "
                f"se esperaban {DMEM_WORDS}"
            )
        return palabras

    def medir_ciclos_rtl(self, ruta, nivel_opt, incluir_dmem=False):
        """Mide el fuente en el RTL y compara su resultado con -O0."""
        iverilog = shutil.which("iverilog")
        vvp = shutil.which("vvp")
        if not iverilog or not vvp:
            return {
                "disponible": False,
                "motivo": "se requieren iverilog y vvp para medir ciclos RTL",
            }

        cpu = os.path.join(self.raiz, "ARQUITECTURA", "src", "cpu")
        if not os.path.isdir(cpu):
            cpu = os.path.abspath(os.path.join(self.raiz, "..", "src", "cpu"))
        fuentes_rtl = sorted(glob.glob(os.path.join(cpu, "*.sv")))
        testbench = os.path.join(self.raiz, "test", "tb_nova_rtl.sv")
        conversor = os.path.join(
            self.raiz, "ARQUITECTURA", "tools", "novac_image.py")
        if not fuentes_rtl or not os.path.isfile(testbench) or \
                not os.path.isfile(conversor):
            return {
                "disponible": False,
                "motivo": "no se encontro el RTL, el testbench o el conversor de imagen",
            }

        niveles = [0] if nivel_opt == 0 else [0, nivel_opt]
        resultados = {}
        advertencias = []
        try:
            with tempfile.TemporaryDirectory(prefix="nova_metricas_rtl_") as tmp:
                for nivel in niveles:
                    prefijo = "antes" if nivel == 0 else "despues"
                    ejecutable = os.path.join(tmp, f"{prefijo}.nvx")
                    imem = os.path.join(tmp, f"{prefijo}.imem.hex")
                    dmem = os.path.join(tmp, f"{prefijo}.dmem.hex")
                    simulacion = os.path.join(tmp, f"{prefijo}.vvp")
                    volcado_dmem = (
                        os.path.join(tmp, "dmem-final.txt")
                        if incluir_dmem and nivel == nivel_opt else None
                    )

                    compilado = subprocess.run(
                        [self.novac, f"-O{nivel}", ruta, "-o", ejecutable],
                        capture_output=True, text=True, timeout=TIEMPO_LIMITE,
                        cwd=self.raiz,
                    )
                    if compilado.stderr.strip():
                        advertencias.append(compilado.stderr.strip())
                    if compilado.returncode != 0:
                        return {
                            "disponible": False,
                            "motivo": f"no se pudo generar el binario -O{nivel}: "
                                      f"{compilado.stderr[-1000:]}",
                        }

                    convertido = subprocess.run(
                        [sys.executable, conversor, ejecutable,
                         "--imem", imem, "--dmem", dmem],
                        capture_output=True, text=True, timeout=TIEMPO_LIMITE,
                        cwd=self.raiz,
                    )
                    if convertido.stderr.strip():
                        advertencias.append(convertido.stderr.strip())
                    if convertido.returncode != 0:
                        return {
                            "disponible": False,
                            "motivo": f"no se pudieron generar las imagenes RTL: "
                                      f"{convertido.stderr[-1000:]}",
                        }

                    argumentos = [
                        iverilog, "-g2012", "-Wall", "-Wno-timescale",
                        "-I", cpu, "-DCERBERO_MAX_CYCLES=200000",
                        f'-DCERBERO_IMEM_FILE="{imem}"',
                        f'-DCERBERO_DMEM_FILE="{dmem}"',
                        "-s", "tb_nova_rtl", "-o", simulacion,
                    ] + fuentes_rtl + [testbench]
                    compilacion_rtl = subprocess.run(
                        argumentos, capture_output=True, text=True,
                        timeout=TIEMPO_LIMITE_RTL, cwd=self.raiz,
                    )
                    if compilacion_rtl.stderr.strip():
                        advertencias.append(compilacion_rtl.stderr.strip())
                    if compilacion_rtl.returncode != 0:
                        return {
                            "disponible": False,
                            "motivo": f"iverilog no pudo compilar el testbench: "
                                      f"{compilacion_rtl.stderr[-1000:]}",
                            "advertencias": advertencias,
                        }

                    argumentos_vvp = [
                        vvp, "-n", simulacion,
                        "+OMITIR_VERIFICACION_RETORNO",
                    ]
                    if volcado_dmem is not None:
                        argumentos_vvp.append(f"+DMEM_DUMP={volcado_dmem}")
                    corrida = subprocess.run(
                        argumentos_vvp,
                        capture_output=True, text=True,
                        timeout=TIEMPO_LIMITE_RTL, cwd=self.raiz,
                    )
                    if corrida.stderr.strip():
                        advertencias.append(corrida.stderr.strip())
                    if corrida.returncode != 0:
                        return {
                            "disponible": False,
                            "motivo": f"la simulacion -O{nivel} fallo: "
                                      f"{(corrida.stderr or corrida.stdout)[-1000:]}",
                            "advertencias": advertencias,
                        }

                    def entero(patron):
                        coincidencia = re.search(patron, corrida.stdout)
                        return int(coincidencia.group(1)) if coincidencia else None

                    ciclos = entero(r"ciclos RTL:\s*(\d+)")
                    instrucciones = entero(r"instrucciones RTL:\s*(\d+)")
                    retorno = entero(r"retorno R6:\s*(-?\d+)")
                    conteo_salida = entero(
                        r"salida en DMEM del procesador \((\d+) valores\):")
                    salida = [
                        int(valor) for valor in re.findall(
                            r"^\s+\[\d+\]\s+(-?\d+)\s+\(",
                            corrida.stdout, flags=re.MULTILINE,
                        )
                    ]
                    if ciclos is None or instrucciones is None or \
                            retorno is None or conteo_salida is None or \
                            len(salida) != conteo_salida or ciclos <= 0:
                        return {
                            "disponible": False,
                            "motivo": f"la simulacion -O{nivel} no produjo "
                                      "contadores RTL completos",
                            "advertencias": advertencias,
                        }
                    resultados_nivel = {
                        "ciclos": ciclos,
                        "instrucciones": instrucciones,
                        "ipc": round(instrucciones / ciclos, 3),
                        "retorno": retorno,
                        "salida": salida,
                    }
                    if volcado_dmem is not None:
                        try:
                            resultados_nivel["dmem"] = self.leer_volcado_dmem(
                                volcado_dmem
                            )
                        except (OSError, ValueError) as e:
                            return {
                                "disponible": False,
                                "motivo": f"no se pudo leer el volcado DMEM: {e}",
                                "advertencias": advertencias,
                            }
                    resultados[prefijo] = resultados_nivel
        except subprocess.TimeoutExpired as e:
            return {
                "disponible": False,
                "motivo": f"la medicion RTL excedio el tiempo limite: {e.cmd}",
                "advertencias": advertencias,
            }
        except OSError as e:
            return {
                "disponible": False,
                "motivo": f"no se pudo ejecutar la medicion RTL: {e}",
                "advertencias": advertencias,
            }

        antes = resultados["antes"]
        despues = resultados.get("despues", antes)
        if (antes["retorno"], antes["salida"]) != \
                (despues["retorno"], despues["salida"]):
            return {
                "disponible": False,
                "motivo": "la ejecucion optimizada difiere de -O0 en R6 o en "
                          "la salida de scribe",
                "antes": antes,
                "despues": despues,
                "advertencias": advertencias,
            }
        respuesta = {
            "disponible": True,
            "origen": "medido",
            "antes": antes,
            "despues": despues,
            "advertencias": advertencias,
        }
        if incluir_dmem:
            lado = "antes" if nivel_opt == 0 else "despues"
            if "dmem" not in resultados[lado]:
                return {
                    "disponible": False,
                    "motivo": "la simulacion no produjo el volcado DMEM",
                    "advertencias": advertencias,
                }
            respuesta["dmem"] = resultados[lado]["dmem"]
        return respuesta

    def ejecutar_rtl(self, ruta, nivel_opt):
        """Ejecuta el nivel elegido y devuelve salida y DMEM final."""
        if nivel_opt not in (0, 1, 2):
            return {"error": "nivel de optimizacion invalido; use 0, 1 o 2"}

        medicion = self.medir_ciclos_rtl(
            ruta, nivel_opt, incluir_dmem=True
        )
        if not medicion.get("disponible"):
            return {
                "error": medicion.get("motivo", "ejecucion RTL no disponible"),
                "advertencias": medicion.get("advertencias", []),
            }

        lado = "antes" if nivel_opt == 0 else "despues"
        resultado = medicion[lado]
        return {
            "nivel_opt": nivel_opt,
            "comparado_con_o0": nivel_opt != 0,
            "retorno": resultado["retorno"],
            "scribe": resultado["salida"],
            "ciclos": resultado["ciclos"],
            "instrucciones": resultado["instrucciones"],
            "ipc": resultado["ipc"],
            "dmem": medicion["dmem"],
        }

    def compilar(self, ruta, modo, nivel_opt=0):
        """
        Corre el compilador de verdad sobre el archivo. Es lo que hace el boton
        de compilar: el IDE no simula la compilacion, la ejecuta.

        'nivel_opt' selecciona -O0, -O1 o -O2. El modo de metricas agrega
        tambien el calendario del mismo nivel para el panel comparativo.
        """
        banderas = {
            "binario": [],
            "tokens": ["--tokens"],
            "ast": ["-t"],
            "simbolos": ["--sym"],
            "ir": ["--ir"],
            "vivacidad": ["--vivacidad"],
            "metricas": ["--metricas"],
            "ensamblador": ["-s"],
            "paquetes": ["-p"],
        }.get(modo, [])

        if nivel_opt:
            banderas = banderas + [f"-O{nivel_opt}"]

        salida = None
        argumentos = [self.novac] + banderas + [ruta]

        # Ojo con -o: varias banderas de inspeccion lo interpretan como "manda
        # el reporte a ese archivo" en vez de a la pantalla. '-p' es una de
        # ellas, asi que pasarle -o dejaba el panel de Salida en blanco con el
        # listado de bundles escondido en un archivo. Solo lo reciben los modos
        # que de verdad producen un binario.
        # --metricas necesita que se genere el binario para poder contar los
        # bundles, pero su reporte sale por pantalla, asi que tambien lleva -o.
        if modo in ("binario", "ensamblador", "metricas"):
            salida = ruta + ".nvx"
            argumentos += ["-o", salida]

        inicio = time.perf_counter()
        try:
            r = subprocess.run(argumentos, capture_output=True, text=True,
                               timeout=TIEMPO_LIMITE, cwd=self.raiz)
        except subprocess.TimeoutExpired:
            return {"error": "la compilacion excedio el tiempo limite"}
        except OSError as e:
            return {"error": f"no se pudo ejecutar novac: {e}"}
        transcurrido = time.perf_counter() - inicio

        metricas = None
        calendario = None
        if r.returncode == 0:
            metricas_texto = r.stdout
            ruta_metricas = None
            if modo != "metricas":
                ruta_metricas = ruta + ".metricas.nvx"
                args_metricas = [self.novac, "--metricas"]
                if nivel_opt:
                    args_metricas.append(f"-O{nivel_opt}")
                args_metricas.extend([ruta, "-o", ruta_metricas])
                try:
                    r_metricas = subprocess.run(
                        args_metricas, capture_output=True, text=True,
                        timeout=TIEMPO_LIMITE, cwd=self.raiz,
                    )
                except subprocess.TimeoutExpired:
                    return {"error": "la medicion de metricas excedio el tiempo limite"}
                except OSError as e:
                    return {"error": f"no se pudieron medir las metricas: {e}"}
                if r_metricas.returncode != 0:
                    return {
                        "error": "novac no pudo generar las metricas comparativas",
                        "errores": r_metricas.stderr,
                        "salida": r_metricas.stdout,
                    }
                metricas_texto = r_metricas.stdout
                try:
                    for extra in (ruta_metricas,
                                  os.path.splitext(ruta_metricas)[0] + ".asm"):
                        if os.path.isfile(extra):
                            os.remove(extra)
                except OSError as e:
                    return {"error": f"no se pudo limpiar la salida de metricas: {e}"}

            metricas = leer_metricas(metricas_texto)
            if metricas is None:
                return {
                    "error": "novac --metricas produjo un reporte incompleto",
                    "salida": metricas_texto,
                    "errores": r.stderr,
                }
            if modo == "metricas":
                ciclos = self.medir_ciclos_rtl(ruta, nivel_opt)
                if not ciclos.get("disponible") and \
                        ciclos.get("motivo", "").startswith(
                            "se requieren iverilog y vvp"):
                    estimados = metricas.get("ciclos_estimados", {})
                    antes = estimados.get("antes")
                    despues = estimados.get("despues")
                    if antes and despues and antes.get("disponible") and \
                            despues.get("disponible"):
                        ciclos = {
                            "disponible": True,
                            "origen": "estimado",
                            "antes": {
                                clave: antes[clave]
                                for clave in ("ciclos", "bundles",
                                              "instrucciones", "ipc")
                            },
                            "despues": {
                                clave: despues[clave]
                                for clave in ("ciclos", "bundles",
                                              "instrucciones", "ipc")
                            },
                        }
                    else:
                        motivos = [
                            valor.get("motivo", "estimacion no disponible")
                            for valor in (antes, despues)
                            if valor and not valor.get("disponible")
                        ]
                        if not motivos:
                            motivos.append("estimacion C no disponible")
                        ciclos = {
                            "disponible": False,
                            "origen": "estimado",
                            "motivo": "simulador C: no soportado: " +
                                      "; ".join(motivos),
                        }
                metricas["ciclos_rtl"] = ciclos
            try:
                r_cal = subprocess.run(
                    [self.novac, "--calendario", f"-O{nivel_opt}", ruta],
                    capture_output=True, text=True, timeout=TIEMPO_LIMITE,
                    cwd=self.raiz,
                )
            except subprocess.TimeoutExpired:
                return {"error": "la generacion del calendario excedio el tiempo limite"}
            except OSError as e:
                return {"error": f"no se pudo generar el calendario: {e}"}
            if r_cal.returncode != 0:
                return {
                    "error": "novac no pudo generar el calendario",
                    "errores": r_cal.stderr,
                    "salida": r_cal.stdout,
                }
            calendario = r_cal.stdout

        tamano = None
        if salida and os.path.isfile(salida):
            tamano = os.path.getsize(salida)
            try:
                os.remove(salida)
                for extra in (".asm",):
                    otro = os.path.splitext(salida)[0] + extra
                    if os.path.isfile(otro):
                        os.remove(otro)
            except OSError:
                pass

        return {
            "modo": modo,
            "codigo_salida": r.returncode,
            "salida": r.stdout,
            "errores": r.stderr,
            # El tiempo de compilacion es una de las metricas que el proyecto
            # pide registrar; se mide aqui para poder graficarla despues.
            "milisegundos": round(transcurrido * 1000, 2),
            "bytes_generados": tamano,
            "metricas": metricas,
            "calendario": calendario,
        }


class Taller:
    """Archivos temporales donde se materializa el buffer del editor."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="nova_ide_")

    def escribir(self, nombre, contenido):
        base = os.path.basename(nombre or "sin_titulo.nv")
        if not base.endswith((".nv", ".nvo")):
            base += ".nv"
        ruta = os.path.join(self.dir, base)
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(contenido)
        return ruta

    def limpiar(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class Manejador(http.server.SimpleHTTPRequestHandler):
    nucleo = None
    taller = None
    raiz_proyecto = None

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WEB, **kw)

    # El log por omision ensucia la terminal con una linea por recurso.
    def log_message(self, formato, *args):
        pass

    # ------------------------------------------------------------ utiles

    def responder_json(self, datos, estado=200):
        cuerpo = json.dumps(datos, ensure_ascii=False).encode("utf-8")
        self.send_response(estado)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(cuerpo)

    def leer_peticion(self):
        largo = int(self.headers.get("Content-Length", 0))
        if largo <= 0:
            return {}
        if largo > 20 * 1024 * 1024:
            return {}
        return json.loads(self.rfile.read(largo).decode("utf-8"))

    def ruta_segura(self, relativa):
        """
        Impide salir del arbol del proyecto. El servidor escucha solo en
        localhost, pero una interfaz que lee archivos por nombre no deberia
        poder alcanzar cualquier cosa del disco ni por error.
        """
        destino = os.path.abspath(os.path.join(self.raiz_proyecto, relativa))
        if not destino.startswith(self.raiz_proyecto + os.sep):
            return None
        return destino

    # ------------------------------------------------------------- GET

    def do_GET(self):
        if self.path.startswith("/api/"):
            if self.path == "/api/estado":
                return self.responder_json({
                    "nucleo": self.nucleo.disponible(),
                    "raiz": self.raiz_proyecto,
                    "novaide": self.nucleo.novaide,
                })
            if self.path == "/api/catalogo":
                return self.responder_json(self.nucleo.ejecutar(["catalogo"]))
            if self.path == "/api/archivos":
                return self.responder_json({"archivos": self.listar_fuentes()})
            if self.path.startswith("/api/archivo?"):
                relativa = urllib.parse.unquote(self.path.split("ruta=", 1)[-1])
                destino = self.ruta_segura(relativa)
                if destino is None or not os.path.isfile(destino):
                    return self.responder_json({"error": "archivo no encontrado"}, 404)
                with open(destino, encoding="utf-8", errors="replace") as f:
                    return self.responder_json({"nombre": relativa, "contenido": f.read()})
            return self.responder_json({"error": "ruta desconocida"}, 404)
        return super().do_GET()

    def listar_fuentes(self):
        """Todos los .nv del proyecto, para el panel de archivos."""
        encontrados = []
        omitir = {".git", "ARQUITECTURA", "__pycache__", "entregables"}
        for base, dirs, archivos in os.walk(self.raiz_proyecto):
            dirs[:] = [d for d in dirs if d not in omitir and not d.startswith(".")]
            for a in archivos:
                if a.endswith(".nv"):
                    completo = os.path.join(base, a)
                    encontrados.append(os.path.relpath(completo, self.raiz_proyecto))
            if len(encontrados) > 500:
                break
        return sorted(encontrados)

    # ------------------------------------------------------------ POST

    def do_POST(self):
        if not self.path.startswith("/api/"):
            return self.responder_json({"error": "ruta desconocida"}, 404)
        try:
            peticion = self.leer_peticion()
        except (ValueError, UnicodeDecodeError) as e:
            return self.responder_json({"error": f"peticion ilegible: {e}"}, 400)

        accion = self.path[len("/api/"):]
        try:
            if accion == "diagnosticar":
                return self.responder_json(self.hacer_diagnosticar(peticion))
            if accion == "completar":
                return self.responder_json(self.hacer_completar(peticion))
            if accion == "arreglar":
                return self.responder_json(self.hacer_arreglar(peticion))
            if accion == "bloques":
                return self.responder_json(self.hacer_bloques(peticion))
            if accion == "clones":
                return self.responder_json(self.hacer_clones(peticion))
            if accion == "compilar":
                return self.responder_json(self.hacer_compilar(peticion))
            if accion == "ejecutar_rtl":
                return self.responder_json(self.hacer_ejecutar_rtl(peticion))
            if accion == "guardar":
                return self.responder_json(self.hacer_guardar(peticion))
        except Exception as e:                       # noqa: BLE001
            return self.responder_json({"error": f"{type(e).__name__}: {e}"}, 500)
        return self.responder_json({"error": "accion desconocida"}, 404)

    def hacer_diagnosticar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["diagnosticar", ruta, "--con-tokens", "--como", nombre])

    def hacer_completar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar([
            "completar", ruta,
            "--linea", str(int(p.get("linea", 1))),
            "--columna", str(int(p.get("columna", 1))),
            "--como", nombre,
        ])

    def hacer_arreglar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["arreglar", ruta, "--como", nombre])

    def hacer_bloques(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["bloques", ruta, "--como", nombre])

    def hacer_clones(self, p):
        """
        Los clones se buscan entre varios archivos a la vez: los abiertos en el
        editor, con su contenido actual, mas los que el usuario haya marcado
        del proyecto.
        """
        rutas, mostrar = [], {}
        for archivo in p.get("archivos", [])[:64]:
            nombre = archivo.get("nombre", "sin_titulo.nv")
            ruta = self.taller.escribir(nombre, archivo.get("contenido", ""))
            rutas.append(ruta)
            mostrar[ruta] = nombre

        if len(rutas) < 1:
            return {"error": "no hay archivos que comparar"}

        argumentos = ["clones"] + rutas
        argumentos += ["--min-tokens", str(int(p.get("min_tokens", 20)))]
        argumentos += ["--umbral", str(float(p.get("umbral", 0.80)))]
        resultado = self.nucleo.ejecutar(argumentos)

        # Devolver los nombres que el usuario reconoce, no los temporales.
        def nombrar(r):
            return mostrar.get(r, os.path.basename(r))

        if "archivos" in resultado:
            resultado["archivos"] = [nombrar(r) for r in resultado["archivos"]]
        for c in resultado.get("clones", []):
            for lado in ("a", "b"):
                c[lado]["archivo"] = nombrar(c[lado]["archivo"])
        return resultado

    def hacer_compilar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        nivel = p.get("nivel_opt", 1 if p.get("optimizar", False) else 0)
        try:
            nivel = int(nivel)
        except (TypeError, ValueError):
            return {"error": "nivel de optimizacion invalido; use 0, 1 o 2"}
        if nivel not in (0, 1, 2):
            return {"error": "nivel de optimizacion invalido; use 0, 1 o 2"}
        return self.nucleo.compilar(ruta, p.get("modo", "binario"), nivel)

    def hacer_ejecutar_rtl(self, p):
        nombre = p.get("nombre", "editor.nv")
        try:
            nivel = int(p.get("nivel_opt", 0))
        except (TypeError, ValueError):
            return {"error": "nivel de optimizacion invalido; use 0, 1 o 2"}
        if nivel not in (0, 1, 2):
            return {"error": "nivel de optimizacion invalido; use 0, 1 o 2"}
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar_rtl(ruta, nivel)

    def hacer_guardar(self, p):
        destino = self.ruta_segura(p.get("nombre", ""))
        if destino is None:
            return {"error": "ruta fuera del proyecto"}
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, "w", encoding="utf-8") as f:
            f.write(p.get("contenido", ""))
        return {"guardado": os.path.relpath(destino, self.raiz_proyecto)}


class Servidor(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def abrir_navegador(direccion):
    """
    Abre la interfaz en el navegador.

    Bajo WSL no hay navegador dentro de Linux: el que importa es el de
    Windows. webbrowser.open() intenta 'gio open', que no existe ahi, y lo
    unico que logra es imprimir un error en la terminal justo cuando el
    servidor acaba de arrancar bien. Por eso en WSL se prueban primero las dos
    formas que si funcionan, y en cualquier caso el fallo es silencioso: la
    direccion ya quedo impresa arriba y abrirla a mano siempre sirve.
    """
    es_wsl = False
    try:
        with open("/proc/version", encoding="utf-8", errors="replace") as f:
            es_wsl = "microsoft" in f.read().lower()
    except OSError:
        pass

    if es_wsl:
        for orden in (["wslview", direccion],
                      ["cmd.exe", "/c", "start", "", direccion]):
            try:
                subprocess.run(orden, check=True, timeout=10,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except (OSError, subprocess.SubprocessError):
                continue
        return

    try:
        webbrowser.open(direccion)
    except Exception:                                # noqa: BLE001
        pass


def main():
    ap = argparse.ArgumentParser(description="Interfaz del IDE de Nova")
    ap.add_argument("--puerto", type=int, default=8099)
    ap.add_argument("--raiz", default=os.path.dirname(AQUI),
                    help="raiz del proyecto, donde estan novac y novaide")
    ap.add_argument("--sin-navegador", action="store_true")
    args = ap.parse_args()

    raiz = os.path.abspath(args.raiz)
    nucleo = Nucleo(raiz)
    if not nucleo.disponible():
        print(f"No se encontro '{nucleo.novaide}'.", file=sys.stderr)
        print("Compile primero el nucleo del IDE con:  make novaide", file=sys.stderr)
        return 1

    Manejador.nucleo = nucleo
    Manejador.taller = Taller()
    Manejador.raiz_proyecto = raiz

    direccion = f"http://127.0.0.1:{args.puerto}/"
    print("IDE de Nova")
    print(f"  proyecto : {raiz}")
    print(f"  nucleo   : {nucleo.novaide}")
    print(f"  interfaz : {direccion}")
    print("  (Ctrl+C para detener)")

    if not args.sin_navegador:
        threading.Timer(0.6, lambda: abrir_navegador(direccion)).start()

    try:
        with Servidor(("127.0.0.1", args.puerto), Manejador) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
    finally:
        Manejador.taller.limpiar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
